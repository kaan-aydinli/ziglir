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

```bash
export PATH=/tmp/zv13/ziglang:$PATH
zig build -Doptimize=ReleaseFast
python3 ai/run_tests.py          # 15/15
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
| 3 katmanlı ağ (2112 kenar × 2000 adım) | 124.7 ms | 7.9 ms | 15.5x |
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

Sohbet, matematik, kod, çeviri, araç kullanımı ve arama — bunlar için gereken
arayüzler `ai/src/` altında var (`math.lir`, `search.lir`) veya protokol
olarak tanımlı (`docs/DESIGN.md` §4).
