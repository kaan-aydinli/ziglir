const form = document.querySelector('#chat-form');
const input = document.querySelector('#message-input');
const messages = document.querySelector('#messages');
const welcome = document.querySelector('#welcome');
const typing = document.querySelector('#typing');
const sendButton = document.querySelector('#send-button');
const byteCount = document.querySelector('#byte-count');
const aboutDialog = document.querySelector('#about-dialog');
let busy = false;

const encoder = new TextEncoder();
const formatNumber = (value, digits = 5) => Number(value).toLocaleString('tr-TR', {
  maximumFractionDigits: digits,
  minimumFractionDigits: 0,
});

function appendUser(text) {
  const row = document.createElement('article');
  row.className = 'message user';
  const body = document.createElement('div');
  body.className = 'message-body';
  const meta = document.createElement('div');
  meta.className = 'message-meta';
  meta.textContent = 'SEN · ŞİMDİ';
  const content = document.createElement('div');
  content.textContent = text;
  body.append(meta, content);
  row.append(body);
  messages.append(row);
}

function formatModelDate(date) {
  if (!date) return 'tarih yok';
  const [year, month, day] = date.split('-');
  return `${day}.${month}.${year}`;
}

function appendModel(metrics, model) {
  const row = document.createElement('article');
  row.className = 'message';
  const avatar = document.createElement('div');
  avatar.className = 'message-avatar';
  avatar.textContent = 'N';
  const body = document.createElement('div');
  body.className = 'message-body';
  const meta = document.createElement('div');
  meta.className = 'message-meta';
  const match = metrics.generatedBytes
    ? ` · eğitim satırı benzerliği ${formatNumber(metrics.retrievalSimilarity, 3)}`
    : ' · yeterince yakın eğitim satırı yok';
  meta.textContent = `${model.filePath} · ${formatModelDate(model.modifiedDate)}${match}`;
  const output = document.createElement('div');
  output.className = 'model-output';
  const bytes = Uint8Array.from(metrics.generatedHex.match(/.{2}/g) || [], pair => Number.parseInt(pair, 16));
  const decoded = new TextDecoder('utf-8', { fatal: false }).decode(bytes);
  const visible = decoded.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, '�');
  const generated = document.createElement('pre');
  generated.className = 'generated-output';
  generated.textContent = metrics.generatedBytes ? visible : 'Güvenilir bir eğitim satırı eşleşmesi bulunamadı; model yanıt üretmedi.';
  const details = document.createElement('details');
  details.className = 'raw-output';
  const summary = document.createElement('summary');
  summary.textContent = `Ham bayt · ${metrics.generatedBytes}`;
  const hex = document.createElement('code');
  hex.textContent = metrics.generatedHex;
  details.append(summary, hex);
  output.append(generated, details);
  body.append(meta, output);
  row.append(avatar, body);
  messages.append(row);
}
function appendError(message) {
  const row = document.createElement('article');
  row.className = 'message';
  const avatar = document.createElement('div');
  avatar.className = 'message-avatar';
  avatar.textContent = '!';
  const body = document.createElement('div');
  body.className = 'message-body';
  const meta = document.createElement('div');
  meta.className = 'message-meta';
  meta.textContent = 'LIR ENGINE · HATA';
  const output = document.createElement('div');
  output.className = 'model-output';
  output.textContent = message;
  body.append(meta, output);
  row.append(avatar, body);
  messages.append(row);
}

function updateInspector(metrics) {
  document.querySelector('#metric-gate').textContent = formatNumber(metrics.surpriseGate, 5);
  document.querySelector('#gate-meter').style.width = `${Math.max(0, Math.min(1, metrics.surpriseGate)) * 100}%`;
  document.querySelector('#metric-stage').textContent = metrics.spectralStage;
  document.querySelector('#stage-meter').style.width = `${((metrics.spectralStage + 1) / 4) * 100}%`;
  document.querySelector('#metric-energy').textContent = formatNumber(metrics.freeEnergy, 5);
  document.querySelector('#metric-bytes').textContent = metrics.inputBytes;
  document.querySelector('#metric-output-bytes').textContent = metrics.generatedBytes;
  document.querySelector('#metric-records').textContent = metrics.trainingRecords;
  document.querySelector('#metric-training-bytes').textContent = formatNumber(metrics.trainingBytes, 0);
  document.querySelector('#metric-do-count').textContent = metrics.trainingDoPerturbations;
  document.querySelector('#model-card-title').textContent = metrics.modelId === 'noema_phi_large' ? 'NOEMA-Φ Large' : 'NOEMA-Φ Fresh';
  document.querySelector('#run-state').textContent = 'TAMAMLANDI';
  document.querySelector('#status-title').textContent = 'Alan işlendi';
  document.querySelector('#status-copy').textContent = `${metrics.trainingRecords} kayıt · ${metrics.storedExemplars}/${metrics.memoryCapacity} örnek belleği · LIR native retrieval`;
  document.querySelector('#connection-label').textContent = 'LIR bağlı';
}

async function submitMessage(value) {
  const message = value.trim();
  if (!message || busy) return;
  welcome.classList.add('hidden');
  appendUser(message);
  input.value = '';
  resizeInput();
  updateByteCount();
  busy = true;
  sendButton.disabled = true;
  typing.classList.remove('hidden');
  document.querySelector('#run-state').textContent = 'ÇALIŞIYOR';
  document.querySelector('#status-title').textContent = 'LIR çalışıyor';
  document.querySelector('#status-copy').textContent = 'Ham baytlar alan dinamiğine aktarılıyor';
  messages.scrollTop = messages.scrollHeight;
  try {
    const response = await fetch('/api/chat', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ message, modelId: document.querySelector('#model-select').value }),
    });
    const result = await response.json();
    if (!response.ok || !result.ok) throw new Error(result.error || 'Model çalıştırılamadı.');
    updateInspector(result.metrics);
    appendModel(result.metrics, result.model);
  } catch (error) {
    document.querySelector('#run-state').textContent = 'HATA';
    document.querySelector('#status-title').textContent = 'İstek başarısız';
    document.querySelector('#status-copy').textContent = 'Backend günlüklerini kontrol edin';
    appendError(error.message || 'LIR backend ile bağlantı kurulamadı.');
  } finally {
    typing.classList.add('hidden');
    busy = false;
    sendButton.disabled = false;
    input.focus();
    messages.scrollTop = messages.scrollHeight;
  }
}

function resizeInput() {
  input.style.height = 'auto';
  input.style.height = `${Math.min(input.scrollHeight, 130)}px`;
}
function updateByteCount() {
  byteCount.textContent = `${encoder.encode(input.value).length} bayt`;
}

form.addEventListener('submit', event => {
  event.preventDefault();
  submitMessage(input.value);
});
input.addEventListener('input', () => { resizeInput(); updateByteCount(); });
input.addEventListener('keydown', event => {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault();
    form.requestSubmit();
  }
});
document.querySelectorAll('.suggestion').forEach(button => {
  button.addEventListener('click', () => {
    input.value = button.dataset.prompt || '';
    updateByteCount();
    form.requestSubmit();
  });
});
document.querySelector('#model-select').addEventListener('change', () => {
  document.querySelector('#run-state').textContent = 'MODEL DEĞİŞTİ';
  document.querySelector('#status-title').textContent = 'Model seçildi';
  document.querySelector('#status-copy').textContent = 'Yeni seçim sonraki inference isteğinde çalışır';
});
document.querySelector('#clear-button').addEventListener('click', () => {
  messages.replaceChildren();
  welcome.classList.remove('hidden');
  document.querySelector('#metric-gate').textContent = '—';
  document.querySelector('#gate-meter').style.width = '0';
  document.querySelector('#metric-stage').textContent = '—';
  document.querySelector('#stage-meter').style.width = '0';
  document.querySelector('#metric-energy').textContent = '—';
  document.querySelector('#metric-bytes').textContent = '—';
  document.querySelector('#run-state').textContent = 'BEKLENİYOR';
  document.querySelector('#status-title').textContent = 'Hazır';
  document.querySelector('#status-copy').textContent = 'LIR backend bağlantısı bekleniyor';
});
document.querySelector('#about-button').addEventListener('click', () => aboutDialog.showModal());
document.querySelector('#close-dialog').addEventListener('click', () => aboutDialog.close());
document.querySelector('#done-dialog').addEventListener('click', () => aboutDialog.close());

async function refreshModels(preferred = null) {
  const response = await fetch('/api/health', { signal: AbortSignal.timeout(8000) });
  const data = await response.json();
  if (!response.ok || !data.ok) throw new Error('Model listesi alınamadı.');
  const select = document.querySelector('#model-select');
  for (const model of data.models || []) {
    let option = select.querySelector(`option[value="${model.id}"]`);
    if (!option) {
      option = document.createElement('option');
      option.value = model.id;
      select.append(option);
    }
    option.textContent = `${model.filePath} · ${formatModelDate(model.modifiedDate)}${model.id === 'fresh' ? ' (eğitimsiz)' : ''}`;
    option.disabled = !model.available;
  }
  if (preferred && Array.from(select.options).some(option => option.value === preferred && !option.disabled)) {
    select.value = preferred;
  } else if (select.selectedOptions[0]?.disabled) {
    select.value = Array.from(select.options).find(option => !option.disabled)?.value || '';
  }
  document.querySelector('#connection-label').textContent = 'LIR bağlı';
  return data.models || [];
}

refreshModels().then(() => {
  document.querySelector('#status-copy').textContent = 'NOEMA-Phi backend hazır';
}).catch(() => {
  document.querySelector('#connection-label').textContent = 'Bağlantı yok';
  document.querySelector('#status-copy').textContent = 'Model listesi alınamadı; LIR backend erişilemiyor';
  const select = document.querySelector('#model-select');
  select.disabled = true;
  for (const option of select.options) {
    option.disabled = true;
    option.textContent = `${option.value === 'trained' ? 'ai/noema-training/pretrain_large.nps' : option.value === 'uploaded' ? 'ai/noema-training/user_pretrain_v001.nps' : 'ai/src/noema_pretrain.lir'} · durum alınamadı`;
  }
});
