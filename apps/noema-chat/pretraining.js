// Corpus upload + local training.
//
// The file is streamed with XMLHttpRequest so the upload bar reflects real bytes on the wire
// (`xhr.upload.onprogress`), not a timer. Training progress comes from the server's own progress
// frame, which the LIR trainer writes as it works.

const $ = selector => document.querySelector(selector);

const MAX_FILE_BYTES = 64 * 1024 * 1024;
const DELIMITER = '<veriayrimi>';

const dom = {
  fileInput: $('#file-input'),
  pick: $('#pick-file'),
  dropzone: $('#dropzone'),
  fileHint: $('#file-hint'),
  uploadState: $('#upload-state'),
  uploadProgress: $('#upload-progress'),
  uploadName: $('#upload-name'),
  uploadPct: $('#upload-pct'),
  uploadTrack: $('#upload-track'),
  uploadBytes: $('#upload-bytes'),
  uploadStatus: $('#upload-status'),
  start: $('#start-button'),
  cancel: $('#cancel-button'),
  panel: $('#training-panel'),
  trainPill: $('#train-pill'),
  trainStage: $('#train-stage'),
  trainPct: $('#train-pct'),
  trainTrack: $('#train-track'),
  trainVersion: $('#train-version'),
  trainTopics: $('#train-topics'),
  trainSource: $('#train-source'),
  trainPayload: $('#train-payload'),
  trainElapsed: $('#train-elapsed'),
  trainEta: $('#train-eta'),
  trainError: $('#train-error'),
  trainResult: $('#train-result'),
  trainActions: $('#train-actions'),
  gotoChat: $('#goto-chat'),
  modelList: $('#model-list'),
  modelCount: $('#model-count'),
};

let currentFile = null;
let currentJobId = null;
let pollTimer = null;
let uploading = false;

const nf = new Intl.NumberFormat('tr-TR');
const fmtInt = v => (Number.isFinite(Number(v)) ? nf.format(Number(v)) : '—');
const fmtBytes = v => {
  const n = Number(v);
  if (!Number.isFinite(n) || n < 0) return '—';
  if (n < 1024) return `${n} B`;
  if (n < 1048576) return `${(n / 1024).toFixed(n < 10240 ? 1 : 0)} kB`;
  return `${(n / 1048576).toFixed(2)} MB`;
};
const fmtTime = seconds => {
  if (seconds == null || !Number.isFinite(Number(seconds))) return 'hesaplanıyor';
  const s = Math.max(0, Math.round(Number(seconds)));
  if (s < 60) return `${s} sn`;
  return `${Math.floor(s / 60)} dk ${s % 60} sn`;
};

/**
 * Set a progress track's fill width. Under `style-src 'self'` assignments to `element.style`
 * are blocked silently, so the value travels as a custom property the stylesheet consumes.
 */
function setFill(track, percent) {
  const fill = track?.querySelector('i');
  if (fill) fill.style.setProperty('--fill', `${Math.max(0, Math.min(100, percent))}%`);
}

// ---------------------------------------------------------------------------------------------
// validation (mirrors the server's rules so the user learns about a problem before uploading)
// ---------------------------------------------------------------------------------------------

/**
 * Count `<veriayrimi>` topics. The server enforces the same minimum, so rejecting here only saves
 * a wasted upload; the server remains the authority.
 */
function countTopics(text) {
  return text.split(DELIMITER).map(part => part.trim()).filter(Boolean).length;
}

async function inspectFile(file) {
  if (!file) return null;
  if (!file.name.toLowerCase().endsWith('.txt')) {
    return { error: 'Yalnızca .txt dosyası yüklenebilir.' };
  }
  if (file.size > MAX_FILE_BYTES) {
    return { error: `Dosya ${fmtBytes(MAX_FILE_BYTES)} sınırını aşıyor.` };
  }
  if (file.size === 0) return { error: 'Dosya boş.' };
  const text = await file.text();
  const topics = countTopics(text);
  if (topics < 2) {
    return { error: `En az 2 konu gerekir; bulunan: ${topics}. Konuları ${DELIMITER} satırıyla ayırın.` };
  }
  return { topics, bytes: file.size, lines: text.split(/\r?\n/).filter(line => line.trim()).length };
}

async function chooseFile(file) {
  currentFile = null;
  dom.start.disabled = true;
  dom.dropzone.dataset.drag = 'false';
  if (!file) {
    dom.fileHint.textContent = 'henüz dosya seçilmedi';
    return;
  }
  dom.fileHint.textContent = `${file.name} · inceleniyor…`;
  const info = await inspectFile(file);
  if (info.error) {
    dom.fileHint.textContent = info.error;
    dom.fileHint.classList.add('is-bad');
    return;
  }
  dom.fileHint.classList.remove('is-bad');
  dom.fileHint.textContent = `${file.name} · ${fmtBytes(info.bytes)} · ${fmtInt(info.topics)} konu · ${fmtInt(info.lines)} satır`;
  currentFile = file;
  dom.start.disabled = false;
}

// ---------------------------------------------------------------------------------------------
// upload
// ---------------------------------------------------------------------------------------------

function setUploadUI(loaded, total) {
  const pct = total > 0 ? Math.min(100, Math.floor((loaded / total) * 100)) : 0;
  dom.uploadPct.textContent = `%${pct}`;
  setFill(dom.uploadTrack, pct);
  dom.uploadBytes.textContent = `${fmtBytes(loaded)} / ${fmtBytes(total)}`;
}

function uploadFile(file) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/api/train');
    xhr.setRequestHeader('content-type', 'application/octet-stream');
    // The filename travels in a header so the body stays a pure byte stream; the server validates
    // the extension and never trusts a path.
    xhr.setRequestHeader('x-file-name', encodeURIComponent(file.name));

    xhr.upload.onprogress = event => {
      if (event.lengthComputable) setUploadUI(event.loaded, event.total);
    };
    xhr.upload.onload = () => {
      dom.uploadStatus.textContent = 'sunucuda işleniyor…';
      dom.uploadState.querySelector('span').textContent = 'işleniyor';
    };

    xhr.onload = () => {
      let body = null;
      try { body = JSON.parse(xhr.responseText); } catch { /* handled below */ }
      if (xhr.status >= 200 && xhr.status < 300 && body?.ok) {
        setUploadUI(file.size, file.size);
        resolve(body);
      } else {
        reject(new Error(body?.error || `Yükleme başarısız (HTTP ${xhr.status}).`));
      }
    };
    xhr.onerror = () => reject(new Error('Ağ hatası: yükleme tamamlanamadı.'));
    xhr.onabort = () => reject(new Error('Yükleme iptal edildi.'));
    xhr.send(file);
  });
}

async function startTraining() {
  if (!currentFile || uploading) return;
  uploading = true;
  dom.start.disabled = true;
  dom.cancel.hidden = false;
  dom.uploadProgress.hidden = false;
  dom.uploadName.textContent = currentFile.name;
  dom.uploadStatus.textContent = 'yükleniyor…';
  dom.uploadState.dataset.tone = 'info';
  dom.uploadState.querySelector('span').textContent = 'yükleniyor';
  setUploadUI(0, currentFile.size);

  try {
    const job = await uploadFile(currentFile);
    dom.uploadState.dataset.tone = 'good';
    dom.uploadState.querySelector('span').textContent = 'yüklendi';
    dom.panel.hidden = false;
    currentJobId = job.jobId;
    dom.trainVersion.textContent = `v${String(job.version).padStart(3, '0')}`;
    dom.trainTopics.textContent = fmtInt(job.topics);
    dom.trainSource.textContent = fmtBytes(job.sourceBytes);
    dom.trainPayload.textContent = fmtBytes(job.payloadBytes);
    dom.panel.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    poll();
  } catch (error) {
    dom.uploadState.dataset.tone = 'bad';
    dom.uploadState.querySelector('span').textContent = 'hata';
    dom.uploadStatus.textContent = error.message;
    dom.uploadTrack.dataset.tone = 'bad';
    dom.start.disabled = false;
  } finally {
    uploading = false;
  }
}

// ---------------------------------------------------------------------------------------------
// training progress
// ---------------------------------------------------------------------------------------------

// The server reports a stage index; naming the stages makes the progress legible without
// inventing a timing model.
const STAGE_NAMES = ['paketleme', 'ağırlık güncellemesi', 'grafik kurulumu', 'anti-verbatim denetimi', 'yayın'];
const stageFor = percent => Math.min(STAGE_NAMES.length - 1, Math.floor((percent / 100) * STAGE_NAMES.length));

function renderStages(percent, status) {
  const active = stageFor(percent);
  const chips = document.querySelectorAll('.stage-chip');
  chips.forEach((chip, index) => {
    if (status === 'completed') chip.dataset.state = 'done';
    else if (index < active) chip.dataset.state = 'done';
    else if (index === active) chip.dataset.state = 'active';
    else chip.dataset.state = '';
  });
}

function renderSummary(summary) {
  if (!summary) return;
  const items = [
    ['konu', fmtInt(summary.topics)],
    ['atom', fmtInt(summary.atoms)],
    ['yasak 4-gram', fmtInt(summary.forbidden4Grams)],
    ['yasak cümle', fmtInt(summary.forbiddenSentences)],
    ['ağırlık adımı', fmtInt(summary.npgSteps)],
    ['SOA doküman', fmtInt(summary.soaDocs)],
    ['deneme baytı', fmtInt(summary.probeEmittedBytes)],
  ];
  dom.trainResult.replaceChildren();
  for (const [label, value] of items) {
    const stat = document.createElement('div');
    stat.className = 'stat';
    const l = document.createElement('span');
    l.className = 'stat-label';
    l.textContent = label;
    const v = document.createElement('span');
    v.className = 'stat-value';
    v.textContent = value;
    stat.append(l, v);
    dom.trainResult.append(stat);
  }
  dom.trainResult.hidden = false;
}

function applyStatus(data) {
  const percent = Math.max(0, Math.min(100, data.percent || 0));
  dom.trainPct.textContent = `%${percent}`;
  setFill(dom.trainTrack, percent);
  dom.trainStage.textContent = data.status === 'completed'
    ? 'Eğitim tamamlandı'
    : data.status === 'failed'
      ? 'Eğitim başarısız'
      : STAGE_NAMES[stageFor(percent)];
  dom.trainElapsed.textContent = fmtTime(data.elapsedSeconds);
  dom.trainEta.textContent = data.status === 'completed' ? '0 sn' : fmtTime(data.estimatedRemainingSeconds);
  renderStages(percent, data.status);

  const pill = dom.trainPill;
  if (data.status === 'completed') {
    pill.dataset.tone = 'good';
    pill.querySelector('span').textContent = 'tamamlandı';
    dom.trainTrack.dataset.tone = '';
  } else if (data.status === 'failed') {
    pill.dataset.tone = 'bad';
    pill.querySelector('span').textContent = 'hata';
    dom.trainTrack.dataset.tone = 'bad';
  } else {
    pill.dataset.tone = 'info';
    pill.querySelector('span').textContent = 'eğitiliyor';
  }

  if (data.error) {
    dom.trainError.hidden = false;
    dom.trainError.textContent = data.error;
  }
  renderSummary(data.summary);

  if (data.status === 'completed') {
    dom.trainActions.hidden = false;
    const selector = data.model?.selector;
    if (selector) {
      // The trained model is addressable by its own selector, so link straight into a chat with
      // it preselected rather than making the user hunt through a dropdown.
      dom.gotoChat.href = `/?model=${encodeURIComponent(selector)}`;
    }
    loadModels();
  }
}

async function poll() {
  if (!currentJobId) return;
  try {
    const response = await fetch(`/api/train/status?jobId=${encodeURIComponent(currentJobId)}`, {
      signal: AbortSignal.timeout(15000),
    });
    const data = await response.json();
    if (!response.ok || !data.ok) throw new Error(data.error || 'Eğitim durumu alınamadı.');
    applyStatus(data);
    if (data.status === 'running') {
      pollTimer = setTimeout(poll, 1000);
    } else {
      dom.start.disabled = false;
      dom.cancel.hidden = true;
    }
  } catch (error) {
    dom.trainError.hidden = false;
    dom.trainError.textContent = error.message;
    pollTimer = setTimeout(poll, 3000);
  }
}

// ---------------------------------------------------------------------------------------------
// model list
// ---------------------------------------------------------------------------------------------

async function loadModels() {
  try {
    const response = await fetch('/api/models', { signal: AbortSignal.timeout(8000) });
    const data = await response.json();
    const users = (data.models || []).filter(model => model.id.startsWith('user_v3_'));
    dom.modelList.replaceChildren();
    dom.modelCount.querySelector('span').textContent = String(users.length);
    if (!users.length) {
      const empty = document.createElement('div');
      empty.className = 'empty';
      empty.innerHTML = 'Henüz kendi modelinizi eğitmediniz.<br>Üretim modeli <b>noema_v3</b> her zaman kullanılabilir.';
      dom.modelList.append(empty);
      return;
    }
    for (const model of users) {
      const item = document.createElement('div');
      item.className = 'model-item';
      const id = document.createElement('span');
      id.className = 'id';
      id.textContent = model.id;
      id.title = model.selector;
      const size = document.createElement('span');
      size.className = 'sz';
      size.textContent = `${fmtBytes(model.checkpointBytes)} + ${fmtBytes(model.graphBytes)}`;
      const link = document.createElement('a');
      link.className = 'btn btn-ghost';
      link.classList.add('btn-sm');
      link.href = `/?model=${encodeURIComponent(model.selector)}`;
      link.textContent = 'Sor';
      item.append(id, size, link);
      dom.modelList.append(item);
    }
  } catch {
    /* the list is informational; a failure must not block training */
  }
}

async function loadCorpusFacts() {
  try {
    const response = await fetch('/api/artifacts', { signal: AbortSignal.timeout(8000) });
    const data = await response.json();
    const body = $('#prod-corpus-rows');
    body.replaceChildren();
    const pairs = [];
    if (data.corpus) {
      pairs.push(['konu', fmtInt(data.corpus.topics)], ['satır', fmtInt(data.corpus.lines)], ['bayt', fmtBytes(data.corpus.bytes)]);
    }
    if (data.graph) {
      pairs.push(['atom', fmtInt(data.graph.atoms)], ['yasak 4-gram', fmtInt(data.graph.forbidden4Grams)]);
    }
    if (data.checkpoint) {
      pairs.push(['parametre', fmtInt(data.checkpoint.params)], ['adım', fmtInt(data.checkpoint.steps)]);
    }
    for (const [key, value] of pairs) {
      const tr = document.createElement('tr');
      const td1 = document.createElement('td');
      td1.textContent = key;
      const td2 = document.createElement('td');
      td2.textContent = value;
      tr.append(td1, td2);
      body.append(tr);
    }
    $('#rail-health').dataset.state = 'up';
    $('#rail-health-label').textContent = 'BAĞLI';
  } catch {
    $('#rail-health').dataset.state = 'down';
    $('#rail-health-label').textContent = 'KAPALI';
  }
}

// ---------------------------------------------------------------------------------------------
// events
// ---------------------------------------------------------------------------------------------

function openPicker() { dom.fileInput.click(); }
dom.pick.addEventListener('click', openPicker);
dom.dropzone.addEventListener('click', event => {
  if (event.target === dom.pick) return;
  openPicker();
});
dom.fileInput.addEventListener('change', () => chooseFile(dom.fileInput.files?.[0] ?? null));

// Drag & drop. `dragenter`/`dragleave` fire for child elements, so depth-count rather than
// toggling on every event, otherwise the highlight flickers.
let dragDepth = 0;
dom.dropzone.addEventListener('dragenter', event => {
  event.preventDefault();
  dragDepth += 1;
  dom.dropzone.dataset.drag = 'true';
});
dom.dropzone.addEventListener('dragover', event => {
  event.preventDefault();
  event.dataTransfer.dropEffect = 'copy';
});
dom.dropzone.addEventListener('dragleave', () => {
  dragDepth = Math.max(0, dragDepth - 1);
  if (dragDepth === 0) dom.dropzone.dataset.drag = 'false';
});
dom.dropzone.addEventListener('drop', event => {
  event.preventDefault();
  dragDepth = 0;
  dom.dropzone.dataset.drag = 'false';
  const file = event.dataTransfer?.files?.[0];
  if (file) chooseFile(file);
});

dom.start.addEventListener('click', startTraining);
dom.cancel.addEventListener('click', () => {
  clearTimeout(pollTimer);
  currentJobId = null;
  dom.cancel.hidden = true;
  dom.start.disabled = !currentFile;
  dom.trainPill.dataset.tone = 'warn';
  dom.trainPill.querySelector('span').textContent = 'izleme durduruldu';
});

window.addEventListener('pagehide', () => clearTimeout(pollTimer));

loadModels();
loadCorpusFacts();
