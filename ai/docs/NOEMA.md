# NOEMA — LIR ile uygulanan karar-kapıları

**Durum:** v2.6. LIR’de uygulanıp test edilenler: contract/evidence/scheduler/data/capability/memory-scope/release-lifecycle/task-execution guard’ları. Bu, tasarlanan NOEMA AI framework’ünün tamamı değildir.

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

The latest LIR suite passes all 61 fixture/backend executions (including 15 Stage 8 assertions); backend coverage varies for legacy fixtures. Zig build tests, 21 Python standard-library validator/audit tests, and example validation also pass. These results verify bounded decision logic only; they do not establish that corresponding services exist.

## Not implemented

No complete inference/reasoning engine, model training loop, tokenizer/parser, persistent episodic/semantic/procedural store, retrieval/CAG backend, task executor, connector/tool runtime, authenticated artifact pipeline, release/deployment service, or production observability/operations layer is provided by these guard modules. They do not train or serve an AI model. Integration and end-to-end tests remain outstanding.

The new framework decision logic in this increment is LIR. Existing Python dataset validator/auditor remains host-side tooling and was not expanded into runtime functionality. No external dependency was added. LIR guard return values are not proof of authorization, persistence, deletion, release safety, or model quality; those require real backends and end-to-end verification.

No claims are made here about intelligence, frontier parity, originality, speed, or training cost. Such properties require defined benchmarks and measured results.
