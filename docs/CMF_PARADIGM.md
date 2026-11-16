# CMF — Causal Morphogenetic Field

**Durum:** uygulanmış, denetlenmiş, test edilmiş. Bu belge LIR'in **ikinci
paradigmasını** tanımlar. Birinci paradigma (fonksiyonel + veri odaklı çekirdek)
`LANGUAGE_REFERENCE.md`'de; üçüncü bir paradigma yok.

Kural aynı: **hiçbir iddia, ölçülenden veya test edilenden fazlasını söylemez.**
Bu belgede gecikme, enerji, hız, çekirdek sayısı gibi hiçbir sayısal donanım
iddiası yoktur. Buradaki tek "sayı" `lir cmf` çıktısındaki gerçek sayımlardır
(kaç witness, kaç varyant doğrulandı, kaçı reddedildi). Bunlar `tests/ai_test.py`
ve `src/bootstrap/tests.zig` tarafından sabitlenmiştir.

```
lir cmf examples/cmf/widening.cmf          # insan biçimi
lir cmf examples/cmf/hyperion.cmf          # HYPERION yüzeyi, alan olarak
lir cmf examples/cmf/hyperion.cmf --json   # lir.cmf.v1
```

---

## 0. Neden bu bir paradigma, bir sözdizimi değil

Dört programlama paradigması bir programı dört farklı şey olarak görür:

| Paradigma | Program nedir | Doğruluk nedir |
|---|---|---|
| Prosedürel | komut dizisi | ön/son koşullar |
| Nesne yönelimli | nesne grafiği + mesajlar | tip sözleşmesi (is-a) |
| Fonksiyonel | fonksiyon bileşimi | tip + eşitlik |
| **CMF** | **iddia alanı (field)** | **her iddianın bir yargıcı olması** |

CMF'de OOP'nin üç yük taşıyıcı fikri de yoktur:

- **is-a yok.** Bir morph, sınıf hiyerarşisi değil, *witness listesi*dir. Kalıtım
  diye bir şey yok; bir şekil diğerini genişletmez.
- **mesaj gönderme yok.** Bir field'a yazmak çağrı değil, *olay*dır. Çağrılan
  nesne, sanal tablo, dinamik dağıtım yoktur.
- **kapsülleme yok.** Gizlenecek durum yok; çünkü field zaten bir *yüzey*dir ve
  yüzeydeki iddialar açıkça yazılır.

Onun yerine üç hareket vardır: **şekil (morph) → altkatman (field) → taahhüt
(claim)**, ve bunları birleştiren **ifade (bloom)**.

---

## 1. Dört direktif

### 1.1 `morph` — şekiller

```
morph Cell =<< u8 u16 u32 u64 i64 >>=
morph Budget =<> u8 u16 u32 u64 <>=
```

- `=<< ... >>=` **kapalı** şekil: örnek kümesi tam olarak yazılan witness'lardır.
- `=<> ... <>=` **açık** şekil: örnekler bağlı tanım kümelerinden üretilir.

Bir morph'ta **tip parametresi** yoktur; *witness* vardır. Fark önemli: witness
bir değer ya da tip adı olabilir ve her witness için ayrı bir **somut program**
üretilir. "Her tip için aynı kod" (generic) değil, "her witness için *doğrulanmış*
kod" (construction) elde edilir.

Kapalı morph'ta witness yoksa hata: `LIR-E8003`.

### 1.2 `field` — altkatman

```
field ledger: u64[1024] ?exclusive
field window: i64[8]       ?shared
```

- `?exclusive`: tek yazıcı iddiası **denetlenebilir**.
- `?shared`: bu iddia geri çekilir; eşzamanlılık iddiası hâlâ denetlenebilir.
- Uzunluk 0 ise hata: `LIR-E8004` (hiç yer ayırmayan bir bölge iddia taşıyamaz).

### 1.3 `claim` — taahhütler

```
claim exclusive_writer over ledger check uniqueness
claim linear_use       over ledger for 4tick runtime adjudicate
claim total_order      over ledger check totality
```

Her iddia **nasıl yargılanacağını** söylemek zorundadır:

| Yargı biçimi | Anlamı | Uygulanan denetçiler |
|---|---|---|
| `check <n>` | derleme zamanı denetimi | `uniqueness`, `concurrency`, `totality`, `absence` |
| `runtime <n> for <k>tick` | çalışma zamanı yargıcı + sınır | serbest ad + zorunlu süre |
| `structural` | yapısal, yargı gerektirmez | — |

Uygulanmayan bir denetçi adı, çözülmeyen bir field, ya da süresi olmayan bir
yargıç **hatadır**: `LIR-E8005`, `LIR-E8006`. Hiçbir şeyin yanlışlayamadığı bir
iddia derlenmez — bu, repodaki "fail closed" kuralının dil seviyesine taşınmış
hâlidir.

### 1.4 `bloom` — ifade (ve **inşa**)

```
bloom narrow: morph Cell {
fn main() -> i64 {
    let cell: @witness = 200
    return cell as i64
}
}
```

`@witness` bir yer tutucudur. `lir cmf` bu gövdeyi **her witness için ayrı ayrı**
gerçek derleyiciden geçirir: lexer → parser → semantik analiz → IR doğrulama.

- Doğrulayan witness → **varyant** olur.
- Doğrulamayan witness → **reddedilir** ve *hiç üretilmez* (`LIR-E8008`).

Yani seçim tablosu (vtable) yerine **inşa edilmiş, önceden doğrulanmış varyant
kümesi** vardır. Reddedilen bir varyant çalışma zamanında seçilemez, çünkü
**yoktur**. Bu, HYPERION'un "önceden kanıtlanmış manifoldlar" fikrinin
uygulanabilir tek dürüst biçimidir: kanıt, tip teorisi değil, gerçek derleme.

Gerçek çıktı (`examples/cmf/widening.cmf`):

```
  variants (constructed, not declared)
    narrow/u8   verified: the expansion type-checks and passes IR verification
    narrow/u16  verified: the expansion type-checks and passes IR verification
    narrow/u32  verified: the expansion type-checks and passes IR verification
    narrow/u64  verified: the expansion type-checks and passes IR verification
    narrow/i64  verified: the expansion type-checks and passes IR verification

  variant surface: 5 witness instances advertised, 5 constructed and verified
```

Ve bir witness tutmayınca (`bool` içine `200` yazılamaz):

```
    narrow/u8    verified: the expansion type-checks and passes IR verification
    narrow/bool  rejected (never emitted)

  variant surface: 2 witness instances advertised, 1 constructed and verified, 1 refused
```

### 1.5 Vacuous varyant dürüstlüğü

Gövde `@witness`'ı hiç kullanmıyorsa, o varyant derlenir ama **hiçbir şey
kanıtlamaz**: witness değişse de aynı programdır. `lir cmf` bunu saklamaz,
`vacuous` olarak raporlar. (Sessizce "doğrulandı" saymak, bu repoda yasak olan
iddia şişirmesidir.)

---

## 1.6 HYPERION alanları → CMF direktifleri

HYPERION belgesindeki her katman, burada **denetlenebilir bir direktife** bağlanır.
Kural: bir alan ya *uygulanmış* olur (denetlenir/ölçülür), ya *planlı* olarak
ilan edilir (analiz edilir, **hiçbir iddiayı** karşılayamaz). Üçüncü yol yok.

| HYPERION katmanı | CMF'de karşılığı | Durum |
|---|---|---|
| §1 HQTT / tip başına pJ | — (pJ bir *tipin* değil, komut dizisinin fonksiyonudur) | ❌ reddedildi, `HYPERION_ASSESSMENT.md` §1.3 |
| §1 niyet→algoritma sentezi | `morph` + `bloom` (witness başına **gerçek** derleme) | ✅ uygulandı (`LIR-E8008`) |
| §1.4 nedensellik konileri / bariyersizlik | `claim`, `tune`, ve dilin mevcut `spawn`/`@chan_*` grafiği | ✅ kısmen (alan tarafı denetlenir) |
| §2 gölge zaman çizgileri | yalnızca `#[pure]` gövdeler speküle edilebilir (dilin kuralı) | 🟡 sınırlı |
| §3.1 cebirsel lens | **`lens`** — O(1) görünüm + *ölçülen* eleman maliyeti | ✅ uygulandı (`LIR-E8009`) |
| §3.2 Shannon sınırı sıkıştırma | — | ❌ 12× iddiası reddedildi |
| §3.3 PIM / aktif kapsül | **`machine pim: pim planned`** | 🟡 ilan edilir, iddia edilemez (`LIR-E8010`) |
| §4 öz-evrimleşen ikili kod | **`telemetry` + `tune`** (yalnızca *var olan* varyantı seçer) | ✅ uygulandı (`LIR-E8011/8012`) |
| §5 kuantum-dirençli ORAM | **`machine oram: oram planned`** | ❌ Ω(log n) teoremi; ilan edilir, iddia edilemez |
| §5 homomorfik veri düzlemi | **`machine fhe: fhe planned`** | ❌ 10³–10⁶× yavaş |
| §6 fotonik kumaş / küresel adres uzayı | — | ❌ ışık hızı |
| §8 2.5 ns yaşam döngüsü | — | ❌ tek DRAM erişimi 60–100 ns |

### `lens` — "sıfır kopya"nın dürüst hâli

```
field ledger: u64[104] ?exclusive ?contiguous
lens back:   reverse(ledger)            as backwards
lens hot:    filter(ledger where > 9)   as hot
lens pivot:  transpose(ledger*104)      as pivot
```

`lir cmf` her lens için **eleman maliyetini yazar**, çünkü görünümü kurmak O(1)
ama üzerinde yürümek bedava değildir:

| Lens | Eleman maliyeti | Neden |
|---|---|---|
| `reverse` | `sequential` | ters yönde de bitişik |
| `filter` | `predicated` | ziyaret edilen her eleman için bir yüklem testi |
| `transpose` | `strided` | stride bir cache satırını aşınca eleman başına bir satır |

Ayrıca **anlam denetimi**: `?ordered` bir alanı permüte eden lens reddedilir —
permütasyon, alanın verdiği sıralılık sözünü bozar (`LIR-E8009`).

### `machine` — "donanıma gönder" iddiasının dürüst hâli

```
machine local: local implemented
machine pim:   pim   planned
machine fhe:   fhe   planned
machine oram:  oram  planned
```

- `local` (bu repodaki IR VM) **tek** `implemented` sınıftır; başka bir sınıfı
  `implemented` yazmak derleme hatasıdır (`LIR-E8010`).
- `planned` bir makine **analiz için** ilan edilebilir, ama ona dayanan bir iddia
  **reddedilir**. Yani HYPERION'un PIM/FHE/ORAM katmanları alanda *görünür*,
  ama hiçbir taahhüdü sessizce üstlenemez.

### `telemetry` + `tune` — öz-evrimleşmenin dürüst hâli

```
telemetry cache: every 100tick
tune narrow: morph Cell under compressible
```

- `telemetry` bir **periyot** ilan eder (100 µs değil, 100 *tick*); gecikme iddiası
  değildir.
- `tune` yalnızca **zaten inşa edilmiş ve doğrulanmış** bir varyantı seçer; yeni
  kod üretmez, JIT yapmaz, "3 çevrimde mikrokod mutasyonu" iddia etmez.
- Tüketilmeyen bir telemetri kaynağı reddedilir (`LIR-E8011`); var olmayan bloom'a
  ya da uyuşmayan morph'a bağlı bir kural reddedilir; ölçüme dayanan bir kural
  telemetri kaynağı yoksa reddedilir (`LIR-E8012`).

### Ölçüm — tahmin değil

Doğrulanan her varyant IR VM'de **çalıştırılır** ve gerçekten yürütülen komut
sayısı raporlanır:

```
narrow/u8   verified: type-checks + passes IR verification, then measured:
            2 IR instructions, exit 200
```

Bu repoda "kaç çevrim/pJ sürer" sorusunun tek dürüst cevabı budur: ölçülen.
(`HYPERION_ASSESSMENT.md` §1.3'teki tablo, gerçek donanım gecikmeleriyle
karşılaştırmayı zaten yapıyor.)

---

## 2. Ne yapar, ne yapmaz

| Yapar | Yapmaz |
|---|---|
| Her iddiayı bir denetçiye/yargıca bağlar veya reddeder | İddiaları *ispatlamaz*; denetçi adları beyan edilir, SMT yoktur |
| Her bloom witness'ı için gerçek derleme çalıştırır | Kodu çalıştırmaz, ölçmez, süre tahmin etmez |
| Reddedilen varyantı üretmez (fail closed) | Donanıma kod göndermez, ORAM/PIM/FHE uygulamaz |
| `lir.cmf.v1` JSON + `LIR-E8001/8005/8008` teşhisleri verir | Yeni bir çalışma zamanı, GC veya eşzamanlılık modeli getirmez |

Sınırlar bilinçlidir: **mimari değil, dil.** Bu yüzden iddia edilebilir tek şey
şudur — *"bu dosyadaki her taahhüdün bir yargıcı var ve her varyant gerçekten
derlendi"*. Daha fazlası, `docs/HYPERION_ASSESSMENT.md`'deki gerekçelerle
reddedilir.

---

## 3. OOP ile karşılaştırma (aynı işi yapan üç satır)

| İhtiyaç | OOP | CMF |
|---|---|---|
| Farklı genişliklerde aynı mantık | arayüz + 5 sınıf + vtable | `morph Cell =<< u8 u16 u32 u64 i64 >>=` + bir gövde |
| Hangi varyantın çalışacağı | çalışma zamanında seçilir, hatası çalışma zamanında görülür | varyant önceden derlenir; derlenmeyen **hiç yoktur** |
| "Tek yazıcı" garantisi | yorum + disiplin | `?exclusive` + `check uniqueness` — denetçisi yoksa derlenmez |
| Yeni bir genişlik eklemek | yeni sınıf, yeni test | witness listesine bir ad; derleyici gerisini inşa eder |
| Kalıtım | var | **yok** (bilinçli) |

---

## 4. Neden "devrimsel" kelimesi burada ölçülü kullanılıyor

HYPERION belgesindeki devrim iddiaları (2.5 ns yaşam döngüsü, sıfır gecikmeli
ORAM, kıtalararası tek adres uzayı) `docs/HYPERION_ASSESSMENT.md` §1'de
teorem/fizik ile çürütüldü. CMF bunları **taklit etmez**. Devrim, ölçülebilir tek
yerde duruyor:

> **Bir program artık "derlenmiş ya da derlenmemiş" değil; her witness için ayrı
> ayrı derlenmiş ve reddedilenlerin *var olmadığı* bir varyant kümesidir.**

Bunu iddia etmek için gereken tek şey, bunu yapan bir komut ve onu sabitleyen
testlerdir; ikisi de bu repoda var.

---

## 5. Dosyalar

| Dosya | İçerik |
|---|---|
| `src/bootstrap/cmf.zig` | alan okuyucu, denetleyici, inşa edici, JSON/insan çıktısı, 9 birim testi |
| `src/bootstrap/diag.zig` | `LIR-E8001..8012` kodları |
| `src/bootstrap/explain.zig` | `lir explain LIR-E8008` vb. |
| `src/bootstrap/main.zig` | `lir cmf <file>` komutu |
| `tests/ai_test.py` | `CmfTests` — 15 uçtan uca test (kabul, ret, vacuous, JSON, lens maliyeti, planlı makine, telemetri, örnek dosyalar) |
| `src/bootstrap/tests.zig` | 5 birim testi (örnek alan, reddedilen witness, iç içe bloklar, HYPERION yüzeyi, planlı makine) |
| `examples/cmf/widening.cmf` | minimal çalışan örnek |
| `examples/cmf/hyperion.cmf` | HYPERION'un tüm katmanları, alan olarak |
