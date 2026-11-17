# LIR Roadmap

## Architecture and release gates

The implementation sequence and mandatory correctness/performance gates are specified in [Compiler Architecture](COMPILER_ARCHITECTURE.md). The complete low-level language contract (including pointer/memory semantics, ABI/layout, hardware facilities, safety modes, tooling, and release gates) is in [Low-Level Language Specification](LOW_LEVEL_LANGUAGE.md). Roadmap checkboxes are not evidence of correctness by themselves: mark an item complete only after its tests run successfully in CI and the behavior is integrated end-to-end.

Release blockers include unchecked capacity/offset arithmetic, process termination from reusable compiler stages, silent acceptance of unsupported syntax, invalid IR reaching code generation, incorrect ABI/register/stack behavior, and non-atomic executable output.

Validated status (2026-11): `zig build test` passes 115/115 unit + catalogue-conformance tests, and `tests/{cli,core,call,project,ai,backend,browser}_test.py` all pass against the release build. Recent bootstrap hardening: unsupported top-level declarations and non-`i64` parameter/return/struct-field annotations now fail closed; AST source-span access uses overflow-safe range validation. These changes reduce silent miscompilation risk but do not constitute a complete type checker. The IR string table now checks both entry and byte capacities before writes, deduplicates only validated ranges, and causes compilation to fail explicitly on overflow. A structural IR verifier now runs before native code generation and checks function/source ranges, block and instruction counts, branch targets, string references, call argument bounds, struct layout, parameter/local slot bounds, and backend stack-frame limits. Regression tests cover malformed branch/string references, invalid local slots, and oversized stack frames. The earlier test-module name-shadowing compile error is fixed and covered by the current green run.

## Phase 1: Core Language
- [x] Lexer with zero allocations
- [x] Pratt parser for expressions
- [ ] Complete type system with enforced ownership and borrow checking
- [x] x86-64 native codegen
- [x] ELF binary output
- [x] Embedded zero-wrapper standard library (`core`, `io`, `os`, `sys`, `net`, `crypto`, `json`, `math`, `testing`)
- [x] Build system (`lir build`/`run`/`check`/`ir`/`test`/`init`)
- [x] JSON-based project manifest

## Phase 2: Complete Compiler
- [ ] Full borrow checking & lifetime inference (required before claiming ownership safety)
- [x] Generic type & function monomorphization (`Option<T>`, `Result<T, E>`, generic structs/methods/fns)
- [x] Trait definitions & `dyn Trait` dynamic dispatch
- [x] ADT & range pattern matching with guards (`match`)
- [x] String interpolation (`"{expr}"`)
- [x] Lambda/closure codegen with captures & higher-order `fn` pointers
- [x] Error propagation (`?` and `??`)
- [x] Defer statement codegen
- [x] Compile-time evaluation (`comptime`, `@size_of`, `@align_of`, `@type_name`)

## Phase 3: Advanced Optimizer
- [x] SSA-based CFG IR with structural verifier (`ir_verify.zig`)
- [x] Global value numbering (`ir_opt.zig`)
- [x] Loop invariant code motion (`ir_opt.zig`)
- [x] Inline expansion (`ir_opt.zig`)
- [x] Tail call optimization
- [ ] Escape analysis
- [ ] Vectorization (SIMD)
- [ ] Profile-guided optimization

#### Phase 3 notes: soundness fixes and the -O1 pipeline (2026-11)

Working on runtime performance surfaced three soundness bugs. All three were
present before this branch, all three produced a wrong answer while every
level reported success, and all three are fixed here. The fixes are the only
reason the -O1 numbers below can be trusted at all.

1. `unrollCountedLoops` advanced the induction variable once per *unrolled
   repetition* rather than once per iteration. It also emitted one write-back
   copy per body definition instead of one per variable, so a later copy
   overwrote an earlier one. `while n <= 10 { count += 1; n += 1 }` printed 6
   instead of 9 at -O2. Fixed by chaining repetitions through the vreg map and
   writing back only the last definition of each carried variable.
2. `coalesceCopiesPostSSA` pass B rewrote a result into a destination `dst`
   that was still read further down the block, and pass A renamed a definition
   into a destination that already had one. Together they turned
   `x = x + 1; y = x + 1; x = y + 1` into `x = x + 1; y = x + 1; x = x + 1`.
   Fixed by requiring a single definition of `dst` and no reads of `dst`
   between the two instructions.
3. `rotateLoops` ran on functions that still carried phis and emitted
   ill-formed code (SIGILL at runtime). It now refuses when any phi is present.

`tests/core_test.py::LoopOptimizationSoundnessTests` covers each case at all
three levels, on the native and VM backends.

With those closed, -O1 was rebuilt: it previously ran local passes only, which
left parameters and loop variables in memory and made the same function up to
2.4x slower than at -O2. It now builds SSA, runs if-conversion, copy
propagation and coalescing, rotates and unrolls counted loops, and skips only
inlining, global value numbering and loop-invariant hoisting. Code generation
also follows trivial `copy` chains when looking for a constant divisor, so
`x / 10000` keeps its multiply-based lowering after out-of-SSA (`mandelbrot`
had regressed 12% purely from a `v = copy const` in front of a `div`).

Paired measurement, 21 sample pairs per workload, bootstrap 95% CI, old and
new binaries alternating within each pair (old = this branch before the
change, same machine, same session):

| Workload | old -O1 | new -O1 | ratio | stable? |
|---|---|---|---|---|
| `mandelbrot_fixed_2d` | 28.47 ms | 25.74 ms | 1.10x | yes |
| `tak_recursive_27` | 29.95 ms | 26.35 ms | 1.18x | yes |
| `branch_mix_30m` | 63.35 ms | 46.50 ms | 1.38x | yes |
| `collatz_sequence_1m` | 315.47 ms | 212.06 ms | 1.49x | yes |
| `bitwise_hash_20m` | 32.74 ms | 31.94 ms | 1.03x | no (CI touches 1.0) |
| `prime_count_500k` | 42.09 ms | 41.91 ms | 1.00x | no |
| `nested_matrix_loop_4m` | 29.88 ms | 29.88 ms | 0.99x | no |
| `fib_mod_30m` | 103.64 ms | 107.90 ms | 0.98x | yes, 2% slower |

Geometric mean of the eight ratios: **1.13x**. -O1 compile time rises from
2.5 ms to 3.7 ms net on the 255-function module, still 2x faster than -O2 at
7.6 ms. Only the "yes" rows are claimed; the rest are noise this machine
cannot resolve.

#### Phase 3 notes: six more wrong-answer bugs found by heavier workloads (2026-11)

Writing the LIR-vs-Rust math suite (`bench/rust_compare`, eleven programs) was
worth more as a bug hunt than as a benchmark: six further miscompiles surfaced,
none of which the existing corpus reached. All shared one property - they only
appear when a program combines constructs the small tests keep apart - and all
produced a plausible-looking number rather than a crash.

Two were in code generation, and both were register-allocation assumptions:

1. The constant-divisor `%` / `/` fast path parks the magic multiplier in `rcx`
   and remembers it in `cur_rcx_const`, which codegen used to hoist the load
   out of loops. But `rcx` is the implicit divisor register for `div`: a runtime
   `div` in the same loop (`mov %rdi,%rcx; div %ecx`) overwrote the parked
   magic, so the next iteration multiplied by the runtime divisor.
   `((i*13)%100)` plus `100000000/d2` in one loop printed -7284561654821
   instead of -10000000000. Hoisting removed; each division loads its magic
   inline. Measured cost: none (geomean 0.99x over `bench/speed_compare`).
2. The same path used `r10` as scratch when the dividend was spilled. `r10` is
   in `CALLER_SAVED_POOL` and can hold a live vreg - in a nested loop it held
   the outer induction variable, which the inner `% 100` destroyed. It now uses
   `r11`, which really is reserved (rax/rcx/rdx/rsp/rbp/r11).

Four more were in the optimizer, all about phis:

3. `mem2reg` placed phis for every slot before inserting any of them, and
   renaming consults a per-slot `promotable[]` flag. A slot rolled back for
   block-capacity reasons could still have its names in the shared pool, so an
   operand-less phi reached the CFG and the vreg it defined was never assigned.
   Placement now commits per slot (`pending` -> `placed`).
4. `simplifyTrivialPhis` rewrote a phi as `dest = copy v` unconditionally. A
   phi is defined on *every* incoming edge, a copy only where it executes.
   The rewrite now requires `definedBefore` (real dominators).
5. `globalCopyPropagate` rewrote phi *operands*. An operand names the value live
   on one specific edge; replacing `{16, 18}` with `{16, 9}` because some block
   contained `copy 18, 9` makes the merge read a stale register. This is what
   turned `a = b; b = t - m | b = t` into an exploding recurrence at -O2 on the
   native *and* VM backends (06_fib_mod printed 735302655874374793 instead of
   577847172). Phi operands are now left alone.
6. The `-O0` build disagreed with -O1/-O2 on literal modulo (`1234 % 100`
   printed -666) because of (2).

`tests/core_test.py::LoopOptimizationSoundnessTests` now has seven cases; the
three added here and the phi pair added with the benchmark suite all fail on the
parent commit and pass after these fixes. 16 benchmark programs (10 in
`speed_compare`, 6 at the time of the fix in `rust_compare`) are identical
across -O0/-O1/-O2.

#### Phase 3 notes: compile-time work (2026-11)

Compilation is the axis where the gains in this branch are unambiguous and
reproducible, because they are pure work-removal (no code generation change:
-O0 and -O2 output is byte-identical to the previous compiler on the test
corpus). Measured with `tools/compile_bench.py`, which subtracts process
startup and alternates the two binaries sample by sample, on a 255-function
module (the compiler's per-unit function cap) of four-statement helpers:

| level | before | after | net speedup |
|---|---|---|---|
| `-O0` | 15.14 ms | 12.26 ms | 1.24x |
| `-O1` | 15.92 ms | 12.00 ms | 1.33x |
| `-O2` | 27.80 ms | 15.21 ms | 1.83x |

In-process phase timers on the same input: IR optimization 2067 -> ~1200 us
and machine-code + ELF emission 2672 -> ~620 us. The remaining per-unit cost
is front-end dominated (lexing/parsing ~470 us, sema ~300 us, IR lowering
~1000 us, codegen ~600 us), i.e. ordinary single-pass work rather than
redundant table traffic.

The changes are all of one kind: several passes are written against
fixed-capacity tables (4096 vregs, 192x384 instruction slots) and cleared
them in full on every invocation, many times per function. See
`src/bootstrap/ir_opt.zig` (`deadCodeElimination` generation stamp,
`localConstantFoldAndLVN` dirty list + block-generation stamp,
`globalCopyPropagateSmall`) and `src/bootstrap/ir_codegen.zig`
(`allocRegsForFn`/`analyzeElidedConsts` bounded by `IRFn.vreg_count`).

Runtime quality is unchanged by this work. Wall-clock ratios on this shared
VM move by more than the effects being measured (absolute throughput drifted
~1.8x between two runs of identical binaries), so the runtime table in the
README is left as measured earlier rather than restated from a noisy sample.

## Phase 3 notes: measured gaps (2026-11)

Recorded so optimizer work is tracked against evidence rather than assumed.
Numbers come from `bench/speed_compare` measured with `tools/ab_bench.py`
(interleaved paired sampling, median of 13, 3 warmups, ratio = LIR/Zig, 95%
bootstrap CI); every program is also checked to print byte-identical output
to its Zig reference.

- Inner-loop multiplies move the accumulator first (`mov %A,%B` then
  `imul`, plus `mov %B,%C` / `sar` to keep the product) where a
  memory-form `imul mem,reg` or commuting `imul rax,%A` would avoid a copy.
  This is the visible difference on the multiply-heavy kernels
  (mandelbrot 1.11x, bitwise_hash 1.14x, branch_mix 1.16x). Note that a
  naive "extra mov" count is misleading: `1 + 2*1` folds to `3` at -O2 and
  Zig independently emits the same `mov`-pair shape for `h = h ^ (h >> 32)`,
  so the gap is in operand selection, not in the optimizer.
- Multi-block loops are not unrolled. `unrollCountedLoops` only matches a
  single-block self-loop of at most 14 instructions, so a counted loop whose
  body spans two blocks (variable initialisation plus an `if`/`break`) is
  left alone. Zig unrolls exactly those loops twice (mandelbrot's inner loop
  appears as two 26-instruction versions against one 38-instruction version),
  so the unroll is the measurable structural difference on that kernel.
- `bitwise_hash_20m` keeps its loop bound in a register because the
  bound is a function parameter, where Zig receives the same value as an
  immediate through inlining; that is an inlining-context difference rather
  than a compare-selection defect.
- Compiler throughput is not the bottleneck: compile time is 1400-2100x
  faster than `zig build-exe -OReleaseFast` on the same programs (median of
  15, warm cache for Zig), so the runtime gap above is a code-quality
  question.

## Phase 4: Concurrency
- [x] Native OS threads (`spawn`, `@thread_create`, `@thread_join`)
- [x] Bounded MPMC channels (`@chan_new`, `@chan_send`, `@chan_recv`, `@chan_close`)
- [x] Mutexes (`@mutex_new`, `@mutex_lock`, `@mutex_unlock`) & atomic operations (`@atomic_add`, `@atomic_cas`)
- [x] Join reports the thread's return value on native, C11 and IR VM backends
- [x] Fail-closed target gate: threads/channels are rejected for `wasm32-wasi` with `LIR-E7004`
- [ ] Data race detection (compile-time)
- [ ] Async/await state-machine runtime
- [ ] Work-stealing scheduler
- [ ] Lock-free data structures

## Phase 5: Cross-Platform (Q4 2026)
- [x] macOS Mach-O backend (`aarch64-macos`, `x86_64-macos` via portable C11 backend)
- [x] Windows PE/COFF backend (`x86_64-windows`, `aarch64-windows` via portable C11 backend)
- [x] WASM backend (zero-dependency `wasm32-wasi` emitter + C11 WASI target)
- [x] ARM64 backend (`aarch64-linux`, `aarch64-macos`, `aarch64-windows`)
- [x] RISC-V backend (`riscv64-linux`)
- [ ] Embedded targets (no_std)
- [x] WASI support (`wasm32-wasi` native emitter, Wasmtime/Node runner, portable IR VM)

## Phase 5b: AI/tooling contracts (2026-11)
- [x] Machine-readable language catalogue (`lir lang --json`, `lir.lang.v1`) validated by tests
- [x] Machine-readable builtin catalogue (`lir builtins --json`, `lir.builtins.v1`)
- [x] Coded diagnostics (`lir.diagnostics.v1`) with `help` and `expect{kind,value}`
- [x] JSON command results (`lir.check.v1`, `lir.build.v1`)
- [x] `lir explain` topic + code knowledge base with `--json`/`--list`
- [x] Agent scaffolding (`lir init --ai` → `AGENTS.md`, `lir.agent.json`)
- [x] Generated reference (`lir lang --markdown` → `docs/LANGUAGE_REFERENCE.md`)
- [x] Regression gate for the above (`tests/ai_test.py`, catalogue conformance in `zig build test`)
- [ ] LSP server publishing `lir.diagnostics.v1` live
- [ ] Formatter (`lir fmt`)
- [ ] Machine-readable stdlib catalogue with per-function signatures

## Phase 6: Ecosystem (2027)
- [ ] Package manager (lir pkg)
- [ ] Package registry (crates.io equivalent)
- [ ] Language server (LSP)
- [ ] VS Code extension
- [ ] IntelliJ plugin
- [ ] Documentation generator
- [x] REPL (`lir repl` interactive Read-Eval-Print Loop)
- [ ] Playground (web-based)

## Phase 7: Advanced Features (2027+)
- [ ] Comptime reflection
- [ ] DSL support (macros)
- [ ] Effect system
- [ ] Algebraic effects
- [ ] Dependent types (optional)
- [ ] Proof assistant integration
- [ ] Formal verification

## Performance and Usability Goals

These are engineering targets, not verified claims about the current compiler. Record baseline measurements before changing the optimizer, and keep each optimization only when correctness tests pass and benchmarks show a repeatable improvement.

| Metric | Goal | Verification |
|--------|------|--------------|
| Runtime speed | Beat optimized C on selected workloads; remain competitive on the full suite | Same algorithm, same inputs, equivalent safety/overflow semantics, optimized builds, repeated runs, report median and variance |
| Compile speed | Improve throughput without weakening diagnostics or correctness | Benchmark cold and warm builds separately; report LOC/s and wall time |
| Binary size | Keep small programs compact without sacrificing runtime speed | Compare stripped release binaries and disclose target/flags |
| Memory use | Avoid hidden allocations and unnecessary copies | Measure peak RSS and allocation counts on identical workloads |
| Startup latency | Keep short-lived CLI programs responsive | Measure process startup separately from steady-state throughput |
| Learnability | Small core syntax, consistent rules, useful diagnostics | Beginner tasks, examples, and error-recovery tests |

### Required optimization workflow

1. Establish a reproducible baseline against a recent, optimizing C compiler (for example, Clang or GCC) using documented flags and identical workloads.
2. Include microbenchmarks and representative programs; prevent dead-code elimination from invalidating results and verify outputs for every implementation.
3. Run multiple repetitions, report median and spread, and test both debug and release configurations.
4. Inspect generated assembly for claimed low-level wins; measure compile time, binary size, and memory alongside runtime.
5. Never claim “faster than C” universally. State exactly which workload, hardware, compiler versions, flags, and correctness constraints support each result.

## Language Design Principles

1. **Simplicity first** — Prefer a small set of consistent rules over many special cases.
2. **Easy to read and write** — Infer obvious local types; require annotations where inference would be ambiguous or obscure.
3. **Performance by construction** — Predictable layouts, explicit allocation control, and abstractions that optimize away when possible.
4. **Safety without hidden costs** — Enforce ownership and borrowing in the type checker; do not claim safety until checks are implemented and tested.
5. **Optimize from evidence** — Use benchmarks, generated-code inspection, and regression tests rather than intuition alone.
6. **Portability through backends** — Keep language semantics separate from target-specific code generation.
7. **Honest status** — Clearly distinguish implemented, partial, and planned features.
