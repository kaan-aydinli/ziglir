import http from 'node:http';
import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { once } from 'node:events';
import { createWriteStream } from 'node:fs';
import { open as openFile, readFile, readdir, rename, stat, statfs, symlink, unlink, writeFile } from 'node:fs/promises';
import { freemem } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const port = Number(process.env.PORT || 4173);
const lir = process.env.LIR_BIN || path.join(root, 'zig-out/bin/lir');
const backend = path.join(root, 'ai/chat_site_backend.lir');
const uploadTrainer = path.join(root, 'ai/train_noema_chat_upload.lir');
const targetRecordBytes = 1024 * 1024;
const diskReserveBytes = 256 * 1024 * 1024;
const estimatedBytesPerExemplar = 8192;
const trainingTimeoutMs = Number(process.env.TRAIN_TIMEOUT_MS || 0); // zero means no artificial time cap
if (!Number.isSafeInteger(trainingTimeoutMs) || trainingTimeoutMs < 0) throw new Error('TRAIN_TIMEOUT_MS must be zero or a positive safe integer');
const uploadNbin = '/tmp/noema-chat-upload.nbin';
const uploadMeta = '/tmp/noema-chat-upload-meta.bin';
const uploadCheckpointTmp = '/tmp/noema-chat-upload.nps';
const progressFile = '/tmp/noema-chat-upload-progress.bin';
const trainingDirectory = path.join(root, 'ai/noema-training');
const modelFiles = {
  trained: path.join(trainingDirectory, 'pretrain_large_latest.nps'),
  trainedLegacy: path.join(trainingDirectory, 'pretrain_large.nps'),
  uploadedLatest: path.join(trainingDirectory, 'user_pretrain_latest.nps'),
  fresh: path.join(root, 'ai/src/noema_pretrain.lir'),
};
let trainingJob = null;
let trainingReserved = false;

async function findUploadedVersions() {
  const names = await readdir(trainingDirectory).catch(() => []);
  return names.flatMap(name => {
    const match = /^user_pretrain_v(\d+)\.nps$/.exec(name);
    return match ? [{ version: Number(match[1]), fileName: name, filePath: path.join(trainingDirectory, name) }] : [];
  }).sort((a, b) => b.version - a.version);
}

async function findIncludedVersions() {
  const names = await readdir(trainingDirectory).catch(() => []);
  return names.flatMap(name => {
    const match = /^pretrain_large_v(\d+)\.nps$/.exec(name);
    return match ? [{ version: Number(match[1]), fileName: name, filePath: path.join(trainingDirectory, name) }] : [];
  }).sort((a, b) => b.version - a.version);
}

async function describeModels() {
  const versions = await findUploadedVersions();
  const latest = versions[0] || null;
  const includedVersions = await findIncludedVersions();
  const included = includedVersions[0] || null;
  const trainedPath = included?.filePath || modelFiles.trainedLegacy;
  const paths = [
    ['trained', trainedPath, included ? `NOEMA-Phi · trained corpus v${String(included.version).padStart(3, '0')}` : 'NOEMA-Phi · trained corpus checkpoint'],
    ['uploaded', latest?.filePath || path.join(trainingDirectory, 'user_pretrain_v001.nps'), latest ? `NOEMA-Phi · TXT checkpoint v${String(latest.version).padStart(3, '0')}` : 'NOEMA-Phi · no TXT checkpoint trained yet'],
    ['fresh', modelFiles.fresh, 'NOEMA-Phi · untrained baseline'],
  ];
  return Promise.all(paths.map(async ([id, filePath, description]) => {
    let fileStat = null;
    try { fileStat = await stat(filePath); } catch {}
    return {
      id,
      description,
      version: id === 'uploaded' ? latest?.version ?? null : id === 'trained' ? included?.version ?? null : null,
      fileName: path.basename(filePath),
      filePath: path.relative(root, filePath).split(path.sep).join('/'),
      modifiedDate: fileStat ? fileStat.mtime.toISOString().slice(0, 10) : null,
      available: id === 'fresh' ? Boolean(fileStat) : Boolean(fileStat && fileStat.size > 0),
      fileBytes: id !== 'fresh' && fileStat ? fileStat.size : 0,
    };
  }));
}

class UploadError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}

async function writeStreamChunk(stream, chunk) {
  if (!chunk.length) return;
  if (!stream.write(chunk)) await once(stream, 'drain');
}

async function prepareUploadedCorpus(req) {
  const output = createWriteStream(uploadNbin, { flags: 'w' });
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let sourceBytes = 0;
  let payloadBytes = 0;
  let records = 0;
  let lineParts = [];
  let lineLength = 0;
  let topicParts = [];
  let topicLength = 0;
  let batchParts = [];
  let batchLength = 0;
  let lastDiskCheck = 0;

  const availableTmpBytes = async () => {
    const fs = await statfs('/tmp');
    return BigInt(fs.bavail) * BigInt(fs.bsize);
  };
  const ensureDiskReserve = async (extra = 0n) => {
    const free = await availableTmpBytes();
    if (free < BigInt(diskReserveBytes) + extra) {
      throw new UploadError(`Yükleme için yeterli disk alanı kalmadı (${free} bayt boş).`, 507);
    }
  };

  const addLineBytes = bytes => {
    lineLength += bytes.length;
    if (!Number.isSafeInteger(lineLength)) throw new UploadError('Satır uzunluğu sayı aralığını aştı.', 413);
    if (bytes.length) lineParts.push(Buffer.from(bytes));
  };

  const flushRecord = async () => {
    if (!batchLength) return;
    const record = Buffer.concat(batchParts, batchLength);
    const header = Buffer.alloc(10);
    header.writeBigUInt64LE(BigInt(record.length), 0);
    header[8] = 0;
    header[9] = 0;
    await writeStreamChunk(output, header);
    await writeStreamChunk(output, record);
    records += 1;
    batchParts = [];
    batchLength = 0;
  };

  const addToBatch = async bytes => {
    let offset = 0;
    while (offset < bytes.length) {
      if (batchLength === targetRecordBytes) await flushRecord();
      const count = Math.min(targetRecordBytes - batchLength, bytes.length - offset);
      batchParts.push(bytes.subarray(offset, offset + count));
      batchLength += count;
      offset += count;
      if (batchLength === targetRecordBytes) await flushRecord();
    }
  };

  const finishTopic = async () => {
    if (topicLength) {
      const content = Buffer.concat(topicParts, topicLength);
      const hasContent = content.some(value => value !== 9 && value !== 10 && value !== 13 && value !== 32);
      if (hasContent) {
        // Preserve all topic bytes; only the standalone delimiter is framing.
        await addToBatch(content);
        payloadBytes += content.length;
      }
    }
    topicParts = [];
    topicLength = 0;
  };

  const finishLine = async (terminatedByNewline) => {
    const line = lineLength ? Buffer.concat(lineParts, lineLength) : Buffer.alloc(0);
    const comparableLength = line.length && line[line.length - 1] === 13 ? line.length - 1 : line.length;
    const separator = comparableLength === 3 && line[0] === 45 && line[1] === 45 && line[2] === 45;
    if (separator) {
      await finishTopic();
    } else {
      const extra = line.length + (terminatedByNewline ? 1 : 0);
      if (!Number.isSafeInteger(topicLength + extra)) throw new UploadError('Konu uzunluğu sayı aralığını aştı.', 413);
      if (topicLength > 0 && topicLength + extra > targetRecordBytes) await finishTopic();
      if (line.length) topicParts.push(line);
      if (terminatedByNewline) topicParts.push(Buffer.from([10]));
      topicLength += extra;
    }
    lineParts = [];
    lineLength = 0;
  };

  try {
    await ensureDiskReserve(64n * 1024n * 1024n);
    for await (const chunk of req) {
      if (!Number.isSafeInteger(sourceBytes + chunk.length)) {
        throw new UploadError('Dosya boyutu geçerli sayı aralığını aştı.', 413);
      }
      sourceBytes += chunk.length;
      if (sourceBytes - lastDiskCheck >= 64 * 1024 * 1024) {
        await ensureDiskReserve(64n * 1024n * 1024n);
        lastDiskCheck = sourceBytes;
      }
      if (chunk.includes(0)) throw new UploadError('TXT dosyası NUL karakteri içeremez.');
      try { decoder.decode(chunk, { stream: true }); }
      catch { throw new UploadError('Dosya geçerli UTF-8 metin değil.'); }
      let start = 0;
      while (start < chunk.length) {
        const newline = chunk.indexOf(10, start);
        if (newline < 0) {
          addLineBytes(chunk.subarray(start));
          break;
        }
        addLineBytes(chunk.subarray(start, newline));
        await finishLine(true);
        start = newline + 1;
      }
    }
    try { decoder.decode(); }
    catch { throw new UploadError('Dosya geçerli UTF-8 metin değil.'); }
    if (lineLength > 0) await finishLine(false);
    await finishTopic(false);
    await flushRecord();
    if (!sourceBytes || !records) throw new UploadError('TXT dosyasında eğitilecek konu bulunamadı.');
    const modelStateEstimate = BigInt(records) * BigInt(estimatedBytesPerExemplar);
    await ensureDiskReserve(modelStateEstimate);
    const memoryReserve = 128n * 1024n * 1024n + BigInt(targetRecordBytes) * 2n;
    if (BigInt(freemem()) < modelStateEstimate + memoryReserve) {
      throw new UploadError('Bu veri kümesi için kullanılabilir bellek yetersiz.', 507);
    }
    output.end();
    await once(output, 'finish');
    return { sourceBytes, payloadBytes, records };
  } catch (error) {
    output.destroy();
    await unlink(uploadNbin).catch(() => {});
    throw error;
  }
}

function currentProgress() {
  const job = trainingJob;
  if (!job) return null;
  let processed = job.processed;
  let total = job.total;
  let payloadBytes = job.processedBytes;
  try {
    const frame = readFileSync(progressFile);
    if (frame.length === 24) {
      processed = Number(frame.readBigUInt64LE(0));
      total = Number(frame.readBigUInt64LE(8));
      payloadBytes = Number(frame.readBigUInt64LE(16));
      job.processed = processed;
      job.total = total;
      job.processedBytes = payloadBytes;
    }
  } catch {}
  const elapsedSeconds = Math.max(0, (Date.now() - job.startedAt) / 1000);
  const percent = total > 0 ? Math.min(100, Math.floor(processed / total * 100)) : 0;
  const estimatedRemainingSeconds = processed > 0 && total > processed
    ? Math.max(0, Math.ceil(elapsedSeconds / processed * (total - processed)))
    : job.status === 'completed' ? 0 : null;
  return {
    jobId: job.id,
    status: job.status,
    version: job.version,
    percent: job.status === 'completed' ? 100 : percent,
    processed,
    total,
    payloadBytes,
    sourceBytes: job.sourceBytes,
    elapsedSeconds: Number(elapsedSeconds.toFixed(1)),
    estimatedRemainingSeconds,
    error: job.error || null,
  };
}

function send(res, status, data, type = 'application/json; charset=utf-8') {
  res.writeHead(status, {
    'content-type': type,
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'no-referrer',
  });
  res.end(data);
}

function jsonResponse(res, status, data) {
  return send(res, status, JSON.stringify(data));
}

async function syncPath(pathname, flags = 'r') {
  const handle = await openFile(pathname, flags);
  try { await handle.sync(); }
  finally { await handle.close(); }
}

async function startTraining(req, fileName, res) {
  if (trainingReserved) {
    req.resume();
    return jsonResponse(res, 409, { ok: false, error: 'Bir veri kümesi yükleniyor veya eğitim sürüyor.' });
  }
  if (!fileName || !fileName.toLowerCase().endsWith('.txt')) {
    req.resume();
    return jsonResponse(res, 400, { ok: false, error: 'Yalnızca .txt dosyası yükleyin.' });
  }
  const safeFileName = path.basename(fileName);
  trainingReserved = true;
  await Promise.all([uploadNbin, uploadMeta, uploadCheckpointTmp, progressFile].map(file => unlink(file).catch(() => {})));
  let corpus;
  try {
    corpus = await prepareUploadedCorpus(req);
  } catch (error) {
    trainingReserved = false;
    const status = error instanceof UploadError ? error.status : 500;
    return jsonResponse(res, status, { ok: false, error: error.message || 'TXT yüklenemedi.' });
  }

  const previousVersions = await findUploadedVersions();
  const nextVersion = (previousVersions[0]?.version || 0) + 1;
  const meta = Buffer.alloc(16);
  meta.writeBigUInt64LE(BigInt(corpus.records), 0);
  meta.writeBigUInt64LE(BigInt(corpus.payloadBytes), 8);
  const progress = Buffer.alloc(24);
  progress.writeBigUInt64LE(0n, 0);
  progress.writeBigUInt64LE(BigInt(corpus.records), 8);
  progress.writeBigUInt64LE(0n, 16);
  try { await Promise.all([writeFile(uploadMeta, meta), writeFile(progressFile, progress)]); }
  catch (error) {
    trainingReserved = false;
    await unlink(uploadNbin).catch(() => {});
    return jsonResponse(res, 500, { ok: false, error: error.message || 'Eğitim dosyaları hazırlanamadı.' });
  }

  const job = {
    id: randomUUID(),
    fileName: safeFileName,
    version: nextVersion,
    status: 'running',
    processed: 0,
    total: corpus.records,
    processedBytes: 0,
    sourceBytes: corpus.sourceBytes,
    payloadBytes: corpus.payloadBytes,
    startedAt: Date.now(),
    error: null,
  };
  trainingJob = job;
  const child = spawn(lir, ['run', uploadTrainer, '--backend=native'], {
    cwd: root,
    stdio: ['ignore', 'ignore', 'pipe'],
    env: { ...process.env },
  });
  let stderr = '';
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', chunk => { stderr = (stderr + chunk).slice(-8000); });
  const timeout = trainingTimeoutMs > 0 ? setTimeout(() => child.kill('SIGKILL'), trainingTimeoutMs) : null;
  child.on('error', error => {
    if (timeout) clearTimeout(timeout);
    job.status = 'failed';
    job.error = error.message;
    job.finishedAt = Date.now();
    trainingReserved = false;
  });
  child.on('close', async code => {
    if (timeout) clearTimeout(timeout);
    try {
      if (code !== 0) throw new Error(stderr.trim() || `LIR eğitim süreci ${code} koduyla bitti.`);
      await syncPath(uploadCheckpointTmp);
      const result = await stat(uploadCheckpointTmp);
      if (!result.size) throw new Error('Eğitim checkpoint dosyası boş.');
      const versionName = `user_pretrain_v${String(job.version).padStart(3, '0')}.nps`;
      const versionPath = path.join(trainingDirectory, versionName);
      try {
        await stat(versionPath);
        throw new Error(`Model sürümü ${versionName} zaten var; güvenlik için üzerine yazılmadı.`);
      } catch (error) {
        if (error.code !== 'ENOENT') throw error;
      }
      await rename(uploadCheckpointTmp, versionPath);
      await syncPath(trainingDirectory);
      const latestAliasTmp = `${modelFiles.uploadedLatest}.${job.id}.tmp`;
      await unlink(latestAliasTmp).catch(() => {});
      await symlink(versionName, latestAliasTmp);
      await rename(latestAliasTmp, modelFiles.uploadedLatest);
      await syncPath(trainingDirectory);
      job.versionFile = versionName;
      job.status = 'completed';
    } catch (error) {
      job.status = 'failed';
      job.error = error.message;
    }
    job.finishedAt = Date.now();
    await Promise.all([unlink(uploadNbin).catch(() => {}), unlink(uploadMeta).catch(() => {})]);
    trainingReserved = false;
  });
  return jsonResponse(res, 202, {
    ok: true,
    jobId: job.id,
    total: corpus.records,
    sourceBytes: corpus.sourceBytes,
    payloadBytes: corpus.payloadBytes,
    fileName: safeFileName,
    version: job.version,
  });
}

const mime = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
};

function parseMetrics(output) {
  const lines = output.trim().split(/\r?\n/).filter(Boolean);
  if (lines.shift() !== 'NOEMA_RESULT_V2') throw new Error('Beklenmeyen LIR çıktısı');
  const values = Object.fromEntries(lines.map(line => {
    const split = line.indexOf('=');
    return split < 0 ? [line, ''] : [line.slice(0, split), line.slice(split + 1)];
  }));
  if (values.ok !== '1') throw new Error(values.error || 'LIR işlemi başarısız');
  const number = key => {
    const n = Number(values[key]);
    if (!Number.isFinite(n)) throw new Error(`Geçersiz model ölçümü: ${key}`);
    return n;
  };
  const generatedHex = values.generated_hex || '';
  if (generatedHex.length % 2 || !/^[0-9a-f]*$/i.test(generatedHex)) throw new Error('Modelin bayt çıktısı bozuk');
  return {
    modelId: values.model_id,
    trainingRecords: number('training_records'),
    trainingBytes: number('training_bytes'),
    trainingDoPerturbations: number('training_do_perturbations'),
    spectralStage: number('spectral_stage'),
    inputBytes: number('input_bytes'),
    freeEnergy: number('inference_free_energy'),
    surpriseGate: number('inference_surprise_gate'),
    retrievalSimilarity: number('retrieval_similarity'),
    storedExemplars: number('stored_exemplars'),
    memoryCapacity: number('memory_capacity'),
    generatedBytes: number('generated_bytes'),
    generatedHex,
    outputMode: 'learned_raw_byte_excerpt',
  };
}

function runLir(modelId, prompt) {
  return new Promise((resolve, reject) => {
    const child = spawn(lir, ['run', backend, '--backend=native'], {
      cwd: root,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env },
    });
    let stdout = '';
    let stderr = '';
    let settled = false;
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      if (!settled) {
        settled = true;
        reject(new Error('LIR isteği zaman aşımına uğradı'));
      }
    }, 15000);
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('error', error => {
      clearTimeout(timer);
      if (!settled) { settled = true; reject(error); }
    });
    child.on('close', code => {
      clearTimeout(timer);
      if (settled) return;
      settled = true;
      if (code !== 0) return reject(new Error(stderr.trim() || `LIR çıkış kodu ${code}`));
      try { resolve(parseMetrics(stdout)); }
      catch (error) { reject(new Error(`${error.message}${stderr ? `: ${stderr.trim()}` : ''}`)); }
    });
    child.stdin.on('error', () => {});
    child.stdin.end(`${modelId}\n${prompt}`, 'utf8');
  });
}

async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (!Number.isSafeInteger(size)) throw new Error('İstek boyutu sayı aralığını aştı.');
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks, size).toString('utf8'));
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || '/', 'http://localhost');
  if (req.method === 'GET' && url.pathname === '/api/health') {
    return jsonResponse(res, 200, {
      ok: true,
      engine: 'LIR / NOEMA-Phi',
      inference: 'learned_raw_byte_excerpt',
      models: await describeModels(),
    });
  }
  if (req.method === 'POST' && url.pathname === '/api/train') {
    let fileName = '';
    try { fileName = decodeURIComponent(req.headers['x-file-name'] || ''); }
    catch { req.resume(); return jsonResponse(res, 400, { ok: false, error: 'Dosya adı geçersiz.' }); }
    return startTraining(req, fileName, res);
  }
  if (req.method === 'GET' && url.pathname === '/api/train/status') {
    if (!trainingJob || url.searchParams.get('jobId') !== trainingJob.id) {
      return jsonResponse(res, 404, { ok: false, error: 'Eğitim işi bulunamadı.' });
    }
    const progress = currentProgress();
    const model = trainingJob.status === 'completed'
      ? (await describeModels()).find(item => item.id === 'uploaded')
      : null;
    return jsonResponse(res, 200, { ok: true, ...progress, model });
  }
  if (req.method === 'POST' && url.pathname === '/api/chat') {
    try {
      const body = await readBody(req);
      if (typeof body.message !== 'string' || !body.message.trim()) {
        return jsonResponse(res, 400, { error: 'Bir mesaj yazın.' });
      }
      const requestedModel = ['trained', 'uploaded', 'fresh'].includes(body.modelId) ? body.modelId : 'trained';
      const model = (await describeModels()).find(item => item.id === requestedModel);
      if (!model?.available) return jsonResponse(res, 400, { error: 'Seçilen model dosyası henüz hazır değil.' });
      const metrics = await runLir(requestedModel, body.message);
      return jsonResponse(res, 200, { ok: true, model, metrics });
    } catch (error) {
      const status = error instanceof SyntaxError ? 400 : 500;
      return jsonResponse(res, status, { error: error.message || 'İstek işlenemedi.' });
    }
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return jsonResponse(res, 405, { error: 'Method not allowed' });
  }
  const route = url.pathname === '/pretraining' ? '/pretraining.html'
    : url.pathname === '/chat' ? '/index.html'
      : url.pathname === '/' ? '/index.html' : decodeURIComponent(url.pathname);
  const safe = path.resolve(here, `.${route}`);
  if (!safe.startsWith(`${here}${path.sep}`)) return send(res, 404, 'Not found', 'text/plain; charset=utf-8');
  try {
    const data = await readFile(safe);
    res.writeHead(200, {
      'content-type': mime[path.extname(safe)] || 'application/octet-stream',
      'cache-control': 'no-cache',
      'x-content-type-options': 'nosniff',
      'content-security-policy': "default-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; img-src 'self' data:",
    });
    if (req.method === 'HEAD') return res.end();
    return res.end(data);
  } catch {
    return send(res, 404, 'Not found', 'text/plain; charset=utf-8');
  }
});

server.listen(port, '0.0.0.0', () => {
  console.log(`NOEMA Chat listening on 0.0.0.0:${port}`);
  console.log(`LIR binary: ${lir}`);
});
