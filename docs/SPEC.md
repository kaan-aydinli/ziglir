# LIR Language Specification

**Version:** 2.3 (bootstrap reference) · compiler `lir 2.3.0`
**Status of this document:** describes what the **checked-in bootstrap compiler
actually accepts, checks and executes**. Anything not implemented is explicitly
labelled *planned* (see [ROADMAP.md](ROADMAP.md)).

> **Ground truth.** The authoritative, always-current list of syntax is generated
> from the compiler itself:
>
> ```sh
> lir lang                 # human-readable catalogue with examples
> lir lang --json          # machine-readable (schema lir.lang.v1)
> lir lang --keywords      # reserved words (schema lir.keywords.v1 with --json)
> lir lang --markdown      # regenerate docs/LANGUAGE_REFERENCE.md
> lir builtins --json      # every builtin + signature
> lir check file.lir --json # validate; lir.diagnostics.v1 on stderr
> ```
>
> [`LANGUAGE_REFERENCE.md`](LANGUAGE_REFERENCE.md) is generated from that table
> and every `supported` example is compiled and executed by `zig build test`, so
> it cannot silently drift from the implementation.

---

## 1. Overview

LIR is a small, performance-first systems language. Its reference
implementation, **Ziglir**, is a Zig bootstrap compiler that emits:

| Backend | Target | External toolchain |
|---|---|---|
| `native` (ELF64) | `x86_64-linux` | none |
| `wasm` | `wasm32-wasi` | none (Wasmtime/Node to run) |
| `c` / `--emit-c` | `aarch64`/`riscv64`/macOS/Windows/FreeBSD/Linux | `cc` or `zig cc` |
| `vm` | any host | none |

Design goals (not guarantees): a small and consistent core syntax, predictable
layout and allocation, checks that are on by default, and evidence-backed
performance claims.

### 1.1 One-page example

```lir
import core

enum Shape {
    Square(i64),
    Empty,
}

fn area(shape: Shape) -> i64 {
    return match shape {
        Shape::Square(side) => side * side,
        Shape::Empty => 0,
    }
}

fn main() -> i64 {
    let mut total = 0
    for i in 1..=3 {
        total += area(Shape::Square(i))
    }
    println("total = {total}")
    return 0
}
```

---

## 2. Lexical structure

* **Encoding:** UTF-8 source; identifiers are ASCII `[A-Za-z_][A-Za-z0-9_]*`.
* **Statement separation:** newlines. `;` is accepted and ignored, but is never
  required and must **not** be placed between `if`/`else` blocks.
* **Comments:** `#` to end of line, `//` to end of line, `///` documentation
  comment, and nested `/* ... */`. `#[` introduces an attribute and `#{` a map
  literal, so they are not comments.
* **Literals:**
  * integers — decimal, `0xFF`, `0b1010`, `0o17`, with `_` separators; must fit
    in `i64` (diagnostic `LIR-E1004` otherwise)
  * floats — `1.5`, `2.5e3` (binary64 value; `f32` rounding only on cast)
  * strings — `"..."` with `\n \t \r \\ \" \0`; interpolation `"{expr}"`
  * chars — `'A'` is an **`i64` code point**, not a distinct type
  * booleans — `true`, `false`; `null` exists only for pointer contexts

---

## 3. Types

### 3.1 Primitive

```
i8 i16 i32 i64 u8 u16 u32 u64 isize usize    integers (8-byte slot)
   f32 f64                                  IEEE-754
   bool                                     distinct from integers
   string                                   immutable, length-prefixed UTF-8
   void  never                              no value / does not return
```

Not available: `i128`, `u128`, `char`, `f16`, `f128`.

### 3.2 Compound

```
(T, U, ...)        tuple, up to 8 fields, accessed as t.0 … t.7
[T; N]  [v; N]     fixed-size array / repeated element
[]T                slice spelling (parses and type-checks; no slicing syntax)
*T  *mut T         pointer to a value; &x / &mut x borrow a local
fn(A) -> R         function value
Option<T>  ?T      optional value
Result<T, E>       success or error (8-byte payloads)
Name / Name::V     struct/enum/union type and variant constructor
dyn Trait          dynamic dispatch
map  chan          builtin handles (@map_*, @chan_*)
```

### 3.3 Conversions

There are **no implicit numeric conversions**. Use `as`:

```lir
let wide: i64 = 300
let byte = wide as u8      // 44 — low 8 bits are kept
let back = byte as i64     // 44
let n = 2.9 as i64         // 2 — truncation toward zero
```

* float → integer traps on `NaN` and out-of-range values;
* integer → float preserves signedness (unsigned values stay non-negative);
* `f32` casts round to binary32 precision before widening;
* a bare integer literal is not a float: `let f: f64 = 1` is rejected.

---

## 4. Declarations

```lir
fn add(a: i64, b: i64) -> i64 { return a + b }
const LIMIT: i64 = 3 ** 4
struct Point { x: i64 y: i64 }              // newline-separated fields
enum Shape { Square(i64), Empty }           // comma-separated variants
union Bits { i: i64 f: f64 }
trait Area { fn area(self) -> i64 }
impl Area for Square { fn area(self) -> i64 { return self.side * self.side } }
impl Point { fn norm1(self) -> i64 { return self.x + self.y } }
type Count = i64
type Percent = i64 range 0..100
import math
import "../lib/util.lir"
```

Rules:

* functions are **top-level only**; there are no nested function declarations
  (use a closure `|x| ...` for local behaviour);
* at most **8 parameters** per function; defaults must follow the parameter and
  may reference global constants;
* struct fields are newline separated and **cannot name another struct type** —
  store `*B` instead. Struct literals use commas: `Point { x: 1, y: 2 }`;
* `proc` is a legacy alias of `fn`; `pub` is accepted and ignored (there is no
  visibility system);
* `mod`, `extern`, and `extern "C"` are rejected (`LIR-E2003`).

---

## 5. Statements

```lir
let x = 1                 // immutable
let x: i64 = 1            // annotated
let mut n = 0             // mutable (legacy: var n = 0)
const K = 2 ** 5          // local compile-time constant
n += 1                    // += -= *= /= %= **= &= |= ^= <<= >>=
if c { } elif c2 { } else { }
unless c { } else { }     // negated if; value-producing
while c { }               // pre-test loop, requires progress
until c { }               // loop until the condition holds
loop { break }            // unconditional loop
for i in 0..n { }         // exclusive range
for i in 0..=n { }        // inclusive range
for v in array { }        // element iteration (arrays and strings)
break  continue           // loops only, not inside defer
return value
defer cleanup()           // LIFO, runs on every scope exit
guard cond else { return }
unreachable
match value { … }         // expression, see §6
```

There are no labelled loops, no `break value`, no `do/while`, no `for(;;)`, and
no index/value pair form (`for i, v in arr` is rejected).

---

## 6. Expressions

| Form | Example |
|---|---|
| arithmetic | `a + b - c * d / e % f`, `2 ** 3 ** 2` (right-assoc) |
| bitwise | `a & b \| c ^ d << e >> f` |
| logic | `a and b`, `a or b`, `!a` (`&&`/`\|\|` are synonyms; `not` does not exist) |
| comparison | `== != < <= > >=` (strings are equality-comparable only) |
| conditional | `cond ? a : b`, `if c { 1 } else { 2 }` |
| call | `f(a, b)`, `recv.method(x)`, `f(name: v)` (named args, direct calls) |
| member | `p.field`, `t.0`, `s.len` |
| index | `a[i]` — fixed arrays and dynamic arrays, bounds-checked |
| cast | `value as u8` |
| closure | `\|x: i64\| x + 1`, `\|\| 7` |
| string | `"a" + "b"`, `"{a + b}"`, `s == "x"` |
| collection | `[1, 2, 3]`, `[0; 8]`, `(1, true)`, `#{ "k": 1 }`, `[i * i for i in 0..4]` |
| option/result | `Some(v)`, `None`, `Ok(v)`, `Err(e)`, `fallible()?`, `maybe ?? 7` |
| concurrency | `spawn f()`, `spawn { … }` |
| comptime | `comptime(2 + 3)`, `comptime fn f() { … }` |

Precedence (high → low): `**` → unary `+ - ! ~ & *` → `* / %` → `+ -` →
`<< >>` → `&` → `^` → `|` → comparisons → `and` → `or` → `?:` → `??` →
assignment.

`match` is an expression; arms are comma separated and **must be exhaustive**
(integers need `_` or `else`, enums need every variant or a fallback, guarded
arms never establish coverage).

---

## 7. Memory, ownership and safety

* Local variables live on the stack; `@malloc`/`@array_new`/`@map_new` allocate
  heap memory and must be released (`@free`, `@array_free`, `@map_free`).
* Borrowing: `&x` and `&mut x`. While a mutable borrow is live, reading or
  writing the owner is a compile error; returning a pointer to a local is
  rejected.
* Compile-time analyses that run by default: use-after-free, double-free,
  double-close, leaks inside loops, constant index out of bounds, constant
  invalid shift counts, division by a constant zero, dangling references,
  stack-frame budget (32 KiB), spin loops that cannot terminate.
* Runtime traps: bounds violations, division/modulo by zero, dynamic shift
  overflow, `NaN`/out-of-range float→int conversions, heap canary corruption.
  A trap terminates the process with status **132**.
* Raw memory is reached only through `@ptr_add`, `@read_u8`, `@write_u64`, …;
  there is no `unsafe { }` block and no inline assembly.

A full Rust-style borrow checker and lifetime inference are **not** implemented;
[ROADMAP.md](ROADMAP.md) tracks that work.

---

## 8. Errors

```lir
fn find(ok: bool) -> Option<i64> {
    if ok { return Some(5) }
    return None
}

fn twice(ok: bool) -> Option<i64> {
    let v = find(ok)?        // propagate None to the caller
    return Some(v * 2)
}

fn main() -> i64 {
    let a: ?i64 = None
    let fallback = a ?? 7    // 7
    return match twice(true) { Some(v) => v, None => 0 }
}
```

`Some`/`None`/`Ok`/`Err` are context typed — `let x = None` without an
annotation or return context is rejected with a hint to add a type.

`main` returns `i64`; the low 8 bits become the process exit status.

---

## 9. Attributes

```lir
#[test]                     // collected by `lir test`
#[inline]  #[cold]          // optimization hints
#[pure]                     // side-effect-free; printing/allocating is rejected
#[pre(b != 0)]              // precondition, verified when arguments are constant
#[post(result >= 0)]        // postcondition
```

Contract syntax is **attribute-based**. The keywords `requires`/`ensures` and
`pure fn` do not parse.

---

## 10. Tooling contract

```sh
lir build file.lir -o app [-O0|-O1|-O2] [--target=…] [--backend=…] [--emit-c]
lir run   file.lir [--backend=vm|native|wasm|c] [-- args…]
lir check file.lir [--json]
lir test  [file.lir]
lir ir    file.lir [-O2]         # dump SSA IR
lir ast   file.lir               # pretty-print the syntax tree
lir lang  [feature] [--json|--markdown]   # language catalogue
lir builtins [name] [--json]              # builtin catalogue
lir explain <topic|LIR-Exxxx>             # knowledge base
lir init  name [--ai]                     # new project (+ agent scaffolding)
lir targets | repl | install | version | help
```

Diagnostics carry a stable code, a span, and usually a `help` line plus an
`expect{kind, value}` field for automated repair:

```
file.lir:2:5: error[LIR-E3004]: annotation on 'x' is 'i64' but the initializer has type 'string'
    2 |     let x: i64 = "text"
      |     ^
      = help: make the initializer a 'i64', or annotate the variable as 'string', or add 'as i64'
```

`--json` turns every command into a machine contract; see [AI.md](AI.md).

---

## 11. Implementation status summary

| Area | Status |
|---|---|
| Frontend (lexer, parser, sema, IR, verifier) | implemented in Zig |
| Native x86-64 ELF, Wasm32-WASI, C11, IR VM backends | implemented |
| Generics, ADTs, `match` with guards, traits/`dyn`, closures, tuples, maps, comprehensions | implemented |
| Compile-time evaluation, contracts, purity, bounded ranges, borrow/UAF analysis | implemented (documented limits) |
| Concurrency: threads, channels, mutexes, atomics | implemented on host targets; threads/channels rejected for `wasm32-wasi` (`LIR-E7004`) |
| Async/await, FFI, `mod` system, macros, package manager, LSP, SIMD | **not implemented** |
| Full borrow checker / lifetime inference | **not implemented** |

Language surface counts, generated: 65 supported, 2 partial, 3 legacy,
6 explicitly-unsupported entries (`lir lang --short`); 71 reserved words
(`lir lang --keywords`). Per-area detail and the known-gap list live in
[STATUS.md](STATUS.md).
