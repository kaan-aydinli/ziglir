# NOEMA: Ağırlık Tabanlı Üretim ve Kanıta Dayalı Akıl Yürütme Tasarımı

**Durum:** Tasarım önerisi; henüz uygulanmadı veya ölçülmedi
**Kapsam:** Harici LLM/LMM, Transformer, Mamba/SSM, NCM, tokenizer, embedding servisi, vektör veritabanı veya dış optimizer kullanmadan LIR içinde geliştirilecek üretim ve akıl yürütme sistemi. Eğitim/kalibrasyon döngüsü, önceden tanımlanmış kaynak ve kaynak politikasıyla insan müdahalesi olmadan çalışacak şekilde tasarlanır.
**Tasarım adı:** Çok-Zamanlı Nedensel Alan (ÇZNA) ve Kanıt Defteri
**Dürüstlük kuralı:** “Özgün” burada bu depo için yeni bir mühendislik tasarımı anlamındadır; akademik öncelik veya bilinen yöntemlerden tümüyle bağımsızlık iddiası değildir.

## 1. Hedef ve mevcut durum

Hedef; cevabı yalnızca eğitim satırlarından arayıp kopyalamak yerine, öğrenilmiş model durumundan değişken uzunlukta metin üreten ve hesap/iddiaları ayrı bir doğrulama katmanında sınayan bir sistem tasarlamaktır. Serbest metin üretimi ile güvenilir akıl yürütme aynı özellik değildir; tasarım bu iki sorumluluğu ayırır.

Mevcut `ai/src/noema_pretrain.lir` ve `/api/chat` yolu corpus satırlarını exemplar olarak saklayıp lexical retrieval yapar. Mevcut `ai/src/noema_decoder.lir` ise sabit sınıf/özellik/çıktı boyutlu, pozisyon bazlı bayt sayımıdır; bu belge önerisinin üretim başlığı değildir. Dolayısıyla bu doküman bir uygulama veya kalite kanıtı değil, yeni bir geliştirme sözleşmesidir.

## 2. Tasarım ilkeleri

1. **Ağırlıktan üretim:** Yanıt baytları, checkpoint’teki öğrenilmiş parametrelerden adım adım seçilir. Retrieval sonucu yanıtın yerine geçirilmez.
2. **Harici model yok:** Eğitim, parametre güncelleme, durum yönetimi, checkpoint ve inference LIR’de yazılır. Harici model/servis/kitaplık çağrısı yoktur.
3. **Ham UTF-8 akışı:** Harici tokenizer veya sabit kelime dağarcığı yoktur. Model 0–255 baytlarını işler; UTF-8 doğrulaması ve bayt sınırları açıkça korunur. İçsel segment sınırları öğrenilen/kestirilen yardımcı durum olabilir; dış tokenizer değildir.
4. **Üretim ile kanıt ayrı:** Dil modeli bir öneri üretir; doğrulayıcı sayısal/biçimsel adımları, kaynak izlerini ve çelişkileri ayrı inceler. Akıcı metin tek başına doğruluk kanıtı sayılmaz.
5. **Ölçmeden iddia yok:** “Aşırı kaliteli”, “genel zekâ” veya “insan düzeyi” kabul kriteri değildir. Yetenek, önceden belirlenmiş, tutulmuş değerlendirme kümeleriyle ölçülür.
6. **Hardcoded içerik yok:** Konu başına cevap tabloları, anahtar-kelimeyle sabit görev yönlendirme, eğitim örneğini cevap diye kopyalama ve el yazımı cevap şablonları yoktur. Dil içeriği ve üretim tercihleri eğitimden öğrenilir. Genel amaçlı sayı/kanıt doğrulayıcıları içerik ezberi değildir; kapsamları açıkça belirtilir.
7. **Bileşimsel genelleme hedefi:** Model, eğitimde görülmemiş soru cümlelerini ve daha önce birlikte görülmemiş bilinen kavram birleşimlerini çözmeye çalışır. Bu, aynı olgunun/işlemin eğitim dağılımında veya mevcut girdide bulunmasını gerektirir. Eğitimde ve girdide hiç bulunmayan yeni bir olguya erişim veya her “benzerliksiz” örnekte doğru cevap garantisi verilemez.
8. **Otonom koşu:** Kaynak/lisans politikası bir kez yapılandırıldıktan sonra ingest, preflight, eğitim, değerlendirme, promotion/rollback ve resume otomatik çalışır; her epoch için insan etiketi veya onayı beklemez. Kaynakların doğruluğu/lisansı salt algoritmayla kesinleştirilemez; güvenilir kaynak allowlist’i başlangıç önkoşuludur.
9. **Kaynak sınırları:** Kodda sabit, keyfî bir corpus sayısı veya 96-bayt yanıt tavanı hedeflenmez; ancak fiziksel RAM/disk, adres alanı, işlem süresi ve I/O sonlu kalır. Büyük ölçek için tek parça belleğe yükleme yerine sayfalama/shard gerekir.

## 3. Mimari genel görünüm

```text
UTF-8 girdi
   │
   ├─ A. Akış çözümleyici ve sınır gözlemcisi
   │      └─ bayt, boşluk, noktalama, satır ve aday anlam parçaları
   │
   ├─ B. Çok-zamanlı nedensel alan (ÇZNA)
   │      ├─ kısa-erimli bağlam durumu
   │      ├─ orta-erimli konu/iddia durumu
   │      └─ uzun-erimli öğrenilmiş parametreler
   │
   ├─ C. Çift yönlü tahmin yüzeyi
   │      ├─ ileri başlık: önekten sonraki bayt
   │      ├─ ters başlık: sonekten önceki bayt (eğitim/yorumlama)
   │      └─ bayt 0..255 + içsel durdurma olayı
   │
   ├─ D. Öğrenilmiş plan/işlem seçici
   │      └─ olası işlemler için yarar, risk ve maliyet tahmini
   │
   ├─ E. Kanıt Defteri ve doğrulama yürütücüsü
   │      ├─ kaynak aralığı / iddia / ilişki / bilinmeyen
   │      └─ sayısal, mantıksal ve çelişki kontrolleri
   │
   └─ F. Sınırlı verbalizer ve çeşitlilik denetimi
          └─ doğrulanmış bulguları ağırlıklardan farklı biçimlerde anlatır
```

A, D ve E dil üretim ağırlıklarının yerine geçmez. Retrieval istenirse kaynak bulucu olarak kullanılabilir; ancak yanıt, saklanan exemplar baytlarını doğrudan kopyalayarak üretilmiş gibi raporlanmaz. Kaynağa dayalı bir yanıtın kaynak izi ayrıca taşınır.

## 4. ÇZNA: çok-zamanlı durum ve tahmin

### 4.1 Öğrenilmiş durum

Her bayt girdisi için model üç bağlam ufkunda durum taşır:

- `s`: yakın yazım ve yerel sözdizimi izleri,
- `m`: cümle/konu ve yerel iddia ilişkileri,
- `l`: daha uzun konuşma/konu özeti ve kalıcı öğrenilmiş eğilimler.

Bunlar sabit bir pencere halinde prompt kopyalamaz; bayt başına taşınan, checkpoint edilebilir durum vektörleridir. Bir ilk uygulama için denetlenebilir geçiş önerisi:

```text
x_t = E[byte_t] + B(boundary_t)
q_t = concat(s_t, m_t, l_t)

s' = clip(ρ_s ⊙ s_t + tanh(A_s s_t + X_s x_t), -1, 1)
m' = clip(ρ_m ⊙ m_t + tanh(A_m m_t + P_sm s' + X_m x_t), -1, 1)
l' = clip(ρ_l ⊙ l_t + g_t ⊙ tanh(A_l l_t + P_ml m' + X_l x_t), -1, 1)
q' = concat(s', m', l')
z_b = c_b + dot(W_b, q') + evidence_bias(b, ledger_t)  // b ∈ [0,255] ∪ {STOP}
```

`E`, `A_*`, `P_*`, `X_*`, `W` ve `c` öğrenilen ağırlıklardır; `ρ_*` ve `g_t` sınırlandırılmış durum-geçiş katsayılarıdır. `g_t`, uzun ufka yazmayı yalnız konu/sınır/kanıt olaylarında açar; her baytın uzun belleği doğrudan ezmesi engellenir. `clip` sayısal güvenlik bariyeridir, öğrenme kalitesi kanıtı değildir. Boyutlar yapılandırılabilir ve checkpoint’te saklanır; varsayılan değer seçimi benchmark ile yapılır.

Üç ufuklu geçiş, çıktı skorlaması ve byte-stream eğitim hattı bu tasarımın kendi bileşimidir; benzer matematiksel yapıların literatürde hiç bulunmadığı iddia edilmez. Bu yapı, mevcut NOEMA alanına bir dil üretim başlığı eklemek için test edilebilir bir başlangıçtır. Her ufkun normu, doygunluk oranı, gradyan/güncelleme normu, byte kaybına katkısı ve konu-held-out davranışı ayrı ölçülür. Bir ufkun öğrenmesi diğer ufukları kontrolsüz biçimde ezmemelidir.

### 4.2 İçsel sınır kestirimi

Dış tokenizer kullanılmaz. Model ham baytları işler ve sınır adayı sinyallerini (boşluk, noktalama, UTF-8 karakter başlangıcı, tahmin hatasında yerel artış) durum güncellemesine verir. Bu sinyaller gerçek token kimlikleri değildir; yalnızca akışın hangi bölgelerinde içsel durumun farklı güncellenebileceğini belirtir. Unicode karakterleri birden çok bayt olduğundan metin görünürlüğü ve kullanıcı aralıkları UTF-8 doğrulayıcısıyla eşlenir.

Sınır kestirimi hatalıysa model yine bayt akışında çalışır; veri atılmaz. Değerlendirmede Türkçe ekler, birleşik sözcükler, noktalama, emojiler, bozuk UTF-8 ve farklı normalizasyon biçimleri ayrı raporlanır.

### 4.3 Sonraki-bayt tahmin başlığı

Her adımda ağırlıklar 256 bayt adayı ile bir içsel `STOP` olayına skor verir. `STOP`, kullanıcıya görünen bayt sözlüğüne eklenmiş harici bir token değildir; decoder protokolünde üretilen kontrol olayıdır. Üretim, istenen stop koşulu, UTF-8 tamamlanma koşulu veya açık kaynak bütçesi gerçekleşene kadar akış halinde yapılır. Sabit 96/256 baytlık model çıktı tamponuna bağlı olmaz.

Inference sözleşmesi:

1. Prompt bayt akışı okunur ve model durumu güncellenir.
2. Çıkış skorları ağırlıklardan hesaplanır.
3. Seçim politikası (deterministik veya seeded sampling) açıkça belirtilir; sessiz rastgelelik yoktur.
4. Seçilen bayt, bağlam durumuna geri beslenir; sonraki bayt yeni durumdan hesaplanır.
5. İçsel `STOP` yalnız uygun bitişte kabul edilir; yarım UTF-8 dizisi kullanıcıya verilmez.
6. Her adımda kaynak, üretim uzunluğu, skor aralığı ve durdurma nedeni telemetry’ye yazılır.

Üretim politikası güvenlik ve tekrarlanabilirlik için checkpoint kimliği, seed, örnekleme parametreleri ve çıktı bütçesini sonuç metaverisinde taşır. Çıktı uzunluğunun kaynakla sınırlandırılması operasyonel korumadır; modelin sabit maksimum yanıt uzunluğu olarak gizlenmez.

### 4.4 İleri/geri bayt tahmini ve bilgi sızıntısı kuralı

Eğitim her metin aralığında iki yönde tahmin yapar:

```text
L_forward = Σ_t -log P(b_(t+1) | b_0..b_t)
L_reverse = Σ_t -log P(b_(t-1) | b_t..b_(T-1))
L_consistency = distance(H_forward(t), H_reverse(t), boundary_targets)
```

`L_forward` üretim başlığını; `L_reverse` mevcut metni sonekten de yorumlayan ayrı başlığı eğitir. `L_consistency` aynı aralığın iki yöndeki temsilinin çelişki/segment işaretlerinde tutarlı olmasını hedefler; ileri ve geri başlıkları aynı ağırlıkları paylaşabilir, ama parametre paylaşım kararı benchmark ile seçilir. Ağırlık paylaşımı varsayılan kabul edilmez.

Kritik nedensellik kuralı: **inference sırasında ileri üretici gelecekteki baytları göremez.** Ters başlık yalnız tamamen verilmiş prompt'u analiz eder veya eğitimde kullanılır; üretilecek cevabın gelecek baytını tahmin etmek için kullanılamaz. Gelecek token/baytın yanlışlıkla girişe sızdığı testler negatif regresyon testidir. Böylece çift yönlü eğitim, nedensel üretimi hileyle ölçmez.

Önceki-bayt hedefi, sonraki-bayt hedefinin yerini almaz. İki yönlü kaybın katkıları ayrı loglanır. Ters başlığın eklenmesi held-out ileri üretim kaybını veya yorumlama başarısını düşürürse ağırlığı azaltılır ya da başlık kaldırılır; “daha fazla hedef her zaman daha akıllıdır” varsayımı yoktur.

### 4.5 Tekrar sorularda kontrollü ifade çeşitliliği

Aynı soruya her defasında bayt bayt aynı yanıtı vermemek için verbalizer, doğrulanmış Kanıt Defteri sabit kalırken farklı ifade yolları seçebilir. Çeşitlilik kararları yalnız yüzey biçimini (açıklama derinliği, cümle kuruluşu, örnek seçimi, üslup) etkiler; tarih, sayı, kaynak, sonuç veya güven düzeyini rastgele değiştiremez.

- Semantik iddia kümesi önce kilitlenir; her aday yüzey yanıtı bu kümeye geri çözümlenip kapsam/çelişki testinden geçer.
- Benzer son yanıtlarla tekrar cezası yalnız bu konuşma oturumu ve aynı intent kapsamında uygulanır; kaynak gerçekleri veya kritik güvenlik uyarıları cezalandırılmaz.
- Çeşitlilik tohumu isteğe bağlı ve telemetry’de görünürdür. Aynı seed + aynı checkpoint + aynı girdi deterministik çıktı verir; farklı seed farklı ama kanıtla uyumlu phrasing seçebilir.
- Tek doğru sayı/olgu varsa olgunun kendisi değişmez. Çeşitlilik, yeni bilgi uydurmak veya her tekrar soruda farklı “doğru” cevaba zorlamak değildir.
- Soru kısa bir yanıt istiyorsa uzun açıklama üretmek “kapsamlılık” sayılmaz; cevap kapsamını model soru ve kullanıcı bağlamından öğrenir.

Bu hedef için testler aynı soruyu birçok kez farklı bağlam/seed ile sorar; iddia eşdeğerliğini, phrasing çeşitliliğini ve gereksiz tekrarı ayrı ölçer. Yalnız string’lerin farklı olması başarı sayılmaz.

## 5. Kanıt Defteri: yorumlama ve akıl yürütme

Serbest metinden güvenilir çıkarım yalnızca sıradaki baytı tahmin ederek çözülemez. Bu nedenle ayrı bir çalışma alanı tasarlanır. Her kayıt en az şunları taşır:

```text
Claim {
  id,
  type: entity | property | event | relation | quantity | unknown,
  value_or_relation,
  source_spans: [(input_or_document_id, byte_start, byte_end)],
  status: observed | derived | assumed | contradicted | unknown,
  derivation_parent_ids,
  confidence_components
}
```

`confidence_components` tek bir büyülü “zeka puanı” değildir. Kaynak kalitesi, doğrudan alıntı/çıkarım ayrımı, bağımsız destek, çelişki ve doğrulama sonucu ayrı gösterilir. Aynı iddianın dayandığı kopya kaynaklar bağımsız kanıt sayılmaz.

### 5.1 Akıl yürütme döngüsü

1. **İsteği ayrıştır:** Soru türü, istenen çıktı, verilenler ve eksik değişkenler aday olarak çıkarılır.
2. **İddia taslağı kur:** Her iddia ya kullanıcı girdisine, ya lisanslı eğitim/kaynak kaydına, ya da açıkça işaretlenmiş varsayıma bağlanır.
3. **İşlem grafiği kur:** Desteklenen işlemler tipli düğümler olarak ifade edilir (eşitlik, toplama, sıralama, koşullu ilişki, zaman sırası gibi). Serbest metin bu grafiğin yerine geçmez.
4. **Türetilmiş sonuçları denetle:** Aritmetik/biçimsel düğümler bağımsız LIR fonksiyonlarıyla yeniden hesaplanır. Nedensel iddia için yalnız korelasyonun yeterli olmadığı gibi bilinen ayrımlar açıkça kodlanır.
5. **Çelişki ve eksik bilgi ara:** Gerekli değişkenler yoksa, kanıtlar çelişiyorsa veya işlem türü desteklenmiyorsa sonuç `unknown/abstain` olur.
6. **Yanıtı üret:** Doğrulanmış iddialar ağırlık tabanlı verbalizer’a verilir. Sabit cümle şablonu değil, öğrenilmiş üretim kullanılır. Verbalizer yeni olgusal iddia ekleyemez; eklerse bu iddia kanıt denetimine geri döner.
7. **Kapsamı denetle:** Soru birden fazla alt istek içeriyorsa modelin öğrendiği kapsam denetleyicisi her alt isteğin cevaplandığını/çekinildiğini kontrol eder; eksik başlık için yeniden planlar. Kontrol, sabit bir “genel cevap” metnini kopyalamaz.
8. **Son kontrol:** Sayı, birim, isim, alıntı aralığı ve yanıtın soruyu karşılayıp karşılamadığı denetlenir; kapsam dışı iddia varsa cevap yeniden üretilir veya çekinilir.

Bu yapı genel doğal dil muhakemesini kendiliğinden çözmez. İlk sürüm yalnız açıkça desteklenen işlem ailelerinde güvenilir sonuç iddia edebilir. Açık uçlu yorumlama için insan değerlendirmeli, konu sızıntısı olmayan test kümesi gerekir.

### 5.2 Çekinme davranışı

Sistem aşağıdaki durumlarda tamamlanmış bir cevap uydurmak yerine çekinir veya açıklayıcı soru sorar:

- cevap için gereken veri yok,
- kaynakların kökeni veya tarihi belirsiz,
- bağımsız kanıtlar çatışıyor,
- soru mevcut işlem/kavram kapsamının dışında,
- generator metni doğrulanmış kanıttan daha ileri iddia içeriyor,
- UTF-8/çıktı bütünlüğü veya checkpoint doğrulaması başarısız.

Çekinme başarısızlık sayılmaz; yanlış güvenli cevaba göre ayrı metrikle ölçülür. Aşırı çekinme de ayrıca raporlanır.

### 5.3 Öğrenilmiş işlem seçimi ve kendi kendini yönlendirme

Sistem her soruya aynı işleme zorlanmaz. Mevcut bağlam/iddia durumundan aday eylemler üretir: ek bağlam isteme, izinli yerel corpus’ta kanıt arama, iddiaları karşılaştırma, tipli bir hesap/biçimsel işlemi çalıştırma, kanıtı özetleme, cevabı yeniden kontrol etme veya çekinme. Bunlar konuya özgü cevaplar değil, dar sözleşmeli genel yeteneklerdir.

Her aday için öğrenilmiş seçici yaklaşık faydayı hesaplar:

```text
U(o | state) = expected_evidence_gain(o)
               - λ_r calibrated_risk(o)
               - λ_c resource_cost(o)
               - λ_u unresolved_uncertainty_after(o)
```

Seçici en yüksek beklenen faydalı işlemi dener; işlem sonucu Kanıt Defteri’ne eklenir, plan yeniden değerlendirilir. İşlem doğrulanamazsa sonuç iddia olarak kullanılmaz. Her action kontratı önkoşul, yan etki, kaynak bütçesi ve başarısızlık dönüşü taşır. Bu, anahtar kelimeye sabitlenmiş `if soru contains X then answer Y` yönlendirmesi değildir; ancak çalıştırılabilecek güvenli işlem kümesi uygulamada açıkça sınırlandırılır. Model kendi kendine yeni yürütülebilir kod yetkisi kazanmaz.

Durdurma, soru kapsamının kapatılması, kanıtın yeterli olması, çözülmemiş riskin yükselmesi veya açık kaynak/işlem bütçesinin bitmesiyle olur. İlerleme sağlamayan aynı işlemi sonsuza dek tekrarlama engellenir. “En iyi işlem” garantisi değil, ölçülen fayda/risk tahminine göre seçim hedefidir; yanlış seçim oranı ayrı benchmark’tır.

## 6. Eğitim tasarımı

### 6.1 Veri sözleşmesi

Genel dil modeli kalitesi, veri kalitesi ve kapsamından bağımsız bir mimari özelliği değildir. Her kaynak için lisans, dil, tarih, kaynak kimliği, deduplikasyon grubu ve kalite/review durumu tutulur. Gerçek dışı veya kaynaksız cümleler “genel kültür” diye etiketlenmez. Eğitim/dev/test bölünmesi satır bazında değil, kaynak ve yakın-kopya ailesi bazında yapılır.

Her corpus turunda şu sayımlar raporlanır:

- okunan kayıt/bayt,
- doğrulanıp kabul edilen kayıt/bayt,
- reddedilen kayıt ve nedeni,
- tekrar/near-duplicate kümeleri,
- checkpoint’e yazılan güncelleme sayısı,
- son byte offset ve checksum.

`okunan = kabul + reddedilen` eşitliği sağlanmadan koşu başarılı sayılmaz. Tamlık, “dosya boyutunu gördüm” demek değil; manifest, okuma offset’i, kayıt sayısı ve checksum’ların tutarlı olmasıdır.

### 6.2 Aşamalı öğrenme

**A. Otomatik akış öğrenimi:** Ham UTF-8 metin üzerinde ileri sonraki-bayt ve ters önceki-bayt hedefleri, etiket/konu tabloları olmadan çıkarılır. Sınır ve anlam parçaları sabit sözlükten değil, iki yöndeki tahmin hatası, UTF-8/boşluk/noktalama gözlemleri ve dev ölçümlerinden öğrenilir. Eğitim kaybı yön, kayıt ve örnek ağırlığı bazında ayrı raporlanır; uzun belgeler metrikleri tek başına domine etmemelidir. Eğitim verisinin tamamı stream edilir, fakat held-out kaynaklar güncelleme yoluna hiçbir aşamada sokulmaz. Eğitim kümesinde ilgili olgu/örüntü yoksa sistemin onu kendiliğinden “bilmesi” beklenmez.

**B. İlişki/kanıt eşlemesi:** Opsiyonel insan gözden geçirmeli veri veya otomatik/deterministik doğrulanabilir örneklerden `iddia → kanıt aralığı`, `verilenler → türetilmiş sonuç`, `eksik bilgi → soru/çekinme` hedefleri oluşturulur. Etiketli veri zorunlu değildir; insan tarafından hazırlanmış bir kaynak kullanılıyorsa bu başlangıç paketlemesidir, her eğitim koşusunda müdahale değildir. Hedefler ham yanıt ezberi değil, denetlenebilir kayıt yapısı ve doğru verbalizasyondur.

**C. Akıl yürütme sınaması:** Sayısal ve mantıksal işlem grafikleri ayrı üretilip doğrulanır. Yanlış adımı saptama, eksik öncülü belirleme ve çelişki bulma örnekleri de eklenir. Bu örnekler, modelin serbest metin kaybının yerine geçmez; ayrı yeteneklerdir.

**D. Kalibrasyon:** Modelin ne zaman cevap vermemesi gerektiği için destek/çelişki/unknown örnekleri eklenir. Eşik yalnız dev kümesinde seçilir; test kümesine göre ayarlanmaz. Harici ödül modeli veya otomatik insan tercihi taklidi yoktur.

### 6.3 Öğrenme hedefi, güncelleme ve kararlılık

İlk eğitim prototipi teacher-forced byte akışında şu hedefi kullanır:

```text
p_t(b) = exp(z_t(b) - max(z_t)) / Σ_j exp(z_t(j) - max(z_t))
L_byte = -Σ_t w_t log p_t(target_t)
L_total = L_byte + λ_boundary L_boundary + λ_claim L_claim + λ_reg L_reg
```

`L_boundary` yalnız doğrulanmış/elle denetlenmiş sınır etiketleri varsa etkinleşir; `L_claim` yalnız Kanıt Defteri hedefleri olan örneklerde hesaplanır. Eksik etiket sıfır hedefi gibi yorumlanmaz. `w_t` uzun kayıtların toplam kaybı tek başına domine etmesini engelleyecek şekilde kayıt başına normalize edilir. STOP hedefi, örnek sonu etiketinin bulunduğu yerlerde eğitilir.

Türevler LIR’de elle uygulanır: `∂L_byte/∂z_t(b) = p_t(b) - 1[b=target_t]`; bu hata çıktı başlığından `q'` ve üç durum geçişine zincir kuralıyla taşınır. Güncelleme, gradient normu açıkça loglanan sınırlı bir deterministik gradient-descent adımıdır; AdamW, harici optimizer veya autodiff paketi yoktur. Bu, standart bir öğrenme hedefinin sıfırdan yerel uygulamasıdır; yeni/üstün bir optimizasyon algoritması olduğu iddia edilmez. Türevler bağımsız küçük tensör fixture’larında sonlu fark kontrolüyle doğrulanmadan büyük eğitime başlanmaz.

Uzun dizilerde aktivasyon izi RAM’de zorunlu tutulmaz: her segment için giriş/çıkış durumları ve checksum’lu ara iz diske dökülebilir; geri geçiş segment segment okunur. Bu, I/O ve disk maliyetini artırır. Segment sınırında gradyan kesmek gerekiyorsa bu “tam uzun bağlam öğrenmesi” diye sunulmaz; kesilen mesafe raporlanır. İlk sürümde açık bir eğitim penceresi seçilir, sonra daha uzun aralıklar kalite/hesap maliyetiyle ölçülerek artırılır.

Her eğitim sürümü şu karşılaştırmaları sağlamalıdır:

- eğitim kaybı düşüyor mu,
- ayrılmış kaynak/dev kaybı ve kalibrasyon kötüleşiyor mu,
- eski görevlerin regresyonu var mı,
- ağırlıkların normu/sonlu olma durumu bozuluyor mu,
- tekrar aynı seed ile aynı checkpoint oluşuyor mu,
- farklı uzunluk ve segment sınırlarında sonuç değişimi kabul edilebilir mi.

Kayıp düşmesi genel zekâ artışına eşit değildir. Yeni veri, held-out dil ve görev testlerinde kazanım göstermiyorsa “kalite yükseldi” denmez.

### 6.4 Benzer örnek olmadan genelleme: senaryo sözleşmesi

“Benzer veriyle hiç eğitilmeden cevap” iki farklı anlama gelebilir; değerlendirme bunları ayırır:

| Senaryo | Eğitimde benzer soru var mı? | Gerekli bilgi nerede? | Beklenen davranış |
|---|---:|---|---|
| Yeni ifade/parafraz | Hayır | Olgu/ilişki corpus’ta var | Öğrenilmiş durum ve kaynak iziyle cevap; kelime eşleşmesi şart değil. |
| Yeni bileşim | Hayır | Bileşen olgular ayrı ayrı corpus’ta veya prompt’ta var | İşlem grafiği kurup bileşimi çöz; held-out kompozisyon başarısı ölçülür. |
| Verilen öncüllerden yeni sonuç | Hayır | Gerekli öncüller yalnız kullanıcı girdisinde | İddia defterini girdiden kur, doğrulanabilir işlemi yürüt ve sonucu üret. |
| Corpus’ta/girdide bulunmayan yeni olgu | Hayır | Hiçbir güvenilir kaynakta yok | Bilindiğini iddia etme; bilinmiyor/kanıt gerekli diye çekin. |
| Çelişkili veya tarih-duyarlı bilgi | Belirsiz | Kaynaklar farklı/eskimiş olabilir | Çelişkiyi ve tarih/kaynak farkını göster; tek cevabı uydurma. |
| Alan/kavram kayması | Hayır | Mevcut eğitim kapsamı dışı | Güven kalibrasyonu uygula; düşük kanıt varsa abstain veya açıklama iste. |
| Gürültülü metin/UTF-8/typo | Değişken | Aynı anlamın bozulmuş yüzeyi | Dayanıklılığı ayrı ölç; bozuk bayt dizisini sessizce düzeltip kesin alıntı gibi sunma. |
| Uzun bağlam ve dikkat dağıtıcı | Değişken | İlgili kanıt bağlam içinde | Kanıt aralığını bul, distractor’a diren; bağlam kesilirse kesilmeyi raporla. |
| Talimat/kaynak enjeksiyonu | Değişken | Belge içinde talimat benzeri metin | Kaynak metnini veri olarak ele al; sistem/politika talimatı yetkisi verme. |

Bu mimarinin “benzer eğitim örneği olmadan” hedefi ilk üç satırdaki **bileşimsel genellemedir**. Beşinci satırda gerektiğinde kaynak/araç gerekir; kaynak erişimi yoksa güvenli çekinme tercih edilir. Dördüncü satırda, hiçbir yerde bulunmayan bilgiyi doğru tahmin etmek teknik kabul kriteri değildir. Bir örnekte başarı genelleme kanıtı sayılmaz; aile/kaynak bazlı held-out kümelerde tekrarlanmalıdır.

### 6.5 Hardcoded olmama denetimi

- Eğitim örneği başına kodda konuya özgü `if/else`, cevap literal’i veya keyword→yanıt tablosu eklenmez.
- Router/segmenter görev seçimini ağırlıklar ve bağlam durumundan öğrenir; evaluator topic labels ile oracle routing yapmaz.
- Kanıt defteri alanları ve tipli işlemler genel veri yapısı/işlem semantiğidir. Desteklenmeyen işlem için sessizce sabit cevap vermek yerine açık `unsupported/unknown` durumu vardır.
- Eğitimden ayrı testlerde, görülmemiş isimler, sayılar, sözcük sıraları ve yeni bileşimler kullanılır; aynı örnek ailesinin parafrazları farklı split’lere sızmaz.
- “Hardcoded değil” iddiası kod taraması, training-data hash’leri ve held-out testlerle sınanır; yalnızca model ağırlığı kullanıyor olmak bu iddiayı kanıtlamaz.

### 6.6 İnsan müdahalesiz eğitim denetleyicisi

Otonomluk, modelin kendi ürettiği metni doğru kabul etmesi değildir. Koşu yöneticisi açık bir durum makinesi kullanır:

```text
DISCOVER → VERIFY_SOURCE → INGEST → TRAIN_CANDIDATE → EVALUATE
   → PROMOTE | ROLLBACK | PAUSE_FOR_RESOURCE | REJECT_SOURCE
```

Her geçiş `run_id`, kaynak manifesti, checkpoint hash’i, son tamamlanan kayıt/byte offset’i, sayaçlar ve sonuç koduyla kalıcı günlüğe yazılır. Çökmede aynı kaynak offset’inden güvenli resume yapılır; yarım checkpoint aktif modele geçirilmez.

**Otomatik veri kapıları (etiket gerektirmeyenler):** UTF-8/binary integrity, checksum, byte-identical dedupe, near-duplicate kümeleri, dil/bozukluk skorları, kayıt uzunluğu dağılımı, kaynak metadata’sı, train/dev/test sızıntı kontrolü. Bu sinyaller kalite şüphelilerini ayırır; metnin doğru olduğunu kanıtlamaz. Lisans ve kaynak allowlist’i dışarıdan bir kez tanımlanır; model kendi lisans iznini çıkaramaz.

**Aday eğitim döngüsü:**

1. Kaynak yeni, izlenebilir bir manifestle alınır; aynı source family train ve test’e bölünmez.
2. Self-supervised ileri/geri bayt hedefleriyle candidate checkpoint eğitilir. Bütün accepted kayıtlar tüketilmeden koşu “tam” sayılmaz.
3. Eğitimde kullanılmayan held-out kayıtlarla ileri/geri tahmin, UTF-8, tekrar ve bağlam uzunluğu değerlendirmesi yapılır.
4. Otomatik soru/çıkarım testleri yalnız bağımsızca doğrulanabilir cevapları varsa kullanılır: kaynakta açık aralık, typed fact kaydı veya deterministik işlem sonucu. Candidate’ın kendisinin ürettiği cevap **gold label** olarak kabul edilmez.
5. Başarı, önceden kilitlenmiş dev eşiklerine ve regresyon sınırlarına göre hesaplanır. Test seti eşik ayarlamak için kullanılamaz.
6. Uygun candidate atomik biçimde promote edilir; kayıp/kalibrasyon/regresyon kapısı geçilmezse rollback edilir. Disk/RAM yetmezse checkpoint bozulmadan `PAUSE_FOR_RESOURCE` durumuna geçilir.
7. Reddedilen kaynak, başarısız test ve nedenleri loglanır; otomatik döngü aynı hatayı sonsuza kadar tekrarlamaz.

**Kendinden eğitim güvenlikleri:** Model çıktıları kendi kendine doğruluk kanıtı değildir. Üretilen metin yeni source-grounded/verified hedef değilse sonraki eğitim turuna gold cevap olarak geri beslenmez. Aksi halde küçük yanlışlıkların kendi kendini büyütmesi (confirmation loop/model collapse) beklenebilir. Synthetic challenge üretimi yalnız test üretmek için kullanılabilir; cevap anahtarı bağımsız LIR verifier veya sabitlenmiş kaynak aralığıyla doğrulanır.

Bu tasarım eğitim çalıştırıcısının her epoch’ta insan müdahalesi olmadan çalışmasını hedefler. **İnsan müdahalesiz çalışma, insan tarafından hiç tanımlanmamış kaynak/lisans politikası veya otomatik olarak kanıtlanmış olgusal doğruluk anlamına gelmez.** Güvenilir bağımsız oracle olmayan açık uçlu iddialar otomatik olarak “doğru” diye promote edilemez; abstain/unknown oranı raporlanır.

### 6.7 Kendi deneyini seçen eğitim politikası

Otonom çalıştırıcı yalnızca kayıtları sırayla eğitmez; ölçülen darboğaza göre bir sonraki deneyi seçer. Deney değişkenleri cevap içeriği değil, sürümlenmiş mimari/eğitim yapılandırmasıdır: durum boyutları, ufuk katsayıları, loss ağırlıkları, segment boyu, güncelleme oranı ve seçim çeşitliliği. Sistem kaynakları ve numeric guard’lar sert güvenlik kısıtlarıdır; kalite hedefleri optimize edilirken aşılamaz.

Her candidate şu vektörle değerlendirilir:

```text
Q = (heldout_forward, heldout_reverse, compositional_reasoning,
     evidence_precision, calibration, repetition, resource_cost)
```

Tek bir bileşik puan kritik doğruluğu gizleyebileceği için karar sırası leksikografiktir: (1) checkpoint/veri bütünlüğü ve güvenlik, (2) kanıta dayalı doğruluk ve unsupported-claim oranı, (3) genelleme/kalibrasyon, (4) çeşitlilik ve sonra maliyet. Yalnızca güvenlik kapılarını geçen candidate’lar arasında kalite/maliyet karşılaştırılır. Kötüleşen eksenler aggregate skorla maskelenmez.

Arama yöneticisi mevcut sürümü koruyarak sınırlı, tekrarlanabilir config varyantları üretir, aynı dev protokolünde karşılaştırır ve sonucu günlüğe yazar. Belirsizliğin yüksek olduğu alanda yeni deney açabilir; ancak gizli final testini tekrar tekrar sorgulayıp ona aşırı uyum sağlayamaz. Yeni kaynak veya hesap bütçesi yoksa mevcut kararlı sürüm korunur. Arama, tanımlı konfigürasyon uzayındaki ölçülmüş en iyi sonucu bulmayı hedefler; küresel optimumu veya “her soruda en iyi karar”ı garanti etmez.

## 7. Checkpoint ve değişken uzunluklu üretim

Mevcut düz `.nps` tek durumu RAM’e alır; bu, çok büyük model için yeterli değildir. Yeni biçim `NPG` (Noema Predictive Graph) olarak sürümlenmelidir:

- mimari sürümü ve model yapılandırması,
- ağırlık shard manifesti ve parametre aralıkları,
- eğitim corpus manifest/checksum özeti,
- optimizer/update durumu (resume desteklenecekse),
- vocab değil, ham byte protokol sürümü,
- her shard checksum’u, boyutu ve byte aralığı,
- atomik yayın/rollback metadata’sı.

Yükleme ve kaydetme parça parça yapılır; tam modelin tek seferde RAM’e alınması şart olmaz. İlk uygulanabilir sürüm yerel dosya shard’larıyla sınırlı olabilir; dağıtık eğitim veya petabayt ölçeği ayrıca tasarlanıp test edilmedikçe destekleniyor denmez. Shard başına ve toplam bayt için checked arithmetic, eksik/bozuk shard’da fail-closed davranış zorunludur.

Üretim API’si sabit `DECODER_MAX_OUTPUT` veya sabit chat input tamponu kullanmaz. Yazıcı sink’e parça halinde çıktı verir; kullanıcı/servis açık bir `output_budget` belirleyebilir. Budget dolarsa `truncated_by_budget` döner ve UTF-8 karakter ortasında kesilmez. Süre limiti operasyonel ayardır; model mimarisinin gizli kalite parametresi değildir.

## 8. Değerlendirme ve yayın kapıları

### 8.1 Dil üretimi

- byte-level next-symbol kaybı/accuracy: eğitim ve kaynak-temelli held-out setlerde,
- bağlam uzadıkça bozulma ve tekrara düşme,
- UTF-8 geçerliliği, stop davranışı ve değişken uzunluk,
- konu çeşitliliği, kopyalama/near-duplicate oranı,
- otomatik kapılar: byte-loss, UTF-8/STOP doğruluğu, tekrar oranı, kaynak aralığı precision/coverage ve evidence dışı iddia oranı,
- insan değerlendirmesi (yayın kalibrasyonu için, her eğitim koşusunda değil): akıcılık, tutarlılık, olgusal doğruluk ayrı ölçeklerde. Bu yoksa yalnız otomatik metrikler raporlanır ve genel kalite iddiası yapılmaz.

### 8.2 Muhakeme ve yorumlama

- doğru sonuç, doğru gerekçe kaydı ve kanıt aralığı,
- eksik bilgi varken doğru soru sorma/abstention ve kaynakta olmayan olguda uydurmama,
- çelişkili/tarih-duyarlı kaynakları fark etme,
- karşı-olgusal küçük değişikliklerde tutarlı sonuç,
- görülmemiş ifade, yeni bileşim ve yalnız prompt’ta sunulan öncüllerle çözüm,
- konu değişimi, uzun/distractor bağlamı, typos ve Unicode varyantları,
- kapsamlı çok parçalı soruda her alt soruyu cevaplama veya açıkça işaretleme,
- hardcoded yanıt/template taraması ve eğitim verisiyle yakın kopya benzerliği,
- eğitim kaynağıyla test kaynağı arasında sızıntı olmadığına dair audit.

Her benchmark’ın soruları, cevap anahtarı, kaynak/lisans, split ve ölçüm komutu saklanır. Üretim demosu benchmark değildir. Bir alandaki kazanım başka alanlara genellenmiş sayılmaz.

### 8.3 Yayın eşiği

Bir checkpoint ancak aşağıdakilerin tümü sağlanırsa yayınlanır:

1. Veri manifesti tam ve checksum’lar doğrulanmış.
2. Checkpoint yeniden yüklenip bit düzeyinde/ölçüm toleransında tutarlı inference veriyor.
3. Eğitim kaybı yanında kaynak-temelli dev/test kalite raporu mevcut.
4. Eski benchmarklarda anlamlı regresyon yok veya gerekçesi açıklanmış.
5. Çıktıların tamamı üretim ağırlıklarından geldiği, retrieval/araç sonucu varsa bunun ayrıca işaretlendiği doğrulanmış.
6. Başarısızlık, kesilme ve abstention oranları raporlanmış.
7. Hiçbir kalite iddiası testin ölçtüğünün ötesine geçmiyor.

### 8.4 GPT/Gemini ile kalite iddiası

GPT/Gemini’den daha iyi olduğu ancak aynı sabit benchmark sürümünde, aynı sorular, aynı kaynak erişimi ve açıkça raporlanan benzer hesaplama/çıktı bütçesiyle kör ve tekrar edilebilir karşılaştırma yapılırsa iddia edilebilir. Harici model bu projenin runtime/training bağımlılığı olmaz; karşılaştırma yalnız ölçüm olabilir. API sürümleri değişiyorsa model adı, tarih ve ayarlar kayıt altına alınır.

Otomatik, deterministik ölçülebilen görevlerde cevap anahtarı ve verifier kullanılır. Açık uçlu faydalılık/akıcılık gibi görevlerde yalnız modelin kendi puanı yeterli değildir; bağımsız kör insan değerlendirmesi yoksa “GPT/Gemini’den üstün” sonucu çıkarılmaz. Tek bir benchmark ailesindeki kazanım genel üstünlük değildir. Bu belge şu anda böyle bir sonuç veya ölçüm ileri sürmez.

## 9. Uygulama planı

### Faz 0 — Ölçülebilir taban

Mevcut retrieval ve decoder yolları ayrıştırılır; `/api/chat` `output_mode` alanı ile gerçek mekanizmayı bildirir. Küçük, lisanslı train/dev/test fixture’ı ve sabit test komutu hazırlanır. Mevcut yanıt davranışı baseline olarak kaydedilir.

### Faz 1 — Tek kayıt üzerinde üretim prototipi

LIR’de ÇZNA state geçişi, ileri-sonraki ve ters-önceki bayt tahmin başlıkları, STOP ve streaming çıktı uygulanır. Küçük corpus üzerinde model eğitilir; aynı konudaki görülmemiş ifade, yeni bileşim ve yalnız prompt’ta verilen öncüllerden çıkarım testleri eklenir. Retrieval devre dışıyken de çıktı alınması ve gelecek-bayt sızıntısı olmaması kabul kriteridir. Bu faz “genel dil modeli” diye yayınlanmaz.

### Faz 2 — Değişken bağlam ve checkpoint

Büyüyen input/output buffer’ları, sürümlü checkpoint, checksum, resume ve deterministik seed eklenir. Bozuk checkpoint, allocation failure, kesilmiş UTF-8 ve yarım eğitim koşusu test edilir.

### Faz 3 — Kanıt Defteri ve doğrulanabilir işlemler

Önce aritmetik, miktar/birim, açık öncül çıkarımı ve çelişki/eksik-bilgi görevleri tipli kayıtlara bağlanır. Üretici yalnız doğrulayıcıdan geçmiş sonuçları kanıtlanmış gibi sunabilir. Açık uçlu yorumlama ayrı ve daha sonra değerlendirilir.

### Faz 4 — Otonom eğitim ve veri kalite kapıları

Koşu yöneticisi, preapproved kaynak allowlist’iyle state-machine ingest/train/evaluate/promote/rollback/resume döngüsünü insan müdahalesi olmadan çalıştırır. Dedupe, kaynak-temelli split, sızıntı denetimi ve verifier tarafından doğrulanabilir test üretimi otomatikleşir. Modelin kendi cevabı hiçbir zaman kendi doğruluk etiketi olmaz. Sürekli insan etiketi gerekmemesi hedeflenir; lisans/source policy başlangıçta yapılandırılır. İlk ürün yayını ve “yüksek kalite” iddiası için bağımsız değerlendirme gerekir; doğrulama yoksa koşu unattended çalışabilir ama genel kalite iddiası yayımlanmaz.

### Faz 5 — Veri kapsamı ve kalite

Lisansı ve kaynağı önceden onaylanmış çeşitli Türkçe corpus’lar eklenir; held-out split’ler kaynak ve yakın-kopya ailesine göre ayrılır. Yeni konu/bileşim ve prompt’taki öncüllerden çıkarım testleri, özel hardcoded soru-cevap tabloları olmadan kurulur. Her kaynakta okunan/kabul edilen/reddedilen baytlar ve kayıp değerleri raporlanır.

### Faz 6 — Ölçekleme

Tek blok RAM checkpoint’i shard/paging’e taşınır. Büyük corpus için sequential I/O ve indeksleme ölçülür; parametre shard’ları için eğitim/inference çalışma kümesi, peak RSS, disk throughput ve recovery test edilir. PB/TB hedefi ancak gerçek donanımda, gerçek veriyle end-to-end test edilirse destek kapsamına alınır.

## 10. Açık riskler ve yapılmaması gereken iddialar

- Özgün isim veya matematiksel gösterim, algoritmanın yeni, üstün ya da kararlı olduğunu kanıtlamaz.
- Harici model kullanmamak, tek başına daha iyi kalite sağlamaz.
- Akıcı metin, doğru bilgi veya muhakeme kanıtı değildir.
- Tüm corpus baytlarının okunması, her cümlenin birebir hatırlanacağı anlamına gelmez.
- Parametre sayısı, kayıt sayısı veya training loss tek başına zekâ ölçüsü değildir.
- Lisanssız/kaynağı belirsiz metin, “genel kültür” diye veri kümesine eklenmez.
- Üretim ağırlıklardan geliyor diye her cevap olgusal doğru olmaz; Kanıt Defteri ve held-out testler bu riski azaltır ama sıfırlamaz.
- Bu belge gerçek bir uygulama, benchmark sonucu, frontier model veya insan düzeyi akıl yürütme iddiası değildir.

## 11. Mevcut kodla entegrasyon sınırı

- `ai/src/noema_pretrain.lir`: mevcut alan eğitimi ve exemplar retrieval; ÇZNA üretim başlığı olarak değerlendirilmemeli.
- `ai/src/noema_decoder.lir`: mevcut sabit boyutlu decoder; değişken uzunluklu otoregresif hedefi karşılamıyor.
- `ai/chat_site_backend.lir`: bugünkü cevap/telemetry adaptörü; model ağırlıklarından serbest üretim kanıtı değil.
- Yeni modüller ayrı namespace ve checkpoint sürümüyle eklenmeli. Mevcut `.nps` checkpoint’i yeni generator ağırlıkları içeriyormuş gibi yorumlanmamalı.

**Belge sonucu:** Öneri, retrieval’dan ağırlık tabanlı bayt üretimine ve kanıtla denetlenen cevaplamaya geçiş için uygulanabilir, aşamalı bir tasarımdır. Kalite hedefleri iddia değil, test kapılarıdır. Önce Faz 0–2 tamamlanıp ölçülmeli; ancak sonra genel dil yeterliliği hakkında konuşulabilir.
