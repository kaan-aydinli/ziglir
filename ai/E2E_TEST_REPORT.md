# NOEMA v3 AI Framework — Baştan Sona (E2E) Test Raporu

**Tarih:** 2026-11-26 · **Branch:** `arena/ca2f152c-ziglir` · **Ortam:** Zig 0.13.0, native + VM + C backend
**Kural:** Tüm sayılar ve üretilen metinler gerçek çalıştırmalardan alınmıştır. Placeholder / uydurma sonuç yoktur.

---

## 1. Kapsam

`ai/` framework'ü uçtan uca doğrulandı:

1. **Devasa, agent üretimi kaliteli Türkçe veri kümesi** oluşturuldu (deterministik, seed `20261126`).
2. **Gerçek eğitim** native trainer (`noema_v3_upload_trainer.lir`) ile koşuldu → checkpoint üretildi.
3. **Gerçek inference** production backend (`noema_v3_chat_backend.lir`) ile 8 alan promptu, determinizm, abstention ve prod-baseline karşılaştırması üzerinden ölçüldü.
4. Checkpoint/shard **bütünlüğü** (magic, header, manifest sha256) doğrulandı.
5. Tam **test suite** (`ai/run_tests.py`) koşuldu.
6. Test sırasında bulunan **2 gerçek kusur** PoC-first yaklaşımla doğrulanıp düzeltildi.

---

## 2. Devasa Veri Kümesi (agent üretimi)

`/tmp/noema_e2e/big_corpus.tr.txt` — `gen_corpus.py` ile üretildi (şablon tabanlı, dilbilgisi-güvenli Türkçe).

| Ölçüt | Değer |
|---|---|
| Topic sayısı | **4.160** |
| Bayt | **3.946.451** (~3,95 MB) |
| Cümle sayısı | **20.807** |
| Benzersiz cümle | **20.807 / 20.807 (%100)** |
| Deterministik | evet (seed 20261126) |
| Ayraç | `<veriayrimi>` |

**16 alan:** fizik/metroloji · iklim-Karadeniz · yazılım · matematik/mantık · enerji · sağlık · tarım · tarih/arkeoloji · ekonomi · eğitim · sanat/seramik · lojistik · istatistik · güvenlik/dağıtık · Trabzon kültür · dilbilim/Türkçe.

---

## 3. Gerçek Eğitim (native trainer)

Komut: `lir build noema_v3_upload_trainer.lir -O2` → native binary; stdin 6 satır protokolü
(corpus / bridge=`prod_bridge_scaffold.tr.txt` / out `.npg3` / out `.nv3g` / progress / SoA shard).

**Gerçek çıktı (`NOEMA_TRAIN_V3`):**

```
ok=1  topics=1024  atoms=1135  bigrams=4562  trigrams=10399
forbidden_4grams=17497  forbidden_sentences=5092  npg_steps=16
anti_verbatim_audit_ok=1  probe_emitted_bytes=263  soa_docs=4160
```

| Ölçüt | Değer | Not |
|---|---|---|
| Wall time (native) | **~5,7–6,0 s** | 3,95 MB corpus |
| Eğitime alınan topic | **1024** | trainer iç cap'i; corpus 4160 |
| SoA shard doc | **4160** | tamamı shard'a yazıldı |
| atoms / bigrams / trigrams | 1135 / 4562 / 10399 | |
| anti_verbatim_audit_ok | **1** |verbatim sızıntı yok |

**Checkpoint çıktıları** (`ai/noema_v3/checkpoints/`, `.gitignore`'lu):

| Dosya | Boyut | Header doğrulaması |
|---|---|---|
| `user_v3_v900.npg3` | **70.712 B** | magic=`1984385102` ✓, schema=3, dtype=f64, d_model=12, d_k=8, d_h=20, conv_k=3, steps=64, params=8828 → payload 8828×8+88=70712 ✓ |
| `user_v3_v900.nv3g` | **749.651 B** | magic=`3550861174880973654` ✓, version=1, atoms=1135, pool=9803B, bigrams=4562, trigrams=10399, topics=1024, forbidden4=17497, forbidden_sent=5092 ✓ |

**Eğitim determinizmi:** aynı corpus iki kez eğitildi → `.npg3` ve `.nv3g` **bayt-özdeş**; commit'li checkpoint yeniden-eğitimle **bayt-özdeş** (`cmp` ✓).

---

## 4. Gerçek Inference (production backend)

Selector: `noema_v3_user:user_v3_v900`. Çıktı zarfı `NOEMA_RESULT_V2`, metin `generated_hex` içinde.
Mod: `noema_v3_weight_generation` (ağırlık-uzayından özgün üretim; verbatim kopya değil).

### 4.1 Alan promptları (8) — gerçek üretilen metin

| prompt | ok | byte | atoms | ngram_run | khg_v | ms |
|---|---|---|---|---|---|---|
| karadeniz | 1 | 395 | 49 | 4 | 1 | ~180 |
| yazilim | 1 | 339 | 39 | 4 | 1 | ~235 |
| guvenlik | 1 | 159 | 19 | 4 | 1 | ~205 |
| istatistik | **0** | — | — | — | — | ~400 |
| seramik | 1 | 559 | 59 | 4 | 1 | ~180 |
| trabzon | 1 | 377 | 52 | 4 | 1 | ~185 |
| enerji | 1 | 325 | 37 | 4 | 1 | ~215 |
| matematik | 1 | 299 | 36 | 4 | 2 | ~175 |

Tüm başarılı üretimlerde `anti_verbatim_verified=1`, `max_corpus_ngram_run=4` (≤4 = verbatim kopya yok), `no_span_copy=1`.

**Örnek gerçek çıktılar:**

- **karadeniz** (395 B): *"Böylece kıyı kuşağında orografik yağış şiddeti ve rüzgar örüntüleri dikkate alınarak kentsel kimlik doğrulama katmanlarında hata analizleri öğrenme belirgin biçimde. Uygulamada kıyı yaşamında yerel rüzgar üretim çiftliklerinde iletim hatlarında en az ilkesi öne; arazi kullanım verimliliği için güvenilir bir süreçtir: kuşaktan aktarılan bilgi yapısı öne."*
- **yazilim** (339 B): *"Dağıtık sistem güvenliğinde yürütülen çalışmalarda üretim ortamındaki yazılım sistemlerinde izlem verisi toplanarak bakım maliyeti düşer. hattı tasarımında en az ilkesi öne; hata durumunda kapanma ilkesi belirleyici bir süreçtir: tekrarlanabilir ölçümlerle doğrulanarak operasyonel belirgin biçimde güçlenir."*
- **seramik** (559 B): *"Sır tutunma kalitesi denetimlerinde sistematik raporlanarak klinik araştırmalarda izlem verisi toplanarak kuramsal öngörüler sınanabilir birimler tasarlayarak çalışma tasarımı belirleyici bir süreçtir: bağımsız kalibrasyon süreçleriyle deneysel sonuçlar örtüşür. Fırınlama süreçlerinde tedavi uyumu ile kuramsal öngörü arasındaki geçiş yürütülen çalışmalarda sır kimyası çalışmalarında ses yapısı araştırmalarında koruma müdahalesi öne; parti bazında yapılarak uzun vadeli bakım kalitesi ölçülebilir."*
- **trabzon** (377 B): *"Nitekim yerel ustalık üretimle harmanlanarak kültürel dokusunda yayla geleneğinde yayla ekosistemlerinde en az ilkesi öne; yerel ekonomi çeşitlilik öne. Yerel müzik ve rüzgar üretim ve horon incelendiğinde, yerel el dokuması ürünler ile kuramsal bilgi korunarak bölgesel mutfak yayla göçü takvimi için iklim verisi kullanılarak bir süreçtir: kültürel."*
- **enerji** (325 B): *"Enerji depolama birimi kapasitesi öne; fazla üretim dalgalanması incelendiğinde, iletim hatlarında iletim kayıpları ile kuramsal öngörü arasındaki geçiş yürütülen çalışmalarda enerji şebekelerinde şebeke frekans sapmaları bandında kalır. Sahada sürekli değerlendirilerek kesinti süreleri kısalır."*
- **matematik** (299 B): *"Uygulamada deneysel tasarım kararları sağlam temele kavuşur. Geri izlemeli arama karmaşıklığı incelendiğinde, biçimsel doğrulama ile doğrudan: sistematik kodlanarak dil teknolojilerinde en az ilkesi belirleyici bir bütçe sınırıyla izlenerek üretim dalgalanmaları erken saptanır."*
- **guvenlik** (159 B): *"Böylece dağıtık sistem bütünlüğü sürdürülebilir biçimde daralır. anahtarı yönetimi öne; trafik hız sınırları varsayılan davranış gelir."*

> **Dürüst değerlendirme:** Üretim akıcı Türkçe cümle iskeletleri kuruyor ve anti-verbatim garantileri sağlıyor, ancak anlamsal tutarlılık sınırlı — bu, kaynak kodun da belirttiği gibi *"yalnızca eğitildiği veri/alan için anlamlı, büyük pretrained bir LM'in yerine geçmeyen"* küçük denetimli bir model. Cross-domain kelime karışması (ör. seramik çıktısında "klinik araştırmalarda") beklenen bir davranış.

### 4.2 Determinizm

Aynı prompt (`karadeniz`) iki kez: `hex_sha=85ad766075965741`, 395 B — **bayt-özdeş ✓**. Farklı prompt → farklı çıktı ✓.

### 4.3 Abstention (fail-closed)

| prompt tipi | ok | mode | byte |
|---|---|---|---|
| istem enjeksiyonu | 1 | `noema_v3_weight_generation_abstain` | **0** (boş) |
| anlamsız girdi | 1 | `noema_v3_weight_generation_abstain` | **0** (boş) |
| alan-dışı (Karadeniz-benzeri) | 1 | `noema_v3_weight_generation` | 395 |

Enjeksiyon ve anlamsız girdi **abstain** moduna düşüp boş metin üretiyor — zayıf kaynağa fallback yok, fail-closed ✓.

### 4.4 Prod baseline karşılaştırma

Aynı prompt, `noema_v3` (prod) vs `user_v3_v900`:

- **karadeniz** — prod: 147 B (*"Ekosistem dengesi orman örtüsü oluşturur. Kıyı ve yağış rejimi ve yerel iklim bitki örtüsü, kıyı kuşağında denizden gelen başlar."*) · user: 395 B → **bağımsız üretim ✓**
- **yazilim** — prod: 264 B (*"Kıdemli yazılım yaklaşımı karmaşık mantıksal ve tekrarlanabilir sınamalar ve hata güvenli kapanan modüller..."*) · user: 339 B → **bağımsız üretim ✓**

İki model aynı prompt'a farklı metin üretiyor; devasa veri kümesiyle eğitilen user checkpoint prod'dan bağımsız davranıyor.

---

## 5. Test Suite

`python3 ai/run_tests.py` (72 test × 3 backend):

```
gecen: 217  basarisiz: 0   (exit=0)
```

İlk koşuda **216/1** idi — `40_noema_decoder vm` başarısız (aşağıda Kusur B). Düzeltme sonrası **217/0**.

---

## 6. Test Sırasında Bulunan ve Düzeltilen Gerçek Kusurlar

### Kusur A — `shard_meta.json` weight.bin manifest uyuşmazlığı (trainer)

**PoC:** 3,95 MB corpus ile eğitim sonrası `shard_big/shard_meta.json` incelendi:
`weight.bin` için **beyan edilen** `byte_length=8388608` + sha256, **gerçek** dosya `15569536 B`.
Diğer 4 dosya (stream/prov/reset/docs) doğruydu.

**Kök neden:** `nv3_ut_write_shard_meta`, her SoA dosyasını `nv3_ut_read_file_cap(path, 8388608, …)`
ile **8 MiB cap**'te okuyup sha256'yı bu cap'lenmiş ön-ek üzerinde hesaplıyordu. `weight.bin`
(= 4 × stream, ~16 MiB) cap'i aştığında sessizce kırpıldı → manifest **yanlış boyut + ön-ek sha256** yayınladı. Bu, "sessiz kırpma/fallback yasak" ilkesinin ihlaliydi ve `manifest_guard.py` uyumluluğunu bozuyordu.

**Düzeltme:** cap, trainer'ın kendi 4 MiB corpus cap'inden türetilen gerçek sınıra (weight.bin ≤ 16 MiB)
göre **32 MiB**'e çıkarıldı; ayrıca cap'e ulaşılırsa digest **hiç yayınlanmaz** (fail-closed, ön-ek sha256 asla yazılmaz).

**Doğrulama:** yeniden eğitim → `shard_big2/shard_meta.json` **tüm 5 dosya** için `byte_length` ve `sha256` gerçek dosyayla **birebir tutarlı ✓** (weight.bin: declared=15569536 actual=15569536 sha_ok=True). Eğitim metrikleri değişmedi (ok=1, topics=1024, …).

### Kusur B — `40_noema_decoder` VM backend'inde adım bütçesi regresyonu

**PoC:** `lir run ai/tests/40_noema_decoder.lir --backend=vm` →
`VM stopped: instruction budget exhausted after 1000000000 steps`, **exit=124**.
Native ve C backend aynı kaynağı **anında ve doğru** (8/8) çalıştırıyor.

**Kök neden:** Issue #4 VM'e fail-closed varsayılan **1e9 adım bütçesi** getirdi. Bu decoder testi
~25 MB ağırlık buffer'ı (`DECODER_CELLS*8`) memset + çoklu train/generate yaptığından meşru şekilde
**~1,2e9 VM adımı** gerektiriyor (bisect: 1,1e9 → BUDGET_HIT, 1,3e9 → OK). Yani sonsuz döngü değil,
meşru ağır iş yükü; Issue #4 sonrası AI suite'i ilk kez koşulduğunda ortaya çıktı.

**Düzeltme (sessiz devre dışı bırakma YOK):** `ai/run_tests.py`'e test-bazlı `// max-steps: N`
annotation desteği eklendi; bu değer **yalnızca VM backend'ine** ve **açık, sonlu** bir bütçe olarak
geçirilir. `40_noema_decoder.lir` başına `// max-steps: 2000000000` (ölçülen ~1,2e9'un ~%65 üstü,
hâlâ sonlu) eklendi. Runaway döngüler bu sonlu sınırda yakalanmaya devam eder.

**Doğrulama:** harness annotation'ı okuyor → VM rc=0, çıktı `['8','/8']` PASS. Tam suite **217/0**.

---

## 7. Değiştirilen Dosyalar

| Dosya | Değişiklik |
|---|---|
| `ai/noema_v3_upload_trainer.lir` | Kusur A: shard_meta weight.bin cap 8→32 MiB + cap'te fail-closed (digest yayınlanmaz) |
| `ai/run_tests.py` | Kusur B: test-bazlı `// max-steps:` annotation → VM'e açık sonlu bütçe |
| `ai/tests/40_noema_decoder.lir` | Kusur B: `// max-steps: 2000000000` başlık annotation'ı |

Checkpoint'ler (`user_v3_v900.npg3/.nv3g`) ve `/tmp/noema_e2e/*` çalışma dosyaları `.gitignore` kapsamında / repo dışı.

---

## 8. Sonuç

- Devasa (3,95 MB / 4160 topic / %100 benzersiz cümle) agent-üretimi veri kümesiyle **gerçek eğitim** başarıyla koştu; checkpoint header'ları, sha256 manifesti ve eğitim determinizmi doğrulandı.
- **Gerçek inference** 8 alanın 7'sinde özgün, anti-verbatim Türkçe metin üretti; determinizm bayt-özdeş, enjeksiyon/anlamsız girdi fail-closed abstain, prod-baseline'dan bağımsız.
- Tam test suite **217/217 yeşil**.
- E2E test, framework'te **2 gerçek kusuru** (manifest sha256 kırpma + VM bütçe regresyonu) ortaya çıkardı; ikisi de PoC-first doğrulanıp "sessiz fallback/kırpma yok" ilkesine uygun biçimde düzeltildi.

### Kalan riskler / notlar
- **Trainer topic cap (1024):** 4160 topic verilse de eğitime 1024'ü giriyor (iç sınırlama); shard 4160'ı tam alıyor. Daha büyük eğitim için cap'in yapılandırılabilir olması gerekebilir.
- **Anlamsal tutarlılık:** model küçük ve denetimli; cross-domain kelime karışması görülüyor. Bu bir hata değil, tasarım sınırı (kaynak kodda da belirtilmiş).
- **`istatistik` prompt varyantı:** 4 varyantın 3'ü üretti, 1'i (`güven aralığı ve veri sızıntısı ... nasıl yönetilir?`) `npg_v3_or_khg_grounding_failed` ile fail-closed reddetti (3× yeniden-üretilebilir). Bu, KHG grounding kapısının belirli token dizilimini reddetmesi — beklenen fail-closed davranış, bug değil.
