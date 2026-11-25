#!/usr/bin/env node
// One-command generate -> train -> validate -> publish for the synthetic corpus.
// Exemplary memory is sized to the number of training records, limited only by
// available memory/disk rather than a fixed 256-slot cap.
import { spawn } from 'node:child_process';
import { open as openFile, readFile, readdir, rename, symlink, unlink, stat, statfs, readlink, lstat } from 'node:fs/promises';
import path from 'node:path';
import { freemem } from 'node:os';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const directory = path.join(root, 'ai/noema-training');
const node = process.execPath;
const lir = process.env.LIR_BIN || path.join(root, 'zig-out/bin/lir');
const lockPath = path.join(directory, 'pretrain_large.lock');
const alias = path.join(directory, 'pretrain_large_latest.nps');
const tmpCheckpoint = '/tmp/noema_pretrain_dataset.nps';
const candidateAlias = '/tmp/noema_pretrain_candidate.nps';
const samplePath = '/tmp/noema_pretrain_samples.jsonl';
const expectedRecords = Number(process.env.RECORDS || 4096);
const recordBytes = Number(process.env.RECORD_BYTES || 1_000_000);
if (!Number.isSafeInteger(expectedRecords) || expectedRecords < 1 ||
    !Number.isSafeInteger(recordBytes) || recordBytes < 1024 ||
    !Number.isSafeInteger(expectedRecords * recordBytes)) {
  throw new Error('RECORDS and RECORD_BYTES must be positive safe integers (record size at least 1024 bytes)');
}

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: root, stdio: ['pipe', 'pipe', 'pipe'], ...options });
    let stdout = '', stderr = '';
    child.stdout.setEncoding('utf8'); child.stderr.setEncoding('utf8');
    child.stdout.on('data', x => { stdout += x; });
    child.stderr.on('data', x => { stderr = (stderr + x).slice(-10000); });
    child.on('error', reject);
    child.on('close', code => code === 0 ? resolve(stdout) : reject(new Error(stderr.trim() || stdout.trim() || `${command} exited ${code}`)));
    if (options.input !== undefined) child.stdin.end(options.input);
    else child.stdin.end();
  });
}
async function syncPath(filePath) {
  const h = await openFile(filePath, 'r');
  try { await h.sync(); } finally { await h.close(); }
}
async function syncDirectory() {
  const h = await openFile(directory, 'r');
  try { await h.sync(); } finally { await h.close(); }
}
function parseMetrics(output) {
  const lines = output.trim().split(/\r?\n/);
  if (lines.shift() !== 'NOEMA_RESULT_V2') throw new Error(`unexpected LIR output: ${output.slice(0,200)}`);
  const fields = Object.fromEntries(lines.map(line => {
    const i = line.indexOf('='); return i < 0 ? [line, ''] : [line.slice(0, i), line.slice(i + 1)];
  }));
  if (fields.ok !== '1') throw new Error(fields.error || 'model inference failed');
  const bytes = Buffer.from(fields.generated_hex || '', 'hex');
  return { fields, answer: bytes.toString('utf8') };
}
async function infer(prompt, model = 'candidate') {
  const output = await run(lir, ['run', 'ai/chat_site_backend.lir', '--backend=native'], { input: `${model}\n${prompt}` });
  return parseMetrics(output);
}
function question(sample) {
  const at = sample.indexOf(' Yanıt:');
  return at < 0 ? sample : sample.slice(0, at).replace(/^Soru:\s*/, '').trim();
}
async function replaceAlias(targetName) {
  const tmp = `${alias}.${process.pid}.tmp`;
  await unlink(tmp).catch(() => {});
  await symlink(targetName, tmp);
  await rename(tmp, alias);
  await syncDirectory();
}

let lock;
let candidate;
let destinationPath = null;
let destinationCreated = false;
let oldAlias = null;
let switched = false;
try {
  lock = await openFile(lockPath, 'wx', 0o600);
  await lock.writeFile(`${process.pid}\n`); await lock.sync();
  let aliasInfo = null;
  try { aliasInfo = await lstat(alias); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (aliasInfo) {
    if (!aliasInfo.isSymbolicLink()) throw new Error('refusing to replace pretrain_large_latest.nps because it is not a symlink');
    oldAlias = await readlink(alias);
    await stat(alias); // reject a dangling prior alias rather than hiding it
  }
  await unlink(tmpCheckpoint).catch(() => {});
  await unlink(candidateAlias).catch(() => {});
  const fs = await statfs(directory);
  const availableBytes = BigInt(fs.bavail) * BigInt(fs.bsize);
  const payloadBytes = BigInt(expectedRecords) * BigInt(recordBytes);
  const exemplarBytes = BigInt(expectedRecords) * 8192n;
  const reserveBytes = 64n * 1024n * 1024n;
  const requiredBytes = payloadBytes * 2n + payloadBytes / 10n + exemplarBytes + reserveBytes;
  if (availableBytes < requiredBytes) {
    throw new Error(`insufficient disk space: need about ${requiredBytes} bytes, have ${availableBytes}`);
  }
  const availableMemory = BigInt(freemem());
  const requiredMemory = exemplarBytes + BigInt(recordBytes) * 2n + 128n * 1024n * 1024n;
  if (availableMemory < requiredMemory) {
    throw new Error(`insufficient memory for planned exemplar state: need about ${requiredMemory} bytes, have ${availableMemory}`);
  }
  console.log(`Preflight: records=${expectedRecords} record_bytes=${recordBytes} free_disk_bytes=${availableBytes} free_ram_bytes=${availableMemory}`);
  console.log(`Generating full deterministic Turkish synthetic corpus (${expectedRecords} records)...`);
  console.log(await run(node, [path.join(here, 'build_synthetic_pretrain.mjs')]));
  console.log('Training every .nbin record with adaptive macro budget and memory sized from record count...');
  const trainingOutput = await run(lir, ['run', 'ai/train_synthetic_pretrain.lir', '--backend=native']);
  console.log(trainingOutput);
  const trainingMetrics = Object.fromEntries(trainingOutput.trim().split(/\r?\n/).map(line => {
    const i = line.indexOf('='); return i < 0 ? [line, ''] : [line.slice(0, i), line.slice(i + 1)];
  }));
  const macroMean = Number(trainingMetrics.auto_macro_mean);
  if (Number(trainingMetrics.trained_records) !== expectedRecords ||
      Number(trainingMetrics.auto_macro_records) !== expectedRecords ||
      Number(trainingMetrics.stored_exemplars) !== expectedRecords ||
      !Number.isFinite(macroMean) || macroMean < 1 || macroMean > 4) {
    throw new Error(`adaptive training metrics failed promotion gate: ${JSON.stringify(trainingMetrics)}`);
  }
  const tmpInfo = await stat(tmpCheckpoint);
  if (!tmpInfo.size) throw new Error('trainer produced an empty checkpoint');
  await syncPath(tmpCheckpoint);

  const names = await readdir(directory);
  const versions = names.flatMap(name => {
    const m = /^pretrain_large_v(\d+)\.nps$/.exec(name); return m ? [Number(m[1])] : [];
  });
  const version = Math.max(0, ...versions) + 1;
  const versionName = `pretrain_large_v${String(version).padStart(3, '0')}.nps`;
  destinationPath = path.join(directory, versionName);
  candidate = path.join(directory, `.${versionName}.${process.pid}.candidate`);
  await unlink(candidate).catch(() => {});
  const c = await openFile(candidate, 'wx', 0o600);
  try {
    const source = await openFile(tmpCheckpoint, 'r');
    try {
      const buffer = Buffer.alloc(1024 * 1024); let position = 0;
      while (true) {
        const { bytesRead } = await source.read(buffer, 0, buffer.length, position);
        if (!bytesRead) break;
        let copied = 0;
        while (copied < bytesRead) {
          const { bytesWritten } = await c.write(buffer, copied, bytesRead - copied);
          if (!bytesWritten) throw new Error('short write while staging checkpoint');
          copied += bytesWritten;
        }
        position += bytesRead;
      }
      if (position !== tmpInfo.size) throw new Error(`checkpoint copy size mismatch: ${position} != ${tmpInfo.size}`);
      await c.sync();
    } finally { await source.close(); }
  } finally { await c.close(); }
  // Candidate inference loads this private staging symlink; the production
  // `latest` alias remains untouched until every validation gate passes.
  await symlink(candidate, candidateAlias);
  const sampleText = (await readFile(samplePath, 'utf8')).trim();
  const samples = sampleText ? sampleText.split(/\r?\n/).map(JSON.parse) : [];
  if (samples.length !== expectedRecords || samples.some((item, i) =>
      item.record !== i || item.category !== i % 16 || !item.sample)) {
    throw new Error(`invalid validation manifest: expected ${expectedRecords} ordered records with 16-family labels; got ${samples.length}`);
  }
  const selectedByRecord = new Map();
  const familyCount = Math.min(16, samples.length);
  for (let category = 0; category < familyCount; category++) {
    const item = samples.find(sample => sample.category === category);
    if (!item) throw new Error(`validation manifest missing task family ${category}`);
    selectedByRecord.set(item.record, item);
  }
  const spreadCount = Math.min(5, samples.length);
  for (let i = 0; i < spreadCount; i++) {
    const index = spreadCount === 1 ? 0 : Math.round(i * (samples.length - 1) / (spreadCount - 1));
    selectedByRecord.set(samples[index].record, samples[index]);
  }
  const selected = [...selectedByRecord.values()];
  const results = [];
  for (const item of selected) {
    const prompt = question(item.sample);
    const { fields, answer } = await infer(prompt);
    if (answer !== item.sample || Number(fields.memory_capacity) !== expectedRecords) {
      throw new Error(`validation failed on record ${item.record}: score=${fields.retrieval_similarity}, answer=${answer}`);
    }
    results.push({ prompt, answer, score: Number(fields.retrieval_similarity) });
  }
  // Promotion also requires safe abstention outside the narrow synthetic
  // arithmetic/conversion domain; these are safety smoke probes, not a language
  // quality benchmark or proof of general reasoning.
  const abstentionProbes = [
    "Trabzon'da bugün hava nasıl?",
    "Fotosentez bitkilerde nasıl gerçekleşir?",
    "Bu programdaki bellek sızıntısını bul ve düzelt.",
    "İnsan kalbinin temel görevi nedir?",
    "Türkiye'nin başkentini ve konumunu açıkla."
  ];
  for (const prompt of abstentionProbes) {
    const probe = await infer(prompt);
    const score = Number(probe.fields.retrieval_similarity);
    if (probe.answer || !Number.isFinite(score)) {
      throw new Error(`out-of-domain abstention gate failed: prompt=${prompt} score=${score} answer=${probe.answer}`);
    }
    results.push({ prompt, answer: '', score });
  }

  await unlink(candidateAlias).catch(() => {});
  await rename(candidate, destinationPath); candidate = null;
  destinationCreated = true;
  switched = true;
  await replaceAlias(versionName);
  switched = false;
  await syncPath(destinationPath);
  destinationCreated = false;
  console.log(`published_checkpoint=${versionName} bytes=${tmpInfo.size}`);
  console.log('validation=' + JSON.stringify(results, null, 2));
} catch (error) {
  let rollbackSafe = !switched;
  if (switched) {
    try {
      if (oldAlias) await replaceAlias(oldAlias);
      else { await unlink(alias).catch(() => {}); await syncDirectory(); }
      switched = false;
      rollbackSafe = true;
    } catch (rollbackError) {
      console.error(`CRITICAL: checkpoint alias rollback failed: ${rollbackError.message}`);
    }
  }
  if (candidate) await unlink(candidate).catch(() => {});
  // Never delete a checkpoint if the alias may still point at it.
  if (destinationCreated && destinationPath && rollbackSafe) await unlink(destinationPath).catch(() => {});
  console.error(`automatic training failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  if (lock) await lock.close().catch(() => {});
  await unlink(lockPath).catch(() => {});
  await unlink(tmpCheckpoint).catch(() => {});
  await unlink(candidateAlias).catch(() => {});
  await unlink('/tmp/noema_pretrain_dataset.txt').catch(() => {});
  await unlink('/tmp/noema_pretrain_dataset.nbin').catch(() => {});
  await unlink(samplePath).catch(() => {});
  await unlink('/tmp/noema_pretrain_dataset_meta.bin').catch(() => {});
}
