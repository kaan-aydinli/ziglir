# `-O2` kod üretim hatası: `learn` + `sqrt` birlikte segfault

## Özet

`ledger.lir` içindeki `learn` ile `fixed.lir` içindeki `sqrt`, aynı programda
ve bir döngü içinde birlikte kullanıldığında, **`-O2` optimizasyon seviyesinde
segfault** oluşuyor. `-O0`, `-O1` ve `-O3` doğru sonuç veriyor.

Bu hata **`sqrt`'in bit-shift sürümüne geçmeden önce de vardı**; orijinal
Newton sürümüyle de aynı şekilde tekrarlanıyor. Yani bu bir regresyon değil,
önceden beri açık olan bir derleyici hatası.

## En küçük tekrar üretim

```lir
import "../src/ledger.lir"

fn main() -> i64 {
    let b = block_new(256, 256, 8, 1)
    let x = @malloc(256 * 8)
    let t = @malloc(256 * 8)
    var i: i64 = 0
    while i < 256 { @write_u64(@ptr_add(x, i*8), ((i * 7) % 13) as u64) i = i + 1 }
    i = 0
    while i < 256 { @write_u64(@ptr_add(t, i*8), ONE as u64) i = i + 1 }
    forward(b, x)
    let eta = from_int(200)
    var s: i64 = 0
    var acc: i64 = 0
    while s < 3000 {
        acc = sat_add(acc, learn(b, x, t, eta))
        s = s + 1
    }
    printInt((acc >> 16) & 1048575)
    return 0
}
```

## Ölçülen davranış

| seviye | sonuç |
|---|---|
| `-O0` | doğru: `768000` |
| `-O1` | doğru: `768000` |
| `-O2` | **segfault** |
| `-O3` | doğru: `768000` |

## Tetikleyicileri daraltma

Denenen ve hatayı **gizleyen** değişiklikler:

* `sqrt` gövdesini eski Newton sürümüne döndürmek — hata sürüyor, yani
  `sqrt`'in algoritmasına özgü değil.
* `learn` döngüsünü kaldırmak (tek çağrı) — gizliyor.
* `x` içeriğini sabit `1` yapmak — gizliyor (veriye bağımlı görünüyor).
* `block_new` boyutlarını küçültmek (8×8, 64×64, 128×128) — gizliyor.
* `b_train.lir` deseni (3 katman, `forward` de döngü içinde) — gizliyor.

## Geçici çözüm

Bu desende `-O2` yerine `-O1` veya `-O3` kullanın. `ai/run_tests.py` içinde
bir test `// opt: -O1` yazarak bu seviyeyi seçebiliyor; `12_learn_batch`
bu yüzden `-O1` ile koşuyor.

## Not

Bu belge bir hata raporudur, çözüm değil. Kaynağı `lir` derleyicisinin
`-O2` optimizasyon geçişinde; bu oturumda derleyici tarafına müdahale
edilmedi.

---

## İkinci hata: `-O2` yanlış sonuç (segfault değil, sessiz yanlış cevap)

`segfault`'tan daha sinsi: program çalışıyor, **yanlış sayı** basıyor.

### Belirti

```
fn gcd(a: i64, b: i64) -> i64 {
    var x = a
    var y = b
    while y != 0 {
        let t = x % y      // <- mod
        x = y
        y = t
    }
    return x
}
```

| | `gcd(24, 18)` |
|---|---|
| `-O0` / `-O1` | **6** (doğru) |
| `-O2` | **18** (yanlış) |

`-O1`'in IR'ı doğru sırayı verir:

```
B2: v10 = mod v14, v15 ; v14 = copy v15 ; v15 = copy v10
```

`-O2`'de `mod` vreg'i yeniden adlandırılıyor ve okuma gövdeden önce yapılıyor.

### Kök neden

`ir_opt.zig` → `isPureHeaderOp()` listesinde `.@"mod"` ve `.umod` vardı. Bu
liste **loop rotasyonunun** (`rotateLoops`) koşul bloğunu klonlarken hangi
op'ları taşıyabileceğini belirler. `mod` gerçek iş yapan bir bölme olduğu
hâlde listede olduğu için döngü gövdesinden koşul bloğuna taşınıyor ve aynı
vreg yeniden tanımlanıyordu.

### Düzeltme

`.@"mod"` / `.umod` listeden çıkarıldı. Regresyon testi:
`ai/tests/13_mod_order.lir` (üç backend'de de koşar).

### Hız etkisi: YOK (ölçüldü, sonra çürütüldü)

İki ayrı ölçümde `05_collatz` 1.36x ve 11 iş yükü toplamı 1.07x çıktı.
Bu **tekrarlanmadı**: aynı iki derleyiciyle 15 dönüşümlü tur atıldığında

| iş yükü | önce | sonra | oran | kazanan |
|---|---:|---:|---:|:--:|
| `05_collatz` (200k başlangıç) | 131.8 ms | 131.9 ms | **1.00x** | 7/15 |
| `05_collatz` (1M, tam) | 529.4 ms | 537.3 ms | **0.99x** | 8/21 |

Yani düzeltme yalnızca doğruluk getiriyor; hız iddiası geçersiz. Önceki
1.36x, makinenin o an sakin olmasından kaynaklanan ölçüm hatasıydı.

### AÇIK KALAN

`while a and b` koşulunu doğrudan hedef bloklara dallandıran ayrı bir
değişiklik (`ir_gen.zig`) bu hatayı **tetikliyor**: tek başına güvenli,
tek başına `mod` düzeltmesi de güvenli, ama ikisi birlikte `gcd`'yi yine
bozuyor. Kök neden bulunamadı; o değişiklik **alınmadı**. `ir_opt.zig`'in
global copy-propagation'ı tanımdan önceki kullanımları yeniden
yazabildiği için blok sırasına duyarlı olduğu düşünülüyor.
