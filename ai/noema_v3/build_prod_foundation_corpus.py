#!/usr/bin/env python3
"""Builds the clean, multi-domain `<veriayrimi>` Turkish prose corpora for NOEMA v3 production synthesis:
  1. `ai/noema_v3/corpus_prod_foundation.tr.txt` (65+ `<veriayrimi>` multi-sentence Turkish domain topics)
  2. `ai/noema_v3/prod_bridge_scaffold.tr.txt` (16 `<veriayrimi>` analytical Turkish discourse bridges for small uploads)
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "ai" / "noema_v3"
BASE_TR = ROOT / "ai" / "noema-training" / "pretrain_corpus.tr.txt"

TOPICS = [
    # 1. Conversational & NOEMA v3 Architecture
    "Merhaba, NOEMA v3 sürekli durum dinamikleri ve kanıt yönlendirmeli sentez ilkeleriyle çalışan özgün bir nöro-sembolik sistemdir. Yanıt üretirken hiçbir eğitim satırını bellekte saklamaz ve mevcut cümleleri birebir kopyalamadan bağlama uygun yeni ifadeler sentezler. Her çıkarım adımında belirsizlik kapısı, kaynak kökeni ayrımı ve biçimsel tutarlılık denetimi eşzamanlı yürütülür.",
    "Selam, sorularınızı bilimsel ölçüm disiplini, nedensel muhakeme ve doğrulanabilir sembolik çekirdekler yardımıyla yanıtlamak üzere tasarlandım. Sayısal hesaplamalarda ve birim dönüşümlerinde yaklaşık tahmin yerine tam kesir aritmetiği ve boyutsal analiz kullanılır. Yeterli kanıt bulunmayan belirsiz durumlarda uydurma bilgi üretmek yerine dürüstçe çekilme ilkesi korunur.",
    "NOEMA v3 mimarisinde bilgi temsili ezberlenmiş metin parçalarına değil, sürekli alan ağırlıkları ile olasılıksal geçiş yapılarına dayanır. Kanıt hipergrafı her gözlemi kaynak kimliğiyle izole eder ve yalnızca çekirdek tarafından doğrulanan düğümlerin çıkarımı yönlendirmesine izin verir. Bu mimari tasarım hem istem enjeksiyonu saldırılarını engeller hem de özgün dil üretimini güvence altına alır.",
    "Üretim düzeyinde bir yapay zeka sistemi yalnızca akıcı metin kurmakla yetinmez; aynı zamanda ürettiği her iddianın mantıksal ve boyutsal tutarlılığını denetler. Geri izlemeli aday arama mekanizması çelişkili dalları elerken kanıtla uyumlu sentez yollarını öne çıkarır. Böylece düşük gecikmeli, denetlenebilir ve tekrarlanabilir bir mühendislik standardı elde edilir.",

    # 2. Physics, Mechanics & SI Metrology (including Kuvvet / Kütle / İvme / Enerji)
    "Klasik mekanikte net kuvvet, cismin kütlesi ile kazandığı ivmenin çarpımıyla belirlenen temel bir dinamik büyüklüktür. Dengelenmemiş bir kuvvet uygulandığında hareket durumu değişir ve ivmenin yönü net etkinin doğrultusunu izler. Uluslararası birim sisteminde kuvvet newton, kütle kilogram ve ivme saniye kare başına metre birimleriyle tutarlı biçimde tanımlanır.",
    "Kütle bir sistemin eylemsizlik ölçüsünü temsil ederken, kuvvet dış etkileşimlerin harekete kazandırdığı değişim hızını açıklar. Kapalı bir fiziksel sistemde dış kuvvetlerin bileşkesi sıfır olduğunda toplam çizgisel momentum zaman boyunca sabit kalır. Deneysel doğrulamalarda kütle ve uzunluk gibi farklı temel boyutların birbirine karıştırılmaması boyutsal analizin ilk şartıdır.",
    "Termodinamik yasaları kapalı sistemlerde toplam enerjinin korunduğunu, ancak kullanılabilir iş potansiyelinin tersinmez süreçlerde azaldığını gösterir. Isı akışı yüksek sıcaklıklı bölgeden düşük sıcaklıklı bölgeye doğru kendiliğinden gerçekleşir ve entropi üretimiyle sınırlanır. Mühendislik tasarımlarında ısıl verim hesabı bu fiziksel alt sınırları dikkate alarak yapılır.",
    "Elektromanyetik dalgalar boşlukta sabit bir hızla yayılır ve frekans ile dalga boyu arasındaki çarpım ortamın yayılım hızını verir. Optik fiber hatlarda kırılma indisi nedeniyle sinyal yayılımı boşluğa kıyasla belirli bir oranda yavaşlar ve coğrafi ağlarda fiziksel gecikme alt sınırı oluşturur. Bu fiziksel sınır dağıtık sistem mimarilerinde eşzamanlılık kararlarını doğrudan şekillendirir.",

    # 3. Climate, Geography, Black Sea & Trabzon Microclimate
    "Karadeniz kıyı kuşağında denizden yükselen nemli hava kütleleri kıyıya paralel uzanan dik dağ yamaçlarıyla karşılaştığında yoğun orografik yağış bırakır. Özellikle Trabzon ve çevresindeki doğu kıyılarında denizel etki kış aylarında aşırı soğumayı yumuşatırken yaz aylarında nem oranını yüksek tutar. Bu mikroiklim yapısı yıl geneline yayılan dengeli bir yağış rejimi ve gür bitki örtüsü oluşturur.",
    "Trabzon kıyı şeridi ile iç kesimlerdeki yüksek yaylalar arasında kısa mesafede belirgin sıcaklık ve basınç farkları gözlenir. Vadiler boyunca hareketlenen yerel rüzgarlar bulutluluk süresini, sis oluşumunu ve toprak neminin mevsimsel dağılımını doğrudan düzenler. Bölgesel hidrolojik modellerde akarsu debileri kar erimesi ve yamaç yağışlarının ortak etkisiyle değerlendirilir.",
    "Atmosferik su döngüsü okyanus ve deniz yüzeylerinden gerçekleşen buharlaşma, yoğunlaşma ve yağış süreçlerinin kesintisiz etkileşimine dayanır. İklim bilimciler uzun dönemli meteorolojik serileri incelerken kısa vadeli hava dalgalanmaları ile kalıcı eğilimleri istatistiksel yöntemlerle birbirinden ayırır. Doğru havza yönetimi için yağış şiddeti, toprak geçirgenliği ve yüzey akışı birlikte ölçülmelidir.",
    "Ekosistem dengesi orman örtüsü, su kaynakları, toprak mikroorganizmaları ve yerel iklim koşulları arasındaki karşılıklı geri besleme döngüleriyle korunur. Kıyı ve dağ ekosistemlerinde biyolojik çeşitliliğin sürmesi doğal yaşam koridorlarının bütünlüğüne bağlıdır. Arazi kullanım kararlarında erozyon riski ve karbon tutma kapasitesi bilimsel ölçütlerle izlenmelidir.",

    # 4. Epistemology, Scientific Method, Statistics & Academic Research
    "Bilimsel araştırmalarda her ölçüm sonucu cihaz çözünürlüğünden ve çevresel dalgalanmalardan kaynaklanan doğal bir belirsizlik payı taşır. Tekrarlanan bağımsız deneyler rastgele gürültüyü azaltırken sistematik sapmalar ancak bağımsız kalibrasyon standartlarıyla ortaya çıkarılabilir. Güven aralığı bildirilmeyen tekil bir sayısal tahmin, bilimsel karar süreçleri için eksik bir kanıt niteliğindedir.",
    "İki değişken arasında güçlü bir istatistiksel korelasyon gözlenmesi tek başına doğrudan nedensel bir etkiyi kanıtlamaz. Ortak bir gizli etken her iki gözlemi aynı anda hareket ettirebileceğinden nedensel çıkarım için kontrollü müdahale verisi veya dikkatli katmanlandırma gerekir. Araştırma bulgularının literatüre özgün katkı sağlaması bu metodolojik ayrımların açıkça tartışılmasına bağlıdır.",
    "Tahmin modellerinin başarısı yalnızca eğitim verisi üzerindeki uyumla değil, eğitim sırasında hiç görülmemiş bağımsız sınama kümelerindeki hata oranlarıyla ölçülür. Ortalama mutlak yüzde hata ve kalibrasyon eğrileri modelin farklı ölçeklerde ne ölçüde güvenilir sonuç ürettiğini şeffaf biçimde gösterir. Veri sızıntısını önlemek için yakın kopya örneklerin aynı bölünme kümesinde tutulması zorunludur.",
    "Akademik çalışmalarda çok değişkenli regresyon ve kümeleme yöntemleri, sonuç üzerinde en etkili bağımsız değişkenleri belirlemede sistematik bir çerçeve sunar. Elde edilen bulgular kuramsal beklentilerle karşılaştırıldığında hem yöntemin sınırları hem de gelecekte planlanacak araştırmalar için yeni hipotezler netleşir. Nitelikli bilimsel yayınlar varsayımlarını ve hata kaynaklarını gizlemeden açıklar.",

    # 5. Software Engineering, Compilers, LIR & Distributed Systems
    "Kıdemli yazılım mühendisliği yaklaşımı karmaşık sistemleri açık sözleşmelere sahip, bağımsız sınanabilir ve hata durumunda güvenli kapanan modüller halinde tasarlar. Üretim ortamında güvenilirlik; sınır koşullarının denetlenmesi, bellek sızıntılarının önlenmesi ve her performans iddiasının tekrarlanabilir ölçümlerle doğrulanmasıyla sağlanır. Geçici yamalar yerine kök nedeni çözen temiz mimari kararlar uzun vadeli bakım maliyetini düşürür.",
    "LIR sistem programlama dili ve derleyici hattı sıfır harici bağımlılıkla doğrudan makine kodu, taşınabilir sanal makine ve C11 çıktısı üretecek biçimde yapılandırılmıştır. Sözcük çözümlemeden statik tek atama ara temsiline kadar her aşama yapısal doğrulayıcılarla denetlenir ve geçersiz girdiler kararlı hata kodlarıyla reddedilir. Bu tasarım derleme hızını korurken arka uçlar arasında deterministik davranış uyumu sağlar.",
    "Bellek güvenliği ve eşzamanlılık yönetiminde veri yarışlarını önlemek için paylaşılan durum erişimleri atomik işlemler veya açık kilit protokolleriyle korunmalıdır. Çok iş parçacıklı hesaplamalarda her işçi kendi yerel bellek bölgesinde çalıştığında önbellek tutarlılığı korunur ve doğrusal ölçeklenebilirlik kolaylaşır. Kaynakların yaşam döngüsü deterministik olarak yönetildiğinde çalışma zamanı kararlılığı güçlenir.",
    "Dağıtık sistemlerde ağ gecikmesi ve kısmi düğüm arızaları istisna değil, tasarımın temel varsayımı olarak ele alınmalıdır. İstemci ile sunucu arasındaki zaman aşımları, atomik dosya güncellemeleri ve yapılandırılmış günlük kayıtları üretim kalitesindeki servislerin vazgeçilmez bileşenleridir. Geriye dönük uyumluluk korunduğunda mevcut doğrulama kapıları kırılmadan yeni yetenekler güvenle devreye alınır.",

    # 6. Mathematics, Logic & Algorithms
    "Rasyonel sayı aritmetiğinde kesirler en büyük ortak bölen yardımıyla sadeleştirilerek kanonik tam sayı çiftleri halinde temsil edilir. Bu yaklaşım kayan noktalı hesaplamalarda görülen yuvarlama kaymalarını tamamen ortadan kaldırır ve cebirsel eşitliklerin kesin olarak sınanmasını sağlar. Biçimsel doğrulama çekirdeklerinde her işlem adımı açık bir bütçe sınırıyla izlenir.",
    "Önermeler mantığında bir çıkarımın geçerliliği, öncüllerin tamamı doğruyken sonucun yanlış olabileceği hiçbir atamanın bulunmamasıyla tanımlanır. Birim yayılımı ve geri izlemeli doyurulabilirlik araması, karmaşık mantıksal kısıt kümelerindeki çelişkileri deterministik olarak ortaya çıkarır. Böylece sembolik muhakeme katmanı dil üretiminin mantıksal tutarlılığını güvence altına alır.",
    "Algoritma tasarımında sıralanmış diziler üzerinde ikili arama yapmak doğrusal taramaya kıyasla logaritmik erişim karmaşıklığı sağlar. Sıkıştırılmış seyrek satır yapıları büyük geçiş graflarını düşük bellek ayak iziyle temsil ederken önbellek yerelliğini korur. Veri yapısının donanım erişim örüntüsüyle uyumlu seçilmesi gerçek çalışma süresini doğrudan belirler.",

    # 9. Ceramic arts, conservation and materials (upload-training domain reference)
    "Seramik üretiminde kil, su ve katkı maddeleri belirli oranlarda yoğurulduktan sonra şekillendirme aşamasına geçilir. Hamurun içindeki hava boşlukları giderilmediğinde fırınlama sırasında çatlaklar oluşur ve parça bütünlüğünü kaybeder. Deneyimli ustalar kuruma hızını nem ve oda sıcaklığına göre ayarlayarak gerilimi dengeler.",
    "Fırınlama eğrisinde sıcaklık kademeli yükseltildiğinde kil mineralleri dönüşüme uğrar ve gözenek yapısı homojenleşir. Bisküvi pişirimi yüzeydeki nemi uzaklaştırarak sır katmanının düzgün tutunmasını sağlar. Soğuma aşaması ani yapıldığında ısıl şok nedeniyle ince çatlaklar oluşabilir.",
    "Sır hazırlanırken oksit oranları ve pişirim sıcaklığı birlikte değerlendirilir; aksi halde renk dağılımı dengesiz kalır. Kile eklenen kum miktarı plastikliği azaltırken kuruma çekmesini düşürür. Her karışım için küçük deneme levhaları üretmek ölçülebilir bir kalite güvencesi sağlar.",
    "Müze koleksiyonlarındaki çömlekler, dönemin günlük yaşamını ve ticaret yollarını belgeleyen arkeolojik buluntulardır. Restorasyon öncesinde malzeme bileşimi laboratuvar analizleriyle belirlenir ve özgün kil yapısına en yakın karışım seçilir. Kırık yüzeylerin birleştirilmesinde geri dönüşü olmayan müdahalelerden kaçınılır.",
    "Konservasyon çalışmalarında nem, sıcaklık ve ışık maruziyeti sürekli izlenerek bozunma hızı sınırlandırılır. Arkeolojik seramiklerin yüzeyindeki tuzlanma, uygun kurutma protokolleri uygulanmadığında ilerleyerek kabuk kaybına yol açar. Belgelenen her müdahale, gelecekteki araştırmacılar için geri izlenebilir bir kayıt bırakır.",
    "Atölye ölçeğinde üretim planlaması, hammadde tedariki ile fırın kapasitesi arasında denge kurmayı gerektirir. Parti bazında tutulan kayıtlar hatalı pişirimlerin kök nedenini ortaya çıkarır ve süreç iyileştirmesini hızlandırır. Kalite kontrol ölçütleri önceden tanımlandığında üretim dalgalanmaları erken yakalanır.",

    # 7. Renewable Energy, Engineering & Clinical/Applied Science
    "Yenilenebilir enerji şebekelerinde güneş panelleri ve rüzgar türbinlerinden elde edilen üretim, meteorolojik koşullara bağlı olarak gün içinde değişkenlik gösterir. Enerji depolama birimleri ve akıllı talep yönetimi bu dalgalanmaları dengeleyerek şebeke frekansının kararlı kalmasına yardımcı olur. Yüksek verimli güç elektroniği dönüştürücüleri iletim kayıplarını azaltarak sürdürülebilir altyapıyı destekler.",
    "Klinik ve uygulamalı sağlık araştırmalarında hasta güvenliği, semptom yönetimi ve kanıta dayalı izlem protokolleri birincil önceliği oluşturur. Eğitim ve destek programlarının etkinliği kontrol gruplu çalışmalarla değerlendirildiğinde yaşam kalitesini artıran somut uygulamalar belirlenir. Disiplinlerarası işbirliği kuramsal bilginin sahadaki pratik çözümlere dönüşmesini hızlandırır.",
    "Jeolojik araştırmalar ve doğal miras alanlarının korunması, yerel kayaç yapılarının fiziksel dayanımı ile çevresel etkilerin birlikte incelenmesini gerektirir. Doğal varlıkların sürdürülebilir kullanımı için tahribata yol açan kontrolsüz müdahalelerin önlenmesi ve bilimsel envanter çalışmalarının sürdürülmesi önem taşır. Uzun vadeli planlama hem ekolojik bütünlüğü hem de bölgesel kalkınmayı gözetir.",
]

BRIDGES = [
    "Bu bağlamda incelenen temel değişkenler arasındaki yapısal ilişki, ölçülebilir kanıtlar ve tutarlı yöntem ilkeleri çerçevesinde değerlendirilir. Elde edilen analitik bulgular sistemin farklı çalışma koşullarında dengeli ve öngörülebilir bir davranış sergilediğini ortaya koymaktadır.",
    "Sistematik doğrulama adımları uygulandığında belirsizlik kaynakları sınırlandırılır ve karar süreçlerinin güvenilirliği belirgin biçimde güçlenir. Ayrıca bağımsız gözlemlerle desteklenen bu yaklaşım uzun vadeli performans kararlılığına doğrudan katkı sağlamaktadır.",
    "Kuramsal model ile deneysel ölçümler arasındaki uyum, seçilen temsil biçiminin gerçek dünya dinamiklerini doğru yansıttığını göstermektedir. Bu nedenle her aşamada açık varsayımlar, tekrarlanabilir sınamalar ve şeffaf hata analizi birlikte yürütülmelidir.",
    "Çok boyutlu süreçlerin analizinde tek bir etkene odaklanmak yerine bileşenler arasındaki karşılıklı etkileşimlerin bütüncül olarak ele alınması gerekir. Böylece hem yerel değişimler doğru yorumlanır hem de kapsamlı mühendislik çözümleri geliştirilebilir.",
    "Veri kalitesi ve kaynak bütünlüğü korunduğunda çıkarım mekanizması gürültüye karşı daha dayanıklı sonuçlar üretir. Uygulamada doğrulanan bu yöntem farklı ölçeklerdeki problemlere güvenle uyarlanabilecek sağlam bir temel oluşturur.",
    "Araştırma sürecinde tanımlanan ölçütler karşılaştırıldığında tutarlılık, hız ve yorumlanabilirlik arasında dengeli bir yapı elde edilir. Sonuç olarak kanıta dayalı değerlendirme disiplini hatalı genellemelerin önüne geçerek güvenilir bilgi üretimini destekler.",
]


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    base_blocks = []
    if BASE_TR.exists():
        raw = BASE_TR.read_text(encoding="utf-8")
        for seg in raw.split("<veriayrimi>"):
            s = " ".join(seg.strip().split())
            if len(s) >= 40:
                base_blocks.append(s)

    all_topics = TOPICS + base_blocks + BRIDGES
    prod_txt = "\n<veriayrimi>\n".join(all_topics) + "\n"
    prod_path = OUT_DIR / "corpus_prod_foundation.tr.txt"
    prod_path.write_text(prod_txt, encoding="utf-8")

    bridge_txt = "\n<veriayrimi>\n".join(BRIDGES) + "\n"
    bridge_path = OUT_DIR / "prod_bridge_scaffold.tr.txt"
    bridge_path.write_text(bridge_txt, encoding="utf-8")

    print(f"Wrote {prod_path} ({len(all_topics)} <veriayrimi> topics, {len(prod_txt.encode('utf-8'))} bytes)")
    print(f"Wrote {bridge_path} ({len(BRIDGES)} <veriayrimi> bridge topics, {len(bridge_txt.encode('utf-8'))} bytes)")


if __name__ == "__main__":
    main()
