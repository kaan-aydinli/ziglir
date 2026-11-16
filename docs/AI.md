# LIR for AI systems and automation

This document is the contract between the LIR toolchain and anything that
generates, repairs or evaluates LIR code automatically (LLM agents, code
assistants, CI bots, transpilers).

Three rules make integration reliable:

1. **Ask the compiler, don't guess.** `lir lang` / `lir builtins` are generated
   from the implementation and compiled by the test suite.
2. **Validate before claiming success.** `lir check --json` (or `lir build`)
   must return `"status":"ok"`; a non-zero exit means the code is wrong.
3. **Repair from structure, not prose.** Every diagnostic has a stable code, a
   span, and usually `expect{kind,value}`.

---

## 1. Discovery: what does LIR accept?

```sh
lir lang --json                 # full catalogue        → schema lir.lang.v1
lir lang --keywords --json      # reserved words        → schema lir.keywords.v1
lir lang --status=unsupported --short   # what NOT to generate
lir lang <feature>              # one feature with a compilable example
lir lang --markdown             # regenerate docs/LANGUAGE_REFERENCE.md
lir builtins --json             # builtin signatures    → schema lir.builtins.v1
lir explain --list --json       # conceptual topics + diagnostic codes
lir explain ai                  # the same guidance, in the terminal
```

### `lir.lang.v1`

```json
{
  "schema": "lir.lang.v1",
  "language": "lir",
  "compiler": "ziglir-bootstrap",
  "features": [
    {
      "name": "closure",
      "status": "supported",
      "category": "expression",
      "syntax": "let f = |x: i64| x + 1",
      "notes": "Pipe-delimited lambdas …",
      "example": "fn main() -> i64 {\n    …\n}",
      "avoid": "|x|..., fn(x: i64) -> i64 { }  (closures are not 'fn' literals)"
    }
  ],
  "keywords": ["fn", "let", "var", "mut", "const", "…"],
  "counts": { "supported": 65, "partial": 2, "legacy": 3, "unsupported": 6 }
}
```

`keywords` is the complete reserved-word list, taken from the lexer's own table
(71 words, including words that are reserved but unimplemented: `async`,
`await`, `unsafe`, `asm`, `extern`, `mod`, `i128`, `u128`, `where`, …). Never
emit one of these as an identifier, parameter, field or function name.
`lir lang --keywords` prints the same list (tab-separated with the token kind);
`lir lang --keywords --json` returns `lir.keywords.v1`.

Field semantics:

| Field | Meaning |
|---|---|
| `status: supported` | implemented for all backends; safe to emit |
| `status: partial` | implemented with documented limits — read `notes` |
| `status: legacy` | accepted but not canonical — emit `prefer` instead |
| `status: unsupported` | the compiler rejects it; `avoid` names the construct |
| `syntax` | canonical shape, one line (may contain `\n` for multi-line forms) |
| `notes` | limits, traps, and interactions a generator must respect |
| `example` | complete program; compiled and executed by `zig build test` |
| `avoid` / `prefer` | do-not-emit spellings and their canonical replacement |

Fifteen habits from other ecosystems are rejected by this compiler and are the
most common cause of wasted generation attempts — see
`lir explain limitations` and `--status=unsupported`:

`async/await`, `unsafe { }`, `asm(...)`, `extern fn`, `mod x`, `i128`, `char`,
nested `fn`, `fn(x){}` closures, labelled loops, `for i, v in arr`,
`a[..]` slicing, `{x:#x}` format specs, struct-typed struct fields,
`Option<Option<T>>` (`>>` is a shift token), `not x`, implicit numeric widening,
`pure fn`/`requires`/`ensures`, and same-scope shadowing.

---

## 2. Validation: `lir check --json`

```sh
$ lir check src/main.lir --json
{"schema":"lir.check.v1","status":"ok","file":"src/main.lir","target":"x86_64-linux"}
# exit 0
```

On failure, **stdout stays a single JSON object** and the full diagnostic list is
emitted as one JSON document on **stderr**:

```sh
$ lir check src/main.lir --json
{"schema":"lir.check.v1","status":"error","file":"src/main.lir",
 "target":"x86_64-linux","error":"TypeMismatch"}          # stdout, exit 1
```

```json
{
  "schema": "lir.diagnostics.v1",
  "status": "error",
  "errors": 1,
  "warnings": 0,
  "truncated": false,
  "diagnostics": [
    {
      "code": "LIR-E3004",
      "severity": "error",
      "file": "src/main.lir",
      "line": 2,
      "column": 5,
      "length": 1,
      "message": "annotation on 'x' is 'i64' but the initializer has type 'string'",
      "help": "make the initializer a 'i64', or annotate the variable as 'string', or add 'as i64'",
      "expect": { "kind": "type", "value": "i64" }
    }
  ]
}
```

### Diagnostic fields

| Field | Type | Use |
|---|---|---|
| `code` | string | stable identifier, `LIR-E<4 digits>` (errors) / `LIR-W` (warnings) |
| `severity` | `error` \| `warning` \| `note` | gate on errors only |
| `file`,`line`,`column`,`length` | numbers | exact edit location (1-based) |
| `message` | string | human summary — do not parse |
| `help` | string? | the concrete fix, when one exists |
| `expect.kind` | string? | `token`, `identifier`, `function`, `builtin`, `struct`, `field`, `type`, `module`, `argument_count`, `assignable_location`, … |
| `expect.value` | string? | the exact token/name/type that was legal there |

### Repair loop

```
check → if status ok: done
       else: read diagnostics[0].expect
             (kind=builtin, value=printInt  → replace the callee name)
             (kind=token,   value=rbrace    → insert the missing token)
             (kind=type,    value=i64       → change the annotation or add a cast)
             re-check; stop when status=ok or the same code repeats twice
```

Codes are stable across releases, messages are not. Full code families:

| Range | Stage |
|---|---|
| `LIR-E1xxx` | lexer (invalid character, literal, capacity) |
| `LIR-E2xxx` | parser (syntax, unsupported statement/declaration/type) |
| `LIR-E3xxx` | semantic analysis (names, types, arguments, borrow/UAF, purity, contracts) |
| `LIR-E4xxx` | module loading (unresolved import, read failure, capacity) |
| `LIR-E5xxx` | capacity limits (AST, IR string table) |
| `LIR-E6xxx` | IR verification and backends |
| `LIR-E7xxx` | driver: target triple, missing entry point, missing input |

`lir explain LIR-E3004` (or `e3004`, `3004`) prints cause/fix/example, and
`lir explain --list --json` lists every documented code.

### Plain-text formats

`--diagnostics=human` (default) prints `file:line:col: error[CODE]: …` plus a
caret and a `= help:` line. `--diagnostics=short` prints one line per
diagnostic for log scrapers:

```
LIR-E3002 1:20 error function call to undefined function 'printint'; did you mean 'printInt'? [printInt] (src/main.lir)
```

---

## 3. Execution and build results

```sh
lir run src/main.lir --backend=vm -- arg1 arg2     # portable, instant, same traps
lir run src/main.lir                               # native ELF via the default backend
lir build src/main.lir -o app --json
```

`lir.build.v1` (stdout):

```json
{"schema":"lir.build.v1","status":"ok","input":"src/main.lir","output":"app",
 "bytes":12314,"backend":"native-elf","target":"x86_64-linux","optimization":"O2"}
```

Failure envelopes keep the same `schema` with `"status":"error"` and an
`"error"` field naming the compiler error. Exit codes:

| Code | Meaning |
|---|---|
| `0` | success |
| `1` | compilation/check error (see diagnostics) |
| `132` | the compiled program trapped (SIGILL: bounds, div-by-zero, assert) |

`lir test` runs the `#[test]` suite and prints `PASS`/`FAIL` per test.

---

## 4. Bootstrapping a project

```sh
lir init demo --ai
```

creates `project.manifest`, `src/main.lir`, `src/lib.lir`, `src/tests.lir`,
`.gitignore`, plus:

* `AGENTS.md` — the ten rules that most often break generated LIR, and the
  commands to validate;
* `lir.agent.json` — machine-readable pointer manifest (`lir.agent.v1`):

```json
{
  "schema": "lir.agent.v1",
  "language": "lir",
  "compiler": "ziglir-bootstrap",
  "commands": {
    "catalogue": "lir lang --json",
    "builtins": "lir builtins --json",
    "check": "lir check <file> --json",
    "run": "lir run <file> --backend=vm",
    "test": "lir test"
  },
  "diagnostics": "lir.diagnostics.v1 (stderr JSON, stable codes LIR-Exxxx)",
  "exit_codes": { "ok": 0, "compile_error": 1, "trap": 132 },
  "validate_before_claiming_success": true
}
```

---

## 5. Canonical generation rules

Short list of the invariants that distinguish valid LIR from C/Rust/Zig-shaped
output. `lir lang` is authoritative; this is the fast path.

```lir
fn main() -> i64 {           // newline statements, braces everywhere
    let mut total = 0        // 'let mut' (not 'var')
    for i in 0..=3 {         // '..' exclusive, '..=' inclusive
        total += i
    }
    let label = total > 4 ? "big" : "small"     // ternary is fine
    println("total={total} ({label})")          // strings only, no specifiers
    printInt(total)                             // numbers: printInt/printFloat
    let shape = (total, true)                   // tuple, t.0 / let (a,b) = t
    let (n, ok) = shape
    if ok and n > 0 {                           // 'and'/'or'/'!', never 'not'
        return (n as u8) as i64                 // explicit casts only
    }
    return 0
}
```

* Exactly one `fn main() -> i64` (return value is the exit code).
* `match` arms end with `,` and the match must be exhaustive.
* `Some`/`None`/`Ok`/`Err` need a typed context.
* Free the heap: `@free`, `@array_free`, `@map_free`.
* Validate with `lir check --json` before reporting success.

---

## 6. Why this matters for evaluation

Because the catalogue is compiled by `zig build test`, an agent can trust the
following chain end-to-end:

```
src/bootstrap/langref.zig  ──(zig build test compiles every example)──►  lir lang --json
                                                                          │
                                                       agent reads it ────┘
                                                                          │
                                              generates LIR ──► lir check --json
                                                                          │
                                                       ok? ──► lir run --backend=vm
```

There is no separate documentation site to go stale. When the compiler gains or
loses a feature, the catalogue, the reference document, `lir explain` coverage
tests and the machine contract move together in the same change.
