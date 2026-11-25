// Train the bundled corpus, then publish a durable, never-overwritten version.
import { spawn } from 'node:child_process';
import { open as openFile, readdir, rename, stat, symlink, unlink } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const directory = path.join(root, 'ai/noema-training');
const lir = process.env.LIR_BIN || path.join(root, 'zig-out/bin/lir');
const trainer = path.join(root, 'ai/train_turkish_corpus.lir');
const temporary = '/tmp/noema-pretrain-large.nps';
const lockPath = path.join(directory, 'pretrain_large.lock');

async function syncPath(filePath) {
  const handle = await openFile(filePath, 'r');
  try { await handle.sync(); }
  finally { await handle.close(); }
}

function runTrainer() {
  return new Promise((resolve, reject) => {
    const child = spawn(lir, ['run', trainer, '--backend=native'], {
      cwd: root,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env },
    });
    let stdout = '';
    let stderr = '';
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr = (stderr + chunk).slice(-8000); });
    child.on('error', reject);
    child.on('close', code => code === 0
      ? resolve(stdout)
      : reject(new Error(stderr.trim() || `LIR trainer exited with code ${code}`)));
  });
}

let lock;
let temporaryAlias;
try {
  lock = await openFile(lockPath, 'wx', 0o600);
  await lock.writeFile(`${process.pid}\n`);
  await lock.sync();
  await unlink(temporary).catch(() => {});

  const output = await runTrainer();
  const checkpoint = await stat(temporary);
  if (!checkpoint.size) throw new Error('Trainer produced an empty checkpoint.');
  await syncPath(temporary);

  const names = await readdir(directory);
  const versions = names.flatMap(name => {
    const match = /^pretrain_large_v(\d+)\.nps$/.exec(name);
    return match ? [Number(match[1])] : [];
  });
  const version = Math.max(0, ...versions) + 1;
  const fileName = `pretrain_large_v${String(version).padStart(3, '0')}.nps`;
  const destination = path.join(directory, fileName);
  try {
    await stat(destination);
    throw new Error(`Refusing to overwrite existing checkpoint ${fileName}.`);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  await rename(temporary, destination);
  await syncPath(directory);

  const latest = path.join(directory, 'pretrain_large_latest.nps');
  temporaryAlias = `${latest}.${process.pid}.${Date.now()}.tmp`;
  await symlink(fileName, temporaryAlias);
  await rename(temporaryAlias, latest);
  temporaryAlias = null;
  await syncPath(directory);

  process.stdout.write(output);
  process.stdout.write(`published_checkpoint=${fileName}\n`);
} catch (error) {
  process.stderr.write(`included corpus training failed: ${error.message}\n`);
  process.exitCode = 1;
} finally {
  if (temporaryAlias) await unlink(temporaryAlias).catch(() => {});
  if (lock) await lock.close().catch(() => {});
  await unlink(lockPath).catch(() => {});
  await unlink(temporary).catch(() => {});
}
