# Türkçe eğitim verisi: JSONL varyant tasarımı v1

`turkish_variants.v1.jsonl` her satırda tek UTF-8 JSON nesnesi olacak şekilde 21 görev varyantı içerir. `turkish_composite_examples.v1.jsonl` ise bunlardan ikişerini birden taşıyan 21 multi-objective şema örneği içerir; bütün 21 atomik varyant en az bir kompozisyonda yer alır. Bu bileşimlerin `split` değeri `catalog` olduğundan eğitim/eval verisi olarak kullanılmamalıdır. Ortak zarf; `schema`, kararlı `id`, `group_key`, `split`, `variant`, `task`, `messages`, hedef/etiket ve `provenance` alanlarını kullanır. Göreve özgü alanlar ayrı nesnelerde tutulur; boş veya anlamı olmayan alanlar her satıra doldurulmaz. Büyük nesneler tek satırdır, satır içi yeni satırlar JSON escape edilir.

## Kapsanan varyantlar

| `variant` | Ek alanlar | Öğrettiği / denetlediği iş |
| --- | --- | --- |
| `supervised_dialogue` | `target.kind/text`, kanıt ve karar etiketi | Kullanıcı isteğinden denetlenmiş yanıta |
| `preference_pair` | sıralı `candidates`, `chosen/rejected` | Aynı istemde doğru ve yanlış stratejiyi karşılaştırma |
| `tool_call_cycle` | `tool_calls`, tool mesajı, `tool_trace` | Araç seçimi → çağrı → sonuç kontrolü → yanıt |
| `clarification` | `missing_slots` | Eksik önkoşulları sorma; varsayım uydurmama |
| `grounded_reasoning` | `facts`, desteklenen adımlar, `unknowns` | İddia–kanıt bağını ve belirsizliği koruma; gizli düşünce zinciri hedefi değil |
| `retrieval_grounded` | sorgu, kaynak/span, claim citations | Kaynağa dayalı yanıt ve atıf bütünlüğü |
| `code_test_repair` | dil, önce/sonra, patch niyeti, testler/sonuç | Kod düzeltme ve çalıştırılmış test ölçütü |
| `safety_refusal_or_confirm` | yetki/ortam/geri alınabilirlik, politika eylemi | Riskli eylemde engelleme veya açıklama/onay isteme |
| `multimodal_alignment` | mesaj parçaları, artifact referansı, hizalama/region | Metin–medya bağlama; payload yerine izinli/hash’li referans |
| `temporal_sequence` | zaman damgaları, değer/missing mask, horizon, tahmin aralığı | Zaman sırası, gözlem sınırı ve belirsizlik |
| `structured_table_transform` | tiplendirilmiş kolon/satır, null politikası, işlem | Tablo üzerinde yeniden üretilebilir dönüşüm |
| `calibration_judgment` | beklenen davranış, rubric ve skor alanı | Kaynak yokken abstain etme ve kalibrasyon değerlendirmesi |
| `natural_language_understanding` | intent, slot, kısıt ve eksik alan | İfade → yapılandırılmış anlam çerçevesi |
| `interpretation_with_alternatives` | olası okumalar ve kanıtları | Belirsizliği tek doğruymuş gibi kapatmama |
| `calculation_with_units` | typed givens, denklem, birim kontrolleri | Hesaplama + boyut/birim doğrulama |
| `plan_with_dependencies` | hedef, bağımlı adımlar, başarı ve risk | Kısıtlı plan üretme ve sıra tutarlılığı |
| `constrained_writing_revision` | tür, ton, uzunluk, checklist ve son metin | Yazma → sınır kontrolü → düzeltme |
| `translation_localization` | dil/locale, kayıt, terim sözlüğü | Anlam ve biçim koşullarını koruyarak çeviri |
| `faithful_summarization` | kaynak belge, zorunlu olgular, citation spans | Kaynağa sadık özetleme ve izlenebilirlik |
| `dialogue_state_tracking` | slot state, teyitli/eksik alanlar, next action | Çok turlu bağlamı güncelleme ve doğru soru |
| `instruction_hierarchy` | öncelikli kurallar, çatışma ve seçilen eylem | Çakışan talimatları güvenli çözme |

## Veri kalitesi ve split kuralları

- Bölme satır bazında değil `group_key`/yakın kopya ailesi bazında yapılır; aynı aile train/dev/test'e yayılamaz. `test`, yalnız raporlama içindir.
- Her örnek `source`, `license`, `review` ve `seed` bilgisi taşır. Mevcut 21 kayıt açıkça `synthetic_template` ve `unreviewed`; gerçek, insan onaylı veri gibi sunulmamalıdır.
- Preference kayıtlarında chosen/rejected ve sıralar farklıdır; tool kayıtlarında sonuç mesajı ve doğrulama işareti bulunur; retrieval/reasoning atıfları mevcut kanıta bağlanır; kod için test sonucu; zaman serisi için gözlem sınırı ve missing mask zorunludur.
- Medya payload'ları JSONL içine gömülmez. Hash/izinli object-store referansı ve hizalama anotasyonu saklanır; içerik anotasyonunun doğruluğu ayrıca incelenmelidir.
- Sentetik train/dev/test örnekleri tek başına kalite kanıtı değildir. Her görev ailesinde gerçek, lisanslı ve insan gözden geçirmeli veri eklenmeden model genellemesi iddia edilmez.

## Kaç tür/kompozisyon?

- Tasarlanmış atomik görev türü: **21**.
- Bu 21 türden yinelenmeyen, sırasız, boş olmayan alt kümelerin kuramsal sayısı: `2^21 - 1 = 2.097.151` (tekli türler dahil).
- En az iki tür içeren kuramsal alt küme: `2.097.151 - 21 = 2.097.130`.
- Yalnız tam ikili seçim sayısı: `C(21, 2) = 210`.
- Bunların hepsi anlamlı/uyumlu eğitim örneği değildir. Örneğin tablo+hesap makinesi doğal birleşirken alakasız güvenlik+hava tahmini bileşimi anlamsız olabilir. Uygulanabilir kombinasyon sayısı görev tanımına, etiketlerin uyumuna, lisans/kanıt koşullarına ve değerlendirme protokolüne bağlıdır; bu yüzden matematiksel 2.097.151 sayısı “geçerli veri türü” iddiası değildir.
- Mevcut kompozit dosya tüm kombinasyonlar değil, her atomik türü kapsayan **21 örnek kompozisyondur**. Generator aynı kaynak örneklerden yeniden üretilebilir.

Kontrol komutları:

```sh
python3 ai/noema-training/validate_variants.py
cd ai/noema-training && python3 -m unittest test_validate_variants.py
```

## Sınırlar

Bu JSONL dosyası format/varyant kataloğu ve doğrulama fixture'ıdır; 21 satır büyük ölçekli eğitim korpusu değildir. Ana Türkçe corpus generator ve classifier/decoder eğitim hattı ile küçük metin eğitim örneği artık canonical JSONL kullanır; artık üretilen/izlenen TSV projection yoktur. LIR'de eski TSV decoder ve onun inline geriye dönük uyumluluk fixture'ları hâlâ durur. Genel JSON AST parser, tüm varyantlara ortak optimizer ve escape/unicode tam round-trip desteği bu JSONL reader'ın kapsamı değildir. Bu dosyanın eklenmesi tek başına LLM/NCM/LMM/Mamba sistemlerinden daha iyi sonuç verdiği anlamına gelmez; bu tür kıyas için eşit veri, bütçe, metrik ve held-out benchmark gerekir.
