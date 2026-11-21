# NOEMA — Analog-Doğal, Doğrulama-Kapılı Muhakeme Mimarisi

**Durum:** v1.5 — **tasarım belgesi. Uygulanmadı.** Hiçbir bileşeni bu depoda yok.
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

1. **Muhakeme derinliğini sabit katman yerine göreve/bütçeye bağlı yapmak** — NOEMA'da arama devam etme, bitirme veya çekimser kalma kararı verir; her adımın doğrulama seviyesi kaydedilir. Derinlik zaman/bellek/enerji bütçesiyle sınırlıdır ve çözüm garantisi yoktur. *Derinlik = parametre değil, açık kaynak bütçesi.*
2. **Kapasiteyi parametre sayısı yerine sayılabilir bilgi birikimine bağlamak** — kural deposu (procedural memory) her doğrulanmış türetmede **büyür**. LLM'de "bilmek" 12B weight'te gizlidir, ölçülemez; NOEMA'da "bilmek" = depodaki kural + bölüm sayısı, sayılabilir ve denetlenebilir.
3. **Bilişsel yeteneği sert kapılarla ölçmek** (§10): doğrulanabilir matematik, kod sentezi, planlama zincirleri, bileşimsel genelleme, unutmasız sürekli öğrenme. Her kapının bir sayı hedefi ve bir **"dur-ölç" koşulu** vardır. Kapı geçilemiyorsa mimari değişir, iddia kabartılmaz.

Dürüst karşı-taraf (NOEMA'nın kaybedeceği yerler): web-ölçeğinde hazır bilgi, açık-alan sohbet akıcılığı, 7/24 kesintisiz üretim. NOEMA, "her şeyi bilen sohbet modeli" değildir; **hesaplayan, doğrulayan, ispat üreten** bir çekirdektir. Bu dar ama gerçek bir iddiadır.

---

## 1. Tasarım ilkeleri

| # | İlke | Sonuç |
|---|---|---|
| P1 | **Muhakeme birincil, istatistik ikincil.** İstatistik aday önerir, asla kanıt değildir. | Her iddia `formal_proof`, `executed_test`, `empirical_support`, `hypothesis` veya `unsupported` evidence level taşır. |
| P2 | **Doğrulanabilir sınırlar açık olmalı.** | Kullanıcıya gerekçe ve evidence level gösterilir; proof tree yalnız kernel'in kapsadığı biçimsel iddialar içindir, her cevap için zorunlu değildir. |
| P3 | **Tokenizer/BPE yok; sembolik yapı ve açık parser vardır.** | Ham girdi kayıpsız saklanır, dil/modality parser'ı sürümlü rule pack'tir; kapsam dışı girdi belirsiz/unsupported olarak kalır. Holografik saha anlamın yerine geçmez. |
| P4 | **Çekirdek bilgi güncellemesi denetlenebilir ve geri alınabilir olmalı.** | §25'teki Karşıt İzden Sözleşme Derleme temel öğrenme adayıdır; SEL/eikonal yalnız uyumluluk/ablation deneyidir, çekirdek zorunluluğu değildir. |
| P5 | **Bellek katmanlı ve provenanslıdır; kapasite sonlu, arşiv büyütülebilir.** | E/M/P katmanları ve dış depo; silme/retention politikası P5'in üstündedir. Parametre belleğinde kayıpsız öğrenme garantisi yoktur. |
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

Her kavram, `d` boyutlu kompleks vektördür: `vⱼ = (xⱼ,yⱼ) ≡ xⱼ+i·yⱼ`; başlangıçta faz-kodlu kavramlarda `(cos θⱼ, sin θⱼ)` kullanılır. Analog yol faz/genlik taşır; dijital yol her reel/imaginary bileşeni Q32.32 `i64` ile saklar. Böylece bağlama ile demetleme aynı tipte ve matematiksel olarak tanımlıdır. `d` koordinat, dijital ham vektör başına `16d` bayt demektir (d=512 için 8192 bayt; indeks/meta hariç).

| işlem | tanım | dijital emülasyon |
|---|---|---|
| Bağlama `⊙` | `(x+iy)⊙(a+ib)=(xa−yb)+i(xb+ya)` koordinat başına | 4 Q32.32 çarpma + 2 toplama/çıkarma; taşmada **hata**, sessiz saturasyon yok |
| Ters bağlama `⊙*` | kompleks eşlenik `(x,y)→(x,−y)` | reel bileşeni kopyala, imajiner işaretini tersle |
| Demetleme `⊕` | koordinat başına kompleks toplama; toplama fan-in ve aralık üst sınırı manifestte | Q32.32 toplama; taşma olasılığı varsa batch reddedilir veya daha geniş exact yol kullanılır |
| Norm | `||v||²=Σ(x²+y²)`; normalize yalnız ölçüm/çıktı gerektiğinde | kare/toplama/isqrt/div; overflow kontrolü zorunlu |

Benzerlik `sim(v,w)=Re(Σ conjugate(vⱼ)wⱼ)/(||v||·||w||)`; sıfır-norm vektör geçersizdir. Yaklaşık Q32.32 hesap öneri sıralaması içindir; sınır civarında karar exact/interval hesapla tekrar edilir. Faz LUT'ı ve `cos(θ−φ)` tanımı ancak ileride optimize edilmiş özel backend'de kullanılabilir; semantik otorite yukarıdaki kompleks tanımdır. İşlemlerde XOR/AND/OR/shift yoktur; dijital donanımın iç temsili ayrı fiziksel gerçektir.

### 3.2 Temsil seçimi ve sınırlamalar

- Kompleks faz binding terslenebilir bir bileşim operatörüdür; **tek başına dil anlamı veya mantıksal kanıt değildir**. Mantık ve tipler ayrı graf/kural deposundadır.
- Analog toplama devresi ölçek/drift/gürültü etkiler; crossbar'ın doğal akım toplaması her iki bileşende doğru faz işlemi yapıldığı anlamına gelmez. Faz/genlik okuma, kalibrasyon ve ADC/DAC kaybı ölçülmeden analog uygulama iddiası yoktur.
- Dijital emülasyon `d=512` ile başlayabilir; gerçek bellek `16d` bayt + indeks/meta'dır. Boyut/normalize/fan-in performansı K3 ve K7 ile ölçülür; L1'e sığma varsayımı yoktur.
- Q32.32'de her ara çarpımın ölçekleme/overflow davranışı tanımlanmalı; saturasyon benzerliği sessizce bozduğu için vektör çekirdeğinde hata döndürür ve örneği karantinaya alır.



### 3.3 Kapasite (teorik, ölçülecek)

VSA/HD literatürü dağıtık kodlarda girişim ve kapasite için olasılıksal sınırlar verir; bu sonuçlar NOEMA'nın kompleks Q32.32 binding/bundling, retrieval ve gürültü koşullarına otomatik taşınmaz. NOEMA `ai/noema/` emülatöründe ilişki sayısı, yanlış recall, false-positive ve gürültü eğrisini ölçmelidir (§10, K3). `~d/10` başlangıç sweep noktasıdır; teorik garanti veya kapasite vaadi değildir.

### 3.4 Diziler ve zaman

Konum kodlaması permütasyon yerine **faz kodu** olabilir: sıra indisindeki `t` için her koordinata sabit bir unit-phase kod `pⱼ^t` bağlanır. Vektör temsilinde bu kompleks çarpımdır; dijitalde tek bir çarpma değildir, Q32.32 multiply/add fan-out ve overflow maliyeti taşır. Faz rampasının üretimi/cache'i ayrıca bütçelenir. Bu bir alternatif kodlama hipotezidir; dizi görevlerinde positional baseline'a karşı ölçülmeden varsayılan sayılmaz.

---

## 4. L4 — Muhakeme Çekirdeği: VGPS (Doğrulama-Kapılı Program Araması)

Mimarinin merkezî tasarım hipotezi budur: **bütçe-kontrollü arama ve açık evidence level ile daha derin/denetlenebilir muhakeme**. Günümüz sistemlerine göre üstünlük ya da genel hatasızlık ölçülmüş değildir; ilgili kapılarda karşılaştırılacaktır.

### 4.1 Muhakeme nedir (NOEMA'da)

Bir muhakeme, **tipli bir yeniden yazma sistemi** `R` içinde, hedefe götüren bir türetmedir:

- Kurallar: `lhs ~> rhs where guard` — küçük tipli LIR fonksiyonlarıdır (emülasyonda i64 giriş/çıkış; doğrulama `lir check` + koşma ile).
- Durum: `(hedef, kısıt-kümesi, kısmi program)` üçlüsü; H vektörü aday benzerliği için kullanılır, döngü/tekrar kararı canonical serialized exact key üzerinden verilir (yaklaşık faz skoru eşitlik kanıtı değildir).
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

- **Öneri mekanizması:** ilk referans sürümde type/arity/guard'a göre deterministik sıralı exact rule index ve bütçeli lineer tarama. Daha sonra eklenebilecek approximate vector/LSH index yalnız aday sıralar; exact checker ve canonical key son kararı verir. Karmaşıklık ölçülmeden `O(log|R|)` hedefi vaat edilmez.
- **Transposition table** döngüleri ve tekrarlı dalları eler → arama sonsuza gitmez.
- **Enerji ağırlıkları** `w₁..w₄` SEL-eikonal ile çevrimdışı öğrenilir (§6.1); arama sırasında sabittir.

### 4.3 Sertifika ve "neden?" sorusu

Bir iddianın epistemik seviyesi açıkça ayrılır: **kanıtlandı** yalnız kernel'in biçimsel olarak denetlediği proof; **çalıştırma ile sınandı** derleme + test + sandbox sonucu (genel doğruluk ispatı değildir); **ampirik destekli** ölçüm/veri sonucu; **hipotez** henüz doğrulanmamış adaydır. `lir check` veya birim testin geçmesi tek başına tüm program davranışının ispatı sayılmaz. Her seviyede kaynak/versiyon/hash kaydedilir. İz, bellekte kuralın meta-verisinde saklanır; kullanıcıya sunulduğunda kanıt/çalıştırma ayrımı görünür:

```
gerekçe := Şu-kanıtlar-zinciri: [kural:kare-alma-karo, doğrulandı: #8412]
                                [kural:ortak-çarpan-ayır, doğrulandı: #7933]
                                [hedef:ifadeyi-sadeleştir, sonuç: 2x(x+3)]
```

LLM'de "neden?"in cevabı daha çok metindir; NOEMA'da "neden?"in cevabı **çalıştırılmış ve geçmiştir**. Bu, muhakeme kapasitesinin ölçülebilir tek biçimidir.

### 4.4 Derinlik için tasarım hipotezleri (üstünlük iddiası değil)

| eksen | günümüz LLM'leri | NOEMA (tasarım) |
|---|---|---|
| Derinlik | sistem/bütçeye göre değişir | bütçe ve sonlandırma koşuluna bağlı arama; çözüm garantisi yok |
| Hatasızlık | olasılıksal çıktılar olabilir | biçimsel kernel'in kapsadığı iddialar doğrulanır; test geçişi ispat değildir |
| Bileşimsellik | görev ve temsil bağımlı | graf/kural bileşimi hedefi; genelleme K1 ve K20 ile sınanır |
| Bilgi büyümesi | sistem politikasına bağlı | arşiv/kural deposu sürümlenir; silme ve finite storage sınırı geçerlidir |
| Enerji/token | donanım/yöntem bağımlı | sayısal maliyet iddiası yok; K7/K21 ile ölçülür |

**Neden iddia değil:** zincirin her halkası tasarımda doğru görünse de hiçbiri bu depoda koşulmamıştır. Sayısal rakamların doğrulanması §10'dur.

### 4.5 LLM'lerle dürüst ilişki

NOEMA bir "daha iyi transformer" değildir ve onlarla rekabet etmez; **doğrulanmış muhakeme gerektiren her yerde** onların yerine/yanında çalışır: matematik, kod, planlama, bilimsel denetim. Ortak-akıl metni için bir dış LLM *araç* olarak çağrılabilir (L7), ama çıktısı hiçbir zaman sertifikasız kabul edilmez — dış LLM da bir araçtır, otorite değil.

---

## 5. L5 — Bellek (üç katman + uyku)

### 5.1 Epizodik (E) — Kanerva SDM üzerine

Her çıkarım epizotu `(raw_ref, giriş-vektörü, türetme/çalıştırma izi, sonuç, evidence_level, consent/retention)` tutar. Ham veriyi ayrı content-addressed arşiv saklar; embedding/vektör tek başına ham kaydın kayıpsız temsili değildir. Kompleks Q32.32 vektör d koordinatta en az `16d` bayttır; d=1024 için 16 KiB, buna indeks ve değişken uzunluktaki iz dahil değildir. SDM benzerlik indeksi geri çağırma hızlandırıcısıdır; asıl kayıt key ile okunur. Silme/retention policy erişim ve depolama süresini belirler.

### 5.2 Anlamsal (M) — holografik süperpoziyon

Sık tekrar eden epizotlar M'de yaklaşık retrieval cache girdilerine bağlanabilir; raw epizot E ve exact key korunur. Kompleks vektör demeti kayıplı olabilir; `~d/10` yalnız test edilecek hipotezdir, kapasite/erişim doğruluğu değildir. M'den gelen sonuç exact key + source record ile doğrulanmadan authoritative sayılmaz. M kapatıldığında doğruluk değişmemeli; yalnız latency/recall değişimi ölçülür.

### 5.3 Prosedürel (P) — kural deposu, mimarinin "bilgisi"

VGPS'in tükettiği `R` buradadır. Kurallar şu yolla doğar:

1. E'de tekrarlayan alt-türetmeler bulunur (aynı hedef H-vektörü ≥3 epizotta),
2. **anti-unification** (karşı-örnek birleştirme) ile ortak şema çıkarılır,
3. şemaya uyan *hold-out* epizotlar üzerinde doğrulanır,
4. geçerse `R`'ye sertifikası ve gerekçe türetmesiyle eklenir.

Bu, **gradyansız öz-geliştirme**dir: sistem, kendi doğrulanmış başarılarından yeni operatörler *türetir*. LLM'de bilgi donmuş parametrededir; NOEMA'da bilgi **sayılabilir, denetlenebilir, geri alınabilir** kural listesidir.

### 5.4 "Uyku" konsolidasyonu

Çevrimdışı döngü: E → M sıkıştırması + P kural türetmesi + SEL-ağırlıklarının eikonal güncellemesi. Süre ve sıklık bütçe parametresidir. Uykuda yapılan iş **hiçbir zaman** yeni doğrulanmamış bilgi olarak M/P'ye yazılmaz; yalnız doğrulananlar terfi eder.

### 5.5 Retention, arşiv ve unutma riski

RAM dolunca izinli kayıtlar dış depoya taşınabilir; checksum/backup/restore testleri gerekir. Bu, fiziksel kayıp veya indeks hatasını imkânsız yapmaz. Yeni kural sürümlü eklenir; ancak retrieval, yönlendirici ve sınırlı parametre değişikliği eski davranışı etkileyebilir. K26 retention testleri başarısızsa aday release terfi etmez. Silme ve retention policy arşiv ömründen üstündür.

---

## 6. Tarihsel öğrenme motoru (v0.1–v0.8; v0.9 çekirdek öğrenme için §25'e bakın)

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

## 12. Tarihsel SEL uyumluluk haritası — v0.9 core dependency değildir

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

- Bu madde v0.1–v0.8 historical design record'dur ve v0.9 core için **geçersizdir**. Güncel çekirdek TTA + Karşıt İzden Sözleşme Derleme adayıdır; VSA/SDM/NLMS/LSH artık zorunlu core değildir (§25). Hiçbirinin uygulama/performans sonucu yoktur.
- Her iddiası bir kapıya (K0–K10) ve her satırı bir dosya/ölçüm planına bağlıdır.
- Analog-doğal + tamsayı emülasyon iki backend hedefidir. Bunun güncel sistemlere göre özgünlüğü, maliyet avantajı veya kazancı karşılaştırmalı araştırma/ölçüm yapılmadan iddia edilmez; K0/K9 ve dış baseline incelemesi gerekir.

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
- **E4 — Yerel kalibrasyon:** v0.9 core için SEL/eikonal zorunlu değildir. İstenirse yalnız karşılaştırma/uyumluluk modülü olarak route/algı adaptörünün küçük parametrelerini izole candidate branch'te günceller; K43 ablation ve retention paneli geçmeden ana sürüme alınmaz.
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

## 20. v0.4 — Uçtan uca framework ve kayıpsız sürekli ön-eğitim

**Durum: tasarım; uygulanmış eğitim altyapısı değildir.** Bu bölüm tüm AI framework yaşam döngüsünü ve "lossless continuous pretraining" talebini operasyonel olarak tanımlar. "Kayıpsız" tek anlamlı bir vaat değildir; burada üç farklı garanti ayrılır.

### 20.1 Kayıpsızlığın kesin anlamı ve imkânsız vaatler

| Katman | Tasarım garantisi | Garanti edilmeyen şey |
|---|---|---|
| Ham kaynak kaydı | İzinli ve saklanması hukuken uygun her kayıt, özgün baytlarıyla, checksum ve provenansla değişmez nesne deposuna yazılır; normalizasyon ayrı türetilmiş nesnedir. | Fiziksel arızaya karşı mutlak ölümsüzlük; yedek ve restore testleri riski azaltır. |
| Öğrenme olayı | Her kabul, ret, düzeltme ve sürüm append-only event log'a yazılır; aynı snapshot + event dizisi deterministik dijital backend'de tekrar oynatılabilir. | Analog backend'de bit-bit tekrar üretim. |
| Bilgi/beceri | Önceki bilgi arşivde tutulur; aday model geçmiş prob testlerini geçmeden terfi etmez; eski sürüme rollback mümkündür. | Sınırlı parametrede keyfi büyüyen tüm bilginin kayıpsız sıkıştırılması veya her görevin aynı kalması. |
| Silme/mahremiyet | Onaylı silme isteği ham nesne ve türevlerini policy'ye göre erişilemez kılar; içeriksiz tombstone audit izi bırakır. | İçeriği silip aynı anda geri getirilebilir kopya saklamak. |

Burada **lossless**, "izinli stream kaydı sessizce atılmaz veya aslı yok edilerek dönüştürülmez" demektir; model ağırlıklarının her örneği unutmasız özümsemesi değildir. Model sınırlı/değişebilir, arşiv gerçeğin kaynağıdır. Depolama kotası dolarsa sistem sessizce veri düşürmez: ingest'i durdurur/geri basınç uygular veya açık politikayla tiered storage'a taşır.

### 20.2 Tam framework bileşenleri

NOEMA tek model dosyası değil, sürümlenmiş modüllerdir. Başlangıçta tek süreç olabilir; arayüzler değişmeden worker'lara ayrılabilir.

```
İstemci/API → A Girdi kapısı → B Güvenlik/izin/PII
  → C Çok-kipli alıcılar (metin/ses/görüntü/tablo/sensör/kod)
  → D Anlam ve olay grafı (alternatif yorum, birim, provenans)
  → E Görev yönlendirici → F Uzman motorları
       ├─ VGPS proof/kural arama       ├─ exact math/kod sentezi
       ├─ STF dünya/nedensel model     ├─ planlama/kısıt çözümü
       ├─ algı/ölçüm adaptörleri       └─ E/M/P retrieval
  → G Bağımsız doğrulayıcı + çürütücü + güven kalibratörü
       ├─ geçer → H yanıt/araç onayı
       └─ kalmaz → yeniden ara / soru sor / çekimser kal
  → I Epizot yazıcısı → J İzole sürekli öğrenme hattı
       ├─ tüm kapılar geçer → imzalı sürüm deposu
       └─ hata → karantina / ret / rollback
```

Ortak protokoller: `TaskContract` görev, izin ve bütçeyi; `EvidenceRecord` iddia-kaynak-validator bağını; `MemoryEvent` bellek/öğrenme değişikliğini; `ToolCall` izin, yan etki ve timeout'u taşır. Her nesnede `schema_version`, `run_id`, `timestamp`, `producer_version`, `provenance_id` vardır. Şema dönüşümü eski kaydı overwrite etmez; yeni sürümlü görünüm üretir.

### 20.3 Sürekli ön-eğitim hattı

Ön-eğitim burada next-token corpus optimizasyonu değil, yeni örnek/olaylardan algı adaptörü, kural deposu ve küçük yönlendirici parametrelerini kontrollü güncelleyen sürekli yetenek öğrenimidir.

1. **Alım:** izinli örnek özgün baytları, kaynak/lisans/onam, zaman, hash ve kip bilgisiyle `raw_object` deposuna yazılır. Saklama izni yoksa içerik tutulmaz.
2. **Tekrar bulma:** hash/fuzzy-match tekrarları bulur; yeni gözlem event'i yine kaydedilir. Dedup ham kaydı silmez, aynı nesneye referans verir.
3. **Ön işleme:** Unicode/OCR/ASR/feature dönüşümleri türetilmiş artifact'tir; kaynak değişmez, dönüşüm sürümü ve kayıplı alan listesi saklanır.
4. **Güvenlik/kalite:** PII, lisans, poisoning, enjeksiyon ve bozuk etiket taranır. Karantina verisi canlı bellek/eğitime giremez.
5. **Örnek tipi:** `supervised`, `self_supervised`, `verified_trace`, `preference`, `correction`, `unlabeled`; her sınıf için izinli hedef ve provenans ayrı tutulur. Modelin kendi çıktısı gerçek etiket sayılmaz.
6. **Hedef:** verified trace → kural adayı; correction → önceki hata ile düzeltme bağlantısı; unlabeled → yalnız kendinden denetimli sinyal, kesin dünya bilgisi değil.
7. **Aday öğrenim:** küçük yerel adaptör/kural adayları izole snapshot'ta üretilir; başlangıç sürümü ve algoritma kaydedilir. Canlı model çevrimiçi ağırlık güncellemez.
8. **Replay:** yeni örneğe ek olarak izinli eski prob/retention örnekleri, sentetik counterexample ve adversarial set kullanılır. Seçim deterministik ve seed'li. Silinmiş içerik replay'e giremez.
9. **Bağımsız doğrulama:** exact/property/holdout/kalibrasyon/safety testleri eğitim hedefinden ayrı kod yoluyla çalışır; üretici kendi başarısını onaylayamaz.
10. **Terfi:** tüm kapılar, provenans ve policy geçerse imzalı sürüm registry'ye girer; hassas davranış değişiminde insan onayı gerekir. Aksi halde karantina, canlı sürüm sabit.
11. **Dağıtım:** offline replay → shadow (yanıt vermeden karşılaştır) → düşük riskli canary. SLO/regresyon bozulursa rollback.
12. **Düzeltme/silme:** düzeltme yeni event; geçmiş overwrite edilmez. Silme raw, kopya, cache, index, feature, replay planı ve kural bağımlılıklarını takip eder; yedek expiry'si policy'de belirlenir.

### 20.4 Eski yeteneklerin korunması

Her görev ailesi için kilitli prob setinde update öncesi `old_score`, sonrası `new_score` ölçülür. Ortalama skor tek kritik kaybı saklayamaz; her alan ve altgrup ayrı kapı.

- Proof kernel, güvenlik politikası ve exact aritmetik: test kapsamındaki kritik invariant'larda sıfır regresyon.
- Dil/algı/kestirim: önceden tanımlı tolerans, grup ve dağılım kırılımlarıyla kalibrasyon.
- Kural terfisi: destekleyici örnek + çürütücüler birlikte saklanır. Çürütülünce kural `retracted/superseded` yapılır; audit izi kalır.
- Parametre değişimi eşdeğer çıktı garantisi vermezse bu **kayıpsız update değildir**; aday sürüm, risk ve rollback bilgisiyle raporlanır.
- Snapshot + config + izinli data manifest + seed tarihsel tekrar sağlar; tüm tarihsel bilgiyi tek küçük modele sıkıştırmaz.

Bu, ölçülen testlerde forgetting'i azaltmayı hedefler; test edilmemiş her görevde unutmayı matematiksel olarak önlemez. Sonlu model durumu, keyfi büyüyen akışın tüm bilgisini kayıpsız temsil edemez. Gerçek kayıpsızlık büyüyebilen arşiv ister; bunun bedeli depolama ve aramadır.

### 20.5 Sürekli öğrenme event şeması

Örnekler [`ai/noema-training/continual_events.jsonl`](../noema-training/continual_events.jsonl) içinde. Event türleri: `observation` (raw content-addressed ref), `correction`, `candidate_update`, `evaluation`, `promotion`/`rejection`/`rollback`, `deletion`. Dosyadaki değerler demo/yer tutucudur; hash, imza veya skorlar gerçek ölçüm değildir.

Log append-only'dir ama kişisel veri içermez. Hash/pseudonymous id bile bazı bağlamlarda kişisel veri sayılabilir; erişim ve retention policy gerekir. Hashing şifreleme/anonimleştirme değildir.

### 20.6 Eğitim ve servis işletimi

**Offline factory:** manifest'i dondur → adayı üret → regression/benchmark/red-team → model+kurallar+schema+lineage manifestini paketle → imzala.

**Online serving:** inference sürümü pinlidir; kullanıcı verisi varsayılan olarak ağırlık güncellemez. Feedback consent/policy sonrası kuyruğa girer. Tenant verisi açık izin ve izolasyon olmadan global eğitime geçmez.

**Gözlemlenebilirlik:** p50/p95 latency, timeout, abstention, verifier fail, tool error, memory hit, drift, enerji ve maliyet; içerik loglamak yerine hassasiyetsiz sayaçlar. Yanıt model/rule/validator sürümüne bağlanır; rollback imzalı eski snapshot'a döner.

**Güvenlik:** araçlar least privilege; kod sandbox ve kaynak limiti; model çıktısı doğrudan shell veya fiziksel eylem yetkisi değildir. Destructive/high-impact eylemde kapsamlı izin, insan onayı ve son durum doğrulaması gerekir. Poisoning şüphesinde kaynak karantinaya alınır, dependency grafı taranır.

### 20.7 Yeni ölçüm kapıları

| Kapı | Ölçüm | Başarı yorumu |
|---|---|---|
| K24 — ingest integrity | raw event hash eşleşmesi + restore testleri | test edilen saklama koşullarında kayıp 0; mutlak ölümsüzlük değil |
| K25 — replay determinism | aynı snapshot/manifest/seed dijital tekrarları | event/snapshot eşitliği; analog backend kapsam dışı |
| K26 — forgetting | her update sonrası eski görev ailesi ve invariant | önkayıtlı eşik; yalnız test paneli kapsamında |
| K27 — düzeltme yayılımı | yanlış türetilmiş index/kural bulunup retraction | dependency kapsamı ve kaçak riski raporlanır |
| K28 — silme uyumu | sentetik veri yaşam döngüsü: raw/copy/cache/index/replay/artifact | policy kapsamındaki erişim kesilir; model unlearning ayrıca ölçülür |
| K29 — continual maliyeti | saat/enerji/etiket/byte/update gecikmesi | aynı kalite ve donanımda baseline |
| K30 — staged rollout | shadow/canary tespit ve rollback süresi | SLO önceden belirlenir |

### 20.8 Tasarımı uygulamaya bağlayan kararlar

Framework arayüzleri ve yaşam döngüsü burada tanımlıdır; uygulama başlamadan ADR ile sabitlenecekler: (1) LIR ABI ve worker sınırları; (2) disk object-store/index; (3) izin, retention ve silme policy'si; (4) ilk görev ailesi (öneri: LIR kod sentezi + matematik); (5) bütçe/latency profili; (6) manifest/validator imza biçimi. Kullanıcı verisi politikası netleşmeden canlı sürekli öğrenme açılmamalıdır.

*Belge sürümü: v0.4 — 2026-11-20. Uçtan uca tasarım ve kayıpsız ingest/denetimli öğrenme protokolü eklendi; uygulama veya forgetting maliyet ölçümü yoktur.*

## 21. v0.5 — Evrensel görev kapsaması ve veri şeması v2

**Durum: tasarım ve şema örneği; hiçbir modalite adaptörü uygulanmış değildir.** "Güncel modellerin yapabildiği her şey" için kapalı ve sonsuza dek tamamlanmış bir liste yoktur; modeller ve görevler değişir. Bu nedenle framework yetenekleri aşağıdaki **sürüm kontrollü kapsam kataloğunda** tanımlar. Amaç aynı API/veri hattında her görev türünü ifade edebilmek ve her birini ayrı test etmektir; tüm görevlerde güncel frontier sistemleri aşma iddiası değildir.

### 21.1 Kapsam kataloğu (görev → adaptör → çıktı → doğrulayıcı)

| Aile | Kapsanan iş türleri | Gerekli girdi/çıktı | Doğrulama |
|---|---|---|---|
| Sohbet ve talimat | çok turlu bağlam, rol, sistem politikası, belirsiz istek, özet | mesaj dizisi + konuşma belleği referansı | yönerge koşulları, kaynak ve yanlış iddia testleri |
| Dil | çok dillilik, çeviri, paraphrase, dil algılama, morfoloji, uzun doküman, tablo/JSON | metin parçası + dil/offset/meta | anlam koruma, kaynak span hizası, şema doğrulama |
| Muhakeme | aritmetik, biçimsel ispat, tümdengelim, indüksiyon, karşı-olgusal, bilimsel hipotez | graf, birimler, varsayımlar, proof/hipotez | proof-kernel veya holdout/kalibrasyon |
| Kod ve bilgisayar kullanımı | kod üretme/düzeltme, test, terminal/IDE/web arayüz eylemi | dosya/araç durumu + izinli ToolCall | derleme, test, sandbox, eylem sonrası durum |
| Retrieval / bilgi | yerel doküman arama, alıntı, kaynak sentezi, güncel harici veri (izinli connector varsa) | indeks/URI/zaman damgası | alıntı kaynağına span doğrulaması; erişilemeyen kaynakta çekimserlik |
| Görüntü ve belge | görüntü betimi, OCR, grafik/diagram, sayfa düzeni, çoklu görüntü kıyası | image/document ref + sayfa/kutu/koordinat | OCR span, koordinat, soru-cevap/grounding metrikleri |
| Ses | konuşmayı tanıma, konuşmacı dönüşü, ses olayı, konuşma anlama/üretim görev tanımı | audio ref + time segments + speaker id | zaman hizası, WER/CER, konuşmacı/olay kalibrasyonu |
| Video / canlı akış | kareler, zaman damgası, olay sırası, ses-video hizası, stream'in parça parça işlenmesi | frame/audio chunk refs + timestamp | olay zaman aralığı, sıralama, gecikme ve eksik chunk testi |
| Uzamsal / hareket | koordinat, pose, eylem dizisi, robot durumu | birimli koordinat/transform + zaman | kinematik/geçiş validator, güvenli alan kontrolü |
| Sayısal / bilimsel veri | CSV/array, sensör, zaman serisi, grafik, belirsizlik | typed tensor/table ref + birim/eksik değer maskesi | sayısal tolerans, birim kontrolü, split-by-entity |
| Araçlar ve ajanlar | tool seçim, çok adımlı görev, API cevapları, hata toparlama | izinli araç şeması + sonuç artifact'i | simulator, side-effect audit, human approval |
| Tercih ve düzeltme | tercih sıralaması, eleştiri, red-team, kullanıcı düzeltmesi | iki aday + tercih gerekçesi veya önce/sonra | tercih seti ayrımı, policy ve bias incelemesi |
| Güvenlik / karar | red/abstain, risk sınıflama, prompt injection, privacy | tehdit örneği + izin/kapsam | saldırı başarı oranı, false positive/negative, privacy test |

Her satır için eklenti manifestinde kapsanan diller, çözünürlük/duration, izinli eylemler, sınırlar ve uygun benchmark kayıt edilir. Modül yoksa sistem o işi destekli gibi göstermez; `unsupported_modality`/`unsupported_task` döndürür. Modüller arasında tek genel başarı yüzdesi kullanılmaz.

### 21.2 Universal Example Record v2

Tek bir JSONL satırı bir **task episode**'dur; metin ve payload aynı dosyada olmak zorunda değildir. Büyük ikili içerik adreslenmiş blob deposunda bulunur; JSONL yalnız metadata/ref taşır. Örnek üst düzey biçim:

```json
{
  "schema": "noema.example.v2",
  "id": "opaque-id",
  "split": "train|dev|test|retention|redteam",
  "group_key": "entity_or_rule_family_hash",
  "seed": 123,
  "task": {"family": "video_qa", "capability": "temporal_grounding", "risk": "low"},
  "conversation": [{"role": "user", "parts": [
    {"kind": "text", "text": "..."},
    {"kind": "image_ref", "uri": "cas://...", "sha256": "...", "frame": 0, "time_ms": 0},
    {"kind": "audio_ref", "uri": "cas://...", "sha256": "...", "start_ms": 0, "end_ms": 800}
  ]}],
  "context": {"facts": [], "units": {}, "constraints": [], "unknowns": []},
  "target": {"decision": "answer|ask|abstain|tool", "parts": [{"kind": "text", "text": "..."}]},
  "grounding": [{"source_ref": "cas://...", "span_or_time": [0, 800], "claim_id": "c1"}],
  "evidence": {"kind": "human|proof|tool_test|measurement|insufficient", "ref": "..."},
  "tools": {"allowed": [], "trace": []},
  "safety": {"policy_version": "...", "labels": [], "pii": "none|redacted|restricted"},
  "quality": {"review": "synthetic|human|dual_review", "disagreement": null},
  "provenance": {"source": "synthetic", "license": "internal", "consent": "training", "created_by": "generator-v1"}
}
```

Bu örnek şema **normatifleştirilecek taslak**tır. `python3 ai/noema-training/validate_examples.py` komutundaki `validate_examples.py`, Python standard library dışında bağımlılık olmadan JSONL kayıtlarını satır satır işleyip manifest/örneklerin yapısal alanlarını ve temel invariant'ları kontrol eder; `python3 -m unittest discover -s ai/noema-training -p 'test_*.py'` negatif durumları sınar. Bu araç JSON Schema'nın tam validator'ı değildir ve payload hash'inin gerçekten doğru olduğunu, lisans/onamı, proof doğruluğunu veya model kalitesini denetlemez. Bilinmeyen alan `null` veya `unknown` olur; boş alanı tahminle doldurmak yasaktır. `target` görev tipine göre proof, metin, koordinat, zaman aralığı, program ya da `abstain` olabilir. Şema sürümü olmayan kayıt eğitime girmez.

### 21.3 Payload biçimleri ve kayıpsız kaynak politikası

- **Metin/doküman:** özgün byte nesnesi + encoding/MIME + sayfa/offset; parse/OCR ayrı türev. Uzun belge parçalara ayrılır ama kaynak URI/span ve sıralama tutulur.
- **Görüntü:** orijinal dosya referansı, hash, renk/ölçü bilgisi; resize/crop/patch üretimleri ayrı türev ve dönüşüm grafına bağlıdır. Kutular normalize koordinat standardı bildirir.
- **Ses:** codec/original blob, sample rate/channel ve segment zamanları; resample/denoise/ASR ayrı artifact. Transcript insan mı otomatik mi, confidence ve hizasıyla işaretlenir.
- **Video:** kaynak video + frame/audio chunk indeksleri ve zaman damgası; frame sampling kayıplıysa örnekleme politikası yazılır. Gerçek zamanlı stream'de chunk sırası, gecikme ve drop sayısı tutulur.
- **Tablo/tensör/uzamsal:** dtype/shape/unit/coordinate frame, missingness mask, transform ve quantization error metadata. Fiziksel ölçü birimleri kaybolmaz.
- **Tool trace:** çağrı girdisi, tool/version/permission, stdout/stderr veya structured result, yan etki, timeout ve son durum artifact'i; sır/gizli token payload'a alınmaz.

Her türev kaydı `parent_hash`, `transform_id`, `parameters`, `loss_description`, `created_at` tutar. "Kayıpsız ingest" yalnız kaynağın saklanmasıdır; crop/resample/transcript gibi türevler bilgi kaybedebilir ve orijinalin yerini alamaz.

### 21.4 Eğitim hedefleri: örnek türüne göre ayrı loss/feedback

NOEMA tek bir evrensel hedef fonksiyonu iddia etmez. Her örnek bir veya daha fazla eğitim sinyali taşır; sinyalin geçerli olduğu parça ve kanıt sınıfı açık olmalıdır.

| Sinyal | Kullanım | Yasak yanlış yorum |
|---|---|---|
| `verified_trace` | proof/prosedür kuralı türetme; checker adım adım doğrular | trace içindeki açıklama doğru diye varsaymak |
| `supervised_target` | anlam grafı, algı spanı, çıktı biçimi veya görev yönlendirici kalibrasyonu | sentetik etiketleri gerçek dünya kapsama kanıtı saymak |
| `self_supervised_view` | aynı kaynağın iki dönüşümünde tutarlılık/eksik parça tahmini | kendi tahminini ground-truth diye tekrar eğitime sokmak |
| `preference_pair` | insan tercih sırası ve gerekçe; düşük ağırlıklı yönlendirici/üslup seçimi | tercih skorunu doğruluk/proof yerine geçirmek |
| `correction_pair` | hata türü, düzeltme, eski cevaba bağımlı rule retraction | sessiz overwrite veya correction provenansını kaybetmek |
| `tool_outcome` | çağrı seçimi ve etkisinin öğrenilmesi | başarısız/yan etkili eylemi başarı örneği saymak |
| `abstention_label` | yetersiz bilgi, risk, kapsam dışı durumda sorma/çekimserlik | cevap yokluğunu otomatik doğru etiketlemek |
| `safety_adversarial` | saldırı/izin sınırı ve containment testi | yalnız anahtar kelime filtresiyle güvenlik sonucu çıkarmak |

### 21.5 Bölme, sızıntı önleme ve ölçüm

Bölme satır bazında rastgele yapılmaz. Aynı video, aynı kişi/konuşmacı, aynı belge, aynı template seed, aynı kural üretim ailesi veya near-duplicate farklı split'lere dağılmaz. `group_key` ile entity/family bazında split; zaman serisinde geçmiş→gelecek; continuous stream'de cutoff-time ve sonradan görülen entity holdout uygulanır. Test etiketleri üretici/induction motoruna erişmez.

Her yetenek için: benchmark sürümü, kaynak/lisans, örnek sayısı, split algoritması, baseline, compute/data bütçesi, exact/soft metric, güven aralığı, altgrup ve hata örnekleri yayımlanır. Prompt varyantları benchmark'a yeni bağımsız örnek sayılmaz. Üçüncü taraf test setiyle eğitim/retrieval sızıntısı denetlenir.

### 21.6 Modality-agnostic streaming record örneği

Tam sentetik JSONL örneği [`ai/noema-training/universal_examples.jsonl`](../noema-training/universal_examples.jsonl) içinde yer alır: görüntü/kare, ses parçası, tool trace, düzeltme/tercih ve güvenlik kayıtları yalnız URI placeholder kullanır; gerçek medya ya da model yeteneği içermez. Bu dosya parser/schema testi içindir, benchmark değildir. JSONL meta-validasyonuna ek olarak `uri` erişilebilirliği, hash, lisans ve modality-specific payload decoder testleri ayrı çalıştırılmalıdır.

### 21.7 Kapsama kabul kapısı

K31: katalogdaki her task family için schema-valid örnek, en az bir independent validator/simulator, baseline, retention test ve fail-closed davranış hazır olmadan "destekleniyor" işareti verilemez. K32: her modality için bozulma (noise/occlusion/missing chunks/long context/language shift) ve out-of-domain kalibrasyonu ayrı ölçülür. K33: gerçek zamanlı görevlerde doğruluk kadar end-to-end gecikme, chunk drop ve toparlanma ölçülür. Bu kapılar geçilmeden "günümüz modellerinin yapabildiği her şeyi yapar" iddiası yayımlanamaz.

*Belge sürümü: v0.5 — 2026-11-20. Yetenek katalogu ve modality-aware veri şema taslağı eklendi; kapsam/performans henüz ölçülmedi.*

## 22. v0.6 — Eğitim sisteminin baştan sona çalışma reçetesi

**Durum: normatif tasarım taslağı; komutlar ve artifact formatı henüz uygulanmış CLI değildir.** Bu bölüm, eğitim ekibinin aynı girdilerle aynı adımları izleyebilmesi için eğitim turunu sonlu durum makinesi ve dosya sözleşmesi olarak tanımlar. Veri şeması v2 (21. bölüm), event log (20. bölüm) ve ölçüm kapıları (K0–K33) bunun alt katmanlarıdır.

### 22.1 Eğitim turu = immutable run manifest

Her tur `TrainingRunManifest` ile başlar; manifest hash'i run kimliğidir. Manifest değişirse yeni run açılır, eski run yerinde kalır. Zorunlu alanlar:

```json
{
  "schema": "noema.training_run.v1",
  "run_id": "derived-from-manifest-hash",
  "parent_release": "release-id-or-null",
  "data_manifests": ["sha256:..."],
  "split_manifest": "sha256:...",
  "generator_versions": ["name@version"],
  "modules_to_update": ["router", "rule_store", "perception.text.tr.v1"],
  "update_methods": ["eikonal_local", "verified_rule_induction"],
  "seed": 1729,
  "compute_budget": {"cpu_seconds": 3600, "memory_bytes": 1073741824, "energy_joules": null},
  "policy_version": "policy-id",
  "schema_versions": ["noema.example.v2"],
  "gate_set": "gates-id",
  "replay_plan": "sha256:...",
  "artifact_retention": "retention-policy-id"
}
```

Yukarıdaki sayılar yalnız örnektir; donanım/ölçek hedefi değildir. Manifestteki `null` bütçe "sınırsız" demek değildir; o kaynak ölçülmüyor demektir ve raporda açık görünür. Veri lisansı/onam policy kapısı geçmezse hiçbir compute işi başlamaz.

### 22.2 Durum makinesi ve geçiş kuralları

```
CREATED → POLICY_CHECK → DATA_AUDIT → SPLIT_LOCKED → BASELINE_CAPTURED
  → TRAIN_CANDIDATE → STATIC_CHECK → EVAL → REVIEW
  → SHADOW → CANARY → PROMOTED
Hata/limit/izin sorunu: herhangi bir aşama → REJECTED veya PAUSED
Canary regresyon: CANARY → ROLLBACK → parent release
```

- `POLICY_CHECK`: lisans, consent, retention, tenant sınırı, silme kuyruğu; fail-closed.
- `DATA_AUDIT`: schema, hash, duplicate, label conflict, poison/PII, provenance; tüm sayımlar raporlanır.
- `SPLIT_LOCKED`: group/entity/time split hash'lenir; test split yalnız evaluator kimliğiyle açılır.
- `BASELINE_CAPTURED`: parent release bütün eski yetenek panellerinde koşar; baseline yoksa eğitim devam etmez.
- `TRAIN_CANDIDATE`: candidate artefact'ı ayrı namespace'e; online serving değişmez.
- `STATIC_CHECK`: serialization, schema, deterministic replay, dependency/proof, resource cap.
- `EVAL`: yeni görev, retention, regressions, safety, privacy, fairness, robustness, cost.
- `REVIEW`: otomatik kapı + risk seviyesine göre insan imzası.
- `SHADOW/CANARY`: gerçek kullanıcı yanıtını değiştirmeden gölge kıyaslama; sonra yalnız düşük riskli, izinli trafik.
- `PROMOTED`: immutable release package, signature, parent pointer ve rollback yolu kaydedilir.
- `PAUSED`: budget/capacity/data outage; cursor ve event position korunur, aynı run devam edebilir.
- `REJECTED`: sebep kodu zorunlu; aynı manifest değiştirilmeden tekrar çalıştırılırsa aynı deterministic ret alınmalı.

### 22.3 Deterministik eğitim orkestratörü

Her `TRAIN_CANDIDATE` adımında scheduler örnekleri sabit ağırlıklı tek havuza karıştırmaz. Önce task-family quota ve risk sınırı uygular; her minibatch/iş paketini şu tuple ile kaydeder: `(example_id, objective_id, module_id, seed, input_artifact_hash, expected_validator)`. Farklı ailelerin ölçeği ayrı tutulur; tek bir büyük grubun örnek çokluğuyla diğerlerini ezmesi engellenir.

```text
manifest doğrula; parent snapshot'ı read-only aç
for family in manifest.task_families (sabit sıra):
    eligible ← consent+license+split+quality filtresinden geçen kayıtlar
    batches ← deterministic_grouped_batches(eligible, seed, no_cross_split=true)
    for batch in batches:
        route by signal type:
          verified_trace → proof checker → kural adayı (parametre gradient'i yok)
          correction_pair → eski iz/bağımlılık bul → retraction adayı + corrected rule
          supervised perception → ilgili modality adapter'ın yerel update'i
          self_supervised → yalnız izinli invariance/consistency objective
          preference → tercih yönlendirici/çıktı biçimi kalibrasyonu (truth validator değil)
          tool_outcome → simulator'da eylem seçimi ve yan etki sonucu
        state ← apply_to_candidate_only(state, objective, bounded_update)
        log input hash, output hash, counters, saturation/overflow, reject reasons
        if budget reached: checkpoint candidate + cursor; transition PAUSED
finalize candidate snapshot; do not publish or serve it yet
```

Yerel update algoritması her modül manifestinde isim, sabit parametreleri, aralık/saturasyon ve bağımsız doğrulayıcıyla belirtilir. Algoritması belirtilmemiş modül öğrenime kapalıdır. Kanıtla türetilmiş kuralı `weight` gibi karıştırmayız: kural deposu sürümlü sembolik kayıt; SEL parametresi sayısal öğrenilebilir durumdur; retrieval epizodu kaynak kaydıdır. Üçü için update ve rollback farklıdır.

### 22.4 Kural adayının terfi algoritması

1. Aynı normalize edilmiş proof subtrace en az yapılandırılmış eşiği kadar bağımsız epizotta görünür; tek veri kaynağı varyantları bağımsız kanıt sayılmaz.
2. Anti-unification ile aday şema çıkar; tip, önkoşul, postkoşul, değişken kapsamı ve kaynak izleri çıkarılır.
3. Checker, adayın kaynak trace'lerinde birebir doğruluğunu ve side condition'larını yeniden koşar.
4. Adayın gelmediği kural ailesi/seed'den holdout üret; nearest counterexample aramasıyla sınır koşullarını dene.
5. Başarırsa `candidate_rule` olur; bağımsız review ve gate sonrası immutable `rule_version` yayınlanır.
6. Sonradan çürütücü gelirse dependency graph'ta bu kuralı kullanan türevler bulunur; kural `retracted` işaretlenir, etkilenmiş cache/öneri invalid edilir, historical event kalır.

Kural eşiği ve test sayısı task-family config'indedir; global sabit sayı yoktur. Kuralın yalnız eğitim örneklerini ezberlemesi, terfi için yeterli değildir.

### 22.5 Aday release paketinin içeriği

Bir release tek bir checkpoint değil, birlikte sürümlenen paket:

- `release_manifest.json`: parent, kod/build, ABI, modül sürümleri, policy/gate set.
- `module_state/`: küçük sayısal adaptör snapshot'ları ve format sürümü.
- `rules/`: kabul edilmiş kurallar, proof reference, applicability ve retraction metadata.
- `memory_index_manifest`: yalnız kalıcılaştırmaya izinli indeks/epizot alanları; özel kullanıcı belleği release'e gömülmez.
- `data_lineage.json`: veri manifest hash'leri, consent/licence summary, dönüşüm grafı; ham kişisel içerik değil.
- `evaluation/`: tüm skorlar, altgrup kırılımları, failed test IDs, confidence interval ve maliyet.
- `replay/`: seed, deterministic event sequence, cursor ve test fixture refs.
- `signature` + `parent_release`: bütünlüğü ve rollback zincirini doğrula.

Üretim secret'ları, erişim token'ları ve ham kullanıcı içeriği release artifact'ına giremez. Release doğrulanamazsa yüklenmez.

### 22.6 Karar tablosu: kabul, ret, erteleme

| Bulgu | Eylem |
|---|---|
| Hard invariant/proof/sandbox critical fail | anında `REJECTED`; waiver yok |
| Yeni yetenek artıyor, retention toleransı aşılıyor | `REJECTED` veya yeni dar kapsamlı modül/route tasarla; ortalama skorla örtme yok |
| Şema/veri provenance/silme belirsiz | `PAUSED`; policy çözülene kadar aday eğitilmez |
| Sonuç seed'ler arasında oynak | ek seed/CI, varyans raporu; yeterli kanıt yoksa terfi yok |
| Yalnız tercihte üslup değişimi | düşük riskli canary; doğruluk veya güven etiketini değiştirme yetkisi yok |
| Yeni modül o görev ailesi için test edilmemiş | `unsupported_task`; genel sürüm terfisine dahil etme |
| Ingest storage/backup integrity başarısız | akışı durdur ve restore et; sessiz drop/overwrite yok |
| Kapsamlı değerlendirme geçer | risk seviyesine göre onay → shadow → canary → imzalı promotion |

### 22.7 Veri üretme ve insan inceleme kuyruğu

Sentetik üretici görev DSL'sinden seed ile dünya/istek/çözüm/validator fixture üretir; **aynı implementasyonu** hem target hem validator olarak kullanamaz. Checker bağımsız kod yolu olmalı; ayrıca seed/kural ailesi holdout'u ve insanın rastgele seçtiği audit örnekleri vardır. İnsan reviewer arayüzü ham iddia, kaynak span, önerilen etiket, karşı-örnek ve anlaşmazlık seçeneklerini gösterir; sessiz otomatik override yoktur.

Kuyruk önceliği: (1) güvenlik/PII/provenance belirsizliği; (2) üretici-checker uyuşmazlığı; (3) yeni hata sınıfı ve dağılım kayması; (4) sıradan örneklerden deterministik örnekleme. Review kararları `human_review_event` olarak sürümlenir; reviewer kimliği/rolü gizlilik policy'sine uygun tutulur. Reviewer anlaşmazlığı `disputed` statüsüdür; ortalama etikete zorlanmaz.

### 22.8 İlk uygulanabilir dikey dilim (başlangıç planı)

Tüm katalogu birden uygulamak yerine, framework'ün tam yaşam döngüsünü doğrulayan küçük ve ölçülebilir dikey dilim:

1. `reasoning` ve `code` text-only; girdi `noema.example.v2`, küçük LIR programı ve arithmetic/array-bounds kuralları.
2. Exact validator: parser/checker/compiler + unit/property tests; dış tool ve canlı kullanıcı verisi yok.
3. Immutable fixture store + manifest hash + training run event log; deletion path sentetik data ile test edilir.
4. Candidate rule induction (v0.9 TTA sözleşme türetimi) ve optional SEL compatibility probe ayrı sürümlenir; SEL çekirdeğe zorunlu değildir, online update yok.
5. Sabit 3 split: train, rule-family holdout, adversarial/retention. Aynı üretim seed'leri testte görülmez.
6. Run başına gate: schema/provenance → baseline → candidate → proof/tests → retention → deterministic replay → cost report → review.
7. Başarılı package shadow'da çalışır; gerçek serving/promote sonraki ADR ve güvenlik review'ına bağlıdır.

Bu dikey dilim geçmeden ses/görüntü/robotik/çok dillilik hedefleri için "tamamlandı" denmez. Yeni modalite eklendiğinde aynı yaşam döngüsü ve ortak kontratlar korunur; yalnız modül + veri decoder + validator + benchmark eklenir.

### 22.9 Sonuç ve kapsam ifadesi

NOEMA'nın "eksiksiz" iddiası burada **tasarım dokümanında gerekli arayüz, durum geçişi, veri provenance'ı, update algoritması, ölçüm, güvenlik, hata/rollback ve release artefact'larının tanımlanmış olması** anlamına gelir. Bu, her yeteneğin implementasyonu veya frontier seviyesinde performansı anlamına gelmez. Kod, validator ve testler geliştirilip kapılar ölçülmeden "bütün güncel modellerin yapabildiği her şeyi yapar" denmeyecektir.

*Belge sürümü: v0.6 — 2026-11-20. Eğitim run state machine'i, deterministik scheduler, rule promotion, release paketi ve ilk dikey dilim tanımlandı; implementasyon/benchmark sonucu yoktur.*

## 23. v0.7 — Zayıf noktalar için öncelikli düzeltme kararı (harici bağımlılık yok)

Bu bölüm önceki sürümlerdeki riskli/çelişkili ifadeleri düzeltir. İyileştirme **yeni dependency eklemek değildir**: mevcut repo'da olan LIR/runtime ve Zig/C standard library ile başlayacak; OS dosya/işlem arayüzleri dışında paket yöneticisi, model framework'ü, tokenizer kütüphanesi, GPU SDK'sı veya internetten model/data indirme gerektirmez. Her modül önce saf deterministic fonksiyon ve fixture ile kurulmalıdır.

| Öncelik | Zayıf nokta | Düzeltme / yeni varsayılan | Doğrulama |
|---|---|---|---|
| P0 | Faz vektöründe kompleks bind ile normalize edilmemiş demetleme karışmıştı; maliyet ve bellek hatalıydı. | §3.1 artık `(real,imag)` kompleks vektör, açık bind/conjugate/sum/norm ve Q32.32 overflow-error tanımlar. Eski 4 KiB/d=512 kestirimi 8 KiB ham vektör olarak düzeltilmiştir. | Sıfır/identity/inverse/associativity toleransı/overflow fixture; integer reference karşılaştırması. |
| P0 | Derleme + unit test sonucu "kanıt" gibi sunulabilirdi. | §4.3 evidence ladder: formal proof ≠ executable test ≠ empirical support ≠ hypothesis; cevap bu etiketi taşımak zorunda. | Bilerek hatalı programın test geçip theorem etiketi alamaması; checker negative tests. |
| P0 | "Sınırsız", "unutma imkânsız", her adım hatasız ifadeleri gerçek sınırları aşıyordu. | §§4.4, 5.1, 5.5 ve §18 ile bütçe, sınırlı depo, silme ve test kapsamı açıklandı. | K18/K24/K26/K28, restore ve regression drill. |
| P1 | Faz korelasyonu/LSH exact doğruluk için fazla otoriterdi. | Vektör skoru yalnız candidate ranking ve cache key önerir; proof/search state canonical serialized exact key ile karşılaştırılır. Yaklaşık arama kanıt veya dedupe kararı vermez. | Collision adversarial set; exact-key final comparison ve fallback scan. |
| P1 | Dil anlamına geçiş varsayımsaldı; tokenizer yokluğu parser'ın kendiliğinden ortaya çıkması gibi okunabilirdi. | Parser açık, küçük, dil/sürüm kapsamlı grammar+lexicon rule pack'tir; bilinmeyen sözcük/parse ambiguity graf üzerinde korunur; kapsamsız dil `unsupported/ask` olur. | Dil başına grammar coverage, ambiguity recall, unseen morphology tests; başarı genellenmez. |
| P1 | Öğrenme hedefleri tek kayıp/tek puan altında karışabilirdi. | §21.4'te proof, supervised, self-supervised, preference, correction, tool outcome ve abstention ayrı; preference/proxy score doğruluk validator'ını geçersiz kılamaz. | Sinyal türü yanlış kullanımı static schema gate'te red edilir. |
| P1 | Harici checker/retriever ile sistemin "bağımsızlığı" belirsizdi. | İlk vertical slice compiler/proof/test için bu repo'nun yerel `lir` araçlarını; indekste kendi küçük sorted-table/AVL/hash-free baseline'ını kullanır. Hızlandırıcı eklenirse aynı API ve exact fallback zorunlu. | Hermetic run: ağ kapalı; build dependency list ve fixture hashes kayıtlı. |
| P2 | Tek seferde analog + tüm modaliteler + tüm görevler tasarlanması scope patlaması yaratıyordu. | Geliştirme sırası: text/math+LIR → train/event/replay/rollback → local retrieval → tek algı kip adaptörü → diğer kipler. Analog backend, digital reference ve testleri geçmeden bloke. | Her faz bir vertical end-to-end use case ve maliyet raporu ile kapanır. |

### 23.1 İlk sürümde kesin algoritmik daraltma

VGPS'in ilk referans implementasyonu approximate nearest-neighbor/LSH'a **bağlı değildir**. Küçük R için exact canonical rule index kullanılır: rule family/type/arity/guard key'ine göre sıralı tablo, sonra deterministik lineer aday taraması; `budget` ve tie-break lexicographic rule ID. Bu seçim hız rekoru değil, kolay denetlenebilir referanstır. Ölçümde aday sayısı darboğaz çıkarsa daha hızlı indeks yanına eklenir; sonuçlar canonical exact checker'dan geçmeye devam eder.

Benzer biçimde SDM ve holografik M ilk release'in doğruluk kaynağı değildir. İlk bellekte raw episode object + exact content key + sorted inverted index; M yalnız cache, bulunamayan/çakışan sonucu E'den tekrar oku. Böylece muğlak faz korelasyonu kullanıcı bilgisini tek başına silemez veya doğrulayamaz.

### 23.2 Hata ilkeleri

Tüm public modüller sonuç tipini açıkça döndürür: `ok(value)`, `unsupported(reason)`, `ambiguous(alternatives)`, `budget_exhausted(partial_trace)`, `invalid_input(code,span)`, `overflow(operation,range)`, `policy_denied(rule_id)`. Sessiz saturation, default değer uydurma, out-of-domain'i normal sonuç gibi sunma yasaktır. Kısmi arama izi saklanabilir ama tamamlanmış cevap statüsü alamaz. Her hata deterministik kod ve test fixture'a bağlanır.

### 23.3 Bağımlılık politikası ve build hermeticity

- Runtime core: repo'nun ZigLIR native runtime'ı; gerekli OS primitive'leri (file read/write, clock, process isolation) ince adapter arkasında.
- Test referansı: mevcut self-hosted `lir`/Zig compiler ve küçük C standard-library twin yalnız gerekirse; Python sadece mevcut test orchestration için olabilir, production inference dependency değildir.
- Üçüncü taraf model weights, tokenizer, network API, pretrained corpus veya paket kurulumu olmadan core testleri çalışmalıdır.
- Her build `dependency_manifest` yayımlar; boş değilse her öğe gerekçe, sürüm, lisans, hash, alternatif ve kapatılabilir feature ile listelenir. Harici dependency eklemek için kullanıcı kapsamı/ADR gerekir.
- Güncelleme indirimi kapalı; training artifacts offline manifest ile içeri alınır ve hash/lisans doğrulanmadan kullanılmaz.

### 23.4 Bu turun kabul kriteri

Doküman içindeki ters düşen eski mutlak ifadeler yukarıdaki yeni normative kararların gerisinde kalır. Kabul edilen semantik: **exact serialized record authoritative; vector/heuristic yalnız aday bulur; tests are not proofs; no silent lossy update; unsupported or ambiguous tasks fail closed; dependency-free local baseline first.** Bu tasarım değişikliklerinin hiçbiri henüz implementasyon/benchmark sonucu değildir.

*Belge sürümü: v0.7 — 2026-11-20. En riskli matematik, doğrulama, unutma ve dependency varsayımları daraltılıp uygulanabilir no-dependency referans yolu belirlendi.*

## 24. v0.8 — Kapasite ve hız için kaynak-verimli çalışma tasarımı

Bu bölüm "daha hızlı ve daha yüksek kapasite" isteğini compute/memory darboğazı ve eşit bütçeli testlere böler. **Performans sonucu iddia etmez.** Hedef, kolay isteklerde ucuz cevap, zor istekte kontrollü ek compute; aynı anda doğruluk ve güvenlik kapılarını korumaktır.

### 24.1 İki yol: erken kesin cevap veya derin arama

1. **Fast path:** policy check → incremental parse → görev tipi/kanıt standardı → exact key/rule lookup → ucuz bağımsız validator → cevap. Yalnız deterministik, düşük riskli ve evidence threshold'ı baştan sağlayan görevlerde kullanılır (exact arithmetic, bilinen LIR intrinsic, direct lookup). Her yol `fast_path_reason` üretir.
2. **Deep path:** anlam grafında ambiguity varsa, fast-path validator başarısızsa, görev yeni/bileşimsel veya riskliyse VGPS'e geçer. Aday generator + constraint/rule search + counterexample/test runner; her birine ayrı step/time/memory limiti konur.
3. **Anytime response:** bütçe ortasında yalnız `partial/verified_subresult` sunulabilir; final-sounding answer yok. Üst-biliş kontrol deadline yaklaşınca mevcut kanıtı özetler veya çekimser kalır.
4. **Risk override:** yıkıcı araç eylemi, tıbbi/hukuki yüksek risk ve privacy/security durumlarında fast path atlanır; insan/ek onay ve ikinci kontrol şart.

Fast path yalnız exact canonical index ile karar verir; vector cache hit'i tek başına doğruluk/route kararı değildir. Deep path'ın sonlanması için max steps + monotonic deadline + repeated-state detection + candidate cap gerekir. Kullanıcı bütçesi boşsa servis kendi düşük varsayılanını uygular ve bunu yanıtta/telemetride belirtir.

### 24.2 Darboğazı ölçmeden optimizasyon yok

Her request trace bu sayaçları hassas içerik olmadan taşır: parse ns, retrieval ns, candidate count, validator ns, exact MAC/operation count, bytes read/written, cache hit/miss, queue delay, p50/p95/p99 E2E latency, timeout/abstain, answer correctness/evidence level. Aynı benchmark'ta cold-cache ve warm-cache ayrı ölçülür; ölçüm koşulları (CPU, core affinity, optimize mode, dataset hash, concurrency) sonuçla birlikte yazılır.

Önce flame/counter tabanlı darboğaz belirlenir. En ucuz yerel düzeltmeler sırasıyla: (a) incremental parser ve arama için allocation azaltma; (b) sıcak immutable rule index'i compile-time veya release-load'da kurup read-only tutma; (c) cold episodic store'da mmap/range read; (d) batch dot/MAC işlerinde Q32.32 pool'lardan yararlanma; (e) independent task'ları sınırlı worker'lara bölme. Her optimizasyondan önce/sonra aynı output, aynı validator ve en az interleaved benchmark round'ları gerekir. Paralellik deterministik tie-break'i değiştiremez.

### 24.3 Kapasiteyi artırma, her şeyi RAM'e taşımadan

- **Episodic archive:** content-addressed immutable cold object + disk index; aktif working set RAM'de. LRU eviction cache içindir, source archive retention policy'ye tabidir.
- **Rule store:** family/type/signature/guard üzerinde exact sorted index; yüklemede immutable snapshot; rule version dependency graph ile geri izlenebilir.
- **Semantic cache M:** yalnız approximate hint; TTL/eviction olabilir, kaynak E/P kalır. M silinince final correctness değişmemeli.
- **Vektör:** küçük query/routing feature'ı; tüm belgeleri devasa dense vector olarak RAM'de tutmak varsayılan değil. Büyük multimodal payload disk/blob referansında, gerektiğinde pencere/chunk okunur.
- **Kapasite limiti:** byte quota / max open file / max search node / max context span kesin. Kota aşımında `budget_exhausted`/retrieval incomplete; sessiz örnek atma ve eksik aramayı eksiksiz gibi gösterme yok.
- **Sıkıştırma:** kayıpsız codec eklenirse raw hash ile round-trip doğrulanır. Lossy feature/embedding sıkıştırması yalnız cache için ve hata/bit-rate metadata'sıyla; authoritative archive asla bununla ikame edilmez.

### 24.4 Ölçülebilir performans hedeflerinin düzeltilmesi

Bu bölüm K7'nin tek sabit makine/iş-adımı eşiğini workload-family raporlamasıyla **yerine koymayı önerir**; K7 tarihsel tabloda korunur ama K34–K39 yanında tek başına hız kabulü değildir. Her ailede latency, throughput ve kalite/maliyet frontier'ı raporlanır. Tasarım hedefi (ölçülmemiş): exact low-risk math/lookup için aynı makinede request başına p95 <10 ms; 10-step küçük program search için p95 <1 s; native CPU serving'de aynı kalite eşiğinde baseline'dan en az 2× düşük median CPU-time hedefi. Bu hedefler **benchmark'ta ölçülene dek kabul kriteri değil**; platform/iş yükü uygun değilse gerekçeli olarak yeniden belirlenir.

Hız karşılaştırmasında adayın yanıtsız bıraktığı veya yanlış yanıtladığı örnekler latency skoru ile saklanmaz: quality-gated performance sadece baseline ile eşit/üst kalite altkümesinde hesaplanır; ayrıca coverage ve abstention ayrı yayımlanır. Eşit hardware, core limit, dataset, context, cache durumu, concurrency ve max-output bütçesi olmadan “daha hızlı” denmez.

### 24.5 Yeni kapılar

| Kapı | Tanım |
|---|---|
| K34 — fast-path soundness | fast path'a route edilen tüm kayıtlar route gerekçesini ve validator'ı taşır; boundary/adversarial testte false-accept = 0 (test kapsamı içinde) |
| K35 — quality-gated latency | her görev ailesinde kalite/coverage/abstention + p50/p95/p99 + CPU/memory ayrı; aynı koşulda baseline kıyası |
| K36 — scale curve | rule/episode sayısı 10²/10³/10⁴/… artarken recall@k, exactness, RAM/disk, index build ve p95 raporu; sonuç eğri olarak yayımlanır |
| K37 — resource honesty | timeout/node/byte limiti vurulunca explicit partial/abstain; eksiksiz cevap iddiası yok |
| K38 — cache invariance | M açık/kapalı/bozulmuş halde final validator correctness aynı; yalnız hit/latency etkisi ölçülür |
| K39 — concurrency determinism | aynı seed/girdi ile farklı worker scheduling altında canonical answer/evidence aynı; elapsed time değişebilir |

*Belge sürümü: v0.8 — 2026-11-16. Fast/deep inference ayrımı, kapasite yönetimi ve kalite-korumalı performans protokolü eklendi; hedefler ölçülmemiştir.*

## 25. v0.9 — Mevcut paradigma özelliklerini çekirdekten çıkarma

Bu sürüm, "başka sistemlerde kullanılan hiçbir özellik olmasın" talebini **mümkün olan en katı, dürüst yorumla** uygular: bilinen literatürde memory, search, learning, parsing, computation gibi temel kavramların daha önce hiç kullanılmadığını garanti etmek mümkün değildir. Ayrıca fiziksel hesaplama, durum saklama, girdiyi yorumlama ve sonucu üretme tüm çalışan sistemlerde ortak zorunluluklardır. Dolayısıyla global olarak "hiçbir benzeri yok" veya patent yeniliği iddiası yapılmaz. Bunun yerine NOEMA çekirdeğinde §16'da listelenen tanınabilir ailelerin (VSA/HDC, SDM, NLMS/eikonal, LSH, Hopfield/energy minimization, wake-sleep, transformer/Mamba/tokenizer/next-token) **zorunlu altyapı veya merkezî çalışma mekanizması olmasını bırakma**, mekanizmayı aşağıdaki yeni aday işlem modeline taşıma kararı alınır.

### 25.1 Normatif değişiklik: önceki çizimler ne olur?

- §3 H/VSA ve faz vektörü **artık çekirdek semantik değildir**; deneysel, kapatılabilir retrieval/cache backend'i olarak arşivlenir. Eğitim, doğruluk veya görev yönlendirme buna bağımlı olamaz.
- §5 SDM/holografik M, §6 eikonal/SEL, LSH ve §4 enerji inişi **çekirdekten çıkarılır**. SEL geriye uyumluluk/karşılaştırma modülüdür, NOEMA'nın zorunlu öğrenme motoru değildir.
- §4'teki VGPS adı, yalnızca aşağıdaki yeni işletim modeli için kullanılır; klasik program araması/kural rewrite ile eşanlamlı değildir. Kod sentezi araç/özel görev adaptörü olarak kalabilir.
- Önceki §2 katman diyagramı ve §11 faz tablosu tarihsel tasarım sürümüdür; aşağıdaki §25.2 ve §25.7 core tanımıdır. Eski adı taşıyan bir backend ancak etkinleştirme manifesti ve benchmark'ıyla açılır.
- Basit tam sayı işlemleri, disk, graph, hash/checksum, queue, parser ve test yine gerekir. Bunların başka sistemlerde de kullanılması kaçınılmaz genel altyapıdır; özgünlük iddiası sayılmaz.

### 25.2 Yeni merkezî primitive: Taahhüt–Tanık Akışı (TTA)

NOEMA çekirdeği latent dense representation veya token state değil, **açık taahhütler ve onları kapatan tanıklar** üzerinde çalışır. Her istek, birbirine indirgenemeyen `Obligation` kayıtlarına ayrılır:

```
Obligation = {
  id, statement, kind, scope, source_refs[], assumptions[],
  required_witness, risk, status, deadline, parent_ids[]
}
Witness = {
  obligation_id, witness_kind, artifact_ref, verifier_id,
  verifier_result, limits[], counterexamples_checked[], provenance
}
State = {obligations[], witnesses[], conflicts[], resource_ledger}
```

Durum geçişi `advance(State, Event) → State' | TypedFailure`'dır. `Event` yeni kaynak, aday tanık, çelişki veya bütçe değişimidir. Geçiş immutable event üretir; geçmiş state overwrite edilmez. Sistem "en yakın embedding'i" izlemek yerine, **hangi taahhüt kapanmamış, hangi bağımsız tanık onu kapatabilir, hangi çelişki çözülmeli?** sorusunu önceliklendirir.

- `kind=formal`: küçük proof kernel'in kabul ettiği tanıkla kapanır.
- `kind=empirical`: ölçüm kaydı + yöntem + belirsizlik ve mümkünse tekrar ile `supported` olur; kesin teorem olmaz.
- `kind=interpretive`: birden çok yorum ve kaynak spanı tutulur; uzlaşma yoksa unresolved kalır.
- `kind=action`: önkoşul, yetki, yan etki, simüle edilen sonuç ve son durum gözlemi gerekir.
- `kind=normative`: paydaş ve ilke çatışmaları kayıt edilir; sistem tek matematiksel doğruya indirgemez.

Cevap üretimi, yalnız kullanıcının istediği çıktı kapsamındaki taahhütlerin kanıt seviyesiyle etiketlenmiş görünümüdür. TTA'da modelin iç durumu ile cevap metni aynı şey değildir; natural-language generator, taahhüt durumunu değiştiremez.

### 25.3 Yeni seçim ilkesi: kapanmamış yükün kontrollü azaltılması

Her açık obligation'ın kalan iş tahmini `cost_upper_bound`, zarar/risk katsayısı `risk_class` ve kullanıcı önceliği vardır. Scheduler, aday işlerin **beklenen açık-taahhüt azaltımını** kaynak maliyeti ve riskle karşılaştırır; tahminin doğruluk kaynağı olmadığını unutmaz.

```text
while budget > 0 and unresolved is not empty:
    o ← deterministic_select(unresolved, risk, deadline, user_priority)
    actions ← registered_witness_producers(o.kind)
    for action in actions within per-tool budget:
        candidate ← produce_witness(o, action)
        result ← verifier_for(o.kind).check(candidate)
        append Event(candidate, result, cost, provenance)
        if result is valid within declared scope:
            close o at that evidence level
        else if result conflicts:
            add explicit Conflict(obligation, candidate, counterexample)
    if no safe progress: ask/abstain with unresolved set
```

Scheduler tie-break, producer registry ve verifier registry deterministic/sürümlüdür. Kapatma monotoniktir yalnız aynı scope/data version için; kaynak düzeltmesi eski tanığı silmez, invalidation event üretir. Her producer kendisini doğrulayamaz; `producer_id != verifier_id` kapısı uygulanır. Ortak kütüphane/algoritma bağımlılığının checker'ı da aynı hatayı paylaşma riski raporlanır.

### 25.4 Yeni öğrenme primitive'i: Karşıt İzden Sözleşme Derleme

Sürekli öğrenmede yeni örnek doğrudan weight veya kalıcı kural olmaz. Her örnek **iyi iz + en yakın başarısız iz + ayırt edici koşul** üçlüsüne dönüştürülmeye çalışılır:

1. Örnekten `Obligation` ve kaynak sınırları çıkar.
2. Aday çözüm/araç izi bir bağımsız verifier ile değerlendirilir.
3. Başarısız en yakın karşıt örnek üretilir: tek bir koşulu değiştir, eski çözümün neden geçersiz olduğunu bul.
4. İki iz arasındaki fark, tipli `TransitionContract` adayı olarak yazılır: önkoşul, izinli değişkenler, postcondition, counterexample set, geçerli scope.
5. Yeni kontrat; farklı generator seed, dışarıda tutulan görev ailesi, adversarial örnek ve verifier çeşitliliği üzerinden sınanır.
6. Başarırsa sürümlü producer registry'ye terfi eder; bu, parametre öğrenimi değildir. Sürekli model adaptasyonu ayrı, opsiyonel deneydir.
7. Geçersiz kılma örneğinde kontrat `withdrawn` olur; tüm bağlı kararlar dependency graph üzerinden tekrar değerlendirilir.

Böylece ana bilgi büyümesi veri-kümelenmiş latent state değil, **açık kontrat + kapsam + karşıt örnek + verifier** kümesidir. Bu tasarım daha açıklanabilir olabilir; hız, kapsam ve örnek verimliliği avantajı henüz kanıtlanmış değildir.

### 25.5 Özgünlük kapısı (özgünlük iddiası için gerekli kanıt)

Her çekirdek primitive için `novelty_record` oluştur: (a) amaç ve formal tanım; (b) bilinen benzer teknikler ve fark tablosu; (c) tarihli prior-art taraması/kaynaklar; (d) patent/akademik özgünlük uzmanı incelemesi gerekirse; (e) ablation: primitive kapatılınca hangi yetenek kayboluyor; (f) bağımsız implementasyon ve benchmark. Yalnızca yeni isim, yeni notasyon, birden çok eski tekniği yan yana koymak veya kaynak listesine atıf yapmamak yenilik değildir.

Bu repo için bu turda **prior-art taraması yapılmadı**; dolayısıyla TTA ve Karşıt İzden Sözleşme Derleme "özgün icat" değil, NOEMA'nın **özgünlük adayı tasarım önerileri**dir. Tarama olmadan `novel`, `first`, `revolutionary` gibi doğrulanabilir tarihsel iddialar belgeye konamaz. Ürün hedefi "başka sistemlerde hiçbir ortak özellik yok" değil; **mevcut modellerin popüler merkezî mekanizmalarına zorunlu bağımlılığı olmayan, kendi işlemsel sözleşmeleriyle tarif edilen sistem** olmalıdır.

### 25.6 Kabul/terk kapıları

| Kapı | Test | Terk koşulu |
|---|---|---|
| K40 — TTA state correctness | event replay'den aynı state hash'i; invalidation ve scope değişimi fixture'ları | nondeterministic veya eski kanıtı sessizce tutarsa tasarım kabul edilmez |
| K41 — independent witness | producer/verifier ayrımı, ortak hata envanteri, yanlış kabul testleri | verifier aynı üretim yoluna bağımlıysa formal closure yok |
| K42 — contrastive contract | görülmeyen karşıt örnekte sözleşme sınırı doğru ayrılıyor mu | üretici/validator aynı seed/logic sızıntısıyla geçiyorsa veri seti geçersiz |
| K43 — no-legacy-core ablation | VSA/SDM/SEL/LSH/eikonal kapalıyken dikey dilim çalışıyor mu | çalışmıyorsa bu bileşenler hâlâ core dependency'dir; iddia ve mimari düzeltilir |
| K44 — originality review | teknik fark, prior art, ablation ve bağımsız review | tarama yok/örtüşme büyükse özgünlük iddiası yapılmaz; tasarım yeniden çalışılır |
| K45 — quality/cost | aynı görev, kalite ve kaynak bütçesinde baseline karşılaştırması | daha iyi değilse hızlı/zeki/ucuz üstünlüğü iddiası yok; en iyi olduğu alana daraltılır |

### 25.7 Yeni geliştirme sırası (önce özgünlük adayı, sonra uzman modüller)

1. **TTA formal data model:** obligation/witness/conflict tipi, event replay, evidence-level invariants; yalnız stdlib/LIR.
2. **En küçük doğrulayıcı:** exact integer ve küçük LIR programlarında ayrı verifier executable; producer/verifier bağımsızlığına test.
3. **Küçük sentetik task DSL:** iyi iz/karşıt iz çiftleri; group split ve generator-seed holdout.
4. **Karşıt İzden Sözleşme Derleme:** typed transition contract çıkarımı, counterexample tabanı, retraction/dependency propagation.
5. **Fast/deep scheduler:** TTA yükünü seçme, sabit budget, deterministic event log; §24 metrikleri.
6. **Tek vertical slice release:** LIR kod düzeltme veya exact matematikte train→candidate→evaluate→rollback uçtan uca.
7. **Uzman modüller:** her yeni dil/algı/araç capability'si, kendi decoder, validator, dataset lineage ve K31+ kapılarıyla ayrı eklenti.
8. **Yenilik denetimi:** çekirdek stabil olduktan sonra prior-art review; sonuç gelene dek isimlendirme "NOEMA önerisi", "dünya tarihinde ilk" değil.

*Belge sürümü: v0.9 — 2026-11-16. Bilinen temsil/öğrenme/arama aileleri zorunlu core'dan çıkarılıp TTA özgünlük adayı olarak önerildi; prior-art ve performans sonucu yoktur.*

## 26. v1.0 — Minimum maliyetli öğrenme ve kusur-kapatma politikası

Hiçbir gerçek AI mimarisinde "hiç zayıflık yok" garantisi verilemez: eksik gereksinim, yeni saldırı, donanım arızası, dağılım kayması ve insan etiket hatası her zaman mümkün. Hedef, bilinen kusurları önlemek, kalan riski görünür tutmak ve etkisini sınırlamaktır. Bu bölüm maliyeti düşürmeyi *önce öğrenme kapsamını küçülterek*, sonra ölçülen darboğazı optimize ederek ele alır; performans sonucu veya maliyet üstünlüğü iddiası değildir.

### 26.1 Her yeni örnekte en ucuz geçerli öğrenme yolu

Gelen örnek için aşağıdaki sıra uygulanır; pahalı aşamaya gerekçe olmadan çıkılmaz:

| Seviye | Eylem | Ne zaman seçilir | Tahmini maliyet sınıfı |
|---|---|---|---|
| U0 — Arşivle | provenanslı raw event + index kaydı; model değişikliği yok | örnek yeni ama genelleme/etiket güveni yok | O(kayıt byte + index update) |
| U1 — Epizot ekle | exact source/evidence bağlantılı yeni çözüm olayı | görev çözüldü ve validator sonucu biliniyor; yeni genel kural kanıtlanmadı | O(trace uzunluğu) |
| U2 — Kural adayı | yalnız ilgili task family'de iyi iz/karşıt iz çiftinden sözleşme üret | farklı seed ve verifier holdout hazır | O(yerel iz + ilgili karşıt örnekler) |
| U3 — Yerel modül kalibrasyonu | yalnız route edilen küçük adapter/router parametrelerini izole snapshot'ta güncelle | kural/epizot yetmiyor; drift ölçülmüş; değerlendirme seti var | O(adapter parametreleri × seçilmiş minibatch) |
| U4 — Görev ailesi yeniden eğitimi | ilgili aileye ait modül ve testlerini yeniden üret | şema/grammar/öğretim kapsamı değişmiş veya yerel update başarısız | O(ilgili family verisi + tüm family gate'leri) |
| U5 — Tam release rebuild | tüm bağımlı modül ve kontratları yeniden kur | core ABI/proof/policy/event formatı değişikliği | O(release manifestindeki tam kapsam) |

U0/U1 varsayılandır: tek örnek tüm parametreleri güncellemez. U3/U4'e geçiş için drift veya kapsama açığına dair kayıtlı sebep gerekir. U5 normal sürekli öğrenme değildir. Kendi ürettiği unlabeled tahmin, yeni etiket gibi depolanmaz. Bu politika hesap maliyetini düşürmeyi hedefler; U2–U4 doğrulama yükünü ortadan kaldırmaz.

### 26.2 Bütçe yöneticisi ve erken durdurma

Her run üç ayrı bütçe kullanır: `compute_budget`, `review_budget`, `storage_budget`. Scheduler her alt iş başlamadan önce worst-case tahmin ve iptal noktası bildirir. Aşağıdaki koşullarda yeni compute başlatılmaz: kalan bütçe sonucu ve zorunlu validator'ı tamamlamaya yetmiyorsa; izin/provenans incomplete ise; test/retention setleri hazır değilse. Deadline geldiğinde checkpoint + cursor yazılır; bütçe aşımı sessiz truncate değil `PAUSED` veya `budget_exhausted` sonucudur.

İşlem önceliği: (1) hard safety/proof regression; (2) yeni örneğin hedeflenen family'ye katkısı; (3) retention; (4) geniş benchmark ve ikincil optimization. Kısa ve ucuz exact validator erken başarısızsa pahalı test ve training update iptal edilir. Adayın ara skorları promotion için kullanılamaz; promotion tüm zorunlu kapıları gerektirir.

### 26.3 Maliyet ölçümü: gerçek toplam, yalnız accelerator süresi değil

Her run başına aşağıdakiler kaydedilir: end-to-end wall time, CPU-core seconds, peak RSS, byte read/write, candidate/rejected count, validator/test zamanı, data generation zamanı, insan inceleme dakikası, enerji (sensör varsa; yoksa `unmeasured`), artifact saklama ve rollback maliyeti. Sonuçlar **başarılı kabul edilen capability update başına** hesaplanır; başarısız deneme ve evaluation giderleri paydadan çıkarılmaz.

K29/K21 raporu şu karşılaştırmayı verir: aynı görev, aynı quality/coverage/abstention eşiği, aynı makine ve source data izinlerinde (a) event/rule-only U0–U2, (b) local adapter U3, (c) aile full retrain U4. Aynı testte hangi aşamanın maliyeti ne kadar olduğu ayrılır. En ucuz yol başarı eşiğini tutmazsa ucuz diye seçilmez.

### 26.4 Kusur-kapatma (FMEA-lite) ve karantina

Her release öncesi hata türleri `severity × likelihood × detectability` ile sıralanır; yüksek risk için owner, detection test, containment, recovery ve residual risk zorunludur. İlk minimum risk listesi:

| Hata türü | Önleyici kontrol | Tespit | Containment / recovery | Kalan risk |
|---|---|---|---|---|
| parser yanlış anlamı kesinleştirir | ambiguity korunur; dil kapsamı pinli | paraphrase/ambiguity test | ask/unsupported; grammar version rollback | kapsanmamış dil/ifade |
| yanlış verifier kabul eder | producer-verifier ayrımı; small checker | mutation/negative tests, independent proof fixtures | formal label'i kaldır; dependent proof invalidate | ortak spec hatası |
| data poisoning / instruction injection | source trust, quarantine, no direct tool privilege | adversarial dataset + provenance anomaly | source lineage karantina, derived contracts retract | bilinmeyen saldırı |
| forgetting / rule collision | snapshot, family-specific retention, scoped contracts | update sonrası test + collision fixtures | rollback, candidate disable | test edilmemiş görev kaybı |
| silent archive loss/corruption | immutable content hash, backup, restore drill | periodic integrity scan | stop ingest, restore ve event reconciliation | ortak arıza/fiziksel afet |
| privacy leakage | minimum collection, tenant scope, delete propagation | canary secrets, access audit | stop release, revoke access, incident process | model inversion/backup retention ihtimali |
| budget exhaustion/DoS | per-task quotas, deadline, queue backpressure | saturation/latency metrics | reject/pause, no unsafe partial action | hizmet erişilebilirliği |
| tool side effect | least privilege, simulator, explicit consent | postcondition + audit trace | circuit breaker, human escalation, rollback if possible | irreversibility |
| dependency/supply-chain | dependency manifest, pinned hash, offline build | hermetic repeat build | artifact quarantine, prior signed release | compiler/OS root trust |
| fairness/calibration drift | disaggregated evaluation, threshold policy | subgroup/shift gates | capability scope down, abstain, human review | ölçülmeyen subgroup |

Severity tablosu sıfır risk kanıtı değildir; risk yüksekliği açıklanamazsa release bloke edilir. Olay sonrası `incident_event` privacy-safe audit log'a yazılır, model/rule/data lineage ile bağlı rollback planı uygulanır.

### 26.5 Hızlı fakat güvenli continuous training için SLO taslağı

- **Örnek kabul SLO:** valid synthetic verified-trace event'inin U0 kaydı tam manifestli run'da ölçülür; hedef p95 <5 ms (disk ve makine profili belirtilmeden genel iddia değildir).
- **Kural adayı SLO:** aynı ailede ≤100 rule candidate için U2 build+checker süresi ölçülür; sabit sayı hedefi ancak ilk LIR dikey dilim benchmark'ından sonra belirlenir.
- **Release SLO:** eğitim süresi değil, yeni kabiliyet başına tüm gate maliyeti K29 ile ölçülür. Zorunlu retention/safety gate kısaltılarak "hız" sağlanamaz.
- **Fast ingestion:** queue batching ve immutable append kullanabilir; batch içi her örnek ayrı id/provenance taşır. Bir örneğin hatası batch'in tamamını sessizce düşürmez; failure kayıtları tutulur.

Bu SLO'lar başlangıç ölçüm planıdır; p95 hedefleri donanım bağımlıdır ve geçerli kapıya dönüşmesi için ölçüm protokolü, fixture hash'i ve birkaç tekrar gerekir.

### 26.6 Sonuç: kusur yok iddiası yerine kanıt dosyası

Her sürümün yanında `assurance_case` bulunur: sistem sınırı, varsayımlar, threat model, evidence level, passed/failed gates, test coverage, residual risks, known unsupported tasks ve rollback sürümü. `all weaknesses eliminated` / `risk-free` status değeri şemada yoktur. Güvenilirlik artışı, kusuru gizlememek, erken saptamak, etkisini daraltmak ve tekrarını testle önlemek üzerinden değerlendirilir.

*Belge sürümü: v1.0 — 2026-11-16. Katmanlı düşük-maliyet update politikası ve kusur containment/assurance süreci eklendi; maliyet/hız hedefleri ölçülmemiştir.*

## 27. v1.1 — Çıktı kipleri, akış ve dış sistem sınırları

Bu bölüm, önceki kapsam kataloğunda **girdi** tarafı daha iyi tanımlanmışken üretim/streaming/connector tarafında açık kalan sözleşmeleri tamamlar. Her output adapter ayrı capability olarak kaydedilir; formatı kabul etmek o formatta üretim yeteneği olduğu anlamına gelmez.

### 27.1 Ortak output artifact protokolü

Her üretilen çıktı, metin dışı olsa da `OutputArtifact` olarak kaydedilir:

```text
OutputArtifact = {
  artifact_id, kind, media_type, payload_ref, payload_hash,
  dimensions_or_duration, encoding, units_or_color_space,
  source_obligations[], evidence_level, generator_version,
  safety_labels[], user_rights, created_at, expires_at
}
```

`kind` örnekleri: `text`, `structured_data`, `code`, `image`, `audio`, `video`, `spatial_action`. Metin cevabı da iddialarını `Obligation`/`EvidenceRecord`'e bağlar. İkili payload JSONL'de inline edilmez; content-addressed artifact store'a yazılır. Streaming'de artifact `partial` → `final` event'leriyle ilerler; final hash ve chunk-index listesi dışında önceki chunk'lar sessizce değiştirilemez. Kullanıcı iptal ederse `cancelled` terminal durumu verilir ve kalan üretim durur.

### 27.2 Üretim capability'leri (yalnız adapter açıkça kurulduğunda)

| Capability | Girdi | Çıktı sözleşmesi | Kontrol/başarısızlık |
|---|---|---|---|
| Metin/structured | TTA sonucu, şema, dil ve üslup sınırı | grounded text veya JSON/CSV; her factual claim obligation ID'ye bağlanabilir | JSON schema check, unsupported claim red; dil kapsamsa üret, değilse bildir |
| Kod | kontrat, izinli çalışma alanı, test | source artifact + build/test report + diff | compile/test sandbox; test geçişi formal proof değildir |
| SVG/vektör görsel | sahne grafı/şekil talimatı | SVG artifact, viewBox, style/rights, alt text | XML/SVG sanitizer, geometry bounds; yalnız vektör çizim, raster diffusion değil |
| Raster görsel | prompt/scene graph + capability manifest | image blob, dimensions, color space, seed/lineage, safety labels | bu adapter yoksa `unsupported_generation`; salt metin açıklaması görsel diye sunulmaz |
| Ses/speech | transcript veya phonetic/score intent + voice/rights profile | audio chunks, sample rate/codec, alignment, transcript ref, voice consent | speech generator ayrı modül; model/voice yoksa unsupported; çıktı ses dosyası olarak doğrulanır |
| Müzik | yapı/tempo/ölçü/gerekli haklar | zamanlanmış note/event score veya audio artifact | sembolik skor ve waveform farklı capability; telif taklidi/voice cloning policy gate |
| Video | storyboard/scene events + süre/fps | frame/audio chunk dizisi, timestamps, codec metadata | frame continuity, audio sync, duration/size limit; adapter bulunmazsa video üretildi denmez |
| Spatial/action | doğrulanmış plan + robot/API capability | typed action proposal, coordinate frame, expiry, safety envelope | simülasyon/insan onayı + postcondition; doğrudan aktüatör komutu varsayılan değil |

Mevcut dependency-free ilk sürümün gerçekçi output'u metin, JSON ve LIR kodudur; SVG basit standard-library serializer ile yapılabilir. Raster/audio/video generation için harici model, kütüphane veya donanım gerekecekse bunlar **opsiyonel adapter** ve ayrı lisans/güvenlik/ölçüm kapısıdır; core'a gizli bağımlılık eklenmez.

### 27.3 Oturum, uzun bağlam ve streaming protokolü

- `Session` global model state değildir; tenant/user ACL'li `session_id`, version, expiration, memory refs, active tasks ve cancellation token taşır.
- Her turn append-only event; context window dolunca özet, raw turn'ün yerine geçmez. Özet `derived_artifact` olarak kaynak spanlara bağlanır; cevap için gerekli veri kaybolmuş olabilir diye işaretlenir.
- Uzun belge RAG/parse aşamasında sayfa/parça refs'e ayrılır; retrieval completeness listesi tutulur. Kısmi retrieval varsa yanıtta coverage bildir veya çekimser kal.
- Streaming event türleri: `accepted`, `progress`, `partial_result`, `tool_request`, `evidence_update`, `final`, `error`, `cancelled`. Her event `seq_no`, `request_id`, `deadline`, `schema_version` taşır; duplicate/reordered event idempotent şekilde yönetilir.
- Kullanıcı feedback'i `response_id` ve obligation refs'e bağlanır; otomatik online update olmaz. İptal edilmiş/abandoned üretim eğitim etiketi sayılmaz.
- Concurrency/queue doluluğunda backpressure; tenant fairness için per-user quotas. Bir tenant'ın uzun task'ı başka tenant'ın hard latency budget'ını aç bırakmamalı.

### 27.4 Connector / plugin güven sınırı

Harici servisler core değil, `ConnectorManifest` ile tanımlı adapter'lardır: `connector_id/version`, input-output schema, network hosts, scopes/permissions, timeout/retry/rate limit, idempotency, data retention, secrets handle, side-effect class, evidence mapping. İzin verilmemiş host/scope çağrısı deny edilir. Connector sonucu `untrusted_observation` olarak TTA'ya girer; tool cevabı kendi kendini kanıtlamaz.

- Core deterministic testlerinde network kapalı; connector fixture/local simulator kullanılır.
- Gerçek connector açılışında kullanıcı/tenant consent, secret vault interface ve audit policy gerekir; secret'lar prompt, logs, training data veya release artifact'ına girmez.
- Read-only ve side-effectful adapter ayrı capability. Write/delete/payment/physical action için preview → explicit confirmation → execute → postcondition readback.
- Timeout/retry duplicate write oluşturabilecekse idempotency key zorunlu; belirsiz sonuç `unknown_side_effect` olarak insan incelemesine gider.

### 27.5 Output-data örnekleri

Yeni şema örnekleri [`ai/noema-training/output_examples.jsonl`](../noema-training/output_examples.jsonl) içindedir. Kayıtlar text/JSON, kod testi ve dependency-free SVG output sözleşmesini gösterir; gerçek raster image/audio/video üretim yeteneği iddia etmez. Diğer modality örneklerinde gerçek media payload yerine yalnız schema/unsupported kararına izin verilir.

### 27.6 Yeni kapılar

| Kapı | Doğrulama |
|---|---|
| K46 — artifact integrity | partial/final chunk manifest, payload hash ve cancellation state round-trip |
| K47 — claim grounding | final text içindeki factual claim'lerin obligation/source eşlemesi; eşleşmeyen iddia unsupported |
| K48 — stream protocol | duplicate/reorder/cancel/backpressure fault injection; final artifact tutarlılığı |
| K49 — connector safety | denied host/scope, prompt injection, timeout/retry/idempotency ve unknown side effect testleri |
| K50 — generation fidelity | yalnız implement edilmiş adapter için format, alignment, safety ve human quality değerlendirmesi; unsupported adapter'da pass yok |
| K51 — long-context completeness | sabit belge büyüklüğü ve retrieval cutoff'larında coverage raporu; eksik parça ile kesin cevap vermeme |

*Belge sürümü: v1.1 — 2026-11-16. Output artefact, session/stream ve connector protokolleri eklendi; generation adapter'ları ve kalite ölçümleri uygulanmış değildir.*

## 28. v1.2 — Doğal dil, düşünme, kod ve problem çözme kalite sözleşmesi

İstenen kalite, tek bir "zekâ" puanı değildir. Dil anlama, metin yazma, muhakeme, kod ve problem çözme ayrı capability'lerdir; ortak bağlam/provenans ve TTA sonucu paylaşırlar, ama bir alandaki başarı diğerine aktarılmış sayılmaz. Bu tasarım bir **yetkinlik şartnamesidir**, modelin bugün bu kaliteye ulaştığı iddiası değildir.

### 28.1 Beş yetenek motoru ve aralarındaki sözleşme

| Motor | Girdi → ara temsil | Çıktı | Doğru kabul şartı |
|---|---|---|---|
| NLU: dil anlama | Unicode text + conversation → sürümlü grammar/lexicon parse forest, discourse referent, speech act, ambiguity set, source span | `MeaningRecord` | altın anlam grafı/span, paraphrase ve ambiguity testleri; bilinmeyen sözcük tahminle kesinleştirilmez |
| NLG: metin yazma | intent + audience/style constraints + closed obligations + evidence refs | discourse plan → paragraf/çıktı | iddia eklememe, talimat/stil uyumu, kaynaklılık, tutarlılık, okunabilirlik; akıcılık doğruluk değildir |
| Reasoning: düşünme | anlam grafı + assumptions + obligation dependencies | tanık/çelişki/kısmi sonuç | formal claim kernel ile; ampirik claim ölçümle; unresolved claim hipotez |
| Code: kodlama | typed specification + pre/postconditions + allowed LIR API | source artifact + test trace + diff | compile/check + property/adversarial tests; test=proof değildir |
| Problem solving | goal, constraints, resources, available tools | çözüm planı veya soru/abstain | state transition simulator/constraint checker; ara şart ve kaynak bütçesi geçmeli |

**Ortak arayüz:** NLU, iddiaların kendisi değil alternatif yorumlar üretir. TTA obligation açar ve `source_span` ile ilişkilendirir. Problem solver/kod motoru candidate artifact üretir. Bağımsız checker evidence level'ı verir. NLG yalnız kabul edilmiş/kapsamı belirtilmiş obligation'ları kullanıcıya uygun dilde ifade eder; yeni olgusal iddia eklerse yeni obligation açılması gerekir.

### 28.2 Tokenizer kullanmadan doğal dil öğrenmenin gerçek sınırı

Token ID/BPE kullanmamak kendi başına daha yüksek kalite sağlamaz. Karakter akışından dil yeteneği için her dilde sürümlü morfoloji/sözdizimi kuralları, sözlük/lemma, bileşik sözcük, yazım varyantı, pragmatik işlev, discourse/coreference ve alana özgü terim yönetimi gerekir. NOEMA şu kademeyi uygular:

1. Unicode code point stream'i koru; grapheme/word/morpheme span'ları ayrı annotation'dır, canonical source overwrite edilmez.
2. Dil algısı emin değilse birden çok dil/parser hipotezi tut.
3. Lexicon/grammar coverage manifest'te sürüm ve lisansla kayıtlıdır. Unknown span `UNK_SPAN` gibi görünür düğüm olur; gizlice başka sözcüğe eşlenmez.
4. Parse forest alternatif anlamları ve olasılık yerine calibration band/rank taşır; bağlam gerektiren seçimde soru sorabilir.
5. Türkçe için eklemeli morfoloji, ses uyumu, düşen özne, iyelik/gönderim, serbest sözdizimi ve yazım hatası ayrı testlenir; İngilizceye göre ölçülen skor Türkçe başarısı sayılmaz.
6. NLG önce `DiscoursePlan` (claim order, rhetorical relation, audience, style, citations) kurar, sonra grammar realization yapar; plan dışı claim detector + source coverage check final kontrol olur.

Bu yaklaşım geniş dil akıcılığı için emek ve veri ister. Küçük sentetik corpus, dünya bilgisi ve doğal çeşitlilik eksikliğini kapatmaz. Geniş alan kalitesi isteniyorsa izin/lisanslı insan yazımı veri, çok dilli reviewer ve gerçek paraphrase/correction setleri gerekecektir; bunlar olmadan kaliteyi iddia etmek yasaktır.

### 28.3 Eğitim müfredatı, kalite sinyalleri ve kaçınılacak kısayollar

- **NLU:** minimal pairs (tek ek/olumsuzluk/zaman değişimi), paraphrase cluster, ellipsis/coreference, ambiguity, discourse turn, typo/noise, domain shift; her cluster aynı split'e gider.
- **NLG:** aynı meaning graph için farklı audience/register uzunlukları; faithful summary vs unsupported embellishment; structured output; editing/copy-edit; citation completeness. Tercih verisi truth labels yerine geçmez.
- **Reasoning:** hidden-rule tasks, multi-step proof, contradiction/insufficient-information, unit/constraint changes, counterexample; answer trace verifier'dan bağımsız.
- **Code:** specification, starter code, failing tests, bug report, patch, regression suite, security constraints; test generation ile test-solving setleri ayrılır.
- **Problem solving:** plan length/branching artan environment, resource limit, impossible-goal, recovery from failed action; simulator result ile natural-language rationalization ayrılır.
- **Sürekli öğrenme:** yeni kural family'leri zamanla gelir; test cutoff ve prior-family retention sabitlenir. Kendi cevabını unlabeled ground truth olarak üretip eğitme (self-confirmation loop) yasaktır.

Maliyet azaltma: önce mevcut grammar/contract/verifier ile çöz; yalnız kapsama hatası gösterilmiş family'ye yeni veriyi yönlendir; yakın kopyaları train'e çoğaltmak yerine cluster-level ölç; sentetik datayı human-authored holdout ile kalibre et; NLG üslup değişimini core reasoning modülünden ayır. Hız uğruna ret/coverage veya evidence standardını düşürmek kalite iyileştirmesi değildir.

### 28.4 Capability-eval kayıt biçimi

`noema.capability_eval.v1` kayıtları training JSONL'den ayrı tutulur. Her kayıt `task`, dil, input, izinli context, reference/criterion, checker/rubric, risk ve leakage group taşır. Subjective writing için tek altın yanıt değil blinded rubric ve en az iki reviewer; kod/matematikte machine-checkable criterion; parser'da graph/span metric kullanılır. Mini fixture dosyası [`ai/noema-training/capability_eval.example.jsonl`](../noema-training/capability_eval.example.jsonl) örnek şemayı gösterir, **benchmark değildir**; dependency-free local validator bu dosyanın yapısını da denetler.

### 28.5 Karşılaştırma ve kabul protokolü

Transformer/tokenizer tabanlı ve diğer uygun baseline'larla karşılaştırma yapılırken aynı public/private data permission, task prompt, tool access, context limit, decoding/attempt sayısı, hardware/CPU/GPU, wall/energy budget ve scoring rubric sağlanır. Baseline'lar tarih/sürüm ve exact config ile sabitlenir; model güncellenirse yeni rapor olur. Aşağıdakiler ayrı raporlanır, tek composite score ile örtülmez:

- NLU: meaning-graph F1/exact, source-span precision/recall, ambiguity calibration, language-by-language.
- NLG: blinded human rubric (factuality, instruction adherence, coherence, style), claim support rate, edit distance değil semantic adequacy.
- Reasoning: answer accuracy + valid witness rate + false-certification rate + abstention/coverage.
- Code: pass@1/pass@k, hidden-test success, security/property failures, time-to-correct.
- Problem solving: goal success, path/resource cost, safety violations, recovery, partial/abstain calibration.
- Cost/speed: end-to-end p50/p95, compute/energy, human annotation and inference/training cost per **quality-gated accepted task**.

Geniş iddia için önceden kaydedilmiş benchmark suite'inde bütün capability family'lerin kalite alt sınırı geçmesi ve hiçbir critical safety/regression metriğinin bozulmaması gerekir. Bir alanda fail varsa sonuç o alanla sınırlanır. "Daha yüksek kalite" ancak bu protokolle bağımsız tekrarlanınca söylenebilir.

### 28.6 Yeni kapılar

| Kapı | Ölçüm |
|---|---|
| K52 — language graph | dil başına ambiguity-aware graph F1 + source span precision/recall; unknown morphology zorunlu test |
| K53 — grounded writing | blinded reviewer rubric + her factual claim için source support; unsupported claim rate ayrı |
| K54 — reasoning | exact/independent witness validity, false certification, task coverage ve abstention birlikte |
| K55 — coding | hidden test pass@1, security property failure ve time-to-correct; public tests tek başına yetmez |
| K56 — problem solving | farklı plan derinliği/branching'de simulator goal rate, resources, unsafe-action ve recovery |
| K57 — cross-lingual parity | her dilin ayrı score'u, calibration ve human review; yüksek resource dili diğerlerini temsil etmez |
| K58 — human preference separation | preference improvement ile correctness/factuality regression ayrı; correctness düşerse tercih gain promotion sağlamaz |

*Belge sürümü: v1.2 — 2026-11-16. NLU/NLG/düşünme/kod/problem çözme motorları, tokenizer'sız dil sınırı, eğitim müfredatı ve kalite kıyas protokolü eklendi; model performansı ölçülmedi.*

## 29. v1.3 — Kanonik sözleşmeler ve uçtan uca kimlik uyumu

Bu bölüm diğer tüm bölümler arasında normatif uyumluluk katmanıdır. Çelişki halinde: (1) §29 kimlik/şema bağlantıları, (2) §25 core ve evidence semantics, (3) ilgili güncel capability bölümü, (4) v0.x tarihsel çizim/ölçüm hedefi sırası geçerlidir. Bölüm başlığı eski sürüm taşıyorsa içindeki fikir uygulanmadan önce bu sıra ile değerlendirilir.

### 29.1 Tek kimlik grafı

| Nesne | ID | Üst/bağlantı | Yetkili yaşam döngüsü |
|---|---|---|---|
| İstek | `request_id` | client/session/tenant + idempotency key | API kabulünden terminal output/cancel |
| Görev | `task_id` | `request_id`, task-family/capability | scheduler'ın bounded task planı |
| Taahhüt | `obligation_id` | `task_id`, parent obligations, source refs | open → candidate → closed-at-level / unresolved / invalidated |
| Tanık/kanıt | `evidence_id` | `obligation_id`, producer/verifier, artifact/source | proposed → checked → valid/invalid/limited |
| Araç çağrısı | `tool_call_id` | `task_id` + obligation, permission scope | requested → authorized/denied → executed/failed/unknown-side-effect |
| Artifact | `artifact_id` | `request_id`, obligation refs, evidence refs | partial → final / failed / cancelled / expired |
| Örnek | `example_id` | dataset/split/group key, schema/provenance | staged → audited → eligible/quarantined/retracted |
| Eğitim turu | `run_id` | immutable manifest, data manifest, parent release | state machine §22.2 |
| Release | `release_id` | run + signed manifest + parent release | candidate → shadow → canary → promoted/rolled-back |

ID'ler sürüm kapsamındaki immutable identifier'dır; içerik hash'i integrity adresidir, tek başına auth/privacy/semantics değildir. Hangi object store'da bulunduğu `payload_ref` ile gösterilir; storage URI, nesnenin anlamı yerine geçmez.

### 29.2 EvidenceLevel tek enumerasyonu

Tüm `Obligation`, `Witness`, `OutputArtifact`, evaluation ve JSONL alanları aynı enum kullanır:

- `formal_proof`: küçük trusted kernel'in açık kapsamı içinde doğruladığı matematiksel/biçimsel sonuç.
- `executed_test`: belirli build/input/fixture üzerinde çalıştırılıp testi geçen artifact; genel correctness theorem değildir.
- `empirical_support`: belirtilen veri/yöntem/ölçüm ve uncertainty ile desteklenen iddia; causal/general guarantee değildir.
- `interpretation`: kaynak spanlarından çıkarılan fakat ambiguity kalan anlam adayı.
- `hypothesis`: henüz independent check geçmemiş öneri.
- `unsupported`: kapsam/kanıt/adapter yok; kesin iddia veya artifact üretilmez.

Terminal obligation status tek başına evidence level değildir. `closed` yalnız bağlı evidence record'u ve valid checker sonucu varsa kullanılabilir. Kaynak veya scope değişince closure invalidation event ile yeniden açılır. Cevap seviyesini en zayıf iddia belirler; yüksek güvenli bir matematik satırı yanındaki hipotezi `formal_proof` yapmaz.

### 29.3 Girdi→çıktı kanıt zinciri

Kanonik zincir:

```
TaskContract(request_id, permissions, budget, input_refs)
  → MeaningRecord(task_id, alternatives, source_spans, unknowns)
  → Obligation(task_id, statement, assumptions, scope)
  → Witness(evidence_id, obligation_id, producer_id, artifact/source refs)
  → VerifierResult(evidence_id, verifier_id, result, limits)
  → OutputArtifact(request_id, source_obligation_ids, source_evidence_ids)
  → terminal API response(status, capability, evidence summary, budget used)
```

Zorunlu invariant'lar:

1. Her obligation request/task içinde var olmalı; task dışı orphan obligation release edilmez.
2. Her evidence bir var olan obligation'a bağlanır; evidence `valid` olmadan obligation closed olamaz.
3. Her factual OutputArtifact en az bir obligation ve aynı obligation'ların valid evidence ref'lerini taşır; ref'i olmayan claim render edilirse post-render scanner yeni obligation açmalı veya claim'i çıkarmalıdır.
4. Her tool result `untrusted_observation` olarak evidence adayıdır; izin ve verifier olmadan final fact değildir.
5. `unsupported` kararında ilgili modality artifact listesi boş olmalıdır; text açıklaması desteklenmeyen medya üretimi diye sunulamaz.
6. Cancel/error/budget-exhausted terminal cevapta partial artifact `final` olarak işaretlenemez; tamamlanmış coverage listesi verilmeden bütün görevin çözüldüğü söylenemez.
7. Split/tenant sınırındaki source ref başka split/tenant içeriğini çözemez; permission denetimi retrieval ve renderer'ın ikisinde de yapılır.

### 29.4 Şema sürümleri ve dönüşüm

Her kayıt tam bir `schema` string'i ve major version taşır. Major version değişikliği yeni parser/validator + migration test + archived old fixture gerektirir; unknown major fail-closed. Minor additive field yalnız optional ise uyumlu sayılır; bilinmeyen required value enum'u sessizce default olmaz. Migration pure function ve `source_hash → derived_hash` ile kayıtlı; raw artifact overwrite edilmez.

JSONL eğitim kayıtları (`noema.example.v2`), capability eval (`noema.capability_eval.v1`), run manifest (`noema.training_run.v1`), event log ve output artifact (`noema.output_example.v1`) farklı aggregate'lerdir, birbirine kopyalanıp karıştırılmaz. `example_id`, `request_id` ve `run_id` aynı string olsa bile ID namespace'i farklıdır; referans alanının türü önemlidir.

### 29.5 Eğitim–servis ayrımı ve online tutarlılık

Serving istekleri sadece immutable promoted release + izinli tenant memory okur; eğitim adayını asla canlı istek yarısında okuyamaz. Feedback, response/request/evidence refs taşıyan ayrı observation event olur; ancak §22 state machine'inden geçince training-eligible olur. Release promotion atomik manifest switch'tir: bir request aynı anda iki release'ın yarım rule table/adapter state'ini karıştıramaz. Rollback parent release'a döner; sonradan gelen correction/deletion event'leri rollback ile silinmez.

### 29.6 Dependency-aware invalidation

`source → derived parse → meaning record → obligation → evidence → rule/artifact` yönlü dependency graph tutulur. Kaynak correction/deletion olduğunda affected descendants bulunur ve `valid → stale/invalidated` event'i çıkar; hangi descendant setinin incelendiği coverage report'a yazılır. Bulunamayan edge ihtimali yüzünden dependent result'lar kaynak değişiminden sonra yeni sorguda cache'ten final diye sunulmaz. Cache index silmek knowledge/event archive silmek anlamına gelmez.

### 29.7 Cross-contract tests ve kabul kapıları

`validate_examples.py` şu an yalnız structural/certain referential checks yapar. Uygulama geliştikçe contract testleri katmanlanır:

- **schema tests:** required field, type, enum, unknown version.
- **referential tests:** output obligation/evidence refs; event/run/release parent links; no orphan IDs.
- **state machine tests:** yasadışı transition, retry/idempotency, cancellation ve rollback.
- **permission tests:** cross-tenant/split ref erişimi reddedilir; deny event iz bırakır.
- **fault-injection tests:** bozuk hash, eksik event, truncated stream, disk full, clock rollback, verifier crash.
- **differential tests:** dijital core deterministik oracle ile aynı input semantics; analog output yalnız tolerance band içinde ve final proof checker'dan geçer.

K59 — canonical ID/reference integrity: dangling obligation/evidence/artifact/event/release ref = 0 (fixture kapsamı).
K60 — legal state transitions: state machine dışı promotion/close/cross-tenant read = 0 kabul.
K61 — correction/deletion propagation: dependency graph üzerinden affected outputların invalidation coverage'ı ölçülür; unknown coverage varsa fail-closed.
K62 — version migration: eski örnekler yalnız explicit migration ile kabul; raw source hash değişmez.

*Belge sürümü: v1.3 — 2026-11-16. Request→task→obligation→evidence→artifact ve train→release kimlik/yaşam döngüleri tek normatif sözleşmede hizalandı; runtime cross-contract testlerinin çoğu henüz uygulanmadı.*

## 30. v1.4 — Eğitim gecikme bütçesi ve kritik-yol hızlandırıcısı

Bu bölüm eğitim hattındaki süreyi kısaltmak için §22 run state machine'ine entegre edilen execution plan'ı tanımlar. Hızlanma; zorunlu güvenlik, veri/provenans, retention ve promotion kontrollerini atlayarak değil, **tekrar işi kaldırıp bağımsız işi paralel çalıştırarak** sağlanır. Bu bir tasarım/ölçüm planıdır; speedup henüz ölçülmedi. Yeni run manifest uzantısı `noema.training_run.v2` olup örneği [`run_manifest.example.json`](../noema-training/run_manifest.example.json) içindedir.

### 30.1 Önce ölç, sonra en yavaş stage'i hedefle

Her run'da DAG node başına queue wait, wall time, CPU-core seconds, bytes, peak memory, cache hit/miss, retry, reject reason ve critical-path contribution ölçülür. Scheduler önce geçmiş **aynı fingerprint family**'nin ölçülen dağılımından p50/p95 tahmini alır; ilk kez görülen node için tahmin `unknown` olur ve konservatif per-node cap kullanılır. Tahmin yalnız planlama içindir, correctness/gate sonucu değildir. Eski `noema.training_run.v1` manifestleri yalnız import edilir; migration, konservatif `max_workers=1`, cache disabled ve tam gate profiliyle yeni v2 manifest üretir. Üretimde doğrudan v1 yürütülmez.

`TrainingRunManifest.execution_plan` alanları:

- `max_workers`: compute budget/CPU kotasını aşmayan sabit worker üst sınırı.
- `batch_size`: aynı schema/module/task family içindeki bağımsız kayıt grubu.
- `shard_key`: bölme/leakage politikasındaki entity/family key; aynı grup farklı worker/split'e dağılmaz.
- `incremental_cache`: yalnız tam fingerprint eşleşmesinde kullanılabilecek cache izni.
- `cache_namespace`: tenant/licence/policy ile sınırlandırılmış content-addressed namespace.
- `deterministic_merge`: tamamlanan sonuçları stable task/object ID sırasıyla birleştirir; v2'de zorunlu `true`.
- `gate_mode`: ucuz fail-fast kontrolleri, sonra terfi öncesi bütün zorunlu gate'ler.

### 30.2 Incremental DAG + güvenli cache

Her stage node fingerprint'i:

```
node_key = H(node_kind, code_hash, config_hash, input_artifact_hashes,
             schema_version, validator_hash, policy_version,
             parent_release, hardware_profile_if_perf_test)
```

- Aynı node key + başarılı, imzalı, bozulmamış result artifact varsa node yeniden koşmak yerine result doğrulanarak reuse edilebilir.
- Değişen veri, parser/grammar, objective, validator, policy, compiler, parent release veya perf donanım profili downstream cache'i invalid eder.
- İzin/tenant sınırları cache key'in ve namespace'in parçasıdır; başka tenant'ın hit'i yasaktır. Silme event'i cache descendants'ı invalid eder.
- Hatalı/başarısız test sonucu cache'den başarı gibi dönemez. Fail sonucu da yalnız triage için cache'lenebilir ve yeni candidate promotion'ını engeller.
- Cache checksum/manifest doğrulanamazsa `MISS` sayılır; live task'ta exact hesap tekrar yapılır. Cache semantik otorite değildir.

Böylece parent baseline, unchanged schema tests, immutable proof fixtures ve hiç etkilenmeyen modüller tekrar kullanılabilir; ancak candidate'nin etkilenen tüm capability'leri, her release'in safety/privacy-critical invariant'ları ve promotion bütünlük kontrolü yeniden değerlendirilir. Cache kullanımı test atlama değil, aynı exact testin aynı exact input/config üzerindeki imzalı sonucunu reuse etmektir.

### 30.3 Paralellik ve deterministic merge

1. DAG hazır node'ları `risk × criticality × predicted_duration` önceliğine göre worker havuzuna verir; high-risk gate erkene alınır.
2. Bağımsız task-family/module shard'ları paralel koşar; aynı mutable candidate state'e birden fazla worker yazmaz. Worker kendi candidate delta/event üretir.
3. Merge aşaması delta'ları stable `(module_id, family_id, shard_key, task_id)` sırasına koyar; conflict veya write-set çakışması varsa merge durur, sequential re-run yapılır.
4. `max_workers` runtime CPU/memory bütçesinin altındaysa unused core kullanılabilir; oversubscription ve aynı anda tüm RAM'i isteyen batch engellenir.
5. Tek büyük batch yerine sınırlandırılmış mini-batch; early rejection kalan batch hesaplarını iptal eder, fakat her satırın status'u event log'a yazılır.
6. Non-deterministic external connector'lar training-critical path'te kullanılmaz; gerekiyorsa frozen fixture/recorded response replay edilir.

### 30.4 Gate pyramid: ucuzdan pahalıya, zorunlu kapı atlamadan

| Aşama | Ne zaman | Hız kuralı |
|---|---|---|
| G0 schema/policy/hash/consent | her ingest ve her run | O(1)/streaming check; ilk fail'de dur |
| G1 cheap exact/local verifier + static typing | her candidate delta | küçük bounded tests önce; hata varsa training devam etmez |
| G2 changed-module smoke + affected-family tests | ilgili modül/veri değişince | dependency graph'taki etkilenen node'ları çalıştır; sonucu parent/config hash'e bağla |
| G3 retention + cross-family + safety/privacy | her promotable candidate | gerekiyorsa exact cache reuse; asla model metriğiyle atlama |
| G4 complete promotion integration | her release promotion | bütün zorunlu gate seti geçmeli; exact fingerprint'li imzalı test reuse dışında kapsam eksiltme yok |
| G5 performance/scale benchmark | kod, model, data veya hardware değişince | yalnız sabit koşullarda karşılaştır; correctness gate'leriyle paralel olabilir ama aynı CPU budget'ı paylaşır |

Tüm gate'ler final terfi için hâlâ geçerlidir. G0/G1 fail olduğunda G2+ compute harcanmaz; bu doğrudan güvenlik/doğruluk kısayolu değil, erken durdurmadır.

### 30.5 Veri hattı ve eğitim adımında hız

- JSONL akışı satır satır okunur; tüm corpus RAM'e yüklenmez. Duplicate IDs/reference sets için gerekli küçük indeksler memory quota ile tutulur veya sıralı external merge olarak yürütülür.
- Deterministic generation: `(generator_version, seed, task_family, params)` ile synthetic fixture üretilir; aynı hash'li artifact tekrar üretilmez. Generator değişirse cache invalid olur.
- Normalizasyon, parse forest, token/grapheme span ve typed graph aynı immutable raw ref'ten türetilir; downstream task'lar bu artifact'i paylaşır, fakat her dönüşüm kendi version/hash'ini taşır.
- Yalnız değişen kontratlar için counterexample araması; bounded local neighborhood/seed expansion. Eşik/aile kapsamı değişince broader search zorunlu hale gelir.
- İnsan incelemesi yalnız disagreement, new error family, high-risk ve stratified random audit'te; basit sentetik doğru etiket otomatik, fakat checker uyuşmazlığı varsa insan kuyruğuna yükseltilir.
- Cache miss/hit, oluşturma zamanı ve doğruluk sonuçları ayrı raporlanır. Çok cache hit ile daha kısa eğitim, model kalitesinde gelişme anlamına gelmez.

### 30.6 Early-stop, cancellation ve bütçe muhasebesi

Stage, başlarken `estimated_remaining`, kill-safe checkpoint ve `cancel_safe` sınırı bildirir. Yeni sample batch başlatmadan önce: kalan CPU/wall/memory bütçesi batch + required local verifier'a yetiyor mu kontrol edilir. Yetmiyorsa `PAUSED`, `budget_exhausted`, ya da kullanıcıdan daha çok kaynak istenir; yarım batch promotion adayı sayılamaz. Bir paralel shard fail edince bağımlı shard'lar iptal edilir; bağımsız diagnostik shard'lar yalnız incident triage manifestinde devam edebilir.

Run sonucu hem `raw_training_seconds` hem `cache_saved_seconds`, `validation_seconds`, `human_minutes`, `promotion_gate_seconds` raporlar. Başarılı capability başına toplam maliyet hesaplanır; cached evaluation da önceki ölçüldüğü için bedava varsayılmaz, artifact storage/verification maliyeti sayılır.

### 30.7 Hızlandırma kabul kapıları

| Kapı | Kriter |
|---|---|
| K63 — cache correctness | node fingerprint'in herhangi bir girdisi değişince cache miss; aynı fingerprint ise payload/checker sonucu hash eşleşir |
| K64 — incremental invalidation | değişen node'un tüm downstream dependency'leri bulunur; unrelated node sabit kalabilir; etkilenen test kaçırma = 0 fixture kapsamında |
| K65 — parallel determinism | worker sayısı/schedule değişse candidate manifest ve sorted event outputs aynı |
| K66 — time-to-detect | fail-fast G0/G1'de geçersiz adayın detection süresi ve harcanan compute raporlanır |
| K67 — end-to-end speedup | aynı gate sonucu/kalite/coverage ve makine altında cold-vs-warm, sequential-vs-parallel duvar saati ve CPU maliyeti; başarısız denemeler dâhil |
| K68 — memory bounded ingest | corpus boyutu büyürken peak RSS configured bound'u aşmaz; malformed satır line number ile fail eder |
| K69 — no gate regression | hızlandırılmış release'te zorunlu gate listesi, baseline release'ten eksik olamaz; promotion manifest set farkını denetler |

Başlangıç hedefi "olabildiğince hızlı" değil: aynı kabul edilen quality/evidence/security sonucunu daha düşük **toplam end-to-end run cost** ile ölçmek. K67 geçmeden hız kazancı iddia edilmez. Mevcut training core'da gerçek paralel learner/cache DAG henüz kodlanmadığı için bu turda performans sonucu yoktur.

*Belge sürümü: v1.4 — 2026-11-16. Eğitim execution plan, incremental DAG/cache, deterministic parallelism ve gate pyramid §22 akışına bağlandı; hızlanma ölçülmedi.*

## 31. v1.5 — LIR: mimarinin doğrulanabilir derleme ve eylem dili

LIR, NOEMA için serbest biçimli doğal dil modeli veya semantik karar motoru değil; **tipli, çalıştırılabilir ve sınırlandırılmış code/effect artifact** dilidir. Natural-language istek önce TaskContract/MeaningRecord/Obligation'a çevrilir; LIR kodu ancak bu sözleşmenin dar kapsamlı alt hedefini gerçekleştiren aday olur. LIR'ın `lir check`/derleme/test sonucu yalnız o artifact/build/input kapsamına evidence sağlar; kullanıcı niyetinin doğru anlaşıldığını veya programın bütün girdilerde doğru olduğunu tek başına kanıtlamaz.

### 31.1 Katman bağlantısı

```
request + permissions + resource budget
 → code obligation (preconditions, postconditions, effects, allowed APIs)
 → LIR candidate + compiler/schema version
 → type/sema + IR verifier + static resource checks
 → O0 reference run + optimized builds (O1/O2) + property tests
 → sandbox execution record + stdout/stderr/exit + resource counters
 → artifact hash + evidence refs → response
```

- **NLU → code contract:** belirsiz önkoşul veya efekt yetkisi bilinmiyorsa kod çalıştırılmaz; eksik şart sorulur veya `unsupported` denir.
- **LIR frontend → IR:** parser/sema/compiler version pin'lenir. `lang --json` capability output ve generated `LANGUAGE_REFERENCE.md` gerçek implementasyon kaynağıdır; docs'taki unsupported/partial features'ı kod üretimi var saymaz.
- **Compiler → optimizer:** O0 semantik referans; O1/O2 performans adayları. Transform geçerli değilse optimizer seviyesi fail eder; guard, trap, bounds, overflow, evaluation order ve observable effect'ler sessizce ortadan kaldırılamaz.
- **Runner → tools:** compiler/runner ayrı `tool_call_id`, read/write permission scope, wall/CPU/memory/output cap ve side-effect classification taşır. Derlenen kullanıcı kodu default olarak izole sandbox'ta çalışır; host I/O capability yoksa kapalıdır.
- **Evidence → output:** source artifact hash, compiler build/version, target/backend, opt level, input/property suite hash, run status ve limitler zincirlenir. `executed_test` yalnız test edilen noktalar/özellikler içindir; `formal_proof` değildir.

### 31.2 Hız ve kapsam hedeflerinin doğru ayrımı

**Hız** iki bağımsız maliyettir: `compile_wall_time / compile_cpu / peak_RSS` ve `run_wall_time / CPU / memory / code_size`. Sadece `-O2` output runtime'ı değil, optimizer pass süresi de toplanır; optimize binary, compile bütçesine değmiyorsa küçük/tek-shot programda O1/O0 tercih edilebilir. Scheduler target workload'lar için compile cost + expected invocation count × runtime cost karşılaştırması yapar; benchmark'sız otomatik O2 varsayımı yok.

**Kapsam** desteklenen construct/backend/target/version matrisidir. Genişleme yalnız grammar eklemek değildir: lexer/parser/sema/IR lowering/verifier/codegen/VM/C/WASM semantics, error diagnostics, language reference generation ve test matrix birlikte güncellenmelidir. Partial/unsupported hücre açıkça görünür; fail-closed ve feature capability ile route edilir. Her yeni feature semantic suite'i O0/O1/O2 ve desteklenen backend'lerde geçmeden training tool capability olarak ilan edilmez.

### 31.3 Eğitim hızlandırıcıyla bağ

Compiler workload DAG'i §30'la aynı execution plan kullanır. Parse/typed IR artifact cache key'i compiler binary+source hash, feature flags, target, schema, parent config ve input hash içerir. Optimization cache ayrı `opt_level` ve pass-pipeline fingerprint taşır. Cache yalnız exact hash ve doğrulanmış immutable result'ta kullanılabilir; compiler, optimizer, verifier, stdlib, target veya flags değişince descendants invalid olur. Property tests değişen IR/codegen/backend dependency'lerine göre incrementaldir; tam release promotion gate'i ve safety testleri yine zorunludur.

Bağımsız source shard'lar ayrı process/worker'da derlenebilir. Bir source module için mutable compiler state paylaşılmaz; sonuçlar deterministik file/module order'ında merge edilir. Benchmark worker'ları correctness suite CPU/RAM kotasını çalamaz. Cold-cache ve warm-cache derleme süreleri ayrı raporlanır; cache speedup kalite artışı veya genel LIR speedup diye sunulmaz.

### 31.4 Gate'ler ve ölçümler

- **L0 language conformance:** supported construct için parse + type + expected diagnostic; generated language reference golden.
- **L1 optimizer equivalence:** deterministic fixtures/property suite'te O0 referans ile O1/O2 sonuç, trap/side effect ve exit davranışı tutarlı.
- **L2 backend equivalence:** yalnız ilan edilmiş backend matrix; unavailable platform unsupported kalır, başka backend sonucu yerine geçmez.
- **L3 sandbox:** path/network/process/host memory sınırı, timeout, output cap, cancel/unknown-side-effect, cleanup; fail closed.
- **L4 performance:** sabit compiler/code/input/host; warmup ve tekrarlar; median + p95/CI, compile+run, peak RSS/code size, correctness gate sonucu.
- **L5 promotion:** artifact provenance + evidence refs, test coverage, regression/failure IDs ve cost raporu; human review risk policy'ye göre.

Capability eval fixture `code-lir-optimization-001` bu sözleşmeyi ve ölçüm kapsamını kaydeder. K70 semantic preservation O0/O1/O2 ve desteklenen backend'lerde geçiş; K71 optimizer correctness regression = 0; K72 feature matrix her release'te generated ref ile uyumlu; K73 sandbox escape = 0 test kapsamı; K74 compile+run cost aynı doğruluk/host ile ölçülür. Benchmark sonuçları olmadan speedup iddiası yok.

**Uygulama sınırı:** mevcut depodaki Zig bootstrap compiler zaten O0/O1/O2, CFG/SSA tabanlı optimizer, IR verifier ve native/VM/C11/WASM execution yolları içeriyor. Bu bölüm bunların NOEMA'daki rolünü ve ortak gate'lerini tanımlar; bu turn'de optimizer algoritması veya derleyici hızı değiştirilmedi. Zig toolchain sandbox'ta bulunmadığından compiler/backend regression matrix'i çalıştırılamadı; yalnız AI fixture validator çalıştırıldı. Öncelikli devam işi: toolchain erişimli CI'da K70–K74 benchmark/equivalence fixture'larını gerçek compiler ile bağlayıp ölçülen bottleneck'e göre pass-pipeline/compiler-cache iyileştirmesi yapmak.

*Belge sürümü: v1.5 — 2026-11-16. LIR'in NOEMA'daki code/effect/evidence kontratı capability evaluation ile bağlandı; hız/kapsam hedefleri ayrıldı, performans henüz ölçülmedi.*
