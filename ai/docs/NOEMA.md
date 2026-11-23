# NOEMA — LIR ile uygulanan karar-kapıları

**Durum:** v3.9. LIR’de uygulanıp test edilenler: contract/evidence/scheduler/data/capability/memory-scope/release-lifecycle/task-execution guard’ları, bounded exact-rule inference/proof checks, scoped volatile record store, deficit-guided curriculum/split checks, metadata/provenance/group-split doğrulayan canonical JSONL→hashed bag-of-words decoder, SEL fit/evaluation/confusion metrics ve örnek metin setinde uçtan uca LIR eğitimi. Eğitim verisinin kanonik kaydı `noema.example.v2` JSONL; LIR eğitim girişleri canonical JSONL kayıtlarını doğrudan okur. Bu, genel amaçlı veya üretime hazır AI framework’ünün tamamı değildir.

## Uygulanmış dilimler

| Dilim | LIR modülü | Test |
|---|---|---:|
| Contract checks | `ai/src/noema_contracts.lir` | `ai/tests/15_noema_contracts.lir` |
| Evidence levels | `ai/src/noema_evidence.lir` | `ai/tests/16_noema_evidence.lir` |
| Budget scheduler | `ai/src/noema_scheduler.lir` | `ai/tests/17_noema_scheduler.lir` |
| Dataset gates | `ai/src/noema_dataset.lir` | `ai/tests/18_noema_dataset.lir` |
| Capability graph and scoped routing | `ai/src/noema_capability.lir` | `ai/tests/19_noema_capability.lir` |
| Memory scope, retention and deletion guards | `ai/src/noema_memory.lir` | `ai/tests/20_noema_memory.lir` |
| Release lifecycle guards | `ai/src/noema_release.lir` | `ai/tests/21_noema_release.lir` |
| Bounded task execution lifecycle and budget admission | `ai/src/noema_execution.lir` | `ai/tests/22_noema_execution.lir` |
| Exact-rule inference, derivation/proof-certificate validation, explicit query status | `ai/src/noema_reasoning.lir` | `ai/tests/23_noema_reasoning.lir`–`ai/tests/27_noema_proof_certificate.lir` |
| Bounded volatile scoped record store (append/find/tombstone/compact with expiry and vacated-cell clearing) | `ai/src/noema_store.lir` | `ai/tests/28_noema_store.lir`, `ai/tests/29_noema_store_compaction.lir` |
| Deficit-guided curriculum frontier selection and group split leakage check | `ai/src/noema_training.lir` | `ai/tests/30_noema_training_data.lir` |
| Multimodal episode/artifact admission guards (text/image/audio/video/spatial metadata; no media decoder) | `ai/src/noema_multimodal.lir` | `ai/tests/37_noema_multimodal.lir` |
| Typed-array SEL fit, split-isolated evaluation, epoch history, dev-only early stopping and best-weight restoration | `ai/src/noema_fit.lir`, `ai/src/ledger.lir` | `ai/tests/31_noema_fit.lir` |
| Strict integer CSV to Q32.32 feature/target arrays | `ai/src/noema_csv.lir` | `ai/tests/32_noema_csv.lir` |
| CSV ingestion → fit → held-out split evaluation smoke pipeline | composed LIR modules | `ai/tests/33_noema_training_pipeline.lir` |
| Read and train on manually encoded 11-record example-set task labels; confusion matrix | `ai/train_example.lir`, `ai/noema-training/example_training.csv` | `ai/tests/34_noema_example_training.lir` |
| Canonical `noema.example.v2` JSONL ingestion, grouped-leakage validation, hashed bag-of-words → SEL fit/evaluation | `ai/noema-training/example_text.v2.jsonl`, `ai/src/noema_text_jsonl.lir`, `ai/train_text_example.lir` | `ai/tests/35_noema_text_ingest.lir`, `ai/tests/36_noema_text_training.lir`, `ai/tests/41_jsonl_reader.lir` |
| Turkish synthetic canonical JSONL generation → LIR JSONL decoder/classifier + SELTOK07 response weights → JSONL held-out inference/export/audit | `ai/src/noema_corpus.lir`, `ai/src/noema_decoder.lir`, `ai/train_turkish_corpus.lir` | `ai/tests/40_noema_decoder.lir`, `ai/noema-training/evaluate_turkish_run.py` |
| Bounded LIR-native f64 tensor primitives: row-major matmul/softmax/layer norm, stable exp/log, causal single-head attention, cross-entropy | `ai/src/noema_tensor.lir` | `ai/tests/43_noema_tensor.lir` |
| In-process LIR causal byte sequence model with attention/MLP forward pass, assistant-target-masked output-head SGD, greedy generation, checksum-validated local checkpoint IO | `ai/src/noema_lm.lir` | `ai/tests/44_noema_lm.lir` |
| Matrix-free incremental prompt/answer memory: 256-bit hashed unigram+ordered-bigram signatures, open-addressed exact-prompt updates, bounded Jaccard retrieval with abstention threshold | `ai/src/noema_sparse_memory.lir` | `ai/tests/45_noema_sparse_memory.lir` |

The sparse memory learns new exemplars in O(prompt bytes) using open addressing and retrieves by scanning compact signatures (O(record count), no matrix multiply). One local native microbenchmark, single-entry 4k-capacity table / 10k repeated operations, measured about 4.0 μs per exact update and 3.7 μs per exact query. This synthetic case does not predict latency at 65k records, and lexical retrieval is not general reasoning or broad language intelligence.

`noema_lm.lir` is an early LIR-only prototype: its attention/embedding trunk is seeded and frozen; only the output projection is updated. `train_noema_lm_demo.lir` uses four hand-written examples and produces visibly poor text. It proves the local train/save/load/infer plumbing, not high-quality chat. Full end-to-end backpropagation, a vetted dialogue corpus, stronger optimizers, scale/performance evaluation and migration of the remaining 11 Python utilities are still outstanding.

The current `python3 ai/run_tests.py` suite passes 115 fixture/backend executions; backend coverage varies for legacy fixtures. The Turkish run has a separate persisted-artifact audit. Passing these tests verifies bounded decision logic and the tested synthetic pipeline only; it does not establish general language ability or that all documented service guards have production backends.

## Dataset format and quality status

The training text records now follow the architecture's `noema.example.v2` episode fields: version, id, group key, seed, task/capability/risk, raw user text, explicit context/unknowns, target decision/text, evidence kind, validator, review state, safety and provenance. The LIR JSONL decoder reads canonical `noema.example.v2` records directly and validates split/decision/risk/provenance/review fields, duplicate IDs, training consent, and group leakage across train/dev/test before building hashed text features. The split is grouped by rule family (train 9, dev 1 causal, test 1 safety), correcting the earlier arithmetic/planning cross-split contamination and correcting plan-002's invalid unreachable label.

Quality is still limited: all records are synthetic, no human/dual review, the corpus is only 11 rows, and dev/test each contain one example. JSONL syntax is framed by the LIR JSONL reader; a schema-specific decoder extracts the current training fields, but this is not a general-purpose JSON AST parser and does not cryptographically authenticate payload/license claims. This follows the schema shape, not the architecture's full production data-quality bar.

## Türkçe eğitim varyantları (JSONL)

`ai/noema-training/turkish_variants.v1.jsonl` 21 ayrı kayıt şemasını aynı sürümlü JSONL zarfında örnekler; `turkish_composite_examples.v1.jsonl` bunları çoklu-hedefli kompozisyonlara birleştiren 21 örnek içerir: supervised diyalog, tercih çifti, araç çağrı döngüsü, açıklama isteme, kanıta dayalı akıl yürütme, retrieval/atıf, kod düzeltme+test, güvenlik/onay, multimodal hizalama, zamansal seri, yapılandırılmış tablo dönüşümü ve kalibrasyon değerlendirmesi. Şema gerekçeleri ve kalite kuralları `ai/noema-training/DATASET_VARIANTS.md`; doğrulama `validate_variants.py` ve `test_validate_variants.py` içindedir. Kayıtlar sentetik ve gözden geçirilmemiş örneklerdir; benchmark veya insan verisi değildir.

Ana Türkçe ve örnek metin eğitim girişleri artık canonical JSONL dosyalarını doğrudan okur; LIR standard library'sindeki `jsonl` modülü bounded line framing, AI decoder ise `noema.example.v2` için şema doğrulamalı alan çıkarımı sağlar. Eski TSV decoder/test fixture'ları geriye dönük uyumluluk için tutulmuştur; ana eğitim akışında kullanılmaz.

## Multimodal status (Stage 24)

`noema_multimodal.lir` defines fail-closed LIR guards for closed MIME codes, modality-specific declared dimensions/duration/sample rate/channels/frame rate, a 64 MiB artifact cap, capability/budget admission, and result status. Host adapters must supply independently verified hash/consent outcomes and sniff actual payload bytes. This is metadata validation only. It does **not** decode image/audio/video/spatial payloads, perform OCR/ASR/generation, align synchronized streams, or provide a multimodal model. The 17/17 fixture checks exercise these guards, not media understanding.

## Not implemented

A bounded numeric regression fit loop updates an existing SEL block from contiguous typed Q32.32 arrays; evaluation is split-selective and non-updating. It supports fixed-epoch training and dev-only early stopping that restores the best validation weights. Strict integer CSV decoding can produce arrays, and synthetic CSV→fit→held-out evaluation plus a Turkish JSONL→LIR fit→checkpoint reload→held-out inference run are executable. The schema-specific JSONL text path uses deterministic hashed token-count features; it is not a general JSON model interface. The response head is prompt-feature-conditioned position-wise byte counting, not an autoregressive language model. There is no general JSONL parser or broad text-target extraction, optimizer selection beyond the implemented update rule, experiment manifest IO, cryptographic artifact provenance/signatures, general neural model architecture, GPU/accelerator execution, or production deployment. Stage 16 curriculum selectors consume typed arrays but are not yet wired into fit. Persistent episodic/semantic/procedural storage, retrieval/CAG backend, task executor, connector/tool runtime, authenticated artifact pipeline, release/deployment service, and production observability remain unimplemented. `ai/train_example.lir` reads the manually encoded `example_training.csv`; the encoding is a toy task-cue-to-decision classification problem whose feature directly exposes the class cue. The observed 1-record test score is not evidence of natural-language generalization, and 11 records are not adequate for model-quality claims. The full framework is therefore not production- or general-AI-training-ready, even though this specific LIR numeric demo is executable. They do not train or serve an AI model. Integration and end-to-end tests remain outstanding.

The new framework decision logic in this increment is LIR. Existing Python dataset validator/auditor remains host-side tooling and was not expanded into runtime functionality. No external dependency was added. LIR guard return values are not proof of authorization, persistence, deletion, release safety, or model quality; those require real backends and end-to-end verification.

No claims are made here about intelligence, frontier parity, originality, speed, or training cost. Such properties require defined benchmarks and measured results.
