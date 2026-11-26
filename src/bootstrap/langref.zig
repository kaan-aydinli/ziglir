// ════════════════════════════════════════════════════════════════════════════
// LANGREF — The single source of truth for "what does LIR actually accept?"
//
// This module is consumed by:
//   * `lir lang`      → human / JSON / Markdown language reference
//   * `lir builtins`  → machine-readable builtin catalogue
//   * `lir explain`   → topic navigation
//   * src/bootstrap/tests.zig → every feature marked `.supported` has its
//     `example` compiled by the test suite, so this table cannot drift from the
//     implementation without a failing test.
//
// Rules for editing:
//   * `status` describes the *current bootstrap compiler*, never the roadmap.
//   * `example` must be a complete, self-contained program that compiles
//     (`fn main` included) for `.supported` entries.
//   * `avoid` lists spellings that look plausible but do NOT compile, so that
//     code generators can steer clear of them.
//   * Every entry is addressable by a stable `name`.
// ════════════════════════════════════════════════════════════════════════════

const std = @import("std");

pub const Status = enum(u8) {
    /// Implemented, covered by the regression matrix; safe to generate.
    supported,
    /// Parsed/implemented with documented limits; read `notes` first.
    partial,
    /// Accepted but not canonical; prefer the spelling named in `prefer`.
    legacy,
    /// Not implemented: the compiler rejects it with a diagnostic.
    unsupported,

    pub fn label(self: Status) []const u8 {
        return switch (self) {
            .supported => "supported",
            .partial => "partial",
            .legacy => "legacy",
            .unsupported => "unsupported",
        };
    }

    pub fn parse(s: []const u8) ?Status {
        if (std.mem.eql(u8, s, "supported")) return .supported;
        if (std.mem.eql(u8, s, "partial")) return .partial;
        if (std.mem.eql(u8, s, "legacy")) return .legacy;
        if (std.mem.eql(u8, s, "unsupported")) return .unsupported;
        return null;
    }
};

pub const Category = enum(u8) {
    declaration,
    statement,
    expression,
    type_syntax,
    attribute,
    builtin,
    pattern,

    pub fn label(self: Category) []const u8 {
        return switch (self) {
            .declaration => "declaration",
            .statement => "statement",
            .expression => "expression",
            .type_syntax => "type",
            .attribute => "attribute",
            .builtin => "builtin",
            .pattern => "pattern",
        };
    }
};

pub const Feature = struct {
    /// Stable identifier, snake_case (`for_range`, `match_enum_payload`).
    name: []const u8,
    category: Category,
    status: Status,
    /// Canonical syntax, one line.
    syntax: []const u8,
    /// What it does and the limits a code generator must respect.
    notes: []const u8,
    /// Complete compilable program for `.supported`/`.partial` entries.
    example: []const u8 = "",
    /// Spellings/constructs that do not compile, and the canonical replacement.
    avoid: []const u8 = "",
    /// For `.legacy`: the canonical spelling to use instead.
    prefer: []const u8 = "",
};

// ════════════════════════════════════════════════════════════════════════════
// THE CATALOGUE
// ════════════════════════════════════════════════════════════════════════════

pub const features = [_]Feature{
    // ── Declarations ───────────────────────────────────────────────────────
    .{
        .name = "fn",
        .category = .declaration,
        .status = .supported,
        .syntax = "fn name(p: T, q: T = default) -> T { ... }",
        .notes = "Top-level only: no nested/named-inner functions. Every non-void function must return a value on all paths. Statements are newline separated; ';' is optional and rarely needed. Maximum 8 parameters.",
        .example =
        \\fn add(a: i64, b: i64) -> i64 {
        \\    return a + b
        \\}
        \\
        \\fn main() -> i64 {
        \\    printInt(add(2, 3))
        \\    return 0
        \\}
        ,
        .avoid = "nested 'fn' inside a body, closures declared with 'fn(x){}'; use |x| ... for lambdas",
    },
    .{
        .name = "proc",
        .category = .declaration,
        .status = .legacy,
        .syntax = "proc name(...) -> T { ... }",
        .notes = "Alias of 'fn' kept for older code. New code must use 'fn'.",
        .example =
        \\proc twice(x: i64) -> i64 {
        \\    return x * 2
        \\}
        \\
        \\fn main() -> i64 {
        \\    return twice(21)
        \\}
        ,
        .prefer = "fn",
    },
    .{
        .name = "const_global",
        .category = .declaration,
        .status = .supported,
        .syntax = "const NAME: i64 = value",
        .notes = "Global constants only; there are no global mutable variables. The type annotation is optional. Constant expressions may use arithmetic, '**' and comptime calls.",
        .example =
        \\const LIMIT: i64 = 3 ** 4
        \\
        \\fn main() -> i64 {
        \\    return LIMIT - 81
        \\}
        ,
        .avoid = "top-level 'let'/'var'; they are rejected with a hint to use 'const'",
    },
    .{
        .name = "struct",
        .category = .declaration,
        .status = .supported,
        .syntax = "struct Name { field: T }",
        .notes = "Fields are newline separated, not comma separated. Field declarations may not name another struct type (use a pointer to it). Layout is 8-byte slots with documented offsets (lir ast shows them). Maximum 32 fields.",
        .example =
        \\struct Point {
        \\    x: i64
        \\    y: i64
        \\}
        \\
        \\fn main() -> i64 {
        \\    let p = Point { x: 3, y: 4 }
        \\    return p.x * 10 + p.y
        \\}
        ,
        .avoid = "struct A { b: B }  (field of struct type); store *B instead",
    },
    .{
        .name = "struct_init",
        .category = .expression,
        .status = .supported,
        .syntax = "Name { field: value, field2: value2 }",
        .notes = "All declared fields must be listed; commas are required inside the braces.",
        .example =
        \\struct P {
        \\    a: i64
        \\    b: i64
        \\}
        \\
        \\fn main() -> i64 {
        \\    let p = P { a: 1, b: 2 }
        \\    return p.a + p.b
        \\}
        ,
    },
    .{
        .name = "enum",
        .category = .declaration,
        .status = .supported,
        .syntax = "enum Name { A, B(i64), C(i64, bool) }",
        .notes = "Variants are comma separated. A variant may carry up to 8 payload fields. Construct with Name::Variant(...), compare with ==. Matching an enum requires exhaustive arms.",
        .example =
        \\enum Shape {
        \\    Circle(i64),
        \\    Empty,
        \\}
        \\
        \\fn main() -> i64 {
        \\    let s = Shape::Circle(7)
        \\    return match s {
        \\        Shape::Circle(r) => r * 2,
        \\        Shape::Empty => 0,
        \\    }
        \\}
        ,
    },
    .{
        .name = "union",
        .category = .declaration,
        .status = .supported,
        .syntax = "union Name { i: i64 f: f64 }",
        .notes = "Untagged C-style union of 8-byte slots. Reading a field other than the one written is not type-checked.",
        .example =
        \\union Bits {
        \\    i: i64
        \\    f: f64
        \\}
        \\
        \\fn main() -> i64 {
        \\    let b = Bits { i: 5 }
        \\    return b.i
        \\}
        ,
    },
    .{
        .name = "impl_methods",
        .category = .declaration,
        .status = .supported,
        .syntax = "impl Name { fn m(self) -> T { ... } }",
        .notes = "Structs + impl blocks: the closest thing LIR has to methods, but there is no inheritance, no embedding and no operator overloading. Methods receive 'self' (read-only) or 'self: *mut Self' (mutable). Call with value syntax p.m(); the receiver is auto-referenced. There is no 'impl Trait for Type' free-standing method block other than trait impls.",
        .example =
        \\struct Counter {
        \\    n: i64
        \\}
        \\
        \\impl Counter {
        \\    fn value(self) -> i64 {
        \\        return self.n
        \\    }
        \\    fn bump(self: *mut Counter) -> i64 {
        \\        self.n = self.n + 1
        \\        return self.n
        \\    }
        \\}
        \\
        \\fn main() -> i64 {
        \\    var c = Counter { n: 0 }
        \\    c.bump()
        \\    return c.value() * 10 + c.bump()
        \\}
        ,
    },
    .{
        .name = "trait_dyn",
        .category = .declaration,
        .status = .supported,
        .syntax = "trait T { fn m(self) -> T }\nstruct S { .. }\nimpl T for S { fn m(self) -> T { ... } }\nfn f(x: dyn T) -> T",
        .notes = "Dynamic dispatch through a 'dyn Trait' parameter. Every declared method must be implemented, and the implementation must match the trait exactly: same parameter count/types and same return type, so a mismatched impl fails with LIR-E3005/LIR-E3004. Receiver forms are 'self', 'self: *T', 'self: *mut T', '&self', '&mut self'; a trait may declare a mutable receiver only as '&mut self' or 'self: *mut T'. Trait methods cannot have default bodies. Values are passed by value and the vtable is selected at the call site. Traits cannot be used as standalone values ('let t: T'), only as 'dyn T' parameters/returns.",
        .example =
        \\trait Area {
        \\    fn area(self) -> i64
        \\}
        \\
        \\struct Square {
        \\    side: i64
        \\}
        \\
        \\impl Area for Square {
        \\    fn area(self) -> i64 {
        \\        return self.side * self.side
        \\    }
        \\}
        \\
        \\fn measure(shape: dyn Area) -> i64 {
        \\    return shape.area()
        \\}
        \\
        \\fn main() -> i64 {
        \\    let s = Square { side: 3 }
        \\    return measure(s)
        \\}
        ,
    },
    .{
        .name = "type_alias",
        .category = .declaration,
        .status = .supported,
        .syntax = "type Alias = i64",
        .notes = "Plain alias; the alias name is interchangeable with the aliased type.",
        .example =
        \\type Count = i64
        \\
        \\fn main() -> i64 {
        \\    let c: Count = 4
        \\    return c
        \\}
        ,
    },
    .{
        .name = "bounded_range_type",
        .category = .declaration,
        .status = .supported,
        .syntax = "type Percent = i64 range 0..100",
        .notes = "Bounded integer type. Constant assignments outside the range are compile errors (LIR-E3004); dynamic values are not trapped by this type alone.",
        .example =
        \\type Percent = i64 range 0..100
        \\
        \\fn main() -> i64 {
        \\    let p: Percent = 42
        \\    return p
        \\}
        ,
    },
    .{
        .name = "generics",
        .category = .declaration,
        .status = .supported,
        .syntax = "fn id<T>(x: T) -> T\nstruct Box<T> { v: T }\nid<i64>(3)\nBox<i64> { v: 3 }",
        .notes = "Monomorphized generics: instantiate explicitly with <T> at call/construction sites. Nested generic arguments such as Option<Option<i64>> do not parse because '>>' lexes as a shift; bind an alias first.",
        .example =
        \\struct Box<T> {
        \\    v: T
        \\}
        \\
        \\fn id<T>(x: T) -> T {
        \\    return x
        \\}
        \\
        \\fn main() -> i64 {
        \\    let b = Box<i64> { v: 5 }
        \\    return id<i64>(b.v)
        \\}
        ,
        .avoid = "Option<Option<i64>>, Vec<Vec<i64>> (nested '>>')",
    },
    .{
        .name = "import",
        .category = .declaration,
        .status = .supported,
        .syntax = "import core\nimport math\nimport std::crypto\nimport \"../lib/util.lir\"",
        .notes = "Resolves to an embedded std module (core, io, os, sys, net, crypto, json, math, str, algo, testing, collections, hash, fmt, time, http), to a sibling/local .lir file, or to a quoted path. Members are unqualified after import. An unknown name that is not a local file stops compilation with LIR-E4004 and a suggestion.",
        .example =
        \\import math
        \\
        \\fn main() -> i64 {
        \\    return factorial_i64(5)
        \\}
        ,
        .avoid = "import MyLib (PascalCase), import lib.rs",
    },
    .{
        .name = "pub",
        .category = .declaration,
        .status = .legacy,
        .syntax = "pub fn f() -> T { ... }",
        .notes = "Accepted and ignored: LIR has no module privacy; every declaration in an imported file is visible.",
        .example =
        \\pub fn helper() -> i64 {
        \\    return 1
        \\}
        \\
        \\fn main() -> i64 {
        \\    return helper()
        \\}
        \\
        ,
        .prefer = "fn (privacy is not implemented)",
    },
    .{
        .name = "extern_ffi",
        .category = .declaration,
        .status = .unsupported,
        .syntax = "extern fn puts(s: string) -> i64",
        .notes = "There is no C FFI declaration syntax yet. Use the @syscall/@open/@write family, or compile with --emit-c and link in C.",
        .avoid = "extern fn / extern \"C\" blocks",
    },
    .{
        .name = "module_file",
        .category = .declaration,
        .status = .unsupported,
        .syntax = "mod foo",
        .notes = "Modules are files reached through 'import', not 'mod' declarations.",
        .avoid = "mod foo { ... }",
    },

    // ── Statements ─────────────────────────────────────────────────────────
    .{
        .name = "let",
        .category = .statement,
        .status = .supported,
        .syntax = "let x = value        let x: i64 = value",
        .notes = "Immutable binding; the annotation is optional and drives type checking. Re-declaring the same name in the same scope is an error (LIR-E3003); use a new scope to shadow.",
        .example =
        \\fn main() -> i64 {
        \\    let a = 2
        \\    let b: i64 = 3
        \\    return a * b
        \\}
        ,
        .avoid = "let x: i64;  (declaration without initializer)",
    },
    .{
        .name = "let_mut",
        .category = .statement,
        .status = .supported,
        .syntax = "let mut x = value",
        .notes = "Mutable local binding. 'var' is accepted as a legacy synonym for 'let mut'.",
        .example =
        \\fn main() -> i64 {
        \\    let mut total = 0
        \\    total = total + 5
        \\    total += 2
        \\    return total
        \\}
        ,
        .avoid = "let x = 0; x = 1  (immutable binding)",
        .prefer = "let mut",
    },
    .{
        .name = "var",
        .category = .statement,
        .status = .legacy,
        .syntax = "var x = value",
        .notes = "Legacy synonym of 'let mut'. Prefer 'let mut' so mutation is explicit at the declaration site.",
        .example =
        \\fn main() -> i64 {
        \\    var x = 1
        \\    x = 2
        \\    return x
        \\}
        ,
        .prefer = "let mut",
    },
    .{
        .name = "const_local",
        .category = .statement,
        .status = .supported,
        .syntax = "const NAME = constant_expression",
        .notes = "Compile-time constant usable inside a function body; the value must be knowable at compile time.",
        .example =
        \\fn main() -> i64 {
        \\    const N = 2 ** 5
        \\    return N
        \\}
        ,
    },
    .{
        .name = "assignment",
        .category = .statement,
        .status = .supported,
        .syntax = "x = v  x += v  x -= v  x *= v  x /= v  x %= v  x **= v  x &= v  x |= v  x ^= v  x <<= v  x >>= v",
        .notes = "Targets: local variables, struct fields, pointer dereferences and array elements. Assigning to an immutable binding or while it is borrowed is an error.",
        .example =
        \\fn main() -> i64 {
        \\    let mut x: i64 = 8
        \\    x += 2
        \\    x *= 3
        \\    x >>= 1
        \\    return x
        \\}
        ,
    },
    .{
        .name = "if_elif_else",
        .category = .statement,
        .status = .supported,
        .syntax = "if cond { } elif cond { } else { }",
        .notes = "Blocks are always required. Conditions must be bool; '=' inside a condition is reported with a did-you-mean-'==' hint. 'if' is also an expression that yields a value (see if_expression).",
        .example =
        \\fn grant(score: i64) -> i64 {
        \\    if score > 90 {
        \\        return 3
        \\    } elif score > 50 {
        \\        return 2
        \\    } else {
        \\        return 1
        \\    }
        \\}
        \\
        \\fn main() -> i64 {
        \\    return grant(95) * 100 + grant(10)
        \\}
        ,
        .avoid = "if a = 1 { }  |  if x > 0 (no braces)",
    },
    .{
        .name = "if_expression",
        .category = .expression,
        .status = .supported,
        .syntax = "let v = if cond { 1 } else { 2 }",
        .notes = "Both branches must produce a value of the same type; an 'else' branch is mandatory when a value is used.",
        .example =
        \\fn main() -> i64 {
        \\    let flag = 7 > 3
        \\    let v = if flag { 10 } else { 20 }
        \\    return v
        \\}
        ,
    },
    .{
        .name = "unless",
        .category = .statement,
        .status = .supported,
        .syntax = "unless cond { } else { }",
        .notes = "Negated 'if' (Elixir-style). It is a value expression as well. Prefer 'if !cond' for audiences unfamiliar with LIR.",
        .example =
        \\fn main() -> i64 {
        \\    let x = 0
        \\    unless x == 0 {
        \\        return 100 / x
        \\    } else {
        \\        return 0
        \\    }
        \\}
        ,
        .prefer = "if !cond",
    },
    .{
        .name = "while",
        .category = .statement,
        .status = .supported,
        .syntax = "while cond { }",
        .notes = "Pre-test loop. Provide loop progress: an infinite body that freezes its condition variables is rejected, and break/continue are not allowed inside 'defer'.",
        .example =
        \\fn main() -> i64 {
        \\    let mut i = 0
        \\    while i < 5 {
        \\        i += 1
        \\    }
        \\    return i
        \\}
        ,
    },
    .{
        .name = "loop",
        .category = .statement,
        .status = .supported,
        .syntax = "loop { ... break }",
        .notes = "Unconditional loop; exits only through break/return. There are no labels and no 'break value'.",
        .example =
        \\fn main() -> i64 {
        \\    let mut n = 0
        \\    loop {
        \\        n += 1
        \\        if n == 3 {
        \\            break
        \\        }
        \\    }
        \\    return n
        \\}
        ,
        .avoid = "'outer: loop { break 'outer }  (no labels)",
    },
    .{
        .name = "until",
        .category = .statement,
        .status = .supported,
        .syntax = "until cond { }",
        .notes = "Runs the body until the condition becomes true. Prefer 'while !cond' for cross-language readers.",
        .example =
        \\fn main() -> i64 {
        \\    let mut i = 0
        \\    until i >= 3 {
        \\        i += 1
        \\    }
        \\    return i
        \\}
        ,
        .prefer = "while !cond",
    },
    .{
        .name = "for_range",
        .category = .statement,
        .status = .supported,
        .syntax = "for i in start..end { }\nfor i in start..=end { }",
        .notes = "'..' excludes the end bound, '..=' includes it. Bounds must be integers; both are evaluated once, before the first iteration. The loop variable is immutable.",
        .example =
        \\fn main() -> i64 {
        \\    let mut sum = 0
        \\    for i in 0..4 {
        \\        sum += i
        \\    }
        \\    for i in 4..=4 {
        \\        sum += i
        \\    }
        \\    return sum
        \\}
        ,
    },
    .{
        .name = "for_in",
        .category = .statement,
        .status = .supported,
        .syntax = "for v in array { }\nfor c in text { }",
        .notes = "Iterates a dynamic array (@array_new) or a string byte by byte. The loop variable is the element value. There is no index/value pair form.",
        .example =
        \\fn main() -> i64 {
        \\    let items = @array_new(4, 8)
        \\    @array_push(items, 5)
        \\    @array_push(items, 6)
        \\    let mut sum = 0
        \\    for v in items {
        \\        sum += v
        \\    }
        \\    return sum
        \\}
        ,
        .avoid = "for i, v in items  (index is not supported)",
    },
    .{
        .name = "break_continue",
        .category = .statement,
        .status = .supported,
        .syntax = "break\ncontinue",
        .notes = "Only inside loops, never inside a 'defer' block, and there are no labelled variants.",
        .example =
        \\fn main() -> i64 {
        \\    let mut sum = 0
        \\    for i in 0..10 {
        \\        if i == 5 {
        \\            break
        \\        }
        \\        if i % 2 == 0 {
        \\            continue
        \\        }
        \\        sum += i
        \\    }
        \\    return sum
        \\}
        ,
    },
    .{
        .name = "return",
        .category = .statement,
        .status = .supported,
        .syntax = "return value\nreturn",
        .notes = "A trailing expression without 'return' is also accepted in value functions; explicit 'return' is the canonical style.",
        .example =
        \\fn sign(x: i64) -> i64 {
        \\    if x < 0 {
        \\        return -1
        \\    }
        \\    return 1
        \\}
        \\
        \\fn main() -> i64 {
        \\    return sign(-5) + sign(5)
        \\}
        ,
    },
    .{
        .name = "defer",
        .category = .statement,
        .status = .supported,
        .syntax = "defer statement   defer { block }",
        .notes = "Runs on every exit from the enclosing scope, in LIFO order. break/continue/return are rejected inside a deferred block.",
        .example =
        \\fn main() -> i64 {
        \\    defer println("second")
        \\    defer println("first")
        \\    return 0
        \\}
        ,
    },
    .{
        .name = "guard_else",
        .category = .statement,
        .status = .supported,
        .syntax = "guard cond else { return ... }",
        .notes = "Early-exit helper: the else block must leave the function. It does not bind values and does not support 'guard let'.",
        .example =
        \\fn ratio(a: i64, b: i64) -> i64 {
        \\    guard b != 0 else {
        \\        return -1
        \\    }
        \\    return a / b
        \\}
        \\
        \\fn main() -> i64 {
        \\    return ratio(9, 3) * 10 + ratio(1, 0)
        \\}
        ,
    },
    .{
        .name = "match",
        .category = .expression,
        .status = .supported,
        .syntax = "match value { pattern => expr, ... }",
        .notes = "Expression form: arms are comma separated and produce a value. Matching must be exhaustive: integers need a '_' (or 'else') arm, enums need every variant or a fallback, bools may cover true/false.",
        .example =
        \\fn classify(n: i64) -> i64 {
        \\    return match n {
        \\        0 => 100,
        \\        1..=9 => 10,
        \\        v if v > 100 => 1000,
        \\        _ => 0,
        \\    }
        \\}
        \\
        \\fn main() -> i64 {
        \\    return classify(0) + classify(5) + classify(500) + classify(-3)
        \\}
        ,
    },
    .{
        .name = "unreachable",
        .category = .statement,
        .status = .supported,
        .syntax = "unreachable",
        .notes = "Marks a path that must not be taken; reaching it traps at runtime.",
        .example =
        \\fn main() -> i64 {
        \\    let x = 1
        \\    if x == 1 {
        \\        return 0
        \\    }
        \\    unreachable
        \\}
        ,
    },
    .{
        .name = "unsafe_block",
        .category = .statement,
        .status = .unsupported,
        .syntax = "unsafe { ... }",
        .notes = "Rejected: raw pointer work is expressed with the *T / @read_* / @write_* builtins instead of an unsafe block.",
        .avoid = "unsafe { }",
    },
    .{
        .name = "asm_block",
        .category = .statement,
        .status = .unsupported,
        .syntax = "asm(\"...\")",
        .notes = "Rejected: there is no inline assembly. Use @syscall or --emit-c plus a C translation unit.",
        .avoid = "asm(\"nop\")",
    },

    // ── Expressions ────────────────────────────────────────────────────────
    .{
        .name = "operators",
        .category = .expression,
        .status = .supported,
        .syntax = "a + b - c * d / e % f ** g  |  a & b | c ^ d << e >> f  |  a == b != c < d <= e > f >= g",
        .notes = "'**' is right-associative integer power and binds tighter than unary minus. Arithmetic wraps modulo 2^64 (no overflow trap); division by zero and out-of-range shifts trap. Precedence: '**' > unary > '* / %' > '+ -' > shifts > '&' > '^' > '|' > comparisons > '&&' > '||' > ternary > assignment.",
        .example =
        \\fn main() -> i64 {
        \\    let a = 2 + 3 * 4
        \\    let b = 2 ** 3 ** 2
        \\    let c = (5 & 3) | (8 ^ 1) << 1
        \\    return a + b + c
        \\}
        ,
    },
    .{
        .name = "boolean_operators",
        .category = .expression,
        .status = .supported,
        .syntax = "a and b   a or b   a && b   a || b   !a",
        .notes = "'and'/'or' are the documented spellings; '&&' and '||' are exact synonyms. 'not' is NOT a keyword.",
        .example =
        \\fn main() -> i64 {
        \\    if true and !false {
        \\        return 1
        \\    }
        \\    if false || true {
        \\        return 2
        \\    }
        \\    return 0
        \\}
        ,
        .avoid = "not x  (use !x)",
    },
    .{
        .name = "ternary",
        .category = .expression,
        .status = .supported,
        .syntax = "cond ? a : b",
        .notes = "Shorthand for a two-armed if-expression. Both sides must have the same type.",
        .example =
        \\fn main() -> i64 {
        \\    let x = 7
        \\    return x % 2 == 0 ? 100 : 200
        \\}
        ,
    },
    .{
        .name = "cast_as",
        .category = .expression,
        .status = .supported,
        .syntax = "value as u8    value as i64    value as f64",
        .notes = "Integer casts narrow by keeping the low bits (300 as u8 == 44). Float to integer truncates toward zero and traps on NaN/out-of-range. Integer to float preserves signedness. There is no implicit numeric conversion.",
        .example =
        \\fn main() -> i64 {
        \\    let wide: i64 = 300
        \\    let narrow = wide as u8
        \\    let back = narrow as i64
        \\    let f = 2.75
        \\    return back + (f as i64)
        \\}
        ,
        .avoid = "implicit widening: let x: i64 = a_i32  (write 'as i64')",
    },
    .{
        .name = "string_literal",
        .category = .expression,
        .status = .supported,
        .syntax = "\"plain\"  \"tab\\there\\n\"  \"quote\\\"inside\"",
        .notes = "UTF-8, immutable, length-prefixed. Escape sequences: \\n \\t \\r \\\\ \\\" \\0. Concatenate with '+', compare with '==', index with s[i] (byte value), read s.len.",
        .example =
        \\fn main() -> i64 {
        \\    let s = "lir" + "lang"
        \\    println(s)
        \\    if s == "lirlang" {
        \\        return s.len
        \\    }
        \\    return 0
        \\}
        ,
    },
    .{
        .name = "string_interpolation",
        .category = .expression,
        .status = .supported,
        .syntax = "\"sum = {a + b}\"   \"len={s.len}\"",
        .notes = "Any expression inside { } is interpolated. Literal braces must be escaped as \\{ and \\}. Format specifiers such as {x:#x} are NOT supported (they print literally); use a formatting helper from std::fmt instead.",
        .example =
        \\fn main() -> i64 {
        \\    let a = 2
        \\    let b = 3
        \\    println("{a}+{b}={a + b}")
        \\    return 0
        \\}
        ,
        .avoid = "println(\"{42:#x}\")  (no format specifiers)",
    },
    .{
        .name = "char_literal",
        .category = .expression,
        .status = .supported,
        .syntax = "'A'   '\\n'",
        .notes = "A char literal is an i64 code point value. There is no distinct 'char' type (annotating with 'char' is rejected).",
        .example =
        \\fn main() -> i64 {
        \\    let c = 'A'
        \\    return c - 64
        \\}
        ,
        .avoid = "let c: char = 'A'  (no char type)",
    },
    .{
        .name = "numeric_literals",
        .category = .expression,
        .status = .supported,
        .syntax = "123  0xFF  0b1010  0o17  1_000  1.5  2.5e3",
        .notes = "Decimal, hex, binary, octal with '_' separators. Integer literals type-check against their context inside the i64 range; a float literal needs a float context (a bare '1' is not a float).",
        .example =
        \\fn main() -> i64 {
        \\    let a = 0xFF
        \\    let b = 0b1010
        \\    let c = 1_000
        \\    return a + b + c
        \\}
        ,
    },
    .{
        .name = "array_literal",
        .category = .expression,
        .status = .supported,
        .syntax = "[1, 2, 3]   [value; count]",
        .notes = "Fixed-size array on the stack; index with a[i] (runtime bounds-checked, out of range traps). Use @array_new/@array_push for growable arrays.",
        .example =
        \\fn main() -> i64 {
        \\    let a = [10, 20, 30]
        \\    let zeros = [0; 2]
        \\    return a[1] + zeros[0]
        \\}
        ,
        .avoid = "[[1,2],[3,4]]  (nested array literals do not type-check)",
    },
    .{
        .name = "dynamic_array",
        .category = .expression,
        .status = .supported,
        .syntax = "@array_new(capacity, elem_size)  @array_push(a, v)  @array_get(a, i)  @array_len(a)  @array_free(a)",
        .notes = "Heap array of 8-byte slots by default. @array_get is bounds-checked and traps out of range. Free with @array_free (compile-time UAF/double-free analysis covers straight-line code).",
        .example =
        \\fn main() -> i64 {
        \\    let a = @array_new(8, 8)
        \\    @array_push(a, 4)
        \\    @array_push(a, 5)
        \\    let n = @array_len(a)
        \\    let sum = @array_get(a, 0) + @array_get(a, 1)
        \\    @array_free(a)
        \\    return n * 10 + sum
        \\}
        ,
    },
    .{
        .name = "tuple",
        .category = .expression,
        .status = .supported,
        .syntax = "(1, true)   t.0   let (a, b) = pair",
        .notes = "Tuples hold up to 8 fields in 8-byte slots; field access is t.0 ... t.7. Destructuring is supported in 'let'. Field types keep their width/signedness.",
        .example =
        \\fn pair() -> (i64, bool) {
        \\    return (7, true)
        \\}
        \\
        \\fn main() -> i64 {
        \\    let (value, ok) = pair()
        \\    if ok {
        \\        return value
        \\    }
        \\    return 0
        \\}
        ,
        .avoid = "(1,2,3,4,5,6,7,8,9)  (max 8 fields)",
    },
    .{
        .name = "option",
        .category = .type_syntax,
        .status = .supported,
        .syntax = "fn f() -> Option<i64> { return Some(1) }\nlet x: ?i64 = None",
        .notes = "Some(v)/None are context-typed: 'None' needs a typed local, return type or '?' context (a bare 'let x = None' is rejected with 'add type annotation'). Read the payload with match or '?'. Note '?i64' is also accepted as a type spelling.",
        .example =
        \\fn find(ok: bool) -> Option<i64> {
        \\    if ok {
        \\        return Some(5)
        \\    }
        \\    return None
        \\}
        \\
        \\fn main() -> i64 {
        \\    return match find(true) {
        \\        Some(v) => v,
        \\        None => 0,
        \\    }
        \\}
        ,
        .avoid = "let x = None  (no context) | Option<i64> { .. } struct syntax",
    },
    .{
        .name = "result",
        .category = .type_syntax,
        .status = .supported,
        .syntax = "fn f() -> Result<i64, i64> { return Ok(1) }\nlet v = g()?",
        .notes = "Ok(v)/Err(e) with '?' propagation to the caller. '??' supplies a default for Option. The error payload is 8 bytes (i64 or pointer).",
        .example =
        \\fn step() -> Result<i64, i64> {
        \\    return Ok(4)
        \\}
        \\
        \\fn run() -> Result<i64, i64> {
        \\    let v = step()?
        \\    return Ok(v + 1)
        \\}
        \\
        \\fn main() -> i64 {
        \\    return match run() {
        \\        Ok(v) => v,
        \\        Err(e) => e,
        \\    }
        \\}
        ,
    },
    .{
        .name = "question_mark",
        .category = .expression,
        .status = .supported,
        .syntax = "let v = fallible()?",
        .notes = "Propagates None/Err to the enclosing function, whose return type must be Option/Result. Also see '??' for a default value.",
        .example =
        \\fn fetch(ok: bool) -> Option<i64> {
        \\    if !ok {
        \\        return None
        \\    }
        \\    return Some(9)
        \\}
        \\
        \\fn twice(ok: bool) -> Option<i64> {
        \\    let v = fetch(ok)?
        \\    return Some(v * 2)
        \\}
        \\
        \\fn main() -> i64 {
        \\    return match twice(true) {
        \\        Some(v) => v,
        \\        None => 0,
        \\    }
        \\}
        ,
    },
    .{
        .name = "coalesce",
        .category = .expression,
        .status = .supported,
        .syntax = "let v = maybe ?? fallback",
        .notes = "Evaluates to the Option payload when present, otherwise to the fallback expression.",
        .example =
        \\fn main() -> i64 {
        \\    let present: ?i64 = Some(3)
        \\    let missing: ?i64 = None
        \\    return (present ?? 7) * 10 + (missing ?? 7)
        \\}
        ,
    },
    .{
        .name = "pointer",
        .category = .type_syntax,
        .status = .supported,
        .syntax = "*T   *mut T   &value   &mut value   *p = v   p.field",
        .notes = "Typed pointers to locals, structs and heap memory. '&x' borrows read-only, '&mut x' borrows mutably and blocks reads/writes of x while live. Returning a pointer to a local is a compile error. Raw addresses use @ptr_add/@read_*/@write_*.",
        .example =
        \\struct Cell {
        \\    v: i64
        \\}
        \\
        \\fn bump(c: *mut Cell) -> i64 {
        \\    c.v = c.v + 1
        \\    return c.v
        \\}
        \\
        \\fn main() -> i64 {
        \\    var c = Cell { v: 4 }
        \\    return bump(&mut c)
        \\}
        ,
        .avoid = "returning &local  (dangling) | *p arithmetic without @ptr_add",
    },
    .{
        .name = "slice_type",
        .category = .type_syntax,
        .status = .partial,
        .syntax = "fn first(items: []i64) -> i64",
        .notes = "The '[]T' spelling parses and type-checks, and a dynamic array can be passed to it, but there is no slice-of-slice slicing operator and no '.len' on slices (use @array_len on the array).",
        .example =
        \\fn first(items: []i64) -> i64 {
        \\    return items[0]
        \\}
        \\
        \\fn main() -> i64 {
        \\    let a = @array_new(4, 8)
        \\    @array_push(a, 9)
        \\    return first(a)
        \\}
        ,
        .avoid = "s[a..b]  (no slice ranges)",
    },
    .{
        .name = "fn_pointer",
        .category = .type_syntax,
        .status = .supported,
        .syntax = "let f: fn(i64) -> i64 = name\napply(f, 3)",
        .notes = "Function values are first class: pass named functions, store them in locals, and call them through the binding. Struct fields cannot hold them (the field is then read as a method).",
        .example =
        \\fn triple(x: i64) -> i64 {
        \\    return x * 3
        \\}
        \\
        \\fn apply(f: fn(i64) -> i64, v: i64) -> i64 {
        \\    return f(v)
        \\}
        \\
        \\fn main() -> i64 {
        \\    let f: fn(i64) -> i64 = triple
        \\    return apply(f, 4)
        \\}
        ,
    },
    .{
        .name = "closure",
        .category = .expression,
        .status = .supported,
        .syntax = "let f = |x: i64| x + 1\nlet g = || 7\nlet h = |x: i64| -> i64 { return x }",
        .notes = "Pipe-delimited lambdas with capture by value of surrounding locals. '||' introduces a no-argument closure. A closure body may be an expression or a block.",
        .example =
        \\fn main() -> i64 {
        \\    let step = 2
        \\    let add = |x: i64| x + step
        \\    let seven = || 7
        \\    return add(seven())
        \\}
        ,
        .avoid = "|x|... , fn(x: i64) -> i64 { }  (closures are not 'fn' literals)",
    },
    .{
        .name = "method_call",
        .category = .expression,
        .status = .supported,
        .syntax = "receiver.method(args)",
        .notes = "Methods come from 'impl'. Field access and method calls share syntax, so a struct field that has the same name as a method is ambiguous (methods win).",
        .example =
        \\struct Bag {
        \\    n: i64
        \\}
        \\
        \\impl Bag {
        \\    fn doubled(self) -> i64 {
        \\        return self.n * 2
        \\    }
        \\}
        \\
        \\fn main() -> i64 {
        \\    let b = Bag { n: 6 }
        \\    return b.doubled()
        \\}
        ,
    },
    .{
        .name = "named_arguments",
        .category = .expression,
        .status = .supported,
        .syntax = "calc(2, code: 9)   calc(code: next(), a: next())",
        .notes = "Named/out-of-order arguments are allowed on direct free-function calls only. Evaluation follows source order. Defaults may reference global constants.",
        .example =
        \\fn box(a: i64, b: i64 = 3) -> i64 {
        \\    return a * 10 + b
        \\}
        \\
        \\fn main() -> i64 {
        \\    return box(1) + box(b: 5, a: 2)
        \\}
        ,
        .avoid = "named arguments on method calls or builtins",
    },
    .{
        .name = "list_comprehension",
        .category = .expression,
        .status = .supported,
        .syntax = "[expr for v in iterable]\n[expr for v in start..end]   [expr for v in a..b if cond]",
        .notes = "Builds a dynamic array from a range (with optional '..='), an array or a string, optionally filtered with 'if'. The result is a heap array; free it with @array_free.",
        .example =
        \\fn main() -> i64 {
        \\    let squares = [i * i for i in 0..4]
        \\    let evens = [i for i in 0..10 if i % 2 == 0]
        \\    let a = @array_len(squares)
        \\    let b = @array_len(evens)
        \\    @array_free(squares)
        \\    @array_free(evens)
        \\    return a * 10 + b
        \\}
        ,
    },
    .{
        .name = "map",
        .category = .type_syntax,
        .status = .supported,
        .syntax = "let m = @map_new()\n@map_set(m, key, v)  @map_get(m, key)  @map_has(m, key)  @map_del(m, key)",
        .notes = "Hash map with i64 or string keys depending on the first key used; keys are hashed with a per-process secret (HashDoS safe). @map_get returns 0 for a missing key: check @map_has first.",
        .example =
        \\fn main() -> i64 {
        \\    let m = @map_new()
        \\    @map_set(m, 1, 40)
        \\    @map_set(m, 2, 2)
        \\    let total = @map_get(m, 1) + @map_get(m, 2)
        \\    @map_free(m)
        \\    return total
        \\}
        ,
        .avoid = "@map_get without @map_has  (missing keys yield 0)",
    },
    .{
        .name = "map_literal",
        .category = .expression,
        .status = .supported,
        .syntax = "let m = #{ \"key\": 1 }",
        .notes = "Literal map construction; '#' followed by '{' is the disambiguator. The same as @map_new + @map_set.",
        .example =
        \\fn main() -> i64 {
        \\    let m = #{ "a": 3 }
        \\    let v = @map_get(m, "a")
        \\    @map_free(m)
        \\    return v
        \\}
        ,
    },
    .{
        .name = "spawn",
        .category = .expression,
        .status = .supported,
        .syntax = "let h = spawn worker(arg)\nlet h2 = spawn { body }\n@thread_join(h)",
        .notes = "Starts an OS thread (host targets only: x86_64/aarch64/riscv64 Linux, macOS, Windows, FreeBSD). The thread body may take one i64 argument passed by value; spawn { ... } and closures take none. Passing pointers to locals into a thread is rejected. Join with @thread_join, which yields the body's return value. wasm32-wasi has no OS threads: the compiler rejects thread/channel builtins there with LIR-E7004.",
        .example =
        \\fn worker(arg: i64) -> i64 {
        \\    return arg * 3
        \\}
        \\
        \\fn main() -> i64 {
        \\    let h = spawn worker(14)
        \\    return @thread_join(h)
        \\}
        ,
    },
    .{
        .name = "channel",
        .category = .expression,
        .status = .supported,
        .syntax = "let c = @chan_new(capacity)\n@chan_send(c, v)  @chan_recv(c)  @chan_close(c)",
        .notes = "Bounded MPMC channel of 8-byte values. @chan_recv blocks until a value is available. Requires a host target with OS threads: wasm32-wasi rejects it with LIR-E7004.",
        .example =
        \\fn main() -> i64 {
        \\    let c = @chan_new(1)
        \\    @chan_send(c, 6)
        \\    let v = @chan_recv(c)
        \\    @chan_close(c)
        \\    return v
        \\}
        ,
    },
    .{
        .name = "atomic",
        .category = .expression,
        .status = .supported,
        .syntax = "@atomic_add(ptr, v)   @atomic_cas(ptr, old, new)",
        .notes = "Sequentially consistent operations on 8-byte aligned memory. @atomic_add returns the previous value.",
        .example =
        \\fn main() -> i64 {
        \\    let slot = @malloc(8)
        \\    @atomic_add(slot, 2)
        \\    let v = @atomic_add(slot, 3)
        \\    @free(slot)
        \\    return v
        \\}
        ,
    },
    .{
        .name = "comptime",
        .category = .expression,
        .status = .supported,
        .syntax = "comptime fn f(n: i64) -> i64 { ... }\nconst V = f(10)\nlet w = comptime(2 + 3)",
        .notes = "Compile-time evaluation of pure constant expressions and comptime functions. Loops and recursion are supported with fixed bounds; I/O and runtime values are not.",
        .example =
        \\comptime fn fib(n: i64) -> i64 {
        \\    if n <= 1 {
        \\        return n
        \\    }
        \\    return fib(n - 1) + fib(n - 2)
        \\}
        \\
        \\const TENTH = fib(10)
        \\
        \\fn main() -> i64 {
        \\    return TENTH
        \\}
        ,
    },
    .{
        .name = "pipe_operator",
        .category = .expression,
        .status = .unsupported,
        .syntax = "value |> f",
        .notes = "Rejected: the right-hand side of '|>' must be a call, and plain values are not callable.",
        .avoid = "5 |> 3   |   x |> f(...)  (supply the receiver explicitly)",
    },
    .{
        .name = "async_await",
        .category = .expression,
        .status = .unsupported,
        .syntax = "async fn f() -> T   let v = await g()",
        .notes = "No async runtime. Use OS threads (spawn/@thread_create) and channels (@chan_*) instead.",
        .avoid = "async fn / await",
    },

    // ── Types ──────────────────────────────────────────────────────────────
    .{
        .name = "integer_types",
        .category = .type_syntax,
        .status = .supported,
        .syntax = "i8 i16 i32 i64 u8 u16 u32 u64 isize usize",
        .notes = "All are 8-byte slots internally; annotations drive signedness/width checks and casts. i128/u128/i54-style widths do not exist.",
        .example =
        \\fn main() -> i64 {
        \\    let a: u8 = 200
        \\    let b: i32 = -5
        \\    let c: usize = 3
        \\    return (a as i64) + (b as i64) + (c as i64)
        \\}
        ,
        .avoid = "i128 / u128",
    },
    .{
        .name = "float_types",
        .category = .type_syntax,
        .status = .partial,
        .syntax = "f64   f32",
        .notes = "Arithmetic, comparisons and casting work; float literal values are stored as binary64 and 'f32' annotations accept float literals only through arithmetic contexts (a bare integer literal is not a float). Floats print with printFloat/printlnFloat.",
        .example =
        \\fn main() -> i64 {
        \\    let a = 1.5
        \\    let b = 2.5
        \\    printFloat(a + b)
        \\    return 0
        \\}
        ,
        .avoid = "let a: f64 = 1   (use 1.0)",
    },
    .{
        .name = "void_never",
        .category = .type_syntax,
        .status = .supported,
        .syntax = "fn f() { }          fn g() -> never { exit(1) }",
        .notes = "A function without '-> T' returns void. 'never' marks functions that do not return normally (exit/panic).",
        .example =
        \\fn log() {
        \\    println("log")
        \\}
        \\
        \\fn stop() -> never {
        \\    exit(3)
        \\}
        \\
        \\fn main() -> i64 {
        \\    log()
        \\    return 0
        \\}
        ,
    },
    .{
        .name = "bool_type",
        .category = .type_syntax,
        .status = .supported,
        .syntax = "true   false   let flag: bool = true",
        .notes = "A bool is a distinct type; it does not implicitly convert to i64. Use (a and b), comparisons, or @signum for arithmetic keys.",
        .example =
        \\fn main() -> i64 {
        \\    let flag: bool = 3 < 4
        \\    if flag {
        \\        return 1
        \\    }
        \\    return 0
        \\}
        ,
        .avoid = "let n: i64 = true  |  printInt(true)",
    },

    // ── Attributes ─────────────────────────────────────────────────────────
    .{
        .name = "attr_test",
        .category = .attribute,
        .status = .supported,
        .syntax = "#[test]\nfn t() { @assert_eq(1, 1) }",
        .notes = "Marks a test function collected by 'lir test'. Test functions take no parameters and do not need main.",
        .example =
        \\#[test]
        \\fn adds() {
        \\    @assert_eq(2 + 2, 4)
        \\}
        ,
    },
    .{
        .name = "attr_inline",
        .category = .attribute,
        .status = .supported,
        .syntax = "#[inline]",
        .notes = "Inline hint for the optimizer. #[cold] is the inverse hint.",
        .example =
        \\#[inline]
        \\fn fast(x: i64) -> i64 {
        \\    return x * 2
        \\}
        \\
        \\fn main() -> i64 {
        \\    return fast(3)
        \\}
        ,
    },
    .{
        .name = "attr_cold",
        .category = .attribute,
        .status = .supported,
        .syntax = "#[cold]",
        .notes = "Marks a rarely executed function so hot paths stay compact.",
        .example =
        \\#[cold]
        \\fn fail() -> i64 {
        \\    return -1
        \\}
        \\
        \\fn main() -> i64 {
        \\    return fail() + 1
        \\}
        ,
    },
    .{
        .name = "attr_pure",
        .category = .attribute,
        .status = .supported,
        .syntax = "#[pure]\nfn f(x: i64) -> i64 { ... }",
        .notes = "Declares a function free of side effects. Calling a printing/allocating builtin inside a pure function is rejected, which lets the optimizer CSE identical calls.",
        .example =
        \\#[pure]
        \\fn square(x: i64) -> i64 {
        \\    return x * x
        \\}
        \\
        \\fn main() -> i64 {
        \\    return square(7)
        \\}
        ,
        .avoid = "println(...) inside a #[pure] function",
    },
    .{
        .name = "attr_pre",
        .category = .attribute,
        .status = .supported,
        .syntax = "#[pre(condition)]\n#[post(condition)]",
        .notes = "Hoare-style contract checked at compile time when arguments are constant (a statically violated call fails with 'precondition violation'), otherwise as a runtime assertion.",
        .example =
        \\#[pre(b != 0)]
        \\fn divide(a: i64, b: i64) -> i64 {
        \\    return a / b
        \\}
        \\
        \\fn main() -> i64 {
        \\    return divide(9, 3)
        \\}
        ,
        .avoid = "requires/ensures keywords  (use #[pre]/#[post])",
    },
};

// ════════════════════════════════════════════════════════════════════════════
// BUILTINS
// ════════════════════════════════════════════════════════════════════════════

pub const Builtin = struct {
    name: []const u8,
    /// True for keyword spellings (`panic`) that are lowered to a `@builtin`
    /// before semantic analysis, so they are not in the sema builtin table.
    keyword_form: bool = false,
    /// True for functions provided by an embedded std module (after `import`),
    /// not by the sema builtin table.
    library_form: bool = false,
    /// Canonical signature with return type.
    signature: []const u8,
    /// One-line behaviour summary; mentions traps where relevant.
    summary: []const u8,
    /// Group used for filtering and docs sections.
    group: []const u8,
};

pub const builtins = [_]Builtin{
    // integer intrinsics
    .{ .name = "@rotl", .signature = "@rotl(i64, i64) -> i64", .summary = "Rotate the 64-bit pattern left by count&63.", .group = "int" },
    .{ .name = "@rotr", .signature = "@rotr(i64, i64) -> i64", .summary = "Rotate the 64-bit pattern right by count&63.", .group = "int" },
    .{ .name = "@bit_reverse", .signature = "@bit_reverse(i64) -> i64", .summary = "Reverse all 64 bits.", .group = "int" },
    .{ .name = "@is_power_of_two", .signature = "@is_power_of_two(i64) -> bool", .summary = "True only for positive powers of two.", .group = "int" },
    .{ .name = "@signum", .signature = "@signum(i64) -> i64", .summary = "-1, 0 or 1 according to the signed value.", .group = "int" },
    .{ .name = "@wrapping_add", .signature = "@wrapping_add(i64, i64) -> i64", .summary = "Sum modulo 2^64 (never traps).", .group = "int" },
    .{ .name = "@wrapping_sub", .signature = "@wrapping_sub(i64, i64) -> i64", .summary = "Difference modulo 2^64 (never traps).", .group = "int" },
    .{ .name = "@wrapping_mul", .signature = "@wrapping_mul(i64, i64) -> i64", .summary = "Product modulo 2^64 (never traps).", .group = "int" },
    .{ .name = "@checked_add", .signature = "@checked_add(i64, i64) -> i64", .summary = "Addition that traps on signed overflow.", .group = "int" },
    .{ .name = "@checked_sub", .signature = "@checked_sub(i64, i64) -> i64", .summary = "Subtraction that traps on signed overflow.", .group = "int" },
    .{ .name = "@checked_mul", .signature = "@checked_mul(i64, i64) -> i64", .summary = "Multiplication that traps on signed overflow.", .group = "int" },
    .{ .name = "@popcount", .signature = "@popcount(i64) -> i64", .summary = "Number of set bits.", .group = "int" },
    .{ .name = "@clz", .signature = "@clz(i64) -> i64", .summary = "Count of leading zero bits.", .group = "int" },
    .{ .name = "@ctz", .signature = "@ctz(i64) -> i64", .summary = "Count of trailing zero bits.", .group = "int" },
    .{ .name = "@bswap", .signature = "@bswap(i64) -> i64", .summary = "Byte-swap the 64-bit value.", .group = "int" },
    .{ .name = "@min", .signature = "@min(a, b) -> T", .summary = "Smaller of two orderable values; result type follows the arguments.", .group = "math" },
    .{ .name = "@max", .signature = "@max(a, b) -> T", .summary = "Larger of two orderable values.", .group = "math" },
    .{ .name = "@clamp", .signature = "@clamp(v, lo, hi) -> T", .summary = "Clamp v into [lo, hi].", .group = "math" },
    // floating point
    .{ .name = "@sqrt", .signature = "@sqrt(f64) -> f64", .summary = "Square root.", .group = "math" },
    .{ .name = "@fabs", .signature = "@fabs(f64) -> f64", .summary = "Absolute value.", .group = "math" },
    .{ .name = "@floor", .signature = "@floor(f64) -> f64", .summary = "Round toward negative infinity.", .group = "math" },
    .{ .name = "@ceil", .signature = "@ceil(f64) -> f64", .summary = "Round toward positive infinity.", .group = "math" },
    .{ .name = "@round", .signature = "@round(f64) -> f64", .summary = "Round to nearest.", .group = "math" },
    .{ .name = "@sin", .signature = "@sin(f64) -> f64", .summary = "Sine (radians).", .group = "math" },
    .{ .name = "@cos", .signature = "@cos(f64) -> f64", .summary = "Cosine (radians).", .group = "math" },
    .{ .name = "@float_to_string", .signature = "@float_to_string(f64) -> string", .summary = "Format a float as a heap string.", .group = "math" },
    .{ .name = "@string_to_float", .signature = "@string_to_float(string) -> f64", .summary = "Parse a float; 0.0 on failure.", .group = "math" },
    // printing
    .{ .name = "print", .signature = "print(string) -> void", .summary = "Write a string to stdout without a newline. Numbers need printInt/printFloat.", .group = "io" },
    .{ .name = "println", .signature = "println(string) -> void", .summary = "Write a string plus a newline.", .group = "io" },
    .{ .name = "printInt", .signature = "printInt(i64) -> void", .summary = "Print a signed integer without a newline.", .group = "io" },
    .{ .name = "printFloat", .signature = "printFloat(f64) -> void", .summary = "Print a float without a newline.", .group = "io" },
    .{ .name = "printlnFloat", .signature = "printlnFloat(f64) -> void", .summary = "Print a float plus a newline.", .group = "io" },
    // process
    .{ .name = "exit", .signature = "exit(i64) -> never", .summary = "Terminate the process with the given status.", .group = "process" },
    .{ .name = "@exit", .signature = "@exit(i64) -> never", .summary = "Alias of exit.", .group = "process" },
    .{ .name = "panic", .signature = "panic(string) -> never", .summary = "Keyword form: print the message to stderr and trap (SIGILL on native). Lowered to @panic.", .group = "process", .keyword_form = true },
    .{ .name = "assertEq", .signature = "assertEq(a, b) -> void", .summary = "Alias of @assert_eq from the embedded module 'testing' (assertEqStr/assertEqFloat also exist). Requires 'import testing'.", .group = "testing", .library_form = true },
    .{ .name = "@panic", .signature = "@panic(string) -> never", .summary = "Alias of panic.", .group = "process" },
    .{ .name = "@assert", .signature = "@assert(bool) -> void", .summary = "Trap with 'assertion failed' when the condition is false.", .group = "testing" },
    .{ .name = "@assert_eq", .signature = "@assert_eq(T, T) -> void", .summary = "Trap when the two values differ.", .group = "testing" },
    .{ .name = "@argc", .signature = "@argc() -> i64", .summary = "Program argument count (argument 0 is the program path).", .group = "process" },
    .{ .name = "@argv", .signature = "@argv(i64) -> string", .summary = "Program argument at index; traps when out of range.", .group = "process" },
    .{ .name = "@getenv", .signature = "@getenv(string) -> string", .summary = "Environment variable value, or \"\" when unset.", .group = "process" },
    .{ .name = "@getpid", .signature = "@getpid() -> i64", .summary = "Current process id.", .group = "process" },
    .{ .name = "@getppid", .signature = "@getppid() -> i64", .summary = "Parent process id.", .group = "process" },
    .{ .name = "@getuid", .signature = "@getuid() -> i64", .summary = "Current user id.", .group = "process" },
    .{ .name = "@sleep_ms", .signature = "@sleep_ms(i64) -> i64", .summary = "Sleep for the given milliseconds.", .group = "process" },
    .{ .name = "@syscall", .signature = "@syscall(nr, ...) -> i64", .summary = "Raw Linux syscall with up to 6 arguments (native ELF target only).", .group = "process" },
    .{ .name = "@time_ns", .signature = "@time_ns() -> u64", .summary = "Nanoseconds since program start.", .group = "process" },
    // memory
    .{ .name = "@malloc", .signature = "@malloc(i64) -> *u8", .summary = "Allocate zeroed heap bytes; traps on failure. Header + canary protected.", .group = "memory" },
    .{ .name = "@alloc", .signature = "@alloc(i64) -> *u8", .summary = "Alias of @malloc.", .group = "memory" },
    .{ .name = "@free", .signature = "@free(ptr) -> void", .summary = "Free heap memory; the block is zero-wiped and double-free/UAF is detected.", .group = "memory" },
    .{ .name = "@memcpy", .signature = "@memcpy(dst, src, n) -> *u8", .summary = "Copy n bytes; traps on invalid ranges.", .group = "memory" },
    .{ .name = "@memset", .signature = "@memset(dst, byte, n) -> *u8", .summary = "Fill n bytes with a value.", .group = "memory" },
    .{ .name = "@ptr_add", .signature = "@ptr_add(ptr, offset) -> *u8", .summary = "Offset a raw pointer by a byte count (the only pointer arithmetic).", .group = "memory" },
    .{ .name = "@read_byte", .signature = "@read_byte(ptr) -> i64", .summary = "Read one byte through a raw pointer.", .group = "memory" },
    .{ .name = "@write_byte", .signature = "@write_byte(ptr, v) -> void", .summary = "Write one byte through a raw pointer.", .group = "memory" },
    .{ .name = "@read_u8", .signature = "@read_u8(ptr) -> u8", .summary = "Read an unsigned byte.", .group = "memory" },
    .{ .name = "@write_u8", .signature = "@write_u8(ptr, v) -> void", .summary = "Write an unsigned byte.", .group = "memory" },
    .{ .name = "@read_u32", .signature = "@read_u32(ptr) -> u32", .summary = "Read 4 bytes little-endian.", .group = "memory" },
    .{ .name = "@write_u32", .signature = "@write_u32(ptr, v) -> void", .summary = "Write 4 bytes little-endian.", .group = "memory" },
    .{ .name = "@read_u64", .signature = "@read_u64(ptr) -> i64", .summary = "Read 8 bytes little-endian.", .group = "memory" },
    .{ .name = "@write_u64", .signature = "@write_u64(ptr, v) -> void", .summary = "Write 8 bytes little-endian.", .group = "memory" },
    .{ .name = "@secure_zero", .signature = "@secure_zero(ptr, n) -> void", .summary = "Wipe n bytes without being optimized away.", .group = "memory" },
    .{ .name = "@const_time_eq", .signature = "@const_time_eq(a, b, n) -> bool", .summary = "Constant-time comparison of n bytes (secret-safe).", .group = "memory" },
    // strings
    .{ .name = "@string_new", .signature = "@string_new(ptr, len=?) -> string", .summary = "Build a string from a buffer.", .group = "string" },
    .{ .name = "@string_len", .signature = "@string_len(string) -> i64", .summary = "Byte length (also available as s.len).", .group = "string" },
    .{ .name = "@string_concat", .signature = "@string_concat(string, string) -> string", .summary = "Heap-allocated concatenation (also 'a + b').", .group = "string" },
    .{ .name = "@string_eq", .signature = "@string_eq(string, string) -> bool", .summary = "Content equality (also 'a == b').", .group = "string" },
    .{ .name = "@string_sub", .signature = "@string_sub(string, start, len) -> string", .summary = "Substring; traps on out-of-range slices.", .group = "string" },
    .{ .name = "@string_slice", .signature = "@string_slice(string, start, end) -> string", .summary = "Substring by end index.", .group = "string" },
    .{ .name = "@string_char_at", .signature = "@string_char_at(string, i) -> i64", .summary = "Byte value at index i; traps when out of range.", .group = "string" },
    .{ .name = "@string_split", .signature = "@string_split(string, sep) -> []string", .summary = "Split into a dynamic array of substrings.", .group = "string" },
    .{ .name = "@string_to_int", .signature = "@string_to_int(string) -> i64", .summary = "Parse a decimal integer; 0 when unparseable.", .group = "string" },
    .{ .name = "@int_to_string", .signature = "@int_to_string(i64) -> string", .summary = "Format an integer as a heap string.", .group = "string" },
    // arrays
    .{ .name = "@array_new", .signature = "@array_new(capacity, elem_size=8) -> []T", .summary = "Allocate a growable heap array.", .group = "array" },
    .{ .name = "@array_push", .signature = "@array_push(array, v) -> void", .summary = "Append a value, growing the array.", .group = "array" },
    .{ .name = "@array_get", .signature = "@array_get(array, i) -> T", .summary = "Read element i; traps when out of range.", .group = "array" },
    .{ .name = "@array_set", .signature = "@array_set(array, i, v) -> i64", .summary = "Write element i; traps when out of range.", .group = "array" },
    .{ .name = "@array_len", .signature = "@array_len(array) -> i64", .summary = "Current element count.", .group = "array" },
    .{ .name = "@array_free", .signature = "@array_free(array) -> void", .summary = "Free the array buffer.", .group = "array" },
    .{ .name = "@array_map", .signature = "@array_map(array, fn) -> []T", .summary = "Apply a function to every element into a new array.", .group = "array" },
    .{ .name = "@array_filter", .signature = "@array_filter(array, fn) -> []T", .summary = "Keep elements whose predicate returns non-zero.", .group = "array" },
    .{ .name = "@array_reduce", .signature = "@array_reduce(array, fn, init) -> T", .summary = "Fold the array into a single value.", .group = "array" },
    // maps / channels
    .{ .name = "@map_new", .signature = "@map_new(kind=0) -> map", .summary = "Create a hash map (i64 keys, or string keys with kind=1).", .group = "collection" },
    .{ .name = "@map_set", .signature = "@map_set(map, key, v) -> void", .summary = "Insert or overwrite a key.", .group = "collection" },
    .{ .name = "@map_get", .signature = "@map_get(map, key) -> i64", .summary = "Value for a key, or 0 when absent (check @map_has).", .group = "collection" },
    .{ .name = "@map_has", .signature = "@map_has(map, key) -> bool", .summary = "Key membership test.", .group = "collection" },
    .{ .name = "@map_del", .signature = "@map_del(map, key) -> bool", .summary = "Remove a key; true when it existed.", .group = "collection" },
    .{ .name = "@map_len", .signature = "@map_len(map) -> i64", .summary = "Number of stored keys.", .group = "collection" },
    .{ .name = "@map_free", .signature = "@map_free(map) -> void", .summary = "Free the map.", .group = "collection" },
    .{ .name = "@chan_new", .signature = "@chan_new(capacity=16) -> chan", .summary = "Create a bounded MPMC channel. Host targets only (wasm32-wasi: LIR-E7004).", .group = "concurrency" },
    .{ .name = "@chan_send", .signature = "@chan_send(chan, v) -> void", .summary = "Send a value (blocks when full).", .group = "concurrency" },
    .{ .name = "@chan_recv", .signature = "@chan_recv(chan) -> i64", .summary = "Receive a value (blocks when empty).", .group = "concurrency" },
    .{ .name = "@chan_close", .signature = "@chan_close(chan) -> void", .summary = "Close the channel.", .group = "concurrency" },
    .{ .name = "@thread_create", .signature = "@thread_create(fn, arg) -> i64", .summary = "Start an OS thread running fn(arg); returns a handle. Host targets only (wasm32-wasi: LIR-E7004).", .group = "concurrency" },
    .{ .name = "@thread_join", .signature = "@thread_join(handle) -> i64", .summary = "Wait for a thread and return its result.", .group = "concurrency" },
    .{ .name = "@mutex_create", .signature = "@mutex_create() -> *mutex", .summary = "Create a mutex.", .group = "concurrency" },
    .{ .name = "@mutex_init", .signature = "@mutex_init() -> *mutex", .summary = "Alias of @mutex_create.", .group = "concurrency" },
    .{ .name = "@mutex_lock", .signature = "@mutex_lock(mutex) -> void", .summary = "Acquire the mutex.", .group = "concurrency" },
    .{ .name = "@mutex_unlock", .signature = "@mutex_unlock(mutex) -> void", .summary = "Release the mutex.", .group = "concurrency" },
    .{ .name = "@atomic_add", .signature = "@atomic_add(ptr, v) -> i64", .summary = "Atomic add; returns the previous value.", .group = "concurrency" },
    .{ .name = "@atomic_cas", .signature = "@atomic_cas(ptr, old, new) -> bool", .summary = "Compare-and-swap; true when it swapped.", .group = "concurrency" },
    // files / net
    .{ .name = "@open", .signature = "@open(path, flags, mode=0) -> i64", .summary = "Open a file descriptor (-1 on failure).", .group = "io" },
    .{ .name = "@read", .signature = "@read(fd, buf, n) -> i64", .summary = "Read up to n bytes into a buffer.", .group = "io" },
    .{ .name = "@write", .signature = "@write(fd, buf, n) -> i64", .summary = "Write n bytes from a buffer.", .group = "io" },
    .{ .name = "@pread", .signature = "@pread(fd, buf, n, offset) -> i64", .summary = "Positional read of n bytes at offset; stateless and thread-safe (does not move the shared file offset). O(1) in offset.", .group = "io" },
    .{ .name = "@pwrite", .signature = "@pwrite(fd, buf, n, offset) -> i64", .summary = "Positional write of n bytes at offset; stateless and thread-safe. O(1) in offset.", .group = "io" },
    .{ .name = "@lseek", .signature = "@lseek(fd, offset, whence) -> i64", .summary = "Reposition file offset (whence 0=SET,1=CUR,2=END); returns the new absolute offset.", .group = "io" },
    .{ .name = "@close", .signature = "@close(fd) -> i64", .summary = "Close a file descriptor.", .group = "io" },
    .{ .name = "@unlink", .signature = "@unlink(path) -> i64", .summary = "Delete a file.", .group = "io" },
    .{ .name = "@mkdir", .signature = "@mkdir(path, mode) -> i64", .summary = "Create a directory (recursively).", .group = "io" },
    .{ .name = "@stat", .signature = "@stat(path, buf=0) -> i64", .summary = "File metadata query; -1 when missing.", .group = "io" },
    .{ .name = "@tcp_socket", .signature = "@tcp_socket() -> i64", .summary = "Create a TCP socket descriptor.", .group = "net" },
    .{ .name = "@tcp_listen", .signature = "@tcp_listen(fd, host, port) -> i64", .summary = "Bind and listen.", .group = "net" },
    .{ .name = "@tcp_accept", .signature = "@tcp_accept(fd) -> i64", .summary = "Accept a connection.", .group = "net" },
    .{ .name = "@tcp_connect", .signature = "@tcp_connect(host, port) -> i64", .summary = "Connect to a peer.", .group = "net" },
    .{ .name = "@sock_send", .signature = "@sock_send(fd, buf, n) -> i64", .summary = "Send bytes on a socket.", .group = "net" },
    .{ .name = "@sock_recv", .signature = "@sock_recv(fd, buf, n) -> i64", .summary = "Receive bytes from a socket.", .group = "net" },
    // console
    .{ .name = "term_size", .signature = "term_size() -> i32", .summary = "Terminal size packed as columns<<16|rows.", .group = "terminal" },
    .{ .name = "@term_size", .signature = "@term_size() -> i32", .summary = "Alias of term_size.", .group = "terminal" },
    .{ .name = "set_raw_mode", .signature = "set_raw_mode(i64) -> void", .summary = "Enable/disable raw TTY mode (1/0).", .group = "terminal" },
    .{ .name = "@set_raw_mode", .signature = "@set_raw_mode(i64) -> void", .summary = "Alias of set_raw_mode.", .group = "terminal" },
    .{ .name = "read_key", .signature = "read_key() -> i32", .summary = "Read a key press in raw mode.", .group = "terminal" },
    .{ .name = "@read_key", .signature = "@read_key() -> i32", .summary = "Alias of read_key.", .group = "terminal" },
    // crypto / random
    .{ .name = "@random_u64", .signature = "@random_u64() -> u64", .summary = "CSPRNG random 64-bit value.", .group = "crypto" },
    .{ .name = "@random_bytes", .signature = "@random_bytes(buf, n) -> i64", .summary = "Fill n bytes with CSPRNG output.", .group = "crypto" },
    // reflection / target
    .{ .name = "@size_of", .signature = "@size_of(T) -> i64", .summary = "Size in bytes of a type.", .group = "reflection" },
    .{ .name = "@align_of", .signature = "@align_of(T) -> i64", .summary = "Alignment of a type.", .group = "reflection" },
    .{ .name = "@type_name", .signature = "@type_name(T) -> string", .summary = "Type name as a string.", .group = "reflection" },
    .{ .name = "@target_os", .signature = "@target_os() -> i64", .summary = "Target OS id, resolved at compile time.", .group = "reflection" },
    .{ .name = "@target_arch", .signature = "@target_arch() -> i64", .summary = "Target architecture id, resolved at compile time.", .group = "reflection" },
    .{ .name = "@target_ptr_bits", .signature = "@target_ptr_bits() -> i64", .summary = "Pointer width in bits (32 or 64).", .group = "reflection" },
    // print aliases kept for symmetry with the @-prefixed family
    .{ .name = "@print", .signature = "@print(string) -> void", .summary = "Alias of print.", .group = "io" },
    .{ .name = "@println", .signature = "@println(string) -> void", .summary = "Alias of println.", .group = "io" },
};

pub fn featureByName(name: []const u8) ?*const Feature {
    for (&features) |*f| {
        if (std.mem.eql(u8, f.name, name)) return f;
    }
    return null;
}

pub fn builtinByName(name: []const u8) ?*const Builtin {
    for (&builtins) |*b| {
        if (std.mem.eql(u8, b.name, name)) return b;
    }
    return null;
}

pub fn countByStatus(status: Status) usize {
    var n: usize = 0;
    for (features) |f| {
        if (f.status == status) n += 1;
    }
    return n;
}

/// Look-up helper used by `lir explain` and by the tests that keep the
/// catalogue honest.
pub fn featureCount() usize {
    return features.len;
}
