# Implementation status

Single, honest matrix of what the bootstrap compiler does **today**.
`lir lang --json` is authoritative; this page is the human summary and is kept
in sync by `tests/ai_test.py` (which fails if a `supported` example stops
compiling, or an `unsupported` probe starts compiling).

Counts from the catalogue: **65 supported · 2 partial · 3 legacy · 6 unsupported**.

## Backends

| Backend | Flag | Targets | Threads/channels | Status |
|---|---|---|---|---|
| IR VM | `--backend=vm` | anywhere the compiler runs | yes | supported |
| x86-64 ELF64 | `--backend=native` (default on linux-x64) | `x86_64-linux` | yes | supported |
| C11 | `--backend=c` / `--emit-c` | x86_64/aarch64/riscv64 × linux/macos/windows/freebsd via `cc`/`zig cc` | yes | supported |
| Wasm32-WASI | `--backend=wasm` | `wasm32-wasi` | **no** — rejected with `LIR-E7004` | supported with that exclusion |

Every backend runs `examples/canonical-tour.lir` with byte-identical stdout
(asserted in `tests/ai_test.py`). Diagnostics/traps are supposed to match too;
see the known gaps below.

## Language

| Area | Supported | Partial / limits |
|---|---|---|
| Declarations | `fn`, `const`, `struct`, `enum`, `union`, `impl`, `trait` + `dyn`, `type` alias incl. `i64 range lo..hi`, `import`, generics on functions/structs | nested generics `Option<Option<i64>>` (`>>` is a shift token); struct fields cannot be struct/function types |
| Statements | `let`, `let mut`, assignment, `op=` (`+= -= *= /= %= &= \|= ^= <<= >>= **=`), `if/elif/else`, `unless`, `while`, `loop`, `until`, `for a..b` / `..=`, `for v in array\|string`, `break`, `continue`, `return`, `defer`, `guard … else`, `match`, `unreachable` | no labelled loops; no `for i, v in arr` |
| Expressions | arithmetic incl. `**` right-assoc, comparison, `and`/`or`/`!` (+`&&`/`||`), ternary `?:`, `as` casts, string concat/interp, char literal as `i64`, array literals `[..]`/`[v; n]`, tuples ≤8, `Option`/`Result` + `?`/`??`, pointers `*T`/`*mut T`, `fn` values, closures `\|x\| …`, method calls, named args + defaults (free fns), comprehensions | `[]T` slice type is partial; free functions only for named/default args |
| Memory | `@malloc`/`@free`/`@realloc`, `@array_*`, `@map_*`, `@memcpy`/`@memset`, bounds traps | no GC, no `no_std`, no allocator interface |
| Concurrency | `spawn { }`, `@thread_create`/`@thread_join`, `@chan_new/send/recv/close`, `@mutex_*`, `@atomic_*` | not on wasm32-wasi (`LIR-E7004`); no async/await, no scheduler |
| Comptime | `comptime` blocks and `fn`, `@size_of`, `@align_of`, `@type_name`, `@target_os/arch/ptr_bits` | no arbitrary comptime execution of syscalls |
| Attributes | `#[test]`, `#[inline]`, `#[cold]`, `#[pure]`, `#[pre(expr)]`, `#[post(result …)]` | contracts verified for constant arguments only |
| Safety analysis | UAF/double-free/defer conflict/close/loop-leak, compile-time bounds where provable, fn-pointer cast checks, thread entry validation, stack budget, spin-loop detection, W^X ELF, canaries | full lifetime/borrow checking is **not** implemented (only live-mutable-borrow and dangling-return checks) |

## Safety and diagnostics

| Mechanism | Status |
|---|---|
| Coded diagnostics (`LIR-E1xxx`…`E7xxx`) + `help:` + `expect{kind,value}` | implemented for the frontend, driver and target gates |
| Text formats: human / short / JSON | implemented |
| Trap behaviour (OOB, div/mod 0, shift, failed assert, contract violation) | traps; process exit code **132** |
| Integer overflow | **wraps silently** on `+ - *` (documented; `@checked_*` returns a flag) |
| `lir explain` coverage | topics + the code families hit by users; not every internal code |
| Warning codes | unused variable/parameter (`LIR-W9000`), unreachable code |

## Tooling

| Command | Status |
|---|---|
| `lir build/run/check/ir/ast/test/targets/init/repl/install/version/help` | implemented |
| `lir lang` (`--json/--markdown/--short/--status/--category`) | implemented, catalogue is compiled by tests |
| `lir builtins` (`--json/--short/--group`) | implemented |
| `lir explain` (`--list`, `--json`, codes) | implemented |
| `lir init --ai` (`AGENTS.md`, `lir.agent.json`) | implemented |
| Embedded stdlib (16 modules, 226 functions) | implemented; see [STDLIB.md](STDLIB.md) |
| Builtins (131 intrinsics in 14 groups) | implemented; `lir builtins --json` |
| Native debug info | **not implemented** (no DWARF) |
| Package manager / registry | **not implemented** (local imports only) |
| LSP / formatter | **not implemented** |

## Test gates

| Gate | What it proves |
|---|---|
| `zig build test` | lexer/parser/sema/IR/optimizer/backends unit tests + catalogue conformance (every `supported` example compiles; `unsupported` probes are rejected; every documented builtin exists) |
| `tests/core_test.py` | language semantics end-to-end, including that a `var`/`let mut` binding is never constant-folded across an assignment (checked at `-O0`/`-O1`/`-O2` on the native, VM, and C backends), that the three optimization levels agree on a 40-function module, and that 25 randomized programs match a Python oracle at every level |
| `tests/backend_test.py` | native/wasm/C parity, traps, cross-targets |
| `tests/cli_test.py` | CLI surface, JSON envelopes, exit codes |
| `tests/ai_test.py` | machine contracts: schemas, catalogue consistency, stdlib imports, tour parity, repair metadata |
| `bench/compare_zig.py` | performance claims, with correctness checks |

## Known gaps (tracked, not hidden)

1. Full borrow/lifetime checking — only the conservative subset above.
2. `Option<Option<T>>` and `a[1][0]`-style nesting need a local binding first.
3. Contract verification is constant-only; runtime checks are not emitted.
4. No DWARF, no package manager, no LSP.
5. Threads/channels are unavailable on wasm32-wasi by design (`LIR-E7004`).
6. Cross-targets through the C11 backend need `zig` (or a matching `CC`) on
   PATH; without it the compiler fails with `CrossCompilerNotFound` and a hint
   instead of emitting a host binary.
