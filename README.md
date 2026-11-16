# LIR — A Simple, Performance-First Systems Language

<p align="center">
  <b>Write simply. Compile natively. Describe itself to machines.</b>
</p>

<p align="center">
  <a href="docs/AI.md">AI integration contract</a> ·
  <a href="docs/LANGUAGE_REFERENCE.md">Generated language reference</a> ·
  <a href="docs/SPEC.md">Specification</a>
</p>

---

## What is LIR?

LIR is a systems-language project aiming to combine a small, approachable syntax with predictable memory use and highly optimized native code. Its Zig-written compiler is named **ZigLIR**; the command-line executable remains `lir`. Its long-term performance goal is to outperform C on selected, benchmarked workloads without sacrificing correctness or readability. That is a goal to prove with reproducible measurements—not a universal speed guarantee. The bootstrap compiler features zero-dependency direct emitters for Linux x86-64 ELF and `wasm32-wasi`, a portable in-process IR VM (`--backend=vm`), and a portable C11 backend (`--backend=c` / `--emit-c`) supporting ARM64, RISC-V, macOS, Windows, FreeBSD, and Linux; features listed as design goals in [Low-Level Language Specification](docs/LOW_LEVEL_LANGUAGE.md) distinguish design requirements from implemented features.

### Design principles

- **Zig-native implementation:** the checked-in bootstrap compiler and native code-generation pipeline are implemented in Zig. Direct `x86_64-linux` ELF64 and `wasm32-wasi` `.wasm` emitters require no external toolchain, while `--backend=c` / `--emit-c` lowers verified IR to strict C11 for cross-platform compilation (`cc` / `zig cc`) and `--backend=vm` runs programs directly in-process.
- **Readable language design:** syntax should stay small and consistent; unsupported features must fail explicitly rather than silently generating incorrect code.
- **Measured performance:** performance claims require repeatable benchmarks against equivalent C implementations, including correctness checks. No universal claim that LIR is faster than C is made.
- **Honest implementation status:** memory safety, compile-time execution, concurrency primitives, cross-compilation, and a stable standard library are not advertised as complete unless they are implemented and tested.

| Capability | Current status |
|---|---|
| Bootstrap compiler implementation | Zig (SSA IR + optimizer + x86-64 ELF, Wasm32-WASI, C11, and IR VM backends) |
| Native output | Zero-dependency Linux x86-64 ELF64 (`ET_EXEC`) & `wasm32-wasi` (`.wasm`); C11 cross-targets for ARM64/RISC-V/macOS/Windows/FreeBSD |
| External compiler required at runtime | No for `x86_64-linux`, `wasm32-wasi`, and `--backend=vm`; optional `cc`/`zig cc` for C11 cross-targets |
| Multi-paradigm features | Generics, ADTs (`Option`/`Result`), `match` + guards, expression `if`/`elif`/`else`, repeat arrays `[val; N]`, compound bitwise/shift ops (`&=`, `|=`, `^=`, `<<=`, `>>=`), `panic(...)`, closures, `trait`/`dyn Trait`, tuples, maps, list comprehensions, string interpolation, unions |
| Compile-time execution | `comptime` blocks/`fn`, `@size_of`, `@align_of`, `@type_name`, `@target_os`, `@target_arch`, `@target_ptr_bits` |
| Built-in concurrency | OS threads (`spawn`, `@thread_join`), channels (`@chan_*`), mutexes, atomics (`@atomic_add`, `@atomic_cas`) |
| Embedded standard library | 16 zero-wrapper embedded modules `std::{core,io,os,sys,net,crypto,json,math,str,algo,testing,collections,hash,fmt,time,http}`: RingBuffer, BitSet, MinHeap/PriorityQueue, Deque, Stack, CRC32, Adler32, Murmur3, FNV1a, Base64 encode/decode, Hex, URL encoding, HTTP parser/builder, calendar/leap year, Levenshtein edit distance, glob pattern matching, QuickSort, binary search, prime tests, vectors, JSON serialization |
| Security & safety architecture | Compile-time UAF/double-free/defer-conflict/close/loop-leak analysis, compile-time heap/string/const-ptr bounds checks, `fn` pointer cast & thread entry validation, 32 KiB per-function stack frame budget, non-terminating spin-loop detection, strict W^X ELF64 (RX `.text`, R-only NX `.rodata`, RW NX `.bss`/stack), CSPRNG `getrandom` stack & heap header/overflow canaries, full zero-wipe on `free`, `<4096`/kernel-space pointer traps, coarse indirect-call CFI, `PROT_NONE` thread stack guard pages, HashDoS-keyed maps, shift traps, exhaustive `match`, strict `?` |
| Optimizer pipeline | `-O2` default on all CLI commands: Cytron SSA `mem2reg`, GVN, trap-safe LICM, counted loop unrolling (up to 8x), magic divisor reciprocal lowering + hardware register multiplier hoisting, algebraic constant reassociation (`(x + c1) + c2 -> x + (c1 + c2)`), double negation elimination (`-(-x) -> x`, `~(~x) -> x`), copy coalescing, DCE |
| Intelligent diagnostics & tooling | Case-insensitive Levenshtein "did you mean '...'?" suggestions for variables, functions, struct names, and fields; unused variable & parameter warnings (`_` prefix suggestion); unreachable code detection; `lir explain` interactive reference; `lir ast` syntax tree visualizer |
| Full borrow checker / embedded `no_std` | Planned (full lifetime borrow checking and bare-metal `no_std` remain future work) |
| Performance versus C | Must be established workload-by-workload with reproducible benchmarks |

## Comparison vs C, Rust, Zig, and Go

| Capability | C (C23) | Rust | Zig | Go | LIR (Current Bootstrap) |
|---|---|---|---|---|---|
| Direct native ELF/WASM without external linker | No | No (LLVM + lld) | Self-hosted | Go linker | **Yes** (`x86_64-linux` ELF64 & `wasm32-wasi` `.wasm`) |
| Generics (`fn<T>`, `struct<T>`) | No (`_Generic`) | Yes | Yes (`comptime`) | Yes | **Yes** (monomorphized) |
| Algebraic data types (`Option`/`Result` + `?`) | No | Yes | Error unions (`!T`) | Multi-return | **Yes** (`Option`/`Result`, `?`, `??`) |
| Expression-valued `if`/`elif`/`else` & `match` | Ternary only | Yes | Yes | No | **Yes** (`if`/`elif`/`else`, `match`) |
| Fixed arrays `[N]T` + `[val; N]` + bounds checks | Manual | Yes | Yes | `[N]T` | **Yes** (compile + runtime bounds + zero-fill) |
| Bitwise/shift compound ops (`&=`, `|=`, `^=`, `<<=`, `>>=`) | Yes | Yes | Yes | Yes | **Yes** (signed/unsigned + shift checks) |
| Compile-time execution (`comptime`) | `constexpr` | `const fn` | Yes | `const` only | **Yes** (`comptime` blocks & `fn`) |
| Built-in OS threads, channels, atomics | C11 / pthreads | `std::sync` / `mpsc` | `std.Thread` | Goroutines / chan | **Yes** (`spawn`, `@chan_*`, `@atomic_*`) |
| Built-in W^X + stack/heap canaries + zero-on-free | Flag-dependent | Flag-dependent | Debug/Safe | Runtime GC | **Yes** (always-on CSPRNG + W^X/NX + zero-wipe) |
| `panic(...)` + trap on null/div0/OOB/shift | UB by default | Panic | Safety-checked | Panic | **Yes** (stderr message + `ud2` trap + bounds checks) |
| Full lifetime borrow checker / GC | No | Borrow checker | Manual/arenas | Tracing GC | Compile-time UAF/leak/defer/bounds analysis (full borrow checker planned) |
| Multi-target architectures (ARM64/RISC-V/etc.) | Yes | Yes | Yes | Yes | **Yes** (`x86_64`/`aarch64`/`riscv64`/`wasm32` across Linux/macOS/Windows/WASI/FreeBSD) |

## Quick Start

The bootstrap compiler is built with **Zig 0.13.0** and runs on Linux, macOS, and Windows.

```bash
git clone https://github.com/sswweett00/ziglir.git
cd ziglir

# Build the compiler and run its unit tests
zig build -Doptimize=ReleaseFast
zig build test

# Ask the compiler what the language actually accepts
./zig-out/bin/lir lang
./zig-out/bin/lir builtins --group=string
./zig-out/bin/lir explain ai

# List supported cross-compilation targets and backends
./zig-out/bin/lir targets

# Compile and run natively or via portable IR VM / Wasm32-WASI / C11
./zig-out/bin/lir build tests/fixtures/test.lir -o /tmp/lir-example
/tmp/lir-example
./zig-out/bin/lir run examples/hello-world/src/main.lir --backend=vm
./zig-out/bin/lir build examples/hello-world/src/main.lir --target=wasm32-wasi -o /tmp/hello.wasm
./zig-out/bin/lir build examples/hello-world/src/main.lir --target=aarch64-macos -o /tmp/hello-mac

# Optional: generate a starter project
./zig-out/bin/lir init myproject
cd myproject
../zig-out/bin/lir check
../zig-out/bin/lir run
../zig-out/bin/lir test
../zig-out/bin/lir build
./myproject.out
```


See [Project workflows](docs/PROJECTS.md) for manifest settings, directory selection,
output paths, and the remaining application/ecosystem roadmap.

## Built for AI systems and automation

LIR is designed so that a code-generating agent never has to guess: the compiler
describes itself in machine-readable form, validates what it is given, and hands
back structured repairs.

```bash
lir lang --json                  # every feature + status + compilable example
lir lang --keywords              # the reserved-word list (never use as names)
lir lang --cheatsheet            # one generated page that fits a small context window
lir lang --status=unsupported    # what NOT to generate, with `avoid` notes
lir builtins --json              # every builtin signature
lir check main.lir --json        # {"schema":"lir.check.v1","status":"ok",...}
lir run main.lir --backend=vm    # execute anywhere, no toolchain needed
lir explain ai                   # the agent workflow, in the terminal
lir init demo --ai               # scaffold + AGENTS.md + lir.agent.json
```

Three properties make this trustworthy rather than aspirational:

1. **Generated, not written.** `docs/LANGUAGE_REFERENCE.md` is emitted by
   `lir lang --markdown` from `src/bootstrap/langref.zig`.
2. **Executable.** `zig build test` compiles every `supported` example in that
   catalogue and asserts that every `unsupported` spelling is rejected — the
   documentation cannot drift from the compiler without failing tests.
3. **Repairable output.** Diagnostics carry stable codes (`LIR-E3004`), a span,
   a `help` line, and `expect{kind,value}` so a generator can fix source
   structurally instead of parsing English:

```json
{"code":"LIR-E3002","line":1,"column":20,
 "message":"call to undefined function 'printint'; did you mean 'printInt'?",
 "expect":{"kind":"function","value":"printInt"}}
```

See [AI.md](docs/AI.md) for the full contract (`lir.lang.v1`,
`lir.builtins.v1`, `lir.diagnostics.v1`, `lir.check.v1`, `lir.build.v1`,
`lir.agent.v1`) and [LANGUAGE_REFERENCE.md](docs/LANGUAGE_REFERENCE.md) for the
canonical syntax.

## Browser execution (initial bridge)

The existing Wasm output can run in a browser using the small WASI host in
`runtime/browser/wasi.mjs`. A button-driven LIR counter demonstrates argument
input and safe text output. DOM/events remain JavaScript; this is not yet a
full frontend framework or an HTTP server. See [Browser bridge](docs/BROWSER.md)
for build/run instructions, supported imports and execution limits.

## Development checks

```bash
zig build test
python3 tests/cli_test.py ./zig-out/bin/lir
# Requires a host C compiler and Node 22+ or Wasmtime
python3 tests/backend_test.py ./zig-out/bin/lir
python3 tests/core_test.py ./zig-out/bin/lir
python3 tests/call_test.py ./zig-out/bin/lir
python3 tests/project_test.py ./zig-out/bin/lir
python3 tests/browser_test.py ./zig-out/bin/lir
zig build run -- version
```

`lir init <name>` creates a **new directory** and refuses existing destinations;
it never overwrites an existing project. See [Bootstrap review](docs/REVIEW.md)
for the review scope, regression coverage, and remaining correctness priorities.

## Hello World

```lir
import core

fn main() -> i64 {
    println("Hello, World!")
    0
}
```

## New language extensions

The bootstrap now supports **`loop`**, **unary `+`**, right-associative integer
`**` exponentiation and mutable-`i64` `**=` assignment, correctly signed/unsigned
conversions between integers and `f32`/`f64` (including range traps and
narrow-width rounding), and eight typed integer intrinsics:
`@rotl`, `@rotr`, `@bit_reverse`, `@is_power_of_two`, `@signum`,
`@wrapping_add`, `@wrapping_sub`, and `@wrapping_mul`.

```lir
fn main() -> i64 {
    let mut n = 0
    loop {
        n += 1
        if n == 3 { break }
    }
    printInt(2 ** 3 ** 2)       // 512
    printInt(@rotl(1, 3))      // 8
    printInt(@signum(-42))     // -1
    return 0
}
```

See [Language extensions](docs/LANGUAGE_EXTENSIONS.md) for exact type, overflow,
precedence, rotation, and trap semantics, restrictions, and executable examples.

## Distinctive Syntax & Expressive Flow

LIR features a distinctive syntax identity designed to avoid confusion with Rust, Go, or Python while offering ergonomic, readable control flow:

- **`proc` declarations**: Distinctive, clear procedure declarations (`proc name(params) -> Type { ... }`) alongside `fn`.
- **`guard <cond> else { ... }`**: Clean early-exit precondition validation without nested `if` pyramids.
- **`unless <cond> { ... } [else { ... }]`**: Inverted conditional flow both as statements and expressions.
- **`until <cond> { ... }`**: Intuitive inverse loop terminating once the target condition is reached.

```lir
proc safe_divide(numerator: i64, denominator: i64) -> i64 {
    guard denominator != 0 else {
        return -1
    }
    return numerator / denominator
}

proc countdown(start: i64) -> i64 {
    var count = start
    until count <= 0 {
        count -= 1
    }
    return count
}

proc classify(val: i64) -> i64 {
    let result = unless val < 0 { val * 2 } else { 0 }
    return result
}
```

## Typed tuple patterns

```lir
fn sum(pair: (i64, i64)) -> i64 {
    return match pair {
        (0, value) if value > 10 => value,
        (left, right) => left + right,
    }
}
```

Nested tuple patterns and guarded wildcards (`_ if condition => ...`) are
supported. Guards must be boolean, match result types must be compatible, and
inferred tuples retain integer widths and signedness. See
[Core language phases 1–2](docs/CORE_LANGUAGE.md) for the exact scope and restrictions.

Enum payload patterns also support recursive matching, including
`Some(7)`, `Event::Data((1..10, true))`, and
`Event::Nested(Inner::Number(number))`. Payload reads are gated by constructor
tags; refutable payloads do not falsely establish exhaustive variant coverage.
See `examples/enum-patterns.lir` for a runnable example.

## Named arguments and optional parameters

```lir
fn calculate(a: i64, b: i64 = 8, c: i64 = 3) -> i64 {
    return a * 100 + b * 10 + c
}
// Inside a function:
// calculate(1)             -> 183
// calculate(c: 9, a: 2)    -> 289
// calculate(2, c: 5)       -> 285
```

Direct free-function calls support named arguments and trailing scalar-constant
or string-literal defaults. Supplied arguments are evaluated once in source
order. This is **not C#/.NET compatibility**; see
[C# capability scope](docs/CSHARP_SCOPE.md) for restrictions and future work.

## Implemented Language Features

The snippets below compile and run natively with `./zig-out/bin/lir` (verified by `zig build test`). Full borrow checking remains planned work.

### Generics, `Option`/`Result`, `?` / `??`, and Pattern Matching

```lir
struct Box<T> { val: T }

fn half_even(x: i64) -> Option<i64> {
    if x % 2 == 0 { return Some(x / 2) }
    return None
}

fn double_half(x: i64) -> i64 {
    let h = half_even(x) ?? -1
    match h {
        n if n > 10 => n * 2,
        n => n,
    }
}
```

### Closures, Pipe Operator, Traits (`dyn Trait`), and Tuples/Maps

```lir
trait Scorer { fn score(&self) -> i64 }
fn eval_dyn(obj: dyn Scorer) -> i64 { return obj.score() }

fn main() -> i64 {
    let k = 10
    let add_k = |x: i64| -> i64 { return x + k }
    let res = 5 |> add_k
    let m = #{"answer": res}
    println("Result: {m[\"answer\"]}")
    0
}
```

### Concurrency (`spawn`, Channels, Atomics) and `comptime`

```lir
comptime fn table_size() -> i64 { return 6 * 7 }
const SIZE = table_size()

fn main() -> i64 {
    let ch = @chan_new(4)
    let th = spawn { @chan_send(ch, SIZE) }
    let result = @chan_recv(ch)
    @thread_join(th)
    @chan_close(ch)
    println("Result: {result}")
    0
}
```

### Zero-Wrapper Embedded Standard Library & Security Builtins

Importable with `import std::<module>` (or `import <module>`):

- **core** — `min_i64`, `max_i64`, `clamp_i64`, `abs_i64`, `signum`, saturating/checked arithmetic
- **collections** — `RingBuffer` (circular FIFO: `rb_new`, `rb_push`, `rb_pop`, `rb_peek`), `BitSet` (dense words: `bitset_new`, `bitset_set`, `bitset_test`, `bitset_count`, `bitset_union`, `bitset_intersect`), `MinHeap` / `PriorityQueue` (`heap_new`, `heap_push`, `heap_pop`), `Deque` (`deque_push_back`, `deque_push_front`, `deque_pop_front`, `deque_pop_back`), `Stack` (LIFO)
- **hash** — `crc32` (IEEE 802.3), `crc32c` (Castagnoli), `adler32` (Zlib), `murmur3_32`, `fnv1a_64`, `fnv1a_buf`
- **fmt** — `base64_encode`, `base64_decode`, `hex_encode`, `hex_decode`, `int_to_hex`, `hex_to_int`, `int_to_bin`, `format_bytes`
- **time** — `time_now_ns`, `time_now_ms`, `time_now_sec`, `time_diff_ms`, `time_diff_us`, `time_sleep_ms`, `is_leap_year`, `days_in_month`, `format_duration_ms`
- **http** — `http_status_text`, `http_build_response`, `http_parse_method`, `http_parse_path`
- **str** — `str_starts_with`, `str_ends_with`, `str_index_of`, `str_contains`, `str_trim`, `str_to_upper`, `str_to_lower`, `str_repeat`, `str_count`, `str_pad_left`, `str_pad_right`, `str_is_numeric`, `str_is_alpha`, `str_is_alphanumeric`, `str_levenshtein` (edit distance), `str_glob_match` (wildcards `*` and `?`)
- **algo** — `gcd_i64`, `lcm_i64`, `pow_i64`, `quick_sort_i64`, `sort_array_i64`, `bsearch_array_i64`, `lower_bound_i64`, `upper_bound_i64`, `min_element_i64`, `max_element_i64`, `shuffle_array_i64`, `dedup_sorted_i64`, `reverse_array_i64`, `sum_array_i64`
- **math** — `pi`, `tau`, `e_const`, `abs_f`, `sqrt_f`, `sin_f`, `cos_f`, `tan_f`, `hypot`, `floor_f`, `ceil_f`, `round_f`, `clamp_f`, `lerp`, `smoothstep`, `deg_to_rad`, `rad_to_deg`, `vec2_dot`, `vec2_len_sq`, `vec2_dist_sq`, `is_prime_i64`, `next_prime_i64`, `log2_i64`, `log10_i64`
- **io** — `eprint`, `eprintln`, `file_exists`, `file_size`, `read_file`, `write_file`, `append_file`
- **os** — `argc`, `argv`, `getenv`, `sleep_ms`, `now_ns`
- **sys** — `getpid`, `getppid`, `getuid`, `unlink_file`, `mkdir_dir`
- **net** — `htons`, `ipv4`, `tcp_socket`, `tcp_bind_listen`, `tcp_accept`, `tcp_connect`, `sock_send`, `sock_recv`, `sock_close`
- **crypto** — `random_u64`, `random_bytes`, `secure_zero`, `const_time_eq`, `const_time_str_eq`, `fnv1a_64`
- **json** — `json_quote`, `json_kv_str`, `json_kv_int`
- **testing** — `assert_true`, `assert_false`, `assert_eq_i64`, `assert_ne_i64`, `assert_eq_str` (plus `#[test]` + `lir test`)

Security builtins: `@random_u64`, `@random_bytes`, `@secure_zero`, `@const_time_eq`, `@checked_add`/`@checked_sub`/`@checked_mul`, `@popcount`/`@clz`/`@ctz`/`@bswap`, `@getenv`, `@sleep_ms`, `@read_u*`/`@write_u*` (null-trapped).

## Project Structure

```
myproject/
├── project.manifest     # Project configuration (JSON)
├── src/
│   ├── main.lir         # Entry point
│   ├── math.lir         # Math module
│   └── tests.lir        # Tests
└── build/               # Build output
```

## Standard Library

The intended standard library includes the following areas; implementation completeness must be verified against the current source and tests:

- **core** — Primitives, Option, Result, panic
- **collections** — Vec, HashMap, HashSet, Stack, Queue
- **io** — File I/O, string builder, path manipulation
- **net** — TCP sockets, HTTP client/server
- **json** — JSON parser and serializer
- **testing** — Test framework, assertions, benchmarks
- **crypto** — Hashing, encryption, random numbers
- **async** — Async/await runtime, channels, tasks

## Performance Benchmarks: LIR vs Zig 0.13.0

LIR's SSA optimizer and direct machine code backend deliver competitive performance against Zig 0.13.0 (`-O ReleaseFast`), while compiling **~9.5x–11.3x faster** with binaries **~100x–135x smaller**:

| Workload | LIR -O2 Runtime | Zig ReleaseFast | Speedup / Winner | LIR Compile Time | Zig Compile Time | Binary Size (LIR vs Zig) |
|---|---|---|---|---|---|---|
| `tak_recursive_27` | **12.29 ms** | 15.10 ms | **LIR 1.23x faster** | **470 ms** | 4,996 ms (10.6x) | **12 KB** vs 1.66 MB (135x) |
| `branch_mix_30m` | **39.71 ms** | 47.28 ms | **LIR 1.19x faster** | **464 ms** | 4,648 ms (10.0x) | **12 KB** vs 1.66 MB (135x) |
| `fib_recursive_38` | **78.34 ms** | 79.62 ms | **LIR 1.02x faster** | **484 ms** | 4,773 ms (9.9x) | **12 KB** vs 1.66 MB (135x) |
| `mandelbrot_fixed_2d` | **26.06 ms** | 26.94 ms | **LIR 1.03x faster** | **460 ms** | 4,748 ms (10.3x) | **12 KB** vs 1.66 MB (135x) |
| `collatz_sequence_1m` | **135.38 ms** | 138.60 ms | **LIR 1.02x faster** | **458 ms** | 4,857 ms (10.6x) | **12 KB** vs 1.66 MB (135x) |
| `prime_count_500k` | **40.02 ms** | 40.11 ms | **LIR 1.00x faster** | **453 ms** | 4,639 ms (10.2x) | **12 KB** vs 1.66 MB (135x) |
| `nested_matrix_loop_4m` | 30.91 ms | **29.44 ms** | Zig 1.05x | **448 ms** | 4,714 ms (10.5x) | **16 KB** vs 1.66 MB (101x) |
| `fib_mod_30m` | 100.77 ms | **98.84 ms** | Zig 1.02x | **453 ms** | 4,756 ms (10.5x) | **12 KB** vs 1.66 MB (135x) |
| `bitwise_hash_20m` | 31.88 ms | **28.75 ms** | Zig 1.11x | **446 ms** | 4,885 ms (10.9x) | **12 KB** vs 1.66 MB (135x) |

Reproduce with:
```bash
python3 bench/compare_zig.py
```

## Intelligent Developer Experience

- **Coded diagnostics:** every message carries a stable code (`LIR-E3004`), a source span, and usually a `help:` line stating the concrete fix. `lir explain LIR-E3004` (also `e3004`, `3004`) prints cause, fix and a working example.
- **Machine output:** `--diagnostics=short` for log scrapers, `--json` for structured diagnostics plus a JSON command result. See [AI.md](docs/AI.md).
- **Fuzzy "Did You Mean" Suggestions:** case-insensitive Levenshtein matching for identifiers, functions, builtins, structs and fields.
- **Static Warning Analysis:** unused variables/parameters (`_` prefix hint) and unreachable statements after control transfers.
- **Language catalogue:** `lir lang` (human), `--json` (machines), `--markdown` (regenerates `docs/LANGUAGE_REFERENCE.md`). Every `supported` example is compiled by `zig build test`.
- **Builtin catalogue:** `lir builtins` lists every intrinsic with its signature and traps.
- **Comparison against a peer language:** [LIR vs Odin](docs/ODIN_VS_LIR.md) states where LIR is behind (slices, `distinct`, allocator context, C FFI, ecosystem) as plainly as where it is ahead.
- **Reserved-word list:** `lir lang --keywords` (or `--json` → `lir.keywords.v1`) is generated from the lexer, so generators never collide with a keyword.
- **Interactive Knowledge Base:** `lir explain <topic>` covers syntax, types, borrow, safety, contracts, purity, ranges, optimizer, concurrency, strings, collections, errors, diagnostics, `ai` and `limitations`.
- **AST Inspector:** `lir ast <file>` prints the structured syntax tree hierarchy.

## Building from Source

```bash
# Clone the repository
git clone https://github.com/sswweett00/ziglir.git
cd ziglir

# Build and test the bootstrap compiler (requires Zig)
zig build
zig build test
```

## Contributing

Two rules keep this project honest:

1. **Never document a feature that the compiler does not implement.** Add it to
   `src/bootstrap/langref.zig` with a compiling `example`, then run
   `lir lang --markdown > docs/LANGUAGE_REFERENCE.md`.
2. **Never merge without the gates:**

```bash
zig build test                       # unit + catalogue conformance
python3 tests/cli_test.py  ./zig-out/bin/lir
python3 tests/ai_test.py   ./zig-out/bin/lir   # machine contracts
python3 tests/core_test.py ./zig-out/bin/lir
python3 tests/backend_test.py ./zig-out/bin/lir
```

See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for the full checklist, code map and
documentation workflow.

## License

LIR is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Links

- [AI integration contract](docs/AI.md) — machine-readable schemas and repair loop
- [Generated language reference](docs/LANGUAGE_REFERENCE.md) — canonical syntax
- [Generated cheatsheet](docs/CHEATSHEET.md) — one page, for constrained context windows
- [LIR vs Odin](docs/ODIN_VS_LIR.md) — honest feature-by-feature comparison
- [Language Specification](docs/SPEC.md)
- [Standard Library](docs/STDLIB.md)
- [Canonical tour](examples/canonical-tour.lir) — every supported feature in one file
- [Examples](examples/)
- [Benchmarks](bench/)
- [Roadmap](docs/ROADMAP.md)

---

<p align="center">
  <b>LIR — Clear syntax. Native performance. Evidence over promises.</b>
</p>
