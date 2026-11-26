import http from 'node:http';
import { spawn } from 'node:child_process';
import { constants as fsConstants, readFileSync, rmSync } from 'node:fs';
import { randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { once } from 'node:events';
import { mkdtemp, open, readFile, readdir, rm, stat, statfs, unlink, writeFile } from 'node:fs/promises';
import { cpus, freemem, loadavg, tmpdir, totalmem } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const port = Number(process.env.PORT || 4173);

/// Positive-integer env reader. Fail-closed: a malformed or non-positive value
/// aborts startup instead of silently falling back to "no limit" — the pre-fix
/// `TRAIN_TIMEOUT_MS || 0` default meant an unbounded trainer subprocess.
function intEnv(name, fallback, { allowZero = false } = {}) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value < 0 || (value === 0 && !allowZero)) {
    throw new Error(`${name} must be a positive safe integer (got '${raw}')`);
  }
  return value;
}

// Bind loopback by default. The pre-fix server listened on 0.0.0.0 with no
// auth and no rate limit: one request from anywhere on the network could pin
// the host CPU with an unbounded VM/trainer subprocess (Issue #4). Exposing
// the service now requires an explicit NOEMA_CHAT_HOST=0.0.0.0.
const HOST = process.env.NOEMA_CHAT_HOST || '127.0.0.1';
const lir = process.env.LIR_BIN || path.join(root, 'zig-out/bin/lir');
const BACKEND_NATIVE = process.env.NOEMA_V3_BACKEND_BIN || path.join(root, 'zig-out/bin/noema_v3_chat_backend');
const BACKEND_LIR = path.join(root, 'ai/noema_v3_chat_backend.lir');
const TRAINER_NATIVE = process.env.NOEMA_V3_TRAINER_BIN || path.join(root, 'zig-out/bin/noema_v3_upload_trainer');
const TRAINER_LIR = path.join(root, 'ai/noema_v3_upload_trainer.lir');
// Phase 0 isolation: the legacy exemplar-retrieval backend is retained for the
// `fresh`/`trained`/`uploaded` NOEMA-Phi selectors. It must *never* be reported as NOEMA v3 weight
// generation, which is why its output mode is a separate contract literal.
const LEGACY_BACKEND_LIR = path.join(root, 'ai/chat_site_backend.lir');
const LEGACY_OUTPUT_MODE = 'legacy_retrieval_exemplar';

const checkpointsDir = path.join(root, 'ai/noema_v3/checkpoints');
const bridgeCorpus = path.join(root, 'ai/noema_v3/prod_bridge_scaffold.tr.txt');
const userShardDir = path.join(root, 'ai/noema_v3/corpus_user');

const maxCorpusRun = 4;
const diskReserveBytes = 256 * 1024 * 1024;

// Private per-process work directory (mkdtemp => mode 0700, unique name)
// instead of the old fixed, world-writable /tmp paths. Fixed paths let any
// local user pre-create a directory/symlink at the name (permanent EISDIR
// DoS, or a TOCTOU race between the unlink and the create), and made the
// uploaded corpus readable to every local user while a job ran.
const workDir = await mkdtemp(path.join(tmpdir(), 'noema-chat-'));
const uploadTmp = path.join(workDir, 'upload.tr.txt');
const progressFile = path.join(workDir, 'progress.bin');
// O_EXCL: refuse to open a pre-existing file (no silent reuse); O_NOFOLLOW:
// refuse symlinks even inside our own directory.
const EXCL_NOFOLLOW = fsConstants.O_WRONLY | fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_NOFOLLOW;
function cleanupWorkDir() {
  try { rmSync(workDir, { recursive: true, force: true, maxRetries: 2 }); } catch { /* best effort */ }
}
process.on('exit', cleanupWorkDir);
for (const [sig, code] of [['SIGINT', 130], ['SIGTERM', 143]]) {
  process.on(sig, () => { cleanupWorkDir(); process.exit(code); });
}

const requestTimeoutMs = intEnv('CHAT_TIMEOUT_MS', 30000);
// Training timeout: 10 minutes by default, never 0. "unlimited" is accepted
// only as an explicit, spelled-out opt-in — a numeric 0 aborts startup.
const trainingTimeoutMs = (() => {
  const raw = process.env.TRAIN_TIMEOUT_MS;
  if (raw === undefined || raw === '') return 600_000;
  if (raw === 'unlimited') return 0; // explicit opt-out; spawnCapture then runs without a timer
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`TRAIN_TIMEOUT_MS must be a positive safe integer or the literal 'unlimited' (got '${raw}')`);
  }
  return value;
})();

// Basic abuse limits (Issue #4). All have sane defaults; all are enforced.
const rateWindowMs = 60_000;
const rateChatPerWindow = intEnv('NOEMA_RATE_CHAT', 30);
const rateTrainPerWindow = intEnv('NOEMA_RATE_TRAIN', 5);
const rateApiPerWindow = intEnv('NOEMA_RATE_API', 240);
const maxConcurrentRuns = intEnv('NOEMA_MAX_CONCURRENT_RUNS', 2);
const maxUploadBytes = intEnv('NOEMA_MAX_UPLOAD_BYTES', 64 * 1024 * 1024);

const rateBuckets = new Map(); // key -> { count, resetAt }
function rateAllow(key, limit) {
  const now = Date.now();
  let bucket = rateBuckets.get(key);
  if (!bucket || now >= bucket.resetAt) {
    bucket = { count: 0, resetAt: now + rateWindowMs };
    rateBuckets.set(key, bucket);
    if (rateBuckets.size > 8192) {
      for (const [k, v] of rateBuckets) if (now >= v.resetAt) rateBuckets.delete(k);
    }
  }
  bucket.count += 1;
  return bucket.count <= limit;
}

// Default-on auth for the endpoints that spawn subprocesses. Browsers get an
// HttpOnly SameSite=Strict session cookie when they load the UI, so the
// existing frontend keeps working with zero changes; anything that is not a
// same-site browser (curl, another host, a CSRF form post) must present the
// cookie or a NOEMA_CHAT_TOKEN bearer token. NOEMA_CHAT_AUTH=off is the only
// way to disable it, and it is explicit.
const authEnabled = (process.env.NOEMA_CHAT_AUTH || '').toLowerCase() !== 'off';
const bearerToken = typeof process.env.NOEMA_CHAT_TOKEN === 'string' && process.env.NOEMA_CHAT_TOKEN.length >= 16
  ? process.env.NOEMA_CHAT_TOKEN
  : null;
const sessions = new Map(); // token -> issuedAt
const SESSION_LIMIT = 1024;
function issueSession() {
  const token = randomBytes(32).toString('base64url');
  if (sessions.size >= SESSION_LIMIT) sessions.delete(sessions.keys().next().value); // evict oldest
  sessions.set(token, Date.now());
  return token;
}
function parseCookies(req) {
  const out = {};
  const header = req.headers.cookie;
  if (typeof header !== 'string') return out;
  for (const part of header.split(';')) {
    const at = part.indexOf('=');
    if (at > 0) out[part.slice(0, at).trim()] = part.slice(at + 1).trim();
  }
  return out;
}
function sessionToken(req) {
  const token = parseCookies(req)['noema_session'];
  return typeof token === 'string' && token.length === 43 && sessions.has(token) ? token : null;
}
function isAuthorized(req) {
  if (!authEnabled) return true;
  const auth = req.headers.authorization;
  if (typeof auth === 'string' && auth.startsWith('Bearer ') && bearerToken) {
    const given = Buffer.from(auth.slice(7));
    const want = Buffer.from(bearerToken);
    if (given.length === want.length && timingSafeEqual(given, want)) return true;
  }
  return sessionToken(req) !== null;
}

let trainingJob = null;
let trainingReserved = false;

// ---------------------------------------------------------------------------------------------
// artifact discovery
// ---------------------------------------------------------------------------------------------

async function listFiles(dir, pattern) {
  const names = await readdir(dir).catch(() => []);
  return names.flatMap(name => {
    const match = pattern.exec(name);
    return match ? [{ name, version: Number(match[1]) }] : [];
  }).sort((a, b) => b.version - a.version);
}

async function fileSize(filePath) {
  try {
    const info = await stat(filePath);
    return info.size;
  } catch {
    return 0;
  }
}

const BASE_MODELS = [
  {
    id: 'noema_v3',
    selector: 'noema_v3',
    label: 'NOEMA v3 · üretim tabanı',
    sampling: { temperature: 0, determinism: 'byte-identical' },
    npg: () => path.join(checkpointsDir, 'noema_v3_promoted.npg3'),
    nv3g: () => path.join(checkpointsDir, 'noema_v3_prod.nv3g'),
  },
  {
    id: 'noema_v3_scaled',
    selector: 'noema_v3_scaled',
    label: 'NOEMA v3 · ölçekli çoklu-shard',
    sampling: { temperature: 0, determinism: 'byte-identical' },
    npg: () => path.join(checkpointsDir, 'noema_v3_scaled.npg3'),
    nv3g: () => path.join(checkpointsDir, 'noema_v3_prod.nv3g'),
  },
];

async function listUserModels() {
  const pairs = await listFiles(checkpointsDir, /^user_v3_(?:v(\d+))\.nv3g$/);
  return pairs.flatMap(({ name, version }) => {
    const stem = name.replace(/\.nv3g$/, '');
    return [{
      id: name.replace(/\.nv3g$/, ''),
      selector: `noema_v3_user:${stem}`,
      label: `NOEMA v3 · yüklenen veri v${String(version).padStart(3, '0')}`,
      sampling: { temperature: 0, determinism: 'byte-identical' },
      npg: () => path.join(checkpointsDir, `${stem}.npg3`),
      nv3g: () => path.join(checkpointsDir, name),
      version,
    }];
  });
}

const LEGACY_MODELS = [
  { id: 'fresh', selector: 'legacy:fresh', label: 'NOEMA-Φ · eğitimsiz başlangıç' },
  { id: 'trained', selector: 'legacy:trained', label: 'NOEMA-Φ · eğitilmiş büyük checkpoint' },
  { id: 'uploaded', selector: 'legacy:uploaded', label: 'NOEMA-Φ · yüklenen veri checkpoint\'i' },
];

async function describeModels() {
  const users = await listUserModels();
  const models = [...BASE_MODELS, ...users];
  return Promise.all(models.map(async model => {
    const npgPath = model.npg();
    const nv3gPath = model.nv3g();
    const [npgBytes, nv3gBytes] = await Promise.all([fileSize(npgPath), fileSize(nv3gPath)]);
    return {
      id: model.id,
      selector: model.selector,
      label: model.label,
      available: npgBytes > 0 && nv3gBytes > 0,
      checkpointBytes: npgBytes,
      graphBytes: nv3gBytes,
      checkpointPath: path.relative(root, npgPath).split(path.sep).join('/'),
      fileName: path.basename(npgPath),
      graphFileName: path.basename(nv3gPath),
      graphPath: path.relative(root, nv3gPath).split(path.sep).join('/'),
      sampling: model.sampling,
      maxCorpusRun,
    };
  })).then(async rows => {
    // Legacy NOEMA-Φ selectors are listed after the v3 models so the UI keeps their historical
    // ids, and are marked with `outputMode` so a client can never confuse them with v3.
    const legacy = LEGACY_MODELS.map(model => ({
      id: model.id,
      selector: model.selector,
      label: model.label,
      available: true,
      legacy: true,
      outputMode: LEGACY_OUTPUT_MODE,
      maxCorpusRun: 0,
    }));
    return [...rows, ...legacy];
  });
}

async function resolveSelector(selector) {
  const models = await describeModels();
  const found = models.find(model => model.selector === selector || model.id === selector);
  if (!found || !found.available) return null;
  return found;
}

// ---------------------------------------------------------------------------------------------
// LIR execution
// ---------------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------------------------
// inference accounting: real, per-process measurements (no simulated numbers anywhere)
// ---------------------------------------------------------------------------------------------

const serverStartedAt = Date.now();
const inferenceStats = {
  requests: 0,
  generated: 0,
  abstained: 0,
  errors: 0,
  cacheHits: 0,
  cpuMsTotal: 0,
  wallMsTotal: 0,
  bytesGenerated: 0,
  atomsSynthesized: 0,
  ngramMax: 0,
  khgObserved: 0,
  khgVerified: 0,
  khgQuarantined: 0,
  antiVerbatimChecks: 0,
  antiVerbatimPasses: 0,
};

// Deterministic inference is the whole point of NOEMA v3: the same prompt against the same
// checkpoint must yield byte-identical bytes. That makes a response cache *exact*, not
// approximate — a repeat question costs zero CPU instead of a full subprocess spawn. The cache
// is small and LRU-bounded so it cannot grow into a memory leak on a long-running server.
const CACHE_LIMIT = Math.max(0, Number(process.env.CHAT_CACHE_SIZE ?? 64));
const responseCache = new Map();
const cacheKey = (selector, prompt) => `${selector}\u0000${prompt}`;

function cacheGet(key) {
  if (!CACHE_LIMIT || !responseCache.has(key)) return null;
  const value = responseCache.get(key);
  responseCache.delete(key);
  responseCache.set(key, value); // refresh recency
  return value;
}

function cachePut(key, value) {
  if (!CACHE_LIMIT) return;
  if (responseCache.size >= CACHE_LIMIT) {
    responseCache.delete(responseCache.keys().next().value); // evict least recently used
  }
  responseCache.set(key, value);
}

let activeRuns = 0;
let peakConcurrentRuns = 0;

function hostTelemetry() {
  const memTotal = totalmem();
  const memFree = freemem();
  const loads = loadavg();
  return {
    // Load average is the OS's own 1-minute run queue length; dividing by core count gives a
    // comparable "how busy is this machine" figure that is independent of hardware size.
    load1: Number(loads[0].toFixed(2)),
    load5: Number(loads[1].toFixed(2)),
    load15: Number(loads[2].toFixed(2)),
    cores: cpus().length,
    memory: {
      totalBytes: memTotal,
      freeBytes: memFree,
      usedPercent: Number((((memTotal - memFree) / memTotal) * 100).toFixed(1)),
    },
    uptimeSeconds: Math.floor(process.uptime()),
    rssBytes: process.memoryUsage().rss,
  };
}

function inferenceTelemetry() {
  const s = inferenceStats;
  return {
    ...s,
    peakConcurrentRuns,
    activeRuns,
    meanCpuMs: s.requests ? Number((s.cpuMsTotal / s.requests).toFixed(2)) : 0,
    meanWallMs: s.requests ? Number((s.wallMsTotal / s.requests).toFixed(2)) : 0,
    cacheSize: responseCache.size,
    cacheLimit: CACHE_LIMIT,
    // A cache hit avoids a process spawn entirely; this is the share of questions answered
    // without touching the CPU at all.
    cacheHitPercent: s.requests ? Number(((s.cacheHits / s.requests) * 100).toFixed(1)) : 0,
    sinceMs: Date.now() - serverStartedAt,
  };
}

function spawnCapture(command, args, { input, timeoutMs } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: root,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env },
    });
    let stdout = '';
    let stderr = '';
    let settled = false;
    const timer = timeoutMs
      ? setTimeout(() => {
        child.kill('SIGKILL');
        if (!settled) {
          settled = true;
          reject(new Error(`LIR süreci ${timeoutMs}ms içinde yanıt vermedi.`));
        }
      }, timeoutMs)
      : null;
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('error', error => {
      if (timer) clearTimeout(timer);
      if (!settled) { settled = true; reject(error); }
    });
    child.on('close', code => {
      if (timer) clearTimeout(timer);
      if (settled) return;
      settled = true;
      if (code !== 0) return reject(new Error(stderr.trim() || `LIR çıkış kodu ${code}`));
      resolve({ stdout, stderr });
    });
    child.stdin.on('error', () => {});
    child.stdin.end(input ?? '', 'utf8');
  });
}

async function runLegacyChat(kind, prompt) {
  const input = `${kind}\n${prompt}`;
  const run = await spawnCapture(lir, ['run', '--backend=vm', LEGACY_BACKEND_LIR], { input, timeoutMs: requestTimeoutMs });
  const values = parseLegacyEnvelope(run.stdout, run.stderr);
  return values;
}

function parseLegacyEnvelope(stdout, stderr = '') {
  const lines = stdout.trim().split(/\r?\n/).filter(Boolean);
  if (!lines.length || lines[0] !== 'NOEMA_RESULT_V2') throw new Error(`Beklenmeyen LIR çıktısı: ${stderr.trim() || stdout.slice(0, 200)}`);
  const values = {};
  for (const line of lines.slice(1)) {
    const at = line.indexOf('=');
    if (at > 0) values[line.slice(0, at)] = line.slice(at + 1);
  }
  if (values.ok !== '1') throw new Error(values.error || 'LIR işlemi başarısız');
  // Fail closed: the legacy path may only ever report its own mode.
  if (values.output_mode !== LEGACY_OUTPUT_MODE) throw new Error(`Legacy izolasyon ihlali: output_mode=${values.output_mode}`);
  const hex = values.generated_hex || '';
  if (hex.length % 2 !== 0 || !/^[0-9a-f]*$/i.test(hex)) throw new Error('Modelin bayt çıktısı bozuk');
  const num = key => {
    const parsed = Number(values[key] ?? 0);
    return Number.isFinite(parsed) ? parsed : 0;
  };
  const text = hex ? Buffer.from(hex, 'hex').toString('utf8') : '';
  return {
    modelId: values.model_id,
    outputMode: LEGACY_OUTPUT_MODE,
    abstained: !text,
    reply: text,
    retrievalSimilarity: Number(values.retrieval_similarity ?? 0),
    generatedBytes: num('generated_bytes'),
    generatedHex: hex,
    trainingRecords: num('training_records'),
    trainingBytes: num('training_bytes'),
    trainingDoPerturbations: num('training_do_perturbations'),
    spectralStage: num('spectral_stage'),
    inputBytes: num('input_bytes'),
    freeEnergy: Number(values.inference_free_energy ?? 0),
    surpriseGate: Number(values.inference_surprise_gate ?? 0),
    storedExemplars: num('stored_exemplars'),
    memoryCapacity: num('memory_capacity'),
    khgObservedSpans: 0,
    khgVerifiedSpans: 0,
    proofVerifiedClaims: 0,
    proofRefutedClaims: 0,
  };
}

// Bare legacy ids (`fresh`, `trained`, `uploaded`) are accepted for historical clients that predate
// the explicit `legacy:` prefix; they are normalised to the prefixed form before routing.
function normalizeSelector(selector) {
  const bare = LEGACY_MODELS.find(model => model.id === selector);
  return bare ? bare.selector : selector;
}

async function runChat(rawSelector, prompt) {
  const selector = normalizeSelector(rawSelector);
  if (selector.startsWith('legacy:')) {
    const kind = selector.slice('legacy:'.length);
    if (!['fresh', 'trained', 'uploaded', 'candidate'].includes(kind)) {
      throw Object.assign(new Error('Bilinmeyen legacy model seçici.'), { status: 400 });
    }
    const envelope = await runLegacyChat(kind, prompt);
    const model = { id: kind, selector, label: `NOEMA-Φ · ${kind}`, checkpointPath: 'ai/noema-training/*.nps', graphPath: '—' };
    return { model, envelope };
  }
  const model = await resolveSelector(selector);
  if (!model) throw Object.assign(new Error('Seçilen NOEMA v3 modeli hazır değil.'), { status: 400 });
  const key = cacheKey(selector, prompt);
  const hit = cacheGet(key);
  if (hit) {
    inferenceStats.requests += 1;
    inferenceStats.cacheHits += 1;
    return { model, envelope: { ...hit, cached: true, latencyMs: 0 } };
  }
  const npg = path.join(root, model.checkpointPath);
  const nv3g = path.join(root, model.graphPath);
  const input = `${selector}\n${prompt}`;
  const started = process.hrtime.bigint();
  const cpuStarted = process.cpuUsage();
  activeRuns += 1;
  peakConcurrentRuns = Math.max(peakConcurrentRuns, activeRuns);
  let result;
  try {
    if (await fileSize(BACKEND_NATIVE)) {
      result = await spawnCapture(BACKEND_NATIVE, [npg, nv3g], { input, timeoutMs: requestTimeoutMs });
    } else {
      result = await spawnCapture(lir, ['run', '--backend=vm', BACKEND_LIR, npg, nv3g], { input, timeoutMs: requestTimeoutMs });
    }
  } finally {
    activeRuns -= 1;
  }
  const wallMs = Number(process.hrtime.bigint() - started) / 1e6;
  const cpu = process.cpuUsage(cpuStarted);
  const cpuMs = (cpu.user + cpu.system) / 1000;
  const envelope = parseEnvelope(result.stdout, result.stderr);
  // Record what this run actually did. Every counter below is incremented from the backend's own
  // report, so the dashboard can never show a number the model did not produce.
  inferenceStats.requests += 1;
  inferenceStats.wallMsTotal += wallMs;
  inferenceStats.cpuMsTotal += cpuMs;
  inferenceStats.bytesGenerated += envelope.generatedBytes || 0;
  inferenceStats.atomsSynthesized += envelope.synthesizedAtoms || 0;
  inferenceStats.ngramMax = Math.max(inferenceStats.ngramMax, envelope.maxCorpusNgramRun || 0);
  inferenceStats.khgObserved += envelope.khgObservedSpans || 0;
  inferenceStats.khgVerified += envelope.khgVerifiedSpans || 0;
  inferenceStats.khgQuarantined += envelope.khgQuarantinedSpans || 0;
  if (envelope.antiVerbatimVerified === 1) inferenceStats.antiVerbatimPasses += 1;
  inferenceStats.antiVerbatimChecks += 1;
  if (envelope.abstained) inferenceStats.abstained += 1;
  else inferenceStats.generated += 1;
  const measured = { ...envelope, cached: false, latencyMs: Math.round(wallMs), cpuMs: Number(cpuMs.toFixed(2)) };
  cachePut(key, measured);
  return { model, envelope: measured };
}

function parseEnvelope(stdout, stderr = '') {
  const lines = stdout.trim().split(/\r?\n/).filter(Boolean);
  if (!lines.length || lines[0] !== 'NOEMA_RESULT_V2') throw new Error(`Beklenmeyen LIR çıktısı: ${stderr.trim() || stdout.slice(0, 200)}`);
  const values = {};
  for (const line of lines.slice(1)) {
    const at = line.indexOf('=');
    if (at > 0) values[line.slice(0, at)] = line.slice(at + 1);
  }
  if (values.ok !== '1') throw new Error(values.error || 'LIR işlemi başarısız');
  const num = key => {
    const parsed = Number(values[key]);
    if (!Number.isFinite(parsed)) throw new Error(`Geçersiz model ölçümü: ${key}`);
    return parsed;
  };
  const optNum = key => (values[key] === undefined || values[key] === '' ? 0 : num(key));
  const hex = values.generated_hex || '';
  if (hex.length % 2 !== 0 || !/^[0-9a-f]*$/i.test(hex)) throw new Error('Modelin bayt çıktısı bozuk');
  const outputMode = values.output_mode || '';
  if (!['noema_v3_weight_generation', 'noema_v3_weight_generation_abstain'].includes(outputMode)) {
    throw new Error(`NOEMA v3 izolasyon ihlali: beklenmeyen output_mode=${outputMode}`);
  }
  const text = hex ? Buffer.from(hex, 'hex').toString('utf8') : '';
  if (text.includes('\uFFFD')) throw new Error('Modelin bayt çıktısı geçerli UTF-8 değil');
  return {
    modelId: values.model_id,
    outputMode,
    abstained: outputMode === 'noema_v3_weight_generation_abstain',
    // Both the decoded text and the exact bytes travel to the client: the UI shows the text, and
    // the raw hex is what makes the reply auditable byte-for-byte (the run detail panel shows it).
    reply: text,
    generatedHex: hex,
    generatedBytes: optNum('generated_bytes'),
    antiVerbatimVerified: optNum('anti_verbatim_verified'),
    maxCorpusNgramRun: optNum('max_corpus_ngram_run'),
    synthesizedAtoms: optNum('synthesized_atoms'),
    khgObservedSpans: optNum('khg_observed_spans'),
    khgQuarantinedSpans: optNum('khg_quarantined_spans'),
    khgVerifiedSpans: optNum('khg_verified_spans'),
    proofVerifiedClaims: optNum('proof_verified_claims'),
    proofRefutedClaims: optNum('proof_refuted_claims'),
    proofStepsUsed: optNum('proof_steps_used'),
    symbolicSolved: optNum('symbolic_solved'),
    noSpanCopyVerified: optNum('no_span_copy_verified'),
    trainingRecords: optNum('training_records'),
    trainingBytes: optNum('training_bytes'),
    trainingDoPerturbations: optNum('training_do_perturbations'),
    spectralStage: optNum('spectral_stage'),
    inputBytes: optNum('input_bytes'),
    freeEnergy: optNum('inference_free_energy'),
    surpriseGate: optNum('inference_surprise_gate'),
    semanticMarginMilli: optNum('semantic_margin_milli'),
    corpusTopics: optNum('corpus_topics'),
    forbidden4Grams: optNum('forbidden_4grams'),
    storedExemplars: optNum('stored_exemplars'),
    memoryCapacity: optNum('memory_capacity'),
  };
}

// ---------------------------------------------------------------------------------------------
// upload validation and training
// ---------------------------------------------------------------------------------------------

class UploadError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}

const delimiter = Buffer.from('<veriayrimi>', 'utf8');

async function writeChunk(stream, chunk) {
  if (!chunk.length) return;
  if (!stream.write(chunk)) await once(stream, 'drain');
}

/**
 * Streams the uploaded TXT into a normalized `<veriayrimi>` payload.
 * Validation is strict and fail-closed: NUL bytes, invalid UTF-8, oversized segments, empty
 * corpora and segments that are only whitespace are rejected before any training starts.
 */
async function prepareUploadedCorpus(req) {
  const { createWriteStream } = await import('node:fs');
  const output = createWriteStream(uploadTmp, { flags: EXCL_NOFOLLOW, mode: 0o600 });
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let sourceBytes = 0;
  let payloadBytes = 0;
  let topics = 0;
  let lineParts = [];
  let lineLength = 0;
  let topicParts = [];
  let topicLength = 0;
  let lastDiskCheck = 0;
  const maxTopicBytes = 64 * 1024;

  const ensureDisk = async () => {
    const info = await statfs(workDir);
    const free = BigInt(info.bavail) * BigInt(info.bsize);
    if (free < BigInt(diskReserveBytes)) throw new UploadError('Yükleme için yeterli disk alanı kalmadı.', 507);
  };

  const appendTopic = async (slice, trailingNewline) => {
    const extra = slice.length + (trailingNewline ? 1 : 0);
    if (!extra) return;
    if (topicLength + extra > maxTopicBytes) throw new UploadError('Tek bir konu 64 kB sınırını aşıyor.', 413);
    if (slice.length) topicParts.push(Buffer.from(slice));
    if (trailingNewline) topicParts.push(Buffer.from([10]));
    topicLength += extra;
  };

  const finishTopic = async () => {
    const content = topicLength ? Buffer.concat(topicParts, topicLength) : Buffer.alloc(0);
    const hasContent = content.some(byte => byte !== 9 && byte !== 10 && byte !== 13 && byte !== 32);
    if (hasContent) {
      if (topics > 0) await writeChunk(output, Buffer.from('\n<veriayrimi>\n', 'utf8'));
      await writeChunk(output, content);
      payloadBytes += content.length;
      topics += 1;
    }
    topicParts = [];
    topicLength = 0;
  };

  const finishLine = async terminated => {
    const line = lineLength ? Buffer.concat(lineParts, lineLength) : Buffer.alloc(0);
    const comparable = line.length && line[line.length - 1] === 13 ? line.length - 1 : line.length;
    if (comparable === delimiter.length && line.subarray(0, comparable).equals(delimiter)) {
      await finishTopic();
    } else {
      let pos = 0;
      let at = line.indexOf(delimiter, pos);
      if (at < 0) {
        await appendTopic(line, terminated);
      } else {
        while (at >= 0) {
          if (at > pos) await appendTopic(line.subarray(pos, at), false);
          await finishTopic();
          pos = at + delimiter.length;
          at = line.indexOf(delimiter, pos);
        }
        if (pos < line.length || terminated) await appendTopic(line.subarray(pos), terminated);
      }
    }
    lineParts = [];
    lineLength = 0;
  };

  try {
    await ensureDisk();
    for await (const chunk of req) {
      sourceBytes += chunk.length;
      if (sourceBytes > maxUploadBytes) throw new UploadError(`Yükleme ${maxUploadBytes} bayt sınırını aşıyor.`, 413);
      if (sourceBytes - lastDiskCheck >= 64 * 1024 * 1024) {
        await ensureDisk();
        lastDiskCheck = sourceBytes;
      }
      if (chunk.includes(0)) throw new UploadError('TXT dosyası NUL karakteri içeremez.');
      try { decoder.decode(chunk, { stream: true }); } catch { throw new UploadError('Dosya geçerli UTF-8 metin değil.'); }
      let start = 0;
      while (start < chunk.length) {
        const newline = chunk.indexOf(10, start);
        if (newline < 0) {
          lineLength += chunk.length - start;
          lineParts.push(Buffer.from(chunk.subarray(start)));
          break;
        }
        lineLength += newline - start;
        if (newline > start) lineParts.push(Buffer.from(chunk.subarray(start, newline)));
        await finishLine(true);
        start = newline + 1;
      }
    }
    try { decoder.decode(); } catch { throw new UploadError('Dosya geçerli UTF-8 metin değil.'); }
    if (lineLength > 0) await finishLine(false);
    await finishTopic();
    if (!sourceBytes || !topics) throw new UploadError('TXT dosyasında `<veriayrimi>` ile ayrılmış konu bulunamadı.');
    if (topics < 2) throw new UploadError('Eğitim için en az 2 konu gerekir; tek konu ile anti-verbatim grafiği kurulamaz.');
    const memEstimate = 256n * 1024n * 1024n + BigInt(payloadBytes) * 8n;
    if (BigInt(freemem()) < memEstimate) throw new UploadError('Bu veri kümesi için kullanılabilir bellek yetersiz.', 507);
    output.end();
    await once(output, 'finish');
    return { sourceBytes, payloadBytes, topics };
  } catch (error) {
    output.destroy();
    await unlink(uploadTmp).catch(() => {});
    throw error;
  }
}

async function nextUserVersion() {
  const existing = await listFiles(checkpointsDir, /^user_v3_v(\d+)\.nv3g$/);
  return (existing[0]?.version || 0) + 1;
}

function currentProgress() {
  const job = trainingJob;
  if (!job) return null;
  let stage = job.stage;
  try {
    const frame = readFileSync(progressFile);
    if (frame.length === 24) {
      stage = Number(frame.readBigUInt64LE(0));
      job.stageTotal = Number(frame.readBigUInt64LE(8));
      job.stage = stage;
      job.bytesDone = Number(frame.readBigUInt64LE(16));
    }
  } catch {}
  const elapsedSeconds = Math.max(0, (Date.now() - job.startedAt) / 1000);
  const total = job.stageTotal || 100;
  const percent = job.status === 'completed'
    ? 100
    : Math.max(0, Math.min(99, Math.floor((stage / total) * 100)));
  const estimatedRemainingSeconds = percent > 0 && percent < 100
    ? Math.max(0, Math.ceil(elapsedSeconds / percent * (100 - percent)))
    : job.status === 'completed' ? 0 : null;
  return {
    jobId: job.id,
    status: job.status,
    version: job.version,
    stage,
    stageTotal: total,
    percent,
    topics: job.topics,
    payloadBytes: job.payloadBytes,
    sourceBytes: job.sourceBytes,
    elapsedSeconds: Number(elapsedSeconds.toFixed(1)),
    estimatedRemainingSeconds,
    error: job.error || null,
  };
}

async function runTrainingJob(corpusPath, version, job) {
  const stem = `user_v3_v${String(version).padStart(3, '0')}`;
  const npgOut = path.join(checkpointsDir, `${stem}.npg3`);
  const nv3gOut = path.join(checkpointsDir, `${stem}.nv3g`);
  const shardOut = path.join(userShardDir, stem);
  const stdin = `${corpusPath}\n${bridgeCorpus}\n${npgOut}\n${nv3gOut}\n${progressFile}\n${shardOut}\n`;
  job.stage = 0;
  job.stageTotal = 100;
  let stdout = '';
  if (await fileSize(TRAINER_NATIVE)) {
    stdout = (await spawnCapture(TRAINER_NATIVE, [], { input: stdin, timeoutMs: trainingTimeoutMs || undefined })).stdout;
  } else {
    stdout = (await spawnCapture(lir, ['run', '--backend=vm', TRAINER_LIR], { input: stdin, timeoutMs: trainingTimeoutMs || undefined })).stdout;
  }
  const values = Object.fromEntries(stdout.trim().split(/\r?\n/).slice(1).map(line => {
    const at = line.indexOf('=');
    return at > 0 ? [line.slice(0, at), line.slice(at + 1)] : [line, ''];
  }));
  if (values.ok !== '1') throw new Error(values.error || 'Eğitim süreci başarısız oldu.');
  if (values.anti_verbatim_audit_ok !== '1') throw new Error('Eğitim sonrası anti-verbatim denetimi başarısız; checkpoint yayınlanmadı.');
  const sizes = await Promise.all([fileSize(npgOut), fileSize(nv3gOut)]);
  if (!sizes[0] || !sizes[1]) throw new Error('Eğitim checkpoint çıktıları boş.');
  job.summary = {
    topics: Number(values.topics || 0),
    atoms: Number(values.atoms || 0),
    forbidden4Grams: Number(values.forbidden_4grams || 0),
    forbiddenSentences: Number(values.forbidden_sentences || 0),
    npgSteps: Number(values.npg_steps || 0),
    soaDocs: Number(values.soa_docs || 0),
    probeEmittedBytes: Number(values.probe_emitted_bytes || 0),
  };
  return { stem, npgOut, nv3gOut, shardOut };
}

async function startTraining(req, fileName, res) {
  if (trainingReserved) {
    req.resume();
    return jsonResponse(res, 409, { ok: false, error: 'Bir veri kümesi zaten eğitiliyor.' });
  }
  if (!fileName || !fileName.toLowerCase().endsWith('.txt')) {
    req.resume();
    return jsonResponse(res, 400, { ok: false, error: 'Yalnızca .txt dosyası yükleyin.' });
  }
  const safeFileName = path.basename(fileName);
  const declaredLength = Number(req.headers['content-length']);
  if (Number.isFinite(declaredLength) && declaredLength > maxUploadBytes) {
    req.resume();
    return jsonResponse(res, 413, { ok: false, error: `Yükleme ${maxUploadBytes} bayt sınırını aşıyor.` });
  }
  trainingReserved = true;
  await Promise.all([uploadTmp, progressFile].map(file => unlink(file).catch(() => {})));
  let corpus;
  try {
    corpus = await prepareUploadedCorpus(req);
  } catch (error) {
    trainingReserved = false;
    return jsonResponse(res, error instanceof UploadError ? error.status : 500, { ok: false, error: error.message || 'TXT yüklenemedi.' });
  }

  const version = await nextUserVersion();
  await writeFile(progressFile, Buffer.alloc(24), { flag: EXCL_NOFOLLOW, mode: 0o600 });
  const job = {
    id: randomUUID(),
    fileName: safeFileName,
    version,
    status: 'running',
    stage: 0,
    stageTotal: 100,
    topics: corpus.topics,
    payloadBytes: corpus.payloadBytes,
    sourceBytes: corpus.sourceBytes,
    startedAt: Date.now(),
    error: null,
    summary: null,
  };
  trainingJob = job;
  runTrainingJob(uploadTmp, version, job).then(async result => {
    job.stem = result.stem;
    job.status = 'completed';
    job.finishedAt = Date.now();
    await unlink(uploadTmp).catch(() => {});
  }).catch(async error => {
    job.status = 'failed';
    job.error = error.message || 'Eğitim başarısız.';
    job.finishedAt = Date.now();
    // Fail closed: a partially written checkpoint must never be selectable.
    const stem = `user_v3_v${String(version).padStart(3, '0')}`;
    await Promise.all([
      rm(path.join(checkpointsDir, `${stem}.npg3`), { force: true }),
      rm(path.join(checkpointsDir, `${stem}.nv3g`), { force: true }),
      rm(path.join(userShardDir, stem), { force: true, recursive: true }),
      unlink(uploadTmp).catch(() => {}),
    ]);
  }).finally(() => {
    trainingReserved = false;
  });

  return jsonResponse(res, 202, {
    ok: true,
    jobId: job.id,
    version,
    topics: corpus.topics,
    sourceBytes: corpus.sourceBytes,
    payloadBytes: corpus.payloadBytes,
    fileName: safeFileName,
  });
}

// ---------------------------------------------------------------------------------------------
// HTTP plumbing
// ---------------------------------------------------------------------------------------------

function send(res, status, body, type = 'application/json; charset=utf-8') {
  res.writeHead(status, {
    'content-type': type,
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'no-referrer',
    'x-frame-options': 'SAMEORIGIN',
  });
  res.end(body);
}

const jsonResponse = (res, status, data) => send(res, status, JSON.stringify(data));

async function readJsonBody(req, limit = 64 * 1024) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limit) throw Object.assign(new Error('İstek gövdesi çok büyük.'), { status: 413 });
    chunks.push(chunk);
  }
  if (!size) return {};
  try {
    return JSON.parse(Buffer.concat(chunks, size).toString('utf8'));
  } catch {
    throw Object.assign(new Error('Geçersiz JSON gövdesi.'), { status: 400 });
  }
}

const mime = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
};

// ---------------------------------------------------------------------------------------------
// artifact introspection: read the real headers out of the shipped binaries
// ---------------------------------------------------------------------------------------------

const NV3G_MAGIC = 3550861174880973654n;
const NPG_MAGIC0 = 1984385102;

async function readHeader(filePath, bytes) {
  try {
    const handle = await open(filePath, 'r');
    try {
      const buf = Buffer.alloc(bytes);
      const { bytesRead } = await handle.read(buf, 0, bytes, 0);
      return bytesRead === bytes ? buf : null;
    } finally {
      await handle.close();
    }
  } catch {
    return null;
  }
}

/// Parse the NV3G1 header exactly as `noema_v3_nv3g.lir` writes it (10 x u64).
async function readGraphHeader(filePath) {
  const buf = await readHeader(filePath, 80);
  if (!buf) return null;
  const magic = buf.readBigUInt64LE(0);
  if (magic !== NV3G_MAGIC) return null;
  const size = await fileSize(filePath);
  return {
    format: 'NV3G1',
    version: Number(buf.readBigUInt64LE(8)),
    atoms: Number(buf.readBigUInt64LE(16)),
    atomPoolBytes: Number(buf.readBigUInt64LE(24)),
    bigramCount: Number(buf.readBigUInt64LE(32)),
    trigramCount: Number(buf.readBigUInt64LE(40)),
    topics: Number(buf.readBigUInt64LE(48)),
    forbidden4Grams: Number(buf.readBigUInt64LE(56)),
    forbiddenSentences: Number(buf.readBigUInt64LE(64)),
    tfEntries: Number(buf.readBigUInt64LE(72)),
    bytes: size,
  };
}

/// Parse the NPG-v3 header exactly as `noema_v3_checkpoint.lir` writes it (11 x u64, 88 bytes).
async function readCheckpointHeader(filePath) {
  const buf = await readHeader(filePath, 88);
  if (!buf) return null;
  if (buf.readUInt32LE(0) !== NPG_MAGIC0) return null;
  const dtypeCode = Number(buf.readBigUInt64LE(24));
  const params = Number(buf.readBigUInt64LE(72));
  const elem = dtypeCode === 1 ? 8 : 4;
  const size = await fileSize(filePath);
  return {
    format: 'NPG-v3',
    schemaVersion: Number(buf.readBigUInt64LE(8)),
    dtype: dtypeCode === 1 ? 'f64' : 'f32',
    dtypeCode,
    archHash: buf.readBigUInt64LE(16).toString(16),
    dModel: Number(buf.readBigUInt64LE(32)),
    dK: Number(buf.readBigUInt64LE(40)),
    dH: Number(buf.readBigUInt64LE(48)),
    convK: Number(buf.readBigUInt64LE(56)),
    steps: Number(buf.readBigUInt64LE(64)),
    params,
    payloadBytes: params * elem,
    bytes: size,
    payloadChecksum: buf.readBigUInt64LE(80).toString(16),
  };
}

/// Count the real topics/docs in a `<veriayrimi>`-delimited training corpus.
async function readCorpusStats(filePath) {
  try {
    const text = await readFile(filePath, 'utf8');
    const topics = text.split('<veriayrimi>').map(part => part.trim()).filter(Boolean);
    const lines = text.split(/\r?\n/).filter(line => line.trim()).length;
    return {
      bytes: Buffer.byteLength(text, 'utf8'),
      topics: topics.length,
      lines,
      // Characters are a better size signal than bytes for Turkish text; both are reported so
      // the UI never has to guess.
      characters: text.length,
    };
  } catch {
    return null;
  }
}

async function artifactPayload() {
  const models = await describeModels();
  const v3 = models.find(model => model.id === 'noema_v3');
  const scaled = models.find(model => model.id === 'noema_v3_scaled');
  const [graph, checkpoint, scaledCheckpoint, corpus, bridgeCorpusStats, lockedTrain] = await Promise.all([
    v3 ? readGraphHeader(path.join(root, v3.graphPath)) : null,
    v3 ? readCheckpointHeader(path.join(root, v3.checkpointPath)) : null,
    scaled ? readCheckpointHeader(path.join(root, scaled.checkpointPath)) : null,
    readCorpusStats(path.join(root, 'ai/noema_v3/corpus_prod_foundation.tr.txt')),
    readCorpusStats(bridgeCorpus),
    readShardMeta(path.join(root, 'ai/noema_v3/corpus_locked/train_soa/shard_meta.json')),
  ]);
  return { ok: true, graph, checkpoint, scaledCheckpoint, corpus, bridgeCorpus: bridgeCorpusStats, lockedTrain };
}

async function readShardMeta(filePath) {
  try {
    const meta = JSON.parse(await readFile(filePath, 'utf8'));
    return {
      shardId: meta.shard_id ?? null,
      numDocs: meta.num_docs ?? null,
      numBytes: meta.num_bytes ?? null,
      version: meta.version ?? null,
    };
  } catch {
    return null;
  }
}

async function healthPayload() {
  const models = await describeModels();
  return {
    ok: true,
    engine: 'LIR · pure-LIR NOEMA v3',
    runtime: await fileSize(BACKEND_NATIVE) ? 'native-x86_64-o2' : 'vm',
    trainer: await fileSize(TRAINER_NATIVE) ? 'native-x86_64-o2' : 'vm',
    maxCorpusRun,
    outputModes: ['noema_v3_weight_generation', 'noema_v3_weight_generation_abstain'],
    // Clients switch on this contract instead of sniffing strings: every v3 reply carries one of
    // `outputModes`, while the isolated legacy exemplar path may only ever carry `legacy_mode`.
    output_mode_contract: {
      version: 2,
      v3: ['noema_v3_weight_generation', 'noema_v3_weight_generation_abstain'],
      legacy_mode: LEGACY_OUTPUT_MODE,
      legacy_selectors: LEGACY_MODELS.map(model => model.selector),
    },
    telemetry: { inference: inferenceTelemetry(), host: hostTelemetry() },
    guarantees: {
      antiVerbatim: 'No response may reproduce more than 4 consecutive corpus atoms; violations are repaired or abstained.',
      grounding: 'Synthesis requires a topical content stem, a KHG-verified claim, or prompt-intent greeting.',
      abstention: 'Zero bytes are emitted when evidence is insufficient or a prompt-injection is detected.',
      determinism: 'Identical prompt + checkpoint => byte-identical response.',
    },
    models,
  };
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || '/', 'http://localhost');
  try {
    // ── Abuse gates (Issue #4) ─────────────────────────────────────────────
    // Per-IP fixed-window rate limit on every /api route; the CPU-spawning
    // endpoints (chat/train) additionally require a session cookie or the
    // bearer token. Pre-fix, 40 back-to-back unauthenticated POSTs all
    // returned 200 and each spawned an unbounded inference subprocess.
    const ip = req.socket.remoteAddress || 'unknown';
    const isApi = url.pathname.startsWith('/api/');
    const isTrainApi = url.pathname === '/api/train' || url.pathname === '/api/train/status';
    const isChatApi = url.pathname === '/api/chat';
    if (isApi) {
      const routeClass = isTrainApi ? 'train' : isChatApi ? 'chat' : 'api';
      const limit = isTrainApi ? rateTrainPerWindow : isChatApi ? rateChatPerWindow : rateApiPerWindow;
      if (!rateAllow(`${ip} ${routeClass}`, limit)) {
        if (req.method === 'POST' || req.method === 'PUT') req.resume();
        res.setHeader('retry-after', String(Math.ceil(rateWindowMs / 1000)));
        return jsonResponse(res, 429, { ok: false, error: 'Çok fazla istek; bir dakika sonra tekrar deneyin.' });
      }
    }
    if ((isChatApi || isTrainApi) && !isAuthorized(req)) {
      if (req.method === 'POST' || req.method === 'PUT') req.resume();
      res.setHeader('www-authenticate', 'Bearer');
      return jsonResponse(res, 401, { ok: false, error: 'Yetkilendirme gerekli: UI üzerinden tarayıcı oturumu veya NOEMA_CHAT_TOKEN ile Bearer token.' });
    }
    if (req.method === 'GET' && url.pathname === '/api/health') {
      return jsonResponse(res, 200, await healthPayload());
    }
    if (req.method === 'GET' && url.pathname === '/api/artifacts') {
      return jsonResponse(res, 200, await artifactPayload());
    }
    if (req.method === 'GET' && url.pathname === '/api/telemetry') {
      return jsonResponse(res, 200, { ok: true, inference: inferenceTelemetry(), host: hostTelemetry() });
    }
    if (req.method === 'GET' && url.pathname === '/api/models') {
      return jsonResponse(res, 200, { ok: true, models: await describeModels() });
    }
    if (req.method === 'POST' && url.pathname === '/api/chat') {
      const body = await readJsonBody(req);
      const message = typeof body.message === 'string' ? body.message : '';
      if (!message.trim()) return jsonResponse(res, 400, { ok: false, error: 'Bir mesaj yazın.' });
      if (Buffer.byteLength(message, 'utf8') > 2048) return jsonResponse(res, 413, { ok: false, error: 'Mesaj 2048 bayt sınırını aşıyor.' });
      const selector = typeof body.selector === 'string' ? body.selector : (typeof body.modelId === 'string' ? body.modelId : 'noema_v3');
      // activeRuns was already tracked for telemetry; it now also caps
      // concurrency so a burst of clients cannot fan out into unbounded
      // subprocess spawns.
      if (activeRuns >= maxConcurrentRuns) {
        res.setHeader('retry-after', '5');
        return jsonResponse(res, 429, { ok: false, error: 'Sunucu meşgul: eşzamanlı çalıştırma sınırı aşıldı.' });
      }
      const started = Date.now();
      let run;
      try {
        run = await runChat(selector, message);
      } catch (error) {
        inferenceStats.errors += 1;
        throw error;
      }
      const { model, envelope } = run;
      return jsonResponse(res, 200, {
        ok: true,
        model: { id: model.id, label: model.label, checkpointPath: model.checkpointPath, graphPath: model.graphPath },
        metrics: { ...envelope, latencyMs: envelope.latencyMs ?? Date.now() - started },
      });
    }
    if (req.method === 'POST' && url.pathname === '/api/train') {
      let fileName = '';
      try { fileName = decodeURIComponent(req.headers['x-file-name'] || ''); } catch {
        req.resume();
        return jsonResponse(res, 400, { ok: false, error: 'Dosya adı geçersiz.' });
      }
      return await startTraining(req, fileName, res);
    }
    if (req.method === 'GET' && url.pathname === '/api/train/status') {
      if (!trainingJob || url.searchParams.get('jobId') !== trainingJob.id) {
        return jsonResponse(res, 404, { ok: false, error: 'Eğitim işi bulunamadı.' });
      }
      const progress = currentProgress();
      let model = null;
      if (trainingJob.status === 'completed') {
        model = (await describeModels()).find(item => item.id === trainingJob.stem) || null;
      }
      return jsonResponse(res, 200, { ok: true, ...progress, summary: trainingJob.summary, model });
    }
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      return jsonResponse(res, 405, { ok: false, error: 'Method not allowed' });
    }
    const route = url.pathname === '/pretraining' ? '/pretraining.html'
      : url.pathname === '/system' ? '/system.html'
        : url.pathname === '/chat' ? '/index.html'
          : url.pathname === '/' ? '/index.html' : decodeURIComponent(url.pathname);
    const safe = path.resolve(here, `.${route}`);
    if (!safe.startsWith(`${here}${path.sep}`)) return send(res, 404, 'Not found', 'text/plain; charset=utf-8');
    const data = await readFile(safe);
    const staticHeaders = {
      'content-type': mime[path.extname(safe)] || 'application/octet-stream',
      'cache-control': 'no-cache',
      'x-content-type-options': 'nosniff',
      'x-frame-options': 'SAMEORIGIN',
      // `style-src 'self'` is deliberately strict: it rejects inline `style=` attributes *and*
      // silently ignores `element.style.prop = ...` (see setFill in app.js). Bar geometry and
      // textarea autosize therefore travel as custom properties set through CSSStyleDeclaration,
      // which this policy permits. Keep it that way — loosening to 'unsafe-inline' would let any
      // injected attribute through.
      'content-security-policy': "default-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'self'; frame-ancestors 'self'",
    };
    // Hand the browser its session cookie when it loads the UI, so the
    // existing frontend satisfies the auth gate with zero client changes.
    // HttpOnly: no script can read it; SameSite=Strict: never sent on
    // cross-site requests (CSRF).
    if (authEnabled && req.method === 'GET' && !sessionToken(req)) {
      staticHeaders['set-cookie'] = `noema_session=${issueSession()}; HttpOnly; SameSite=Strict; Path=/; Max-Age=86400`;
    }
    res.writeHead(200, staticHeaders);
    if (req.method === 'HEAD') return res.end();
    return res.end(data);
  } catch (error) {
    // A LIR exit caused by an unresolvable selector is the caller's mistake, not ours: report
    // it as a bad request with a message that names the value, instead of an opaque 500.
    if (/LIR çıkış kodu/i.test(error.message || '')) {
      return jsonResponse(res, 400, { ok: false, error: `Model çalıştırılamadı: ${error.message}` });
    }
    const status = error.status || 500;
    return jsonResponse(res, status, { ok: false, error: error.message || 'İstek işlenemedi.' });
  }
});

server.listen(port, HOST, () => {
  console.log(`NOEMA Chat listening on ${HOST}:${port}`);
  if (!['127.0.0.1', 'localhost', '::1'].includes(HOST)) {
    console.warn(`WARNING: NOEMA_CHAT_HOST=${HOST} exposes the service beyond loopback; rate limits and auth are the only protection.`);
  }
  console.log(`NOEMA v3 backend: ${BACKEND_NATIVE} (fallback LIR: ${BACKEND_LIR})`);
  console.log(`NOEMA v3 trainer: ${TRAINER_NATIVE} (fallback LIR: ${TRAINER_LIR})`);
  console.log(`auth: ${authEnabled ? (bearerToken ? 'session cookie + bearer token' : 'session cookie (UI); set NOEMA_CHAT_TOKEN for non-browser API clients') : 'DISABLED via NOEMA_CHAT_AUTH=off'}`);
  console.log(`limits: chat ${rateChatPerWindow}/min, train ${rateTrainPerWindow}/min, api ${rateApiPerWindow}/min, concurrent runs ${maxConcurrentRuns}, upload cap ${maxUploadBytes} bytes, train timeout ${trainingTimeoutMs === 0 ? 'unlimited (explicit)' : `${trainingTimeoutMs}ms`}`);
  console.log(`private work dir: ${workDir} (mode 0700, removed on exit)`);
});
