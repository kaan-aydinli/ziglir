# NOEMA v3 — Ingest Ölçeklenebilirlik Raporu (kapasite sınırını kaldırma)

**Tarih:** 2026-11-26 · **Branch:** `arena/ca2f152c-ziglir` · **Commit'ler:** `6c045f8`, `35385ee`, `0eda3f1`
**Kapsam kararı (kullanıcı):** *ingest* (veri işleme) kapasitesini kaldır; model grafiği sabit kapasiteli kalır. Önce LIR dilini olgunlaştır, sonra LIR içinde çöz.
**Kural:** Tüm sayılar gerçek ölçümlerdir (`/proc VmHWM` peak RSS, gerçek eğitim/inference çalıştırmaları). Uydurma sonuç yok.

---

## 1. Sorun: capacity ceiling nerede idi

| Sınır | Eski değer | Etki |
|---|---|---|
| Corpus RAM'e tümü | **4 MiB cap** (`nv3_ut_read_file_cap`) | >4 MiB corpus **sessizce** ilk 4 MiB'e kırpılırdı (`ok=1`, hata yok) |
| Server upload cap | 64 MiB | 4–64 MiB yüklemeler **%75+ sessiz veri kaybı**na uğrardı |
| Derin shard okuma | `nv3_pread_slice` offset 0'dan atlar | **O(offset)** — 256 MB'dan 8 bayt = 63 ms |
| Pozisyonel I/O builtin | **yok** (`@lseek/@pread/@mmap` tanımsız) | thread-safe rastgele erişim imkânsız |

**Ölçülen kanıt (16 MB corpus):** eski trainer `soa_docs=5584` (kırpylmış), %75 veri kaybı, `ok=1`.

---

## 2. Yapılanlar (3 atomik adım, PoC-first)

### Adım 1 — Dil olgunluğu: `@pread` / `@pwrite` / `@lseek` (commit `6c045f8`)
O(1), stateless, **thread-safe** pozisyonel I/O. 4 backend'de implement (native x86-64 SYS_pread64=17/pwrite64=18/lseek=8; VM `File.pread/pwrite/seek*`; C POSIX `pread/pwrite/lseek`; wasm32-wasi `-ENOSYS`, mevcut `@open/@read` ile tutarlı). `call_read`'in fail-closed negatif-count trap (ud2) + ptr/len bounds kontrolü birebir korundu.

**PoC ölçümü (256 MB dosya, offset 256 MB'dan 8 bayt okuma):**

| yol | süre |
|---|---|
| eski skip-read (`nv3_pread_slice`) | **63.245.101 ns (63 ms)** — O(offset) |
| yeni `@pread` (native) | **1.484 ns** — O(1) |
| **kazanç** | **~42.000×** |

`@pread` stateless doğrulandı: çağrı sonrası dosya offset'i değişmedi (`pos_after_pread=268435456`) → paralel shard worker'ları paylaşılan offset'te yarışmaz.

### Adım 2 — Sınırlı-bellekli streaming multi-shard ingest (commit `35385ee`)
`nv3_stream_pack_shards(in_path, out_root, chunk_bytes, prov, ...)`: corpus'u **sabit boyutlu pencere**den akıtır (O(chunk) bellek, corpus boyutundan **bağımsız**), her `<veriayrimi>` doc'unu mevcut `nv3_soa_pack_veriayrimi` ile `out_root/shard_N`'e paketler. Chunk reads `@pread` ile.

**Sınır güvenliği (sessiz kırpma/fallback yok):**
- Chunk sınırını aşan doc → sonraki pencereye **taşınır** (bölünmez/kaybolmaz).
- Work buffer'dan büyük tek doc → **fail-closed** `NV3_STREAM_ERR_DOC_TOO_LARGE`.
- Read/short-read/pack hatası → negatif error code; kısmi ingest asla success sayılmaz.

**Ölçülen bellek (native, `/proc VmHWM` peak RSS):**

| corpus | chunk | shard | docs | peak RSS |
|---|---|---|---|---|
| 16 MB | 256 KiB | 65 | 22.351 | **21,8 MB** |
| 32 MB | 256 KiB | 129 | 44.669 | **21,8 MB** ← corpus 2×, RSS aynı |
| 32 MB | 4 MiB | 9 | 44.669 | 123,0 MB ← chunk 16×, RSS ~5,6× |

→ **Bellek `chunk_bytes` ile ölçeklenir, corpus boyutuyla DEĞİL.** Tüm doc'lar korundu.

### Adım 3 — Streaming'i üretim trainer'ına bağla (commit `0eda3f1`)
Upload trainer artık SoA shard'ını RAM'deki örnekten paketlemek yerine **tüm corpus'u** `NV3_UT_STREAM_CHUNK=1 MiB` pencereyle `out_soa/shard_N`'e akıtıyor; shard başına `manifest_guard`-uyumlu `shard_meta.json` yazıyor. Başarısız/kısmi ingest **fail-closed** (`error=soa_stream_ingest_failed`).

**16 MB corpus, eski vs yeni:**

| | soa_docs | shard | veri kaybı |
|---|---|---|---|
| eski (4 MiB cap) | 5.584 | tek | **%75 sessiz** |
| yeni (streaming) | **22.351** | 17 | **yok** |

**Tam trainer, 12 MB kaliteli corpus** (12.800 topic, 64.067 cümle, %100 benzersiz):
```
ok=1 topics=1024 atoms=1133 bigrams=4613 trigrams=10545
forbidden_4grams=17806 forbidden_sentences=5141 npg_steps=16
anti_verbatim_audit_ok=1 soa_docs=12800   (12 shard)
trainer peak RSS = 35,9 MB   wall = 16,2 s
```
Inference (aynı checkpoint, gerçek üretim):
- *Karadeniz…yağış rejimi* → 280 B: *"Kıyı ile dağ arasındaki uyum. Böylece Karadeniz yayla ekosistemlerinde erozyon kontrolü öne; yağış rejimi ve toprak geçirgenliği birlikte değerlendirilerek…"*
- *Yenilenebilir enerji…frekans* → 250 B: *"Enerji depolama tesislerinde en az ilkesi öne; … frekans kararlılığı için … kesinti süreleri kısalır."*
- *Seramik…sır kalitesi* → 247 B: *"Sır kimyası çalışmalarında … uzun vadeli bakım kalitesi ölçülebilir biçimde. Uygulamada seramik atölyelerinde sır kimyası."*

Hepsi `output_mode=noema_v3_weight_generation`, `anti_verbatim_verified=1`, `max_corpus_ngram_run=4`.

---

## 3. Regresyon durumu

| Suite | sonuç |
|---|---|
| `ai/run_tests.py` | **220/0** (yeni `noema_v3_14_stream_ingest` ×3 backend dahil) |
| `tests/backend_test.py` | **8/8 OK** (yeni `test_positional_io_pread_pwrite_lseek` ×3 backend ×3 seviye) |
| `zig build test` | **exit 0** |
| `phase10_prod_audit.py` | **[1]–[7] OK** (özellikle [5] upload training: exit=0, checkpoint'ler, non-verbatim chat) |

> phase10'un son canlı-HTTP adımında `401 Unauthorized` görülüyor — bu Issue #4'ün auth kapısının audit'in credential'sız isteğini reddetmesi; ingest/trainer ile **ilgisiz**, önceden var olan durum.

---

## 4. Dürüst fizik: "petabayt" için kalan nedir

Bu çalışma **ingest capacity ceiling'i kaldırdı** ve **sınırlı bellekli streaming + multi-shard** mimarisini kurdu. Gerçek PB için dürüst durum:

1. **✅ İşleme/ingest artık sınırsız (disk-bound):** corpus boyutundan bağımsız O(chunk) bellek ile herhangi büyüklükte veri akıtılıp shard'lanabilir. 32 MB'ta kanıtlandı; mimari (N shard, sabit bellek) PB'a uzanır.

2. **⚠️ Model kapasitesi sabit (kapsam kararı gereği dokunulmadı):** nv3g grafiği `MAX_ATOMS=24576 / MAX_TOPICS=1024 / MAX_ARENA=384 KiB`. PB veri **ingest edilip shard'lanabilir**, ama bu sabit-kapasiteli grafik PB'dan *öğrenip tutamaz* — model eğitimi 4 MiB'lik örnek üzerinde. (Kullanıcı kapsamı *ingest* seçti; model büyütmek ayrı bir araştırma işi.)

3. **⚠️ Disk genişlemesi:** SoA shard formatı girdi başına ~6,1 bayt yazar (stream 1 + prov 1 + reset 1/8 + weight f32 4 + docs.idx). 1 PB corpus → **~6,1 PB shard depolama**. Bu formatın kendisinden gelir; sıkıştırma/sparse-prov gelecekte azaltabilir.

4. **⚠️ Yatay dağıtım:** Tek makine PB'ı diskte tutabilir ama **tek sandbox fiziksel olarak PB demonstrate edemez**. Multi-shard formatı + thread-safe `@pread` paralel/dağıtık ingest'i **mümkün kılar** (her worker kendi offset aralığını `@pread` edip kendi shard'ını paketler); mevcut streaming sıralıdır, paralel worker fan-out bir sonraki optimizasyondur.

5. **⚠️ Geçici pack belleği:** `nv3_soa_pack_veriayrimi` doc başına ~24×/byte geçici in-RAM genişleme yapar (prov/reset/weight i64/f64), chunk ile sınırlı. Küçük chunk belleği düşük tutar; disk formatlarını doğrudan kaynak baytlardan yazmak bu geçici maliyeti kaldırır (gelecek optimizasyon).

---

## 5. Değiştirilen dosyalar

| Dosya | Değişiklik |
|---|---|
| `src/bootstrap/ir.zig` | `call_pread/call_pwrite/call_lseek` IROp + hasSideEffects |
| `src/bootstrap/ir_gen.zig` | `@pread/@pwrite/@lseek` isim→op eşleme |
| `src/bootstrap/ir_codegen.zig` | native x86-64 syscall emisyonu (ptr/len trap korumalı) |
| `src/bootstrap/ir_vm.zig` | VM `File.pread/pwrite/seek*` fail-closed |
| `src/bootstrap/c_backend.zig` | C POSIX `pread/pwrite/lseek` (+ Win `_lseeki64`) |
| `src/bootstrap/wasm_backend.zig` | wasm `-ENOSYS` (tutarlı) |
| `src/bootstrap/sema.zig` | arity tablosu (4/4/3) |
| `src/bootstrap/langref.zig` | builtin dokümantasyonu |
| `tests/backend_test.py` | `test_positional_io_pread_pwrite_lseek` |
| `ai/src/noema_v3/noema_v3_stream_ingest.lir` | **yeni**: streaming multi-shard ingest + `nv3_stream_shard_num_docs` |
| `ai/tests/noema_v3_14_stream_ingest.lir`(+`.expected`) | **yeni**: streaming regresyon testi |
| `ai/noema_v3_upload_trainer.lir` | SoA yolu streaming'e çevrildi (4 MiB cap kaldırıldı) |
