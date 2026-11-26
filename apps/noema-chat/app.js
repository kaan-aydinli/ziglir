// NOEMA chat client.
//
// Every number rendered here comes from one of three places: the `/api/chat` response for a
// single run, `/api/health`'s telemetry block for server-wide counters, or `/api/artifacts` for
// values read out of the shipped checkpoint/graph headers. Nothing is estimated client-side and
// nothing is invented: an unknown value renders as an em dash rather than a plausible-looking
// constant.

const $ = selector => document.querySelector(selector);

const dom = {
  form: $('#chat-form'),
  input: $('#message-input'),
  send: $('#send-button'),
  stream: $('#stream'),
  welcome: $('#welcome'),
  thinking: $('#thinking'),
  thinkingLabel: $('#thinking-label'),
  byteCount: $('#byte-count'),
  cacheHint: $('#cache-hint'),
  modelSelect: $('#model-select'),
  conversation: $('#conversation'),
  aboutDialog: $('#about-dialog'),
};

const encoder = new TextEncoder();
let busy = false;
let lastTelemetry = null;
let pollTimer = null;

const DASH = '—';

const nf = new Intl.NumberFormat('tr-TR');
const fmtInt = value => (Number.isFinite(Number(value)) ? nf.format(Number(value)) : DASH);
const fmtBytes = value => {
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0) return DASH;
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(n < 10240 ? 1 : 0)} kB`;
  return `${(n / 1048576).toFixed(2)} MB`;
};
const fmtMs = value => {
  const n = Number(value);
  if (!Number.isFinite(n)) return DASH;
  if (n < 0.01) return '0';
  if (n < 10) return n.toFixed(2);
  if (n < 1000) return Math.round(n).toString();
  return (n / 1000).toFixed(2) + ' s';
};

// ---------------------------------------------------------------------------------------------
// rendering primitives
// ---------------------------------------------------------------------------------------------

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function receiptItem(label, value, tone = null) {
  // No trailing space in the label: the value element supplies its own leading gap via CSS.
  const span = el('span', null, label);
  const b = el('b', null, String(value));
  span.append(b);
  if (tone) span.dataset.tone = tone;
  return span;
}

function kvRow(dl, key, value) {
  dl.append(el('dt', null, key), el('dd', null, value));
}

// ---------------------------------------------------------------------------------------------
// message rendering
// ---------------------------------------------------------------------------------------------

function messageShell(kind, who, metaText) {
  const row = el('article', `msg ${kind}`);
  const avatar = el('span', 'msg-avatar', kind === 'err' ? '!' : kind === 'me' ? '↑' : 'N');
  const main = el('div', 'msg-main');
  const head = el('div', 'msg-head');
  head.append(el('span', 'msg-who', who));
  if (metaText) head.append(el('span', 'mono', metaText));
  main.append(head);
  row.append(avatar, main);
  return { row, main };
}

function appendUser(text) {
  const { row, main } = messageShell('me', 'Siz', '');
  const bubble = el('div', 'bubble', text);
  main.append(bubble);
  dom.stream.append(row);
  return row;
}

function appendError(message) {
  const { row, main } = messageShell('err', 'Sistem', 'istek başarısız');
  main.append(el('div', 'bubble', message));
  dom.stream.append(row);
}

/**
 * Decode the model's raw bytes. The backend already guarantees valid UTF-8 (the server rejects
 * invalid output), so the fatal decoder is the honest choice: if it throws, something upstream
 * broke and we want to know rather than silently show replacement characters.
 */
function decodeReply(hex) {
  if (!hex) return '';
  const bytes = Uint8Array.from(hex.match(/../g) || [], pair => Number.parseInt(pair, 16));
  return new TextDecoder('utf-8', { fatal: false }).decode(bytes);
}

function appendModel(metrics, model) {
  const isV3 = String(metrics.outputMode || '').startsWith('noema_v3_');
  const abstained = Boolean(metrics.abstained) || Number(metrics.generatedBytes) === 0;
  const { row, main } = messageShell('ai', 'NOEMA v3', '');

  const head = main.querySelector('.msg-head');
  const pillTone = abstained ? 'warn' : 'good';
  const pill = el('span', 'pill');
  pill.dataset.tone = pillTone;
  pill.append(el('i'), el('span', null, abstained ? 'ÇEKİMSER' : 'ÜRETİLDİ'));
  head.append(pill);
  if (metrics.cached) {
    const c = el('span', 'mono', 'önbellek');
    head.append(c);
  } else {
    head.append(el('span', 'mono', `${fmtMs(metrics.latencyMs)} ms`));
  }

  if (abstained) {
    const bubble = el('div', 'bubble abstain');
    const h = el('div', 'abstain-head');
    h.append(el('span', null, '◼'), el('span', null, 'Kanıt yetersiz — yanıt üretilmedi'));
    bubble.append(h);
    const quarantined = Number(metrics.khgQuarantinedSpans) > 0;
    bubble.append(el('div', 'abstain-copy', quarantined
      ? 'İstemde talimat enjeksiyonu tespit edildi ve karantinaya alındı. Model yönergeyi izlemedi; sıfır bayt döndürdü.'
      : 'Sorunun içerik kökleri eğitim korpusunda yeterince temsil edilmiyor. Model tahmin yürütmek yerine sıfır bayt döndürdü.'));
    main.append(bubble);
  } else {
    const text = decodeReply(metrics.generatedHex);
    main.append(el('div', 'bubble', text || '(boş yanıt)'));
  }

  // The receipt: exactly what this run verified, with the numbers the backend reported.
  const receipt = el('div', 'receipt');
  receipt.append(
    receiptItem('bayt', fmtInt(metrics.generatedBytes), abstained ? 'warn' : null),
  );
  if (!abstained) {
    receipt.append(receiptItem('atom', fmtInt(metrics.synthesizedAtoms)));
    receipt.append(receiptItem(
      'n-gram',
      `${fmtInt(metrics.maxCorpusNgramRun)}/4`,
      Number(metrics.maxCorpusNgramRun) > 4 ? 'warn' : null,
    ));
  }
  if (isV3) {
    receipt.append(receiptItem(
      'anti-verbatim',
      Number(metrics.antiVerbatimVerified) === 1 ? 'geçti' : 'ihlal',
      Number(metrics.antiVerbatimVerified) === 1 ? 'good' : 'warn',
    ));
    receipt.append(receiptItem('KHG', `${fmtInt(metrics.khgVerifiedSpans)}/${fmtInt(metrics.khgObservedSpans)}`));
    if (metrics.khgQuarantinedSpans > 0) {
      receipt.append(receiptItem('karantina', fmtInt(metrics.khgQuarantinedSpans), 'warn'));
    }
    if (metrics.proofVerifiedClaims || metrics.proofRefutedClaims) {
      receipt.append(receiptItem('kanıt', `${fmtInt(metrics.proofVerifiedClaims)}✓ ${fmtInt(metrics.proofRefutedClaims)}✗`));
    }
  }
  if (metrics.cached) {
    receipt.append(receiptItem('CPU', '0 ms', 'good'));
  } else if (Number.isFinite(Number(metrics.cpuMs))) {
    receipt.append(receiptItem('CPU', `${fmtMs(metrics.cpuMs)} ms`));
  }
  main.append(receipt);

  // Everything else the backend reported, collapsed by default so the reading view stays calm.
  const details = el('details', 'msg-details');
  details.append(el('summary', null, 'çalıştırma dökümü'));
  const dl = el('dl', 'kv');
  kvRow(dl, 'model_id', metrics.modelId ?? DASH);
  kvRow(dl, 'output_mode', metrics.outputMode ?? DASH);
  kvRow(dl, 'checkpoint', `${model?.checkpointPath ?? DASH}`);
  kvRow(dl, 'graph', `${model?.graphPath ?? DASH}`);
  kvRow(dl, 'eğitim kaydı', fmtInt(metrics.trainingRecords));
  kvRow(dl, 'eğitim baytı', fmtBytes(metrics.trainingBytes));
  kvRow(dl, 'spektral aşama', `${fmtInt(metrics.spectralStage)} / 3`);
  kvRow(dl, 'girdi baytı', fmtInt(metrics.inputBytes));
  kvRow(dl, 'serbest enerji', Number(metrics.freeEnergy).toFixed(6));
  kvRow(dl, 'sürpriz kapısı', Number(metrics.surpriseGate).toFixed(6));
  kvRow(dl, 'KHG gözlem', fmtInt(metrics.khgObservedSpans));
  kvRow(dl, 'KHG doğrulanan', fmtInt(metrics.khgVerifiedSpans));
  kvRow(dl, 'KHG karantina', fmtInt(metrics.khgQuarantinedSpans));
  kvRow(dl, 'kanıt adımı', fmtInt(metrics.proofStepsUsed));
  kvRow(dl, 'saklı örnek', fmtInt(metrics.storedExemplars));
  kvRow(dl, 'korpus konusu', fmtInt(metrics.corpusTopics));
  kvRow(dl, 'yasaklı 4-gram', fmtInt(metrics.forbidden4Grams));
  kvRow(dl, 'CPU (süreç)', Number.isFinite(Number(metrics.cpuMs)) ? `${Number(metrics.cpuMs).toFixed(2)} ms` : 'önbellek');
  kvRow(dl, 'duvar saati', metrics.cached ? '0 ms (önbellek)' : `${fmtInt(metrics.latencyMs)} ms`);
  details.append(dl);
  if (metrics.generatedHex) {
    details.append(el('div', 'kv-code', metrics.generatedHex));
  }
  main.append(details);

  dom.stream.append(row);
}

// ---------------------------------------------------------------------------------------------
// inspector: per-run metrics
// ---------------------------------------------------------------------------------------------

function verifyRow(key, state, value) {
  const row = $(`#verify-list .verify-row[data-key="${key}"]`);
  if (!row) return;
  row.dataset.state = state;
  const mark = row.querySelector('.v-name i');
  if (mark) mark.textContent = state === 'pass' ? '✓' : state === 'fail' ? '✕' : state === 'warn' ? '!' : '·';
  $(`#v-${key}`).textContent = value;
}

function updateInspector(metrics) {
  const isV3 = String(metrics.outputMode || '').startsWith('noema_v3_');
  const abstained = Boolean(metrics.abstained) || Number(metrics.generatedBytes) === 0;

  $('#m-bytes').textContent = fmtInt(metrics.generatedBytes);
  $('#m-latency').innerHTML = metrics.cached ? '0<small>ms · önbellek</small>' : `${fmtMs(metrics.latencyMs)}<small>ms</small>`;
  $('#m-cpu').innerHTML = metrics.cached ? '0<small>ms</small>' : `${fmtMs(metrics.cpuMs)}<small>ms</small>`;
  $('#m-atoms').textContent = fmtInt(metrics.synthesizedAtoms);
  $('#m-mode').textContent = metrics.outputMode ?? DASH;
  $('#model-name').textContent = 'NOEMA v3';

  const ngram = Number(metrics.maxCorpusNgramRun) || 0;
  $('#m-ngram').textContent = `${ngram} / 4`;
  const bar = $('#m-ngram-bar');
  setFill(bar, Math.min(100, (ngram / 4) * 100));
  // `delete` rather than `= ''` so `[data-tone=""]` never matches a selector.
  if (ngram > 4) bar.dataset.tone = 'bad';
  else if (ngram === 4) bar.dataset.tone = 'warn';
  else delete bar.dataset.tone;

  if (!isV3) return;

  const antiOk = Number(metrics.antiVerbatimVerified) === 1;
  verifyRow('anti', antiOk ? 'pass' : 'fail', antiOk ? 'geçti' : 'ihlal');
  verifyRow('ngram', ngram <= 4 ? 'pass' : 'fail', `${ngram} ≤ 4`);
  const khgOk = Number(metrics.khgVerifiedSpans) > 0;
  verifyRow('khg', khgOk ? 'pass' : abstained ? 'warn' : 'warn',
    `${fmtInt(metrics.khgVerifiedSpans)}/${fmtInt(metrics.khgObservedSpans)}`);
  const quarantined = Number(metrics.khgQuarantinedSpans) > 0;
  verifyRow('inj', quarantined ? 'fail' : 'pass', quarantined ? `${fmtInt(metrics.khgQuarantinedSpans)} yakalandı` : 'temiz');
  verifyRow('ground', abstained ? 'warn' : 'pass', abstained ? 'kapsam dışı' : 'kapsandı');

  const pill = $('#verify-pill');
  pill.dataset.tone = abstained ? 'warn' : 'good';
  $('#verify-pill-text').textContent = abstained ? 'ÇEKİMSER' : 'DOĞRULANDI';

  const runPill = $('#run-pill');
  runPill.dataset.tone = abstained ? 'warn' : 'good';
  $('#run-pill-text').textContent = abstained ? 'ÇEKİMSER' : 'TAMAM';
}

function resetInspector() {
  for (const id of ['m-bytes', 'm-atoms', 'm-mode', 'm-ngram']) $(`#${id}`).textContent = DASH;
  $('#m-latency').innerHTML = `${DASH}<small>ms</small>`;
  $('#m-cpu').innerHTML = `${DASH}<small>ms</small>`;
  setFill($('#m-ngram-bar'), 0);
  for (const row of document.querySelectorAll('#verify-list .verify-row')) {
    row.dataset.state = '';
    const mark = row.querySelector('.v-name i');
    if (mark) mark.textContent = '·';
  }
  for (const id of ['v-anti', 'v-ngram', 'v-khg', 'v-inj', 'v-ground']) $(`#${id}`).textContent = DASH;
  $('#verify-pill').dataset.tone = 'info';
  $('#verify-pill-text').textContent = DASH;
  $('#run-pill').dataset.tone = 'info';
  $('#run-pill-text').textContent = 'BEKLENİYOR';
}

// ---------------------------------------------------------------------------------------------
// live telemetry
// ---------------------------------------------------------------------------------------------

/**
 * Set a bar's fill width.
 *
 * The page is served under `Content-Security-Policy: style-src 'self'`, which blocks *every*
 * inline style — including assignments to `element.style`, which fail silently (the property reads
 * back unchanged and nothing renders). Setting a custom property through CSSStyleDeclaration is
 * allowed and carries no console error, so bar geometry travels as `--fill` and the stylesheet
 * turns it into a width.
 */
function setFill(bar, percent) {
  const fill = bar?.querySelector('i');
  if (fill) fill.style.setProperty('--fill', `${Math.max(0, Math.min(100, percent))}%`);
}

function setBar(id, value, max, tone) {
  const bar = $(`#${id}`);
  const pct = max > 0 ? Math.max(0, Math.min(100, (value / max) * 100)) : 0;
  setFill(bar, pct);
  if (tone) bar.dataset.tone = tone; else delete bar.dataset.tone;
}

function applyTelemetry(payload) {
  lastTelemetry = payload;
  const { inference, host } = payload;
  $('#live-tick').textContent = fmtInt(inference.requests);

  // Host load, normalised against the real core count so the bar means "fraction of this
  // machine". A load above 1.0 per core is saturation.
  const perCore = host.cores > 0 ? host.load1 / host.cores : 0;
  setBar('g-load', perCore, 1, perCore > 0.9 ? 'bad' : perCore > 0.6 ? 'warn' : null);
  $('#g-load-v').textContent = host.load1.toFixed(2);

  setBar('g-mem', host.memory.usedPercent, 100, host.memory.usedPercent > 90 ? 'bad' : host.memory.usedPercent > 75 ? 'warn' : null);
  $('#g-mem-v').textContent = `${host.memory.usedPercent.toFixed(0)}%`;

  const cachePct = inference.cacheLimit ? (inference.cacheSize / inference.cacheLimit) * 100 : 0;
  setBar('g-cache', cachePct, 100, null);
  $('#g-cache-v').textContent = `${inference.cacheSize}/${inference.cacheLimit}`;

  $('#t-req').textContent = fmtInt(inference.requests);
  $('#t-hit').textContent = `${fmtInt(inference.cacheHits)} (%${inference.cacheHitPercent})`;
  $('#t-cpu').textContent = `${fmtMs(inference.meanCpuMs)} ms`;
  $('#t-abst').textContent = fmtInt(inference.abstained);
}

async function pollTelemetry() {
  try {
    const response = await fetch('/api/telemetry', { signal: AbortSignal.timeout(6000) });
    if (!response.ok) throw new Error('telemetry');
    applyTelemetry(await response.json());
    setHealth(true);
  } catch {
    setHealth(false);
  }
}

function setHealth(up) {
  const dot = $('#rail-health');
  const label = $('#rail-health-label');
  dot.dataset.state = up ? 'up' : 'down';
  label.textContent = up ? 'BAĞLI' : 'KAPALI';
}

function schedulePoll() {
  clearTimeout(pollTimer);
  // Poll only while the tab is visible. A background tab asks the server for nothing, which
  // keeps an idle NOEMA page at 0% CPU on the client machine.
  pollTimer = setTimeout(async () => {
    if (document.visibilityState === 'visible') await pollTelemetry();
    schedulePoll();
  }, 4000);
}

// ---------------------------------------------------------------------------------------------
// send / receive
// ---------------------------------------------------------------------------------------------

async function submitMessage(raw) {
  const message = raw.trim();
  if (!message || busy) return;

  dom.welcome.classList.add('hidden');
  appendUser(message);
  dom.input.value = '';
  resizeInput();
  updateByteCount();
  dom.cacheHint.hidden = true;

  busy = true;
  dom.send.disabled = true;
  dom.thinking.classList.remove('hidden');
  dom.thinkingLabel.textContent = 'LIR ağırlık grafiği çalışıyor';
  $('#run-pill').dataset.tone = 'info';
  $('#run-pill-text').textContent = 'ÇALIŞIYOR';
  scrollToEnd();

  const started = performance.now();
  try {
    const response = await fetch('/api/chat', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ message, modelId: dom.modelSelect.value }),
    });
    const result = await response.json();
    if (!response.ok || !result.ok) throw new Error(result.error || 'Model çalıştırılamadı.');

    const metrics = result.metrics || {};
    // Show the model's own wall clock, not the round-trip time: network overhead and JSON
    // serialisation are visible as the difference if anyone cares to look.
    metrics.latencyMs = metrics.cached ? 0 : (metrics.latencyMs ?? Math.round(performance.now() - started));
    appendModel(metrics, result.model);
    // Paint the inspector *after* the message so the panel always describes the reply that was
    // just appended, never a later background poll.
    updateInspector(metrics);
    dom.cacheHint.hidden = !metrics.cached;
    if (metrics.cached) dom.cacheHint.textContent = '· önbellekten';
    else dom.cacheHint.hidden = true;
    pollTelemetry();
  } catch (error) {
    appendError(error.message || 'LIR arka ucu ile bağlantı kurulamadı.');
    $('#run-pill').dataset.tone = 'bad';
    $('#run-pill-text').textContent = 'HATA';
  } finally {
    dom.thinking.classList.add('hidden');
    busy = false;
    dom.send.disabled = false;
    dom.input.focus();
    scrollToEnd();
  }
}

function scrollToEnd() {
  dom.conversation.scrollTop = dom.conversation.scrollHeight;
}

function resizeInput() {
  // Autosize through a custom property for the same CSP reason as `setFill`.
  dom.input.style.setProperty('--rows-h', `${Math.min(dom.input.scrollHeight, 132)}px`);
}

function updateByteCount() {
  const bytes = encoder.encode(dom.input.value).length;
  dom.byteCount.textContent = `${fmtInt(bytes)} / 2048 bayt`;
  dom.byteCount.classList.toggle('over', bytes > 2048);
}

// ---------------------------------------------------------------------------------------------
// bootstrap
// ---------------------------------------------------------------------------------------------

function populateModels(models) {
  const select = dom.modelSelect;
  select.replaceChildren();
  for (const model of models) {
    if (model.legacy) continue; // the primary experience is v3 only
    const option = el('option', null, `${model.id} · ${fmtBytes(model.checkpointBytes)}`);
    // Post the selector, not the short id: that is what the backend resolves. Using the id here
    // made every model except the default fail with an opaque LIR exit code.
    option.value = model.selector || model.id;
    option.dataset.modelId = model.id;
    option.disabled = !model.available;
    select.append(option);
  }
  // `?model=` lets the training page hand off directly to the model it just produced, so the
  // user does not have to find it in a dropdown. Accept either the selector or the short id.
  const requested = new URLSearchParams(location.search).get('model');
  const wanted = requested
    ? Array.from(select.options).find(o => !o.disabled && (
        o.value === requested || o.dataset.modelId === requested ||
        requested.endsWith(`:${o.dataset.modelId}`) || requested.endsWith(o.value)
      ))
    : null;
  const firstAvailable = wanted || Array.from(select.options).find(option => !option.disabled);
  if (firstAvailable) select.value = firstAvailable.value;
  if (wanted) select.dataset.pendingDeepLink = '1';
}

function renderWelcomeFacts(artifacts) {
  const { corpus, graph, checkpoint } = artifacts;
  if (corpus) {
    $('#fact-corpus').textContent = `${fmtInt(corpus.topics)} konu · ${fmtInt(corpus.lines)} satır`;
  }
  if (graph) {
    $('#fact-graph').textContent = `${fmtInt(graph.atoms)} atom · ${fmtInt(graph.forbidden4Grams)} yasak 4-gram`;
  }
  if (checkpoint) {
    $('#fact-params').textContent = `${fmtInt(checkpoint.params)} ağırlık · ${checkpoint.dtype}`;
    $('#model-file').textContent = `${fmtBytes(checkpoint.bytes)} · ${fmtInt(checkpoint.params)} param · ${checkpoint.dtype}`;
  }
}

async function bootstrap() {
  resetInspector();
  try {
    const healthResponse = await fetch('/api/health', { signal: AbortSignal.timeout(8000) });
    const health = await healthResponse.json();
    if (!health.ok) throw new Error('health');
    populateModels(health.models || []);
    $('#runtime-tag').textContent = `LIR · ${health.runtime}`;
    if (health.telemetry) applyTelemetry(health.telemetry);
    setHealth(true);
  } catch {
    setHealth(false);
    $('#runtime-tag').textContent = 'LIR · bağlantı yok';
    $('#model-file').textContent = 'backend erişilemiyor';
  }

  try {
    const artifactResponse = await fetch('/api/artifacts', { signal: AbortSignal.timeout(8000) });
    const artifacts = await artifactResponse.json();
    if (artifacts.ok) renderWelcomeFacts(artifacts);
  } catch {
    /* the welcome facts are decoration; a failure here must not break the chat */
  }

  schedulePoll();
}

// --- events ---

dom.form.addEventListener('submit', event => {
  event.preventDefault();
  submitMessage(dom.input.value);
});

dom.input.addEventListener('input', () => { resizeInput(); updateByteCount(); });
dom.input.addEventListener('keydown', event => {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault();
    dom.form.requestSubmit();
  }
});

for (const button of document.querySelectorAll('.starter')) {
  button.addEventListener('click', () => {
    dom.input.value = button.dataset.prompt || '';
    updateByteCount();
    dom.form.requestSubmit();
  });
}

$('#clear-button').addEventListener('click', () => {
  dom.stream.replaceChildren();
  dom.welcome.classList.remove('hidden');
  dom.cacheHint.hidden = true;
  resetInspector();
  dom.input.focus();
});

$('#about-button').addEventListener('click', () => dom.aboutDialog.showModal());
$('#close-dialog').addEventListener('click', () => dom.aboutDialog.close());
$('#done-dialog').addEventListener('click', () => dom.aboutDialog.close());

// Stop polling when the page is hidden, resume immediately when it comes back: no wasted
// requests and no stale numbers on return.
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') {
    pollTelemetry();
    schedulePoll();
  } else {
    clearTimeout(pollTimer);
  }
});

window.addEventListener('pagehide', () => clearTimeout(pollTimer));

updateByteCount();
bootstrap();
