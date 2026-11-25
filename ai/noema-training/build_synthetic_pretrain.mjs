#!/usr/bin/env node
// Deterministic Turkish arithmetic/conversion corpus generator. No Python or
// external model is used. Writes separated TXT, length-prefixed .nbin, a small
// exemplar manifest, and record metadata under /tmp.
import { open, mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';

// This is a default corpus size, not a trainer limit. RECORDS can be any
// positive value representable by the host and available disk/RAM.
const RECORDS = Number(process.env.RECORDS || 4096);
const RECORD_BYTES = Number(process.env.RECORD_BYTES || 1_000_000);
const TXT = '/tmp/noema_pretrain_dataset.txt';
const NBIN = '/tmp/noema_pretrain_dataset.nbin';
const SAMPLES = '/tmp/noema_pretrain_samples.jsonl';
const META = '/tmp/noema_pretrain_dataset_meta.bin';
let rngState = 20261124;
let serial = 0;
let writtenExamples = 0;
function rand() {
  rngState = (Math.imul(rngState, 1664525) + 1013904223) >>> 0;
  return rngState / 4294967296;
}
function int(min, max) { return min + Math.floor(rand() * (max - min + 1)); }
function pick(items) { return items[Math.floor(rand() * items.length)]; }

function makeExample(index) {
  const kind = index % 16;
  if (kind === 0) {
    const a = int(10, 9999), b = int(1, 9999), c = a + b;
    return pick([
      `Soru: ${a} ile ${b} sayısının toplamı kaçtır? Yanıt: ${a} + ${b} = ${c}; toplam ${c} olur.`,
      `Soru: ${a} sayısına ${b} eklenirse sonuç nedir? Yanıt: ${a} + ${b} = ${c}. Sonuç ${c} olur.`,
      `Bir kutuda ${a} kalem, diğerinde ${b} kalem var. Toplam kaç kalem vardır? Yanıt: ${a} + ${b} = ${c}; toplam ${c} kalem vardır.`,
    ]);
  }
  if (kind === 1) {
    let a = int(2, 9999), b = int(1, 9999); if (b > a) [a, b] = [b, a]; const c = a - b;
    return pick([
      `Soru: ${a} sayısından ${b} çıkarılırsa kaç kalır? Yanıt: ${a} - ${b} = ${c}; kalan ${c} olur.`,
      `Bir rafta ${a} kitap vardı, ${b} kitap alındı. Kaç kitap kaldı? Yanıt: ${a} - ${b} = ${c}; ${c} kitap kaldı.`,
      `Soru: ${a} ile ${b} arasındaki fark kaçtır? Yanıt: ${a} - ${b} = ${c}; fark ${c} olur.`,
    ]);
  }
  if (kind === 2) {
    const a = int(2, 999), b = int(2, 999), c = a * b;
    return pick([
      `Soru: ${a} çarpı ${b} kaçtır? Yanıt: ${a} × ${b} = ${c}; sonuç ${c} olur.`,
      `Her birinde ${b} nesne olan ${a} eş grup var. Toplam kaç nesne vardır? Yanıt: ${a} × ${b} = ${c}; toplam ${c} nesne vardır.`,
      `Soru: ${a} grupta ${b} nesne bulunursa toplam nedir? Yanıt: ${a} × ${b} = ${c}; toplam ${c} olur.`,
    ]);
  }
  if (kind === 3) {
    const divisor = int(2, 999), quotient = int(2, 999), dividend = divisor * quotient;
    return pick([
      `Soru: ${dividend} sayısı ${divisor} eşit gruba bölünürse her grupta kaç olur? Yanıt: ${dividend} ÷ ${divisor} = ${quotient}; her grupta ${quotient} olur.`,
      `${dividend} nesne ${divisor} kişiye eşit paylaştırılıyor. Kişi başına kaç nesne düşer? Yanıt: ${dividend} ÷ ${divisor} = ${quotient}; kişi başına ${quotient} nesne düşer.`,
      `Soru: ${dividend} bölü ${divisor} işleminin sonucu nedir? Yanıt: ${dividend} ÷ ${divisor} = ${quotient}.`,
    ]);
  }
  if (kind === 4) {
    const base = int(1, 9999) * 100, p = pick([5, 10, 20, 25, 50, 75]), c = base * p / 100;
    return pick([
      `Soru: ${base} sayısının yüzde ${p}'i kaçtır? Yanıt: ${base} × ${p} / 100 = ${c}; sonuç ${c} olur.`,
      `${base} liranın yüzde ${p}'i hesaplanıyor. Tutar kaç liradır? Yanıt: ${base} × ${p} / 100 = ${c}; tutar ${c} liradır.`,
    ]);
  }
  if (kind === 5) {
    const a = int(1, 999_999), c = a * 1000;
    return pick([
      `Soru: ${a} kilometre kaç metredir? Yanıt: ${a} km = ${c} m; çünkü 1 km = 1000 m.`,
      `${a} km uzunluğu metreye çevriliyor. Sonuç nedir? Yanıt: ${a} × 1000 = ${c}; uzunluk ${c} metredir.`,
    ]);
  }
  if (kind === 6) {
    const a = int(1, 999_999), c = a * 60;
    return pick([
      `Soru: ${a} dakika kaç saniyedir? Yanıt: ${a} × 60 = ${c}; süre ${c} saniyedir.`,
      `Bir süre ${a} dakika. Bu kaç saniye eder? Yanıt: 1 dakika 60 saniye olduğundan ${a} × 60 = ${c} saniye.`,
    ]);
  }
  const hours = int(1, 9999), minutes = hours * 60;
  if (kind === 7) return pick([
    `Soru: ${hours} saat kaç dakikadır? Yanıt: ${hours} × 60 = ${minutes}; süre ${minutes} dakikadır.`,
    `${hours} saatlik süre dakika cinsinden kaçtır? Yanıt: 1 saat 60 dakika olduğundan ${hours} × 60 = ${minutes} dakika.`,
  ]);
  if (kind === 8) {
    const meters = int(1, 999_999), centimeters = meters * 100;
    return pick([
      `Soru: ${meters} metre kaç santimetredir? Yanıt: ${meters} × 100 = ${centimeters}; uzunluk ${centimeters} santimetredir.`,
      `${meters} m uzunluğu santimetreye çevir. Yanıt: ${meters} m = ${centimeters} cm.`,
    ]);
  }
  if (kind === 9) {
    const kg = int(1, 999_999), grams = kg * 1000;
    return pick([
      `Soru: ${kg} kilogram kaç gramdır? Yanıt: ${kg} × 1000 = ${grams}; kütle ${grams} gramdır.`,
      `${kg} kg ağırlığı gram cinsinden yaz. Yanıt: ${kg} kg = ${grams} g.`,
    ]);
  }
  if (kind === 10) {
    const liters = int(1, 999_999), ml = liters * 1000;
    return pick([
      `Soru: ${liters} litre kaç mililitredir? Yanıt: ${liters} × 1000 = ${ml}; hacim ${ml} mililitredir.`,
      `${liters} L sıvı kaç mL eder? Yanıt: ${liters} L = ${ml} mL.`,
    ]);
  }
  if (kind === 11) {
    const cm = int(1, 999_999), mm = cm * 10;
    return pick([
      `Soru: ${cm} santimetre kaç milimetredir? Yanıt: ${cm} × 10 = ${mm}; uzunluk ${mm} milimetredir.`,
      `${cm} cm uzunluğu mm cinsine dönüştür. Yanıt: ${cm} cm = ${mm} mm.`,
    ]);
  }
  if (kind === 12) {
    const days = int(1, 999_999), totalHours = days * 24;
    return pick([
      `Soru: ${days} gün kaç saattir? Yanıt: ${days} × 24 = ${totalHours}; süre ${totalHours} saattir.`,
      `${days} günlük süre toplam kaç saat eder? Yanıt: 1 gün 24 saat olduğundan ${days} × 24 = ${totalHours}.`,
    ]);
  }
  if (kind === 13) {
    const weeks = int(1, 999_999), days = weeks * 7;
    return pick([
      `Soru: ${weeks} hafta kaç gündür? Yanıt: ${weeks} × 7 = ${days}; süre ${days} gündür.`,
      `${weeks} haftalık süreyi gün olarak yaz. Yanıt: ${weeks} × 7 = ${days} gün.`,
    ]);
  }
  if (kind === 14) {
    const hours = int(1, 999_999), totalSeconds = hours * 3600;
    return pick([
      `Soru: ${hours} saat kaç saniyedir? Yanıt: ${hours} × 3600 = ${totalSeconds}; süre ${totalSeconds} saniyedir.`,
      `${hours} saatlik süreyi saniyeye çevir. Yanıt: ${hours} × 3600 = ${totalSeconds} saniye.`,
    ]);
  }
  const kilometers = int(1, 999_999), meters = kilometers * 1000;
  return pick([
    `Soru: ${meters} metre kaç kilometredir? Yanıt: ${meters} ÷ 1000 = ${kilometers}; uzunluk ${kilometers} kilometredir.`,
    `${meters} m mesafeyi km olarak yaz. Yanıt: ${meters} m = ${kilometers} km.`,
  ]);
}

async function writeAll(file, buffer) {
  let offset = 0;
  while (offset < buffer.length) {
    const { bytesWritten } = await file.write(buffer, offset, buffer.length - offset);
    if (!bytesWritten) throw new Error('short write');
    offset += bytesWritten;
  }
}
function selectedLine(block, _docCount) {
  // Keep validation aligned with np_memory_add's deterministic first-line
  // exemplar policy; never sample from the whitespace padding tail.
  let pos = 0;
  while (pos < block.length) {
    let end = block.indexOf(10, pos); if (end < 0) end = block.length;
    const text = block.subarray(pos, end).toString('utf8').trim();
    if (text && Buffer.byteLength(text) <= 256) return text;
    pos = end + 1;
  }
  return '';
}

async function main() {
  if (!Number.isSafeInteger(RECORDS) || RECORDS < 1 || !Number.isSafeInteger(RECORD_BYTES) || RECORD_BYTES < 1024) throw new Error('invalid RECORDS/RECORD_BYTES');
  await mkdir(dirname(TXT), { recursive: true });
  const txt = await open(TXT, 'w');
  const nbin = await open(NBIN, 'w');
  const samples = await open(SAMPLES, 'w');
  let totalExamples = 0;
  try {
    for (let record = 0; record < RECORDS; record++) {
      const block = Buffer.alloc(RECORD_BYTES, 32);
      let cursor = 0;
      while (cursor < RECORD_BYTES) {
        // Start every record with a different one of the 16 task families so
        // bounded exemplar storage and publication probes cover them all.
        const seed = cursor === 0 ? record % 16 : serial;
        const line = Buffer.from(`${makeExample(seed)}\n`, 'utf8');
        serial++;
        if (cursor + line.length > RECORD_BYTES) break;
        line.copy(block, cursor); cursor += line.length;
        writtenExamples++; totalExamples++;
      }
      if (record) await writeAll(txt, Buffer.from('\n---\n'));
      await writeAll(txt, block);
      const header = Buffer.alloc(10);
      header.writeBigUInt64LE(BigInt(RECORD_BYTES), 0); header[8] = 0; header[9] = 0;
      await writeAll(nbin, header); await writeAll(nbin, block);
      const sample = selectedLine(block, record + 1);
      await writeAll(samples, Buffer.from(`${JSON.stringify({record, category: record % 16, sample})}\n`, 'utf8'));
      if ((record + 1) % 50 === 0) console.log(`records=${record + 1}/${RECORDS} payload_bytes=${(record + 1) * RECORD_BYTES}`);
    }
    const metadata = Buffer.alloc(16);
    metadata.writeBigUInt64LE(BigInt(RECORDS), 0); metadata.writeBigUInt64LE(BigInt(RECORD_BYTES), 8);
    const metaFile = await open(META, 'w'); await writeAll(metaFile, metadata); await metaFile.sync(); await metaFile.close();
    await Promise.all([txt.sync(), nbin.sync(), samples.sync()]);
    console.log(`done records=${RECORDS} written_examples=${totalExamples} payload_bytes=${RECORDS * RECORD_BYTES}`);
    console.log(`txt_file_bytes=${(await txt.stat()).size} nbin_file_bytes=${(await nbin.stat()).size}`);
    console.log(`samples=${SAMPLES} metadata=${META}`);
  } finally {
    await Promise.all([txt.close(), nbin.close(), samples.close()]);
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
