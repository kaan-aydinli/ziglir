# Contributing to LIR / Ziglir

Thanks for helping. This project has one unusual rule that everything else
follows from:

> **The compiler is the documentation.** If a feature is documented it must
> exist, be tested, and be listed in `src/bootstrap/langref.zig`. If it does not
> exist, it must be listed as `unsupported` with an `avoid` note.

## 1. Repository map

```
src/bootstrap/          the compiler (Zig 0.13)
  lexer.zig             tokens, keyword table, literals
  parser.zig            AST + recursive-descent parser (ASTNode has 3 children + flags)
  expand.zig            generics/comptime/test expansion, Option/Result synthesis
  sema.zig              name resolution, type checking, borrow/UAF/purity/contract analysis
  optimizer.zig         AST-level constant folding and simplification
  ir.zig                SSA IR data structures
  ir_gen.zig            AST → IR lowering
  ir_opt.zig            mem2reg, GVN, LICM, unrolling, magic division, DCE
  ir_verify.zig         structural IR verifier (runs before and after optimization)
  ir_codegen.zig        x86-64 ELF64 emitter
  wasm_backend.zig      wasm32-wasi emitter
  c_backend.zig         portable C11 emitter / cross-target driver
  ir_vm.zig             portable in-process VM
  target.zig            triples, backends, ABI descriptors
  driver.zig            compile pipeline orchestration
  diag.zig              coded diagnostics + human/short/JSON rendering
  langref.zig           language + builtin catalogue  ← single source of truth
  langcmd.zig           `lir lang`, `lir builtins`
  explain.zig           `lir explain` knowledge base (topics + LIR-Exxxx codes)
  main.zig              CLI
  project.zig           `lir init` scaffolding
tests/                  Python regression suites (CLI, backends, core, AI contracts)
examples/               runnable programs; canonical-tour.lir is the reference
docs/                   SPEC, AI contract, generated reference, roadmap
```

## 2. Build and test

```bash
zig build -Doptimize=ReleaseFast
zig build test                                  # unit + catalogue conformance
python3 tests/cli_test.py      ./zig-out/bin/lir
python3 tests/ai_test.py       ./zig-out/bin/lir   # machine contracts
python3 tests/core_test.py     ./zig-out/bin/lir
python3 tests/call_test.py     ./zig-out/bin/lir
python3 tests/backend_test.py  ./zig-out/bin/lir   # needs cc + node 22+
python3 tests/project_test.py  ./zig-out/bin/lir
python3 tests/browser_test.py  ./zig-out/bin/lir
```

CI runs all of these on every pull request (`.github/workflows/ci.yml`).

## 3. Adding a language feature

The order matters; each step is a place where drift is caught.

1. **Implement it** in the frontend/IR/backends, with the same diagnostics style
   as the surrounding code (`failAt`/`reportCoded` + a stable `diag.Code`).
2. **Add a `Feature` entry** to `src/bootstrap/langref.zig`:
   * `status = .supported` only if all backends agree;
   * `example` must be a complete program (`fn main`), because the test suite
     compiles it;
   * `notes` must state limits and traps;
   * `avoid` must name the near-miss spellings that do *not* compile.
3. **Add negative coverage**: put the rejected spellings into
   `tests/ai_test.py::test_unsupported_spellings_are_rejected` (or a core test).
4. **Regenerate the reference**: `./zig-out/bin/lir lang --markdown > docs/LANGUAGE_REFERENCE.md`.
5. **Update `docs/SPEC.md`** if the feature changes the language contract, and
   `docs/ROADMAP.md` if it closes a planned item.
6. Run the full gate list in §2.

If you cannot finish a feature, land it as `status = .partial` (with the limit in
`notes`) or `.unsupported` (with `avoid`). Half-documented work is worse than
none.

## 4. Adding a builtin

1. Register it in `sema.zig` (`builtins` table) — that is what type-checking
   consults.
2. Lower it in `ir_gen.zig` (`builtin_op` table) and emit it in **every** backend
   it claims to support (`ir_codegen.zig`, `wasm_backend.zig`, `c_backend.zig`,
   `ir_vm.zig`). A backend that cannot express it must reject it at compile time
   with `LIR-E7004`, never trap at runtime.
3. Document it in `langref.builtins` with a signature and trap notes.
4. Add a runtime test that exercises it on `--backend=vm`, native and `c`.

## 5. Documentation workflow

| Document | Source | Regenerate |
|---|---|---|
| `docs/LANGUAGE_REFERENCE.md` | `src/bootstrap/langref.zig` | `lir lang --markdown` |
| `docs/SPEC.md` | hand-written, must match `lir lang` | — |
| `docs/AI.md` | hand-written machine contracts | — |
| `lir explain` topics | `src/bootstrap/explain.zig` | — |
| `AGENTS.md` in new projects | `src/bootstrap/project.zig` | — |

Wording rules: say *what the bootstrap compiler does today*; never describe a
roadmap item as implemented; prefer “rejected with LIR-Exxxx” over “not yet
supported” when the compiler actually fails.

## 6. Performance changes

Follow `docs/ROADMAP.md` §“Required optimization workflow”: show a baseline, use
identical workloads and flags, verify outputs for correctness, report median and
spread, and inspect generated code. Keep an optimization only if the benchmark
gate in `bench/` shows a repeatable win at `-O2`.

## 7. Diagnostics style

* One diagnostic per problem, with the narrowest span that identifies it.
* Message form: what is wrong, then what was expected: `expected i64, found string`.
* Use `expectAt` so JSON consumers get `expect{kind,value}`.
* Add a `helpAt` when there is a concrete fix.
* Never silently accept unsupported syntax; fail closed with a code.

## 8. Pull requests

* One logical change per PR; describe which gate commands you ran.
* Do not reformat unrelated files.
* If you change a diagnostic message, keep the code stable — tooling keys on the
  code, not the text.
* Keep generated artifacts and large data out of Git.
