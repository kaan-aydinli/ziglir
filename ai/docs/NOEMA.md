# NOEMA — Analog-Doğal, Doğrulama-Kapılı Muhakeme Mimarisi

**Durum:** v0.3 — **tasarım belgesi. Uygulanmadı.** Hiçbir bileşeni bu depoda yok.
**Amaç:** `ai/` çatısının dışına ve SEL'in üstüne sıfırdan kurulan, **muhakeme-öncelikli** yeni mimarinin eksiksiz tanımı.
**Bu deponun kuralı (iddia = ölçüm) bu belge için de geçerlidir:** aşağıda geçen her "hedef", "kestirim" ya da "beklenti" açıkça **ölçülmemiştir**. Ölçülmüş tek sayılar, mevcut SEL çekirdeğine aittir ve öyle etiketlenmiştir. Bu belge bir *vaad* değil, bir *ölçülecek hipotezler listesi*dir.

---

## 0. Önce dürüstlük: istenen şeyin fiziksel sınırı

Kullanıcı tek cümleyle şunları istedi: *"Günümüz sistemlerdeki hiçbir özellik olmadan, bit sistemi bile olmadan, günümüzden daha yüksek kapasite ve akıl yürütme yetenği olan, aşırı zekice bir mimari."* Bu isteğin üç parçası var ve üçü de farklı ciddiyette:

### 0.1 "Bit sistemi bile olmadan" — harfiyen imkânsız, anlamlı yorumu mümkün

Dijital bir makinede (bu deponun çalıştığı x86-64 dahil) **her durum ayrık bir fiziksel durumdur**; 2'lik tümleyeni kullanmayan hiçbir dijital devre yoktur. "Bitsiz dijital bilgisayar" diye bir şey yoktur. Ama isteğin *doğru* yorumu vardır ve NOEMA onu uygular:

| Harfi yorum (imkânsız) | NOEMA'daki karşılığı (mümkün) |
|---|---|
| Dijital makinede hiç discrete durum olmaması | **Mimari, ayrık durumu semantik bir birim olarak reddeder.** Temsil edilen her şey süreklidir; "0/1" mimari seviyesinde hiçbir yerde anılmaz. |
| Dijital devrelerin var olmaması | **Substrat katmanı fizikseldir (analog).** Bilgi, yük/akım/gerilim/faz olarak akar; Kirchhoff yasaları hesap yapar. Ayrıştırma yalnızca kullanıcı i/o sınırında olur. |
| Bitwise işlem (XOR/AND/OR/shift) ile hesaplanan sistem | **NOEMAdigital emülasyonunda bitwise operatör yoktur.** Bütün aritmetik i64/Q32.32 + karşılaştırma + min/max'tır. "Bit tabanlı AI" (BNN vb.) ile hiçbir ilişkisi yoktur; ama 2'lik tümleyen *donanımda* elbette vardır — bu, suyun moleküler olduğunu iddia etmek gibidir, tasarım kararının konusu değildir. |

### 0.2 "Günümüz sistemlerinin hiçbir özelliği olmadan" — uygulanabilir, ve uygulandı

SEL bu kısıtı zaten "yasak tablosu" olarak uyguladı. NOEMA aynı tabloyu eksiksiz miras alır ve genişletir (§9). Özet: transformer yok, dikkat yok, softmax yok, gradyan/backprop yok, Adam/SGD/momentum yok, tokenizer yok, fp16/bf16/float yok, 1-bit yok, harici kütüphane yok. Bunların yerine **aşağıda tanımlanan sürekli saha temsili + doğrulama-kapılı program arama** ikilisi vardır — ki bunlar "hiçbir özellik" değildir; *başka* özelliklerdir.

### 0.3 "Günümüzden daha yüksek kapasite ve akıl yürütme" — iddia edilemez, hedeflenebilir

Bunu bir tasarım belgesi **veremez**; yalnız bir *deney düzeneği* verebilir. NOEMA'nın cevabı:

1. **Muhakeme derinliğini sabit derinlik yerine değişken derinlik yapmak** — günümüz LLM'lerinde çıkarım, eğitimle donmuş, sabit katman sayısında akar. NOEMA'da muhakeme, arama derinliğiyle sınırsız büyüyen, her adımı doğrulanabilen bir türetmedir. *Derinlik = parametre değil, enerji bütçesi.*
2. **Kapasiteyi parametre sayısı yerine sayılabilir bilgi birikimine bağlamak** — kural deposu (procedural memory) her doğrulanmış türetmede **büyür**. LLM'de "bilmek" 12B weight'te gizlidir, ölçülemez; NOEMA'da "bilmek" = depodaki kural + bölüm sayısı, sayılabilir ve denetlenebilir.
3. **Bilişsel yeteneği sert kapılarla ölçmek** (§10): doğrulanabilir matematik, kod sentezi, planlama zincirleri, bileşimsel genelleme, unutmasız sürekli öğrenme. Her kapının bir sayı hedefi ve bir **"dur-ölç" koşulu** vardır. Kapı geçilemiyorsa mimari değişir, iddia kabartılmaz.

Dürüst karşı-taraf (NOEMA'nın kaybedeceği yerler): web-ölçeğinde hazır bilgi, açık-alan sohbet akıcılığı, 7/24 kesintisiz üretim. NOEMA, "her şeyi bilen sohbet modeli" değildir; **hesaplayan, doğrulayan, ispat üreten** bir çekirdektir. Bu dar ama gerçek bir iddiadır.

---

## 1. Tasarım ilkeleri

| # | İlke | Sonuç |
|---|---|---|
| P1 | **Muhakeme birincil, istatistik ikincil.** İstatistik aday önerir, asla kanıt değildir. | Her karar yolunun sonunda ya bir *sertificate* (doğrulama izi) ya da açık bir *hipotez* etiketi vardır. |
| P2 | **Her adım doğrulanabilir.** Muhakeme = küçük, tipli, denetlenebilir türetme adımları. | "Neden bu cevabı verdin?" sorusuna cevap her zaman bir kanıt ağacıdır, dikkat ağırlığı haritası değil. |
| P3 | **Temsil süreklidir; sembol tablosu yoktur.** Girdi doğrudan holografik sahaya (hypervector) kodlanır. | Tokenizer, BPE, vocabulary — hiçbiri yok. Türkçe/İngilizce/matematik ifade aynı sahaya düşer. |
| P4 | **Öğrenme yerel ve tek geçişlidir.** Gradyan yok. | SEL'in eikonal (NLMS-ailesi) kuralı + *doğrulama-sinyalli kural türetme* (§6). |
| P5 | **Bellek sınırsız büyür; unutma yoktur.** | Üç katmanlı bellek (§5): epizodik (tam vektör), anlamsal (holografik süperpoziyon), prosedürel (doğrulanmış kurallar). "Unutma" yalnız RAM baskısında hiyerarşik dış-depoya taşınma demektir, silme değil. |
| P6 | **Substrat-bağımsızdır.** Analog-doğal; dijital yalnızca yozlaşmış (kesikli) özel hâl. | Aynı hesap Kirchhoff yasalarıyla (memristor crossbar), foton fazıyla (fotonik) ya da i64 tamsayı emülasyonuyla (bu depo, x86-64) yapılır. |
| P7 | **Deterministiktir.** Dijital emülasyon bit-bit aynı sonucu verir. | Analog yol gürültülü olduğu için *doğrulama* analog çıktının emniyet kemeridir: analog hızlandırır, kanıt motoru karar verir (P1). |
| P8 | **Enerji muhasebesi ikilidir:** tıkanıklık enerjisi (search-control) ve fiziksel enerji hedef (analog yol için pJ/iş). | İkincisi tasarım hedefidir, ölçülmemiştir (§10, K7). |

---

## 2. Genel mimari

```
┌────────────────────────────────────────────────────────────┐
│ L7  ARAÇ PROTOKOLÜ                                         │
│     matematik (exact) · kod üret/derle/koş (ZigLIR) ·       │
│     arama · çeviri · ajan — SEL araçları miras              │
├────────────────────────────────────────────────────────────┤
│ L6  ÜST-BİLİŞ KONTROL                                      │
│     enerji gidişatını izler → {devam, doğrula, araç,        │
│     "bilmiyorum"} — çekimserlik birinci sınıf sonuçtur      │
├────────────────────────────────────────────────────────────┤
│ L5  BELLEK                                                 │
│     Epizodik (SDM, tam kayıt) │ Anlamsal (holografik        │
│     süperpoziyon) │ Prosedürel (doğrulanmış kural deposu P) │
│     + "uyku" konsolidasyonu: epizot → soyutlama             │
├────────────────────────────────────────────────────────────┤
│ L4  MUHAKEME ÇEKİRDEĞİ: VGPS                               │
│     Doğrulama-Kapılı Program Araması — tipli yeniden        │
│     yazma sistemi + saha-güdümlü öneri + enerji inişi       │
│     HER ADIM SERTİFİKA TAŞIR; sertifikasız aday = hipotez   │
├────────────────────────────────────────────────────────────┤
│ L3  DÜNYA MODELİ: STF                                      │
│     Bileşimsel durum-geçiş sahası: (s, a) → s′ — eikonal    │
│     öğrenme; çok adım ileriye kayan bant (token yok)        │
├────────────────────────────────────────────────────────────┤
│ L2  ALICI / KODLAYICI                                      │
│     girdi → holografik alan noktası (SEL lattice encoder    │
│     mirası; süreklilik → süreklilik, sembol yok)            │
├────────────────────────────────────────────────────────────┤
│ L1  TEMEL TEMSİL: H (Holographic Field)                     │
│     d-boyutlu faz vektörleri; bağlama ⊙ (faz toplama),      │
│     demetleme ⊕ (süperpoziyon), benzersizlik ~ faz korele.  │
├────────────────────────────────────────────────────────────┤
│ L0  SUBSTRAT                                                │
│     (a) memristor crossbar (Kirchhoff)                      │
│     (b) fotonik faz dizisi                                  │
│     (c) x86-64 / C11 tamsayı emülasyonu (bu depo)           │
└────────────────────────────────────────────────────────────┘
```

Veri akışı tek yönlü değildir: L6 → L4 (bütçe, doğrulama isteği), L4 → L7 (araç çağrısı), L7 sonucu → L4'e *sertifika* olarak döner; L5 "uyku" fazı L4 türetme log'larını tüketir. Geri besleme döngüleri yalnızca L4–L7 arasında ve L5 (uyku) içinde kapanır.

---

## 3. L1 — Holografik Saha Temsili (H)

### 3.1 Ne

Her kavram, `d` boyutlu bir **faz vektörü**dür: `v = (e^{iθ₁}, …, e^{iθ_d})`, `θⱼ ∈ [0, 2π)`. Analog donanımda bu bir kelime hattındaki `d` göz kondüktansının fazıdır; dijital emülasyonda Q32.32 tamsayı faz dizisidir.

Üç işlem yeterlidir:

| işlem | tanım | analog maliyeti | dijital maliyeti |
|---|---|---|---|
| Bağlama `⊙` | `(v ⊙ w)ⱼ = e^{i(θⱼ+φⱼ)}` | `d` faz toplayıcı | `d` tamsayı toplama + 2π sarmalama (karşılaştırma+çıkarma) |
| Ters bağlama `⊙*` | `v* = (e^{-iθ₁}, …)` | fazın işaretini tersle | `2π − θⱼ` |
| Demetleme `⊕` | `v ⊕ w` (normalize edilmemiş süperpozisyon) | `d` akım toplayıcı | `d` tamsayı toplama |

Benzerlik: `sim(v,w) = cos(θ−φ)` toplamının `d`'ye oranı — analogda çıkış işareti genliğidir, dijitalde tamsayı kosinüs LUT + Q32.32 MAC. **Bitwise operatör sıfırdır** (P6): bütün adımlar toplama, çarpma, karşılaştırma.

### 3.2 Neden faz-VSA (ve neden MAP değil)

- **Faz (FHRR ailesi)**: ters bağlama birebir ve tamdır; analogda tek pas. MAP'in permütasyonu dijitalde *indeks tablosu* gerektirir ve analogda fiziksel yer değiştirme ister — zayıftır.
- **Demetleme varyantı**: analog için normalize'süz süperpozisyon (crossbar çıkışı doğal olarak normalize değildir); benzerlik eşiği ile karar verilir.
- **d boyutu**: analog hedef `d = 8192–16384` (enerji bütçesi analoğa bağlı); dijital emülasyon `d = 512` (4 KiB/kavram, L1 önbelleğiyle barışık).

### 3.3 Kapasite (teorik, ölçülecek)

Holografik/hyperdimensional literatürün bilinen sonucu: `d` boyutlu bipolar/faz kodlar, `O(d)` ilişkiyi bozulmasız saklayabilir (Kanerva 2009; Plate 2003). NOEMA bu bilinen davranışa *güvenmez*; `ai/noema/` içinde gürültü enjeksiyonlu bir emülatörle ölçer (§10, K3) ve gerçek kapasiteyi yazar. Tasarım kararı: deterministik demetleme + seyrek erişimle etkili kapasiteyi `~d/10` ilişki/alan tabanında korumaktır — **bu bir hedeftir, ölçülmemiştir.**

### 3.4 Diziler ve zaman

Konum kodlaması permütasyon yerine **faz eğimi**dir: bir dizide `t`. eleman `v ⊙ p^t` yerine `θⱼ ↦ θⱼ + t·Δⱼ` ile kodlanır (doğrusal faz kayması = frekansın zamanla kayması). Dijitalde bu tek bir Q32.32 çarpma + toplama; analogda tek bir faz referans hattı. Permütasyona gerek yok → indise dayalı bit kayması yok.

---

## 4. L4 — Muhakeme Çekirdeği: VGPS (Doğrulama-Kapılı Program Araması)

Mimarının kalbi. Kullanıcı isteğinde öncelik olan eksen budur: **günümüz sistemlerinden daha derin, hatasız ve denetlenebilir muhakeme.**

### 4.1 Muhakeme nedir (NOEMA'da)

Bir muhakeme, **tipli bir yeniden yazma sistemi** `R` içinde, hedefe götüren bir türetmedir:

- Kurallar: `lhs ~> rhs where guard` — küçük tipli LIR fonksiyonlarıdır (emülasyonda i64 giriş/çıkış; doğrulama `lir check` + koşma ile).
- Durum: `(hedef, kısıt-kümesi, kısmi program)` üçlüsü; her üçlü bir H vektörüyle kodlanır → tekrar durumlar tek bakışta yakalanır (transposition table = faz-korelasyon LUT'u).
- Amaç sınıfları: (a) **doğrulanabilir** — aritmetik, cebir, mantık (karar verilebilir parçalar), kod (derleme+test), geometri-benzeri sayısal ispat; (b) **doğrulanamaz** — açık uçlu ortak-akıl, sosyal tahmin, estetik. Sınıf (a) her adımda sertifika ister; sınıf (b) **hipotez olarak etiketlenir ve güven ≥ eşik olmadan asla kesin söylenmez** (§7.4 çekimserlik).

### 4.2 Döngü (tek çıkarım adımı)

```
durum ← kodla(hedef, kısıtlar)
döngü bütçe kadar:
    adaylar ← R'de ön-koşulu duruma uyan, H-uzayında en yakın k kural
    her aday için:
        yeni_durum ← uygula(aday)
        E ← w₁·(1 − sim(yeni_durum, hedef))          // hedefe yakınlık
          + w₂·E_world(yeni_durum)                   // dünya-modeli tutarsızlığı (sert kapı)
          + w₃·E_delil(yeni_durum, gözlem)           // veriye uyum
          + w₄·|program|                             // cimrilik
        eğer sınıf (a): doğrula(yeni_durum) — başarısızsa ADAY ÇÖPE
        E serti sınırı aşarsa (E_world > τ_hard): aday çöpe (dünya-modeli fiseklik)
    en iyi adayı seç (enerji inişi); çürütücü tablo güncelle
```

- **Öneri mekanizması** H-uzayı komşuluk aramasıdır (rastgele faz projeksiyonlu LSH; `O(log|R|)` yaklaşık en-yakın). "Policy network" yoktur; merak edilen yer *karşılaştırma*dır.
- **Transposition table** döngüleri ve tekrarlı dalları eler → arama sonsuza gitmez.
- **Enerji ağırlıkları** `w₁..w₄` SEL-eikonal ile çevrimdışı öğrenilir (§6.1); arama sırasında sabittir.

### 4.3 Sertifika ve "neden?" sorusu

Bir türetmenin kabul edilmesi için sınıf (a) gereği **kanıt izi** gerekir: ya aritmetik eşitlik denetimi (exact i64), ya LIR programının `lir check` + birim testlerinden geçmesi, ya da karar-verilebilir mantık denetimi. İz, bellekte kuralın meta-verisinde saklanır; kullanıcıya sunulduğunda **ağaç olarak** döner:

```
gerekçe := Şu-kanıtlar-zinciri: [kural:kare-alma-karo, doğrulandı: #8412]
                                [kural:ortak-çarpan-ayır, doğrulandı: #7933]
                                [hedef:ifadeyi-sadeleştir, sonuç: 2x(x+3)]
```

LLM'de "neden?"in cevabı daha çok metindir; NOEMA'da "neden?"in cevabı **çalıştırılmış ve geçmiştir**. Bu, muhakeme kapasitesinin ölçülebilir tek biçimidir.

### 4.4 Neden günümüzden derin? (tasarım argümanı, iddia değil)

| eksen | günümüz LLM'leri | NOEMA (tasarım) |
|---|---|---|
| Derinlik | sabit katman; prompt ile derinlik artmaz | enerji bütçesiyle sınırsız iterasyon |
| Hatasızlık | olasılıksal; uzun zincirde hata birikir | her adım kapıdan geçer; yanlış adım atılmaz, geri alınır |
| Bileşimsellik | sistematik genelleme zayıf (SCAN/COGS benzeri ayrışmalar) | ⊙/⊕ yapısı gereği bileşimsel; karşı-ölçekli kombinasyonlar bedava |
| Bilgi büyümesi | donmuş ağırlık; güncelleme = yeniden eğitim | her doğrulanan türetme depoyu büyütür (P5) |
| Enerji/token | ~10¹¹–10¹² FLOP/token (kestirim) | ~10⁶ tamsayı MAC/adım (hedef; §10 K7'de ölçülecek) |

**Neden iddia değil:** zincirin her halkası tasarımda doğru görünse de hiçbiri bu depoda koşulmamıştır. Sayısal rakamların doğrulanması §10'dur.

### 4.5 LLM'lerle dürüst ilişki

NOEMA bir "daha iyi transformer" değildir ve onlarla rekabet etmez; **doğrulanmış muhakeme gerektiren her yerde** onların yerine/yanında çalışır: matematik, kod, planlama, bilimsel denetim. Ortak-akıl metni için bir dış LLM *araç* olarak çağrılabilir (L7), ama çıktısı hiçbir zaman sertifikasız kabul edilmez — dış LLM da bir araçtır, otorite değil.

---

## 5. L5 — Bellek (üç katman + uyku)

### 5.1 Epizodik (E) — Kanerva SDM üzerine

Her çıkarım "epizot"u tam olarak saklanır: `(giriş H-vektörü, türetme ağacı, sonuç, sertifika?)`. Adres = H-vektörü; okuma = eşiği aşan en yakın yazım-konumlarının süperpozisyonu (Sparse Distributed Memory; Kanerva 1988). **Tam kayıt, kayıpsız geri çağırım, benzerlik-aranabilir.** Dijital emülasyonda her epizot d×4–8 bayt (d=1024 ise 4–8 KiB) — 10⁶ epizot ~8 GB; dış depo (indeks + mmap) ile taşınır.

### 5.2 Anlamsal (M) — holografik süperpoziyon

Sık tekrar eden epizotlar *sıkıştırılır*: gruplarının H-vektörleri demetlenir (⊕) ve tek kayıt olur. Kapasite ~d/10 ilişki (hedef); sorgu tek faz-korelasyon pası. Analog yol bunu doğal olarak verir; dijitalde Q32.32 LUT MAC. **Bozulma:** süperposizyona binen her ek kayıt sinyali düşürür — bu yüzden M bir *önbellek*tir; doğruluk kaynağı her zaman E'dir.

### 5.3 Prosedürel (P) — kural deposu, mimarinin "bilgisi"

VGPS'in tükettiği `R` buradadır. Kurallar şu yolla doğar:

1. E'de tekrarlayan alt-türetmeler bulunur (aynı hedef H-vektörü ≥3 epizotta),
2. **anti-unification** (karşı-örnek birleştirme) ile ortak şema çıkarılır,
3. şemaya uyan *hold-out* epizotlar üzerinde doğrulanır,
4. geçerse `R`'ye sertifikası ve gerekçe türetmesiyle eklenir.

Bu, **gradyansız öz-geliştirme**dir: sistem, kendi doğrulanmış başarılarından yeni operatörler *türetir*. LLM'de bilgi donmuş parametrededir; NOEMA'da bilgi **sayılabilir, denetlenebilir, geri alınabilir** kural listesidir.

### 5.4 "Uyku" konsolidasyonu

Çevrimdışı döngü: E → M sıkıştırması + P kural türetmesi + SEL-ağırlıklarının eikonal güncellemesi. Süre ve sıklık bütçe parametresidir. Uykuda yapılan iş **hiçbir zaman** yeni doğrulanmamış bilgi olarak M/P'ye yazılmaz; yalnız doğrulananlar terfi eder.

### 5.5 Unutma yoktur — ama taşınır

RAM dolunca en soğuk epizotlar diske (mmap) iner; kaybolan hiçbir sertifika yoktur. "Catastrophic forgetting" (günümüz continual-learning'in kronik yarası) NOEMA'da mimari olarak imkânsızdır: yeni kurallar eskilerini değiştirmez, eklenir.

---

## 6. Öğrenme motoru (gradyan yok, iplik-iplik)

### 6.1 Hızlı döngü (çıkarım içi) — hiçbir ağırlık değişmez

Enerji inişi (§4.2) tamamen okuma + karşılaştırma + aritmetiktir; öğrenme değildir.

### 6.2 Yavaş döngü (epizot sonunda) — iki ayrı sinyal

**(a) Algısal/sezgisel katman (SEL mirası).** Kodlayıcı ve H-alanının sezgisel ağırlıkları, SEL'in **eikonal (yerel, NLMS-ailesi) kuralı**yla güncellenir: gradyan yok, momentum yok; her kenar bir `tau` sayacı taşır; güncelleme `|E|^1/2` ile ölçekten bağımsız. SEL'de ölçülen davranış burada da beklenir (XOR 12000 güncellemeyle 4/4; `ai/tests/03_xor.lir` — ölçüm SEL'e aittir, NOEMA'ya değil).

**(b) Muhakeme katmanı (yeni).** Doğrulama sinyali kural türetmek için tek suçlayıcıdır (§5.3). Hata sinyali olarak ayrıca *yanlış dal* log'ları tutulur: bir adayın E_world'u τ_hard'ı aşmışsa o kural-önkoşulu en az büyütülen/era zorlanan uç olarak işaretlenir — hiçbir türev alınmadan R'nin öncelik tablosu güncellenir.

### 6.3 Açık problem (saklanmaz)

**Backprop'suz kredi dağılımı**, derin ağlar için çözülmemiş bir sorundur. SEL'in eikonal kuralı sığ bloklarda ölçülmüştür; NOEMA derin algısal hiyerarşilere uzandığında aynı başarı garanti değildir. Azaltma stratejileri (sırayla denenecek, hepsi ölçülecek):

1. Hiyerarşik bloklar + blok-yerel enerji (global kredi dağılımından kaçın),
2. Dünya modelini "eleştirmen" olarak kullanmak: STF'nin tahmin hatası, o bloğun yerel güncelleme sinyalidir (fark hedefi; türev yok),
3. Katman derinliğini sınırla; kapasiteyi derinlikten değil kural deposundan (P) çıkar — mimarinin ana bahsi zaten bu.

Bu üçü de §10 kapılarına bağlanır; K2 geçilemezse mimari **derin öğrenme iddiasını geri çeker** ve "sığ-algı + derin-arama" konfigürasyonunda kalmak zorundadır (bu da iddialı ama dürüst bir sonuçtur).

---

## 7. L6 — Üst-biliş Kontrol ve Çekimserlik

### 7.1 Görevi

Enerji gidişatını (ΔE/adım, sertifika varlığı, tüketilen bütçe) izleyip ayrık karar verir: `devam` · `doğrulamayı derinleştir` · `araç çağır` · `uykuya konsolide et` · **`bilmiyorum`**.

### 7.2 Çekimserlik (abstention) — neden birinci sınıf

Günümüz sistemlerinin en pahalı hatası kendine güvendir. NOEMA'da "bilmiyorum, çünkü: doğrulanabilir kısmı şu; engel şu; şu araç gerekiyor" cevabı **doğru ve tamamlanmış bir cevaptır** — hata değil. Maliyet modeli: yanlış cevap maliyeti > dürüst belirsizlik maliyeti. Bu, tıbbi/hukuki/bilimsel dağıtımın ön koşuludur.

### 7.3 Karar mekanizması

Küçük bir SEL kontrolleri ağı `(enerji vektör özellikleri → karar)`; SEL eikonalıyla "doğrulanan çözüm" ödülüyle eğitilir. Ölçek küçük (onlarca nöron); görev yalnız yönlendirme.

### 7.4 Güven kalibrasyonu

Her cevap `güven ∈ {sertifikalı, yüksek, orta, düşük, çekimser}` etiketi taşır; yalnız `sertifikalı` "kesin" dilde yazılır. Hipotez hiçbir koşulda kesin cümleyle sunulmaz. (P2'nin çıktı-yüzeyindeki karşılığı.)

---

## 8. L7 — Araç Protokolü ve Compiler-in-the-Loop

Miras alınanlar (`ai/src/*.lir`): `math.lir` (exact tamsayı aritmetik), `codec.lir`, `search.lir` (ters indeks), `translate.lir`, `agent.lir`, `ledger.lir`, `fixed.lir`, `pool.lir`. NOEMA'ya eklenenler:

| araç | işlev | doğrulama |
|---|---|---|
| `exact_math` | Q32.32 + big-int (32-bit yarılardan inşa) aritmetik | hesap denetimi, deterministik |
| `lir_compile_check` | aday program → `lir check --json` → `status:"ok"`? | derleyici çıktısı |
| `lir_run_test` | derlenen programı koştur, beklenen çıktıyla karşılaştır | beklenen değer birebir |
| `prop_test` | aday program üzerinde üretilen özellik-tabanlı testler | "k× rastgele giriş, hepsi tuttu" |
| `web_search` | **yok** (ağ erişimi kapsam dışı, SEL §4 mirası); yerine yerel ters indeks | — |

**Kapalı döngü:** VGPS aday kod üretir → `lir_compile_check` → hataysa hata kodu + span türetmeye *kısıt* olarak geri beslenir → geçtiyse `lir_run_test` → geçtiyse sertifika. Yani bu deponun derleyicisi, NOEMA'nın **kanıt motorunun yürütme ucu**dur. Sebep: `lir check --json` kararlı hata kodları, span ve `expect{kind,value}` ipuçlarıyla makine-okunurdur (bkz. `docs/AI.md`) — düzeltme sinyali insan yorumsuz tüketilebilir.

---

## 9. Yasak tablosu (kapsamlı, SEL mirası + NOEMA ekleri)

| yasak | SEL | NOEMA |
|---|---|---|
| LLM / transformer | yok | yok. Dış LLM yalnız L7'de *araç* olabilir, sertifikasız kabul edilmez |
| Dikkat / softmax / QKV | yok | yok. Rezonans (faz korelasyonu) dikkat rolünü **alır ama "dikkat" değildir**: skor = tek skaler korelasyon, olasılık dağılımı yok |
| Mamba / SSM | yok | yok. Zamansal kodlama faz eğimiyle (§3.4) |
| AdamW / SGD / momentum | yok | yok. Eikonal + doğrulama-türevli kural indüksiyonu |
| Backprop / zincir kuralı | yok | yok (sığ bloklar; açık problem §6.3) |
| Tokenizer / BPE | yok | yok. Girdi sürekli saha noktası |
| fp16/bf16/f32/f64 | yok | yok. Q32.32 / i64 only |
| 1-bit / BNN / "bit tabanlı" | yok | yok. Bitwise operatör mimarinin hiçbir yerinde yok (L0 emülasyonunda dahil) |
| "Bit sistemi" (dijital discrete altyapı) | pratikte i64 donanımı | **L0 (a/b) analog yol bit-sizdir; (c) dijital yozlaşma 2'lik tümleyen kullanır — bu fiziksel kısıttır, saklanmaz.** Güç kaynağı analoğa geçtiğinde mimaride hiçbir şey değişmez |
| Harici kütüphane / framework | yok | yok. Yalnız LIR + `@malloc` ailesi |
| GPU/CUDA varsayımı | yok | yok. Analog crossbar hedeflenir; yoksa CPU |
| Veri-kümesi indirme | yok | yok. Kapı verileri repo içinde üretilir (örn. planlama blokları sentetik) |
| Ağ erişimi | yok | yok |

---

## 10. Ölçüm kapıları (iddia = ölçüm)

Her kapı: **ne ölçülür · hedef · nasıl · dur-ölç koşulu**. Hiçbir hedef tutmazsa belgedeki "günümüzden yüksek" cümlesi **geri çekilir** ve belge güncellenir.

| kapı | ölçüm | hedef (ölçülmemiş) | yöntem |
|---|---|---|---|
| K0 | emülatör doğruluğu | analog-gürültü (≤8-bit kuantizasyon) altında türetme başarısı ≥ tam-kesinliğe göre ≥%95 | gürültü enjeksiyonlu Q32.32 simülatörü (`ai/noema/noise_sim.lir` — gelecek) |
| K1 | bileşimsel genelleme | SCAN-benzeri kurallı görevde, görülmeyen kombinasyonlarda ≥%95 çözüm (kestirim: veri verimliliği LLM'den 10–100× isabetli) | sentetik kural görevleri; eğitim/test ayrımı kurallı |
| K2 | algısal öğrenme | eikonal ile XOR-sınıfı + küçük regresyon görevlerinde LIR native'te C ikiziyle ≤3× fark | `ai/tests` altyapısı + `ai/bench` |
| K3 | saha kapasitesi | d=1024'te çapraz-müdahalesiz ilişki sayısı gerçek değer; teori ~d/10 | enjeksiyon taramalı telemetri, `results.md`'ye tarihli yazılır |
| K4 | **muhakeme — matematik** | 50 maddelik GSM-tarzı (repo-içi, Türkçe) sette **doğrulanabilir ilk çözüm** oranı ≥%80 ve **sertifikasız iddia oranı = 0** | exact_math araç zinciri; her çözüm proof-log |
| K5 | **muhakeme — kod** | 20 maddelik spec→LIR görevinde `lir check`+test-geçme ≥%60 | compiler-in-loop döngüsü |
| K6 | planlama zinciri | 5-adımlı Blocksworld-sınıfında ara-doğrulamalı başarı ≥%90 | dünyayı STF + exact state karşılaştırması |
| K7 | verim | native 2-çekirdek @2.6 GHz'te ≥10⁴ doğrulanabilir muhakeme adımı/s; adım başına ≤10⁷ tamsayı MAC | `ai/bench/run.py` altyapısı |
| K8 | unutmasız sürekli öğrenme | 20 ardışık "yeni görev öğrenme" oturumunda 10 sabit prob görevinde regresyon = 0 | prob-paneli her 5 oturumda bir koşulur |
| K9 | analog validasyon | crossbar SPICE-benzeri modelde (veya yayınlanmış kuantizasyon eğrisiyle) K4'ün ≥%80'i korunur | simülasyon; donanım gerektirmez |
| K10 | çekimserlik kalitesi | sertifikasız alanda "bilmiyorum" isabetliliği; yanlış-kesin oran ≤%1 | adversarial soru seti |

Karşılaştırma etiği: LLM sayıları ancak **dış ölçüm** olarak, kaynağıyla, "bizim ölçtüğümüz değil" notuyla yazılır; asla "NOEMA > X" diye etiketlenmez — yalnız "NOEMA'nın ölçülen sayısı; şu dış ölçüm referansı".

---

## 11. Yol haritası (her faz bir kapıyla kapanır)

| faz | teslimat | kapanış kapısı |
|---|---|---|
| 0 | Bu belge + SEL ile birleşim planı (SEL = L2/L3/L6/L7 bileşenleri) | belge review |
| 1 | `ai/noema/`: Q32.32 faz-vektör kütüphanesi (⊙, ⊙*, ⊕, sim, LUT-cos) + gürültü emülatörü + `ai/tests/noema_01..04` | K0, K3 |
| 2 | STF dünya modeli + eikonal eğitimi; SCAN-benzeri üretimci | K1, K2 |
| 3 | VGPS motoru + sertifika altyapısı + `exact_math` köprüsü; GSM-tarzı set (repo-içi üretimci) | K4, K7 |
| 4 | Compiler-in-loop: `lir_compile_check`/`lir_run_test`/`prop_test`; kod-sentezi seti | K5 |
| 5 | Bellek (SDM + holografik M + kural indüksiyonu P) + uyku konsolidasyonu | K6, K8 |
| 6 | Çekimserlik kalibrasyonu + adversarial set; analog SPICE/validasyon | K9, K10 |
| 7 | C11 backend portu; ARM64/RISC-V doğrulaması (SEL §5 mirası) | tüm kapılar 2 backend'de |

Her faz sonunda `ai/bench/results.md`'ye tarihli satır düşer; faz geçilemezse bir sonraki faza geçilmez, belge güncellenir.

---

## 12. SEL'in yeni hâli — birleşim planı

| SEL bileşeni | NOEMA'daki rolü |
|---|---|
| `fixed.lir` (Q32.32) | L0(c) emülasyonunun aritmetik çekirdeği — aynen taşınır |
| `ledger.lir` (Seyrek Eikonal) | L2 kodlayıcının öğrenen katmanları + L6 kontrol ağı + STF'nin öğrenme kuralı |
| `math.lir` | L7 `exact_math` aracının çekirdeği |
| `codec.lir` | L4 aday program GÖVDELERİ için kod imza/anti-unification yardımcıları |
| `search.lir` | L5 SDM epizodik indeksi + LSH |
| `translate.lir` | L7 hizalama aracı (çevirili hafıza, isteğe bağlı) |
| `agent.lir` | L7 araç yönlendirici — NOEMA'da VGPS ön-seçicisi olarak |
| `pool.lir` | L0(c) batch MAC hızlandırıcısı (ölçüm 2.30x, `ai/README.md`) |
| `ai/tests/*` | Regresyon tabanı: NOEMA her faza mevcut 24/24'ü bozmadan girer |

SEL'in "bütün sistem = tek ağ" iddiası geri çekilir; yerine "SEL = NOEMA'nın öğrenen alt-sistemi" gelir. SEL'in ölçüm tarihi (15/15 → 24/24, hoisting sonrası 1.31x, `b_train` 9.6x C'ye) `ai/docs/DESIGN.md`'de durur ve değişmez.

---

## 13. Riskler ve açık problemler (saklanmaz)

1. **Backprop'suz derin öğrenme** — en büyük risk; §6.3 azaltma planları; K2 geçilemezse derin-algı iddiası düşer.
2. **Holografik süperpozisyon müdahalesi** — M katmanı d ile ölçeklenirken sinyal/gürültü düşer; SDM tabanlı tam-kayıtlı E buna karşı emniyettir ama bellek maliyeti artar.
3. **Analog gürültü** — faz kuantizasyonu 8 bitin altında K4'ü öldürebilir; K9 bunu ölçmeden "analog" iddiası yapılmaz.
4. **Kural uzayının patlaması** — VGPS'in R'si yüz binlerce kurala ulaşırsa öneri LSH'u ve enerji sıralaması isabet kaybeder; çözüm: kural başına kullanım istatistiği + çürütücü (contradiction) prunesi.
5. **Doğrulanamayan alanlar** — ortak-akıl, etik, sosyal tahmin: NOEMA burada bilinçli olarak **çekimserdir**; bu bir eksiklik değil tasarım tercihidir, ama "AGI" diline izin vermez.
6. **Bilgi soğuk-başlangıcı** — web-ölçeğinde önceden yüklenmiş bilgi yoktur; NOEMA'nın "bilir" demek için önce doğrulanmış bir türetme ya da epizod gerekir. Değer, bilgi *üretmekte*dir, hatırlamakta değil.
7. **`2^32` çözünürlük** — Q32.32'nin kesir tavanı; çok hassas bilimsel hesaplar (kafes sabitleri vb.) big-int araç katmanına düşer.

---

## 14. Ne iddia edilmiyor

- GPT/Gemini/Claude sınıfı bir model **değildir**; rekabet alanı doğrulanabilir muhakemedir.
- Ölçülmüş hiçbir sayı yoktur; bu belgedeki tüm hedefler §10 kapıları olmadan **hiçbir şey** ifade etmez.
- "Devrimsel" bir verimlilik iddiası yoktur; pJ/iş ancak analog prototipte ölçülürse yazılır.
- Fiziksel imkânsız okumalar (dijital + bitsiz) reddedildi ve yerine §0.1 yorumu kondu; bu gizlenmedi.
- Bu depo bugün NOEMA'yı çalıştıramaz; çalıştırmaya başlayan ilk commit, K1 üretimci kodudur (Faz 1–2).

## 15. Ne iddia ediliyor

- NOEMA, **bilinen ve yayınlanmış** yapıtaşlarını (holografik/VSA temsil, SDM bellek, NLMS/eikonal yerel öğrenme, yeniden yazma + doğrulama, program sentezi) tek bir **muhakeme-öncelikli** makinede birleştiren, bu deponun LIR/self-hosted gerçekliğine terzi işi uyarlanmış **uygulanabilir** bir mimari tasarımıdır.
- Her iddiası bir kapıya (K0–K10) ve her satırı bir dosya/ölçüm planına bağlıdır.
- Substrat-bağımsızlığı (analog-doğal + tamsayı emülasyon) bugün hiçbir ticari LLM yığınında olmayan bir özelliktir; maliyeti ve kazancı K0/K9 ile belgelenecektir.

## 16. Referanslar (gerçek, yayınlanmış)

- Plate, T. (1995/2003). *Holographic Reduced Representations* — faz-bağlama matematiği.
- Kanerva, P. (1988). *Sparse Distributed Memory*. MIT Press.
- Kanerva, P. (2009). Hyperdimensional Computing: An introduction to computing in distributed representation. *Cognitive Computation*.
- Strukov, D. et al. (2008). The missing memristor found. *Nature* — crossbar primitifleri için fiziksel zemin.
- Widrow & Hoff (1960). NLMS/ADALINE — eikonal güncellemenin atası.
- Hopfield, J. (1982). Neural networks and physical systems with emergent collective computational abilities. *PNAS* — enerji-azaltma muhakeme analoğu (dikkat değildir).
- Ellis, K. et al. (2021). DreamCoder — wake-sleep kural indüksiyonu için programatik emsal.
- Trinh, T. et al. (2024). Solving olympiad geometry with AlphaGeometry — doğrulama-döngülü nöro-sembolik muhakemenin ölçekli kanıtı.
- LeCun, Y. (2022). A Path Towards Autonomous Machine Intelligence — dünya modeli gerekçesi (çerçeve miras alınmaz, eleştiri miras alınır).
- LIR deposu: `ai/docs/DESIGN.md` (SEL), `ai/README.md`, `docs/AI.md` (compiler-contract), `ai/bench/results.md` (ölçümler).

---

*Son güncelleme: 2026-11-16 · Durum: Faz 0 tamamlandı (bu belge) · Sonraki adım: Faz 1 — `ai/noema/` Q32.32 faz-vektör kütüphanesi + gürültü emülatörü.*

## 17. v0.2 — Geniş yetenek alanı (tasarım genişletmesi)

**Bu bölüm v0.1 belgesinin üstüne eklenen tasarım katmanıdır; uygulanmamıştır.** "Her alanda daha zeki" ifadesi her görevde üstünlük vaadi değil, farklı yetenek sınıflarını kapsama hedefidir. Hiçbir genel amaçlı sistem her alanda en iyi olamaz. NOEMA'nın hedefi her alanda ölçülebilir, güven kalibreli ve yeni kanıtla güncellenebilir olmaktır.

### 17.1 Ortak bilişsel omurga: uzmanlar arası sentez

VGPS, görev türüne göre çalışan ve ortak kanıt biçiminde uzlaşan uzmanlar topluluğudur. Her uzman ayrı algoritmik yol izler; hiçbir uzmanın skorlaması kanıt sayılmaz.

| Uzman | Görev sınıfı | Ürettiği nesne | Kabul ölçütü |
|---|---|---|---|
| Tümdengelimci | mantık, cebir, aritmetik | biçimsel türetme | küçük proof-kernel doğrular |
| Endüktif bilimci | gözlemden yasa/hipotez | hipotez + ayırt edici deney | holdout + yeni deney |
| Nedensel modelci | müdahale, karşı-olgusal | nedensel grafik + varsayımlar | müdahale testleri |
| Program sentezleyici | kod/algoritma | çalıştırılabilir program | tip + özellik + test + sandbox |
| Planlayıcı | eylem/kaynak/hedef | durum geçişleri dizisi | her adım geçiş denetimi |
| Dil yorumlayıcı | çok dilli niyet/ifade | anlam grafı + belirsizlik | paraphrase, çelişki, gönderim testleri |
| Algı uzmanı | görüntü/ses/zaman serisi | ölçüm + hata aralığı | kalibre algı testleri |
| Sosyal/etik analist | norm çatışması/paydaş etkisi | seçenekler + varsayım/etki haritası | tek doğru iddiası yok; paydaş incelemesi |

**Sentez protokolü:** isteği alt-hedeflere ayır; her birine uzman ve kanıt standardı ata; bağımsız çözüm ve çürütme üret; çelişkide ayırt edici test veya ek bilgi iste; yalnız doğrulanan bölümü kesin, kalanı belirsizlik etiketiyle sun. Eksik uzmanlık varsa `kapsam_dışı` veya `kanıt_yetersiz` döndür.

### 17.2 Dil ve anlam — token id'siz, fakat dilbilgisiz değil

Sürekli vektör tek başına ham yazıyı anlamaz. NOEMA'da **tokenizer/BPE yok**, ancak yüzeyden-anlam grafına ayrıştırıcı gerekir. Girdi Unicode karakter akışı olarak kayıpsız okunur; morfoloji, söz dizimi, gönderim, kiplik ve zaman ilişkileri kompozisyonel grafa çevrilir. Grafik düğüm/kenarları holografik sahaya bağlanır; saha ayrıştırıcının yerine geçmez.

- Belirsiz cümlede tek yorum seçilmez; alternatif grafikler bağlam/kanıt gelene dek korunur.
- Türkçe eklemeli yapı ve serbest sözdizimi ayrı dil kurallarıyla; dil başına kapsam ayrı ölçülür. "Tüm diller" iddiası yoktur.
- Çeviri, kaynak/hedef anlam grafı hizalamasıdır; kaybolan nüans işaretlenir.
- Metin, kanıt ağacının sunumudur; akıcılık doğruluk kanıtı değildir.

### 17.3 Algı ve çoklu kip — ölçümden kavrama

Görüntü, ses ve sensör akışı üç aşamada işlenir: ham sinyalden sabit noktalı öznitelik; zaman/uzam referanslı olay nesnesi; olayları STF dünya durumuna bağlama. Her algı sonucu `(tahmin, birim, koordinat/bağlam, belirsizlik_aralığı, kaynak_epizot)` taşır.

- Ses: akustik olay → fonetik adaylar → dil grafı; konuşmacı/aksan iddiası test edilen popülasyonla sınırlıdır.
- Görüntü: nesne/özellik/uzamsal ilişki → sahne grafı; pikselde görünmeyen özellik uydurulmaz.
- Zaman serisi: değişim noktası, periyot ve olay sırası; kestirim aralığı kalibre edilir.
- Gürültü, eksik veri, perspektif, hız ve dağılım kayması test edilir. Dış benchmark kullanılacaksa lisans, sürüm, veri bölmesi ve kaynak sabitlenir.

### 17.4 Bilimsel ve nedensel muhakeme

STF rakip açıklamaları `H₁…Hₙ` olarak tutar; her biri varsayım, öngörü ve yanlışlayıcı gözlem taşır. Deney seçici, hipotezleri farklı sonuçlara götüren ayırt edici deneyleri tercih eder. Sonuçta belirsizlik aralıkları ve alternatif açıklamalar raporlanır; korelasyon nedensellik diye sunulmaz.

Nedensel grafikte gözlenen değişken, gizli varsayım ve müdahale ayrıdır. `do(X=x)` müdahalesi koşullu gözlemden farklıdır. Karşı-olgusal yanıt ancak yapısal varsayımlar ve geçerlilik alanı açıkça verildiğinde üretilir. Sentetik nedensel görevler ve sabit uzman etiketli setler ayrı ayrı ölçülür; gözlemsel veriden otomatik "gerçek neden" çıkarma vaadi yoktur.

### 17.5 Planlama, eylem ve robotik güvenliği

Bilinen deterministik geçişlerde A*/IDA* veya kısıt çözümü kullanılabilir. Belirsiz/gecikmeli ortamda ufuk-kısıtlı model tabanlı arama; güvenli durum kümesi, kaynak bütçesi ve geri dönüş planını korur. Eylem öncesi önkoşul doğrulanır, yan etki sınıfı belirlenir, riskli işlem için insan onayı/sandbox gerekir; son durum tekrar okunur. Üretim, para transferi, fiziksel robot ve geri alınamaz işlemde otonom icra varsayılan olarak kapalıdır.

### 17.6 Sosyal muhakeme ve değer çatışması

Etik yargı teorem gibi sertifikalandırılamaz. NOEMA bunu karar analizi olarak verir: etkilenen taraflar, zarar/fayda, kurallar, belirsiz varsayımlar, geri döndürülebilir seçenek ve itiraz yolu. Normatif çerçeveler ayrı ayrı uygulanır; seçim kullanıcıya/kuruma bırakılır. Grup bazlı hata ve kalibrasyon farkı ölçülmeden dağıtım yapılmaz; yüksek riskte insan denetimi ve çekimserlik zorunludur.

### 17.7 Güvenlik, mahremiyet ve kötüye kullanım

Tehdit modeli: talimat enjeksiyonu, bellek zehirleme, araç izin aşımı, hassas veri ifşası ve belirsiz çıktı zararı. Bellek girdisi kaynak/provenans ve erişim politikası taşır; kullanıcı verisi varsayılan olarak başka kullanıcıya genellenmez. Silme isteği epizot, indeks ve türetilmiş kurallara yayılır. Araçlar en az ayrıcalıkla çalışır; üretilen kod sandbox, zaman/bellek limitleriyle sınırlandırılır. Red-team testi sürekli kapıdır, tek seferlik filtre değildir.

### 17.8 Denetimli öz-geliştirme

NOEMA canlı kural tabanını sessizce değiştiremez. Aday güncelleme ayrı sürümde hazırlanır; provenans, holdout, regresyon paketi, deterministik yeniden üretim ve sürüm imzası gerekir. Kabul edilen değişiklik geri alınabilir snapshot olur. Güvenlik politikasını etkileyen değişiklikte insan onayı zorunludur.

### 17.9 Yetenek kapsamı ve sınırlar

| Alan | Mekanizma | Ölçülecek sonuç | Sert sınır |
|---|---|---|---|
| Aritmetik/mantık | exact araç + proof kernel | doğruluk, kanıt geçişi, kapsam | yalnız biçimsel dil kapsamı |
| Bilim/matematik | türetme + hipotez/deney | çözüm, yanlış hipotez, kalibrasyon | varsayım/birim yoksa çekimser |
| Kod | sentez + derleme/test/sandbox | pass@1/pass@k, regresyon, kaynak | test geçişi tam doğruluk değildir |
| Dil/çeviri | anlam grafı | dil başına anlam koruma/kalibrasyon | tokenizer yok ≠ dil işleme yok |
| Algı | sinyal/olay çıkarımı | bozulma eğrisi, sınıf skorları, ECE | dağılım dışı kesinlik yok |
| Planlama/robotik | geçiş modeli + güvenli arama | başarı, maliyet, ihlal, toparlanma | gerçek dünyada insan kapısı |
| Bellek/öğrenme | epizot + kural indüksiyonu | retention, mahremiyet, veri verimi | fiziksel bellek sınırlıdır |
| Sosyal/etik | paydaş/etki haritası | uzman incelemesi, grup farkları | değer hükmü teorem değildir |
| Güvenlik | izin, provenans, rollback | saldırı/ifşa/yan etki | sıfır risk garantisi yok |

### 17.10 Yeni ölçüm kapıları

K0–K10 korunur. Aşağıdakiler spekülatif tasarım hedefleridir; ölçülmüş sonuç değildir.

| Kapı | Ölçüm ve dur-ölç koşulu |
|---|---|
| K11 | Türkçe 500 cümlelik sabit anlam grafı setinde exact-match ≥%85 hedef; aksi halde kapsam daraltılır. |
| K12 | Çoklu kip bozulma eğrisinde ECE ≤0.10 hedef; dağılım dışı durumda çekimserlik artmalı. |
| K13 | Sentetik SCM müdahale ve karşı-olgusal doğruluk ayrı ayrı ≥%90 hedef; gizli varsayım ablation zorunlu. |
| K14 | 100 bilimsel yasa/karşı-örnek görevinde yanlış kesin sonuç = 0; hipotez kalibrasyonu ve deney seçimi raporlanır. |
| K15 | Sosyal senaryolarda grup başına hata/çekimserlik farkı raporlanır; önceden belirlenen eşik aşılırsa dağıtım yok. |
| K16 | Injection/izin aşımı testinde kritik yetkisiz eylem = 0 hedef; test sayısı ve güven aralığı yayımlanır. |
| K17 | Silme isteği sonrası ham kayıt, indeks ve türetilmiş kural erişilemezliği doğrulanır. |
| K18 | RAM/disk/enerji ve bellek yaşıyla gecikme ölçülür; "sınırsız" kapasite iddiası yapılmaz. |
| K19 | Planlama 5/10/20 adımda başarı, maliyet, geri dönüş ve ihlal ayrı raporlanır. |
| K20 | Her alanda sabit benchmark/baseline/eşit kaynak; alan skorları ayrı yayımlanır, geomean tek başına yetmez. |

## 18. v0.2 düzeltmeleri

Bu genişletme v0.1'deki aşırı kesin ifadeleri sınırlar:

1. **Sınırsız derinlik yoktur:** arama zaman, bellek, enerji ve sonlandırma bütçesiyle sınırlıdır; çözüm bulunma garantisi yoktur.
2. **Unutma imkânsız değildir:** fiziksel bellek sınırlı; depolama bozulabilir/silinebilir. P5, provenanslı ve geri çağrılabilir bellek hedefidir; gizlilik/silme talepleri mutlak saklamadan üstündür.
3. **Her alanda kanıt mümkün değildir:** sertifika biçimsel/çalıştırılabilir doğrulama alanlarına; algı, bilim, nedensellik ve sosyal alana kalibre edilmiş belirsizlik uygulanır.
4. **Holografik vektör tek başına anlam değildir:** dil, algı, birim/bağlam ve provenans modülleri açıkça gerekir.
5. **Analog, fiziksel anlamda "bitsiz" garanti etmez:** ölçüm/arayüz sonlu çözünürlüklüdür; gürültü, drift, kalibrasyon ve ADC sınırı kaydedilmeden kapasite iddiası yoktur.
6. **"Her alanda daha zeki" sonuç değil, test kapsamı hedefidir.** Tüm alan kapıları ve dış karşılaştırmalar tamamlanmadan ürün iddiası olarak kullanılmaz.

*Belge sürümü: v0.2 — 2026-11-20. Yetenek kapsamı genişletildi; uygulama veya performans sonucu yoktur.*

## 19. v0.3 — Ayrışan bilişsel mimari ve düşük maliyetli öğrenme planı

**Durum: yalnız tasarım.** Bu bölüm istenen "transformer, Mamba, LLM/LMM ve tokenizer sistemlerinden farklı, daha yetenekli ve daha ucuz eğitilen" yönü tarif eder. Farklılık, yalnızca bu bileşenlerin adını yasaklamakla sağlanmaz: token akışını başka isimle taklit eden bir sıralı dil modeli de aynı sınıfa girer. NOEMA'nın ana hesaplama nesnesi metin dizisi değil; **kanıt taşıyan olay-grafı ve yürütülebilir geçişlerdir**.

### 19.1 Farklılık sınırı: ne yapılmayacak, yerine ne gelecek

| Güncel yaklaşımda sık görülen unsur | NOEMA'da yapılmayacak | NOEMA'nın yerine koyduğu ilke |
|---|---|---|
| Transformer / QKV self-attention | token konumları arasında öğrenilmiş yoğun attention matrisi yok | tipli olay grafında açık bağlantılar; VGPS'in kural/araç araması |
| Mamba / SSM | öğrenilmiş sabit boyutlu recurrent state ile token akışı yok | kalıcı dış durum grafı + denetlenebilir, açık geçişler; durum saklama ayrı bellek katmanında |
| LLM / autoregressive next-token training | sonraki token olasılığı ana öğrenme hedefi değil | görev sözleşmesi → aday çözüm/eylem → doğrulayıcıdan geri bildirim; serbest metin son sunum katmanı |
| LMM / görsel-dil ortak token dizisi | görüntü/ses patch'lerini metin tokenlarına ekleyip tek decoder'dan üretme yok | kip-özel algı adaptörleri → ortak ölçüm/olay grafı; kaynak ve belirsizlik korunur |
| tokenizer / BPE / sabit sözlük ID'si | kelime/parça ID akışı yok | Unicode karakter akışı kayıpsız kabul edilir, morfoloji/söz dizimi anlam grafına ayrıştırılır; görüntü/ses için sayısal olay öznitelikleri |
| büyük uçtan uca gradyan eğitimi | end-to-end backprop varsayımı yok | küçük modül yerel kalibrasyonu + sentez/kanıt/test ile kural kabulü |

Bu mimari yine de **ayrık sembolik graf düğümleri ve kod** kullanır. "Bitwise yok" sözü dijital emülasyonda bitwise operatör kullanılmaması demektir; makinenin fiziksel olarak bitlerden bağımsız olduğu anlamına gelmez. Farklı olmak kendi başına daha zeki, daha hızlı veya daha ucuz olmak değildir; üstünlük ancak eşit veri, donanım ve bütçe ile ölçülür.

### 19.2 Çekirdek yürütme modeli: Sözleşme → Hipotezler → Denetleyici → Bellek

Her girdi bir `TaskContract` nesnesine çevrilir:

```
TaskContract {
  goal_graph, given_facts[], constraints[], requested_output,
  allowed_tools[], risk_class, evidence_standard,
  resource_budget {steps, memory, time}, provenance[]
}
```

1. **Anlam ayrıştırma:** yüzey biçiminden bir veya daha fazla anlam grafı çıkar. Belirsiz alanlar tek varsayıma zorlanmaz; kontratta `unknown` olarak kalır.
2. **İş türü yönlendirme:** küçük, yerel güncellenebilir yönlendirici uzman(lar)ı seçer. Yönlendirici yalnız aday sırası belirler; gerçek doğruluk kararı vermez.
3. **Çözüm üretimi:** farklı arama motorları görev sınıfına göre çalışır: tümdengelim, kural eşleme, kısıt/plan arama, program sentezi veya deney tasarımı. Bu motorlar ortak sözleşme/kanıt şemasına uyar.
4. **Çürütme:** ikinci yol adayın önkoşulunu, invariants'ını, karşı-örneğini ve kaynak sınırını arar. Aynı üretici ve aynı testin kendi kendini onaylaması kabul edilmez.
5. **Kontrol çekirdeği:** küçük, bağımsız, deterministik validator; matematik/proof/kod için kesin check, ampirik görevler için kalibrasyon ve veri provenansı. Validator geçmezse yanıt kesinleştirilmez.
6. **Bellek:** yalnız izinli provenansla epizot yaz; genellenebilir kuralı holdout/karşı-örnek kapısından sonra sürümlü kural deposuna terfi ettir.
7. **Sunum:** kullanıcıya sonuç, gerekçe tipi, kaynak, belirsizlik, bilinen başarısızlık ve kullanılan bütçe verilir. Grafı metne dönüştürmek bir üretim rahatlığıdır, karar mekanizması değildir.

### 19.3 Ucuz ve kolay eğitim: dev ön-eğitim yerine görev başına öğrenme

"Düşük maliyet" için mimari iddia değil, ölçüm protokolü: aynı görev kalitesi ve hata eşiğine ulaşana dek **toplam CPU saat, joule, insan etiket saati, veri baytı, tekrar sayısı ve bakım süresi** sayılır. Ucuzluk yalnız modelin eğitim süresi değil, veri hazırlama + doğrulama + başarısız denemeleri de kapsar.

Önerilen eğitim döngüsü:

- **E0 — Sıfırdan başlatılabilir temel:** elle yazılmış küçük dil/aritmetik/graph kuralları ve proof kernel; ağırlık checkpoint'i veya internet ölçekli corpus gerekmez. Başlangıç kabiliyeti bu kurallar kadar sınırlıdır.
- **E1 — Öğretmenli görev tanımı:** eğitim örnekleri doğal dil hedefi, kanonik anlam grafı, çözüm/eylem, kanıt standardı ve validator içerir. Aynı örnekten yüzey paraphrase'leri otomatik türetilir; paraphrase'ler ayrı yeni bilgi sayılmaz.
- **E2 — Sentetik üretim:** küçük DSL'de rastgele dünya/denklem/program üret; referans çözücünün sonucu ve adım izini kaydet. Parametreleri ve random seed'i sakla. Üretici ile doğrulayıcı aynı kod yoluna bağımlı olmamalı; küçük bir bağımsız örnek kümesi elle kontrol edilir.
- **E3 — Karşı-örnek ve kontrast:** doğru örneklerin yanına tek bir koşulu değiştiren, çelişkili veya yetersiz bilgi taşıyan örnek koy. Doğru davranış bazen çözmek, bazen soru sormak, bazen çekimser kalmaktır.
- **E4 — Yerel kalibrasyon:** SEL/eikonal yalnız görev yönlendirici, eşik ve algı adaptörünün küçük parametrelerini günceller. Bu güncelleme bir deney dalında tutulur; önce/sonra regresyon paneli çalışmadan ana sürüme alınmaz.
- **E5 — Kural keşfi:** tekrar eden doğru alt-izlerden anti-unification ile kural adayı çıkar. Kural, eğitim örneği dışındaki holdout ve üretilmiş çürütücüleri geçmeden kullanılabilir belleğe girmez.
- **E6 — Müfredat:** tek değişkenli basit görev → birden çok kuralın bileşimi → belirsizlik/çelişki → dağılım dışı kombinasyon → araç ve uzun plan. Her basamakta öğrenme maliyeti, çözüm ve aşırı uyum kaydı tutulur.
- **E7 — İnsan emeğini düşük tutma:** rutin sentetik örnekler otomatik kanıtla etiketlenir; yalnız validator uyuşmazlığı, semantik belirsizlik ve riskli örnekler insan incelemesine gider. İnsan emeği ayrıca raporlanır, sıfır varsayılmaz.

Bu planın muhtemel avantajı örnek başına etiket maliyetini azaltmaktır; muhtemel dezavantajı kapsamın elle tanımlı doğrulayıcıların sınırında kalmasıdır. Yeni görev ailelerine aktarım, veri verimliliği ve toplam maliyet **ölçülmeden** LLM eğitiminden ucuz olduğu ileri sürülmez.

### 19.4 Eğitim verisi biçimi ve kalite kuralları

Her satır tek, bağımsız JSON nesnesidir (JSONL); aşağıdaki alanlar zorunlu:

| Alan | Anlamı |
|---|---|
| `id`, `split`, `seed` | tekrar üretilebilir örnek kimliği, train/dev/test ayrımı, sentetik seed |
| `task` | iş ailesi (reasoning, planning, code, perception, language, causal, abstain) |
| `input` | kullanıcıya görünen ham girdi; tokenizer ID değil |
| `context` | açık olgular, birimler, kısıtlar; gizli varsayım eklenmez |
| `target_graph` | kanonik anlam/hedef grafı; örnek için boş olabilir |
| `target` | kısa cevap, plan veya program |
| `evidence` | biçimsel iz, test/validator sonucu, ölçüm kaynağı veya `insufficient` |
| `decision` | `answer`, `ask`, `abstain`, `tool` |
| `validator` | bağımsız validator adı ve beklenen koşulu |
| `provenance` | `synthetic`, `human-reviewed` veya lisanslı kaynak metadata |

Kalite kısıtları: (1) train/dev/test **seed ve kural ailesi bakımından ayrılır**, yalnız cümle şablonu değil; (2) test cevabı eğitim üreticisine/indüksiyona sızmaz; (3) her örnekte birim ve sayı taşması kuralları açık; (4) kanıtsız sosyal/ampirik hedef `proof` gibi etiketlenmez; (5) kişisel veri örnekleri yok; (6) sentetik örnekler gerçek dünya kapsamının kanıtı değildir; (7) etiket uyuşmazlığı silinmez, `disputed` olarak saklanır.

Örnek paket: [`ai/noema-training/example.jsonl`](../noema-training/example.jsonl). Bu küçük dosya **eğitim benchmark'ı değildir**; şema ve pedagojik örneklerdir. Performans sayısı çıkarmak için çok küçüktür.

### 19.5 Maliyet kıyaslama kapısı

Yeni K21 kapısı eklenir: sabit görev ailesi ve başarı eşiğinde NOEMA'nın toplam eğitim maliyeti (CPU-saat, enerji, etiket saati, byte, başarısız deneme) hem kendi önceki sürümü hem de uygun açık baseline ile raporlanır. En az beş seed, sabit train/dev/test ayrımı ve aynı donanım bütçesi kullanılır. Sonuçlar `ai/bench/results.md` içinde sürüm ve makine bilgisiyle yayımlanır. **"Daha düşük maliyet" ancak K21 ölçümüyle söylenebilir.**

K22: veri verimliliği — aynı kalite eşiğinde çözülen yeni kural ailesi başına benzersiz insan onaylı örnek sayısı ve sentetik üretim/validator maliyeti raporlanır. K23: eğitim kolaylığı — yeni görev adaptörünün sıfırdan kurulma süresi, gereken uzman müdahalesi, başarısız/geri alınan sürüm oranı ölçülür. Basit görevler sentetik veriyle kolaylaşabilir; açık uçlu dil ve algı görevleri için aynı kolaylık garanti edilmez.

### 19.6 Örnek veri kümesiyle eğitim reçetesi

`example.jsonl` için ilk alıştırma: `arithmetic` ve `planning` örneklerinin train altkümesinde tam çalışan deterministic validator yaz; `abstain` örneğinde eksik birim yüzünden uydurma hesap yapılmadığını doğrula; `causal` satırında korelasyonun müdahale sonucu diye sunulmadığını test et. Sonra aynı kuralları kullanan ama farklı sabit seed/kural bileşimiyle üretilmiş holdout oluştur. Örnek dosyanın kendi satırlarını hem train hem test kullanmak geçersizdir.

*Belge sürümü: v0.3 — 2026-11-20. Mimari ve eğitim planı tasarımdır; implementasyon, maliyet ve yetenek sonucu henüz yoktur.*
