# LIR vs Odin

A feature-by-feature comparison between **LIR** (this repository, bootstrap
compiler `lir 2.3.0`) and **[Odin](https://odin-lang.org)** (Bill Hall, 2016).

**How to read the evidence column**

* **LIR** claims were produced by running this branch's compiler —
  `lir check` / `lir run --backend=vm` — on each construct. Every "supported"
  line corresponds to an entry in `lir lang --json` that `zig build test`
  compiles.
* **Odin** claims come from the official overview, the language FAQ and the
  community style guide ([odin-styleguide](https://github.com/berryp/odin-styleguide)).
  No Odin toolchain was available while writing this, so Odin snippets are
  illustrative, not executed here.
* Where LIR is weaker, it says so. `docs/STATUS.md` is the authoritative gap list.

---

## 1. One-paragraph summary

Both languages are **C replacements for people who want the machine to stay
visible**: no GC, no exceptions, no hidden control flow, compile to native code.
Odin is the mature, data-oriented one: implicit `context` allocators, `#soa`
layout, built-in vector/matrix/quaternion maths, `distinct` types, `or_return`
error propagation, an excellent C FFI, and a decade of production use
(EmberGen, Blick and others). LIR is the small, *self-describing* one: a
deliberately tiny core (65 supported constructs, 71 reserved words, 131
builtins) whose compiler publishes its own machine-readable catalogue, emits
coded diagnostics with machine-fixable `expect{kind,value}` metadata, and ships
a portable IR VM so a generated program can be validated and run with no
toolchain at all.

Put differently: **Odin optimises for the programmer's throughput and cache
behaviour; LIR optimises for a generator's ability to be correct on the first
try.**

---

## 2. Side-by-side at a glance

| Dimension | LIR (this repo) | Odin |
|---|---|---|
| First release | 2024–2026, bootstrap (v2.3.0) | 2016, ~10 years of iteration |
| Compiler written in | Zig (bootstrap) + a partial self-hosted corpus | Odin (self-hosted) |
| Syntax family | C/Go-ish, newline statements, `let`/`let mut` | Pascal/Go-ish, `x := 10`, `val: int` |
| Memory | explicit `@malloc`/`@free`, `@array_*`, `@map_*` | explicit, **allocator via implicit `context`** (heap + temp arena) |
| Zero-init | no (struct literal must name every field) | **yes** — "zero is initialization" |
| Generics | `fn id<T>(x: T) -> T`, `Box<T>` | parametric polymorphism with `$T: typeid` |
| Closures | **yes** — `\|x: i64\| x + 1`, captures | **no** — no closures or function literals |
| Methods | `impl` blocks, `self` / `self: *mut Self` | free procedures; no type-bound methods |
| Traits / interfaces | `trait` + `dyn Trait` dispatch | no interfaces; tagged unions + `switch` |
| Error handling | `Result<T,E>`, `?`, `??`, `Option<T>` | multiple returns + `or_return` / `or_else` |
| Sum types | `enum` with payloads, exhaustive `match` | tagged `union` + exhaustive `switch` |
| Distinct/new types | no (`type X = i64` is a plain alias) | **yes** — `distinct` with explicit casts |
| Slices | `[]T` accepted, **no range slicing** (`a[1..3]` rejected) | **yes** — `x[:]`, `x[a:b]` free on arrays/dynamic/slices |
| Dynamic arrays | `@array_new` / `@array_push` (raw pointer) | `[dynamic]T` + `append`, `make`/`delete` |
| Maps | `@map_*` builtins | `map[K]V` with `m[k]`, `v, ok :=` |
| Data-oriented layout | no `#soa`, no swizzling | **`#soa`, array programming, swizzles** |
| Built-in math types | no vectors/matrices | vectors, matrices, quaternions in the language |
| Concurrency | **in the language**: `spawn`, `@chan_*`, `@mutex_*`, `@atomic_*` | library only: `core:thread`, `core:sync` |
| Bounds checks | compile-time where provable, otherwise trap (exit 132) | runtime bounds checks (removable with a flag) |
| Compile-time static checks | **UAF/double-free/defer-conflict/leak/loop-leak, purity, contracts, bounded ranges, thread-capture** | `-vet`, `#no_bounds_check`, `assert`/`ensure`; no ownership analysis |
| C FFI | **none** (`extern` is rejected, fail-closed) | **excellent** — `foreign import`, `#link_name`, COM/Obj-C interop |
| `defer` semantics | end of enclosing block | end of enclosing scope (matches) |
| Cross-compilation | x86-64 ELF + wasm32-wasi direct; 8 more targets via C11 | Windows/Linux/macOS natively, WASM in progress |
| Hot reload | no | yes (`core:hot_reload`) |
| Formatter / LSP | **no** (documented gap); `lir explain` instead | `odinfmt`, `ols` |
| Package manager | none (local `import` only) | none by design — vendoring |
| Machine-readable language catalogue | **yes** — `lir lang --json`, CI-verified | no (prose docs + style guide) |
| Structured diagnostics | **yes** — `lir.diagnostics.v1`, stable `LIR-Exxxx`, `expect{kind,value}` | human-readable compiler errors |
| Portable interpreter | **yes** — `--backend=vm` for every target | no (compiles, you run the binary) |
| Production users | none known | EmberGen, GeoGen, LiquiGen, Blick, … |

---

## 3. The same program, twice

### 3.1 Hello + a struct with a method

```lir
// LIR — verified: lir run --backend=vm
struct Counter {
    value: i64
}

impl Counter {
    fn get(self) -> i64 { return self.value }
    fn bump(self: *mut Counter) -> i64 {
        self.value = self.value + 1
        return self.value
    }
}

fn main() -> i64 {
    var c = Counter { value: 0 }
    c.bump()
    println("value={c.get()}")
    return 0
}
```

```odin
// Odin — illustrative (free procedures, no methods, `p->x` auto-deref)
Counter :: struct {
	value: i64,
}

counter_get :: proc(c: Counter) -> i64 { return c.value }
counter_bump :: proc(c: ^Counter) -> i64 {
	c.value += 1
	return c.value
}

main :: proc() {
	c := Counter{}          // zero-initialised
	counter_bump(&c)
	fmt.println("value=", counter_get(c))
}
```

What differs in kind, not detail:

* LIR groups behaviour under the type (`impl`); Odin deliberately does not.
* Odin's `Counter{}` is a valid zero value; LIR requires every field
  (`Counter { }` is `LIR-E3004 missing field 'x'`).
* Odin's `fmt.println` is variadic and formats anything; LIR's `println` takes a
  string and `printInt`/`printFloat` take numbers — the type checker rejects
  `println(42)`.

### 3.2 Error handling

```lir
// LIR — `?` propagation, `??` default, exhaustive match on Result
fn parse(s: string) -> Result<i64, string> {
    if @string_len(s) == 0 { return Err("empty") }
    return Ok(@string_to_int(s))
}

fn divide(a: i64, b: i64) -> Result<i64, string> {
    if b == 0 { return Err("division by zero") }
    return Ok(a / b)
}

fn main() -> i64 {
    let v = match divide(20, 4) {
        Ok(n) => n,
        Err(_) => -1,
    }
    let d = parse("") ?? 7          // default on Err
    printInt(v + d)
    println("")
    return 0
}
```

```odin
// Odin — errors are ordinary last return values
Parse_Error :: enum { Empty, Not_A_Number }

parse :: proc(s: string) -> (value: i64, err: Parse_Error) {
	if len(s) == 0 { return 0, .Empty }
	return strconv.parse_i64(s) or_return
}

divide :: proc(a, b: i64) -> (n: i64, err: Parse_Error) {
	if b == 0 { return 0, .Not_A_Number }
	return a / b, nil
}

main :: proc() {
	n, err := divide(20, 4)
	if err != nil { n = -1 }
	// or_return in a proc with matching named results:
	//   v := parse("42") or_return
}
```

Both refuse exceptions. LIR models failure as a value in the type system
(`Result<T,E>`, so a `match` must handle both cases); Odin keeps it a convention
enforced by exhaustiveness on the error enum and the `or_return` shorthand.

### 3.3 Generics

```lir
fn max_of<T>(a: T, b: T) -> T { return @max(a, b) }

struct Box<T> { value: T }

fn main() -> i64 {
    let b = Box<i64> { value: 3 }
    printInt(max_of<i64>(b.value, 7))
    println("")
    return 0
}
```

```odin
max_of :: proc(a, b: $T) -> T { return max(a, b) }

Box :: struct($T: typeid) { value: T }

main :: proc() {
	b := Box(i64){ value = 3 }
	_ = max_of(b.value, 7)   // T inferred, not written
}
```

Odin **infers** the type parameter from the argument; LIR requires the explicit
`<i64>` at call/construction sites (its monomorphiser is deliberately literal).
Odin's `typeid/[]$E` constraints have no LIR equivalent.

### 3.4 Cleanup

```lir
fn main() -> i64 {
    {
        defer println("inner block done")
        println("body")
    }
    defer println("function done")
    return 0
}
// verified output: body / inner block done / function done
```

Odin's `defer` also runs at end of scope, so this is a genuine match rather than
a LIR invention. LIR additionally *statically* rejects the classic mistakes —
double free, use-after-free, `defer` conflict, a `break` inside `defer`, and
(verified) a heap allocation assigned inside a loop that leaks on the next
iteration.

---

## 4. Where Odin is clearly ahead

1. **Memory ergonomics.** Odin's implicit `context` carries the allocator and a
   temp arena into every procedure, so `make`/`new` work in library code you
   don't control and arenas are a one-liner. LIR has raw `@malloc`/`@free` and
   no allocator abstraction at all.
2. **Zero-init by default.** Odin's "zero is initialization" removes a whole bug
   class. LIR forces explicit initialisation but leaves heap memory
   uninitialised.
3. **Data-oriented toolkit.** `#soa`, array programming, swizzles, built-in
   `vector`/`matrix`/`quaternion` types, `bit_set`. LIR has none of these; a
   SIMD/SoA workload is simply not LIR's territory yet.
4. **`distinct` types.** `type Celsius = distinct i64` buys unit safety for free.
   In LIR an alias is transparent and `let c: Celsius = 5` is unguarded.
5. **Slices.** `x[:]`, `x[1..3]`, `for &x in xs`. LIR accepts `[]T` but rejects
   range slicing (`LIR-E2001 expected rbracket, got dot_dot`) — this is the
   single most annoying difference when porting Odin-shaped code.
6. **C FFI.** `foreign import` + `#link_name` is a first-class feature and the
   reason Odin ships DirectX/Metal/Vulkan/OpenGL bindings. LIR rejects `extern`
   outright (fail-closed) and can only reach the OS through builtins.
7. **Ecosystem and maturity.** Ten years, a large `core:`/`vendor:` library,
   `odinfmt`, `ols`, hot reload, real games shipped. LIR is a bootstrap compiler
   with 131 builtins, 16 embedded modules, no formatter and no LSP.
8. **Auto-dereference ergonomics.** `p.x` on a `^T` just works in Odin; LIR needs
   `(*p).x`-style explicitness in places and `self: *mut Self` for mutating
   methods.

## 5. Where LIR is clearly ahead

1. **Machine-readable language definition.** `lir lang --json` returns every
   construct with a status, notes, an `avoid` list and a **compiled** example;
   `lir lang --keywords` returns the reserved-word list from the lexer;
   `lir lang --cheatsheet` renders the whole language to one page. Odin
   publishes prose plus a community style guide. For an LLM writing code, the
   LIR catalogue is directly consumable; Odin's is not.
2. **Diagnostics that are repairable by a program.** Every LIR error has a stable
   code, a span, a `help:` line, and usually `expect{kind,value}`:

   ```
   error[LIR-E3002]: call to undefined function 'printint'; did you mean 'printInt'?
      = help: declare the function with 'fn', or import the module that defines it
      expect = {"kind":"function","value":"printInt"}
   ```

   `--diagnostics=short` and `--json` (`lir.diagnostics.v1`) exist as first-class
   contracts. Odin's compiler errors are human prose.
3. **Compile-time ownership analysis.** LIR rejects, before code generation:
   use-after-free, double free, `defer`/close conflicts, leaks from allocations
   inside loops, dangling returns of pointers to locals, capturing a local by
   reference into a thread, mutation of captured variables inside `spawn`, and
   unsynchronised writes to shared pointers inside `spawn` (`@atomic_*`/mutex
   required). Odin has none of this; it relies on the programmer plus `-vet`.
4. **Contracts, purity and bounded ranges in the language.**
   `#[pre(expr)]`, `#[post(result …)]`, `#[pure]`, `type Percent = i64 range 0..100`
   — verified for constant arguments at compile time. Odin offers `assert`/
   `ensure` at runtime only.
5. **Concurrency in the language, statically gated.** `spawn`, channels, mutexes
   and atomics are keywords/builtins, and a construct the target cannot provide
   is a *compile* error (`LIR-E7004` for threads on wasm32-wasi) rather than a
   runtime trap. Odin's equivalent lives in `core:thread`/`core:sync`.
6. **A portable VM backend.** `lir run f.lir --backend=vm` executes on any host
   with identical semantics and traps — no C toolchain, no linker, no binary.
   That is what makes "generate → validate → execute" a tight loop for an agent.
7. **Cross-target reach without a toolchain.** x86-64 ELF and `wasm32-wasi` are
   emitted directly; 8 further triples go through C11 when `zig`/`cc` is present.
   Odin targets desktop OSes natively and is still finishing WASM.
8. **Fail-closed philosophy.** Anything unimplemented is rejected with a code and
   the catalogue marks it `unsupported` with an `avoid` note — no silent
   miscompilation, and no documentation that drifts (CI diffs the generated
   reference and cheatsheet against the compiler).

## 6. Philosophy in one line each

| | Odin | LIR |
|---|---|---|
| Design centre | data-oriented systems work (games, graphics, simulation) | a small core that machines and humans can both verify |
| "Simple" means | fewer abstractions, direct control, zero-init, no OOP | fewer constructs, everything documented, nothing silently accepted |
| Memory | allocators chosen per scope via `context` | explicit `@malloc`/`@free`, verified statically for the mistakes that can be proven |
| Errors | ordinary values + `or_return` | `Result`/`Option` in the type system + `?`/`??` |
| Optimises for | programmer throughput and cache behaviour | first-try correctness for generated code |
| Risk profile | trusts the programmer, removes ceremony | refuses to guess, refuses to emit |

## 7. What LIR should borrow (and what it should not)

Worth borrowing, in rough order of value:

1. **Slices** — `x[:]`, `x[a:b]`, `for &x in xs`. Currently the biggest gap for
   porting and for idiomatic array code. (`slice_type` is already marked
   `partial` in the catalogue.)
2. **Allocator abstraction** — even a single `Allocator` struct passed
   explicitly would let libraries be allocator-agnostic without Odin's implicit
   context.
3. **`distinct` types** — cheap to implement (a flag on the alias), high payoff
   for unit-safety, and easy to describe in the catalogue.
4. **Zero-init for heap allocations** — one builtin (`@calloc`) or a documented
   default; removes a class of generated-code bugs.
5. **Multiple return values** — already supported (`-> (i64, i64)` is verified);
   worth promoting in the catalogue and docs as the idiomatic error channel.

Not worth copying: no-closures (LIR's closures are used by `spawn` and
comprehensions), no-methods (LIR's `impl` keeps `dyn Trait` dispatch simple), and
the implicit context (it conflicts with LIR's "explicit and checkable" stance —
though `docs/STATUS.md` notes an allocator interface as a possible future).

## 8. Choosing between them

* **Use Odin** for games, engines, graphics, simulation, anything needing C
  libraries, SoA layout, hot reload, or a decade-proven toolchain.
* **Use LIR** when the code is generated or reviewed by machines, when you want
  a program validated *and executed* with no toolchain (`--backend=vm`), when
  you want the compiler to refuse unsafe patterns instead of trusting you, and
  when a stable machine contract (`lir.diagnostics.v1`, `LIR-Exxxx`) matters more
  than a large standard library.
* **Porting Odin → LIR**: replace methods with free functions or keep `impl`
  (LIR supports it), replace `distinct` with plain aliases (and lose the
  checking), replace slices with `[]T` plus explicit indices, replace `context`
  allocators with explicit `@malloc`/`@free`, and replace `or_return` with `?`.

---

*LIR side verified with `lir 2.3.0` on this branch: `zig build test` 115/115,
`tests/ai_test.py` green, `examples/canonical-tour.lir` byte-identical on
vm/native/c/wasm. Odin side reflects the official documentation and the
community style guide; nothing there was executed in this environment.*
