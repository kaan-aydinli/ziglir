# NOEMA v3 Namespace (Phases 0–9 Complete Architectural Implementation)

This directory is the **isolated** pure-LIR namespace for the NOEMA v3 architecture:
**EK-HNB (Entropy-Folded Hierarchical Causal Memory) + KHG (Pointer-Addressed Evidence/Hypothesis Graph)**.

## Isolation rules

- New modules live under `ai/src/noema_v3/`, standalone v3 CLIs & adapters at `ai/noema_v3_infer_cli.lir`, `ai/noema_v3_train_cli.lir`, `ai/noema_v3_promote_cli.lir`, and `ai/noema_v3_chat_backend.lir`, and runtime/data/checkpoint/report/audit artifacts under `ai/noema_v3/`.
- Legacy paths remain functional and strictly isolated — they are **not** NOEMA v3 weight generation:
  - `ai/src/noema_pretrain.lir` — legacy exemplar/retrieval pretrain state (NPS checkpoints).
  - `ai/src/noema_decoder.lir` — legacy fixed decoder.
  - `ai/chat_site_backend.lir` — legacy backend; emits `output_mode=legacy_retrieval_exemplar`.
- Old `.nps` checkpoints or retrieval paths MUST NOT be reported as `noema_v3_weight_generation` and are rejected fail-closed by `NPG-v3` loaders.
- Zero external LLM/LMM/Transformer/Mamba/SSM/NCM, external tokenizer/BPE/vocab, external embedding/vector DB, or external autodiff/optimizer libraries are used; all forward/backward math, memory state, checkpoints, verification kernels, and inference operate in 100% LIR over raw UTF-8 bytes.

## Implemented status (this branch)

### Phase 0 (Complete — `python3 ai/noema_v3/phase0_audit.py`)
- [x] Isolated namespace (`ai/src/noema_v3/`, `ai/noema_v3/`) and contract (`noema_v3_contract.lir`).
- [x] `/api/chat`, `/api/health`, frontend inspector (`ÜRETİM MODU`), and legacy backend report real `output_mode` (`legacy_retrieval_exemplar`).
- [x] Leakage-free split policy, manifest schema, and executable fail-closed guard (`ai/noema_v3/manifest_guard.py` + sample & disjoint held-out `NV3D` v3 binary SoA shard fixtures).
- [x] Deterministic reasoning/causality/finite-diff fixture contracts (`ai/noema_v3/fixtures/`).

### Phase 1 (Complete — `python3 ai/noema_v3/phase1_audit.py`)
- [x] Pure-LIR math & packed 4-byte IEEE-754 `binary32` (`fp32`) storage primitives (`noema_v3_math.lir`), including finite/NaN/Inf guards.
- [x] Hand-written forward + backward LIR kernels (`noema_v3_kernels.lir`): `RMSNorm`, `L2Norm`, `Linear`, `SwiGLU`, `CausalDepthwiseConv1D`, single-pass weighted raw-UTF-8 `SoftmaxCrossEntropy` + `bpb` conversion.
- [x] `fp32`-state Householder-Delta fast associative memory (`HAİB`, `noema_v3_haib.lir`) with `f64` dot-product accumulation, associative overwrite, and document `reset` isolation.
- [x] Two-level segment checkpointing (`noema_v3_seg_ckpt.lir`) reducing saved state count from $O(T)$ to $O(T/C_1 + C_1/C_2 + C_2)$, verified for exact `f64` gradient agreement, `fp32` checkpoint drift $\le 10^{-5}$, zero future leakage, and zero cross-document gradient leakage across `reset` boundaries.
- [x] Pure-LIR preconditioned optimizer `LIR-PreOpt` (`noema_v3_preopt.lir`): Newton-Schulz polar orthogonalized momentum for 2D matrices, bias-corrected diagonal second-moment preconditioning for 1D vectors, global L2 clipping, linear-warmup + cosine LR schedule, and fail-closed NaN/Inf rejection.
- [x] Differential test suites (`ai/tests/noema_v3_01..03.lir`) passing across `native`, `vm`, and `c`.

### Phase 2 (Complete — `python3 ai/noema_v3/phase2_audit.py`)
- [x] Pure-LIR `NV3D` v3 binary Structure-of-Arrays (`SoA`) shard writer & fail-closed loader (`noema_v3_soa.lir`) with 64-bit FNV-1a checksums, provenance/reset/weight validation, and `read_docs == accepted_docs + rejected_docs` accounting.
- [x] 3-level Entropy-Folded Hierarchical Causal Memory (`EK-HNB`, `noema_v3_ek_hnb.lir`: `Bayt -> Yerel Yama -> Olay/Önerme`) with reset-aware causal depthwise conv, $O(1)$ lazy-decay causal byte-surprise folding router ($g^{(2)}_t \le g^{(1)}_t$), two-level segment-checkpointed `HAİB` memories, provenance authority gate, exact-causality reverse-prompt `HAİB` head (`leak_001..003`), and full analytical backward verified against central finite differences across all 30 parameter slices.
- [x] Pure-LIR `NPG-v3` binary checkpoint serializer & fail-closed validator (`noema_v3_checkpoint.lir`) supporting `f64` and packed `binary32` (`fp32`) payloads, `arch_hash` lock, FNV-1a64 integrity verification, and strict `.nps` rejection.
- [x] Streaming SoA trainer/evaluator & raw UTF-8 weight generator (`noema_v3_trainer.lir`), verified for both train and disjoint held-out `bpb` descent across `native`, `vm`, and `c` (`ai/tests/noema_v3_04_ek_hnb_causality.lir`, `ai/tests/noema_v3_05_soa_npg_bpb.lir`).

### Phase 3 (Complete — `python3 ai/noema_v3/phase3_audit.py`)
- [x] Pointer-addressed Evidence & Hypothesis Graph (`KHG`, `noema_v3_khg.lir`) with epistemic states (`OBSERVED`, `HYPOTHESIS`, `VERIFIED`, `REFUTED`, `ABSTAIN`), byte-span pointer addressing (never copying stored spans as answers), fail-closed provenance authority isolation, and authoritative continuous summary conditioning.
- [x] Pure-LIR step-budgeted deterministic verification kernels (`noema_v3_verify_math.lir`, `noema_v3_verify_logic.lir`, `noema_v3_khg.lir`):
  - Arbitrary-precision signed `BigInt` (base-$10^9$ limbs) & exact canonical `Rational` (`GCD`-reduced).
  - 7-base-dimension `SI Unit Algebra` (`[m, kg, s, A, K, mol, cd]`) with dimensional contradiction detection and canonical derived symbol resolution.
  - Propositional `Constraint/Logic` DPLL solver with deletion-based minimal unsat-core extraction.
  - `Temporal Consistency` & interval supersession kernel with exact Gregorian ISO-8601 validation.
  - `Evidence / Epistemic Abstain Gate` and `Provenance Isolation` prompt-injection quarantine kernel.
- [x] Differential verification across `native`, `vm`, and `c` (`ai/tests/noema_v3_06_khg_and_kernels.lir`).

### Phase 4 (Complete — `python3 ai/noema_v3/phase4_audit.py`)
- [x] Verified self-play curriculum admission filter & training loop (`noema_v3_selfplay_gate.lir`): rejects unverified/contradicted model hypotheses (`loss_weight = 0`), admitting only deterministic-kernel-certified derivations into SoA curriculum training.
- [x] Compositional multi-kernel KHG chain evaluator, pure-LIR Expected Calibration Error (`ECE`), and strict lexicographic acceptance gate `Q = (integrity_safety, verified_reasoning, unsupported_claim_rate, compositional_gen, calibration_ece, heldout_bpb, compute_cost)` where lower-priority metrics (`heldout_bpb`, `compute_cost`) cannot mask upper-gate failures or regressions.
- [x] Standalone pure-LIR `NPG-v3 + KHG` inference CLI (`ai/noema_v3_infer_cli.lir`) emitting `output_mode=noema_v3_weight_generation` or `output_mode=noema_v3_weight_generation_abstain` (`ai/tests/noema_v3_07_selfplay_and_q_gate.lir`).

### Phase 5 (Complete — `python3 ai/noema_v3/phase5_audit.py`)
- [x] Locked multi-domain raw-UTF-8 Turkish/English corpus (`ai/noema_v3/corpus_locked/`, 12 documents across strictly disjoint `source_family` and `near_duplicate_cluster_id` splits: `train_soa` 6 docs, `dev_soa` 3 docs, `test_soa` 3 docs) passing `manifest_guard.py --audit-split`.
- [x] Pure-LIR pretraining + kernel-verified self-play CLI (`ai/noema_v3_train_cli.lir`) producing SHA-256-pinned `NPG-v3` binary checkpoint `ai/noema_v3/checkpoints/noema_v3_locked.npg3` (`8,828` parameters, `36` preconditioned steps; `train bpb: 7.988 -> 5.960`, `dev bpb: 7.984 -> 6.112`, locked `test bpb: 7.983 -> 6.083`, `ECE: 0.1683`, all 7 `Q` gates passing) and report `ai/noema_v3/reports/phase5_locked_q_report.json`.
- [x] RFC-3629 byte-validity masked weight generator (`nv3_trainer_generate_utf8_valid`) + isolated pure-LIR chat backend adapter (`ai/noema_v3_chat_backend.lir`) wired into `apps/noema-chat` (`modelId="noema_v3"`) alongside untouched legacy `ai/chat_site_backend.lir` (`legacy_retrieval_exemplar`), verified across `native`, `vm`, and `c` (`ai/tests/noema_v3_08_phase5_e2e.lir`).

### Phase 6 (Complete — `python3 ai/noema_v3/phase6_audit.py`)
- [x] Pointer-addressed local `NV3D` v3 `SoA` span grounding (`noema_v3_ground_promote.lir`: `nv3_grounded_khg_infer`, `nv3_trainer_generate_utf8_khg`, `nv3_verify_no_verbatim_soa_copy`): attaches resonant local spans strictly as `OBSERVED` + `UNTRUSTED_SOURCE` pointer nodes `(doc_id, span_off, span_len)`, quarantines injected spans (`promoted_to_system_policy == 0`), promotes certified spans only via `nv3_khg_apply_kernel_verdict`, conditions `EK-HNB` readout via `nv3_khg_authoritative_summary`, and deterministically enforces zero verbatim span copying.
- [x] Candidate-to-production lexicographic `Q`-gate promotion engine (`ai/noema_v3_promote_cli.lir`, `ai/noema_v3/generate_phase6_report.py`): continued preconditioned training (`36 -> 48` steps) promoted `ai/noema_v3/checkpoints/noema_v3_promoted.npg3` (`locked test_bpb: 6.083383 -> 5.739479`, `locked test_ece: 0.168306 -> 0.118530`) while blocking upper-gate regression masking fail-closed (`ai/tests/noema_v3_09_grounding_and_promotion.lir`).

### Phase 7 (Complete — `python3 ai/noema_v3/phase7_audit.py`)
- [x] Universal `<veriayrimi>` topic-separation framing across `ai/src/noema_pretrain.lir`, `ai/src/noema_v3/noema_v3_soa.lir` (`nv3_soa_pack_veriayrimi`), Turkish corpora, and `apps/noema-chat` (`server.mjs`, `pretraining.html`).
- [x] Unit-stride row-SAXPY + 4-way ILP unrolled linear forward/backward kernels (`noema_v3_kernels.lir`, IEEE-754 bit-exact with scalar dot products).
- [x] Paged zero-parse document-window `SoA` streamer (`nv3_soa_stream_window`) + multi-threaded OS worker fork-join data-parallel engine (`noema_v3_scale_mt.lir`, `@thread_create` + `@thread_join`) with canonical ordered gradient reduction (`W=1` vs `W=3` `max_grad_diff < 1e-11`), backed by atomic active-thread refcounting and locked `LIVE_MMAP` region reclamation in `src/bootstrap/ir_codegen.zig` (`ai/tests/noema_v3_10_phase7_mt_multishard.lir`).

### Phase 8 (Complete — `python3 ai/noema_v3/phase8_audit.py`)
- [x] Trainable zero-keyword neural epistemic regime proposal head (`nv3_regime_head_fwd_bwd` in `noema_v3_proof_search.lir`) operating directly on raw UTF-8 byte-structure & transition moments, verified against central finite differences (`< 1e-6`).
- [x] Pure-LIR byte-stream formal claim extractor & pointer-addressed `KHG` verifier across all 4 deterministic kernels (`Rational/BigInt`, `Dimensional SI`, `Propositional DPLL Entailment`, `ISO-8601 Temporal`).
- [x] Step-budgeted `K`-candidate proof-guided backtracking search (`nv3_proof_guided_search_candidates`) that strictly prunes lower-NLL refuted fluency traps, logs refutations in `KHG`, and abstains honestly (`NOEMA_V3_OUTPUT_WEIGHT_GENERATION_ABSTAIN`) when all branches fail or budget expires (`ai/tests/noema_v3_11_phase8_proof_search.lir`, live telemetry in `ai/noema_v3_chat_backend.lir`).

### Phase 9 (Complete — `python3 ai/noema_v3/phase9_audit.py`)
- [x] Cluster-disjoint `<veriayrimi>`-packed multi-shard multi-domain corpus (`ai/noema_v3/corpus_v3_multishard/`: `train_shard_0`, `train_shard_1`, `val_soa`, `test_soa`; 24 manifest entries, zero split/cluster/SimHash leakage verified by `manifest_guard.py`).
- [x] Multi-shard data-parallel scaled `NPG-v3` training & side-by-side locked benchmark (`ai/noema_v3_phase9_bench_cli.lir`, `ai/noema_v3/checkpoints/noema_v3_scaled.npg3`, `12,404` parameters vs `8,840` baseline: locked `test_bpb = 5.929397` vs `7.456400`, `-1.527003 bpb`; locked `test_ece = 0.197147` vs `0.246032`, `-0.048885`; `12/12` neuro-symbolic proof benchmark; strict lexicographic `Q` dominance) recorded in `ai/noema_v3/reports/phase9_full_benchmark_report.json` with `"external_frontier_claim": false` (`ai/tests/noema_v3_12_phase9_scaled_bench.lir`).
- [x] Salted SHA-256-committed blinded human-evaluation packet (`ai/noema_v3/reports/phase9_blind_eval_packet.jsonl` + `phase9_blind_eval_key_sha256.json`) containing zero model-identity strings.

## Output mode contract

| Mode | Meaning | Legacy path allowed |
|---|---|---|
| `legacy_retrieval_exemplar` | Exemplar/retrieval excerpt from legacy NOEMA-Phi path | Yes (only this) |
| `noema_v3_weight_generation` | Weight-generated NOEMA v3 response backed by verified KHG gate | No |
| `noema_v3_weight_generation_abstain` | Weight-generated NOEMA v3 honest abstain (insufficient/quarantined evidence) | No |

## Acceptance discipline ("Ölçmeden İddia Yok")

Passing `phase0_audit.py` .. `phase9_audit.py` (`257/257` automated checks) certifies **architectural, numerical, causality, provenance, kernel-verification, verified self-play admission, KHG pointer grounding, `<veriayrimi>` multi-shard data-parallel OS-thread scaling, neuro-symbolic proof-guided search, blinded evaluation packaging, and isolated `noema-chat` integration invariants** across all LIR backends (`native`, `vm`, `c`). All measured checkpoint capacities, compute wall times, `bpb`, `ECE`, and `Q` vectors are reported transparently with `"external_frontier_claim": false`; external frontier superiority is never claimed without matched external-scale compute and blind evaluation.
