# Türkçe eğitim verisi: JSONL varyant tasarımı v1

`turkish_variants.v1.jsonl` her satırda tek UTF-8 JSON nesnesi olacak şekilde 12 görev varyantı içerir. Ortak zarf; `schema`, kararlı `id`, `group_key`, `split`, `variant`, `task`, `messages`, hedef/etiket ve `provenance` alanlarını kullanır. Göreve özgü alanlar ayrı nesnelerde tutulur; boş veya anlamı olmayan alanlar her satıra doldurulmaz. Büyük nesneler tek satırdır, satır içi yeni satırlar JSON escape edilir.

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

## Veri kalitesi ve split kuralları

- Bölme satır bazında değil `group_key`/yakın kopya ailesi bazında yapılır; aynı aile train/dev/test'e yayılamaz. `test`, yalnız raporlama içindir.
- Her örnek `source`, `license`, `review` ve `seed` bilgisi taşır. Mevcut 12 kayıt açıkça `synthetic_template` ve `unreviewed`; gerçek, insan onaylı veri gibi sunulmamalıdır.
- Preference kayıtlarında chosen/rejected ve sıralar farklıdır; tool kayıtlarında sonuç mesajı ve doğrulama işareti bulunur; retrieval/reasoning atıfları mevcut kanıta bağlanır; kod için test sonucu; zaman serisi için gözlem sınırı ve missing mask zorunludur.
- Medya payload'ları JSONL içine gömülmez. Hash/izinli object-store referansı ve hizalama anotasyonu saklanır; içerik anotasyonunun doğruluğu ayrıca incelenmelidir.
- Sentetik train/dev/test örnekleri tek başına kalite kanıtı değildir. Her görev ailesinde gerçek, lisanslı ve insan gözden geçirmeli veri eklenmeden model genellemesi iddia edilmez.

Kontrol komutları:

```sh
python3 ai/noema-training/validate_variants.py
cd ai/noema-training && python3 -m unittest test_validate_variants.py
```

## Sınırlar

Bu JSONL dosyası format/varyant kataloğu ve doğrulama fixture'ıdır; 12 satır büyük ölçekli eğitim korpusu değildir. Mevcut `train_turkish_corpus.lir` ana ölçekli pipeline'ının TSV projection bağımlılığı henüz bu katalog tarafından kaldırılmış değildir. JSONL-only talebi için sonraki entegrasyon adımı, LIR corpus parser/decoder ve eğitim girişini bu canonical JSONL'ye taşımak, sonra TSV üretimini ve TSV testlerini kaldırmaktır. Bu dosyanın eklenmesi tek başına LLM/NCM/LMM/Mamba sistemlerinden daha iyi sonuç verdiği anlamına gelmez; bu tür kıyas için eşit veri, bütçe, metrik ve held-out benchmark gerekir.
