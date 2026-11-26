// System page: renders the real headers of the shipped artifacts and the live server counters.
// Every row is produced from an API field; a missing field renders as an em dash so a broken
// backend shows up as `—` instead of a stale or invented number.

const $ = selector => document.querySelector(selector);

const DASH = '—';
const nf = new Intl.NumberFormat('tr-TR');
const fmtInt = v => (Number.isFinite(Number(v)) ? nf.format(Number(v)) : DASH);
const fmtBytes = v => {
  const n = Number(v);
  if (!Number.isFinite(n) || n < 0) return DASH;
  if (n < 1024) return `${n} B`;
  if (n < 1048576) return `${(n / 1024).toFixed(n < 10240 ? 1 : 0)} kB`;
  return `${(n / 1048576).toFixed(2)} MB`;
};
const fmtMs = v => {
  const n = Number(v);
  if (!Number.isFinite(n)) return DASH;
  if (n < 0.01) return '0 ms';
  if (n < 1000) return `${n < 10 ? n.toFixed(2) : Math.round(n)} ms`;
  return `${(n / 1000).toFixed(2)} s`;
};
const fmtDuration = seconds => {
  const s = Math.floor(Number(seconds) || 0);
  if (s < 60) return `${s} sn`;
  if (s < 3600) return `${Math.floor(s / 60)} dk ${s % 60} sn`;
  const h = Math.floor(s / 3600);
  return `${h} sa ${Math.floor((s % 3600) / 60)} dk`;
};

function rows(tbodyId, pairs) {
  const body = $(`#${tbodyId}`);
  body.replaceChildren();
  for (const [key, value] of pairs) {
    const tr = document.createElement('tr');
    const td1 = document.createElement('td');
    td1.textContent = key;
    const td2 = document.createElement('td');
    td2.textContent = value === undefined || value === null ? DASH : String(value);
    tr.append(td1, td2);
    body.append(tr);
  }
}

function setBar(id, ratio, tone) {
  const bar = $(`#${id}`);
  const pct = Math.max(0, Math.min(100, (Number(ratio) || 0) * 100));
  bar.querySelector('i').style.width = `${pct}%`;
  if (tone) bar.dataset.tone = tone; else delete bar.dataset.tone;
}

function setPill(id, tone, text) {
  const pill = $(`#${id}`);
  pill.dataset.tone = tone;
  pill.querySelector('span').textContent = text;
}

function setHealth(up) {
  const dot = $('#rail-health');
  dot.dataset.state = up ? 'up' : 'down';
  $('#rail-health-label').textContent = up ? 'BAĞLI' : 'KAPALI';
}

// ---------------------------------------------------------------------------------------------

function renderArtifacts(a) {
  const { graph, checkpoint, scaledCheckpoint, corpus, bridgeCorpus, lockedTrain } = a;

  if (graph) {
    setPill('graph-pill', 'good', graph.format);
    rows('graph-rows', [
      ['format', graph.format],
      ['sürüm', graph.version],
      ['atom', fmtInt(graph.atoms)],
      ['atom havuzu', fmtBytes(graph.atomPoolBytes)],
      ['bigram', fmtInt(graph.bigramCount)],
      ['trigram', fmtInt(graph.trigramCount)],
      ['konu', fmtInt(graph.topics)],
      ['yasaklı 4-gram', fmtInt(graph.forbidden4Grams)],
      ['yasaklı cümle', fmtInt(graph.forbiddenSentences)],
      ['tf girdisi', fmtInt(graph.tfEntries)],
      ['dosya', fmtBytes(graph.bytes)],
    ]);
  } else {
    setPill('graph-pill', 'bad', 'okunamadı');
    rows('graph-rows', [['durum', 'NV3G1 başlığı okunamadı']]);
  }

  if (checkpoint) {
    setPill('ckpt-pill', 'good', `${checkpoint.dtype} · ${fmtBytes(checkpoint.bytes)}`);
    rows('ckpt-rows', [
      ['format', checkpoint.format],
      ['şema', checkpoint.schemaVersion],
      ['tür', checkpoint.dtype],
      ['d_model', checkpoint.dModel],
      ['d_k', checkpoint.dK],
      ['d_h', checkpoint.dH],
      ['conv_k', checkpoint.convK],
      ['adım', fmtInt(checkpoint.steps)],
      ['parametre', fmtInt(checkpoint.params)],
      ['yük baytı', fmtBytes(checkpoint.payloadBytes)],
      ['mimari özeti', checkpoint.archHash],
      ['yük sağlaması', checkpoint.payloadChecksum],
      ['dosya', fmtBytes(checkpoint.bytes)],
    ]);
  } else {
    setPill('ckpt-pill', 'bad', 'okunamadı');
    rows('ckpt-rows', [['durum', 'NPG-v3 başlığı okunamadı']]);
  }

  const corpusRows = [];
  if (corpus) {
    corpusRows.push(
      ['üretim korpusu', `${fmtInt(corpus.topics)} konu`],
      ['satır', fmtInt(corpus.lines)],
      ['bayt', fmtBytes(corpus.bytes)],
      ['karakter', fmtInt(corpus.characters)],
    );
  }
  if (bridgeCorpus) corpusRows.push(['köprü korpusu', `${fmtInt(bridgeCorpus.topics)} konu`]);
  if (lockedTrain) {
    corpusRows.push(
      ['kilitli shard', lockedTrain.shardId ?? DASH],
      ['kilitli doküman', fmtInt(lockedTrain.numDocs)],
      ['kilitli bayt', fmtBytes(lockedTrain.numBytes)],
    );
  }
  if (scaledCheckpoint) {
    corpusRows.push(['ölçekli ckpt', `${fmtInt(scaledCheckpoint.params)} param · ${scaledCheckpoint.dtype}`]);
  }
  rows('corpus-rows', corpusRows.length ? corpusRows : [['durum', 'veri yok']]);
}

function renderTelemetry(t) {
  const { inference, host } = t;

  rows('infer-rows', [
    ['istek', fmtInt(inference.requests)],
    ['üretilen', fmtInt(inference.generated)],
    ['çekimser', fmtInt(inference.abstained)],
    ['hata', fmtInt(inference.errors)],
    ['önbellek isabeti', fmtInt(inference.cacheHits)],
    ['üretilen bayt', fmtBytes(inference.bytesGenerated)],
    ['sentez atomu', fmtInt(inference.atomsSynthesized)],
    ['en uzun n-gram', fmtInt(inference.ngramMax)],
    ['anti-verbatim', `${fmtInt(inference.antiVerbatimPasses)}/${fmtInt(inference.antiVerbatimChecks)}`],
    ['KHG gözlem', fmtInt(inference.khgObserved)],
    ['KHG doğrulanan', fmtInt(inference.khgVerified)],
    ['KHG karantina', fmtInt(inference.khgQuarantined)],
    ['ort. CPU', fmtMs(inference.meanCpuMs)],
    ['ort. duvar', fmtMs(inference.meanWallMs)],
    ['zirve eşzamanlı', fmtInt(inference.peakConcurrentRuns)],
    ['çalışma süresi', fmtDuration(inference.sinceMs / 1000)],
  ]);

  rows('host-rows', [
    ['çekirdek', fmtInt(host.cores)],
    ['yük 1dk', host.load1.toFixed(2)],
    ['yük 5dk', host.load5.toFixed(2)],
    ['yük 15dk', host.load15.toFixed(2)],
    ['bellek toplam', fmtBytes(host.memory.totalBytes)],
    ['bellek boş', fmtBytes(host.memory.freeBytes)],
    ['bellek kullanımı', `%${host.memory.usedPercent}`],
    ['süreç RSS', fmtBytes(host.rssBytes)],
    ['sunucu uptime', fmtDuration(host.uptimeSeconds)],
  ]);

  const perCore = host.cores > 0 ? host.load1 / host.cores : 0;
  setBar('b-load', perCore, perCore > 0.9 ? 'bad' : perCore > 0.6 ? 'warn' : null);
  $('#m-load').textContent = `${host.load1.toFixed(2)} / ${host.cores} çekirdek`;

  setBar('b-mem', host.memory.usedPercent / 100, host.memory.usedPercent > 90 ? 'bad' : host.memory.usedPercent > 75 ? 'warn' : null);
  $('#m-mem').textContent = `%${host.memory.usedPercent} · ${fmtBytes(host.memory.totalBytes - host.memory.freeBytes)}`;

  const cacheRatio = inference.cacheLimit ? inference.cacheSize / inference.cacheLimit : 0;
  setBar('b-cache', cacheRatio, null);
  $('#m-cache').textContent = `${fmtInt(inference.cacheSize)} / ${fmtInt(inference.cacheLimit)} kayıt`;

  setBar('b-hitrate', inference.cacheHitPercent / 100, inference.cacheHitPercent > 50 ? 'good' : null);
  document.querySelector('#b-hitrate').querySelector('i').style.background = 'var(--good)';
  $('#m-hitrate').textContent = `%${inference.cacheHitPercent} · ${fmtInt(inference.cacheHits)} istek`;

  $('#live-tick').querySelector('span').textContent = fmtInt(inference.requests);
}

function renderContract(health) {
  const list = $('#guarantees');
  list.replaceChildren();
  const checks = [
    ['anti-verbatim', health.guarantees?.antiVerbatim, '4-gram sınırı'],
    ['zemin', health.guarantees?.grounding, 'kapsama'],
    ['çekimserlik', health.guarantees?.abstention, 'sıfır bayt'],
    ['determinizm', health.guarantees?.determinism, 'bayt-eşit'],
  ];
  for (const [name, text, tag] of checks) {
    const row = document.createElement('div');
    row.className = 'verify-row';
    row.dataset.state = text ? 'pass' : 'fail';
    const left = document.createElement('span');
    left.className = 'v-name';
    const mark = document.createElement('i');
    mark.textContent = text ? '✓' : '✕';
    left.append(mark, document.createTextNode(` ${name}`));
    const right = document.createElement('span');
    right.className = 'v-val';
    right.textContent = tag;
    right.title = text || '';
    row.append(left, right);
    list.append(row);
  }

  const modes = $('#modes');
  modes.replaceChildren();
  const contract = health.output_mode_contract || {};
  const entries = [
    ...(contract.v3 || []).map(mode => ['v3', mode]),
    ['legacy', contract.legacy_mode],
  ];
  for (const [group, mode] of entries) {
    if (!mode) continue;
    const row = document.createElement('div');
    row.className = 'hexrow';
    const k = document.createElement('span');
    k.className = 'k';
    k.textContent = group;
    const v = document.createElement('span');
    v.className = 'v';
    v.textContent = mode;
    row.append(k, v);
    modes.append(row);
  }
}

// ---------------------------------------------------------------------------------------------

async function refresh() {
  try {
    const [healthRes, artifactRes] = await Promise.all([
      fetch('/api/health', { signal: AbortSignal.timeout(8000) }),
      fetch('/api/artifacts', { signal: AbortSignal.timeout(8000) }),
    ]);
    const health = await healthRes.json();
    const artifacts = await artifactRes.json();
    setHealth(Boolean(health.ok));
    $('#runtime-tag').textContent = `LIR · ${health.runtime ?? DASH}`;
    if (artifacts.ok) renderArtifacts(artifacts);
    renderContract(health);
    if (health.telemetry) renderTelemetry(health.telemetry);
  } catch {
    setHealth(false);
    $('#runtime-tag').textContent = 'LIR · bağlantı yok';
  }
}

async function tick() {
  if (document.visibilityState !== 'visible') return;
  try {
    const res = await fetch('/api/telemetry', { signal: AbortSignal.timeout(6000) });
    if (!res.ok) throw new Error('telemetry');
    renderTelemetry(await res.json());
    setHealth(true);
  } catch {
    setHealth(false);
  }
}

$('#refresh-button').addEventListener('click', () => { refresh(); tick(); });
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') tick(); });

// A 5 s cadence is enough for a status page and costs the server one cheap JSON write; the
// poll stops entirely while the tab is hidden.
setInterval(tick, 5000);
refresh();
