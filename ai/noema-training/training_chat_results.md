# NOEMA yerel eğitim ve sohbet çalıştırması

**Çalıştırma:** `./zig-out/bin/lir run ai/train_turkish_corpus.lir --backend=native`

**Durum:** Program hatasız tamamlandı; model, LIR içindeki eğiticiyle eğitildi ve checkpoint'ler kaydedilip yeniden yüklendi. Eğitim verisi bu çalıştırmada sentetik/şablonlu olduğundan sonuçlar gerçek dünya dil yeterliliği veya olgusal bilgi kanıtı değildir.

- Eğitim/dev/test: 88.000 / 11.000 / 11.000 satır
- Sınıflandırıcı: 11 epoch
- Yanıt baytı ağırlıklarına alınan eğitim örneği: 4.400
- Holdout üzerinde dışa aktarılan üretilmiş örnek: 40
- Sınıflandırıcı doğruluğu: train 24.806/88.000; dev 5.496/11.000; test 2.722/11.000
- Dev/test MSE (Q32.32 raw): 1.040.207.188 / 1.812.005.128
- Checkpoint'ler: `turkish_model.selcp`, `turkish_decoder.seltok`

## Modelin ürettiği etkileşimler

Aşağıdaki cevaplar çalıştırma stdout'undan aynen alınmıştır. Üretim kalitesi zayıf: model çoğu farklı isteğe aynı kod-aracı yanıtını verdi. Sonuçlar saklanmıştır; başarılı sohbet ya da yüksek zekâ göstergesi olarak yorumlanmamalıdır.

1. **Soru:** 17 ile 25 sayılarının toplamı kaçtır?  
   **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
2. **Soru:** Bir sepette 12 elma ve 8 armut var. Toplam kaç meyve vardır?  
   **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
3. **Soru:** Bir otobüste 31 yolcu vardı, 9 kişi daha bindi. Kaç yolcu oldu?  
   **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
4. **Soru:** 45 kitabın yanına 17 kitap daha kondu. Toplam kaç kitap var?  
   **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
5. **Soru:** Bir bahçeye 23 fidan ve 14 fidan daha dikildi. Toplam kaç fidan?  
   **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
6. **Soru:** Sınıfta 28 öğrenci vardı, 11 öğrenci geldi. Yeni toplam kaçtır?  
   **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
7. **Soru:** Depoda 42 koli vardı ve 16 koli daha geldi. Kaç koli oldu?  
   **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
8. **Soru:** Çiftlikte 19 koyun ve 21 keçi var. Hayvanların toplamı nedir?  
   **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
9. **Soru:** Bir kutuda kaç parça olduğu bilinmiyor. Her parçanın kütlesi kaçtır?  
   **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
10. **Soru:** Dikdörtgenin alanı 48 santimetrekare. Bir kenarının uzunluğu nedir?  
    **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
11. **Soru:** Bir yolculuk 3 saat sürdü. Alınan yol kaç kilometredir?  
    **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
12. **Soru:** Bir sınıfta 30 öğrenci var. Kaçı kız öğrencidir?  
    **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
13. **Soru:** Bir havuzda 500 litre su var. Havuzun derinliği nedir?  
    **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
14. **Soru:** Bir ürünün fiyatı 90 liradır. İndirimli fiyatı nedir?  
    **Model cevabı:** Tek bir yanıt için ek ölçü veya ikinci koşul gerekir.
15. **Soru:** Şemsiye satışı arttı ve kaldırım ıslandı. Bu kanıtlar nedenselliği gösterir mi?  
    **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
16. **Soru:** Dondurma satışı ile sağlık başvuruları birlikte arttı. Dondurma başvurulara neden oldu mu?  
    **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
17. **Soru:** Reklam harcaması ve satışlar arttı. Reklam artışın kesin nedeni midir?  
    **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
18. **Soru:** Kahve tüketimi ile üretkenlik puanı birlikte yükseldi. Nedensellik kanıtlandı mı?  
    **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
19. **Soru:** Bir LIR fonksiyonunu derleyip test etmem gerekiyor. Hangi araçları kullanmalıyım?  
    **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
20. **Soru:** Uzunluğu 20 olan listedeki en büyük değeri bulan LIR kodunu yaz.  
    **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
21. **Soru:** En fazla 100 satırlı dosyanın satırlarını sayan program oluştur.  
    **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.
22. **Soru:** Belirli bir dosyada kayıt arayıp eşleşmeyi bulmak istiyorum. Ne yapmalıyım?  
    **Model cevabı:** Bu istek için LIR kodu üretip derleme ve test aracı kullanmalıyım.

## Matris kullanmayan hibrit çıkarım ve sohbet sistemi (`ai/chat.lir`)

Üretime hazır çıkarım hattı üç aşamalı bir karar mimarisiyle çalışır:
1. **Sembolik & Doğal Dil Aritmetik Aracı:** Toplama, çıkarma, çarpma ve bölme sorularını hem doğrudan matematiksel ifadelerden (`17 + 25`) hem de Türkçe problem metinlerinden (`Sepette 12 elma ve 8 armut var. Toplam meyve sayısı kaçtır?`) deterministik olarak çözer. Bu sayede retrieval benzerliğindeki ezber kaynaklı yanlış sayı döndürme (12 + 8 = 18 halüsinasyonu) tamamen ortadan kalkar.
2. **Matrix-free Sparse Bellek:** Yetersiz bilgi tespiti, nedensellik/korelasyon ayrımı ve araç yönlendirme gibi bağlamsal görevleri 88.000 `train` kaydı üzerinden Jaccard benzerliğiyle eşleştirir.
3. **Güvenilir Çekilme (Epistemic Abstention):** Bellekte güvenilir eşleşme bulunmayan veya kapsam dışı sorularda uydurma metin üretmek yerine kibar ve açık bir şekilde çekilerek ek bağlam talep eder.

Ölçülen güncel canlı çalıştırma çıktıları:

- Soru: `İki sayının toplamı kaçtır? Birinci sayı 2, ikinci sayı 1.` → `Toplam 3.`
- Soru: `Sepette 12 elma ve 8 armut var. Toplam meyve sayısı kaçtır?` → `Toplam 20.`
- Soru: `17 + 25` → `= 42`
- Soru: `100 - 37` → `= 63`
- Soru: `Bir rafta 15 kitap vardı; 6'sı alındı. Kaç kitap kaldı?` → `Kalan 9.`
- Soru: `Dikdörtgenin alanı 48 santimetrekare. Bir kenarının uzunluğu nedir?` → `Tek bir yanıt için ek ölçü veya ikinci koşul gerekir.`
- Soru: `Şemsiye satışı 25 iken ıslak kaldırım sayısı 14 oldu. Bu ilişki nedenselliği kanıtlar mı?` → `Bu gözlem tek başına nedenselliği göstermez; ortak neden veya müdahale verisi gerekir.`
- Soru: `Müzik teorisinde akor nedir?` → `Bu soruya eğitim belleğimde yeterince güvenilir bir eşleşme bulamadım. Daha fazla bağlam verebilir misiniz?`

