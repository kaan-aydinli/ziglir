# NOEMA-Phi pretraining path

See [`NOEMA-ARCHITECTURE-STATUS.md`](NOEMA-ARCHITECTURE-STATUS.md) for a
requirement-by-requirement conformance audit and the distinction between
implemented behavior and the v3.0 target.

The active training entrypoints now use `ai/src/noema_pretrain.lir`. This is a
separate raw-byte field-dynamics path: it does not import `noema_lm.lir`,
`noema_tensor.lir`, the text encoder, or the supervised fit/decoder modules.
The former LM demo and chat filenames remain as compatibility paths but now
exercise only the NOEMA-Phi pretraining API. The Transformer LM module has been
removed; test 44 now verifies the architectural replacement instead.

## Run

```sh
./zig-out/bin/lir run ai/train_text_example.lir --backend=native
./zig-out/bin/lir run ai/train_turkish_corpus.lir --backend=native
node ai/noema-training/train_synthetic_auto.mjs
./zig-out/bin/lir run ai/train_noema_lm_demo.lir --backend=native
```

`ai/chat_noema_lm.lir` no longer loads the old autoregressive model. It accepts
one raw message from stdin and reports pretraining telemetry; it intentionally
does not claim to generate a response.

## Runtime model

- The arena is allocated at runtime and exposed through an opaque `*f64` API.
  Per-document signature/card-selection scratch is reserved inside the arena, so
  document training and inference do not allocate those temporary arrays on the
  heap. The record reader still allocates bounded staging buffers. Documents
  arrive as `(raw_bytes, length, reset_kind)`. The authoring corpus is
  plain UTF-8 text; a standalone line exactly equal to `---` separates topics.
  The delimiter is framing only and is not passed into the model; all other
  topic bytes are preserved. Each topic is currently packed as a full-reset
  text-domain record, with no tokenization or JSON parsing.
- The record reader/writer implements the pretraining `.nbin` record layout:
  little-endian `u64` byte length, `u8` reset kind (`0` full, `1` partial),
  `u8` domain, then the exact byte payload. Both fixed-budget
  `noema_pretrain_nbin_train` and adaptive `noema_pretrain_nbin_train_auto`
  alternate two payload buffers; `noema_pretrain_nbin_write` emits records.
- A bounded O(1)-state harmonic recurrence computes the four sampled Fourier
  signature pairs without per-byte trig calls (at most 8,192 evenly spaced byte
  samples). Test 54 compares it with direct Fourier sums. This is still not the
  architecture's damped sliding-window Goertzel. The cavity selector routes
  these signatures through the binary max-norm atlas and returns four exact
  top-K resonance cards; the current training entrypoint rebuilds bounds for
  each selection, so total work remains O(C·D), not strict O(log C). Eight
  streams are integrated per active cavity. Every eighth document receives a paired deterministic
  counterfactual branch; that branch reverses the encoded phase variable across
  its field input (it is not stochastic additive noise).
- Partial reset clears working fields but preserves the causal context and
  perturbation ring; full reset also clears that context. The spectral active
  band advances 25%, 50%, 75%, then 100% only after at least eight records in
  the current phase and eight consecutive records with relative energy change
  below 0.5%. This is an operational plateau proxy, not the architecture's
  full moving-average free-energy scheduler.
- Field evolution now uses a nonlinear radial half-kick, the analytic linear
  ETD mode, and a second nonlinear half-kick at coarse `0.30`/fine `0.15` step
  sizes. The linear coefficients match the damped oscillator energy used by
  `np_energy`; curriculum cutoff and the early-stability check remain active.
  This is not the full spatial Randers PDE, DCT Strang scheduler or protection
  propagator. A 16-pulse consolidation interval updates bounded cavity-local
  parameters. Consolidation is gated by energy surprise; the perturbation branch
  stores a margin diagnostic, but CAWR and the architecture's complete loss are
  not implemented.
- Automatic `.nbin` training plans per-record macro steps from curriculum
  stage, payload length, prior surprise gate, plateau and early-exit telemetry,
  subject to a caller cap (the current trainer uses 4). A prior numerical failure
  blocks further automatic steps. The run records selected/mean macro budgets;
  `RECORDS` and `RECORD_BYTES` scale the synthetic corpus; the default is 4,096
  records, with no hard-coded record ceiling. Host address space, RAM and disk
  are the practical limits. The Node promotion pipeline preflights disk capacity,
  checks the complete manifest, trained-record totals, exemplar presence, macro
  telemetry, task-family coverage and exact-record probes, then requires
  abstention on five out-of-domain probes before publishing. It validates a
  private staged checkpoint without switching the live alias; rollback preserves
  the previous alias on publication failure. These probes are safety and corpus
  retrieval checks, not held-out language-quality or reasoning evidence.
- Each successful training record additionally contributes at most one
  deterministic first eligible complete source line (maximum 256 bytes) to an
  in-state exemplar ring sized to the planned record count. This aligns generated
  validation examples with stored anchors and avoids selecting from whitespace
  padding tails. The training entrypoints size capacity from the planned record
  count; the state can be expanded beyond its initial 256 slots. A full state now
  rejects the next document without evicting existing exemplars; callers expand
  it with `noema_pretrain_expand_memory` and retry. There is no configured maximum
  slot count, though host memory, disk, address space and integer representation
  remain finite. The 256-byte exemplar-line limit is still in force.
  Inference first prefers an exact byte-substring match for sufficiently long
  prompts, then falls back to a normalized 512-feature byte-5-gram score with the
  requested `0.22` threshold plus at least one case-insensitive whole-token
  overlap with the candidate. The token guard prevents unrelated hash-bucket
  collisions from passing solely on a low score; both checks remain lexical,
  heuristic, and non-semantic. Matching returns stored lines, not newly generated
  calculations or prose.
  Checkpoint v4 stores its memory capacity in the payload size and verifies it
  with the checksum; v1-v3 checkpoints remain loadable. The chat UI labels matches and abstentions.

## Tests

The authoring corpus is `ai/noema-training/pretrain_corpus.tr.txt`, with a
standalone `---` line between topics. `ai/train_turkish_corpus.lir` converts
each topic to a full-reset text-domain `.nbin` record and trains on those
records. `ai/tests/48_noema_pretrain_plaintext.lir` checks the topic framing on
native, VM, and C backends. `ai/tests/46_noema_pretrain.lir` checks the arena
API, sparse activation, eight streams, and document schedule;
`47_noema_pretrain_nbin` checks binary writing/loading and alternating buffers.
`49_noema_pretrain_learning` verifies deterministic phase reversal on the paired
branch; tests 50 and 51 verify surprise-gated updates and plateau-triggered
curriculum transitions; test 52 verifies the two reset scopes; test 53 verifies
checkpoint v4 round-trip, v1-v3 compatibility and checksum rejection; test 54 checks
harmonic-spectrum equivalence with direct Fourier sums; test 55 checks numerical
rejection and checkpoint preservation. Test 56 uses two training lines and a
separate paraphrased query to check corpus-derived retrieval, unrelated-query
abstention, and persistence through checkpoint save/load. Test 57 checks that a
full memory refuses insertion without eviction, allows a record with no eligible
short anchor to train, then expands past 256 slots, retains the earliest
exemplar and persists all 300 slots in a v4 checkpoint.
Tests 58-61 verify the geometry,
implicit-midpoint wave, analytic ETD, and binary atlas kernels; test 62 checks
the adaptive macro planner, auto `.nbin` path, requested 0.22 retrieval
threshold and exact-substring retrieval. The connected pretraining
path remains covered by tests 46-57. All these tests target native, VM, and C;
test 53 uses `-O1` due a current LIR `-O2` checkpoint-test codegen issue. The
`.nps` v4 state snapshot uses a 32-bit FNV-1a payload
check and retains v1-v3 read compatibility; the chat server fsyncs the temporary file and
model directory around the versioned rename. This is not the specified `.nphi`
Parseval/DCT container or a full crash-resume protocol.

## Large local corpus run (2026-11-24)

`build_large_pretrain_corpus.py` assembled local LIR documentation and source
files into 70 plain-text topics. Each run consumed **566,714 payload bytes**
(about 0.541 MiB; 566,990 source bytes including 276 delimiter-line bytes) in
70 full-reset records. On the sandbox x86_64 Xeon 2.60 GHz host, three
end-to-end native `lir run` timings (process/compile startup included) after
the gated-learning, reset-scope, checkpoint-integrity, byte-preserving parser,
harmonic-recurrence and numerical-guard changes were 0.846, 0.741, and 0.756
seconds; median **0.756 seconds** (about 0.715 MiB/s). Each pass scheduled 8 do-perturbation documents and
remained at spectral stage 0 because the measured records did not satisfy the
plateau criterion. This is a local technical corpus, not a large general-language
dataset or a quality benchmark. A separate HTTP stress test used a synthetic
66,000,066-byte repeated-byte body, packed into 63 records; three end-to-end
runs took 1.046, 1.052, and 1.145 seconds (median 1.052 s; accept median
0.237 s, training median 0.815 s). This is only an upload/throughput test, not
an intelligence benchmark. The trainer writes a flat
`.nps` snapshot, but there is no `.nphi` artifact or complete crash-resume
protocol. The expanded 4,096-record synthetic training run (16 arithmetic and
unit-conversion families) is summarized in [`../noema-training/PRETRAINING-RUN.md`](../noema-training/PRETRAINING-RUN.md); it is a full corpus ingestion/retrieval run, not evidence of general language learning.
