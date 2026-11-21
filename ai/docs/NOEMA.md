# NOEMA — LIR ile uygulanan karar-kapıları

**Durum:** v3.8. LIR’de uygulanıp test edilenler: contract/evidence/scheduler/data/capability/memory-scope/release-lifecycle/task-execution guard’ları, bounded exact-rule inference/proof checks, scoped volatile record store, deficit-guided curriculum/split checks, strict integer-CSV decoder, textual TSV→hashed bag-of-words decoder, SEL fit/evaluation/confusion metrics ve örnek metin setinde uçtan uca LIR eğitimi. Bu, genel amaçlı veya üretime hazır AI framework’ünün tamamı değildir.

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
| Typed-array SEL regression fit, split-isolated evaluation and epoch loss history | `ai/src/noema_fit.lir`, `ai/src/ledger.lir` | `ai/tests/31_noema_fit.lir` |
| Strict integer CSV to Q32.32 feature/target arrays | `ai/src/noema_csv.lir` | `ai/tests/32_noema_csv.lir` |
| CSV ingestion → fit → held-out split evaluation smoke pipeline | composed LIR modules | `ai/tests/33_noema_training_pipeline.lir` |
| Read and train on manually encoded 11-record example-set task labels; confusion matrix | `ai/train_example.lir`, `ai/noema-training/example_training.csv` | `ai/tests/34_noema_example_training.lir` |
| Textual TSV prompts/labels → hashed bag-of-words → SEL fit/evaluation | `ai/src/noema_text.lir`, `ai/train_text_example.lir`, `ai/noema-training/example_text.tsv` | `ai/tests/35_noema_text_ingest.lir`, `ai/tests/36_noema_text_training.lir` |

The latest LIR suite passes all 103 fixture/backend executions (including Stage 21 text ingestion and Stage 22 file-backed text training checks); backend coverage varies for legacy fixtures. Zig build tests, 21 Python standard-library validator/audit tests, and example validation also pass. These results verify bounded decision logic only; they do not establish that corresponding services exist.

## Not implemented

A bounded numeric regression fit loop now updates an existing SEL block from contiguous typed Q32.32 arrays; evaluation is split-selective and non-updating. Strict integer CSV decoding can produce these arrays, and an end-to-end synthetic CSV→fit→held-out evaluation fixture passes. This establishes runnable numeric and small textual TSV training paths, not turnkey training on repository JSONL: the TSV loader builds hashed token-count features, but there is no JSONL parser or broad text-target extraction, checkpoint save/restore, optimizer selection, experiment manifest IO, artifact provenance binding, general model architecture, GPU/accelerator execution, or production deployment. Stage 16 curriculum selectors consume typed arrays but are not yet wired into fit. Persistent episodic/semantic/procedural storage, retrieval/CAG backend, task executor, connector/tool runtime, authenticated artifact pipeline, release/deployment service, and production observability remain unimplemented. `ai/train_example.lir` reads the manually encoded `example_training.csv`; the encoding is a toy task-cue-to-decision classification problem whose feature directly exposes the class cue. The observed 1-record test score is not evidence of natural-language generalization, and 11 records are not adequate for model-quality claims. The full framework is therefore not production- or general-AI-training-ready, even though this specific LIR numeric demo is executable. They do not train or serve an AI model. Integration and end-to-end tests remain outstanding.

The new framework decision logic in this increment is LIR. Existing Python dataset validator/auditor remains host-side tooling and was not expanded into runtime functionality. No external dependency was added. LIR guard return values are not proof of authorization, persistence, deletion, release safety, or model quality; those require real backends and end-to-end verification.

No claims are made here about intelligence, frontier parity, originality, speed, or training cost. Such properties require defined benchmarks and measured results.
