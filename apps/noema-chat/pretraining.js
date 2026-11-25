const fileInput = document.querySelector('#training-file');
const startButton = document.querySelector('#training-start');
const uploadProgress = document.querySelector('#upload-progress');
const trainingPanel = document.querySelector('#training-panel');
let currentFile = null;
let active = false;

function formatBytes(bytes) {
  if (bytes < 1000) return `${bytes} B`;
  if (bytes < 1_000_000) return `${(bytes / 1000).toFixed(1)} kB`;
  if (bytes < 1_000_000_000) return `${(bytes / 1_000_000).toFixed(1)} MB`;
  return `${(bytes / 1_000_000_000).toFixed(2)} GB`;
}

function formatTime(seconds) {
  if (seconds == null || !Number.isFinite(seconds)) return 'Hesaplanıyor';
  if (seconds < 60) return `${Math.max(0, seconds)} sn`;
  const minutes = Math.floor(seconds / 60);
  const remainder = seconds % 60;
  return `${minutes} dk ${remainder} sn`;
}

function setUploadProgress(loaded, total, status = 'Dosya yükleniyor') {
  const percent = total > 0 ? Math.min(100, Math.floor(loaded / total * 100)) : 0;
  document.querySelector('#upload-percent').textContent = `${percent}%`;
  document.querySelector('#upload-bar').style.width = `${percent}%`;
  document.querySelector('.upload-progress .training-track').setAttribute('aria-valuenow', String(percent));
  document.querySelector('#upload-bytes').textContent = `${formatBytes(loaded)} / ${formatBytes(total)}`;
  document.querySelector('#upload-status').textContent = status;
}

function updateTrainingProgress(data) {
  const percent = Math.max(0, Math.min(100, data.percent || 0));
  document.querySelector('#training-percent').textContent = `${percent}%`;
  document.querySelector('#training-bar').style.width = `${percent}%`;
  document.querySelector('.live-progress .training-track').setAttribute('aria-valuenow', String(percent));
  document.querySelector('#training-records').textContent = `${data.processed} / ${data.total} kayıt işlendi`;
  document.querySelector('#training-payload').textContent = formatBytes(data.payloadBytes || 0);
  document.querySelector('#training-source').textContent = formatBytes(data.sourceBytes || 0);
  document.querySelector('#training-elapsed').textContent = `${formatTime(data.elapsedSeconds)} geçti`;
  document.querySelector('#training-remaining').textContent = data.status === 'completed'
    ? '0 sn' : formatTime(data.estimatedRemainingSeconds);
  document.querySelector('#training-eta').textContent = data.status === 'completed'
    ? `Tamamlandı · ${formatTime(data.elapsedSeconds)} sürdü`
    : `Tahmini kalan: ${formatTime(data.estimatedRemainingSeconds)}`;
  document.querySelector('#training-status').textContent = data.status === 'completed'
    ? 'Tüm kayıtlar eğitildi'
    : data.status === 'failed' ? 'Eğitim başarısız' : `LIR kaydı ${data.processed} / ${data.total} işliyor`;
  const versionLabel = data.version ? `V${String(data.version).padStart(3, '0')} · ` : '';
  document.querySelector('#training-state-pill').textContent = data.status === 'completed'
    ? `${versionLabel}TAMAMLANDI` : data.status === 'failed' ? 'HATA' : `${versionLabel}EĞİTİLİYOR`;
}

async function pollTraining(jobId) {
  try {
    const response = await fetch(`/api/train/status?jobId=${encodeURIComponent(jobId)}`);
    const data = await response.json();
    if (!response.ok || !data.ok) throw new Error(data.error || 'Eğitim durumu alınamadı.');
    updateTrainingProgress(data);
    if (data.status === 'running') {
      setTimeout(() => pollTraining(jobId), 500);
      return;
    }
    active = false;
    startButton.disabled = !currentFile;
    if (data.status === 'completed') {
      document.querySelector('#training-result').hidden = false;
      document.querySelector('#training-checkpoint').textContent = `${data.model.filePath} · ${data.model.modifiedDate}`;
      document.querySelector('#connection-label').textContent = 'Checkpoint hazır';
      document.querySelector('#dataset-topics').textContent = `${data.total} konu kaydı`;
      document.querySelector('#training-hint').textContent = 'Eğitilmiş model Chat sayfasındaki model seçicisinde kullanılabilir.';
    } else {
      document.querySelector('#training-status').textContent = data.error || 'Eğitim başarısız oldu.';
      document.querySelector('#connection-label').textContent = 'Eğitim hatası';
    }
  } catch (error) {
    active = false;
    startButton.disabled = !currentFile;
    document.querySelector('#training-status').textContent = error.message || 'İlerleme alınamadı.';
    document.querySelector('#training-state-pill').textContent = 'BAĞLANTI HATASI';
  }
}

fileInput.addEventListener('change', () => {
  const file = fileInput.files?.[0] || null;
  currentFile = null;
  document.querySelector('#training-result').hidden = true;
  if (!file) return;
  if (!file.name.toLowerCase().endsWith('.txt')) {
    document.querySelector('#training-file-name').textContent = 'Yalnızca .txt dosyası kabul edilir';
    document.querySelector('#training-hint').textContent = 'Düz metin dosyası seçmelisiniz.';
    startButton.disabled = true;
    return;
  }
  if (!file.size) {
    document.querySelector('#training-file-name').textContent = 'Dosya boş';
    document.querySelector('#training-hint').textContent = 'Boş olmayan bir TXT seçin. Toplam boyut; disk ve bellek kaynaklarıyla sınırlıdır.';
    startButton.disabled = true;
    return;
  }
  currentFile = file;
  document.querySelector('#training-file-name').textContent = file.name;
  document.querySelector('#dataset-size').textContent = formatBytes(file.size);
  document.querySelector('#dataset-topics').textContent = 'Yükleme sırasında hesaplanacak';
  document.querySelector('#dataset-facts').hidden = false;
  document.querySelector('#training-hint').textContent = 'Hazır · eğitim başlatıldığında dosya akış halinde gönderilir.';
  startButton.disabled = active;
});

startButton.addEventListener('click', () => {
  if (!currentFile || active) return;
  active = true;
  startButton.disabled = true;
  uploadProgress.hidden = false;
  trainingPanel.hidden = true;
  document.querySelector('#training-result').hidden = true;
  document.querySelector('#training-hint').textContent = 'Dosya yükleniyor; ardından LIR kayıtlara göre eğitim yapacak.';
  setUploadProgress(0, currentFile.size);

  const xhr = new XMLHttpRequest();
  xhr.open('POST', '/api/train');
  xhr.setRequestHeader('Content-Type', 'application/octet-stream');
  xhr.setRequestHeader('X-File-Name', encodeURIComponent(currentFile.name));
  xhr.upload.addEventListener('progress', event => {
    if (event.lengthComputable) setUploadProgress(event.loaded, event.total);
  });
  xhr.upload.addEventListener('load', () => {
    setUploadProgress(currentFile.size, currentFile.size, 'Dosya alındı · TXT kayıtları hazırlanıyor');
  });
  xhr.addEventListener('load', () => {
    let result;
    try { result = JSON.parse(xhr.responseText); }
    catch { result = { error: 'Sunucudan geçersiz yanıt alındı.' }; }
    if (xhr.status < 200 || xhr.status >= 300 || !result.ok) {
      active = false;
      startButton.disabled = !currentFile;
      document.querySelector('#upload-status').textContent = result.error || 'Yükleme başarısız';
      document.querySelector('#training-hint').textContent = result.error || 'Dosya işlenemedi.';
      return;
    }
    uploadProgress.hidden = true;
    trainingPanel.hidden = false;
    document.querySelector('#dataset-topics').textContent = `${result.total} konu kaydı bulundu`;
    document.querySelector('#training-source').textContent = formatBytes(result.sourceBytes);
    document.querySelector('#training-records').textContent = `0 / ${result.total} kayıt işlendi`;
    document.querySelector('#training-state-pill').textContent = `V${String(result.version).padStart(3, '0')} · EĞİTİLİYOR`;
    document.querySelector('#training-payload').textContent = formatBytes(result.payloadBytes);
    document.querySelector('#training-status').textContent = 'LIR pretraining başlatıldı';
    pollTraining(result.jobId);
  });
  xhr.addEventListener('error', () => {
    active = false;
    startButton.disabled = !currentFile;
    document.querySelector('#upload-status').textContent = 'Ağ yüklemesi başarısız';
    document.querySelector('#training-hint').textContent = 'Bağlantıyı kontrol edip yeniden deneyin.';
  });
  xhr.send(currentFile);
});

const drop = document.querySelector('#upload-drop');
drop.addEventListener('dragover', event => { event.preventDefault(); drop.classList.add('drag-over'); });
drop.addEventListener('dragleave', () => drop.classList.remove('drag-over'));
drop.addEventListener('drop', event => {
  event.preventDefault();
  drop.classList.remove('drag-over');
  const file = event.dataTransfer?.files?.[0];
  if (!file) return;
  const transfer = new DataTransfer();
  transfer.items.add(file);
  fileInput.files = transfer.files;
  fileInput.dispatchEvent(new Event('change', { bubbles: true }));
});

fetch('/api/health').then(response => response.json()).then(data => {
  if (data.ok) document.querySelector('#connection-label').textContent = 'LIR bağlı';
}).catch(() => {
  document.querySelector('#connection-label').textContent = 'Bağlantı yok';
});
