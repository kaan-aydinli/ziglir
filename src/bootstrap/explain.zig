// ════════════════════════════════════════════════════════════════════════════
// EXPLAIN — In-terminal knowledge base (`lir explain <topic|code>`)
//
// Every topic below is written against the behaviour of the *current* bootstrap
// compiler; anything not implemented is marked as such instead of being
// described as if it were supported. The canonical, exhaustive list lives in
// `langref.zig` (see `lir lang`); these topics are the "why", not the "what".
//
// Machine use:  lir explain --list --json     → topic index
//               lir explain ai                → agent integration guide
//               lir explain LIR-E3001         → per-diagnostic help
// ════════════════════════════════════════════════════════════════════════════

const std = @import("std");
const util = @import("util.zig");

const printStr = util.printStr;
const printErr = util.printErr;
const eql = util.eql;

pub const Topic = struct {
    name: []const u8,
    summary: []const u8,
    body: []const u8,
    aliases: []const []const u8 = &.{},
};

pub const topics = [_]Topic{
    .{
        .name = "syntax",
        .summary = "Statement layout, comments, and the canonical spellings.",
        .aliases = &.{ "grammar", "statements" },
        .body =
        \\=== LIR Syntax Essentials ===
        \\
        \\Statements are NEWLINE separated. ';' is accepted and ignored, but it is
        \\never required; do not use it as a terminator between 'if' and 'else'.
        \\
        \\  fn add(a: i64, b: i64) -> i64 {
        \\      let sum = a + b
        \\      return sum
        \\  }
        \\
        \\Braces are always required for control-flow bodies:
        \\
        \\  if cond { ... } elif cond2 { ... } else { ... }
        \\  while cond { ... }        loop { ... break }
        \\  until cond { ... }        for i in 0..n { ... }
        \\  for v in array { ... }    unless cond { ... } else { ... }
        \\  guard cond else { return ... }
        \\
        \\Comments: '#' to end of line, '//' to end of line, '///' doc comment,
        \\'/* ... */' nested block comment.
        \\
        \\Canonical spellings (aliases exist but are legacy):
        \\  fn      (not proc, not function/def)
        \\  let mut (not var)
        \\  let x = if c { 1 } else { 2 }   (not let x: i64; ...)
        \\  and/or  (&& and || are accepted synonyms; 'not' does NOT exist)
        \\
        \\There are no semicolon-terminated 'for(;;)' loops, no labels, and no
        \\do/while. See 'lir lang' for the exhaustive table.
        \\
        ,
    },
    .{
        .name = "types",
        .summary = "What the type checker accepts, converts, and rejects.",
        .aliases = &.{ "type-system", "casts" },
        .body =
        \\=== LIR Type System (implemented surface) ===
        \\
        \\Integers:  i8 i16 i32 i64 u8 u16 u32 u64 isize usize
        \\Floats:    f32 f64            Other: bool, string, void, never
        \\Compound:  (T, U) tuples (max 8 fields), [T; N] and [v; N] arrays,
        \\           []T slices, *T / *mut T pointers, fn(T) -> T values,
        \\           Option<T>, Result<T, E>, enum/struct/union/dyn Trait, map, chan
        \\
        \\NOT available: i128/u128, char, f16/f128, implicit numeric conversion.
        \\
        \\All integers occupy an 8-byte slot; the *annotation* is what drives
        \\range/signedness checks, casts and printing. Casting is always explicit:
        \\
        \\  let wide: i64 = 300
        \\  let byte = wide as u8            // 44: low 8 bits are kept
        \\  let back = byte as i64           // 44
        \\  let f = 2.75
        \\  let n = f as i64                 // 2: truncation toward zero
        \\
        \\Float to integer traps on NaN and out-of-range values; integer to float
        \\preserves signedness. A bare integer literal is NOT a float:
        \\  let f: f64 = 1        // rejected
        \\  let f: f64 = 1.0      // accepted
        \\
        \\Arithmetic wraps modulo 2^64 (no overflow trap); division by zero,
        \\modulo by zero and out-of-range shift counts trap. Use @checked_add,
        \\@checked_sub and @checked_mul when overflow must be an error.
        \\
        ,
    },
    .{
        .name = "borrow",
        .summary = "Ownership/borrow rules the compiler actually enforces.",
        .aliases = &.{ "ownership", "lifetimes", "references" },
        .body =
        \\=== Borrow Checking in the Bootstrap Compiler ===
        \\
        \\The bootstrap tracks borrows per local variable. What is enforced today:
        \\
        \\1. While a variable is mutably borrowed, reading or writing the owner is
        \\   a compile error:
        \\       let mut x = 1
        \\       let p = &mut x
        \\       x = 5          // error[LIR-E3009]: cannot assign while borrowed
        \\
        \\2. Returning a pointer to a local stack variable is rejected:
        \\       fn bad() -> *i64 {
        \\           let v = 42
        \\           return &v  // error[LIR-E3004]: dangling reference
        \\       }
        \\
        \\3. Pointers to locals cannot be handed to another thread.
        \\
        \\What is NOT implemented: full Rust-style lifetime inference, move
        \\semantics, and proving aliasing across function boundaries. "Memory safe"
        \\in this project means: bounds checks, traps on invalid memory, and the
        \\specific compile-time analyses listed here and in 'lir explain safety'.
        \\
        ,
    },
    .{
        .name = "safety",
        .summary = "Every check that is on by default, and what still traps.",
        .aliases = &.{ "security", "traps", "defaults" },
        .body =
        \\=== Default Safety Checks ===
        \\
        \\Compile time:
        \\  * use-after-free / double-free / use-after-close on straight-line code
        \\  * unfreed heap allocation or descriptor leaked inside a loop
        \\  * constant index out of bounds for fixed arrays
        \\  * shift counts that are constant and out of range (0..63)
        \\  * division/modulo by a constant zero
        \\  * dangling reference returns, pointer-to-local thread arguments
        \\  * non-exhaustive match, type mismatches, unknown names
        \\  * 32 KiB per-function stack frame budget, non-terminating spin loops
        \\
        \\Runtime:
        \\  * array and string index bounds (traps with SIGILL, exit 132)
        \\  * division/modulo by zero, dynamic shift overflow
        \\  * NaN / out-of-range float to integer conversion
        \\  * heap canaries, zero-on-free, W^X segments, stack guard pages
        \\  * map hashing keyed per process (HashDoS resistance)
        \\
        \\Not provided: a garbage collector, a full borrow checker, or a claim that
        \\arbitrary unsafe pointer arithmetic is memory safe. 'unsafe { }' is not a
        \\language construct; raw memory is reached through @read_u64/@write_u64
        \\and friends, which still validate ranges.
        \\
        ,
    },
    .{
        .name = "contracts",
        .summary = "Compile-time pre/postconditions implemented as attributes.",
        .aliases = &.{ "verification", "spark", "requires" },
        .body =
        \\=== Function Contracts (implemented form) ===
        \\
        \\Contracts are ATTRIBUTES, not keywords. The spellings 'requires' and
        \\'ensures' do not parse; use:
        \\
        \\  #[pre(b != 0)]
        \\  #[post(result >= 0)]
        \\  fn divide(a: i64, b: i64) -> i64 {
        \\      return a / b
        \\  }
        \\
        \\A call whose arguments are compile-time constants is verified statically:
        \\  divide(9, 3)   // ok
        \\  divide(1, 0)   // error[LIR-E3004]: precondition violation
        \\
        \\Dynamic calls keep the check as a runtime assertion. Contracts are not a
        \\proof system: there is no SMT solver, no loop invariant, and no
        \\verification of the postcondition against arbitrary inputs.
        \\
        ,
    },
    .{
        .name = "purity",
        .summary = "Side-effect-free functions via #[pure].",
        .aliases = &.{ "pure" },
        .body =
        \\=== Pure Functions ===
        \\
        \\Declared with an attribute, not a keyword ('pure fn' does not parse):
        \\
        \\  #[pure]
        \\  fn square(x: i64) -> i64 {
        \\      return x * x
        \\  }
        \\
        \\Enforced: a pure function may not call printing, allocation, file, network
        \\or thread builtins, and may only call other pure code:
        \\  #[pure]
        \\  fn noisy(x: i64) -> i64 {
        \\      println("side effect")   // error[LIR-E3004]: purity violation
        \\      return x
        \\  }
        \\
        \\Benefit: the optimizer may common-subexpression-eliminate duplicate pure
        \\calls. Purity is a promise checked inside the function body; it is not a
        \\whole-program effect system.
        \\
        ,
    },
    .{
        .name = "ranges",
        .summary = "Bounded scalar types (compile-time checked integer domains).",
        .aliases = &.{ "bounded", "subtypes" },
        .body =
        \\=== Bounded Integer Types ===
        \\
        \\Syntax (note '=' and the missing trailing semicolon):
        \\
        \\  type Percent = i64 range 0..100
        \\
        \\  fn main() -> i64 {
        \\      let p: Percent = 42       // ok
        \\      return p
        \\  }
        \\
        \\  let bad: Percent = 105        // error[LIR-E3004]: outside [0..100]
        \\
        \\Only constant initialisers are checked. Indexing with a bounded type does
        \\not yet remove bounds checks; that optimization is not implemented.
        \\
        ,
    },
    .{
        .name = "optimizer",
        .summary = "The SSA/IR pipeline, in the order it runs.",
        .aliases = &.{ "ir", "o2", "passes" },
        .body =
        \\=== Optimization Pipeline (-O2 is the default) ===
        \\
        \\AST stage: constant folding, algebraic simplification, dead-code removal.
        \\IR stage on SSA form, verified before and after every pass:
        \\  1. mem2reg style promotion of stack slots to virtual registers
        \\  2. global value numbering + copy propagation/coalescing
        \\  3. trap-safe loop invariant code motion
        \\  4. counted-loop unrolling (up to 8x)
        \\  5. magic-number division lowering, hoisted multipliers
        \\  6. constant reassociation, double-negation and identity elimination
        \\  7. dead code elimination
        \\
        \\-O0 skips the optimizer, -O1 keeps the cheap passes. Optimization never
        \\changes defined semantics: traps (bounds, divide by zero, shifts) survive.
        \\Inspect with: lir ir file.lir -O0  and compare to -O2.
        \\
        \\(C) The IR verifier runs between stages and rejects malformed IR; a
        \\verification failure is a compiler bug, reported as LIR-E6001.
        \\
        ,
    },
    .{
        .name = "concurrency",
        .summary = "Threads, channels, mutexes and atomics that exist today.",
        .aliases = &.{ "threads", "channels", "atomics" },
        .body =
        \\=== Concurrency Primitives ===
        \\
        \\  let h = spawn worker()          // or: spawn { work() }
        \\  let h = @thread_create(worker, arg)
        \\  let result = @thread_join(h)
        \\
        \\  let c = @chan_new(1)            // bounded MPMC channel
        \\  @chan_send(c, 7)
        \\  let v = @chan_recv(c)           // blocks while empty
        \\  @chan_close(c)
        \\
        \\  let m = @mutex_create()
        \\  @mutex_lock(m) ... @mutex_unlock(m)
        \\  @atomic_add(ptr, 1)  @atomic_cas(ptr, old, new)
        \\
        \\These are real OS threads/atomics, sequentially consistent, on host targets.
        \\Threads and channels are NOT available for wasm32-wasi: the compiler
        \\rejects them with LIR-E7004 instead of emitting a program that traps.
        \\Atoms, mutexes, maps and @time_ns work on every target.
        \\
        \\There is no async/await runtime, no work-stealing scheduler, and no
        \\compile-time data race detector. Passing a pointer to a local into a
        \\thread is a compile error; other sharing is the programmer's responsibility.
        \\
        ,
    },
    .{
        .name = "strings",
        .summary = "String literals, interpolation, comparison, and the helpers.",
        .aliases = &.{ "text", "interpolation" },
        .body =
        \\=== Strings ===
        \\
        \\  let s = "lir"                 // immutable UTF-8
        \\  let t = "a\tb\n\"c\""         // escapes: \n \t \r \\ \" \0
        \\  let joined = s + "lang"       // heap-allocated concatenation
        \\  if joined == "lirlang" { }    // content equality
        \\  println(joined)               // print/println take strings only
        \\  let n = joined.len            // byte length
        \\  let ch = joined[0]            // byte value, bounds-checked
        \\
        \\Interpolation: any expression inside { } is inserted.
        \\  println("{a}+{b}={a + b}")
        \\Format specifiers such as {x:#x} are NOT implemented; they print
        \\literally. Use std::fmt or std::crypto base64/hex helpers instead.
        \\
        \\Numbers need their own printers: printInt(x), printFloat(x).
        \\  println(42)     // error[LIR-E3004]: println expects a string
        \\
        \\Handy builtins: @string_len, @string_concat, @string_eq, @string_sub,
        \\@string_slice, @string_char_at, @string_split, @string_to_int,
        \\@int_to_string, @string_to_float, @float_to_string.
        \\
        ,
    },
    .{
        .name = "collections",
        .summary = "Dynamic arrays, maps, tuples, and list comprehensions.",
        .aliases = &.{ "arrays", "maps", "data-structures" },
        .body =
        \\=== Collections ===
        \\
        \\Fixed array (stack):      let a = [10, 20, 30]      a[5] traps
        \\Repeat array:             let zeros = [0; 8]
        \\Dynamic array (heap):
        \\  let items = @array_new(8, 8)          // capacity, element size
        \\  @array_push(items, 4)
        \\  let n = @array_len(items)
        \\  let v = @array_get(items, 0)          // bounds-checked
        \\  @array_set(items, 0, 9)
        \\  @array_free(items)
        \\List comprehension:
        \\  let squares = [i * i for i in 0..4]
        \\  let evens = [i for i in 0..10 if i % 2 == 0]
        \\Map (hash map; i64 or string keys):
        \\  let m = @map_new()
        \\  @map_set(m, "k", 1)
        \\  if @map_has(m, "k") { let v = @map_get(m, "k") }
        \\  @map_free(m)
        \\Tuples: (1, true), t.0, let (a, b) = pair   — max 8 fields.
        \\
        \\The embedded 'collections' module adds RingBuffer, BitSet, Deque,
        \\MinHeap/PriorityQueue and Stack; import it to use them.
        \\
        ,
    },
    .{
        .name = "errors",
        .summary = "Option/Result, ? propagation, ?? defaults, and exit codes.",
        .aliases = &.{ "result", "option", "error-handling" },
        .body =
        \\=== Error Handling ===
        \\
        \\Option<T>:   Some(v) / None      Result<T, E>: Ok(v) / Err(e)
        \\
        \\  fn find(ok: bool) -> Option<i64> {
        \\      if ok { return Some(5) }
        \\      return None
        \\  }
        \\  let v = find(true) ?? 0        // default when None
        \\
        \\Propagation with '?', which requires the caller to return the same shape:
        \\  fn twice(ok: bool) -> Option<i64> {
        \\      let v = find(ok)?
        \\      return Some(v * 2)
        \\  }
        \\
        \\Some/None/Ok/Err are context typed: 'let x = None' without an annotation
        \\or return context is rejected, so write 'let x: ?i64 = None'.
        \\
        \\Read payloads with match:
        \\  match twice(true) { Some(v) => v, None => 0 }
        \\
        \\Process status: main's return value is the exit code (i64, low 8 bits).
        \\exit(n) and panic(msg) terminate immediately; a trap exits with 132.
        \\
        ,
    },
    .{
        .name = "diagnostics",
        .summary = "Error codes, fix-its, and machine-readable output.",
        .aliases = &.{ "errors", "json", "codes" },
        .body =
        \\=== Diagnostics ===
        \\
        \\Every diagnostic has a stable code, a span, a message, and often a
        \\'help' line plus an expected value for automated repair:
        \\
        \\  file.lir:2:5: error[LIR-E3004]: annotation on 'x' is 'i64' but the
        \\  initializer has type 'string'
        \\    2 |     let x: i64 = "text"
        \\      |     ^
        \\      = help: make the initializer a 'i64', or annotate the variable as
        \\              'string', or add 'as i64'
        \\
        \\Code families:
        \\  LIR-E1xxx  lexer         LIR-E5xxx  capacity limits
        \\  LIR-E2xxx  parser        LIR-E6xxx  IR verification/backend
        \\  LIR-E3xxx  type checker  LIR-E7xxx  driver, targets, missing input
        \\
        \\Output formats (any command):
        \\  --diagnostics=human   snippet + caret + help (default)
        \\  --diagnostics=short   one machine-friendly line per diagnostic
        \\  --json                JSON diagnostics on stderr + JSON result on stdout
        \\
        \\Look up a code with: lir explain LIR-E3004
        \\Fuzzy suggestions: unknown names within edit distance 2-3 are matched
        \\case-insensitively ('printint' → 'printInt').
        \\
        ,
    },
    .{
        .name = "ai",
        .summary = "How an AI system should drive this compiler.",
        .aliases = &.{ "agent", "llm", "automation" },
        .body =
        \\=== LIR for AI Systems ===
        \\
        \\Use these deterministic interfaces instead of guessing:
        \\
        \\  1. Ground the language in the catalogue, not in other languages:
        \\       lir lang --json          -> features with status + compilable example
        \\       lir lang --keywords      -> reserved words (never use as names)
        \\       lir builtins --json      -> every builtin signature
        \\     Only emit code for entries whose status is "supported"; entries marked
        \\     "unsupported" list an 'avoid' field naming what not to write.
        \\
        \\  2. Validate, never assume:
        \\       lir check file.lir --json   -> {"schema":"lir.check.v1","status":...}
        \\     Diagnostics arrive on stderr as {"schema":"lir.diagnostics.v1",...};
        \\     each has code, line, column, message, help and expect{kind,value}.
        \\     Repair the source using 'expect' (a literal token/name/type), then
        \\     re-run check. Never re-parse the prose message.
        \\
        \\  3. Execute quickly with the portable VM:
        \\       lir run file.lir --backend=vm -- args...
        \\     Same semantics as native, no toolchain, identical traps.
        \\
        \\  4. Bootstrap a program deterministically:
        \\       lir init name        (creates project.manifest + src/)
        \\       lir lang fn          (canonical shape of a function)
        \\
        \\  5. Exit codes: 0 ok, 1 compiler error, 132 trap in compiled code.
        \\
        \\Rules of thumb for generation: newline-separated statements, explicit
        \\'return', no ';' between blocks, explicit casts, printInt/printFloat for
        \\numbers, 'let mut' for mutation, and an exhaustive '_' arm in every
        \\integer match.
        \\
        ,
    },
    .{
        .name = "limitations",
        .summary = "What is deliberately absent; do not generate it.",
        .aliases = &.{ "unsupported", "gaps", "roadmap" },
        .body =
        \\=== Known Gaps (rejected by this compiler) ===
        \\
        \\  async fn / await            no async runtime (use threads + channels)
        \\  unsafe { } / asm(...)       rejected statements
        \\  extern fn / mod foo         no FFI or module declarations
        \\  i128 / u128 / char          no such types
        \\  nested fn inside a body     closures use |x| ... instead
        \\  labelled loops, 'break v'   not implemented
        \\  for i, v in arr             no index/value form
        \\  a[..] slice ranges          no slicing syntax
        \\  {expr:#x} format specs      interpolation has no specifiers
        \\  struct A { b: B }           struct-typed field (use *B)
        \\  Option<Option<T>>           '>>' lexes as shift; alias it first
        \\  implicit numeric widening   always write 'as T'
        \\  immutable shadowing in one scope (use a nested block)
        \\  'not x'                     use '!x'
        \\  'pure fn' / 'requires'      use #[pure] / #[pre(...)]
        \\
        \\Whole subsystems still missing: package registry, LSP, formatter,
        \\data-race detection, escape analysis, SIMD/vectorization, macro system.
        \\See docs/ROADMAP.md for status; only items with tests count as done.
        \\
        ,
    },
    .{
        .name = "all",
        .summary = "Everything above, in one pass.",
        .body =
        \\=== LIR in One Page ===
        \\
        \\LIR (Ziglir) is a small systems language with a Zig bootstrap compiler.
        \\Native Linux x86-64 ELF and wasm32-wasi come from zero-dependency
        \\emitters; other targets go through a portable C11 backend; a portable
        \\IR VM runs any program on any host.
        \\
        \\Everything is a newline-terminated statement; braces are mandatory;
        \\'fn' declares functions; 'let'/'let mut' bind values; 'match' is an
        \\expression; Option/Result plus '?' cover errors; '#[test]', '#[pure]',
        \\'#[pre]'/'#[post]' are the attributes.
        \\
        \\Safety defaults: bounds checks, traps on divide-by-zero/shift/NaN
        \\conversion, UAF/double-free analysis, W^X + canaries, HashDoS-keyed maps.
        \\Missing: garbage collector (by design), full borrow checker (partly),
        \\async runtime, FFI, macros, package manager.
        \\
        \\For exact syntax use: lir lang            (or --json / --markdown)
        \\For builtins:         lir builtins
        \\Per-topic detail:     lir explain <topic>
        \\
        ,
    },
};

pub fn find(name: []const u8) ?*const Topic {
    for (&topics) |*t| {
        if (eql(t.name, name)) return t;
    }
    for (&topics) |*t| {
        for (t.aliases) |alias| {
            if (eql(alias, name)) return t;
        }
    }
    return null;
}

fn jsonStr(text: []const u8) void {
    printStr("\"");
    for (text) |ch| {
        switch (ch) {
            '"' => printStr("\\\""),
            '\\' => printStr("\\\\"),
            '\n' => printStr("\\n"),
            '\r' => printStr("\\r"),
            '\t' => printStr("\\t"),
            else => {
                if (ch < 0x20) {
                    var buf: [8]u8 = undefined;
                    const esc = std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{ch}) catch "";
                    printStr(esc);
                } else {
                    const one = [_]u8{ch};
                    printStr(one[0..]);
                }
            },
        }
    }
    printStr("\"");
}

/// Per-code guidance. Codes mirror `diag.Code`; only the ones a user can act on
/// are listed here.
const CodeHelp = struct {
    code: []const u8,
    title: []const u8,
    cause: []const u8,
    fix: []const u8,
    example: []const u8 = "",
};

const code_help = [_]CodeHelp{
    .{
        .code = "LIR-E1001",
        .title = "Invalid character or unterminated literal",
        .cause = "The lexer met a byte it cannot classify, an unterminated string/char literal, or a malformed escape.",
        .fix = "Close the literal on the same line, and use only \\n \\t \\r \\\\ \\\" \\0 escapes. '#' starts a comment, so it cannot appear unquoted in code.",
    },
    .{
        .code = "LIR-E1004",
        .title = "Malformed or out-of-range integer literal",
        .cause = "An integer literal does not fit in i64, or a 0x/0b/0o literal has no digits for its base.",
        .fix = "Keep literals within -9223372036854775808..9223372036854775807, or build large unsigned values with '@checked_*' and casts.",
    },
    .{
        .code = "LIR-E2001",
        .title = "Syntax error",
        .cause = "The parser expected a different token. The message names both sides ('expected X, got Y'); JSON output adds expect.kind = token.",
        .fix = "Check braces, commas in struct literals and match arms, and remember that statements end at a newline (no ';' needed).",
        .example =
        \\fn main() -> i64 {
        \\    let p = Point { x: 1, y: 2 }
        \\    return p.x
        \\}
        ,
    },
    .{
        .code = "LIR-E2002",
        .title = "Unsupported statement",
        .cause = "A reserved keyword that has no implementation was used as a statement: unsafe, asm, volatile, try.",
        .fix = "Remove the block. Raw memory work uses @read_u64/@write_u64/@ptr_add; errors use '?' and match.",
    },
    .{
        .code = "LIR-E2003",
        .title = "Unsupported top-level declaration",
        .cause = "Only fn, struct, union, enum, trait, impl, const, type and import may appear at top level (mod/extern are not implemented).",
        .fix = "Replace 'mod x' with a separate file plus 'import x'; drop 'extern' and call a builtin instead.",
    },
    .{
        .code = "LIR-E2005",
        .title = "Unsupported or unknown type",
        .cause = "A type name the compiler does not know, such as i128, char, or a struct used before declaration/annotation of a struct-typed field.",
        .fix = "Use i64/u64/bool/string/pointers, or declare the struct first. struct-typed fields are not supported: store *B.",
    },
    .{
        .code = "LIR-E3001",
        .title = "Undefined variable",
        .cause = "An identifier is used that is not a local, parameter, global const, function, or imported name.",
        .fix = "Declare it before use ('let x = ...'), import the module that defines it, or fix the spelling: JSON output puts the closest match in expect.value.",
    },
    .{
        .code = "LIR-E3002",
        .title = "Undefined function or method",
        .cause = "A call names a function that does not exist, or a method the receiver's struct/trait does not declare.",
        .fix = "Declare the function with 'fn', import the module, or use the suggested name from expect.value. Look up builtins with 'lir builtins'.",
    },
    .{
        .code = "LIR-E3003",
        .title = "Duplicate declaration",
        .cause = "Two declarations share a name in the same namespace, or a local is redeclared in the same scope.",
        .fix = "Rename one of them. To shadow intentionally, open a nested block: { let x = 2 ... }.",
    },
    .{
        .code = "LIR-E3004",
        .title = "Type mismatch",
        .cause = "The most common error family: annotation vs initializer, argument vs parameter, arm vs result, numeric vs string, bool vs i64, borrow/UAF/purity/range/contract violations.",
        .fix = "Read the 'expected X, found Y' part, then either annotate with Y, pass a value of type X, or convert explicitly with 'as'.",
        .example =
        \\fn main() -> i64 {
        \\    let n: i64 = 41
        \\    let text = @int_to_string(n)
        \\    println(text)
        \\    return n + 1
        \\}
        ,
    },
    .{
        .code = "LIR-E3005",
        .title = "Wrong number of arguments",
        .cause = "A call passes fewer arguments than required, more than 8, or mixes named arguments on a non-direct call.",
        .fix = "Match the signature; defaults fill trailing parameters. Named arguments work on direct free-function calls only.",
    },
    .{
        .code = "LIR-E3008",
        .title = "Loop control outside a loop",
        .cause = "break/continue used outside a loop, or inside a 'defer' block.",
        .fix = "Move the statement into the loop body; put cleanup in defer without control flow.",
    },
    .{
        .code = "LIR-E3009",
        .title = "Invalid assignment",
        .cause = "Assigning to an immutable binding, to a non-lvalue, or to a variable that is currently borrowed.",
        .fix = "Declare with 'let mut', end the borrow's lifetime first, or assign through the pointer (*p = v).",
    },
    .{
        .code = "LIR-E4001",
        .title = "Unresolved import",
        .cause = "The imported path does not exist relative to the importing file, and it is not an embedded std module.",
        .fix = "Check the path ('import ../lib/util.lir') or use one of: core io os sys net crypto json math str algo testing collections hash fmt time http.",
    },
    .{
        .code = "LIR-E5001",
        .title = "Capacity limit reached",
        .cause = "The program exceeds the bootstrap limits (65536 AST nodes, 512 functions, 256 structs, 128 enums, 64 sources).",
        .fix = "Split the program into modules, or reduce generated code volume. These are fixed compile-time budgets.",
    },
    .{
        .code = "LIR-E6001",
        .title = "Invalid intermediate representation",
        .cause = "The IR verifier rejected the program before code generation: an internal compiler bug, never a user error.",
        .fix = "Report it with the source and 'lir ir file.lir' output. The compiler refuses to emit a binary rather than miscompile.",
    },
    .{
        .code = "LIR-E7001",
        .title = "Unsupported target triple",
        .cause = "The requested --target is not implemented for this build.",
        .fix = "Run 'lir targets' for the list; x86_64-linux, wasm32-wasi and the C11 cross-targets are supported.",
    },
    .{
        .code = "LIR-E4004",
        .title = "Unknown standard library module",
        .cause = "An 'import' named a module the embedded standard library does not provide, and there is no '<name>.lir' next to the importing file.",
        .fix = "Import one of: core, io, os, sys, net, crypto, json, math, testing, str, algo, collections, hash, fmt, time, http — or create the local file you are importing.",
    },
    .{
        .code = "LIR-E7004",
        .title = "Builtin unavailable for the selected target",
        .cause = "The program uses a builtin the target cannot provide, for example threads or blocking channels on wasm32-wasi.",
        .fix = "Build for a host thread target (default x86_64-linux or the C11 backend), or run the program with --backend=vm during development.",
    },
    .{
        .code = "LIR-E8001",
        .title = "CMF field syntax",
        .cause = "A line in a .cmf file is not one of the field directives (morph, field, claim, bloom), or a directive is incomplete.",
        .fix = "Headers are one directive per line: 'morph Name =<< w1 w2 >>=', 'field f: u64[64] ?exclusive', 'claim c over f check uniqueness', 'bloom b: morph Name { ... }'. Run 'lir cmf --help'.",
    },
    .{
        .code = "LIR-E8005",
        .title = "Claim nothing can falsify",
        .cause = "A claim names a check LIR does not implement, names no field, or carries a duration without an adjudicator.",
        .fix = "Use check uniqueness|concurrency|totality|absence, or runtime <adjudicator> plus 'for <n>tick', or drop the claim.",
    },
    .{
        .code = "LIR-E8008",
        .title = "Bloom variant does not verify",
        .cause = "One witness instance of a morph was substituted into the bloom body and the result failed lexing, parsing, type checking, or IR verification. The variant is refused.",
        .fix = "Fix the body or narrow the morph. A refused variant is never emitted, so it can never be selected at runtime.",
    },
    .{
        .code = "LIR-E8009",
        .title = "Lens would break a field's promise",
        .cause = "A lens permutes a field declared ?ordered (permutation destroys the ordering the field promises), or transposes a field already declared ?transpose, or views an undeclared field.",
        .fix = "Filter instead of permuting an ?ordered field, declare the base layout once, and declare the field before the lens that views it.",
    },
    .{
        .code = "LIR-E8010",
        .title = "Claim depends on an unavailable machine",
        .cause = "A machine class other than local was marked 'implemented', or a claim names an adjudicator that is neither a declared machine nor adjudicate/verify/check, or depends on a machine declared 'planned'.",
        .fix = "Mark offload classes 'planned' and adjudicate on 'local' today. A planned machine is analysable in the field and can never discharge a claim.",
    },
    .{
        .code = "LIR-E8011",
        .title = "Telemetry that measures nothing",
        .cause = "A telemetry period is not a positive '<n>tick', or a source is sampled but no 'tune' rule consumes it.",
        .fix = "Use 'telemetry cache: every 100tick' and add a 'tune <bloom>: morph <M> under <condition>' rule that uses it.",
    },
    .{
        .code = "LIR-E8012",
        .title = "Tuning rule without a real target",
        .cause = "A tune rule names a bloom that does not exist, disagrees with the bloom's morph, or selects on a measured condition while no telemetry source is declared.",
        .fix = "Point the rule at a declared bloom whose morph matches, and declare the telemetry source that feeds the condition. Tuning only ever picks an already verified variant.",
    },
    .{
        .code = "LIR-E7002",
        .title = "Missing entry point",
        .cause = "The program has no 'fn main' (required unless compiling tests with --test/lir test).",
        .fix = "Add fn main() -> i64 { ... return 0 }.",
    },
};

fn findCodeHelp(code: []const u8) ?*const CodeHelp {
    for (&code_help) |*c| {
        if (eql(c.code, code)) return c;
    }
    return null;
}

/// Normalises short spellings ("e3004", "3004", "LIR-3004") into the canonical
/// `LIR-E3004` form. The result always points into `buf`.
fn normalizeCode(raw: []const u8, buf: []u8) ?[]const u8 {
    if (raw.len == 0 or buf.len < 12) return null;
    const prefix = "LIR-";
    var len: usize = 0;
    @memcpy(buf[0..prefix.len], prefix);
    len = prefix.len;

    var rest = raw;
    if (rest.len >= 4 and std.ascii.toUpper(rest[0]) == 'L' and std.ascii.toUpper(rest[1]) == 'I' and
        std.ascii.toUpper(rest[2]) == 'R' and rest[3] == '-')
    {
        rest = rest[4..];
    }
    if (rest.len == 0) return null;

    if (!std.ascii.isAlphabetic(rest[0])) {
        // Bare digits default to the error family.
        if (len + 1 > buf.len) return null;
        buf[len] = 'E';
        len += 1;
    }
    for (rest) |ch| {
        if (len >= buf.len) return null;
        if (!std.ascii.isAlphanumeric(ch)) return null;
        buf[len] = std.ascii.toUpper(ch);
        len += 1;
    }
    if (len <= prefix.len) return null;
    return buf[0..len];
}

pub fn printTopicList() void {
    printStr(
        \\LIR knowledge base — lir explain <topic>
        \\
        \\Topics:
        \\
    );
    for (topics) |t| {
        printStr("  ");
        printStr(t.name);
        const pad = if (t.name.len < 14) 14 - t.name.len else 1;
        var i: usize = 0;
        while (i < pad) : (i += 1) printStr(" ");
        printStr(t.summary);
        printStr("\n");
    }
    printStr(
        \\
        \\Error codes:  lir explain LIR-E3004   (or simply e3004)
        \\Machine use:  lir explain --list --json
        \\Exact syntax: lir lang        Builtins: lir builtins
        \\
    );
}

pub fn run(args: []const []const u8) void {
    var want_json = false;
    var list_only = false;
    var selector: ?[]const u8 = null;
    for (args) |arg| {
        if (eql(arg, "--json")) {
            want_json = true;
        } else if (eql(arg, "--list") or eql(arg, "-l")) {
            list_only = true;
        } else if (eql(arg, "--help") or eql(arg, "-h")) {
            printTopicList();
            return;
        } else if (arg.len > 0 and arg[0] == '-') {
            printErr("Error: unknown option '");
            printErr(arg);
            printErr("'\n");
            util.sysExit(1);
        } else if (selector == null) {
            selector = arg;
        } else {
            printErr("Error: unexpected extra argument '");
            printErr(arg);
            printErr("'\n");
            util.sysExit(1);
        }
    }

    if (want_json) {
        if (selector) |sel| {
            printStr("{\"schema\":\"lir.explain.v1\",\"topic\":");
            if (find(sel)) |t| {
                jsonStr(t.name);
                printStr(",\"summary\":");
                jsonStr(t.summary);
                printStr(",\"body\":");
                jsonStr(t.body);
                printStr("}\n");
                return;
            }
            var code_buf: [16]u8 = undefined;
            if (normalizeCode(sel, &code_buf)) |code| {
                if (findCodeHelp(code)) |c| {
                    printStr("{\"schema\":\"lir.explain.v1\",\"code\":");
                    jsonStr(c.code);
                    printStr(",\"title\":");
                    jsonStr(c.title);
                    printStr(",\"cause\":");
                    jsonStr(c.cause);
                    printStr(",\"fix\":");
                    jsonStr(c.fix);
                    printStr("}\n");
                    return;
                }
            }
            printErr("{\"schema\":\"lir.explain.v1\",\"status\":\"unknown\",\"query\":");
            jsonStr(sel);
            printErr("}\n");
            util.sysExit(1);
        }
        printStr("{\"schema\":\"lir.explain.v1\",\"topics\":[");
        for (topics, 0..) |t, i| {
            if (i > 0) printStr(",");
            printStr("{\"name\":");
            jsonStr(t.name);
            printStr(",\"summary\":");
            jsonStr(t.summary);
            printStr("}");
        }
        printStr("],\"codes\":[");
        for (code_help, 0..) |c, i| {
            if (i > 0) printStr(",");
            printStr("{\"code\":");
            jsonStr(c.code);
            printStr(",\"title\":");
            jsonStr(c.title);
            printStr("}");
        }
        printStr("]}\n");
        return;
    }

    if (list_only) {
        printTopicList();
        return;
    }

    if (selector) |sel| {
        if (find(sel)) |t| {
            printStr(t.body);
            return;
        }
        var code_buf: [16]u8 = undefined;
        if (normalizeCode(sel, &code_buf)) |code| {
            if (findCodeHelp(code)) |c| {
                printStr("=== ");
                printStr(c.code);
                printStr(": ");
                printStr(c.title);
                printStr(" ===\n\nCause:\n  ");
                printStr(c.cause);
                printStr("\n\nFix:\n  ");
                printStr(c.fix);
                printStr("\n");
                if (c.example.len > 0) {
                    printStr("\nWorking example:\n");
                    printStr(c.example);
                    printStr("\n");
                }
                return;
            }
        }
        printErr("Unknown topic '");
        printErr(sel);
        printErr("'.");
        var cands: [topics.len + code_help.len][]const u8 = undefined;
        var n: usize = 0;
        for (topics) |t| {
            cands[n] = t.name;
            n += 1;
        }
        for (code_help) |c| {
            cands[n] = c.code;
            n += 1;
        }
        if (util.findSimilarName(sel, cands[0..n], 3)) |sugg| {
            printErr(" Did you mean 'lir explain ");
            printErr(sugg);
            printErr("'?");
        }
        printErr("\nRun 'lir explain' without arguments to see available topics.\n");
        util.sysExit(1);
    }

    printTopicList();
}

// ════════════════════════════════════════════════════════════════════════════

test "explain topics are unique and resolvable by alias" {
    var i: usize = 0;
    while (i < topics.len) : (i += 1) {
        var j = i + 1;
        while (j < topics.len) : (j += 1) {
            try std.testing.expect(!eql(topics[i].name, topics[j].name));
        }
        try std.testing.expect(find(topics[i].name) != null);
        for (topics[i].aliases) |alias| {
            try std.testing.expect(find(alias) != null);
        }
    }
}

test "explain documents every actionable diagnostic code" {
    try std.testing.expect(findCodeHelp("LIR-E3004") != null);
    try std.testing.expect(findCodeHelp("LIR-E3001") != null);
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("LIR-E3004", normalizeCode("e3004", &buf).?);
    try std.testing.expectEqualStrings("LIR-E3004", normalizeCode("LIR-3004", &buf).?);
}
