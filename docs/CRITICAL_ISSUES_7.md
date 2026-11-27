# LIR / ZigLIR — Hızlandırma Çalışmasında Ortaya Çıkan 2 Kritik Sorun (#7, #8)

**Tarih:** 2026-11-27
**Branch:** `arena/ca2f152c-ziglir`
**İlgili commit'ler:** `1146c36` (#8 çözümü + regresyon testi), `45b9f95` (#7'yi
ortaya çıkaran pass serisi; erken `simplifyCFG` çağrısı bilinçli olarak eklenmedi)

**Bağlam:** `-O2` optimizer'a üç yeni pass eklenirken (kısa-devre bool diamond'ını
thread'leme, `2^k`'ya bölme/kalan korelasyonu) bulunan iki ayrı **sessiz
miscompile**. Numaralandırma `docs/CRITICAL_ISSUES_6.md`'yi takip eder; oradaki
#5 ve #6 hâlâ açık.

Her iki sorun da optimizasyon pass'lerinin *kendi* hatası değildi: ikisi de
boru hattının başka bir yerinde uzun süredir duran, ancak belirli bir CFG
şekli üretildiğinde tetiklenen hatalardı. Bu, #6'da (genel dominance verifier
yokluğu) belirtilen kök nedeni somut olarak doğruluyor — IR seviyesinde bir
bekçi olmadığı için bu sınıf hatalar yalnızca uçtan uca fark testleriyle
yakalanabiliyor.

---

## Özet tablo

| # | Sorun | Kategori | Şiddet | Durum | Konum |
|---|-------|----------|--------|-------|-------|
| 7 | `-O2` döngüsünde erken konuma eklenen tek bir `simplifyCFG` çağrısı iki fark testini sessizce bozuyor — üç backend'de de (native, VM, C) | Doğruluk / optimizer | **Kritik** | **AÇIK** (çağrı eklenmedi — `45b9f95`, kök neden bulunmadı) | `ir_opt.zig` `optimizeFn` -O2 döngüsü, `simplifyCFG` |
| 8 | Native codegen'de frame-shrink durumu fonksiyonlar arasında sıfırlanmıyor: shrink yapamayan bir fonksiyon, bir önceki fonksiyonun erken-dönüş sabitini ve blok indeksini miras alıyor | Doğruluk / native codegen | **Kritik** | **ÇÖZÜLDÜ** (`1146c36`) | `ir_codegen.zig:2586-2620, 3522-3552, 4528-4550` |

---

## 7. Erken konumda `simplifyCFG`: tek satırlık ekleme iki fark testini bozuyor — AÇIK

**Ne oluyor:**

`-O2` döngüsünde `simplifyCFG` zaten bir kez çalışıyor
(`globalCopyPropagate`'den sonra). Yeni pass'lerin erişilmez bıraktığı
blokları daha erken toplamak amacıyla aynı döngüde, `simplifyTrivialPhis`'den
hemen sonra **ikinci bir** `simplifyCFG` çağrısı eklendiğinde iki test sessizce
bozuldu:

```
$ lir run ai/tests/30_noema_training_data.lir -O2 --backend=native | head -1
7          # beklenen 9
$ lir run ai/tests/37_noema_multimodal.lir -O2 --backend=native | head -1
13         # beklenen 17
```

**Kanıt zinciri (hepsi gerçek koşumlardan):**

1. `-O0` ve `-O1` aynı kaynaklarda doğru (`9`, `17`) → sorun `-O2`'ye özgü.
2. Üç yeni pass'in **hepsi** geçici env anahtarlarıyla kapatıldığında da sonuç
   bozuk kaldı (`7`, `13`) → suçlu pass'ler değil.
3. `ifConversion` bütçesi eski değerine (`inst_count > 3`) indirildiğinde de
   bozuk kaldı → suçlu bütçe genişlemesi değil.
4. Dört ek satırın tamamı kaldırıldığında iki test de düzeldi (`9`, `17`).
5. Dört satırdan **yalnızca** `if (simplifyCFG(f)) changed = true;` geri
   konduğunda (üç pass olmadan) bozulma geri geldi (`7`, `13`).

**Kapsam:** `--backend=native`, `--backend=vm` ve `--backend=c` üçünde de aynı
yanlış sonuç. Yani hata makine kodu üretiminde değil, **IR dönüşümünde**:
`simplifyCFG` bu konumda IR'i semantik olarak bozuyor. Backend'den bağımsız
olması bunu kesinleştiriyor.

**Neden kritik:** Çıktı yanlış ama program çökmüyor, exit code 0. Bu sınıf
hata ancak fark testiyle yakalanır; kullanıcı tarafında hiçbir belirti yok.

**Şu anki durum / karar:** Erken çağrı **eklenmedi** (`45b9f95`). Yeni pass'lerin erişilmez
bıraktığı bloklar, aynı iterasyonda daha sonra çalışan mevcut `simplifyCFG`
tarafından toplanıyor; ölçülen fark ihmal edilebilir
(geomean LIR/LLVM-C 1.267, erken çağrı varken 1.250 — kollatz iç döngüsünün
IR'i her iki durumda da 4 blok ve branchless).

**Çözüm için gereken:** `simplifyCFG`'nin bu konumda hangi dönüşümü yanlış
yaptığını bulmak. En olası aday, `mem2reg` sonrası fakat
`localConstantFoldAndLVN`/`globalValueNumbering` öncesi durumdaki phi
birleştirme veya erişilmezlik analizi; `ai/tests/37_noema_multimodal.lir`
üzerinden fonksiyon bazında daraltma yapılabilir. Bu, #6'daki genel dominance
verifier'ının neden gerekli olduğunun somut örneği: verifier olsaydı bozuk IR
backend'e ulaşmadan yakalanırdı.

---

## 8. Frame-shrink durumu fonksiyonlar arasında sızıyor — ÇÖZÜLDÜ

**Ne oluyor:**

Native backend, giriş bloğu ucuz bir guard olan fonksiyonlarda callee
frame'ini erteleyebiliyor: `B0` prologue olmadan emit ediliyor, sabit erken
dönüş inline ediliyor, frame ancak devam bloğunda kuruluyor. Bu karar
`cur_shrink_shared`, `cur_shrink_cont_bi`, `cur_shrink_ret_imm`,
`cur_shrink_ret_vreg`, `cur_shrink_ret_is_imm` alanlarında tutuluyor.

Alanlar **yalnızca shrink'in uygulandığı yolda** yazılıyordu. Onları tüketen
iki emit noktası ise (`compileFusedCmpBranch` ve `.cond_jump` kolu) sadece
`self.cur_shrink_shared and cur_bi == 0` koşuluna bakıyor; içinde bulunulan
fonksiyonun shrink'e uygun olup olmadığını **göremiyor**. Sonuç: shrink
yapamayan her fonksiyon, bir önceki fonksiyonun durumunu miras alıyordu. Giriş
bloğu `cond_jump` ile biten böyle bir fonksiyon, kendi gövdesinin başına
**başka bir fonksiyonun** erken dönüşünü emit ediyordu:

```
jne/jge <önceki fonksiyonun devam blok indeksi>
mov   rax, <önceki fonksiyonun erken-dönüş sabiti>
ret
```

Bayat blok indeksi hangi bloğa denk gelirse, akış aşağıdaki fonksiyonlar ya
sessizce yanlış değer döndürdü ya da segfault etti.

**Tetikleme koşulu (optimizer yardımı gerekmiyor):**

1. Shrink'e uygun, **paylaşılan** erken-dönüş bloğu olan bir fonksiyon —
   yani sabit döndüren bloğa giden kenar sayısı ≥ 2 (`shrink_ret_shared=true`).
2. Hemen ardından, shrink'e uygun olmayan (gerçek frame isteyen) ve giriş
   bloğu `cond_jump` ile biten bir fonksiyon.

`if a == 0 or b <= 0 { return K }` şeklindeki kısa-devre guard, koşul
diamond'ı thread'lendiğinde tam olarak (1)'i üretir: birleşen blok ikinci
kenarı da alır ve özel (`shared=false`) biçimden paylaşılan biçime geçer. Bu
yüzden hata, yeni pass'lerle birlikte ilk kez görünür oldu — ama pass'ler
olmadan da elle yazılabilir.

**Minimal repro (17 satır):** `src/bootstrap/tests.zig` içinde
`"codegen: frame-shrink state must not leak from one function into the next"`
testine gömülü. `shrinker_shared` tetikleyici, `hex_encode` kurban: inline
edilemeyecek kadar büyük olduğu için gerçekten çağrılıyor ve sızıntı doğrudan
stdout'a yansıyor.

```
düzeltmeden önce:  -3750763034362895579   sonra exit 139 (SIGSEGV)
düzeltmeden sonra: -3750763034362895579 / 4c4952 / 6     (IR VM ile birebir aynı)
```

**Teşhis yöntemi:** `cur_shrink_*` alanlarını okuyan emit noktalarına geçici
izleme eklenerek, `shrinker_shared`'dan sonra derlenen *her* fonksiyonun
`imm=-3750763034362895579 cont_bi=1` değerlerini miras aldığı doğrudan
gözlendi (`zero_param_cond_entry`, `hex_encode`, `hex_nibble`, `hex_decode`,
`base64_encode`, `b64_char_val`, `base64_decode`, `int_to_hex`, ...).
`can_shrink=false` olmasına rağmen `shared=true` görünmesi sızıntının kanıtı.

**Çözüm (`1146c36`):** `compileFn` içinde, `can_shrink` hesaplandıktan hemen
sonra beş alanı **koşulsuz** sıfırla. Shrink'e uygun fonksiyonlarda alanlar hemen
ardından kendi kontrolleri geçince yeniden dolduruluyor, bu yüzden kazanç
korunuyor; uygun olmayanlarda ise artık temiz bir durum görülüyor.

**Doğrulama:** `zig build test` (140 test, yeni regresyon testi dahil) ve
`ai/run_tests.py` **220/220**, üç backend'de. Ayrıca `11/11` bench çıktısı
`expected.txt` ile birebir.

---

## Çıkarılan iki genel kural

1. **Backend'de fonksiyonlar arası taşınan her alan, fonksiyon başına
   koşulsuz sıfırlanmalı.** "Yalnızca geçerli yolda yaz" deseni, o alanı
   okuyan kod geçerliliği göremiyorsa sessiz sızıntı üretir.
2. **Pass sırası bir güvenlik özelliğidir.** Aynı pass'in döngü içindeki
   konumunu değiştirmek, pass'i değiştirmek kadar riskli; #7 bunun ölçülmüş
   örneği.
