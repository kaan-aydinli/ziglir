# SEL — Sparse Eikonal Ledger

LIR dili ile yazılmış, **sıfır bağımlılıklı** bir öğrenme çekirdeği.

```lir
import "ai/src/ledger.lir"

fn main() -> i64 {
    let h = block_new(2, 24, 2, 3)     // 2 girdi -> 24 gizli, K=2 seyrek
    let o = block_new(24, 1, 24, 5)    // 24 -> 1 çıktı
    // ... ileri geçiş + eikonal güncelleme
}
```

## Durum

**Uygulanmış ve test edilmiş.** Beş test, üç backend'de (native, VM, C)
birebir aynı sonucu veriyor: **15/15**.

| test | ne kanıtlar | sonuç |
|---|---|---|
| `01_fixed_point` | Q32.32 aritmetiği doğru (mul, div, sqrt, doygunluk) | 9 değer birebir |
| `02_learn` | öğrenme enerjiyi gerçekten düşürüyor | 2^17 = 131.000x |
| `03_xor` | doğrusal olmayan problem çözülüyor | **4/4** |
| `04_search` | ters indeks + sıralama | belge 4, sonra 3 |
| `05_math` | gcd, mod_pow, mod_inv, is_prime, fpow | 8 değer birebir |
| `06_codec` | tokenizer'sız kodlama + kod imzası | 5/5 |
| `07_translate` | hizalama defteri (çeviri) yakınsıyor | 2/2 |
| `08_agent` | araç yönlendirici doğru aracı seçiyor | 2/2 |

**8 test × 3 backend = 24/24.**

```bash
export PATH=/tmp/zv13/ziglang:$PATH
zig build -Doptimize=ReleaseFast
python3 ai/run_tests.py          # 24/24
python3 ai/bench/run.py          # ölçüm tablosu
```

## Tasarım

Tam belge: [`docs/DESIGN.md`](docs/DESIGN.md).

- **Sayı formatı:** Q32.32 sabit nokta, tamamen `i64`. Float yok, 16-bit yok,
  bit tabanlı yok.
- **Öğrenme kuralı:** eikonal (NLMS) güncelleme — gradyan yok, momentum yok,
  Adam yok. Her kenar tek bir `tau` tamsayısı taşır.
- **Mimari:** seyrek "ledger" katmanı — her nöron sabit `K` kenar taşır,
  bellek `O(n·K)`.
- **Tokenizasyon yok:** girdi sürekli bir vektör.

## Ölçülen hız

| iş | SEL | LLVM C ikizi | oran |
|---|---:|---:|---:|
| 3 katmanlı ağ (2112 kenar × 2000 adım) | 126 ms | 6.1 ms | 20.6x |
| Q32.32 matmul 96³ | 17.3 ms | — | — |
| XOR eğitimi (12.000 güncelleme) | 45.0 ms | — | — |

Farkın kaynağı ölçüldü: LIR'in `@read_u64`/`@write_u64` builtin'leri her
erişimde sınır kontrolü yapıyor. Bu, dilin bellek güvenliği sözleşmesinin
bedeli — gizlenmiyor.

**Rust ölçümü yoktur**; bu ortamda Rust çalıştırılamıyor. Karşılaştırma
yalnızca C ile ve öyle etiketlenerek yapılmıştır.

## Ne değildir

Bu, GPT/Gemini/Claude ile yarışan bir model değildir ve olduğu iddia
edilmiyor. GPT seviyesi, mimariden değil **veri ve hesaplama ölçeğinden**
gelir. Buradaki şey, o ölçeğe çıkabilecek *mekanizmanın* kendisi: taşınabilir,
deterministik, sıfır bağımlılıklı bir eğitim çekirdeği.

## Yetenek katmanları

| istenen yetenek | bu depodaki karşılığı | durum |
|---|---|---|
| matematik | `src/math.lir` — gcd, mod_pow, mod_inv, is_prime, fpow | çalışıyor, test 05 |
| arama | `src/search.lir` — ters indeks, top-k | çalışıyor, test 04 |
| kod | `src/codec.lir` — rotation-encode + yapısal imza | çalışıyor, test 06 |
| çeviri | `src/translate.lir` — hizalama defteri (NLMS matris) | çalışıyor, test 07 |
| araç kullanımı | `src/agent.lir` — öğrenilmiş araç yönlendirici | çalışıyor, test 08 |
| sohbet | çekirdek + yönlendirici; diyalog verisi gerekir | mekanizma var |

Sohbet, diğerlerinden farklı: bir mekanizma sorunu değil, **veri** sorunu.
Çekirdek (ledger + eikonal + kodlama) hazır; diyalog kalitesi, bu depoda
bulunmayan bir veri kümesini gerektirir. Bunu abartmıyorum.
