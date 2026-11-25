# NOEMA-Φ architecture conformance status

This file distinguishes implemented behavior from the aspirational specification
in [`NOEMA-PHI-v3-user-spec.md`](NOEMA-PHI-v3-user-spec.md) (the user's supplied
291-line reference) and the repository companion
[`NOEMA-PHI-v3-architecture.md`](NOEMA-PHI-v3-architecture.md). It is an audit,
not a claim that the specification's physical interpretation or mathematical
guarantees have been proved. See the section-by-section implementation gates in
[`NOEMA-PHI-v3-IMPLEMENTATION-PLAN.md`](NOEMA-PHI-v3-IMPLEMENTATION-PLAN.md).
Status reflects the current checkout.

## Implemented and verified

| Area | Current behavior | Evidence |
|---|---|---|
| LIR pretraining path | `ai/src/noema_pretrain.lir` remains raw-byte LIR-only. `np_select` now uses the shared exact top-K atlas router (`noema_phi_atlas.lir`), and `np_step` uses nonlinear half-kicks around the analytic linear ETD step (`noema_phi_etd.lir`); the damped oscillator parameters preserve the legacy linear damping rate and align the radial force with `np_energy`. It does not import a tokenizer, Transformer, attention, MLP, autodiff tape, or external optimizer. | Tests 44, 46–57 and 61; all pass on native, VM and C (checkpoint compatibility test 53 uses the documented `-O1` test directive). |
| Sparse work and phase lanes | Four distinct selected cards and eight state streams are evolved per record. | Tests 46–49. |
| Counterfactual schedule | One of every eight documents gets a deterministic alternate branch with phase inversion; no random additive perturbation. | Tests 46 and 49. |
| Reset scopes | Partial reset clears working fields and retains middle-ring/context values; full reset clears fields, context and ring. | Tests 46 and 52. |
| Surprise-gated updates | Energy-derived gate scales signature, sigma, bias and low-rank parameter updates during consolidation. A zero gate is a no-op on those learned values. | Test 50 directly checks signature behavior; source inspection covers the other parameter arrays. |
| Curriculum proxy | Four spectral cutoffs are available; transition requires eight records in the phase and eight consecutive within-record relative energy changes below 0.5%. | Test 51. This is not the specified moving-average free-energy plateau. |
| Numerical rejection | Non-finite or extreme energy/state values abort a document, propagate a failed record status, and prevent overwriting a valid checkpoint. | Test 55; this does not prove a Lyapunov bound or all-step stability. |
| Corpus-derived retrieval | Each successful record contributes at most one eligible source line (≤256 bytes) to an exemplar ring sized from planned dataset records. Capacity has no configured maximum and can be expanded; an insertion at full capacity now fails instead of evicting stored exemplars. Exact byte-substring matches take priority; otherwise 512-feature byte 5-grams rank candidates and fallback scores below 0.22 or candidates with no whole-token overlap abstain. This is lexical retrieval—not semantic understanding or free-form generation. | Tests 56-57 verify retrieval, abstention, overflow refusal, expansion beyond 256 slots and checkpoint persistence on native, VM and C. The 4,096-record v008 run stores all 4,096 exemplars. |
| NOEMA-Φ geometry/objective kernel (§3–4 slice) | New `ai/src/noema_phi_geometry.lir` computes the inverse Randers metric using an O(R·D) Woodbury application with a Cholesky solve on the R×R core (R≤4), projects drift to the configured g-dual norm bound 0.85, forms convex five-mode parameter mixtures, evaluates Randers norms and complex U(1)-covariant kinetic density, pointwise bridge coupling, syntax-charge and keyword-lock penalties, bounded-context mutual information, and a discrete Yamabe regularizer. It also implements the specified De-Morgan abstention gate and pointwise V_top, V_validation, V_symbol, V_protection, V_abstention and source-work terms. Inputs are caller-owned buffers; no model/runtime dependency is added. | Test 58 checks Woodbury against a direct dense metric, drift bound, directional norm, kinetic phase asymmetry, bridge alignment, local potentials and global-term fixtures on native, VM and C. |
| Hierarchical resonance top-K selector (§3.1 slice) | `ai/src/noema_phi_atlas.lir` builds a binary max-signature-norm bound tree and uses Cauchy-Schwarz branch-and-bound to return exact top-K raw resonance scores, with deterministic tie ordering and bounded K≤4. It is now called by pretraining's `np_select`, which currently rebuilds the bound tree from card signatures on each selection. The tree walk can prune candidates, but total route cost is therefore O(C·D) per selection in this integration and the selector itself has O(C·D) worst case; neither meets the specification's strict O(log C). | Test 61 compares top-three ranked cards/scores to a hand-computed fixture, checks zero-query tie order and rejects malformed tree/K metadata; tests 46–57 exercise the connected pretraining path on native, VM and C. |
| NOEMA-Φ damped wave and ETD mode kernels (§5–6 slices) | `ai/src/noema_phi_wave.lir` provides a standalone spatially uniform complex quadratic mode with fixed source/Hermitian gyro and implicit-midpoint identity ΔE = −2γΔt|Π_mid|². `ai/src/noema_phi_etd.lir` applies analytic under-, critical- and over-damped linear-mode propagators and is wired into pretraining's `np_step` between matching nonlinear radial half-kicks. This makes the current field update a nonlinear-kick / linear-ETD / nonlinear-kick split, not the full spatial solver. | Test 59 checks the midpoint decrement and conservation. Test 60 checks three-regime semigroup behavior and energy behavior. Existing tests 46–57 exercise ETD in the pretraining route; all affected tests pass on native, VM and C (53 at `-O1`). |
| Adaptive training controller and publish gate | New `noema_pretrain_nbin_train_auto` selects a per-record macro budget from curriculum stage, byte length, prior surprise gate, plateau and early-exit statistics, bounded by caller cap. A prior numerical failure halts auto scheduling. Synthetic corpus defaults to 4,096 records across 16 deterministic task families; `RECORDS` is configurable without an artificial ceiling, while disk/RAM and the LIR address range remain physical limits. The publisher checks full manifests, family coverage, record/exemplar totals, macro metrics, exact retrieval and five out-of-domain abstentions against a staged checkpoint before switching the live alias. | Test 62 checks planner decisions, cap/invalid handling, numerical-failure stop, exact-substring retrieval and telemetry on native/VM/C. The 4,096-record v008 run trained all records and passed promotion plus HTTP reload checks. This controller is a deterministic resource heuristic, not learned curriculum intelligence. |
| Plain TXT framing | Standalone `---` lines are excluded from the packed payload; other bytes, including surrounding whitespace, are preserved. | Test 48; HTTP upload integration check. |
| Upload and progress | TXT upload has no configured total-byte or physical-line ceiling; parser chunks are an I/O strategy, and host disk/RAM plus transport/address-space limits remain. Estimated exemplar RAM is checked before training. There is no default training timeout; operators can set `TRAIN_TIMEOUT_MS`. The UI reports live record progress/ETA and the service creates versioned model files without overwriting earlier versions. | 66 MB synthetic HTTP stress check; a one-record upload/chat check. The expanded 4,096-record pretraining corpus was also served by the trained chat API. |
| State checkpoint | `.nps` version 4 stores a dataset-sized retrieval index and uses a 32-bit FNV-1a payload checksum; loader accepts v1-v3 layouts. Model dimensions no longer have the former fixed 1,024/128/256 upper bounds; checked size arithmetic rejects only values outside the addressable representation, and allocation can still fail for lack of resources. State allocation and checkpoint load remain single contiguous in-memory operations, not paged or distributed. | Tests 53, 56, 57 and 63; test 63 creates dimensions 1,025/129/257. v008 4,096-record publication and LIR/API reload, retrieval and abstention verification. |

## Partial or not implemented

| Specification | Actual gap |
|---|---|
| Sections 3–4: full topological atlas, bridges, Randers-Finsler geometry and unified free-energy functional | Numerical primitives now implement low-rank Randers/Woodbury geometry, drift projection, U(1) kinetic density, pointwise bridge penalty, local/global energy terms and Yamabe regularizer (§3.2–3.4/§4.1–4.2). An exact top-K binary branch-and-bound resonance selector exists (§3.1), but its worst-case is O(C·D), not the specified strict O(log C). Active cross-card bridge integration and a complete spatially integrated/variational energy pipeline remain. The branch-bound selector is connected to pretraining, but the Randers/energy kernels are not yet wired into training/inference or chat. |
| Sections 5–6: Lyapunov-stable second-order PDE and Strang IMEX-ETD | A finite-dimensional scalar mode has an implicit-midpoint identity for fixed quadratic potential/source and Hermitian gyro term; a separate analytic ETD propagator covers under-, critical- and over-damped modes (§5.1/§5.2/§6.2). The ETD mode is now connected to `np_step` as a linear subflow between nonlinear radial half-kicks; the resulting prototype is tested through training on all backends. Still missing spatial gradients and Randers operator coupling, full §4 nonlinear variational forces, protection masks/position-dependent damping, noise handling, atlas bridge coupling, DCT modes, protection propagator and specified L1/L2 macro/micro scheduling. This is a useful split-mode integration, not the full geometrical PDE or complete Strang IMEX-ETD solver. |
| Section 7: Envelope theorem and CAWR | No adjoint verification field, CAWR trajectory integral, Fréchet-gradient validation, or architecture-equivalent margin/FT loss is implemented. The current surprise gate is a local energy-change heuristic. |
| Section 8: Goertzel, syntax charge, epistemic output gate | Input signatures use an O(1)-state harmonic oscillator recurrence for bounded sampled Fourier projections (checked against direct sums), but not the specified damped sliding-window Goertzel algorithm. There is no syntax/topological-charge conservation or calibrated semantic confidence. The byte-overlap threshold is heuristic and cannot guarantee relevance; retrieval is not a natural-language generator. |
| Section 9: zero-heap SoA / `.nphi v3` / `.nbin v3` | Per-document scratch arrays are arena-resident, but the arena and record staging still use heap allocations. `.nps` is a flat native-state snapshot, not a page-aligned Parseval/DCT `.nphi`; `.nbin` is a minimal 10-byte record header, not the FT v3 indexed format. Resume offset, complete job metadata, DCT error bounds and fsync-based full resume are absent. |
| Section 9.4: asynchronous action transducer and `V_protection` | The web app is an HTTP chat/pretraining interface, not an `fs.*`/`app.*`/`api.*` tool transducer. No allowlisted action registry, protection barrier, async soliton parking or three-error abstention loop is present. |
| Petabyte corpora / terabyte-scale models | Not currently supported or verified. Corpus ingestion is streamed/chunked, but training state and `.nps` checkpoint are still allocated/loaded as one contiguous in-memory block; retrieval exemplars retain at most one 256-byte line per record; inference is a single-process native run. Out-of-core sharded state, indexed disk retrieval, resumable multi-shard checkpoints and benchmarked throughput are required before claiming PB/TB scale. |
| Section 2: physical intelligence metrics | No validated topological-complexity, spectral-capacity, energy-efficiency or causal-depth benchmark exists. Corpus throughput and unit-test passes are not intelligence measurements. |

## Reproducible checks

```sh
python3 ai/run_tests.py
```

The pretraining-specific tests are `46` through `57`, geometry/objective test
`58`, damped-wave/Lyapunov test `59`, scalar-mode ETD test `60`, atlas
routing test `61`, and adaptive trainer test `62`; these are expected to pass on
native, VM and C backends. The repository-wide runner also
executes the earlier LIR suite. `zig build test` requires the Zig toolchain,
which may not be present in the current runtime.

The latest separate synthetic upload stress measurement is 66,000,066 bytes
(66 decimal MB; 62.94 MiB), 63 records, with 1.052 seconds median end-to-end
across three runs. It demonstrates bounded upload/training throughput only; the
repeated-byte corpus is deliberately not a language or intelligence benchmark.

## Completion criterion

Calling this project fully conformant requires implementing and testing the
remaining mathematical core, binary formats, observability and transducer
contracts above. Do not mark a row complete based on terminology or a passing
smoke test alone; attach an invariant or behavioral test for each guarantee.
