# NOEMA-Φ v3.0 implementation plan and acceptance gates

This plan is tied to the user-provided specification copied verbatim to
[`NOEMA-PHI-v3-user-spec.md`](NOEMA-PHI-v3-user-spec.md). It is deliberately
separate from the aspirational architecture: a component is not complete because
its name or equation appears in code. Every completion claim needs executable
invariant/behavior tests and measured behavior on held-out data.

## Current baseline (2026-11-24)

- The LIR-only field prototype and bounded symbolic reasoning modules run without
  an imported LLM, LMM, Transformer, Mamba/SSM, or NCM.
- `noema_pretrain_infer` still returns a corpus-derived stored line selected by
  byte-feature resonance. It is retrieval, not open-ended generation.
- `noema_decoder.lir` is a small class-conditioned, position-wise byte head. It
  is not an autoregressive language model and is not evidence of general-purpose
  language ability.
- Existing rule-based reasoning is bounded to its explicit symbolic rules; it
  is not general-purpose reasoning.
- The currently implemented core is not fully conformant to NOEMA-Φ v3.0. An
  geometry/objective slice is in `ai/src/noema_phi_geometry.lir` (Woodbury,
  Randers, U(1) kinetic density, selected local/global free-energy terms and
  discrete Yamabe penalty). A scalar-mode implicit-midpoint wave kernel with a
  tested discrete Lyapunov decrement is in `ai/src/noema_phi_wave.lir`; a separate
  exact three-regime scalar ETD kernel is in `ai/src/noema_phi_etd.lir`. The exact
  top-K branch-and-bound selector is in `ai/src/noema_phi_atlas.lir` (worst-case
  O(C·D), not strict O(log C)). The atlas selector and ETD mode are now connected
  to the pretraining route; the standalone wave and Randers/objective kernels are
  not. A bounded adaptive macro planner and automatic `.nbin` training path now
  use stage, record length, recent surprise/plateau and early-exit telemetry; the
  publisher checks counts, macro metrics and out-of-domain abstention before
  promotion. None completes its specification section. The detailed audit is in
  [`NOEMA-ARCHITECTURE-STATUS.md`](NOEMA-ARCHITECTURE-STATUS.md).

## Section-by-section conformance gates

| User specification | Required implementation before marking complete | Required evidence | Baseline |
|---|---|---|---|
| §1 Zero-modern-stack | Dependency/build audit proving inference and training have no prohibited external model/runtime dependency; LIR is the executable core. | Reproducible clean build plus dependency/import scan and runtime test. | Partial: current LIR paths avoid those model stacks; repository-wide and end-to-end proof is still needed. |
| §2 Metrics | Implement specified measurable metrics with defined units and repeatable collection; do not label throughput as intelligence. | Deterministic metric tests and documented benchmark protocol. | Missing. |
| §3 Topological atlas / Randers-Finsler / Woodbury | Implement card atlas, bridges, the specified metric/drift, stable low-rank inverse and convexity projection. | Geometry identities, inverse-vs-direct numerical checks, convexity and scaling tests. | Partial: `noema_phi_geometry.lir` implements O(R·D) inverse application, g-norm drift projection, Randers norm, convex five-mode mixing and complex U(1)-covariant kinetic density; pointwise bridge penalty is available. `noema_phi_atlas.lir` provides exact top-K resonance ranking and is called by pretraining `np_select`; the integration currently rebuilds the bound tree per selection, so total routing remains O(C·D). Tests 58/61 cover metric, drift, bridge and routing fixtures; 46–57 exercise connected pretraining on native/VM/C. Strict O(log C), Randers objective integration and active cross-card bridge graph remain. |
| §4 Unified free energy | Implement each specified energy/potential term and their common objective with consistent units. | Term-by-term reference fixtures, finite-difference checks and objective decomposition tests. | Partial: local V_top, V_validation, V_symbol, V_protection, V_abstention and source-work terms; global syntax-charge, keyword-lock, bounded-context information terms; and discrete Yamabe regularizer are implemented/tested. The complete spatially integrated objective and variational gradients are not yet wired together. |
| §5 PDE / Lyapunov | Implement the complex second-order field dynamics and protection term; prove/check the stated Lyapunov decrease under declared assumptions. | Small-system analytic comparisons plus adversarial long-run stability/property tests. | Partial: `noema_phi_wave.lir` implements a spatially uniform quadratic complex mode with fixed source and Hermitian gyro term using implicit midpoint; test 59 verifies ΔE=−2γΔt|Π_mid|², zero-damping conservation, 200-step monotonicity and rejection transactionality on native/VM/C. Spatial Randers operators, nonlinear full-objective forces, protection masks and noise remain uncoupled. |
| §6 Strang IMEX-ETD | Implement the specified operator split, analytical ETD regimes and L1/L2 macro/micro execution. | Against analytic/reference solutions, convergence-order tests and stiff-regime stability tests. | Partial: `noema_phi_etd.lir` implements the analytic under/critical/overdamped matrix for one linear mode and is connected to pretraining between nonlinear radial half-kicks. Test 60 checks semigroup consistency in all three regimes, undamped energy conservation, damped monotonicity and invalid-step rejection; tests 46–57 exercise the integrated path on native/VM/C. DCT blocks, geometry-coupled nonlinear forces, protection propagator, L1/L2 tiling and bridge synchronization remain. |
| §7 Envelope theorem / CAWR / plasticity | Implement adjoint and CAWR integrals, the single plasticity law and three-regime gate/margin table. | Gradient/adjoint checks on small cases, trajectory invariants and gate-boundary tests. | Missing; local energy-delta gating is only a heuristic. |
| §8 Raw-byte injector / topology lock / solver | Implement the exact four-ary byte boundary, cavity selection and topological/syntactic charge constraints. | UTF-8/raw-byte boundary tests, conservation/invariant tests and calibrated abstention tests. | Partial only: raw bytes and bounded harmonic features exist; specified injector/charge/calibration do not. |
| §9.1 Zero-heap SoA arena | Replace heap-dependent execution/staging with the specified aligned arena layout and enforce its bounds. | Allocation instrumentation, alignment/layout assertions, capacity exhaustion tests. | Missing; scratch is arena-relative but allocated state/record staging still uses heap. |
| §9.2 `.nphi v3.0` | Implement page-aligned Parseval/DCT spectral storage and stated error bounds. | Golden format fixtures, round trips, corruption rejection and quantitative DCT error tests. | Missing; `.nps` is a different flat snapshot. |
| §9.3 `.nbin v3.0` | Implement indexed, zero-parse offline binary training format and resume metadata. | Format compatibility, index/offset and interruption/resume tests. | Missing; current `.nbin` is a minimal record framing. |
| §9.4 Async action transducer | Implement allowlisted `fs.*`, `app.*`, `api.*` actions behind `V_protection`, async parking/resume and specified abstention loop. | Deny-by-default, prompt/action isolation, race, timeout, resume and three-error tests. | Missing; current interface is HTTP chat/pretraining, not the specified tool transducer. |
| §9.5 End-to-end flow | Wire only verified components into the described data flow and expose observable state/errors. | End-to-end golden runs for training, checkpoint reload, inference and protected action. | Partial operational path: auto `.nbin` training connects atlas selection and ETD modes, records adaptive macro metrics, and the Node publisher rejects incomplete counts or failed OOD abstention probes. Full verified component flow, resume metadata and protected actions remain missing. |
| Adaptive-training automation (implementation aid) | Choose bounded per-record work from measured progress, stop after numeric failure, and gate publication on reproducible metrics. | Planner fixtures, all-backend auto-trainer test, count/checkpoint checks and OOD-abstention probes. | Implemented prototype: test 62 verifies the deterministic planner and auto `.nbin` telemetry. Node publisher checks counts, adaptive budget range, training-record examples and five out-of-domain abstentions. These gates do not measure generalization or replace held-out quality evaluation. |
| Free-text generation (user goal) | Add an original LIR-native next-byte generation path consistent with §8 and train/evaluate it on genuine, properly licensed text; do not substitute retrieval or templates. | Held-out continuation/perplexity or comparable metrics, prompt-diversity tests, UTF-8 validity, memorization/leakage checks and human review. | Not implemented; existing byte head is not autoregressive. |
| General-purpose reasoning (user goal) | Establish a general reasoning architecture within the specified field/cavity framework and connect it to generation without an external model. | Publicly specified held-out multi-domain suites, tool-free reasoning tests, calibration/abstention and error analysis. | Not implemented; bounded symbolic inference is the current scope. |

## Work order and stop conditions

1. Preserve the user's exact specification and keep the status audit current (done in
   this change).
2. Implement §3–4 as a small, independently testable geometry/objective kernel;
   do not connect it to chat until its numerical invariants pass.
3. Implement §5–6 with reference-solution and stability/convergence tests.
4. Implement §7–8 and verify learning, boundary and abstention invariants.
5. Implement §9 formats/arena/transducer; reject malformed or unsafe inputs by
   default.
6. Only then wire training and inference, add autoregressive raw-byte generation,
   and evaluate on held-out real text/reasoning tasks.
7. Mark full conformance only after every row above has evidence. If a guarantee
   cannot be established, narrow the claim and document the measured limitation.

The architecture describes a substantial research system, not a safe one-commit
feature. No test count, synthetic corpus size, generated output, or successful
smoke test alone demonstrates general-purpose intelligence. Existing unrelated
working-tree changes were present before this plan was written and are not part of
this plan's validation claim.
