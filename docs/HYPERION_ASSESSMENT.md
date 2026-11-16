# HYPERION / CMF — teknik değerlendirme

**Belgenin statüsü:** Bu, HYPERION mimari tanımının *iddialarının* bağımsız
değerlendirmesidir. Bu repodaki kurala uyar: **hiçbir iddia, kanıtlanmış veya
ölçülmüş olandan fazlasını söyleyemez.** Dolayısıyla aşağıdaki her satır ya
"gerçek/ürün", ya "kısmen gerçek (sınırlı alan)", ya "araştırma prototipi", ya da
"teorem/fizik ile çelişiyor" olarak etiketlenir — ve gerekçesi verilir.

İşaretler: ✅ bugün üründe · 🟡 kısmen gerçek, sınırlı alanda · 🔶 araştırma
prototipi · ❌ matematik/fizik ile çelişiyor · ⚠️ sayısal iddia birkaç büyüklük
mertebesi hatalı

---

## 0. Özet yargı

HYPERION, gerçek ve önemli araştırma yönlerini (bellek-içi hesaplama, veri
akışı yürütme, çok sürümlü kod, erasure-coded hesaplama, CXL havuzlama) tek bir
anlatıda birleştiriyor. **Bileşenlerin çoğu gerçek; ama iki iddia kanıtlanmış
teoremlerle, bir iddia da ışık hızıyla çelişiyor; ve neredeyse tüm sayısal
süreler 1–4 büyüklük mertebesi hatalı.**

| # | İddia | Yargı |
|---|---|---|
| 1 | HQTT (Homotopi + Niceliksel Tip Teorisi) ile tam kaynak muhasebesi | 🔶 HoTT ve QTT ayrı ayrı gerçek araştırma; ikisinin *birleşimiyle üretim tip sistemi* yok. "Tip başına pJ" bugün türetilemez |
| 2 | Sıfır-maliyetli izomorfizm, "Cebirsel Lens" ile 100 GB'ı kopyalamadan yeniden indeksleme | 🟡 **Görünüm (view) O(1)'dir**, ama *o görünüm üzerinden erişim bedava değildir*: strided erişim cache davranışını bozar. "Donanım adres permütasyon matrisi" diye bir yükleme birimi bileşeni yok |
| 3 | Shannon sınırında sıkıştırılmış cache akışı, 100 GB/s → 1.2 TB/s (12×) | 🟡 Donanımda bellek sıkıştırma var (IBM z, GPU HBM); ⚠️ gerçekçi kazanç sıkıştırılabilir veride ~2–4×, rastgele veride 1× (Shannon: sıkıştırılamaz) |
| 4 | PIM / SmartNIC / CXL'e "kanıt-taşıyan kapsül" gönderme | ✅ **En gerçek bileşen.** UPMEM PIM DIMM, Samsung HBM-PIM, SmartNIC/DPU, computational storage bugün satılıyor — ama sadece dar çekirdekler (map/filter/reduce) için |
| 5 | Küresel epoch bariyerlerinin kaldırılması, nedensellik konileri | ✅ **Doğru ve zaten standart**: veri akışı / happens-before / görev paralelliği (TBB, Rayon) küresel bariyer kullanmaz. "Fizik" değil, iyi mühendislik |
| 6 | Gölge zaman çizgileri, 1 çevrimde "dalga fonksiyonu çökmesi" | 🟡 Fikir gerçek (TLS, değer tahmini, iyimser future'lar); ⚠️ "sıfır ceza" yanlış — yanlış tahmin bedava değil; yan kanalsız spekülasyon ise **ek maliyet** getirir |
| 7 | "Sıfır gecikmeli Oblivious RAM", erişim desenini beyaz gürültüye çevirme | ❌ **Teoremle çelişiyor**: her online ORAM Ω(log n) bant genişliği ek yükü ödemek zorundadır |
| 8 | Lattice tabanlı homomorfik veri düzlemleri, cache satırı başına 1 çevrim | 🔶 Kuantum-dirençli ilkeller gerçek ve standart (ML-KEM/ML-DSA); ⚠️ *şifreli veri üzerinde hesaplama* (FHE) 10³–10⁶× yavaş, "1 çevrim" mümkün değil |
| 9 | Holografik erasure-coded hesaplama, 100 düğümden 10'u ölse sıfır rollback | 🟡 Depolamada Reed-Solomon standart; "coded computing" gerçek ama **cebirsel iş yükleriyle sınırlı** (lineer işlemler). Hareketli genel durum için sıfır-kurtarma yok |
| 10 | Önceden kanıtlanmış manifoldlar, 3 çevrimde mikrokod mutasyonu | 🟡 Çok-sürümlü kod + çalışma anında seçim gerçek (CPU dispatch, PGO, ifunc); ⚠️ "veri yapısını 3 çevrimde yeniden şekillendirme" veri taşımayı gerektirir |
| 11 | Tokyo–Frankfurt RAM'i "biraz daha yavaş L4 cache" olarak görmek | ❌ **Fizikle çelişiyor**: tek yön ~60–70 ms. Bir cache miss 10⁸ çevrim sürer; cache-line seviyesinde tutarlılık imkânsız |
| 12 | 5 aşamalı yaşam döngüsü toplam 2.5 ns | ❌ **Tek bir DRAM erişimi ~60–100 ns.** Önerilen bütçe, bir bellek gecikmesinin ~1/40'ı |

---

## 1. Neden bazı iddialar sadece "iyimser" değil, *imkânsız*

### 1.1 ORAM'de sıfır gecikme yoktur (iddia 7)

Goldreich–Ostrovsky (1996) her ORAM için Ω(log n) bant genişliği alt sınırı
verdi; Larsen–Nielsen (CRYPTO 2018) bunu **online** ORAM'lar için, yalnızca
hesaplama güvenliği varsayarak ve verinin keyfî biçimde kodlanmasına izin
vererek kanıtladı. OptORAMa (EUROCRYPT 2020) bu sınıra *ulaşan* ilk şemadır —
yani log n maliyeti aşılamaz, sadece "optimal" hale getirilebilir.

Sonuç: "sıfır gecikmeli ORAM" bir mühendislik eksiği değil, bir teorem ihlalidir.
Dürüst versiyon: *oblivious erişim, log n ek yükle mümkündür ve bu ek yük
donanım hızlandırıcılarıyla sabit katsayıya indirilebilir.*

### 1.2 Işık hızı bir bütçe kısıtıdır (iddia 11)

- Boşlukta ışık: 30 cm/ns. Fiberde (n ≈ 1.47): ~20 cm/ns.
- Tokyo–Frankfurt büyük daire ≈ 9.400 km; fiber güzergâhı tipik olarak 1.3–1.5×
  → tek yön **~60–70 ms**, gözlenen RTT ~120–250 ms.
- 3 GHz'de bu, **~2×10⁸ çevrim** demektir.

Bir L4 cache miss'i ~40 çevrimdir. 2×10⁸ çevrimlik bir "cache katmanı" cache
değildir; coğrafi replikasyon + gevşek tutarlılık modelidir. CXL 3.0'ın bellek
havuzlama/paylaşımı gerçek — ama **aynı raf/oda ölçeğinde** (yüz nanosaniye).
Kıtalararası tek adres uzayı, tutarlılık protokollerinin değil, fiziğin
sınırıdır; bu yüzden gerçek sistemler (Spanner, CRDT'ler) mantıksal saat ve
gevşek tutarlılık kullanır.

### 1.3 Sayısal bütçe tutarsız (iddia 12)

| İşlem | Gerçekçi gecikme (3 GHz) |
|---|---|
| L1 hit | 4–5 çevrim ≈ 1.5 ns |
| L2 hit | ~14 çevrim ≈ 5 ns |
| L3 hit | ~40 çevrim ≈ 13 ns |
| DRAM | **~200–300 çevrim ≈ 60–100 ns** |
| CXL uzak bellek | ~350–600 çevrim |
| PCIe/NVMe erişimi | ~10⁵–10⁶ çevrim (10–100 µs) |

2.5 ns'lik uçtan uca "yaşam döngüsü", tek bir DRAM erişiminden 40× kısa. Ayrıca
0.2 ns < 1 çevrim; "Shannon entropisini ölçüp sıkıştırıp CXL'e yazıp lens
oluşturmak" tek bir çevrimden küçük bir bütçeye sığmaz — entropi ölçümü akışın
tamamını görmeyi gerektirir.

### 1.4 "Sıfır cezalı" spekülasyon mümkün değil (iddia 6)

Spekülasyonun üç ayrı maliyeti var ve hiçbiri sıfır değil:

1. **Yanlış tahmin** → iş boşa gider (enerji + ALU zamanı).
2. **Yan etki disiplini** → yalnızca saf hesaplar speküle edilebilir; yan etkili
   kodu (yazma, IO, serbest bırakma) speküle etmek geri alınamaz.
3. **Yan kanal** → "paylaşılan cache durumunu asla değiştirme" kuralı, tam da
   sabit-zamanlı (constant-time) hesaplama demektir; bu da tipik olarak
   belirgin bir yavaşlama getirir.

Yani Spectre/Meltdown'a bağışık *ve* bedava spekülasyon, aynı anda olamaz.
Gerçek karşılığı: iyimser paralelleştirme (TLS), değer tahmini ve zararsız
(rollback edilebilir) saf gelecekler — hepsi ölçülmüş kazanç/zarar oranıyla
değerlendirilir.

---

## 2. Gerçekten değerli olan kısımlar

Bunlar HYPERION'un değil, *zaten var olan* mühendisliğin parçaları — ve tam da
bu yüzden ilginç:

1. **PIM / DPU / computational storage** (iddia 4). UPMEM PIM DIMM'ler, Samsung
   HBM-PIM (Aquabolt-XL), SK hynix AiM, NVIDIA BlueField, SmartSSD — hepsi
   üründe. Sınır: bu birimlere **her kod gitmez**; ancak dar, veri-paralel
   çekirdekler (map/filter/reduce, lineer cebir) offload edilir. "Kanıt-taşıyan
   kapsül" fikrinin gerçek karşılığı, *sınırlı bir DSL için* derleyicinin
   doğrulanmış çekirdek üretmesidir.
2. **Bariyersiz çalıştırma** (iddia 5). Global epoch yok; happens-before var.
   Rayon/TBB/OpenMP task'ları bunu yıllardır yapıyor. PDTF'ye göre gerçek bir
   mimari fark — ama yeni fizik değil, iyi bilinen veri akışı modeli.
3. **Çok sürümlü kod + çalışma anında seçim** (iddia 10). CPU dispatch
   (`ifunc`), PGO, otomatik vektörleştiricinin seçtiği varyantlar, polymorphic
   inline cache'ler: hepsi "önceden derlenmiş, kanıtlanmış varyantlar arasında
   atlama"dır. 3 çevrimde *kod* seçmek inandırıcı (bir dallanma); 3 çevrimde
   *veri yapısını* değiştirmek değil.
4. **Sıkıştırılmış bellek yolu** (iddia 3). IBM z15/z16 bellek sıkıştırması,
   GPU'larda kayıpsız sıkıştırma gerçek. Sınır: veri sıkıştırılabilir olmalı ve
   sıkıştırma gecikme + alan maliyeti getirir.
5. **Coded computing** (iddia 9). Lee ve ark. (2017) polinom kodlarıyla dağıtık
   lineer cebirde straggler/kayıp toleransı gösterdi; depolamada Reed-Solomon
   standart. Sınır: cebirsel iş yükleri; genel amaçlı "sıfır rollback" yok
   (tek kopyası olan hareketli durum ölürse kurtarma *zaman* alır — PACELC).
6. **Kuantum-dirençli kriptografi** (iddia 8'in gerçek yarısı). NIST FIPS 203
   (ML-KEM), 204 (ML-DSA), 205 (SLH-DSA) 2024'te standardlaştı. Kafes tabanlı
   *anahtar* işlemleri ucuz; kafes tabanlı *hesaplama* (FHE) değil.

---

## 3. "Niyet-güdümlü sentez" iddiası (Bölüm 1.B) ne kadar gerçek?

Bu bölüm, FY'daki en abartılı ve en az kanıtlı kısım — ve hakkında en çok veri
olan kısım.

**Gerçek olan:** DeepMind'ın AlphaDev'i (Nature, 2023) sıralama ağlarını RL ile
*gerçekten* keşfetti ve LLVM libc++'a girdi. Ama ölçek şu:

| Sonuç | Kazanç |
|---|---|
| sort 3 | 18 → 17 komut |
| sort 5 | 46 → 42 komut |
| uzunluk 5 diziler | en fazla ~%70 hız |
| >250.000 eleman | **~%1.7** |
| VarInt çözümleme | ~3× (alan-özel) |

Yani "literatürde adı olmayan hibrit Radix-SIMD-Bitonic ağ algoritması sentezleme"
iddiasının gerçek karşılığı: *dar, ölçülebilir, doğrulanabilir bir alt alanda
birkaç komutluk iyileştirme.* Bu bile büyük bir başarı.

**Gerçek olmayan:** "milyarlarca algoritma uzayını tarayıp genel amaçlı yeni bir
sıralama algoritması sentezlemek". Sıralamanın asimptotik alt sınırı
Ω(n log n)'dir ve bu bir teoremdir; sentez bunu değiştiremez, yalnızca sabit
katsayıyı ve sabit boyutlu ağları iyileştirebilir. Ayrıca arama uzayı üstel
büyür: AlphaDev'in kendisi sort > 8 için "hesaplama açısından yasak" diyor.

**HQTT eleştirisi:** Homotopi Tip Teorisi (univalence) ile Niceliksel Tip
Teorisi (Atkey/McBride; Idris 2'deki lineerlik) ayrı ayrı gerçek ve aktiftir.
Ama:

* Univalence, genel haliyle **karar verilemez** ve kanoniklik/computation'ı
  bozar; cubical tip teorisi bunu kısmen onarır, bedeli ağır.
* Kaynak muhasebesi için gerçek araçlar QTT değil, **AARA** (otomatik amortize
  kaynak analizi) ve Granule gibi lineer/grade'li sistemlerdir.
* "Tip başına pJ" bugün türetilemez: enerji, tipin değil *komut dizisinin ve
  veri hareketinin* fonksiyonudur. Ölçülebilir bir yaklaşım var: derleyicinin
  IR'i üzerinden çevrim/bayt modeli (bu repo tam olarak bunu yapabilir — bkz. §5).

---

## 4. Belgenin kendi içindeki çelişkiler

Bunlar zevk meselesi değil, tasarım tutarsızlıkları:

1. **"Veri hiç hareket etmez" vs "PIM'e kapsül fırlatılır".** Eğer hesaplama
   veriye gidiyorsa, sonuç geri gelmek zorunda; "sıfır hareket" yalnızca
   *ara* hareketler için geçerli. Ayrıca transpoze bir görünüm üzerinden
   hesaplama, donanımda strided erişim üretir: kopyalamayı *erteleyip* cache
   ıskalamasına dönüştürürsünüz.
2. **"Küresel zaman yok" vs "her 100 µs'de telemetri okuyup 3 çevrimde karar
   ver".** Telemetri döngüsü tam da küresel bir senkronizasyondur; PMU okuması
   ucuz değildir ve çekirdekler arası karar için bir noktada anlaşma gerekir.
3. **"Sıfır bayt kopya" vs "Shannon sınırında sıkıştırma".** Sıkıştırılmış
   gösterim, farklı bir *kodlama*dır; ALU'ya girerken açmak zorunludur, bu da
   genişletme (unpack) işidir — yani bir tür hareket.
4. **"Kanıt-taşıyan kapsül" vs "her kodu gönderebilme".** Doğrulanmış çekirdek
   göndermek, çekirdek dilinin toplam olmasını (total, yan etkisiz, sınırlı)
   gerektirir; o zaman genel amaçlı dil iddiası düşer.

---

## 5. LIR açısından: hangisi gerçekten yapılabilir?

Bu reponun ölçütü net: *derlenen, çalışan ve test edilen* şey iddia edilir. Bu
ölçütle HYPERION'un altı fikri aşamalı olarak somutlaştırılabilir. Aşağıdaki
sıralama "etki / gerçekleştirilebilirlik" oranına göredir ve her adımın ölçümü
var.

### 5.1 Çok-sürümlü kod + çalışma anında seçim (en yüksek oran)
LIR zaten IR üretiyor ve `-O0/-O1/-O2` varyantlarını derleyebiliyor. Yapılabilir
olan: *aynı fonksiyonun ölçülmüş olarak farklı veri yoğunluklarında farklı
varyantlarla derlenmesi* ve çalışma anında seçilmesi.

* Ölçüt: bir benchmark'ta (seyrek vs yoğun matris) tek-varyantlı derlemeye göre
  ölçülebilir kazanç; `bench/` içinde tekrarlanabilir.
* Dürüst sınır: veri yapısı *değişmez*; yalnızca kod yolu değişir.

### 5.2 Sıfır-kopya görünümler (view) — doğru tanımla
`[]T` zaten var; eksik olan *yeniden yorumlama* (reinterpret) primitifi ve
hizalama/aliasing kuralları. Gerçek kazanç: transpoze/filtre görünümü O(1)
kurmak; sonrasında erişimin *strided* olduğunu ve cache maliyeti taşıdığını
belgelemek.

* Ölçüt: 1 GB'lık matriste transpoze görünüm kurma < 100 ns; görünüm üzerinden
  toplama, kopyalı sürüme göre ölçülen bir yavaşlama ile raporlanır.
* Bu, "0 bayt kopya" iddiasının *kanıtlanabilir* halidir.

### 5.3 Sadece saf fonksiyonlar için spekülasyon
LIR'de `#[pure]` zaten var ve sema onu denetliyor. Bu, spekülasyonun güvenli
olduğu tek alan: yan etkisiz bir çağrıyı iyimser hesaplayıp sonucu atabilirsiniz.

* Ölçüt: gecikmeli bir bağımlılıkta (`@chan_recv` beklerken) saf çağrıyı önden
  hesaplamanın kazancı; yanlış tahminde kayıp raporlanır.
* Dürüst sınır: yan kanal izolasyonu ek maliyet getirir; bu ölçülmeden
  "sıfır ceza" denemez.

### 5.4 Tipte kaynak bütçesi — HoTT değil, ölçülmüş model
`#[cost(cycles<=N, bytes<=M)]` gibi bir öznitelik; düz çizgili (branch-free)
tam sayı fonksiyonlarda IR üzerinden çevrim modeliyle doğrulanır. LIR'in VM'i
sayesinde modeli *ölçümle* kalibre etmek mümkün.

* Ölçüt: modelin tahmini ile gerçek çevrim sayısı arasındaki sapma (ör. ±%10)
  ve modelin reddettiği/geçirdiği örneklerin test edilmesi.

### 5.5 Bariyersiz görev grafiği
`spawn`/`@chan_*` var; eksik olan *bağımlılık grafiğinden* otomatik zamanlama.
Bir kütüphane düzeyinde DAG zamanlayıcı gerçekçi ve küresel bariyer gerektirmez.

### 5.6 Offload çekirdekleri (PIM/DPU) — araştırma, ama en gerçekçi uzun vade
Dar bir "çekirdek DSL'i" (map/filter/reduce) tanımlayıp, hedefe (CPU / SIMD /
PIM) derleyen bir arka uç. Bugün yapılabilecek kısmı: aynı çekirdeğin CPU ve
SIMD varyantlarını üretip ölçmek.

### 5.7 Yapılmaması gerekenler
* ORAM'i "sıfır gecikme" olarak sunmak (teorem ihlali).
* Kıtalararası tek adres uzayı vaadi (fizik ihlali).
* "Her tip şu kadar pJ" (ölçülemez; yalnızca dizi/komut düzeyinde modellenir).
* Genel amaçlı "algoritmayı sistem icat eder" (Ω(n log n) ve arama uzayı).

---

## 6. Sonuç

HYPERION'un **değerli çekirdeği** şu üç cümleye indirgenebilir ve üçü de
savunulabilir:

1. **Hesaplamayı veriye gönder** (PIM/DPU/computational storage) — gerçek,
   üründe, dar çekirdeklerle sınırlı.
2. **Küresel bariyer yerine bağımlılık tabanlı zamanlama** — gerçek, standart,
   doğru yön.
3. **Tek bir ikili yerine, önceden doğrulanmış varyantlar arasında çalışma
   anında seçim** — gerçek, ölçülebilir, bugün yapılabilir.

Geri kalanı (sıfır gecikmeli ORAM, kıtalararası tek adres uzayı, 2.5 ns'lik
uçtan uca döngü, sıfır cezalı yan-kanalsız spekülasyon, tip başına pJ muhasebesi,
genel amaçlı algoritma sentezi) ya kanıtlanmış teoremlerle ya ışık hızıyla ya da
termodinamikle çelişiyor.

Bu, fikirlerin değersiz olduğu anlamına gelmez: **her iddianın ölçülebilir bir
versiyonu var** ve doğru sıra, en ucuz ölçümden başlamaktır. Bu reponun kuralı
tam olarak bunu söylüyor: *önce ölç, sonra iddia et.*

---

### Kaynaklar

* Larsen & Nielsen, "Yes, There is an Oblivious RAM Lower Bound!", CRYPTO 2018 —
  https://eprint.iacr.org/2018/423
* Asharov ve ark., "OptORAMa: Optimal Oblivious RAM", EUROCRYPT 2020 —
  https://eprint.iacr.org/2018/892
* Mankowitz ve ark., "Faster sorting algorithms discovered using deep
  reinforcement learning", Nature 2023 —
  https://www.nature.com/articles/s41586-023-06004-9
* Lee ve ark., "Speeding Up Distributed Machine Learning Using Codes", 2017
  (coded computing)
* NIST FIPS 203/204/205 (ML-KEM, ML-DSA, SLH-DSA), 2024
* CXL 3.0/3.1 spec (bellek havuzlama ve paylaşım)

---

## 7. Bu değerlendirme artık yürütülebilir

Bu belgedeki ayrımlar (`✅ üründe` / `🟡 kısmen` / `🔶 prototip` / `❌ çelişiyor`)
`lir cmf` tarafından **denetlenen** alan yüzeyine dönüştürüldü:

```
lir cmf examples/cmf/hyperion.cmf
```

| Değerlendirme | CMF'de karşılığı |
|---|---|
| ✅ gerçek olan (lens, çok-varyant, seçim) | `lens`, `bloom` (her witness gerçekten derlenir), `telemetry` + `tune` |
| 🟡 sınırlı (PIM/DPU, kodlanmış hesaplama) | `machine pim: pim planned` — ilan edilir, iddia edilemez |
| 🔶 prototip (FHE veri düzlemi, HQTT maliyeti) | `machine fhe: fhe planned`; pJ iddiası yok, **ölçülen** komut sayısı var |
| ❌ çelişen (ORAM, fotonik küresel adres uzayı, 2.5 ns) | temsil edilmez; bir iddia bunlara dayanırsa derleme **reddedilir** (`LIR-E8010`) |

Ölçüm kuralı: her doğrulanmış varyant IR VM'de çalıştırılır ve raporlanan tek
maliyet **gerçekten yürütülen komut sayısıdır**. "3 çevrim", "2.5 ns",
"pJ/tip" gibi hiçbir sayı bu repoda üretilmez — çünkü ölçülmemiştir.

Ayrıntı: `docs/CMF_PARADIGM.md` §1.6.
