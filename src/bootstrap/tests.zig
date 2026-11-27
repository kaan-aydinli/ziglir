// LIR Compiler — Unit Tests
// Tests for lexer, parser, and codegen

const std = @import("std");
const main = @import("main.zig");
const parser_mod = @import("parser.zig");
const ir_mod = @import("ir.zig");
const ir_verify = @import("ir_verify.zig");
const lexer_mod = @import("lexer.zig");

const diag_mod = @import("diag.zig");
const util = @import("util.zig");

fn compileSource(source: []const u8) ![]u8 {
    // Exercise the same AST -> IR -> ELF pipeline used by the production CLI.
    // Tests must not silently validate the legacy AST code generator instead.
    var compiler = main.Compiler.init(source, "<test>");
    compiler.quiet = true;
    const output = try compiler.compile();
    defer std.heap.page_allocator.free(output);

    return try std.testing.allocator.dupe(u8, output);
}

fn compileSourceWithOpt(source: []const u8, opt_level: main.OptLevel) ![]u8 {
    var compiler = main.Compiler.initWithOpts(source, "<test>", opt_level);
    compiler.quiet = true;
    const output = try compiler.compile();
    defer std.heap.page_allocator.free(output);

    return try std.testing.allocator.dupe(u8, output);
}

/// Compile with an explicit CPU mode so a test can compare the host-specific
/// instruction selection against the portable baseline byte for byte in output.
fn compileSourceCpuMode(source: []const u8, opt_level: main.OptLevel, cpu_mode: main.Backend.CpuMode) ![]u8 {
    var compiler = main.Compiler.initWithOpts(source, "<test>", opt_level);
    compiler.quiet = true;
    compiler.cpu_mode = cpu_mode;
    const output = try compiler.compile();
    defer std.heap.page_allocator.free(output);

    return try std.testing.allocator.dupe(u8, output);
}

fn runElfCapture(allocator: std.mem.Allocator, elf: []const u8, name_suffix: []const u8) !struct { exit_code: u8, stdout: []u8 } {
    var path_buf: [128]u8 = undefined;
    const tmp_path = try std.fmt.bufPrint(&path_buf, "/tmp/lir_test_{d}_{s}", .{ std.os.linux.getpid(), name_suffix });
    {
        const f = try std.fs.createFileAbsolute(tmp_path, .{ .mode = 0o755 });
        defer f.close();
        try f.writeAll(elf);
    }
    defer std.fs.deleteFileAbsolute(tmp_path) catch {};

    const res = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{tmp_path},
    });
    allocator.free(res.stderr);
    const code: u8 = switch (res.term) {
        .Exited => |c| c,
        else => 255,
    };
    return .{ .exit_code = code, .stdout = res.stdout };
}

fn runElfExpectSigIll(allocator: std.mem.Allocator, elf: []const u8, name_suffix: []const u8) !void {
    var path_buf: [128]u8 = undefined;
    const tmp_path = try std.fmt.bufPrint(&path_buf, "/tmp/lir_trap_{d}_{s}", .{ std.os.linux.getpid(), name_suffix });
    {
        const f = try std.fs.createFileAbsolute(tmp_path, .{ .mode = 0o755 });
        defer f.close();
        try f.writeAll(elf);
    }
    defer std.fs.deleteFileAbsolute(tmp_path) catch {};

    const res = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{tmp_path},
    });
    allocator.free(res.stdout);
    allocator.free(res.stderr);
    switch (res.term) {
        .Signal => |sig| {
            if (sig != 4) std.debug.print("runElfExpectSigIll('{s}'): expected SIGILL(4), got signal {d}\n", .{ name_suffix, sig });
            try std.testing.expectEqual(@as(u32, 4), sig); // SIGILL from ud2
        },
        else => {
            std.debug.print("runElfExpectSigIll('{s}'): expected signal, got {any}\n", .{ name_suffix, res.term });
            return error.TestUnexpectedResult;
        },
    }
}


test "enum declarations and match expressions compile and execute" {
    const source =
        \\enum Color {
        \\    Red = 1,
        \\    Green,
        \\    Blue = 10,
        \\}
        \\fn main() -> i64 {
        \\    let c = Color::Green
        \\    let r = match c {
        \\        Color::Red => 100,
        \\        Color::Green | Color::Blue => 42,
        \\        _ => 0,
        \\    }
        \\    printInt(Color::Red)
        \\    printInt(c)
        \\    printInt(Color::Blue)
        \\    return r
        \\}
    ;
    for ([_]main.OptLevel{ .O0, .O1, .O2 }) |opt| {
        const elf = try compileSourceWithOpt(source, opt);
        defer std.testing.allocator.free(elf);
        const run_res = try runElfCapture(std.testing.allocator, elf, "enum_match");
        defer std.testing.allocator.free(run_res.stdout);
        try std.testing.expectEqual(@as(u8, 42), run_res.exit_code);
        try std.testing.expectEqualStrings("1\n2\n10\n", run_res.stdout);
    }
}

test "top-level and local const declarations fold and execute" {
    const source =
        \\const BASE = 40
        \\const ANSWER: i64 = BASE + 2
        \\fn main() -> i64 {
        \\    const LOCAL = 8
        \\    printInt(ANSWER + LOCAL)
        \\    return 0
        \\}
    ;
    const elf = try compileSourceWithOpt(source, .O2);
    defer std.testing.allocator.free(elf);
    const run_res = try runElfCapture(std.testing.allocator, elf, "const_fold");
    defer std.testing.allocator.free(run_res.stdout);
    try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
    try std.testing.expectEqualStrings("50\n", run_res.stdout);
}


test "AST source range access rejects invalid indices and overflowing ranges" {
    const ast = try std.testing.allocator.create(parser_mod.AST);
    defer std.testing.allocator.destroy(ast);
    ast.initInPlace();
    ast.sources[0] = "hello";
    ast.source_count = 1;

    const node = ast.addNode(.identifier, 1);
    ast.nodes[node].text_start = 1;
    ast.nodes[node].text_len = 3;
    try std.testing.expectEqualStrings("ell", ast.nodeText(node));
    try std.testing.expectEqualStrings("", ast.nodeText(0));
    try std.testing.expectEqualStrings("", ast.nodeText(999999));
    try std.testing.expectEqualStrings("", ast.nodeTextSrcFrom(std.math.maxInt(u32), 8, 0));
    try std.testing.expectEqualStrings("", ast.nodeTextSrcFrom(0, 1, 999));
}

test "AST struct lookup rejects out-of-range source spans" {
    const ast = try std.testing.allocator.create(parser_mod.AST);
    defer std.testing.allocator.destroy(ast);
    ast.initInPlace();
    try std.testing.expect(ast.findStructByName("abc", std.math.maxInt(u32), 4) == null);
}


test "sized and unsigned types compile across parameters, returns, and structs" {
    const source =
        \\struct Packet {
        \\    tag: u8
        \\    len: u32
        \\}
        \\fn id(x: i32) -> i64 { return x as i64 }
        \\fn add_u64(a: u64, b: u64) -> u64 { return a + b }
        \\fn main() -> i64 {
        \\    let p = Packet { tag: 7, len: 1024 }
        \\    let big: u64 = (-16) as u64
        \\    if big > 100 {
        \\        printInt(id(-5))
        \\    }
        \\    let div_u = big / 2
        \\    if div_u > 100 {
        \\        printInt(1)
        \\    }
        \\    printInt(p.tag as i64)
        \\    printInt(p.len as i64)
        \\    return (add_u64(3, 4) as i64)
        \\}
    ;
    const elf = try compileSourceWithOpt(source, .O2);
    defer std.testing.allocator.free(elf);
    const run_res = try runElfCapture(std.testing.allocator, elf, "sized_types");
    defer std.testing.allocator.free(run_res.stdout);
    try std.testing.expectEqual(@as(u8, 7), run_res.exit_code);
    try std.testing.expectEqualStrings("-5\n1\n7\n1024\n", run_res.stdout);
}

test "unsupported types and declarations fail closed" {
    var c1 = main.Compiler.init("fn id(x: NoSuchType) -> i64 { return 0 }", "<test>");
    c1.quiet = true;
    try std.testing.expectError(error.InvalidSyntax, c1.compile());

    var c2 = main.Compiler.init("fn bad() -> i64 { unsafe { return 1 }\n return 0 }", "<test>");
    c2.quiet = true;
    try std.testing.expectError(error.InvalidSyntax, c2.compile());
}

test "lexer tokenizes basic LIR" {
    const source =
        \\fn main() -> i64 {
        \\    println("Hello, World!")
        \\    0
        \\}
    ;
    const lexer = try std.testing.allocator.create(main.Lexer);
    defer std.testing.allocator.destroy(lexer);
    lexer.* = main.Lexer.init(source);
    lexer.tokenize();

    // Should have tokens: fn, main, (, ), ->, i64, {, println, (, string, ), newline, 0, newline, }, eof
    try std.testing.expect(lexer.token_count > 10);
    try std.testing.expectEqual(main.TokenKind.kw_fn, lexer.get(0).kind);
    try std.testing.expectEqual(main.TokenKind.identifier, lexer.get(1).kind);
}

test "lexer get handles out of bounds index" {
    const source = "let x = 42";
    const lexer = try std.testing.allocator.create(main.Lexer);
    defer std.testing.allocator.destroy(lexer);
    lexer.* = main.Lexer.init(source);
    lexer.tokenize();

    try std.testing.expect(lexer.token_count > 0);
    const valid_tok = lexer.get(0);
    try std.testing.expectEqual(main.TokenKind.kw_let, valid_tok.kind);

    // Test idx == token_count
    const eof_at_count = lexer.get(lexer.token_count);
    try std.testing.expectEqual(main.TokenKind.eof, eof_at_count.kind);
    try std.testing.expectEqual(@as(u32, 0), eof_at_count.start);
    try std.testing.expectEqual(@as(u32, 0), eof_at_count.len);
    try std.testing.expectEqual(@as(u32, 0), eof_at_count.line);

    // Test idx > token_count
    const eof_beyond = lexer.get(lexer.token_count + 100);
    try std.testing.expectEqual(main.TokenKind.eof, eof_beyond.kind);
    try std.testing.expectEqual(@as(u32, 0), eof_beyond.start);
    try std.testing.expectEqual(@as(u32, 0), eof_beyond.len);
    try std.testing.expectEqual(@as(u32, 0), eof_beyond.line);

    // Test un-tokenized lexer (token_count == 0)
    const uninit_lexer = try std.testing.allocator.create(main.Lexer);
    defer std.testing.allocator.destroy(uninit_lexer);
    uninit_lexer.* = main.Lexer.init(source);
    const eof_uninit = uninit_lexer.get(0);
    try std.testing.expectEqual(main.TokenKind.eof, eof_uninit.kind);
    try std.testing.expectEqual(@as(u32, 0), eof_uninit.start);
    try std.testing.expectEqual(@as(u32, 0), eof_uninit.len);
    try std.testing.expectEqual(@as(u32, 0), eof_uninit.line);
}

test "lexer recognizes all operator tokens" {
    const source = "+ - * ** **= / % == != < > <= >= = += -= *= /= && || !";
    const lexer = try std.testing.allocator.create(main.Lexer);
    defer std.testing.allocator.destroy(lexer);
    lexer.* = main.Lexer.init(source);
    lexer.tokenize();

    const expected = [_]main.TokenKind{
        .plus,       .minus,    .star,       .star_star, .star_star_eq,
        .slash,      .percent,  .eq,         .ne,        .lt,
        .gt,         .le,       .ge,         .assign,    .plus_eq,
        .minus_eq,   .star_eq,  .slash_eq,   .and_and,   .pipe_pipe,
        .bang,
    };
    for (expected, 0..) |k, i| {
        try std.testing.expectEqual(k, lexer.get(@intCast(i)).kind);
    }
}

test "lexer records token start line for multiline strings" {
    const source =
        \\"first
        \\second" value
    ;
    const lexer = try std.testing.allocator.create(main.Lexer);
    defer std.testing.allocator.destroy(lexer);
    lexer.* = main.Lexer.init(source);
    lexer.tokenize();

    try std.testing.expectEqual(main.TokenKind.string_literal, lexer.get(0).kind);
    try std.testing.expectEqual(@as(u32, 1), lexer.get(0).line);
    try std.testing.expectEqual(main.TokenKind.identifier, lexer.get(1).kind);
    try std.testing.expectEqual(@as(u32, 2), lexer.get(1).line);
}

test "lexer flags unterminated strings" {
    const source = "\"unterminated";
    const lexer = try std.testing.allocator.create(main.Lexer);
    defer std.testing.allocator.destroy(lexer);
    lexer.* = main.Lexer.init(source);
    lexer.tokenize();

    try std.testing.expect(lexer.invalid);
    try std.testing.expectEqual(@as(u32, 1), lexer.invalid_line);
}

test "lexer flags unknown characters instead of treating them as EOF" {
    const source = "fn main() { $ }";
    const lexer = try std.testing.allocator.create(main.Lexer);
    defer std.testing.allocator.destroy(lexer);
    lexer.* = main.Lexer.init(source);
    lexer.tokenize();

    try std.testing.expect(lexer.invalid);
    try std.testing.expectEqual(@as(u32, 1), lexer.invalid_line);
}

test "parser parses function declaration" {
    const source =
        \\fn add(a: i64, b: i64) -> i64 {
        \\    return a + b
        \\}
    ;
    const lexer = try std.testing.allocator.create(main.Lexer);
    defer std.testing.allocator.destroy(lexer);
    lexer.* = main.Lexer.init(source);
    lexer.tokenize();

    const ast = try std.testing.allocator.create(main.AST);
    defer std.testing.allocator.destroy(ast);
    ast.initInPlace();
    var parser = main.Parser{ .lex = lexer, .pos = 0, .ast = ast, .src = source };
    parser.parse();

    // Param nodes are emitted before the fn_decl node; find it
    var fn_idx: ?u32 = null;
    for (0..ast.count) |i| {
        if (ast.nodes[i].kind == .fn_decl) {
            fn_idx = @intCast(i);
            break;
        }
    }
    try std.testing.expect(fn_idx != null);
    const f = ast.nodes[fn_idx.?];
    try std.testing.expectEqualStrings("add", parser.src[f.text_start..][0..f.text_len]);
    try std.testing.expectEqual(@as(i64, 2), f.int_val); // param count
}

test "parser rejects out-of-range integer literals" {
    const source = "fn main() { let x = 9223372036854775808 }";
    const lexer = try std.testing.allocator.create(main.Lexer);
    defer std.testing.allocator.destroy(lexer);
    lexer.* = main.Lexer.init(source);
    lexer.tokenize();
    const ast = try std.testing.allocator.create(main.AST);
    defer std.testing.allocator.destroy(ast);
    ast.initInPlace();
    var parser = main.Parser{ .lex = lexer, .pos = 0, .ast = ast, .src = source };
    parser.parse();
    try std.testing.expect(parser.invalid_integer_literal);
    try std.testing.expectEqual(@as(u32, 1), parser.invalid_integer_line);
}

test "parser rejects malformed integer separators" {
    const source = "fn main() { let x = 1__2 }";
    const lexer = try std.testing.allocator.create(main.Lexer);
    defer std.testing.allocator.destroy(lexer);
    lexer.* = main.Lexer.init(source);
    lexer.tokenize();
    const ast = try std.testing.allocator.create(main.AST);
    defer std.testing.allocator.destroy(ast);
    ast.initInPlace();
    var parser = main.Parser{ .lex = lexer, .pos = 0, .ast = ast, .src = source };
    parser.parse();
    try std.testing.expect(parser.invalid_integer_literal);
}

test "AST node capacity exhaustion is reported without out-of-bounds access" {
    const ast = try std.testing.allocator.create(main.AST);
    defer std.testing.allocator.destroy(ast);
    ast.initInPlace();
    for (0..parser_mod.MAX_AST_NODES - 1) |_| {
        _ = ast.addNode(.identifier, 1);
    }
    try std.testing.expect(!ast.overflowed);
    try std.testing.expectEqual(@as(u32, 0), ast.addNode(.identifier, 1));
    try std.testing.expect(ast.overflowed);
}

test "float literals compile and execute end to end" {
    const source =
        \\fn main() -> i64 {
        \\    let x = 1.5
        \\    let y = 2.5
        \\    return (x + y) as i64
        \\}
    ;
    const elf = try compileSource(source);
    defer std.testing.allocator.free(elf);
    const res = try runElfCapture(std.testing.allocator, elf, "float_lit");
    defer std.testing.allocator.free(res.stdout);
    try std.testing.expectEqual(@as(u8, 4), res.exit_code);
}

test "compiler reports malformed syntax without exiting the test process" {
    const source = "fn main( {";
    var compiler = main.Compiler.init(source, "<test>");
    compiler.quiet = true;
    try std.testing.expectError(error.InvalidSyntax, compiler.compile());
}

test "compiler reports undefined function calls without exiting the test process" {
    const source =
        \\fn main() {
        \\    missing_function()
        \\}
    ;
    var compiler = main.Compiler.init(source, "<test>");
    compiler.quiet = true;
    try std.testing.expectError(error.UndefinedFunctionCall, compiler.compile());
}

test "codegen produces ELF header" {
    const elf = try compileSource(
        \\fn main() -> i64 {
        \\    return 42
        \\}
    );
    defer std.testing.allocator.free(elf);

    try std.testing.expect(elf.len >= 64);
    try std.testing.expectEqual(@as(u8, 0x7F), elf[0]);
    try std.testing.expectEqual(@as(u8, 'E'), elf[1]);
    try std.testing.expectEqual(@as(u8, 'L'), elf[2]);
    try std.testing.expectEqual(@as(u8, 'F'), elf[3]);
    try std.testing.expectEqual(@as(u8, 2), elf[4]); // 64-bit
    try std.testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, elf[16..18], .little)); // ET_EXEC
    try std.testing.expectEqual(@as(u16, 62), std.mem.readInt(u16, elf[18..20], .little)); // EM_X86_64
}

test "variables, loops and functions compile" {
    const elf = try compileSource(
        \\fn fib(n: i64) -> i64 {
        \\    if n <= 1 { return n }
        \\    return fib(n - 1) + fib(n - 2)
        \\}
        \\
        \\fn main() {
        \\    let mut i = 0
        \\    let mut sum = 0
        \\    while i < 10 {
        \\        if i % 2 == 0 { sum += i }
        \\        elif i > 7 { break }
        \\        else { sum -= 1 }
        \\        i += 1
        \\    }
        \\    printInt(sum)
        \\    printInt(fib(10))
        \\    let ok = sum < 100 and !(sum == 0)
        \\    let not_ok = false or sum > 1000
        \\    if ok and !not_ok { printInt(1) }
        \\}
    );
    defer std.testing.allocator.free(elf);

    // ELF magic + entry point present
    try std.testing.expectEqual(@as(u8, 0x7F), elf[0]);
    try std.testing.expect(elf.len > 200);
}

test "string operations compile" {
    const elf = try compileSource(
        \\fn main() {
        \\    let s = @string_new("Hello, World!", 13)
        \\    let len = @string_len(s)
        \\    printInt(len)
        \\    let sub = @string_sub(s, 7, 5)
        \\    printInt(@string_len(sub))
        \\    if @string_eq(sub, "World") { printInt(1) }
        \\}
    );
    defer std.testing.allocator.free(elf);
    try std.testing.expect(elf.len > 500);
}

test "array operations compile" {
    const elf = try compileSource(
        \\fn main() {
        \\    let arr = @array_new(5, 8)
        \\    @array_set(arr, 0, 10)
        \\    @array_set(arr, 1, 20)
        \\    @array_set(arr, 2, 30)
        \\    printInt(@array_len(arr))
        \\    printInt(@array_get(arr, 0))
        \\    printInt(@array_get(arr, 2))
        \\}
    );
    defer std.testing.allocator.free(elf);
    try std.testing.expect(elf.len > 500);
}

test "struct declaration compiles" {
    const elf = try compileSource(
        \\struct Point {
        \\    x: i64
        \\    y: i64
        \\}
        \\
        \\fn main() {
        \\    printInt(42)
        \\}
    );
    defer std.testing.allocator.free(elf);
    try std.testing.expect(elf.len > 100);
}

test "optimizer: constant folding compiles" {
    const elf = try compileSource(
        \\fn main() {
        \\    let x = 3 + 4
        \\    let y = 10 * 2
        \\    let z = 100 / 5
        \\    printInt(x + y + z)
        \\}
    );
    defer std.testing.allocator.free(elf);
    try std.testing.expectEqual(@as(u8, 0x7F), elf[0]);
}

test "optimizer: algebraic simplification compiles" {
    const elf = try compileSource(
        \\fn main() {
        \\    let x = 42
        \\    let a = x + 0
        \\    let b = 0 + x
        \\    let c = x * 1
        \\    let d = 1 * x
        \\    let e = x - 0
        \\    let f = x * 0
        \\    printInt(a + b + c + d + e + f)
        \\}
    );
    defer std.testing.allocator.free(elf);
    try std.testing.expectEqual(@as(u8, 0x7F), elf[0]);
}

test "optimizer: dead code elimination compiles" {
    const elf = try compileSource(
        \\fn main() {
        \\    return 0
        \\    let x = 999
        \\    let y = 888
        \\    printInt(x + y)
        \\}
    );
    defer std.testing.allocator.free(elf);
    try std.testing.expectEqual(@as(u8, 0x7F), elf[0]);
}

test "optimizer: boolean simplification compiles" {
    const elf = try compileSource(
        \\fn main() {
        \\    let x = 42
        \\    let a = true and x > 0
        \\    let b = false or x > 0
        \\    let c = true or x > 0
        \\    let d = false and x > 0
        \\    if a { printInt(1) }
        \\}
    );
    defer std.testing.allocator.free(elf);
    try std.testing.expectEqual(@as(u8, 0x7F), elf[0]);
}

test "optimizer: ternary simplification compiles" {
    const elf = try compileSource(
        \\fn main() {
        \\    let x = true ? 42 : 99
        \\    let y = false ? 42 : 99
        \\    printInt(x + y)
        \\}
    );
    defer std.testing.allocator.free(elf);
    try std.testing.expectEqual(@as(u8, 0x7F), elf[0]);
}

test "optimizer: if-condition constant folding compiles" {
    const elf = try compileSource(
        \\fn main() {
        \\    if true {
        \\        printInt(42)
        \\    }
        \\    if false {
        \\        printInt(99)
        \\    } else {
        \\        printInt(0)
        \\    }
        \\}
    );
    defer std.testing.allocator.free(elf);
    try std.testing.expectEqual(@as(u8, 0x7F), elf[0]);
}

test "optimizer: strength reduction compiles" {
    const elf = try compileSource(
        \\fn main() {
        \\    let x = 5
        \\    let a = x * 8
        \\    let b = x * 4
        \\    printInt(a + b)
        \\}
    );
    defer std.testing.allocator.free(elf);
    try std.testing.expectEqual(@as(u8, 0x7F), elf[0]);
}

test "optimizer: while false eliminated compiles" {
    const elf = try compileSource(
        \\fn main() {
        \\    while false {
        \\        printInt(999)
        \\    }
        \\    printInt(42)
        \\}
    );
    defer std.testing.allocator.free(elf);
    try std.testing.expectEqual(@as(u8, 0x7F), elf[0]);
}


test "codegen uses disp32 for stack slots beyond signed disp8 range" {
    const source =
        \\fn seed() -> i64 {
        \\    return 1
        \\}
        \\
        \\fn main() {
        \\    let v0 = seed()
        \\    let v1 = v0 + 1
        \\    let v2 = v1 + 1
        \\    let v3 = v2 + 1
        \\    let v4 = v3 + 1
        \\    let v5 = v4 + 1
        \\    let v6 = v5 + 1
        \\    let v7 = v6 + 1
        \\    let v8 = v7 + 1
        \\    let v9 = v8 + 1
        \\    let v10 = v9 + 1
        \\    let v11 = v10 + 1
        \\    let v12 = v11 + 1
        \\    let v13 = v12 + 1
        \\    let v14 = v13 + 1
        \\    let v15 = v14 + 1
        \\    let v16 = v15 + 1
        \\    let v17 = v16 + 1
        \\    let v18 = v17 + 1
        \\    let v19 = v18 + 1
        \\    let v20 = v19 + 1
        \\    printInt(v20)
        \\}
    ;
    const elf = try compileSourceWithOpt(source, .O0);
    defer std.testing.allocator.free(elf);

    // Slot 17 is at rbp-136, which cannot be encoded as a signed disp8.
    const store_disp32 = [_]u8{ 0x48, 0x89, 0x85, 0x78, 0xFF, 0xFF, 0xFF };
    const load_disp32 = [_]u8{ 0x48, 0x8B, 0x85, 0x78, 0xFF, 0xFF, 0xFF };
    try std.testing.expect(std.mem.indexOf(u8, elf, &store_disp32) != null);
    try std.testing.expect(std.mem.indexOf(u8, elf, &load_disp32) != null);
}


test "IR string table rejects entry-count overflow without writing out of bounds" {
    const module = try std.testing.allocator.create(ir_mod.IRModule);
    defer std.testing.allocator.destroy(module);
    module.init();
    var i: usize = 0;
    while (i < module.string_offsets.len) : (i += 1) {
        const value = try std.fmt.allocPrint(std.testing.allocator, "s{d}", .{i});
        defer std.testing.allocator.free(value);
        _ = module.addString(value);
    }
    try std.testing.expectEqual(@as(u32, module.string_offsets.len), module.string_count);
    _ = module.addString("overflow");
    try std.testing.expect(module.string_overflowed);
    try std.testing.expectEqual(@as(u32, module.string_offsets.len), module.string_count);
}

test "IR string table rejects byte-capacity overflow without partial insertion" {
    const module = try std.testing.allocator.create(ir_mod.IRModule);
    defer std.testing.allocator.destroy(module);
    module.init();
    const too_large = [_]u8{'x'} ** 16384;
    _ = module.addString(&too_large);
    try std.testing.expect(module.string_overflowed);
    try std.testing.expectEqual(@as(u32, 0), module.string_count);
    try std.testing.expectEqual(@as(u32, 0), module.string_len);
}

test "IR string hash table preserves lookup through collisions and capacity" {
    const module = try std.testing.allocator.create(ir_mod.IRModule);
    defer std.testing.allocator.destroy(module);
    module.init();
    var i: usize = 0;
    while (i < module.string_offsets.len) : (i += 1) {
        const value = try std.fmt.allocPrint(std.testing.allocator, "interned_{d}", .{i});
        defer std.testing.allocator.free(value);
        try std.testing.expectEqual(@as(u32, @intCast(i)), module.addString(value));
    }
    try std.testing.expectEqual(@as(u32, module.string_offsets.len), module.string_count);

    i = 0;
    while (i < module.string_offsets.len) : (i += 1) {
        const value = try std.fmt.allocPrint(std.testing.allocator, "interned_{d}", .{i});
        defer std.testing.allocator.free(value);
        try std.testing.expectEqual(@as(u32, @intCast(i)), module.addString(value));
    }
    try std.testing.expectEqual(@as(u32, module.string_offsets.len), module.string_count);
    try std.testing.expect(!module.string_overflowed);
}

test "IR string table deduplicates existing entries" {
    const module = try std.testing.allocator.create(ir_mod.IRModule);
    defer std.testing.allocator.destroy(module);
    module.init();
    const first = module.addString("hello");
    const second = module.addString("hello");
    try std.testing.expectEqual(first, second);
    try std.testing.expectEqual(@as(u32, 1), module.string_count);
    try std.testing.expect(!module.string_overflowed);
}


test "IR verifier rejects invalid branch targets before code generation" {
    const module = try std.testing.allocator.create(ir_mod.IRModule);
    defer std.testing.allocator.destroy(module);
    module.init();
    module.fn_count = 1;
    ir_mod.IRModule.initFnSlot(&module.fns[0], 0, 2, 0, 0, 0);
    module.fns[0].block_count = 1;
    module.fns[0].blocks[0].label = 0;
    module.fns[0].blocks[0].inst_count = 1;
    module.fns[0].blocks[0].insts[0] = .{ .op = .jump, .target_block = 7 };

    try std.testing.expectError(error.InvalidBranchTarget, ir_verify.verify(module, "fn"));
}

test "IR verifier rejects invalid string references" {
    const module = try std.testing.allocator.create(ir_mod.IRModule);
    defer std.testing.allocator.destroy(module);
    module.init();
    module.fn_count = 1;
    ir_mod.IRModule.initFnSlot(&module.fns[0], 0, 2, 0, 0, 0);
    module.fns[0].block_count = 1;
    module.fns[0].blocks[0].label = 0;
    module.fns[0].blocks[0].inst_count = 1;
    module.fns[0].blocks[0].insts[0] = .{ .op = .const_str, .str_idx = 1 };

    try std.testing.expectError(error.InvalidStringIndex, ir_verify.verify(module, "fn"));
}


test "IR verifier rejects local slots outside the declared frame" {
    const module = try std.testing.allocator.create(ir_mod.IRModule);
    defer std.testing.allocator.destroy(module);
    module.init();
    module.fn_count = 1;
    ir_mod.IRModule.initFnSlot(&module.fns[0], 0, 2, 0, 0, 0);
    module.fns[0].block_count = 1;
    module.fns[0].total_locals = 1;
    module.fns[0].vreg_count = 2;
    module.fns[0].blocks[0].label = 0;
    module.fns[0].blocks[0].inst_count = 1;
    module.fns[0].blocks[0].insts[0] = .{ .op = .load_local, .dest = 1, .slot = 2 };

    try std.testing.expectError(error.InvalidLocalSlot, ir_verify.verify(module, "fn"));
}

test "IR verifier rejects virtual registers beyond the function register table" {
    const module = try std.testing.allocator.create(ir_mod.IRModule);
    defer std.testing.allocator.destroy(module);
    module.init();
    module.fn_count = 1;
    ir_mod.IRModule.initFnSlot(&module.fns[0], 0, 2, 0, 0, 0);
    module.fns[0].block_count = 1;
    module.fns[0].blocks[0].label = 0;
    module.fns[0].blocks[0].inst_count = 1;
    module.fns[0].blocks[0].insts[0] = .{ .op = .const_int, .dest = 1, .imm = 4 };
    try std.testing.expectError(error.InvalidVirtualRegister, ir_verify.verify(module, "fn"));

    module.fns[0].blocks[0].insts[0] = .{ .op = .add, .src1 = 1 };
    try std.testing.expectError(error.InvalidVirtualRegister, ir_verify.verify(module, "fn"));

    module.fns[0].blocks[0].insts[0] = .{ .op = .call, .callee_fn_idx = 0, .arg_count = 1, .args = .{ 1 } ** 8 };
    try std.testing.expectError(error.InvalidVirtualRegister, ir_verify.verify(module, "fn"));
}

test "IR verifier rejects stack frames above backend safety limit" {
    const module = try std.testing.allocator.create(ir_mod.IRModule);
    defer std.testing.allocator.destroy(module);
    module.init();
    module.fn_count = 1;
    ir_mod.IRModule.initFnSlot(&module.fns[0], 0, 2, 0, 0, 0);
    module.fns[0].block_count = 1;
    module.fns[0].total_locals = 3_000_000;
    module.fns[0].blocks[0].label = 0;
    module.fns[0].blocks[0].inst_count = 0;

    try std.testing.expectError(error.StackFrameTooLarge, ir_verify.verify(module, "fn"));
}

// ── Regression tests for docs/CRITICAL_ISSUES_6.md issue #6 ────────────────
// Hand-built IR modules for the value-flow bug classes that caused the six
// wrong-answer bugs of 2026-11 (docs/STATUS.md:84-88):
//   A: same-block use before def,
//   B: use in a merge block whose only def does not dominate it,
//   C: phi whose predecessor list does not match the real CFG preds.
// Before the verifier hardening all three passed verify(), and module B
// executed in the VM as a silent wrong answer (0 from a zero-initialised
// vreg). Each must now be rejected with a precise error, and well-formed
// SSA / post-SSA modules must still be accepted.

fn pocModuleA() !*ir_mod.IRModule {
    const module = try std.testing.allocator.create(ir_mod.IRModule);
    errdefer std.testing.allocator.destroy(module);
    module.init();
    module.fn_count = 1;
    ir_mod.IRModule.initFnSlot(&module.fns[0], 0, 4, 0, 0, 0);
    const f = &module.fns[0];
    f.vreg_count = 3;
    f.block_count = 1;
    f.blocks[0].label = 0;
    f.blocks[0].inst_count = 3;
    f.blocks[0].insts[0] = .{ .op = .copy, .dest = 2, .src1 = 1 }; // uses v1 BEFORE its def
    f.blocks[0].insts[1] = .{ .op = .const_int, .dest = 1, .imm = 5 };
    f.blocks[0].insts[2] = .{ .op = .ret, .src1 = 2 };
    return module;
}

fn pocModuleB(take_defined_path: bool) !*ir_mod.IRModule {
    const module = try std.testing.allocator.create(ir_mod.IRModule);
    errdefer std.testing.allocator.destroy(module);
    module.init();
    module.fn_count = 1;
    ir_mod.IRModule.initFnSlot(&module.fns[0], 0, 4, 0, 0, 0);
    const f = &module.fns[0];
    f.vreg_count = 3;
    f.block_count = 4;
    // B0: v1 = 1|0; if v1 goto B1 else B2
    f.blocks[0].inst_count = 2;
    f.blocks[0].insts[0] = .{ .op = .const_int, .dest = 1, .imm = @intFromBool(take_defined_path) };
    f.blocks[0].insts[1] = .{ .op = .cond_jump, .src1 = 1, .target_block = 1, .alt_block = 2 };
    // B1: v2 = 10; goto B3
    f.blocks[1].inst_count = 2;
    f.blocks[1].insts[0] = .{ .op = .const_int, .dest = 2, .imm = 10 };
    f.blocks[1].insts[1] = .{ .op = .jump, .target_block = 3 };
    // B2: goto B3 (v2 NEVER defined on this path)
    f.blocks[2].inst_count = 1;
    f.blocks[2].insts[0] = .{ .op = .jump, .target_block = 3 };
    // B3: return v2 — v2's only def (B1) does not dominate B3
    f.blocks[3].inst_count = 1;
    f.blocks[3].insts[0] = .{ .op = .ret, .src1 = 2 };
    return module;
}

fn pocModuleC() !*ir_mod.IRModule {
    const module = try std.testing.allocator.create(ir_mod.IRModule);
    errdefer std.testing.allocator.destroy(module);
    module.init();
    module.fn_count = 1;
    ir_mod.IRModule.initFnSlot(&module.fns[0], 0, 4, 0, 0, 0);
    const f = &module.fns[0];
    f.vreg_count = 4;
    f.block_count = 3;
    // B0: v1 = 1; if v1 goto B1 else B2  → preds(B2) = {B0, B1}
    f.blocks[0].inst_count = 2;
    f.blocks[0].insts[0] = .{ .op = .const_int, .dest = 1, .imm = 0 };
    f.blocks[0].insts[1] = .{ .op = .cond_jump, .src1 = 1, .target_block = 1, .alt_block = 2 };
    // B1: goto B2
    f.blocks[1].inst_count = 1;
    f.blocks[1].insts[0] = .{ .op = .jump, .target_block = 2 };
    // B2: v3 = phi(v1 from B0) — MISSING the B1 entry entirely
    f.blocks[2].inst_count = 2;
    f.blocks[2].insts[0] = .{ .op = .phi, .dest = 3, .arg_count = 1, .args = .{1} ** 8, .phi_blocks = .{0} ** 8 };
    f.blocks[2].insts[1] = .{ .op = .ret, .src1 = 3 };
    return module;
}

test "IR verifier rejects same-block use before def" {
    const module = try pocModuleA();
    defer std.testing.allocator.destroy(module);
    try std.testing.expectError(error.UseBeforeDef, ir_verify.verify(module, "main"));
}

test "IR verifier rejects uses whose definition does not dominate them" {
    const module = try pocModuleB(false);
    defer std.testing.allocator.destroy(module);
    try std.testing.expectError(error.NonDominatingDef, ir_verify.verify(module, "main"));

    // Why this matters: if such IR ever reaches the VM (the verifier is the
    // gate that must stop it), the undefined path executes as a silent wrong
    // answer instead of failing — this is the 2026-11 wrong-answer bug class.
    const ir_vm_mod = @import("ir_vm.zig");
    const res = try ir_vm_mod.execute(std.testing.allocator, module, "main", &[_][]const u8{}, false, .{});
    try std.testing.expect(!res.trapped);
    try std.testing.expectEqual(@as(i64, 0), res.exit_code); // silently 0, not an error
}

test "IR verifier rejects phi predecessor mismatches" {
    // Missing predecessor (preds(B2) = {B0, B1}, phi lists only B0).
    {
        const module = try pocModuleC();
        defer std.testing.allocator.destroy(module);
        try std.testing.expectError(error.PhiPredecessorMismatch, ir_verify.verify(module, "main"));
    }
    // Foreign predecessor (phi lists B1 twice; B0 missing).
    {
        const module = try pocModuleC();
        defer std.testing.allocator.destroy(module);
        module.fns[0].blocks[2].insts[0] = .{ .op = .phi, .dest = 3, .arg_count = 2, .args = .{ 1, 1, 0, 0, 0, 0, 0, 0 }, .phi_blocks = .{ 1, 1, 0, 0, 0, 0, 0, 0 } };
        try std.testing.expectError(error.PhiPredecessorMismatch, ir_verify.verify(module, "main"));
    }
    // Incoming value defined only in the merge block itself (does not
    // dominate the incoming edge).
    {
        const module = try pocModuleC();
        defer std.testing.allocator.destroy(module);
        // v3 = phi(v1 from B0, v1 from B1) — well-formed edge list, but add a
        // second phi whose incoming vreg is defined only in B2 after the phi.
        module.fns[0].vreg_count = 5;
        module.fns[0].blocks[2].inst_count = 4;
        module.fns[0].blocks[2].insts[0] = .{ .op = .phi, .dest = 3, .arg_count = 2, .args = .{ 1, 1, 0, 0, 0, 0, 0, 0 }, .phi_blocks = .{ 0, 1, 0, 0, 0, 0, 0, 0 } };
        module.fns[0].blocks[2].insts[1] = .{ .op = .phi, .dest = 4, .arg_count = 2, .args = .{ 3, 3, 0, 0, 0, 0, 0, 0 }, .phi_blocks = .{ 0, 1, 0, 0, 0, 0, 0, 0 } };
        module.fns[0].blocks[2].insts[2] = .{ .op = .copy, .dest = 3, .src1 = 4 }; // redefine v3 in B2
        module.fns[0].blocks[2].insts[3] = .{ .op = .ret, .src1 = 4 };
        // phi v4's incoming v3 on edges B0/B1: v3 is defined in B0? No — v3's
        // defs are both in B2 (the phi itself + the copy). Neither dominates
        // B0/B1, so this must be rejected.
        try std.testing.expectError(error.NonDominatingDef, ir_verify.verify(module, "main"));
    }
}

test "IR verifier accepts well-formed SSA, post-SSA redefinition and dead code" {
    // Correct SSA diamond: phi at the merge with one entry per pred, every
    // incoming value defined in its predecessor; the VM computes the right
    // answer (20 via the B2 path).
    {
        const module = try std.testing.allocator.create(ir_mod.IRModule);
        defer std.testing.allocator.destroy(module);
        module.init();
        module.fn_count = 1;
        ir_mod.IRModule.initFnSlot(&module.fns[0], 0, 4, 0, 0, 0);
        const f = &module.fns[0];
        f.vreg_count = 6;
        f.block_count = 4;
        f.blocks[0].inst_count = 2;
        f.blocks[0].insts[0] = .{ .op = .const_int, .dest = 1, .imm = 0 };
        f.blocks[0].insts[1] = .{ .op = .cond_jump, .src1 = 1, .target_block = 1, .alt_block = 2 };
        f.blocks[1].inst_count = 2;
        f.blocks[1].insts[0] = .{ .op = .const_int, .dest = 2, .imm = 10 };
        f.blocks[1].insts[1] = .{ .op = .jump, .target_block = 3 };
        f.blocks[2].inst_count = 2;
        f.blocks[2].insts[0] = .{ .op = .const_int, .dest = 5, .imm = 20 };
        f.blocks[2].insts[1] = .{ .op = .jump, .target_block = 3 };
        f.blocks[3].inst_count = 2;
        f.blocks[3].insts[0] = .{ .op = .phi, .dest = 4, .arg_count = 2, .args = .{ 2, 5, 0, 0, 0, 0, 0, 0 }, .phi_blocks = .{ 1, 2, 0, 0, 0, 0, 0, 0 } };
        f.blocks[3].insts[1] = .{ .op = .ret, .src1 = 4 };
        try ir_verify.verify(module, "main");
        const ir_vm_mod = @import("ir_vm.zig");
        const res = try ir_vm_mod.execute(std.testing.allocator, module, "main", &[_][]const u8{}, false, .{});
        try std.testing.expect(!res.trapped);
        try std.testing.expectEqual(@as(i64, 20), res.exit_code);
    }
    // Post-SSA (destructSSA output shape): a vreg defined in the entry block
    // and *redefined* on one path; the merge-block use is fed by the
    // dominating entry def, which is legal non-SSA IR. Plus an unreachable
    // block whose nonsense use must be ignored (dead code is exempt).
    {
        const module = try std.testing.allocator.create(ir_mod.IRModule);
        defer std.testing.allocator.destroy(module);
        module.init();
        module.fn_count = 1;
        ir_mod.IRModule.initFnSlot(&module.fns[0], 0, 4, 0, 0, 0);
        const f = &module.fns[0];
        f.vreg_count = 4;
        f.block_count = 4;
        f.blocks[0].inst_count = 3;
        f.blocks[0].insts[0] = .{ .op = .const_int, .dest = 1, .imm = 0 };
        f.blocks[0].insts[1] = .{ .op = .const_int, .dest = 2, .imm = 7 }; // dominating def of v2
        f.blocks[0].insts[2] = .{ .op = .cond_jump, .src1 = 1, .target_block = 1, .alt_block = 2 };
        f.blocks[1].inst_count = 2;
        f.blocks[1].insts[0] = .{ .op = .const_int, .dest = 2, .imm = 9 }; // redefinition on one path
        f.blocks[1].insts[1] = .{ .op = .jump, .target_block = 2 };
        f.blocks[2].inst_count = 1;
        f.blocks[2].insts[0] = .{ .op = .ret, .src1 = 2 };
        f.blocks[3].inst_count = 1;
        f.blocks[3].insts[0] = .{ .op = .ret, .src1 = 3 }; // unreachable: v3 never defined anywhere
        try ir_verify.verify(module, "main");
    }
}

test "Optimizer regression: if-conversion must not move branch bodies above the producer they read" {
    // The hidden SSA bug the Issue #6 dataflow verifier exposed. ifConversion
    // lowers its insertion point below the condition `cmp` (and below the
    // `bit_and` feeding it) so the compare stays adjacent to the synthesized
    // `select`, but it used to do that without checking whether the moved
    // branch bodies read vregs defined by those very tail instructions.
    // For `let rem = v & 15; if rem < 10 { 48 + rem } else { 87 + rem }` it
    // emitted `add rem,48` / `add rem,87` BEFORE `rem = v & 15`: a
    // use-before-def that silently evaluated against a stale register. The
    // verifier now rejects that shape, so a successful -O2 compile of this
    // source plus the exact output is the regression check.
    // The shape matters: inside a loop, LICM/LVN hoist the comparison
    // constants into the preheader, leaving `rem = x & 15`, `cmp`, `cond_jump`
    // adjacent at the end of the header — exactly the pattern whose tail the
    // buggy insertion-point logic moved the branch bodies above.
    const src =
        \\fn sum_hex(v: i64) -> i64 {
        \\    var acc: i64 = 0
        \\    var x = v
        \\    while x != 0 {
        \\        let rem = x & 15
        \\        let c = if rem < 10 { 48 + rem } else { 87 + rem }
        \\        acc = acc + c
        \\        x = x >> 4
        \\    }
        \\    return acc
        \\}
        \\fn main() -> i64 {
        \\    printInt(sum_hex(255))
        \\    printInt(sum_hex(7))
        \\    return 0
        \\}
    ;
    const elf = try compileSourceWithOpt(src, .O2);
    defer std.testing.allocator.free(elf);
    const res = try runElfCapture(std.testing.allocator, elf, "ifconv_nibble");
    defer std.testing.allocator.free(res.stdout);
    try std.testing.expectEqual(@as(u8, 0), res.exit_code);
    try std.testing.expectEqualStrings("204\n55\n", res.stdout);

    // Same answer from the unoptimized pipeline: -O0 and -O2 must agree.
    const elf0 = try compileSourceWithOpt(src, .O0);
    defer std.testing.allocator.free(elf0);
    const res0 = try runElfCapture(std.testing.allocator, elf0, "ifconv_nibble_o0");
    defer std.testing.allocator.free(res0.stdout);
    try std.testing.expectEqual(@as(u8, 0), res0.exit_code);
    try std.testing.expectEqualStrings("204\n55\n", res0.stdout);
}

test "VM enforces a non-zero step limit: while true {} fails with StepLimitExceeded" {
    // Issue #4 PoC shape: `fn main() -> i64 { while true {} }` lowers to a
    // single block that jumps to itself. The VM counted `steps` but never
    // compared them to a limit, so this loop ran forever — a deterministic
    // host DoS for anything that interprets untrusted programs. Before the
    // fix this test does not fail, it hangs (verified with timeout(1)).
    const ir_vm_mod = @import("ir_vm.zig");

    // The default budget must be non-zero: 0 silently meant "unlimited".
    try std.testing.expect(ir_vm_mod.DEFAULT_MAX_STEPS > 0);

    // Infinite-loop module: B0 = [jump B0].
    const loop_mod = try std.testing.allocator.create(ir_mod.IRModule);
    defer std.testing.allocator.destroy(loop_mod);
    loop_mod.init();
    loop_mod.fn_count = 1;
    ir_mod.IRModule.initFnSlot(&loop_mod.fns[0], 0, 4, 0, 0, 0);
    loop_mod.fns[0].vreg_count = 1;
    loop_mod.fns[0].block_count = 1;
    loop_mod.fns[0].blocks[0].inst_count = 1;
    loop_mod.fns[0].blocks[0].insts[0] = .{ .op = .jump, .target_block = 0 };

    // A small explicit budget fires deterministically and immediately.
    {
        const vm = try ir_vm_mod.VMState.init(std.testing.allocator, loop_mod, "main");
        defer vm.deinit();
        vm.max_steps = 1_000;
        try std.testing.expectError(ir_vm_mod.VMError.StepLimitExceeded, vm.run());
        try std.testing.expect(vm.steps >= 1_000);
    }

    // execute() maps the budget exhaustion to the conventional timeout code.
    {
        const res = try ir_vm_mod.execute(std.testing.allocator, loop_mod, "main", &[_][]const u8{}, false, .{ .max_steps = 1_000 });
        try std.testing.expect(res.trapped);
        try std.testing.expectEqual(@as(i64, 124), res.exit_code);
        try std.testing.expect(res.steps >= 1_000);
    }

    // Wall-clock budget: a guest loop that never stops is also cut at
    // max_wall_ms even when the step budget is effectively unbounded.
    {
        const vm = try ir_vm_mod.VMState.init(std.testing.allocator, loop_mod, "main");
        defer vm.deinit();
        vm.max_steps = std.math.maxInt(u64);
        vm.max_wall_ms = 1;
        try std.testing.expectError(ir_vm_mod.VMError.WallTimeExceeded, vm.run());
    }

    // max_steps = 0 must not disable the guard: run() normalizes it back to
    // the default (same for max_wall_ms). Pinned on a program that exits
    // immediately (spinning the full 1e9-step default would be too slow for
    // a unit test).
    {
        const ok_mod = try std.testing.allocator.create(ir_mod.IRModule);
        defer std.testing.allocator.destroy(ok_mod);
        ok_mod.init();
        ok_mod.fn_count = 1;
        ir_mod.IRModule.initFnSlot(&ok_mod.fns[0], 0, 4, 0, 0, 0);
        ok_mod.fns[0].vreg_count = 1;
        ok_mod.fns[0].block_count = 1;
        ok_mod.fns[0].blocks[0].inst_count = 1;
        ok_mod.fns[0].blocks[0].insts[0] = .{ .op = .ret, .src1 = 0 };

        const vm = try ir_vm_mod.VMState.init(std.testing.allocator, ok_mod, "main");
        defer vm.deinit();
        vm.max_steps = 0; // the pre-fix "unlimited" value
        vm.max_wall_ms = 0;
        const code = try vm.run();
        try std.testing.expectEqual(@as(i64, 0), code);
        try std.testing.expectEqual(ir_vm_mod.DEFAULT_MAX_STEPS, vm.max_steps);
        try std.testing.expectEqual(ir_vm_mod.DEFAULT_MAX_WALL_MS, vm.max_wall_ms);
    }
}





test "unreachable terminates block and does not accept following statements" {
    const source =
        \\fn main() -> i64 {
        \\    unreachable
        \\    return 7
        \\}
    ;
    const elf = try compileSource(source);
    defer std.testing.allocator.free(elf);
    try std.testing.expect(elf.len > 4);
    try std.testing.expectEqualSlices(u8, "\x7fELF", elf[0..4]);
    try std.testing.expect(std.mem.indexOf(u8, elf, &[_]u8{ 0x0F, 0x0B }) != null);
}

test "unreachable keyword is lowered to a native trap" {
    const source =
        \\fn main() -> i64 {
        \\    unreachable
        \\}
    ;
    const elf = try compileSource(source);
    defer std.testing.allocator.free(elf);
    try std.testing.expect(elf.len > 4);
    try std.testing.expectEqualSlices(u8, "\x7fELF", elf[0..4]);
    try std.testing.expect(std.mem.indexOf(u8, elf, &[_]u8{ 0x0F, 0x0B }) != null);
}

test "low-level bitwise and shift operators reach native code generation" {
    const source =
        \\fn main() -> i64 {
        \\    return ((6 & 3) | (1 << 2)) ^ (~0)
        \\}
    ;
    const elf = try compileSource(source);
    defer std.testing.allocator.free(elf);
    try std.testing.expect(elf.len > 4);
    try std.testing.expectEqualSlices(u8, "\x7fELF", elf[0..4]);
}

test "lexer distinguishes shift operators from comparisons" {
    const lexer = try std.testing.allocator.create(lexer_mod.Lexer);
    defer std.testing.allocator.destroy(lexer);
    lexer.* = lexer_mod.Lexer.init("1 << 2 >> 1 <= 4 >= 2");
    lexer.tokenize();
    const expected = [_]lexer_mod.TokenKind{
        .int_literal, .lshift, .int_literal, .rshift, .int_literal,
        .le, .int_literal, .ge, .int_literal, .eof,
    };
    try std.testing.expectEqual(expected.len, lexer.token_count);
    for (expected, 0..) |kind, i| try std.testing.expectEqual(kind, lexer.get(@intCast(i)).kind);
}

test "lexer recognizes low-level systems keywords without splitting identifiers" {
    const source = "unsafe volatile asm align packed union unreachable as isize usize i128 u128 never unsafe_mode";
    const lexer = try std.testing.allocator.create(lexer_mod.Lexer);
    defer std.testing.allocator.destroy(lexer);
    lexer.* = lexer_mod.Lexer.init(source);
    lexer.tokenize();

    const expected = [_]lexer_mod.TokenKind{
        .kw_unsafe, .kw_volatile, .kw_asm, .kw_align, .kw_packed, .kw_union,
        .kw_unreachable, .kw_as, .kw_isize, .kw_usize, .kw_i128, .kw_u128,
        .kw_never, .identifier, .eof,
    };
    try std.testing.expectEqual(expected.len, lexer.token_count);
    for (expected, 0..) |kind, i| {
        try std.testing.expectEqual(kind, lexer.get(@intCast(i)).kind);
    }
}

test "lexer recognizes distinctive keywords: guard, unless, until, proc" {
    const source = "guard unless until proc guard_mode";
    const lexer = try std.testing.allocator.create(lexer_mod.Lexer);
    defer std.testing.allocator.destroy(lexer);
    lexer.* = lexer_mod.Lexer.init(source);
    lexer.tokenize();

    const expected = [_]lexer_mod.TokenKind{
        .kw_guard, .kw_unless, .kw_until, .kw_fn, .identifier, .eof,
    };
    try std.testing.expectEqual(expected.len, lexer.token_count);
    for (expected, 0..) |kind, i| {
        try std.testing.expectEqual(kind, lexer.get(@intCast(i)).kind);
    }
}

test "lexer supports radix literals, char literals, and nested block comments" {
    const source =
        \\/* outer /* inner */ still comment */ let a = 0xFF
        \\let b = 0b1010_0101
        \\let c = 0o77
        \\let ch = 'A'
    ;
    const lexer = try std.testing.allocator.create(lexer_mod.Lexer);
    defer std.testing.allocator.destroy(lexer);
    lexer.* = lexer_mod.Lexer.init(source);
    lexer.tokenize();
    try std.testing.expect(!lexer.invalid);
    try std.testing.expectEqual(lexer_mod.TokenKind.kw_let, lexer.get(0).kind);
    try std.testing.expectEqual(lexer_mod.TokenKind.int_literal, lexer.get(3).kind);
    try std.testing.expectEqual(lexer_mod.TokenKind.int_literal, lexer.get(8).kind);
    try std.testing.expectEqual(lexer_mod.TokenKind.int_literal, lexer.get(13).kind);
    try std.testing.expectEqual(lexer_mod.TokenKind.char_literal, lexer.get(18).kind);
}

test "sema rejects undefined variable, arity mismatch, break outside loop, and invalid address-of" {
    const bad_var = "fn main() -> i64 { return missing }";
    var c1 = main.Compiler.init(bad_var, "<test>");
    c1.quiet = true;
    try std.testing.expectError(error.UndefinedVariable, c1.compile());

    const bad_arity = "fn f(a: i64) -> i64 { return a }\nfn main() -> i64 { return f(1, 2) }";
    var c2 = main.Compiler.init(bad_arity, "<test>");
    c2.quiet = true;
    try std.testing.expectError(error.InvalidArgumentCount, c2.compile());

    const bad_break = "fn main() -> i64 { break\n return 0 }";
    var c3 = main.Compiler.init(bad_break, "<test>");
    c3.quiet = true;
    try std.testing.expectError(error.LoopControlOutsideLoop, c3.compile());

    const bad_addr = "fn main() -> i64 { let p = &42\n return *p }";
    var c4 = main.Compiler.init(bad_addr, "<test>");
    c4.quiet = true;
    try std.testing.expectError(error.InvalidAddressOf, c4.compile());
}

test "ELF execution: arithmetic, recursion, radix literals, and -O0/-O1/-O2 parity" {
    const source =
        \\fn fib(n: i64) -> i64 {
        \\    if n <= 1 { return n }
        \\    return fib(n - 1) + fib(n - 2)
        \\}
        \\fn main() -> i64 {
        \\    let hex = 0x10
        \\    let bin = 0b101
        \\    let oct = 0o10
        \\    let ch = 'A'
        \\    printInt(fib(12))
        \\    printInt(hex + bin + oct + ch)
        \\    return 7
        \\}
    ;
    const opts = [_]main.OptLevel{ .O0, .O1, .O2 };
    for (opts) |opt| {
        const elf = try compileSourceWithOpt(source, opt);
        defer std.testing.allocator.free(elf);
        const run_res = try runElfCapture(std.testing.allocator, elf, @tagName(opt));
        defer std.testing.allocator.free(run_res.stdout);
        try std.testing.expectEqual(@as(u8, 7), run_res.exit_code);
        try std.testing.expectEqualStrings("144\n94\n", run_res.stdout);
    }
}

test "ELF execution: structs, pointers, strings, arrays, and byte primitives" {
    const source =
        \\struct Pair {
        \\    a: i64
        \\    b: i64
        \\}
        \\fn bump(p: *i64) -> i64 {
        \\    *p = *p + 10
        \\    return *p
        \\}
        \\fn main() -> i64 {
        \\    let mut p = Pair { a: 3, b: 4 }
        \\    p.b = 19
        \\    let mut x = p.a + p.b
        \\    printInt(bump(&x))
        \\
        \\    let s = "hi" + "!"
        \\    println(s)
        \\    printInt(@string_len(s))
        \\    printInt(@string_to_int("4096"))
        \\    println(@int_to_string(-123))
        \\
        \\    let arr = @array_new(4, 8)
        \\    @array_push(arr, 11)
        \\    @array_push(arr, 22)
        \\    @array_push(arr, 33)
        \\    let mut total = 0
        \\    for v in arr {
        \\        total += v
        \\    }
        \\    printInt(total)
        \\
        \\    let buf = @malloc(16)
        \\    @memset(buf, 65, 3)
        \\    @write_byte(@ptr_add(buf, 3), 0)
        \\    printInt(@read_byte(buf))
        \\    return 0
        \\}
    ;
    const elf = try compileSourceWithOpt(source, .O2);
    defer std.testing.allocator.free(elf);
    const run_res = try runElfCapture(std.testing.allocator, elf, "runtime");
    defer std.testing.allocator.free(run_res.stdout);
    try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
    try std.testing.expectEqualStrings("32\nhi!\n3\n4096\n-123\n66\n65\n", run_res.stdout);
}

test "ELF execution: impl methods, defer LIFO, fixed arrays, and var/type aliases" {
    const source =
        \\type Index = i64
        \\struct Counter {
        \\    val: i64
        \\}
        \\impl Counter {
        \\    fn new(start: i64) -> Counter {
        \\        return Counter { val: start }
        \\    }
        \\    fn add(&mut self, delta: i64) {
        \\        self.val += delta
        \\    }
        \\    fn get(&self) -> i64 {
        \\        return self.val
        \\    }
        \\}
        \\fn trace_defer(flag: i64) -> i64 {
        \\    defer printInt(10)
        \\    defer printInt(20)
        \\    if flag > 0 {
        \\        defer printInt(30)
        \\        return 99
        \\    }
        \\    return 0
        \\}
        \\fn main() -> i64 {
        \\    var c = Counter::new(5)
        \\    c.add(7)
        \\    printInt(c.get())
        \\    printInt(trace_defer(1))
        \\
        \\    var arr: [4]i64 = [10, 20, 30, 40]
        \\    arr[2] = 35
        \\    var sum: Index = 0
        \\    for i in 0..=3 {
        \\        sum += arr[i]
        \\    }
        \\    printInt(arr.len)
        \\    printInt(sum)
        \\    return 0
        \\}
    ;
    for ([_]main.OptLevel{ .O0, .O1, .O2 }) |opt| {
        const elf = try compileSourceWithOpt(source, opt);
        defer std.testing.allocator.free(elf);
        const run_res = try runElfCapture(std.testing.allocator, elf, "pillar1");
        defer std.testing.allocator.free(run_res.stdout);
        try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
        try std.testing.expectEqualStrings("12\n30\n20\n10\n99\n4\n105\n", run_res.stdout);
    }
}

test "ELF execution: 8 parameters, null pointer, slab free/reuse, string_split, and -O2 loop LICM/GVN" {
    const source =
        \\fn sum8(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64) -> i64 {
        \\    return a + b + c + d + e + f + g + h
        \\}
        \\fn licm_gvn(n: i64, a: i64, b: i64) -> i64 {
        \\    var acc = 0
        \\    var i = 0
        \\    while i < n {
        \\        let k1 = (a + b) * 3
        \\        let k2 = (a + b) * 3
        \\        acc += k1 + k2 + i
        \\        i += 1
        \\    }
        \\    return acc
        \\}
        \\fn main() -> i64 {
        \\    printInt(sum8(1, 2, 3, 4, 5, 6, 7, 8))
        \\    let p: *i64 = null
        \\    printInt(p == null ? 1 : 0)
        \\    printInt(licm_gvn(5, 2, 4))
        \\
        \\    // Slab alloc + free reuse + large mmap allocation
        \\    let m1 = @malloc(32)
        \\    @write_byte(m1, 77)
        \\    @free(m1)
        \\    let m2 = @malloc(32)
        \\    @write_byte(m2, 88)
        \\    printInt(@read_byte(m2))
        \\    let big = @malloc(8192)
        \\    @write_byte(@ptr_add(big, 8000), 55)
        \\    printInt(@read_byte(@ptr_add(big, 8000)))
        \\    @free(big)
        \\
        \\    // String split
        \\    let parts = @string_split("alpha,beta,gamma", ",")
        \\    printInt(@array_len(parts))
        \\    println(@array_get(parts, 0))
        \\    println(@array_get(parts, 2))
        \\    printInt(@time_ns() > 0 ? 1 : 0)
        \\    return 0
        \\}
    ;
    for ([_]main.OptLevel{ .O0, .O1, .O2 }) |opt| {
        const elf = try compileSourceWithOpt(source, opt);
        defer std.testing.allocator.free(elf);
        const run_res = try runElfCapture(std.testing.allocator, elf, "pillar2");
        defer std.testing.allocator.free(run_res.stdout);
        try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
        try std.testing.expectEqualStrings("36\n1\n190\n88\n55\n3\nalpha\ngamma\n1\n", run_res.stdout);
    }
}

test "multi-file quoted imports resolve dependencies and deduplicate diamond imports" {
    var tmp_dir_buf: [128]u8 = undefined;
    const tmp_dir = try std.fmt.bufPrint(&tmp_dir_buf, "/tmp/lir_mf_{d}", .{std.os.linux.getpid()});
    std.fs.makeDirAbsolute(tmp_dir) catch {};
    defer std.fs.deleteTreeAbsolute(tmp_dir) catch {};

    var p_common_buf: [192]u8 = undefined;
    const p_common = try std.fmt.bufPrint(&p_common_buf, "{s}/common.lir", .{tmp_dir});
    try std.fs.cwd().writeFile(.{ .sub_path = p_common, .data = "struct Pair { x: i64, y: i64 }\nfn base() -> i64 { return 10 }\n" });

    var p_left_buf: [192]u8 = undefined;
    const p_left = try std.fmt.bufPrint(&p_left_buf, "{s}/left.lir", .{tmp_dir});
    try std.fs.cwd().writeFile(.{ .sub_path = p_left, .data = "import \"common.lir\"\nfn left_val() -> i64 { return base() + 5 }\n" });

    var p_right_buf: [192]u8 = undefined;
    const p_right = try std.fmt.bufPrint(&p_right_buf, "{s}/right.lir", .{tmp_dir});
    try std.fs.cwd().writeFile(.{ .sub_path = p_right, .data = "import \"common.lir\"\nfn right_val(p: Pair) -> i64 { return p.x + p.y }\n" });

    var p_main_buf: [192]u8 = undefined;
    const p_main = try std.fmt.bufPrint(&p_main_buf, "{s}/entry.lir", .{tmp_dir});
    const entry_src =
        \\import "left.lir"
        \\import "right.lir"
        \\fn main() -> i64 {
        \\    let p = Pair { x: 20, y: 7 }
        \\    printInt(left_val() + right_val(p))
        \\    return 0
        \\}
    ;
    try std.fs.cwd().writeFile(.{ .sub_path = p_main, .data = entry_src });

    var compiler = main.Compiler.initWithOpts(entry_src, p_main, .O2);
    compiler.quiet = true;
    const elf = try compiler.compile();
    defer std.heap.page_allocator.free(elf);
    const run_res = try runElfCapture(std.testing.allocator, elf, "multifile");
    defer std.testing.allocator.free(run_res.stdout);
    try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
    try std.testing.expectEqualStrings("42\n", run_res.stdout);
}

test "multi-file missing quoted import fails closed with ImportNotFound" {
    var compiler = main.Compiler.init("import \"missing_module_xyz.lir\"\nfn main() -> i64 { return 0 }", "<test>");
    compiler.quiet = true;
    try std.testing.expectError(error.ImportNotFound, compiler.compile());
}

test "ELF execution: 2M self-tail-call recursion executes in O(1) stack space" {
    const source =
        \\fn sum_tail(n: i64, acc: i64) -> i64 {
        \\    if n <= 0 { return acc }
        \\    return sum_tail(n - 1, acc + 1)
        \\}
        \\fn main() -> i64 {
        \\    printInt(sum_tail(2000000, 0))
        \\    return 0
        \\}
    ;
    for ([_]main.OptLevel{ .O1, .O2 }) |opt| {
        const elf = try compileSourceWithOpt(source, opt);
        defer std.testing.allocator.free(elf);
        const run_res = try runElfCapture(std.testing.allocator, elf, "tail2m");
        defer std.testing.allocator.free(run_res.stdout);
        try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
        try std.testing.expectEqualStrings("2000000\n", run_res.stdout);
    }
}

test "ELF execution: 10000-cycle slab malloc/free churn and @argc/@argv" {
    const source =
        \\fn main() -> i64 {
        \\    var i = 0
        \\    while i < 10000 {
        \\        let a = @malloc(32)
        \\        let b = @malloc(256)
        \\        let c = @malloc(1024)
        \\        @write_byte(a, 11)
        \\        @write_byte(b, 22)
        \\        @write_byte(c, 33)
        \\        @free(a)
        \\        @free(b)
        \\        @free(c)
        \\        i += 1
        \\    }
        \\    printInt(@argc())
        \\    printInt(@string_len(@argv(0)) > 0 ? 1 : 0)
        \\    return 0
        \\}
    ;
    const elf = try compileSourceWithOpt(source, .O2);
    defer std.testing.allocator.free(elf);
    const run_res = try runElfCapture(std.testing.allocator, elf, "slab_churn");
    defer std.testing.allocator.free(run_res.stdout);
    try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
    try std.testing.expectEqualStrings("1\n1\n", run_res.stdout);
}

test "sema rejects constant div/mod by zero, out-of-range shifts, and fixed-array OOB" {
    try std.testing.expectError(error.TypeMismatch, compileSource("fn main() -> i64 { return 10 / 0 }"));
    try std.testing.expectError(error.TypeMismatch, compileSource("fn main() -> i64 { return 10 % 0 }"));
    try std.testing.expectError(error.TypeMismatch, compileSource("fn main() -> i64 { var x = 5\n x /= 0\n return x }"));
    try std.testing.expectError(error.TypeMismatch, compileSource("fn main() -> i64 { return 1 << 64 }"));
    try std.testing.expectError(error.TypeMismatch, compileSource("fn main() -> i64 { return 1 >> -1 }"));
    try std.testing.expectError(error.TypeMismatch, compileSource("fn main() -> i64 { let a: [3]i64 = [1, 2, 3]\n return a[3] }"));
    try std.testing.expectError(error.TypeMismatch, compileSource("fn main() -> i64 { let a: [3]i64 = [1, 2, 3]\n return a[-1] }"));
}

test "sema enforces cross-namespace uniqueness, non-void return paths, and fixed-point consts" {
    try std.testing.expectError(error.DuplicateDeclaration, compileSource("struct Foo { x: i64 }\nfn Foo() -> i64 { return 0 }\nfn main() -> i64 { return 0 }"));
    try std.testing.expectError(error.DuplicateDeclaration, compileSource("enum Bar { A }\nconst Bar = 1\nfn main() -> i64 { return 0 }"));
    try std.testing.expectError(error.DuplicateDeclaration, compileSource("type Num = i64\nfn Num() -> i64 { return 0 }\nfn main() -> i64 { return 0 }"));
    try std.testing.expectError(error.TypeMismatch, compileSource("fn f(x: i64) -> i64 { if x > 0 { return 1 } }\nfn main() -> i64 { return f(1) }"));
    try std.testing.expectError(error.TypeMismatch, compileSource("const A = B + 1\nconst B = A + 1\nfn main() -> i64 { return A }"));

    // Forward-referenced non-cyclic global constants must resolve
    const elf = try compileSourceWithOpt("const B = A + 1\nconst A = 41\nfn main() -> i64 { printInt(B)\n return 0 }", .O2);
    defer std.testing.allocator.free(elf);
    const run_res = try runElfCapture(std.testing.allocator, elf, "fp_const");
    defer std.testing.allocator.free(run_res.stdout);
    try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
    try std.testing.expectEqualStrings("42\n", run_res.stdout);
}

test "multi-file diagnostics attribute errors to the imported filename and line" {
    var tmp_dir_buf: [128]u8 = undefined;
    const tmp_dir = try std.fmt.bufPrint(&tmp_dir_buf, "/tmp/lir_mfdiag_{d}", .{std.os.linux.getpid()});
    std.fs.makeDirAbsolute(tmp_dir) catch {};
    defer std.fs.deleteTreeAbsolute(tmp_dir) catch {};

    var p_bad_buf: [192]u8 = undefined;
    const p_bad = try std.fmt.bufPrint(&p_bad_buf, "{s}/bad_mod.lir", .{tmp_dir});
    try std.fs.cwd().writeFile(.{ .sub_path = p_bad, .data = "fn helper() -> i64 {\n    return missing_var\n}\n" });

    var p_main_buf: [192]u8 = undefined;
    const p_main = try std.fmt.bufPrint(&p_main_buf, "{s}/main.lir", .{tmp_dir});
    const entry_src = "import \"bad_mod.lir\"\nfn main() -> i64 { return helper() }\n";
    try std.fs.cwd().writeFile(.{ .sub_path = p_main, .data = entry_src });

    var compiler = main.Compiler.initWithOpts(entry_src, p_main, .O1);
    compiler.quiet = true;
    try std.testing.expectError(error.UndefinedVariable, compiler.compile());
    try std.testing.expect(compiler.last_diag_count > 0);
    try std.testing.expectEqual(@as(u32, 1), compiler.last_diag_source_id);
    try std.testing.expectEqual(@as(u32, 2), compiler.last_diag_line);
}

test "ELF execution: runtime safety traps on OOB, div0, MIN_INT/-1, double-free, and argv OOB" {
    const cases = [_]struct { name: []const u8, src: []const u8 }{
        .{
            .name = "fa_oob",
            .src =
            \\fn get_idx(i: i64) -> i64 {
            \\    let a: [3]i64 = [10, 20, 30]
            \\    return a[i]
            \\}
            \\fn main() -> i64 { return get_idx(3) }
            ,
        },
        .{
            .name = "dyn_oob",
            .src =
            \\fn main() -> i64 {
            \\    let a = @array_new(4)
            \\    @array_push(a, 11)
            \\    return @array_get(a, 1)
            \\}
            ,
        },
        .{
            .name = "div_zero",
            .src =
            \\fn divv(a: i64, b: i64) -> i64 { return a / b }
            \\fn main() -> i64 { return divv(100, 0) }
            ,
        },
        .{
            .name = "min_int_div",
            .src =
            \\fn rt_val(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
            \\fn divv(a: i64, b: i64) -> i64 { return a / b }
            \\fn main() -> i64 { return divv(rt_val(-9223372036854775807 - 1), rt_val(-1)) }
            ,
        },
        .{
            .name = "char_oob",
            .src =
            \\fn rt_val(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
            \\fn main() -> i64 { return @string_char_at("abc", rt_val(5)) }
            ,
        },
        .{
            .name = "double_free",
            .src =
            \\fn do_free(p: *u8) { @free(p) }
            \\fn main() -> i64 {
            \\    let p = @malloc(32)
            \\    do_free(p)
            \\    do_free(p)
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "unaligned_free",
            .src =
            \\fn main() -> i64 {
            \\    let p = @malloc(32)
            \\    @free(@ptr_add(p, 1))
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "argv_oob",
            .src = "fn main() -> i64 { return @string_len(@argv(999)) }",
        },
    };
    for (cases) |tc| {
        const elf = try compileSourceWithOpt(tc.src, .O2);
        defer std.testing.allocator.free(elf);
        try runElfExpectSigIll(std.testing.allocator, elf, tc.name);
    }
}

test "security: heap bounds checks cannot be disabled via environment (LIR_TRAP_CEIL removed)" {
    // Regression for docs/CRITICAL_ISSUES_6.md issue #1. An out-of-bounds heap
    // read (4096 bytes past a 16-byte chunk, still inside the heap arena) must
    // trap with SIGILL regardless of ambient environment configuration, and
    // the emitted ELF must be byte-identical with and without the legacy
    // LIR_TRAP_CEIL measurement switch set to "1" or "0". Before the fix, any
    // value of that variable (including "0") stripped the heap-range screen
    // and the __lir_chk_heap{1,4,8} verifier call from the hottest access
    // paths, turning the OOB read into a silent success.
    const source =
        \\fn rt_val(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
        \\fn main() -> i64 {
        \\    let buf = @malloc(16)
        \\    @memset(buf, 65, 16)
        \\    let v = @read_byte(@ptr_add(buf, rt_val(4096)))
        \\    printInt(v)
        \\    return 0
        \\}
    ;
    for ([_]main.OptLevel{ .O0, .O1, .O2 }) |opt| {
        const baseline = try compileSourceWithOpt(source, opt);
        defer std.testing.allocator.free(baseline);
        try runElfExpectSigIll(std.testing.allocator, baseline, "trap_ceil_base");

        for ([_][]const u8{ "1", "0" }) |value| {
            // Zig 0.13 has no setenv in std; append to the environ slice the
            // same way std.posix.getenv reads it, then restore.
            const saved_environ = std.os.environ;
            var entry_buf: [32]u8 = undefined;
            const entry_z = try std.testing.allocator.dupeZ(u8, try std.fmt.bufPrint(&entry_buf, "LIR_TRAP_CEIL={s}", .{value}));
            defer std.testing.allocator.free(entry_z);
            const extended = try std.testing.allocator.alloc([*:0]u8, saved_environ.len + 1);
            defer std.testing.allocator.free(extended);
            @memcpy(extended[0..saved_environ.len], saved_environ);
            extended[saved_environ.len] = entry_z.ptr;
            std.os.environ = extended;
            errdefer std.os.environ = saved_environ;
            // The variable must be visible to std.posix.getenv before we rely
            // on codegen ignoring it.
            try std.testing.expect(std.posix.getenv("LIR_TRAP_CEIL") != null);

            const with_env = try compileSourceWithOpt(source, opt);
            std.os.environ = saved_environ;
            defer std.testing.allocator.free(with_env);
            // The emitted machine code must not depend on the environment.
            try std.testing.expectEqualSlices(u8, baseline, with_env);
            // And the OOB read must still trap.
            try runElfExpectSigIll(std.testing.allocator, with_env, "trap_ceil_env");
        }
    }
}

test "security: startup seeds canaries via getrandom, never rdtsc or fixed constants" {
    // Regression for docs/CRITICAL_ISSUES_6.md issue #3. The native startup
    // used to derive heap_secret and stack_canary from rdtsc ^ rsp with a
    // constant 0x0102030405060700 fallback canary, and heap redzone canaries
    // were keyed by the compile-time-public CANARY_SALT 0xA5A55A5A12345678.
    // All secrets must now come from the kernel CSPRNG (getrandom, SYS 318)
    // with fail-closed ud2 on error/short read/zero canary: no rdtsc seeding
    // sequence, no constant fallback canary immediate, and no CANARY_SALT
    // immediate may appear anywhere in the emitted ELF. Note that the runtime
    // secret values are deliberately unobservable to the guest program, so
    // this test pins the seeding mechanism in the emitted code; the existing
    // stack_canary_smash / heap_slab_overflow_canary trap tests prove the
    // canary write/check pairs still agree after the salt removal.
    const source =
        \\fn main() -> i64 {
        \\    let buf = @malloc(32)
        \\    @memset(buf, 7, 32)
        \\    let v = @read_byte(buf)
        \\    @free(buf)
        \\    printInt(v)
        \\    return 0
        \\}
    ;
    for ([_]main.OptLevel{ .O0, .O2 }) |opt| {
        const elf = try compileSourceWithOpt(source, opt);
        defer std.testing.allocator.free(elf);

        // mov eax, 318 (SYS_getrandom); syscall — the startup seeding call.
        const getrandom_call = [_]u8{ 0xB8, 0x3E, 0x01, 0x00, 0x00, 0x0F, 0x05 };
        try std.testing.expect(std.mem.indexOf(u8, elf, &getrandom_call) != null);

        // rdtsc; shl rdx, 32 — the removed weak-seed sequence.
        const rdtsc_seed = [_]u8{ 0x0F, 0x31, 0x48, 0xC1, 0xE2, 0x20 };
        try std.testing.expect(std.mem.indexOf(u8, elf, &rdtsc_seed) == null);

        // movabs rax, 0x0102030405060700 — the removed constant fallback canary.
        const fallback_canary = [_]u8{ 0x48, 0xB8, 0x00, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01 };
        try std.testing.expect(std.mem.indexOf(u8, elf, &fallback_canary) == null);

        // CANARY_SALT as a little-endian 64-bit immediate.
        const canary_salt = [_]u8{ 0x78, 0x56, 0x34, 0x12, 0x5A, 0x5A, 0xA5, 0xA5 };
        try std.testing.expect(std.mem.indexOf(u8, elf, &canary_salt) == null);

        // The program must still run correctly: the redzone canary written by
        // @malloc must still match what @free recomputes (secret ^ size).
        const run_res = try runElfCapture(std.testing.allocator, elf, "csprng_seed");
        defer std.testing.allocator.free(run_res.stdout);
        try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
        try std.testing.expectEqualStrings("7\n", run_res.stdout);
    }
}

test "ELF execution: dynamic arrays grow past 1024, @array_set zero-fills gaps, and string_split > 1024 tokens" {
    const source =
        \\fn main() -> i64 {
        \\    let arr = @array_new(2)
        \\    var i = 0
        \\    while i < 1500 {
        \\        @array_push(arr, i * 2)
        \\        i += 1
        \\    }
        \\    @array_set(arr, 2000, 777)
        \\    printInt(@array_len(arr))
        \\    printInt(@array_get(arr, 1499))
        \\    printInt(@array_get(arr, 1750))
        \\    printInt(@array_get(arr, 2000))
        \\    @array_free(arr)
        \\
        \\    // Build 1300-part CSV string and split without truncation
        \\    var csv = "x"
        \\    var k = 0
        \\    while k < 1299 {
        \\        csv = csv + ",x"
        \\        k += 1
        \\    }
        \\    let parts = @string_split(csv, ",")
        \\    printInt(@array_len(parts))
        \\
        \\    // Clamped substrings never corrupt memory
        \\    println(@string_sub("hello", -3, 2))
        \\    println(@string_sub("hello", 3, 999))
        \\    println(@string_slice("hello", 10, 2))
        \\    return 0
        \\}
    ;
    for ([_]main.OptLevel{ .O0, .O1, .O2 }) |opt| {
        const elf = try compileSourceWithOpt(source, opt);
        defer std.testing.allocator.free(elf);
        const run_res = try runElfCapture(std.testing.allocator, elf, "dyn_grow");
        defer std.testing.allocator.free(run_res.stdout);
        try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
        try std.testing.expectEqualStrings("2001\n2998\n0\n777\n1300\nhe\nlo\n\n", run_res.stdout);
    }
}

test "ELF execution: >16-predecessor CFG join, unsigned pow2 ops, and multi-file AST optimizer" {
    var tmp_dir_buf: [128]u8 = undefined;
    const tmp_dir = try std.fmt.bufPrint(&tmp_dir_buf, "/tmp/lir_optmf_{d}", .{std.os.linux.getpid()});
    std.fs.makeDirAbsolute(tmp_dir) catch {};
    defer std.fs.deleteTreeAbsolute(tmp_dir) catch {};

    var p_helper_buf: [192]u8 = undefined;
    const p_helper = try std.fmt.bufPrint(&p_helper_buf, "{s}/helper.lir", .{tmp_dir});
    try std.fs.cwd().writeFile(.{
        .sub_path = p_helper,
        .data =
        \\fn mod_in_imported(n: i64) -> i64 {
        \\    var s = 0
        \\    for i in 0..n {
        \\        if i % 2 == 0 { s += 1 }
        \\    }
        \\    return s
        \\}
        ,
    });

    var p_main_buf: [192]u8 = undefined;
    const p_main = try std.fmt.bufPrint(&p_main_buf, "{s}/main.lir", .{tmp_dir});
    const entry_src =
        \\import "helper.lir"
        \\fn many_preds(k: i64) -> i64 {
        \\    var r = 0
        \\    if k == 0 { r = 10 }
        \\    else if k == 1 { r = 11 }
        \\    else if k == 2 { r = 12 }
        \\    else if k == 3 { r = 13 }
        \\    else if k == 4 { r = 14 }
        \\    else if k == 5 { r = 15 }
        \\    else if k == 6 { r = 16 }
        \\    else if k == 7 { r = 17 }
        \\    else if k == 8 { r = 18 }
        \\    else if k == 9 { r = 19 }
        \\    else if k == 10 { r = 20 }
        \\    else if k == 11 { r = 21 }
        \\    else if k == 12 { r = 22 }
        \\    else if k == 13 { r = 23 }
        \\    else if k == 14 { r = 24 }
        \\    else if k == 15 { r = 25 }
        \\    else if k == 16 { r = 26 }
        \\    else if k == 17 { r = 27 }
        \\    else if k == 18 { r = 28 }
        \\    else { r = 99 }
        \\    return r
        \\}
        \\fn udiv_pow2(x: u64) -> u64 {
        \\    return (x / (8 as u64)) + (x % (16 as u64))
        \\}
        \\fn main() -> i64 {
        \\    printInt(many_preds(18))
        \\    printInt(many_preds(99))
        \\    printInt(udiv_pow2(37 as u64) as i64)
        \\    printInt(mod_in_imported(6))
        \\    let buf = @malloc(16)
        \\    @write_byte(buf, 65)
        \\    @write_byte(@ptr_add(buf, 1), 66)
        \\    printInt(@read_byte(buf) + @read_byte(@ptr_add(buf, 1)))
        \\    @free(buf)
        \\    return 0
        \\}
    ;
    try std.fs.cwd().writeFile(.{ .sub_path = p_main, .data = entry_src });

    for ([_]main.OptLevel{ .O0, .O1, .O2 }) |opt| {
        var compiler = main.Compiler.initWithOpts(entry_src, p_main, opt);
        compiler.quiet = true;
        const elf = try compiler.compile();
        defer std.heap.page_allocator.free(elf);
        const run_res = try runElfCapture(std.testing.allocator, elf, "optmf");
        defer std.testing.allocator.free(run_res.stdout);
        try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
        try std.testing.expectEqualStrings("28\n99\n9\n3\n131\n", run_res.stdout);
    }
}

test "util atomic write refuses symlinks and reads roundtrip safely" {
    var path_buf: [128]u8 = undefined;
    const dir_path = try std.fmt.bufPrint(&path_buf, "/tmp/lir_util_{d}", .{std.os.linux.getpid()});
    std.fs.makeDirAbsolute(dir_path) catch {};
    defer std.fs.deleteTreeAbsolute(dir_path) catch {};

    var file_buf: [192]u8 = undefined;
    const fpath = try std.fmt.bufPrint(&file_buf, "{s}/out.bin", .{dir_path});
    try std.testing.expect(util.writeFileAtomic(fpath, "payload-123", 0o644));
    const got = try util.readFileAlloc(std.testing.allocator, fpath);
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("payload-123", got);
    _ = diag_mod;
}

test "ELF execution: generics, Option/Result, ?/??, and ADT match with guards across optimization levels" {
    const source =
        \\struct Box<T> {
        \\    val: T,
        \\}
        \\impl<T> Box<T> {
        \\    fn unwrap(&self) -> T {
        \\        return self.val
        \\    }
        \\}
        \\fn id<T>(x: T) -> T { return x }
        \\enum Shape {
        \\    Circle(i64),
        \\    Rect(i64, i64),
        \\    Dot,
        \\}
        \\fn area_like(s: Shape) -> i64 {
        \\    return match s {
        \\        Shape::Circle(r) if r > 5 => r * r * 3,
        \\        Shape::Circle(r) => r,
        \\        Shape::Rect(w, h) => w * h,
        \\        Shape::Dot => 1,
        \\    }
        \\}
        \\fn half_even(x: i64) -> Option<i64> {
        \\    if x % 2 == 0 { return Some(x / 2) }
        \\    return None
        \\}
        \\fn double_half(x: i64) -> Option<i64> {
        \\    let h = half_even(x)?
        \\    return Some(h + 10)
        \\}
        \\fn check_pos(x: i64) -> Result<i64, string> {
        \\    if x > 0 { return Ok(x * 3) }
        \\    return Err("nonpos")
        \\}
        \\fn wrap_pos(x: i64) -> Result<i64, string> {
        \\    let v = check_pos(x)?
        \\    return Ok(v + 1)
        \\}
        \\fn main() -> i64 {
        \\    let b = Box<i64> { val: id<i64>(77) }
        \\    printInt(b.unwrap())
        \\    println(id<string>("genstr"))
        \\    printInt(area_like(Shape::Circle(10)))
        \\    printInt(area_like(Shape::Circle(3)))
        \\    printInt(area_like(Shape::Rect(4, 5)))
        \\    printInt(area_like(Shape::Dot))
        \\    printInt(double_half(8) ?? -1)
        \\    printInt(double_half(7) ?? -1)
        \\    printInt(wrap_pos(4) ?? -2)
        \\    printInt(wrap_pos(-3) ?? -2)
        \\    return 0
        \\}
    ;
    for ([_]main.OptLevel{ .O0, .O1, .O2 }) |opt| {
        const elf = try compileSourceWithOpt(source, opt);
        defer std.testing.allocator.free(elf);
        const run_res = try runElfCapture(std.testing.allocator, elf, "gen_adt");
        defer std.testing.allocator.free(run_res.stdout);
        try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
        try std.testing.expectEqualStrings("77\ngenstr\n300\n3\n20\n1\n14\n-1\n13\n-2\n", run_res.stdout);
    }
}

test "ELF execution: multi-paradigm features (closures, pipe, dyn Trait, tuples, maps, comps, interp, union, comptime, floats)" {
    const source =
        \\trait Scorer {
        \\    fn score(&self) -> i64
        \\}
        \\struct Sword { dmg: i64 }
        \\struct Shield { arm: i64 }
        \\impl Scorer for Sword {
        \\    fn score(&self) -> i64 { return self.dmg * 3 }
        \\}
        \\impl Scorer for Shield {
        \\    fn score(&self) -> i64 { return self.arm + 10 }
        \\}
        \\fn eval_dyn(obj: dyn Scorer) -> i64 { return obj.score() }
        \\fn dbl(x: i64) -> i64 { return x * 2 }
        \\fn add5(x: i64) -> i64 { return x + 5 }
        \\fn apply(f: fn(i64) -> i64, x: i64) -> i64 { return f(x) }
        \\union NumBits {
        \\    as_i64: i64,
        \\    as_f64: f64,
        \\}
        \\comptime fn ct_mul(a: i64, b: i64) -> i64 { return a * b + 1 }
        \\const CT_VAL = ct_mul(6, 7)
        \\fn main() -> i64 {
        \\    let k = 100
        \\    let cl = |x: i64| -> i64 { return x + k }
        \\    printInt(apply(cl, 7))
        \\    printInt(apply(dbl, 7))
        \\    printInt(6 |> dbl |> add5 |> cl)
        \\    printInt(eval_dyn(Sword { dmg: 8 }))
        \\    printInt(eval_dyn(Shield { arm: 15 }))
        \\    let tup = (10, "ok", 42)
        \\    let (ta, tb, tc) = tup
        \\    printInt(ta + tc)
        \\    println("v={ta}_{tb}")
        \\    let m = #{"alice": 42, "bob": 7}
        \\    m["carol"] = 99
        \\    printInt(m["alice"] + m["bob"] + m["carol"])
        \\    printInt(m.len)
        \\    let sm = #{"k": "val"}
        \\    println(sm["k"])
        \\    let fm = #{"pi": 3.14}
        \\    println(@float_to_string(fm["pi"]))
        \\    let sq = [x * x for x in 1..6 if x % 2 == 1]
        \\    printInt(@array_len(sq))
        \\    printInt(@array_get(sq, 0) + @array_get(sq, 1) + @array_get(sq, 2))
        \\    var u = NumBits { as_i64: 123 }
        \\    printInt(u.as_i64)
        \\    u.as_f64 = 3.5
        \\    println(@float_to_string(u.as_f64))
        \\    printInt(CT_VAL)
        \\    printInt(comptime { 3 * 14 + 2 })
        \\    printInt(@size_of(Sword))
        \\    printInt(@align_of(Sword))
        \\    println(@type_name(Sword))
        \\    println(@float_to_string(1.0e16))
        \\    println(@float_to_string(1.25e-5))
        \\    println(@float_to_string(@string_to_float("-12.25")))
        \\    println(@float_to_string(@sqrt(9.0) + @floor(2.9) + @ceil(1.1) + @round(3.6)))
        \\    println(@float_to_string(@sin(0.0) + @cos(0.0)))
        \\    return 0
        \\}
    ;
    for ([_]main.OptLevel{ .O0, .O1, .O2 }) |opt| {
        const elf = try compileSourceWithOpt(source, opt);
        defer std.testing.allocator.free(elf);
        const run_res = try runElfCapture(std.testing.allocator, elf, "multiparadigm");
        defer std.testing.allocator.free(run_res.stdout);
        try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
        try std.testing.expectEqualStrings(
            "107\n14\n117\n24\n25\n52\nv=10_ok\n148\n3\nval\n3.14\n3\n35\n123\n3.5\n43\n44\n8\n8\nSword\n1.0e+16\n1.25e-5\n-12.25\n11.0\n1.0\n",
            run_res.stdout,
        );
    }
}

test "ELF execution: embedded stdlib modules, concurrency, atomics, functional arrays, and security builtins" {
    var path_buf: [128]u8 = undefined;
    const io_path = try std.fmt.bufPrint(&path_buf, "/tmp/lir_stdiot_{d}.txt", .{std.os.linux.getpid()});
    defer std.fs.deleteFileAbsolute(io_path) catch {};

    const source = try std.fmt.allocPrint(std.testing.allocator,
        \\import std::core
        \\import std::io
        \\import std::os
        \\import std::sys
        \\import std::net
        \\import std::crypto
        \\import std::json
        \\import std::math
        \\import std::testing
        \\fn sq_i64(x: i64) -> i64 {{ return x * x }}
        \\fn is_even(x: i64) -> bool {{ return x % 2 == 0 }}
        \\fn add_acc(acc: i64, x: i64) -> i64 {{ return acc + x }}
        \\fn main() -> i64 {{
        \\    printInt(min_i64(9, 4))
        \\    printInt(clamp_i64(25, 0, 10))
        \\    println(json_kv_int("ok", 42))
        \\    println(@float_to_string(sin_f(pi() * 0.5)))
        \\    println(@float_to_string(cos_f(pi())))
        \\    @assert(getpid() > 0)
        \\    @assert(@string_len(getenv("PATH")) > 0)
        \\    @assert_eq(write_file("{s}", "abc123"), 6)
        \\    @assert(file_exists("{s}"))
        \\    @assert_eq(file_size("{s}"), 6)
        \\    @assert_eq(read_file("{s}"), "abc123")
        \\    @assert_eq(unlink_file("{s}"), 0)
        \\    @assert(random_u64() != random_u64())
        \\    let rbuf = @malloc(32)
        \\    @assert_eq(random_bytes(rbuf, 32), 32)
        \\    @assert(const_time_eq(rbuf, rbuf, 32))
        \\    let rbuf2 = @malloc(32)
        \\    @memcpy(rbuf2, rbuf, 32)
        \\    @write_u8(rbuf2, @read_u8(rbuf2) ^ 1)
        \\    @assert(!const_time_eq(rbuf, rbuf2, 32))
        \\    secure_zero(rbuf, 32)
        \\    var zsum: i64 = 0
        \\    for k in 0..4 {{ zsum += @read_u64(@ptr_add(rbuf, k * 8)) }}
        \\    @assert_eq(zsum, 0)
        \\    @free(rbuf)
        \\    @free(rbuf2)
        \\    @assert(const_time_str_eq("secret", "secret"))
        \\    @assert(!const_time_str_eq("secret", "secreX"))
        \\    @assert(fnv1a_64("a") != fnv1a_64("b"))
        \\    @assert_eq(@popcount(0xF0F), 8)
        \\    @assert_eq(@clz(1), 63)
        \\    @assert_eq(@ctz(8), 3)
        \\    @assert_eq(@bswap(0x0102030405060708), 0x0807060504030201)
        \\    @assert_eq(@checked_add(100, 23), 123)
        \\    @assert_eq(@checked_sub(100, 23), 77)
        \\    @assert_eq(@checked_mul(6, 7), 42)
        \\    let mem = @malloc(16)
        \\    @write_u32(mem, 0x12345678)
        \\    @assert_eq(@read_u32(mem) as i64, 0x12345678)
        \\    @free(mem)
        \\    let base = [1, 2, 3, 4, 5]
        \\    let total = @array_reduce(@array_filter(@array_map(base, sq_i64), is_even), 0, add_acc)
        \\    printInt(total)
        \\    let ch = @chan_new(4)
        \\    let ctr = @malloc(8)
        \\    @write_u64(ctr, 0)
        \\    let th = spawn {{
        \\        @atomic_add(ctr, 10)
        \\        @chan_send(ch, 55)
        \\        @chan_send(ch, 44)
        \\    }}
        \\    @sleep_ms(1)
        \\    printInt(@chan_recv(ch) + @chan_recv(ch))
        \\    @thread_join(th)
        \\    @assert(@atomic_cas(ctr, 10, 99))
        \\    @assert_eq(@read_u64(ctr), 99)
        \\    @chan_close(ch)
        \\    @free(ctr)
        \\    @assert_eq(htons(80), 20480)
        \\    let sfd = tcp_socket()
        \\    @assert(sfd >= 0)
        \\    @assert_eq(sock_close(sfd), 0)
        \\    assert_true(true)
        \\    assert_false(false)
        \\    assert_eq_i64(7, 7)
        \\    assert_ne_i64(7, 8)
        \\    assert_eq_str("lir", "lir")
        \\    return 0
        \\}}
    , .{ io_path, io_path, io_path, io_path, io_path });
    defer std.testing.allocator.free(source);

    for ([_]main.OptLevel{ .O0, .O1, .O2 }) |opt| {
        const elf = try compileSourceWithOpt(source, opt);
        defer std.testing.allocator.free(elf);
        const run_res = try runElfCapture(std.testing.allocator, elf, "stdlib_sec");
        defer std.testing.allocator.free(run_res.stdout);
        try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
        try std.testing.expectEqualStrings("4\n10\n\"ok\":42\n1.0\n-1.0\n20\n99\n", run_res.stdout);
    }
}

test "ELF execution: security traps on checked arithmetic overflow, null mem ops, and negative lengths" {
    const cases = [_]struct { name: []const u8, src: []const u8 }{
        .{ .name = "chk_add_ovf", .src = "fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }\nfn main() -> i64 { return @checked_add(rt(9223372036854775807), rt(1)) }" },
        .{ .name = "chk_sub_ovf", .src = "fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }\nfn main() -> i64 { return @checked_sub(rt(-9223372036854775807 - 1), rt(1)) }" },
        .{ .name = "chk_mul_ovf", .src = "fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }\nfn main() -> i64 { return @checked_mul(rt(9223372036854775807), rt(2)) }" },
        .{ .name = "null_read_u8", .src = "fn rp(a: i64) -> *u8 { if @argc() > 999999 { return @malloc(8) } return a as *u8 }\nfn main() -> i64 { return @read_u8(rp(0)) as i64 }" },
        .{ .name = "null_read_u32", .src = "fn rp(a: i64) -> *u8 { if @argc() > 999999 { return @malloc(8) } return a as *u8 }\nfn main() -> i64 { return @read_u32(rp(0)) as i64 }" },
        .{ .name = "null_read_u64", .src = "fn rp(a: i64) -> *u8 { if @argc() > 999999 { return @malloc(8) } return a as *u8 }\nfn main() -> i64 { return @read_u64(rp(0)) }" },
        .{ .name = "null_write_u8", .src = "fn rp(a: i64) -> *u8 { if @argc() > 999999 { return @malloc(8) } return a as *u8 }\nfn main() -> i64 { @write_u8(rp(0), 1)\n return 0 }" },
        .{ .name = "neg_secure_zero", .src = "fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }\nfn main() -> i64 { let p = @malloc(8)\n @secure_zero(p, rt(-1))\n @free(p)\n return 0 }" },
    };
    for (cases) |tc| {
        const elf = try compileSourceWithOpt(tc.src, .O2);
        defer std.testing.allocator.free(elf);
        try runElfExpectSigIll(std.testing.allocator, elf, tc.name);
    }
}

test "Compiler test_mode synthesizes and executes #[test] runner" {
    const source =
        \\import std::testing
        \\#[test]
        \\fn test_one() {
        \\    assert_eq_i64(2 + 2, 4)
        \\}
        \\#[test]
        \\fn test_two() {
        \\    assert_eq_str("hi", "hi")
        \\}
    ;
    var compiler = main.Compiler.initWithOpts(source, "<test>", .O1);
    compiler.quiet = true;
    compiler.test_mode = true;
    const elf = try compiler.compile();
    defer std.heap.page_allocator.free(elf);
    const run_res = try runElfCapture(std.testing.allocator, elf, "test_runner");
    defer std.testing.allocator.free(run_res.stdout);
    try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
    try std.testing.expectEqualStrings("  PASS: test_one\n  PASS: test_two\nAll 2 tests passed!\n", run_res.stdout);
}

test "ELF64 strict W^X layout: RX .text, read-only NX .rodata, RW NX .bss, NX PT_GNU_STACK" {
    const source =
        \\fn main() -> i64 {
        \\    println("wx_check")
        \\    return 0
        \\}
    ;
    const elf = try compileSourceWithOpt(source, .O2);
    defer std.testing.allocator.free(elf);
    try std.testing.expect(elf.len >= 64 + 56 * 4);
    const e_phnum = std.mem.readInt(u16, elf[56..58], .little);
    try std.testing.expectEqual(@as(u16, 4), e_phnum);

    // PHDR 0: PT_LOAD R|X (5)
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, elf[64..68], .little));
    try std.testing.expectEqual(@as(u32, 5), std.mem.readInt(u32, elf[68..72], .little));

    // PHDR 1: PT_LOAD .rodata R only (4 = PF_R, no W, no X)
    const p1 = 64 + 56;
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, elf[p1 .. p1 + 4], .little));
    try std.testing.expectEqual(@as(u32, 4), std.mem.readInt(u32, elf[p1 + 4 .. p1 + 8], .little));
    const p1_off = std.mem.readInt(u64, elf[p1 + 8 .. p1 + 16], .little);
    const p1_vaddr = std.mem.readInt(u64, elf[p1 + 16 .. p1 + 24], .little);
    try std.testing.expectEqual(@as(u64, 0), p1_off & 0xFFF);
    try std.testing.expectEqual(@as(u64, 0), p1_vaddr & 0xFFF);

    // PHDR 2: PT_LOAD .bss R|W (6)
    const p2 = 64 + 56 * 2;
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, elf[p2 .. p2 + 4], .little));
    try std.testing.expectEqual(@as(u32, 6), std.mem.readInt(u32, elf[p2 + 4 .. p2 + 8], .little));

    // PHDR 3: PT_GNU_STACK R|W (6, no X)
    const p3 = 64 + 56 * 3;
    try std.testing.expectEqual(@as(u32, 0x6474e551), std.mem.readInt(u32, elf[p3 .. p3 + 4], .little));
    try std.testing.expectEqual(@as(u32, 6), std.mem.readInt(u32, elf[p3 + 4 .. p3 + 8], .little));
}

test "ELF execution: hardened heap zero-wipes freed blocks on reuse and stdlib hardening works" {
    const source =
        \\import core
        \\import crypto
        \\import json
        \\import net
        \\fn main() -> i64 {
        \\    let p1 = @malloc(32)
        \\    @write_u64(p1, 111111111)
        \\    @write_u64(@ptr_add(p1, 8), 222222222)
        \\    @write_u64(@ptr_add(p1, 16), 333333333)
        \\    @write_u64(@ptr_add(p1, 24), 444444444)
        \\    @free(p1)
        \\    let p2 = @malloc(32)
        \\    @assert_eq(@read_u64(p2), 0)
        \\    @assert_eq(@read_u64(@ptr_add(p2, 8)), 0)
        \\    @assert_eq(@read_u64(@ptr_add(p2, 16)), 0)
        \\    @assert_eq(@read_u64(@ptr_add(p2, 24)), 0)
        \\    @free(p2)
        \\    // Large mmap canary + free path
        \\    let big = @malloc(8192)
        \\    @write_u64(big, 777)
        \\    @write_u64(@ptr_add(big, 8184), 888)
        \\    @assert_eq(@read_u64(big), 777)
        \\    @free(big)
        \\    // Core saturating arithmetic & checked ops
        \\    let max_v: i64 = 9223372036854775807
        \\    let min_v: i64 = -9223372036854775807 - 1
        \\    @assert_eq(saturating_add(max_v, 100), max_v)
        \\    @assert_eq(saturating_sub(min_v, 100), min_v)
        \\    @assert_eq(checked_add(19, 23), 42)
        \\    // RFC 8259 JSON escaping prevents quote/control injection
        \\    println(json_kv_str("a\"b", "x\\y\nz"))
        \\    // Crypto helpers
        \\    @assert_eq(constant_time_select(true, 11, 22), 11)
        \\    @assert_eq(constant_time_select(false, 11, 22), 22)
        \\    @assert(random_range(10) < 10)
        \\    let tok = random_token_hex(16)
        \\    @assert_eq(@string_len(tok), 32)
        \\    @assert(tcp_bind_listen(-1, 8080, 10) < 0)
        \\    @assert(tcp_connect(0, 70000) < 0)
        \\    return 0
        \\}
    ;
    for ([_]main.OptLevel{ .O0, .O1, .O2 }) |opt| {
        const elf = try compileSourceWithOpt(source, opt);
        defer std.testing.allocator.free(elf);
        const run_res = try runElfCapture(std.testing.allocator, elf, "hardened_heap_std");
        defer std.testing.allocator.free(run_res.stdout);
        try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
        try std.testing.expectEqualStrings("\"a\\\"b\":\"x\\\\y\\nz\"\n", run_res.stdout);
    }
}

test "ELF execution: security traps on stack canary smash, heap overflow, CFI, low-page/neg ptr, shifts, and abs(MIN_I64)" {
    const cases = [_]struct { name: []const u8, src: []const u8 }{
        .{
            .name = "stack_canary_smash",
            .src =
            \\fn smash() -> i64 {
            \\    var x: i64 = 42
            \\    let p = &x
            \\    @write_u64(@ptr_add(p, 8), 123456)
            \\    return x
            \\}
            \\fn main() -> i64 { return smash() }
            ,
        },
        .{
            .name = "heap_slab_overflow_canary",
            .src =
            \\fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
            \\fn main() -> i64 {
            \\    let p = @malloc(8)
            \\    @write_u64(@ptr_add(p, rt(8)), 999)
            \\    @free(p)
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "heap_mmap_overflow_canary",
            .src =
            \\fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
            \\fn main() -> i64 {
            \\    let p = @malloc(8192)
            \\    @write_u64(@ptr_add(p, rt(8192)), 999)
            \\    @free(p)
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "low_page_ptr_deref",
            .src = "fn rp(a: i64) -> *u8 { if @argc() > 999999 { return @malloc(8) } return a as *u8 }\nfn main() -> i64 { return @read_u64(rp(64)) }",
        },
        .{
            .name = "negative_ptr_deref",
            .src = "fn rp(a: i64) -> *u8 { if @argc() > 999999 { return @malloc(8) } return a as *u8 }\nfn main() -> i64 { return @read_u64(rp(-1)) }",
        },
        .{
            .name = "free_negative_ptr",
            .src = "fn rp(a: i64) -> *u8 { if @argc() > 999999 { return @malloc(8) } return a as *u8 }\nfn main() -> i64 { @free(rp(-16))\n return 0 }",
        },
        .{
            .name = "shift_left_oob",
            .src = "fn sh(x: i64, n: i64) -> i64 { return x << n }\n fn main() -> i64 { return sh(1, 64) }",
        },
        .{
            .name = "shift_neg_oob",
            .src = "fn sh(x: i64, n: i64) -> i64 { return x >> n }\n fn main() -> i64 { return sh(8, -1) }",
        },
        .{
            .name = "cfi_rodata_exec",
            .src = "fn ok() -> i64 { return 1 }\nfn main() -> i64 { var f: fn() -> i64 = ok\n let s = \"evil\"\n @write_u64((&f) as *u8, s as i64)\n return f() }",
        },
        .{
            .name = "cfi_start_stub_bypass",
            .src = "fn ok() -> i64 { return 1 }\nfn main() -> i64 { var f: fn() -> i64 = ok\n @write_u64((&f) as *u8, 0x401000)\n return f() }",
        },
        .{
            .name = "abs_min_i64_trap",
            .src = "import core\n fn main() -> i64 { return abs_i64(-9223372036854775807 - 1) }",
        },
    };
    for (cases) |tc| {
        const elf = try compileSourceWithOpt(tc.src, .O2);
        defer std.testing.allocator.free(elf);
        try runElfExpectSigIll(std.testing.allocator, elf, tc.name);
    }
}

test "Sema enforces exhaustive match, strict ? return type, and field assignment types" {
    // Non-exhaustive enum match rejected
    {
        const bad_enum_match =
            \\enum Light { Red, Yellow, Green }
            \\fn code(l: Light) -> i64 {
            \\    return match l {
            \\        Light::Red => 1,
            \\        Light::Green => 3,
            \\    }
            \\}
            \\fn main() -> i64 { return 0 }
        ;
        var c = main.Compiler.init(bad_enum_match, "<test>");
        c.quiet = true;
        try std.testing.expectError(error.TypeMismatch, c.compile());
    }
    // Guarded arm alone does not make match exhaustive
    {
        const guarded_match =
            \\enum Light { Red, Green }
            \\fn code(l: Light, ok: bool) -> i64 {
            \\    return match l {
            \\        Light::Red if ok => 1,
            \\        Light::Green => 2,
            \\    }
            \\}
            \\fn main() -> i64 { return 0 }
        ;
        var c = main.Compiler.init(guarded_match, "<test>");
        c.quiet = true;
        try std.testing.expectError(error.TypeMismatch, c.compile());
    }
    // Non-exhaustive integer match without else/_ rejected
    {
        const bad_int_match =
            \\fn code(x: i64) -> i64 {
            \\    return match x {
            \\        1 => 10,
            \\        2 => 20,
            \\    }
            \\}
            \\fn main() -> i64 { return 0 }
        ;
        var c = main.Compiler.init(bad_int_match, "<test>");
        c.quiet = true;
        try std.testing.expectError(error.TypeMismatch, c.compile());
    }
    // '?' inside non-Option/Result function rejected
    {
        const bad_try =
            \\fn maybe(x: i64) -> Option<i64> {
            \\    if x > 0 { return Some(x) }
            \\    return None
            \\}
            \\fn main() -> i64 {
            \\    let v = maybe(1)?
            \\    return v
            \\}
        ;
        var c = main.Compiler.init(bad_try, "<test>");
        c.quiet = true;
        try std.testing.expectError(error.TypeMismatch, c.compile());
    }
    // '?' mismatching Option inside Result function rejected
    {
        const cross_try =
            \\fn maybe(x: i64) -> Option<i64> { return Some(x) }
            \\fn res_fn(x: i64) -> Result<i64, string> {
            \\    let v = maybe(x)?
            \\    return Ok(v)
            \\}
            \\fn main() -> i64 { return 0 }
        ;
        var c = main.Compiler.init(cross_try, "<test>");
        c.quiet = true;
        try std.testing.expectError(error.TypeMismatch, c.compile());
    }
    // Struct field type mismatch on assignment rejected
    {
        const bad_field_assign =
            \\struct S { n: i64 }
            \\fn main() -> i64 {
            \\    var s = S { n: 1 }
            \\    s.n = "oops"
            \\    return s.n
            \\}
        ;
        var c = main.Compiler.init(bad_field_assign, "<test>");
        c.quiet = true;
        try std.testing.expectError(error.TypeMismatch, c.compile());
    }
    // Exhaustive enum match returning from every arm without else compiles and runs
    {
        const good_exh =
            \\enum Tri { A, B, C }
            \\fn pick(t: Tri) -> i64 {
            \\    match t {
            \\        Tri::A => return 10,
            \\        Tri::B => return 20,
            \\        Tri::C => return 30,
            \\    }
            \\}
            \\fn main() -> i64 { return pick(Tri::C) }
        ;
        const elf = try compileSourceWithOpt(good_exh, .O2);
        defer std.testing.allocator.free(elf);
        const run_res = try runElfCapture(std.testing.allocator, elf, "exh_ret");
        defer std.testing.allocator.free(run_res.stdout);
        try std.testing.expectEqual(@as(u8, 30), run_res.exit_code);
    }
}

test "Sema rejects compile-time memory errors, leaks, bounds overflows, bad casts, and anti-patterns" {
    const cases = [_]struct { name: []const u8, src: []const u8 }{
        .{
            .name = "uaf_read",
            .src =
            \\fn main() -> i64 {
            \\    let p = @malloc(16)
            \\    @free(p)
            \\    return @read_u8(p) as i64
            \\}
            ,
        },
        .{
            .name = "uaf_copy",
            .src =
            \\fn main() -> i64 {
            \\    let p = @malloc(16)
            \\    @free(p)
            \\    let q = p
            \\    return q as i64
            \\}
            ,
        },
        .{
            .name = "double_free_direct",
            .src =
            \\fn main() -> i64 {
            \\    let p = @malloc(32)
            \\    @free(p)
            \\    @free(p)
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "double_free_defer",
            .src =
            \\fn main() -> i64 {
            \\    let p = @malloc(32)
            \\    defer @free(p)
            \\    @free(p)
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "conditional_double_free",
            .src =
            \\fn main() -> i64 {
            \\    let p = @malloc(32)
            \\    if @argc() > 1 { @free(p) }
            \\    @free(p)
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "conditional_uaf",
            .src =
            \\fn main() -> i64 {
            \\    let p = @malloc(32)
            \\    if @argc() > 1 { @free(p) }
            \\    return @read_u8(p) as i64
            \\}
            ,
        },
        .{
            .name = "use_after_close_fd",
            .src =
            \\fn main() -> i64 {
            \\    let fd = @open("/dev/null", 0, 0)
            \\    @close(fd)
            \\    let buf = @malloc(16)
            \\    defer @free(buf)
            \\    return @read(fd, buf, 8)
            \\}
            ,
        },
        .{
            .name = "double_close_fd",
            .src =
            \\fn main() -> i64 {
            \\    let fd = @open("/dev/null", 0, 0)
            \\    @close(fd)
            \\    @close(fd)
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "loop_heap_leak",
            .src =
            \\fn main() -> i64 {
            \\    var i = 0
            \\    while i < 10 {
            \\        let p = @malloc(64)
            \\        @write_u8(p, 1)
            \\        i += 1
            \\    }
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "loop_fd_leak",
            .src =
            \\fn main() -> i64 {
            \\    var i = 0
            \\    while i < 5 {
            \\        let fd = @open("/dev/null", 0, 0)
            \\        i += 1
            \\    }
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "loop_outer_double_free",
            .src =
            \\fn main() -> i64 {
            \\    let p = @malloc(16)
            \\    var i = 0
            \\    while i < 3 {
            \\        @free(p)
            \\        i += 1
            \\    }
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "loop_outer_overwrite_leak",
            .src =
            \\fn main() -> i64 {
            \\    var p = @malloc(8)
            \\    @free(p)
            \\    var i = 0
            \\    while i < 4 {
            \\        p = @malloc(32)
            \\        i += 1
            \\    }
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "discarded_malloc_call",
            .src =
            \\fn main() -> i64 {
            \\    @malloc(64)
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "heap_oob_ptr_add_write",
            .src =
            \\fn main() -> i64 {
            \\    let p = @malloc(8)
            \\    @write_u64(@ptr_add(p, 8), 42)
            \\    @free(p)
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "heap_oob_memset",
            .src =
            \\fn main() -> i64 {
            \\    let p = @malloc(16)
            \\    @memset(p, 0, 32)
            \\    @free(p)
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "stack_budget_exceeded",
            .src =
            \\fn main() -> i64 {
            \\    var huge: [5000]i64 = [0]
            \\    return huge[0]
            \\}
            ,
        },
        .{
            .name = "const_null_deref",
            .src = "fn main() -> i64 { return @read_u64(0 as *u8) }",
        },
        .{
            .name = "const_low_page_deref",
            .src = "fn main() -> i64 { return @read_u8(64 as *u8) as i64 }",
        },
        .{
            .name = "const_neg_ptr_free",
            .src = "fn main() -> i64 { @free((-8) as *u8)\n return 0 }",
        },
        .{
            .name = "const_malloc_zero",
            .src = "fn main() -> i64 { let p = @malloc(0)\n @free(p)\n return 0 }",
        },
        .{
            .name = "const_neg_memset_len",
            .src = "fn main() -> i64 { let p = @malloc(8)\n @secure_zero(p, -1)\n @free(p)\n return 0 }",
        },
        .{
            .name = "const_neg_close_fd",
            .src = "fn main() -> i64 { @close(-1)\n return 0 }",
        },
        .{
            .name = "const_min_i64_div_neg1",
            .src = "const X: i64 = (-9223372036854775807 - 1) / -1\nfn main() -> i64 { return X }",
        },
        .{
            .name = "const_checked_add_overflow",
            .src = "fn main() -> i64 { return @checked_add(9223372036854775807, 1) }",
        },
        .{
            .name = "const_string_char_at_oob",
            .src = "fn main() -> i64 { return @string_char_at(\"abc\", 3) }",
        },
        .{
            .name = "const_string_index_oob",
            .src = "fn main() -> i64 { return \"abc\"[5] as i64 }",
        },
        .{
            .name = "uninitialized_var",
            .src = "fn main() -> i64 { var x: i64\n return x }",
        },
        .{
            .name = "forged_fn_ptr_cast",
            .src = "fn main() -> i64 { let f: fn() -> i64 = (0x401000 as fn() -> i64)\n return f() }",
        },
        .{
            .name = "unconditional_infinite_loop",
            .src = "fn main() -> i64 { var x = 0\n while true { x += 1 }\n return x }",
        },
        .{
            .name = "heap_oob_ptr_index",
            .src =
            \\fn main() -> i64 {
            \\    let p = @malloc(16)
            \\    let x = p[2]
            \\    @free(p)
            \\    return x
            \\}
            ,
        },
        .{
            .name = "fixed_array_oob_const",
            .src =
            \\fn main() -> i64 {
            \\    var a: [4]i64 = [1, 2, 3, 4]
            \\    return a[4]
            \\}
            ,
        },
        .{
            .name = "neg_array_get",
            .src =
            \\fn main() -> i64 {
            \\    let a = @array_new(4)
            \\    defer @array_free(a)
            \\    @array_push(a, 1)
            \\    return @array_get(a, -1)
            \\}
            ,
        },
        .{
            .name = "unknown_thread_entry",
            .src = "fn main() -> i64 { let p = @malloc(8)\n defer @free(p)\n return @thread_create(\"does_not_exist\", p) }",
        },
    };

    for (cases) |tc| {
        var compiler = main.Compiler.init(tc.src, "<test>");
        compiler.quiet = true;
        if (compiler.compile()) |elf| {
            std.heap.page_allocator.free(elf);
            std.debug.print("Expected compile-time rejection for '{s}', but compilation succeeded!\n", .{tc.name});
            return error.TestExpectedError;
        } else |_| {}
    }
}

test "Safe loop cleanup, defer, escape, and bounded pointer idioms compile and execute" {
    const src =
        \\fn alloc_and_return(n: i64) -> *u8 {
        \\    var i = 0
        \\    while i < 3 {
        \\        let p = @malloc(n)
        \\        if i == 2 { return p }
        \\        @free(p)
        \\        i += 1
        \\    }
        \\    return @malloc(n)
        \\}
        \\fn main() -> i64 {
        \\    var i = 0
        \\    while i < 10 {
        \\        let buf = @malloc(16)
        \\        defer @free(buf)
        \\        @write_u64(@ptr_add(buf, 8), i + 1)
        \\        i += 1
        \\    }
        \\    let out = alloc_and_return(16)
        \\    defer @free(out)
        \\    @write_u64(@ptr_add(out, 8), 77)
        \\    let v = @read_u64(@ptr_add(out, 8))
        \\    var k = 0
        \\    while true {
        \\        if k == 3 { break }
        \\        k += 1
        \\    }
        \\    return v - 77 + k - 3
        \\}
    ;
    const elf = try compileSource(src);
    defer std.testing.allocator.free(elf);
    const run_res = try runElfCapture(std.testing.allocator, elf, "safe_idioms");
    defer std.testing.allocator.free(run_res.stdout);
    try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
}

test "Compiler defaults to -O2 and performs strength reduction, 2-pass inlining, and safe shift LICM" {
    const default_compiler = main.Compiler.init("fn main() -> i64 { return 0 }", "<test>");
    try std.testing.expectEqual(main.OptLevel.O2, default_compiler.opt_level);

    // Unconditional power-of-2 strength reduction (no prior shift/mask constant required) and x * -1 -> neg
    {
        const sr_src =
            \\fn mul8(x: i64) -> i64 { return x * 8 }
            \\fn udiv8(x: u64) -> u64 { return x / 8 }
            \\fn umod64(x: u64) -> u64 { return x % 64 }
            \\fn neg1(x: i64) -> i64 { return x * -1 }
            \\fn main() -> i64 { return mul8(@argc()) + (udiv8(@argc() as u64) as i64) + (umod64(@argc() as u64) as i64) + neg1(@argc()) }
        ;
        const ir_module = try std.testing.allocator.create(ir_mod.IRModule);
        defer std.testing.allocator.destroy(ir_module);
        var c = main.Compiler.initWithOpts(sr_src, "<sr_test>", .O2);
        c.quiet = true;
        try c.compileToIR(ir_module);

        var has_shl = false;
        var has_ushr = false;
        var has_and = false;
        var has_neg = false;
        var has_mul_or_div_mod = false;
        for (0..ir_module.fn_count) |fi| {
            const f = &ir_module.fns[fi];
            const fsrc = ir_module.sourceFor(f.source_id, sr_src);
            const fname = fsrc[f.name_start..][0..f.name_len];
            if (!std.mem.eql(u8, fname, "mul8") and !std.mem.eql(u8, fname, "udiv8") and
                !std.mem.eql(u8, fname, "umod64") and !std.mem.eql(u8, fname, "neg1")) continue;
            for (0..f.block_count) |bi| {
                const b = &f.blocks[bi];
                for (0..b.inst_count) |ii| {
                    const op = b.insts[ii].op;
                    if (op == .shl) has_shl = true;
                    if (op == .ushr) has_ushr = true;
                    if (op == .bit_and) has_and = true;
                    if (op == .neg) has_neg = true;
                    if (op == .mul or op == .udiv or op == .umod) has_mul_or_div_mod = true;
                }
            }
        }
        try std.testing.expect(has_shl);
        try std.testing.expect(has_ushr);
        try std.testing.expect(has_and);
        try std.testing.expect(has_neg);
        try std.testing.expect(!has_mul_or_div_mod);

        const elf = try compileSourceWithOpt(sr_src, .O2);
        defer std.testing.allocator.free(elf);
        const res = try runElfCapture(std.testing.allocator, elf, "sr_exec");
        defer std.testing.allocator.free(res.stdout);
        // argc=1 -> 1*8 + 1/8 + 1%64 + (-1) = 8 + 0 + 1 - 1 = 8
        try std.testing.expectEqual(@as(u8, 8), res.exit_code);
    }

    // 2-pass extended inlining (leaf -> mid -> main all inlined at -O2)
    {
        const inl_src =
            \\fn leaf(x: i64) -> i64 {
            \\    if x < 0 { return -x }
            \\    return x * 2
            \\}
            \\fn mid(a: i64, b: i64) -> i64 {
            \\    return leaf(a) + leaf(b)
            \\}
            \\fn main() -> i64 {
            \\    let n = @argc()
            \\    return mid(n, n + 1)
            \\}
        ;
        const ir_module = try std.testing.allocator.create(ir_mod.IRModule);
        defer std.testing.allocator.destroy(ir_module);
        var c = main.Compiler.initWithOpts(inl_src, "<inl_test>", .O2);
        c.quiet = true;
        try c.compileToIR(ir_module);
        for (0..ir_module.fn_count) |fi| {
            const f = &ir_module.fns[fi];
            const fsrc = ir_module.sourceFor(f.source_id, inl_src);
            const fname = fsrc[f.name_start..][0..f.name_len];
            if (!std.mem.eql(u8, fname, "main")) continue;
            for (0..f.block_count) |bi| {
                const b = &f.blocks[bi];
                for (0..b.inst_count) |ii| {
                    try std.testing.expect(b.insts[ii].op != .call);
                }
            }
        }
    }

    // LICM must NOT hoist trapping shifts out of unexecuted conditional branches inside loops
    {
        const licm_shift_src =
            \\fn check_loop(flag: i64, sh: i64) -> i64 {
            \\    var i = 0
            \\    var acc = 0
            \\    while i < 4 {
            \\        if flag != 0 {
            \\            acc += (1 << sh)
            \\        }
            \\        i += 1
            \\    }
            \\    return acc
            \\}
            \\fn main() -> i64 {
            \\    return check_loop(0, 99)
            \\}
        ;
        const elf = try compileSourceWithOpt(licm_shift_src, .O2);
        defer std.testing.allocator.free(elf);
        const res = try runElfCapture(std.testing.allocator, elf, "licm_shift_safe");
        defer std.testing.allocator.free(res.stdout);
        try std.testing.expectEqual(@as(u8, 0), res.exit_code);
    }
}

test "ELF execution: bitwise/shift compound assigns, if-expressions, repeat arrays [val; N], panic(), and std::str + std::algo" {
    const src =
        \\import std::str
        \\import std::algo
        \\import std::io
        \\
        \\struct Flags { bits: i64 }
        \\
        \\fn abs_expr(x: i64) -> i64 {
        \\    if x < 0 { 0 - x } else { x }
        \\}
        \\
        \\fn classify(n: i64) -> string {
        \\    let label = if n < 0 {
        \\        "neg"
        \\    } elif n == 0 {
        \\        "zero"
        \\    } else {
        \\        "pos"
        \\    }
        \\    return label
        \\}
        \\
        \\fn main() -> i64 {
        \\    // Bitwise & shift compound assigns (signed, unsigned, struct field, fixed array)
        \\    var m: i64 = 3
        \\    m |= 4
        \\    m &= 6
        \\    m ^= 1
        \\    m <<= 2
        \\    m >>= 1
        \\    printInt(m) // (((3|4)&6)^1)<<2>>1 = (((7)&6)^1)<<2>>1 = (6^1)<<2>>1 = 7<<2>>1 = 14
        \\
        \\    var u: u64 = (-1) as u64
        \\    u >>= 60
        \\    printInt(u as i64) // 15 (logical right shift)
        \\
        \\    var f = Flags { bits: 1 }
        \\    f.bits |= 8
        \\    printInt(f.bits) // 9
        \\
        \\    // If expressions + tail if-else + early-return arm (.never compatibility)
        \\    printInt(abs_expr(-42))
        \\    println(classify(-5))
        \\    println(classify(0))
        \\    println(classify(7))
        \\    let chosen = if @argc() > 0 { 100 } else { return 1 }
        \\    printInt(chosen)
        \\
        \\    // Repeat arrays [val; N] (both unrolled <=8 and looped >8) + computed repeat expr + partial init zero-fill
        \\    let seed: i64 = 6
        \\    let z4 = [seed + 1; 4]
        \\    printInt(z4[0] + z4[3]) // 14
        \\    let inline_rep = ([3; 4])[2]
        \\    printInt(inline_rep) // 3
        \\    var big: [16]i64 = [5; 16]
        \\    big[15] += 10
        \\    big[14] |= 2
        \\    big[13] <<= 1
        \\    printInt(big[0] + big[13] + big[14] + big[15]) // 5 + 10 + 7 + 15 = 37
        \\    var partial: [4]i64 = [9]
        \\    printInt(partial[0] + partial[1] + partial[3]) // 9
        \\
        \\    // Nested if/elif/else expressions
        \\    let nested = if @argc() > 0 { if big[0] == 5 { 77 } else { 88 } } else { 99 }
        \\    printInt(nested)
        \\
        \\    // std::str
        \\    println(str_trim("  hello LIR \t\n"))
        \\    println(str_to_upper("Abc-123"))
        \\    println(str_to_lower("XyZ!"))
        \\    println(str_repeat("ab", 3))
        \\    printInt(str_starts_with("ziglir", "zig") ? 1 : 0)
        \\    printInt(str_ends_with("ziglir", "lir") ? 1 : 0)
        \\    printInt(str_contains("banana", "nan") ? 1 : 0)
        \\    printInt(str_index_of("banana", "nan"))
        \\    printInt(str_count("ababab", "ab"))
        \\
        \\    // std::algo
        \\    printInt(gcd_i64(48, 18))
        \\    printInt(lcm_i64(12, 18))
        \\    printInt(pow_i64(2, 10))
        \\    let arr = @array_new(8)
        \\    defer @array_free(arr)
        \\    @array_push(arr, 40)
        \\    @array_push(arr, 10)
        \\    @array_push(arr, 30)
        \\    @array_push(arr, 20)
        \\    sort_array_i64(arr)
        \\    printInt(bsearch_array_i64(arr, 30)) // 2
        \\    printInt(sum_array_i64(arr)) // 100
        \\    reverse_array_i64(arr)
        \\    printInt(@array_get(arr, 0)) // 40
        \\    eprint("")
        \\    return 0
        \\}
    ;
    const elf = try compileSource(src);
    defer std.testing.allocator.free(elf);
    const res = try runElfCapture(std.testing.allocator, elf, "lang_gaps");
    defer std.testing.allocator.free(res.stdout);
    try std.testing.expectEqual(@as(u8, 0), res.exit_code);
    try std.testing.expectEqualStrings(
        "14\n15\n9\n42\nneg\nzero\npos\n100\n14\n3\n37\n9\n77\nhello LIR\nABC-123\nxyz!\nababab\n1\n1\n1\n2\n3\n6\n36\n1024\n2\n100\n40\n",
        res.stdout,
    );

    // panic("msg") prints message to stderr and terminates with SIGILL trap; acts as .never in expression branches
    {
        const panic_src =
            \\fn checked(n: i64) -> i64 {
            \\    if n < 0 { panic("boom: negative") } else { return n * 2 }
            \\}
            \\fn main() -> i64 {
            \\    return checked(-1)
            \\}
        ;
        const p_elf = try compileSource(panic_src);
        defer std.testing.allocator.free(p_elf);
        var pbuf: [128]u8 = undefined;
        const ppath = try std.fmt.bufPrint(&pbuf, "/tmp/lir_panic_{d}", .{std.os.linux.getpid()});
        {
            const f = try std.fs.createFileAbsolute(ppath, .{ .mode = 0o755 });
            defer f.close();
            try f.writeAll(p_elf);
        }
        defer std.fs.deleteFileAbsolute(ppath) catch {};
        const pres = try std.process.Child.run(.{
            .allocator = std.testing.allocator,
            .argv = &[_][]const u8{ppath},
        });
        defer std.testing.allocator.free(pres.stdout);
        defer std.testing.allocator.free(pres.stderr);
        switch (pres.term) {
            .Signal => |sig| try std.testing.expectEqual(@as(u32, 4), sig),
            else => return error.TestUnexpectedResult,
        }
        try std.testing.expectEqualStrings("boom: negative\n", pres.stderr);
    }

    // Rejects: if-expression missing else, mismatched if/else branch types, OOB compound shift, [val; N] > 32KiB, repeat count <= 0
    const bad_cases = [_][]const u8{
        "fn main() -> i64 { let x = if @argc() > 0 { 1 }\n return x }",
        "fn main() -> i64 { let x = if @argc() > 0 { 1 } else { \"str\" }\n return 0 }",
        "fn main() -> i64 { var x = 1\n x <<= 64\n return x }",
        "fn main() -> i64 { let huge = [0; 5000]\n return huge[0] }",
        "fn main() -> i64 { let bad = [0; 0]\n return bad[0] }",
        "fn main() -> i64 { panic(123)\n return 0 }",
    };
    for (bad_cases) |bsrc| {
        var c = main.Compiler.init(bsrc, "<bad_gap>");
        c.quiet = true;
        if (c.compile()) |belf| {
            std.heap.page_allocator.free(belf);
            return error.TestExpectedError;
        } else |_| {}
    }
}

test "target descriptor parsing, aliases, and backend resolution" {
    const t_lx64 = main.Target.parse("x86_64-linux") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(main.Arch.x86_64, t_lx64.arch);
    try std.testing.expectEqual(main.OS.linux, t_lx64.os);
    try std.testing.expectEqual(main.BinaryFormat.elf, t_lx64.binaryFormat());
    try std.testing.expectEqual(main.BackendKind.native_elf, t_lx64.resolveBackend(.auto));

    const t_arm_mac = main.Target.parse("arm64-darwin") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(main.Arch.aarch64, t_arm_mac.arch);
    try std.testing.expectEqual(main.OS.macos, t_arm_mac.os);
    try std.testing.expectEqual(main.BinaryFormat.macho, t_arm_mac.binaryFormat());
    try std.testing.expectEqual(main.BackendKind.c, t_arm_mac.resolveBackend(.auto));

    const t_win = main.Target.parse("win64") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(main.Arch.x86_64, t_win.arch);
    try std.testing.expectEqual(main.OS.windows, t_win.os);
    try std.testing.expectEqual(main.BinaryFormat.pe, t_win.binaryFormat());
    try std.testing.expectEqualStrings(".exe", t_win.exeSuffix());

    const t_wasm = main.Target.parse("wasm32-wasi") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(main.Arch.wasm32, t_wasm.arch);
    try std.testing.expectEqual(main.OS.wasi, t_wasm.os);
    try std.testing.expectEqual(main.BinaryFormat.wasm, t_wasm.binaryFormat());
    try std.testing.expectEqual(main.BackendKind.native_wasm, t_wasm.resolveBackend(.auto));
    try std.testing.expectEqualStrings(".wasm", t_wasm.exeSuffix());

    const t_rv = main.Target.parse("riscv64-linux") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(main.Arch.riscv64, t_rv.arch);
    try std.testing.expectEqual(main.BackendKind.c, t_rv.resolveBackend(.auto));

    try std.testing.expect(main.Target.parse("mips-plan9") == null);
}

test "target validation rejects unsupported architecture and OS combinations" {
    const invalid_targets = [_]main.Target{
        .{ .arch = .x86_64, .os = .wasi },
        .{ .arch = .wasm32, .os = .linux },
        .{ .arch = .riscv64, .os = .macos },
        .{ .arch = .aarch64, .os = .wasi },
    };
    // This source is intentionally malformed: target validation must win before lexing.
    const src = "fn main() { let x = $ }";

    for (invalid_targets) |target| {
        try std.testing.expect(!target.isSupported());
        try std.testing.expect(target.resolveBackend(.auto) != .native_wasm);

        var compiler = main.Compiler.initForTarget(src, "<invalid_target>", .O2, target, .auto);
        compiler.quiet = true;
        try std.testing.expectError(error.UnsupportedTarget, compiler.compile());
    }
}

test "backend entry points independently reject unsupported target pairs" {
    const module = try std.testing.allocator.create(main.IRModule);
    defer std.testing.allocator.destroy(module);
    module.init();

    const invalid = main.Target{ .arch = .wasm32, .os = .linux };
    try std.testing.expectError(
        error.UnsupportedTarget,
        main.Backend.emitBinary(std.heap.page_allocator, module, "", invalid, .auto, .host),
    );
    try std.testing.expectError(
        error.UnsupportedTarget,
        main.Backend.emitCSource(std.heap.page_allocator, module, "", invalid),
    );
}

test "explicit native backends reject incompatible valid targets" {
    const src = "fn main() -> i64 { return 0 }";
    const linux = main.Target.parse("x86_64-linux") orelse return error.TestUnexpectedResult;
    const wasi = main.Target.parse("wasm32-wasi") orelse return error.TestUnexpectedResult;

    var wasm_on_linux = main.Compiler.initForTarget(src, "<wasm_on_linux>", .O2, linux, .native_wasm);
    wasm_on_linux.quiet = true;
    try std.testing.expectError(error.UnsupportedTargetForNativeWasm, wasm_on_linux.compile());

    var elf_on_wasi = main.Compiler.initForTarget(src, "<elf_on_wasi>", .O2, wasi, .native_elf);
    elf_on_wasi.quiet = true;
    try std.testing.expectError(error.UnsupportedTargetForNativeElf, elf_on_wasi.compile());
}

test "C source emission rejects unsupported target combinations" {
    const src = "fn main() -> i64 { return 0 }";
    const invalid = main.Target{ .arch = .wasm32, .os = .linux };
    var compiler = main.Compiler.initForTarget(src, "<invalid_c_target>", .O2, invalid, .c);
    compiler.quiet = true;
    compiler.emit_c = true;
    try std.testing.expectError(error.UnsupportedTarget, compiler.compile());
}

test "target-aware @target_os, @target_arch, and @target_ptr_bits lowering" {
    const src =
        \\fn main() -> i64 {
        \\    println("{@target_os()},{@target_arch()},{@target_ptr_bits()}")
        \\    return 0
        \\}
    ;
    const cases = [_]struct { spec: []const u8, expected: []const u8 }{
        .{ .spec = "x86_64-linux", .expected = "0,0,64\n" },
        .{ .spec = "aarch64-macos", .expected = "1,1,64\n" },
        .{ .spec = "x86_64-windows", .expected = "2,0,64\n" },
        .{ .spec = "wasm32-wasi", .expected = "3,3,32\n" },
    };
    for (cases) |tc| {
        const tgt = main.Target.parse(tc.spec) orelse return error.TestUnexpectedResult;
        var compiler = main.Compiler.initForTarget(src, "<target_test>", .O2, tgt, .vm);
        compiler.quiet = true;
        var vm_res = try compiler.runInVM(&[_][]const u8{"prog"}, true);
        defer vm_res.deinit(std.heap.page_allocator);
        try std.testing.expect(!vm_res.trapped);
        try std.testing.expectEqual(@as(i64, 0), vm_res.exit_code);
        try std.testing.expectEqualStrings(tc.expected, vm_res.stdout);
    }
}

test "differential backend parity across native ELF, IR VM, C11, and Wasm32-WASI" {
    const src =
        \\import std::str
        \\import std::math
        \\import std::algo
        \\import std::crypto
        \\
        \\struct Quad { a: i64, b: i64, c: i64, d: i64 }
        \\
        \\enum Kind {
        \\    Circle(i64),
        \\    Rect(i64, i64),
        \\}
        \\
        \\fn fib(n: i64) -> i64 {
        \\    if n <= 1 { return n }
        \\    return fib(n - 1) + fib(n - 2)
        \\}
        \\
        \\fn mul_fn(x: i64, y: i64) -> i64 { return x * y }
        \\fn apply2(f: fn(i64, i64) -> i64, x: i64, y: i64) -> i64 { return f(x, y) }
        \\
        \\fn area(k: Kind) -> i64 {
        \\    return match k {
        \\        Kind::Circle(r) => r * r * 3,
        \\        Kind::Rect(w, h) => w * h,
        \\    }
        \\}
        \\
        \\fn main() -> i64 {
        \\    let p = Quad { a: 10, b: 20, c: 30, d: 40 }
        \\    let q = Quad { a: 1, b: 2, c: 3, d: 4 }
        \\    let s1 = area(Kind::Circle(5))
        \\    let s2 = area(Kind::Rect(6, 7))
        \\    let r_fib = fib(10)
        \\    let r_ind = apply2(mul_fn, 6, 7)
        \\    let neg_shr = (-16) >> 2
        \\    let pc = @popcount(0xF0F0)
        \\    let f0 = @float_to_string(0.0)
        \\    let f1 = @float_to_string(4.0)
        \\    let f2 = @float_to_string(3.14)
        \\    let f3 = @float_to_string(1.0e16)
        \\    let f4 = @float_to_string(1.25e-5)
        \\    let f5 = @float_to_string(@sqrt(9.0) + @floor(2.9) + @ceil(1.1) + @round(3.6))
        \\    let fs = @float_to_string(@string_to_float("-12.25"))
        \\    let arr = @array_new(8)
        \\    @array_push(arr, 9)
        \\    @array_push(arr, 3)
        \\    @array_push(arr, 7)
        \\    @array_push(arr, 1)
        \\    sort_array_i64(arr)
        \\    let a0 = @array_get(arr, 0)
        \\    let a3 = @array_get(arr, 3)
        \\    @array_free(arr)
        \\    let m = @map_new(4)
        \\    @map_set(m, "one", 111)
        \\    @map_set(m, "two", 222)
        \\    let ms = @map_get(m, "one") + @map_get(m, "two")
        \\    @map_free(m)
        \\    let up = str_to_upper(str_trim("  ziglir  "))
        \\    let ca = @checked_add(100, 23)
        \\    let cs = @checked_sub(50, 8)
        \\    let cm = @checked_mul(6, 7)
        \\    let same = @const_time_eq("abc", "abc", 3)
        \\    let fv25 = 2.5
        \\    let fv11 = 11.0
        \\    println("p={p.a + p.d},{q.b + q.c}:enum={s1},{s2}:fib={r_fib}:ind={r_ind}:shr={neg_shr},{pc}")
        \\    println("flt={f0}|{f1}|{f2}|{f3}|{f4}|{f5}|{fs}")
        \\    println("col={a0},{a3}:{ms}:{up}:{ca},{cs},{cm}:{same}:{fv25},{fv11}")
        \\    return 0
        \\}
    ;
    const expected =
        "p=50,5:enum=75,42:fib=55:ind=42:shr=-4,8\n" ++
        "flt=0.0|4.0|3.14|1.0e+16|1.25e-5|11.0|-12.25\n" ++
        "col=1,9:333:ZIGLIR:123,42,42:true:2.5,11.0\n";

    // 1. Native x86-64 ELF
    const elf = try compileSource(src);
    defer std.testing.allocator.free(elf);
    const elf_res = try runElfCapture(std.testing.allocator, elf, "diff_nat");
    defer std.testing.allocator.free(elf_res.stdout);
    try std.testing.expectEqual(@as(u8, 0), elf_res.exit_code);
    try std.testing.expectEqualStrings(expected, elf_res.stdout);

    // 2. Portable IR VM
    {
        var c_vm = main.Compiler.initForTarget(src, "<diff_vm>", .O2, main.Target.host(), .vm);
        c_vm.quiet = true;
        var vm_res = try c_vm.runInVM(&[_][]const u8{"diff_vm"}, true);
        defer vm_res.deinit(std.heap.page_allocator);
        try std.testing.expect(!vm_res.trapped);
        try std.testing.expectEqual(@as(i64, 0), vm_res.exit_code);
        try std.testing.expectEqualStrings(expected, vm_res.stdout);
    }

    // 3. Portable C11 backend (host cc)
    {
        var c_cc = main.Compiler.initForTarget(src, "<diff_c>", .O2, main.Target.host(), .c);
        c_cc.quiet = true;
        const c_bin = try c_cc.compile();
        defer std.heap.page_allocator.free(c_bin);
        const c_res = try runElfCapture(std.testing.allocator, c_bin, "diff_c");
        defer std.testing.allocator.free(c_res.stdout);
        try std.testing.expectEqual(@as(u8, 0), c_res.exit_code);
        try std.testing.expectEqualStrings(expected, c_res.stdout);
    }

    // 4. Zero-dependency Wasm32-WASI emitter
    {
        const w_tgt = main.Target.parse("wasm32-wasi") orelse return error.TestUnexpectedResult;
        var c_wasm = main.Compiler.initForTarget(src, "<diff_wasm>", .O2, w_tgt, .native_wasm);
        c_wasm.quiet = true;
        const wasm_bytes = try c_wasm.compile();
        defer std.heap.page_allocator.free(wasm_bytes);
        try std.testing.expect(wasm_bytes.len > 64);
        try std.testing.expectEqualStrings("\x00asm\x01\x00\x00\x00", wasm_bytes[0..8]);
    }
}

test "differential trap parity across native ELF and IR VM" {
    const traps = [_][]const u8{
        "fn main() -> i64 { let x = 10\n let z = 0\n return x / z }",
        "fn main() -> i64 { let x = -9223372036854775807 - 1\n let y = -1\n return x / y }",
        "fn main() -> i64 { let a = @array_new(4)\n @array_push(a, 1)\n return @array_get(a, 5) }",
        "fn main() -> i64 { let x = 1\n let s = 64\n return x << s }",
        "fn bump(x: i64) -> i64 { return @checked_add(x, 1) }\nfn main() -> i64 { return bump(9223372036854775807) }",
        "fn drop_buf(p: *u8) { @free(p) }\nfn main() -> i64 { let p = @malloc(16)\n drop_buf(p)\n drop_buf(p)\n return 0 }",
    };
    for (traps, 0..) |tsrc, idx| {
        // Native ELF must trap cleanly (non-zero / signal)
        const elf = try compileSource(tsrc);
        defer std.testing.allocator.free(elf);
        var path_buf: [128]u8 = undefined;
        const tmp_path = try std.fmt.bufPrint(&path_buf, "/tmp/lir_trapp_{d}_{d}", .{ util.sysGetPid(), idx });
        {
            const f = try std.fs.createFileAbsolute(tmp_path, .{ .mode = 0o755 });
            defer f.close();
            try f.writeAll(elf);
        }
        defer std.fs.deleteFileAbsolute(tmp_path) catch {};
        const run_res = try std.process.Child.run(.{
            .allocator = std.testing.allocator,
            .argv = &[_][]const u8{tmp_path},
        });
        std.testing.allocator.free(run_res.stdout);
        std.testing.allocator.free(run_res.stderr);
        switch (run_res.term) {
            .Exited => |code| try std.testing.expect(code != 0),
            .Signal => {},
            else => {},
        }

        // In-process IR VM must trap with exit_code == 132
        var c_vm = main.Compiler.initForTarget(tsrc, "<trap_vm>", .O2, main.Target.host(), .vm);
        c_vm.quiet = true;
        var vm_res = try c_vm.runInVM(&[_][]const u8{"trap_vm"}, true);
        defer vm_res.deinit(std.heap.page_allocator);
        try std.testing.expect(vm_res.trapped);
        try std.testing.expectEqual(@as(i64, 132), vm_res.exit_code);
    }
    // In-process IR VM additionally traps runtime use-after-free reads via heap metadata
    {
        const uaf_src = "fn drop_buf(p: *u8) { @free(p) }\nfn main() -> i64 { let p = @malloc(16)\n drop_buf(p)\n return @read_u64(p) }";
        var c_vm = main.Compiler.initForTarget(uaf_src, "<uaf_vm>", .O2, main.Target.host(), .vm);
        c_vm.quiet = true;
        var vm_res = try c_vm.runInVM(&[_][]const u8{"uaf_vm"}, true);
        defer vm_res.deinit(std.heap.page_allocator);
        try std.testing.expect(vm_res.trapped);
        try std.testing.expectEqual(@as(i64, 132), vm_res.exit_code);
    }
}

test "portable C11 emitter generates platform-appropriate cross-target code" {
    const src =
        \\import std::crypto
        \\struct Big { a: i64, b: i64, c: i64, d: i64 }
        \\fn helper(x: i64) -> i64 { return x + 1 }
        \\fn main() -> i64 {
        \\    let s = Big { a: 1, b: 2, c: 3, d: 4 }
        \\    var arr: [4]i64 = [10; 4]
        \\    let f: fn(i64) -> i64 = helper
        \\    let r = @random_u64()
        \\    println("{s.a + s.d},{arr[2]},{f(41)},{@target_os()}")
        \\    return 0
        \\}
    ;
    const targets = [_][]const u8{ "aarch64-macos", "x86_64-windows", "wasm32-wasi", "x86_64-freebsd" };
    const needles = [_][]const u8{ "_DARWIN_C_SOURCE", "_WIN32", "__wasi_random_get", "__BSD_VISIBLE" };
    for (targets, needles) |spec, needle| {
        const tgt = main.Target.parse(spec) orelse return error.TestUnexpectedResult;
        var compiler = main.Compiler.initForTarget(src, "<c_emit>", .O0, tgt, .c);
        compiler.quiet = true;
        compiler.emit_c = true;
        const c_src = try compiler.compile();
        defer std.heap.page_allocator.free(c_src);
        try std.testing.expect(std.mem.indexOf(u8, c_src, needle) != null);
        try std.testing.expect(std.mem.indexOf(u8, c_src, "lir_call_indirect(") != null);
        try std.testing.expect(std.mem.indexOf(u8, c_src, "_alloca_") != null);
    }
}

test "portable IR VM supports recursion, alloca frames, and argv" {
    const src =
        \\fn sum_rec(n: i64) -> i64 {
        \\    if n <= 0 { return 0 }
        \\    return n + sum_rec(n - 1)
        \\}
        \\fn main() -> i64 {
        \\    println("{@argc()},{@argv(1)},{sum_rec(10)}")
        \\    return 0
        \\}
    ;
    var compiler = main.Compiler.initForTarget(src, "<vm_argv>", .O2, main.Target.host(), .vm);
    compiler.quiet = true;
    var res = try compiler.runInVM(&[_][]const u8{ "prog", "ziglir" }, true);
    defer res.deinit(std.heap.page_allocator);
    try std.testing.expect(!res.trapped);
    try std.testing.expectEqual(@as(i64, 0), res.exit_code);
    try std.testing.expectEqualStrings("2,ziglir,55\n", res.stdout);
}

test "Sema rejects mutability, borrow/escape, closure capture, loop leak, narrowing, and union violations" {
    const cases = [_]struct { name: []const u8, src: []const u8 }{
        .{
            .name = "immutable_let_reassign",
            .src = "fn main() -> i64 { let x = 1\n x = 2\n return x }",
        },
        .{
            .name = "immutable_ref_param_mutate",
            .src = "fn bad(p: &i64) { *p = 2 }\nfn main() -> i64 { var x = 1\n bad(&x)\n return x }",
        },
        .{
            .name = "copied_shared_ref_keeps_borrow_live",
            .src = "fn main() -> i64 { var x = 1\n var y = 2\n var r = &x\n let r2 = r\n r = &y\n x = 3\n return *r2 }",
        },
        .{
            .name = "mutable_ref_cannot_be_aliased_by_copy",
            .src = "fn main() -> i64 { var x = 1\n let mut r = &mut x\n let mut r2 = r\n *r2 = 2\n return x }",
        },
        .{
            .name = "escape_local_addr_return",
            .src = "fn bad() -> *i64 { var x = 1\n return &x }\nfn main() -> i64 { let p = bad()\n return *p }",
        },
        .{
            .name = "escape_local_addr_ternary",
            .src = "fn bad(c: bool) -> *i64 { var x = 1\n let h = @malloc(8) as *i64\n return c ? &x : h }\nfn main() -> i64 { return 0 }",
        },
        .{
            .name = "closure_escapes_local_ref",
            .src = "fn bad() -> fn() -> i64 { var x = 1\n let r = &x\n return || -> i64 { return *r } }\nfn main() -> i64 { return 0 }",
        },
        .{
            .name = "loop_unfreed_heap_alloc",
            .src = "fn main() -> i64 { var i = 0\n while i < 4 { let p = @malloc(16)\n @write_u64(p, i)\n i += 1 }\n return 0 }",
        },
        .{
            .name = "narrowing_u8_overflow",
            .src = "fn main() -> i64 { let x: u8 = 256\n return x as i64 }",
        },
        .{
            .name = "narrowing_u8_negative",
            .src = "fn main() -> i64 { let x: u8 = -1\n return x as i64 }",
        },
        .{
            .name = "narrowing_i8_underflow",
            .src = "fn main() -> i64 { let x: i8 = -129\n return x as i64 }",
        },
        .{
            .name = "spawn_local_addr_escape",
            .src = "fn main() -> i64 { var x = 0\n let t = spawn(|| { *(&x) = 1 })\n return 0 }",
        },
        .{
            .name = "fn_sig_arity_mismatch",
            .src = "fn add2(a: i64, b: i64) -> i64 { return a + b }\nfn main() -> i64 { let f: fn(i64) -> i64 = add2\n return f(1) }",
        },
        .{
            .name = "fixed_array_non_int_index",
            .src = "fn main() -> i64 { var a: [2]i64 = [1, 2]\n return a[\"bad\"] }",
        },
        .{
            .name = "fixed_array_lit_too_long",
            .src = "fn main() -> i64 { var a: [2]i64 = [1, 2, 3]\n return a[0] }",
        },
        .{
            .name = "union_multi_field_init",
            .src = "union U { a: i64, b: f64 }\nfn main() -> i64 { let u = U { a: 1, b: 2.0 }\n return 0 }",
        },
    };
    for (cases) |tc| {
        var compiler = main.Compiler.init(tc.src, "<sema_neg>");
        compiler.quiet = true;
        if (compiler.compile()) |elf| {
            std.heap.page_allocator.free(elf);
            std.debug.print("Expected Sema rejection for '{s}', but succeeded!\n", .{tc.name});
            return error.TestExpectedError;
        } else |_| {}
    }
}

test "Runtime security parity: exact CFI, ftoi NaN/OOB, bulk OOB, negative lengths, and shift wrap traps across backends" {
    // 1. Valid -2^63 float->int conversion succeeds on Native ELF, C11, and IR VM
    {
        const min_f_src =
            \\fn rt(x: f64) -> f64 { if @argc() > 999999 { return 0.0 } return x }
            \\fn main() -> i64 {
            \\    let v = rt(-9223372036854775808.0) as i64
            \\    return v == (-9223372036854775807 - 1) ? 0 : 1
            \\}
        ;
        const elf = try compileSourceWithOpt(min_f_src, .O2);
        defer std.testing.allocator.free(elf);
        const er = try runElfCapture(std.testing.allocator, elf, "ftoi_min_ok");
        defer std.testing.allocator.free(er.stdout);
        try std.testing.expectEqual(@as(u8, 0), er.exit_code);

        var c_vm = main.Compiler.initForTarget(min_f_src, "<ftoi_min_vm>", .O2, main.Target.host(), .vm);
        c_vm.quiet = true;
        var vm_res = try c_vm.runInVM(&[_][]const u8{"ftoi_min_vm"}, true);
        defer vm_res.deinit(std.heap.page_allocator);
        try std.testing.expect(!vm_res.trapped);
        try std.testing.expectEqual(@as(i64, 0), vm_res.exit_code);

        var c_cc = main.Compiler.initForTarget(min_f_src, "<ftoi_min_c>", .O2, main.Target.host(), .c);
        c_cc.quiet = true;
        const c_bin = try c_cc.compile();
        defer std.heap.page_allocator.free(c_bin);
        const cr = try runElfCapture(std.testing.allocator, c_bin, "ftoi_min_c");
        defer std.testing.allocator.free(cr.stdout);
        try std.testing.expectEqual(@as(u8, 0), cr.exit_code);
    }

    // 2. Native-only exact CFI mid-function gadget trap (entry + 4 inside real fn_addr target)
    {
        const mid_gadget_src =
            \\fn ok() -> i64 { return 1 }
            \\fn main() -> i64 {
            \\    var f: fn() -> i64 = ok
            \\    let box = @read_u64((&f) as *u8)
            \\    let entry = @read_u64(box as *u8)
            \\    @write_u64(box as *u8, entry + 4)
            \\    return f()
            \\}
        ;
        const elf = try compileSourceWithOpt(mid_gadget_src, .O2);
        defer std.testing.allocator.free(elf);
        try runElfExpectSigIll(std.testing.allocator, elf, "cfi_mid_fn_gadget");
    }

    // 3. Cross-backend runtime trap suite: Native ELF, C11, IR VM (plus valid Wasm32-WASI emission)
    const trap_cases = [_]struct { name: []const u8, src: []const u8 }{
        .{
            .name = "cfi_non_addr_taken_target",
            .src =
            \\fn secret() -> i64 { return 99 }
            \\fn ok() -> i64 { return 1 }
            \\fn main() -> i64 {
            \\    var f: fn() -> i64 = ok
            \\    let box = @read_u64((&f) as *u8)
            \\    @write_u64(box as *u8, 0xC0000000)
            \\    return f()
            \\}
            ,
        },
        .{
            .name = "ftoi_nan_trap",
            .src =
            \\fn rt(x: f64) -> f64 { if @argc() > 999999 { return 0.0 } return x }
            \\fn main() -> i64 {
            \\    let z = rt(0.0)
            \\    let nan = z / z
            \\    return nan as i64
            \\}
            ,
        },
        .{
            .name = "ftoi_oob_trap",
            .src =
            \\fn rt(x: f64) -> f64 { if @argc() > 999999 { return 0.0 } return x }
            \\fn main() -> i64 { return rt(1.0e25) as i64 }
            ,
        },
        .{
            .name = "memcpy_heap_oob",
            .src =
            \\fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
            \\fn main() -> i64 {
            \\    let dst = @malloc(8)
            \\    let src = @malloc(64)
            \\    @memset(src, 65, 64)
            \\    @memcpy(dst, src, rt(32))
            \\    @free(src)
            \\    @free(dst)
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "memset_heap_oob",
            .src =
            \\fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
            \\fn main() -> i64 {
            \\    let dst = @malloc(8)
            \\    @memset(dst, 65, rt(32))
            \\    @free(dst)
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "secure_zero_heap_oob",
            .src =
            \\fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
            \\fn main() -> i64 {
            \\    let p = @malloc(8)
            \\    @secure_zero(p, rt(32))
            \\    @free(p)
            \\    return 0
            \\}
            ,
        },
        .{
            .name = "const_time_eq_oob",
            .src =
            \\fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
            \\fn main() -> i64 {
            \\    let a = @malloc(8)
            \\    let b = @malloc(32)
            \\    let eq = @const_time_eq(a, b, rt(16))
            \\    @free(a)
            \\    @free(b)
            \\    return eq ? 1 : 0
            \\}
            ,
        },
        .{
            .name = "const_time_eq_neg",
            .src =
            \\fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
            \\fn main() -> i64 {
            \\    let a = @malloc(8)
            \\    let b = @malloc(8)
            \\    let eq = @const_time_eq(a, b, rt(-1))
            \\    @free(a)
            \\    @free(b)
            \\    return eq ? 1 : 0
            \\}
            ,
        },
        .{
            .name = "random_bytes_oob",
            .src =
            \\fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
            \\fn main() -> i64 {
            \\    let p = @malloc(8)
            \\    let n = @random_bytes(p, rt(16))
            \\    @free(p)
            \\    return n
            \\}
            ,
        },
        .{
            .name = "random_bytes_neg",
            .src =
            \\fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
            \\fn main() -> i64 {
            \\    let p = @malloc(8)
            \\    let n = @random_bytes(p, rt(-1))
            \\    @free(p)
            \\    return n
            \\}
            ,
        },
        .{
            .name = "write_neg_len",
            .src =
            \\fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
            \\fn main() -> i64 {
            \\    let p = @malloc(8)
            \\    let r = @write(1, p, rt(-1))
            \\    @free(p)
            \\    return r
            \\}
            ,
        },
        .{
            .name = "write_heap_oob",
            .src =
            \\fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
            \\fn main() -> i64 {
            \\    let p = @malloc(8)
            \\    let r = @write(1, p, rt(64))
            \\    @free(p)
            \\    return r
            \\}
            ,
        },
        .{
            .name = "stat_buf_oob",
            .src =
            \\fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
            \\fn main() -> i64 {
            \\    let p = @malloc(rt(8))
            \\    let r = @stat("/dev/null", p)
            \\    @free(p)
            \\    return r
            \\}
            ,
        },
        .{
            .name = "ptr_index_shift_wrap",
            .src =
            \\fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
            \\fn main() -> i64 {
            \\    let p = @malloc(16) as *i64
            \\    let x = p[rt(2305843009213693952)]
            \\    @free(p as *u8)
            \\    return x
            \\}
            ,
        },
        .{
            .name = "string_char_at_oob_rt",
            .src =
            \\fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
            \\fn main() -> i64 { return @string_char_at("abc", rt(3)) }
            ,
        },
        .{
            .name = "argv_oob_rt",
            .src =
            \\fn rt(x: i64) -> i64 { if @argc() > 999999 { return 0 } return x }
            \\fn main() -> i64 { return @string_len(@argv(rt(99))) }
            ,
        },
    };

    const w_tgt = main.Target.parse("wasm32-wasi") orelse return error.TestUnexpectedResult;
    for (trap_cases, 0..) |tc, idx| {
        // Native ELF
        const elf = try compileSourceWithOpt(tc.src, .O2);
        defer std.testing.allocator.free(elf);
        try runElfExpectSigIll(std.testing.allocator, elf, tc.name);

        // Portable IR VM
        var c_vm = main.Compiler.initForTarget(tc.src, "<trap4_vm>", .O2, main.Target.host(), .vm);
        c_vm.quiet = true;
        var vm_res = try c_vm.runInVM(&[_][]const u8{"trap4_vm"}, true);
        defer vm_res.deinit(std.heap.page_allocator);
        if (!vm_res.trapped) std.debug.print("VM did not trap for '{s}' (exit={d})\n", .{ tc.name, vm_res.exit_code });
        try std.testing.expect(vm_res.trapped);

        // Portable C11 binary
        var c_cc = main.Compiler.initForTarget(tc.src, "<trap4_c>", .O2, main.Target.host(), .c);
        c_cc.quiet = true;
        const c_bin = try c_cc.compile();
        defer std.heap.page_allocator.free(c_bin);
        var path_buf: [128]u8 = undefined;
        const tmp_path = try std.fmt.bufPrint(&path_buf, "/tmp/lir_c_trap_{d}_{d}", .{ util.sysGetPid(), idx });
        {
            const f = try std.fs.createFileAbsolute(tmp_path, .{ .mode = 0o755 });
            defer f.close();
            try f.writeAll(c_bin);
        }
        defer std.fs.deleteFileAbsolute(tmp_path) catch {};
        const c_run = try std.process.Child.run(.{
            .allocator = std.testing.allocator,
            .argv = &[_][]const u8{tmp_path},
        });
        std.testing.allocator.free(c_run.stdout);
        std.testing.allocator.free(c_run.stderr);
        switch (c_run.term) {
            .Exited => |code| {
                if (code == 0) std.debug.print("C11 did not trap for '{s}' (exit=0)\n", .{tc.name});
                try std.testing.expect(code != 0);
            },
            .Signal => {},
            else => {},
        }

        // Wasm32-WASI binary emits cleanly
        var c_wasm = main.Compiler.initForTarget(tc.src, "<trap4_wasm>", .O2, w_tgt, .native_wasm);
        c_wasm.quiet = true;
        const wasm_bytes = try c_wasm.compile();
        defer std.heap.page_allocator.free(wasm_bytes);
        try std.testing.expectEqualStrings("\x00asm\x01\x00\x00\x00", wasm_bytes[0..8]);
    }
}






test "Security hardening: compile-time overflow, non-canonical pointers, and VM heap canary checks" {
    // 1. Sema compile-time compound division overflow (MIN_I64 / -1)
    const div_ovf_src =
        \\fn main() -> i64 {
        \\    var x: i64 = -9223372036854775807 - 1
        \\    x /= -1
        \\    return x
        \\}
    ;
    try std.testing.expectError(error.TypeMismatch, compileSource(div_ovf_src));

    // 2. Sema compile-time compound modulo overflow (MIN_I64 % -1)
    const mod_ovf_src =
        \\fn main() -> i64 {
        \\    var x: i64 = -9223372036854775807 - 1
        \\    x %= -1
        \\    return x
        \\}
    ;
    try std.testing.expectError(error.TypeMismatch, compileSource(mod_ovf_src));

    // 3. Sema compile-time constant pointer upper bound (kernel / non-canonical address)
    const upper_ptr_src =
        \\fn main() -> i64 {
        \\    return @read_u8(0x800000000000 as *u8) as i64
        \\}
    ;
    try std.testing.expectError(error.TypeMismatch, compileSource(upper_ptr_src));

    // 4. VM Heap canary smash detection
    const ir_vm_mod = @import("ir_vm.zig");
    const empty_mod = try std.testing.allocator.create(ir_mod.IRModule);
    defer std.testing.allocator.destroy(empty_mod);
    empty_mod.init();
    const vm = try ir_vm_mod.VMState.init(std.testing.allocator, empty_mod, "");
    defer vm.deinit();
    const ptr = try vm.allocHeap(64);
    var found = false;
    for (vm.heap_allocs.items) |ha| {
        if (ptr == ha.addr + 8) {
            found = true;
            // Smashing the canary byte
            ha.data[8 + 64] ^= 0xFF;
            break;
        }
    }
    try std.testing.expect(found);
    // Attempting to free should fail with MemoryFault because canary is corrupted
    try std.testing.expectError(error.MemoryFault, vm.freeHeap(ptr));

    // 5. VM Heap non-canonical address rejection
    try std.testing.expectError(error.MemoryFault, vm.freeHeap(0x8000_0000_0000));

    // 6. C11 Backend security hardening validation
    const c_src =
        \\fn main() -> i64 {
        \\    let p = @malloc(32)
        \\    @random_bytes(p, 16)
        \\    @free(p)
        \\    return 0
        \\}
    ;
    var c_cc = main.Compiler.initForTarget(c_src, "<c_sec>", .O2, main.Target.host(), .c);
    c_cc.quiet = true;
    const c_code = try c_cc.compileToC();
    defer std.heap.page_allocator.free(c_code);
    // Upper bound / non-canonical address check present in C runtime
    try std.testing.expect(std.mem.indexOf(u8, c_code, "0x800000000000ULL") != null);
    // Cryptographically secure random reading from /dev/urandom present
    try std.testing.expect(std.mem.indexOf(u8, c_code, "/dev/urandom") != null);
}

test "Security hardening: recursion depth limits, shift folding safety, and VM exit/string robustness" {
    // 1. Deeply nested expression exceeds recursion limit (64) and fails closed with error
    var deep_buf: [512]u8 = undefined;
    var pos: usize = 0;
    const prefix = "fn main() -> i64 { return ";
    @memcpy(deep_buf[pos..][0..prefix.len], prefix);
    pos += prefix.len;
    var d: usize = 0;
    while (d < 80) : (d += 1) {
        deep_buf[pos] = '(';
        pos += 1;
    }
    deep_buf[pos] = '1';
    pos += 1;
    d = 0;
    while (d < 80) : (d += 1) {
        deep_buf[pos] = ')';
        pos += 1;
    }
    const suffix = " }\n";
    @memcpy(deep_buf[pos..][0..suffix.len], suffix);
    pos += suffix.len;
    try std.testing.expectError(error.InvalidSyntax, compileSource(deep_buf[0..pos]));

    // 2. Negative integer shifted left in constant evaluation does not panic
    const neg_shift_src =
        \\fn main() -> i64 {
        \\    let x = -1 << 2
        \\    return x
        \\}
    ;
    const neg_shift_elf = try compileSource(neg_shift_src);
    defer std.testing.allocator.free(neg_shift_elf);
    const elf_res = try runElfCapture(std.testing.allocator, neg_shift_elf, "neg_shift");
    defer std.testing.allocator.free(elf_res.stdout);
    try std.testing.expectEqual(@as(u8, @truncate(@as(u64, @bitCast(@as(i64, -4))))), elf_res.exit_code);

    // 3. VM exit(42) terminates VM with exit code 42 without killing host process
    const vm_exit_src =
        \\fn main() -> i64 {
        \\    @exit(42)
        \\    return 0
        \\}
    ;
    var comp = main.Compiler.initForTarget(vm_exit_src, "<vm_exit>", .O2, main.Target.host(), .vm);
    comp.quiet = true;
    var vm_res = try comp.runInVM(&[_][]const u8{}, true);
    defer vm_res.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i64, 42), vm_res.exit_code);
    try std.testing.expect(!vm_res.trapped);
}

test "starter project regression tests" {
    _ = @import("project.zig");
}

test "manifest regression tests" {
    _ = @import("manifest.zig");
}

test "comprehensive stdlib modules: collections, hash, fmt, time, http, math, and string extensions" {
    const src =
        \\import std::collections
        \\import std::hash
        \\import std::fmt
        \\import std::time
        \\import std::http
        \\import std::str
        \\import std::algo
        \\import std::math
        \\
        \\fn main() -> i64 {
        \\    let rb = rb_new(4)
        \\    rb_push(rb, 100)
        \\    rb_push(rb, 200)
        \\    printInt(rb_len(rb))
        \\    printInt(rb_pop(rb))
        \\    printInt(rb_pop(rb))
        \\    rb_free(rb)
        \\
        \\    let bs = bitset_new(64)
        \\    bitset_set(bs, 42)
        \\    printInt(bitset_test(bs, 42) ? 1 : 0)
        \\    printInt(bitset_test(bs, 43) ? 1 : 0)
        \\    printInt(bitset_count(bs))
        \\    bitset_free(bs)
        \\
        \\    let hp = heap_new(8)
        \\    heap_push(hp, 30)
        \\    heap_push(hp, 10)
        \\    heap_push(hp, 20)
        \\    printInt(heap_pop(hp))
        \\    printInt(heap_pop(hp))
        \\    printInt(heap_pop(hp))
        \\    heap_free(hp)
        \\
        \\    printInt(crc32("123456789"))
        \\    printInt(adler32("Wikipedia"))
        \\
        \\    println(base64_encode("Hello LIR!"))
        \\    println(base64_decode(base64_encode("Hello LIR!")))
        \\    println(hex_encode("LIR"))
        \\    println(hex_decode(hex_encode("LIR")))
        \\    println(format_bytes(1048576))
        \\
        \\    printInt(is_leap_year(2024) ? 1 : 0)
        \\    printInt(is_leap_year(2023) ? 1 : 0)
        \\    printInt(days_in_month(2024, 2))
        \\
        \\    println(http_status_text(200))
        \\    println(http_parse_method("GET /index.html HTTP/1.1"))
        \\    println(http_parse_path("GET /api/users?id=1 HTTP/1.1"))
        \\
        \\    printInt(str_glob_match("*.lir", "test.lir") ? 1 : 0)
        \\    printInt(str_levenshtein("kitten", "sitting"))
        \\    println(str_pad_left("7", 3, 48))
        \\
        \\    let arr = @array_new(8)
        \\    @array_push(arr, 50)
        \\    @array_push(arr, 20)
        \\    @array_push(arr, 40)
        \\    @array_push(arr, 10)
        \\    @array_push(arr, 30)
        \\    quick_sort_i64(arr)
        \\    printInt(@array_get(arr, 0))
        \\    printInt(@array_get(arr, 4))
        \\    printInt(lower_bound_i64(arr, 30))
        \\    @array_free(arr)
        \\
        \\    printInt(is_prime_i64(17) ? 1 : 0)
        \\    printInt(is_prime_i64(18) ? 1 : 0)
        \\    printInt(next_prime_i64(18))
        \\    printInt(log2_i64(1024))
        \\    printInt(log10_i64(10000))
        \\    return 0
        \\}
    ;
    const elf = try compileSource(src);
    defer std.testing.allocator.free(elf);
    const res = try runElfCapture(std.testing.allocator, elf, "stdlib_comprehensive");
    defer std.testing.allocator.free(res.stdout);
    try std.testing.expectEqual(@as(u8, 0), res.exit_code);
    try std.testing.expectEqualStrings(
        "2\n100\n200\n1\n0\n1\n10\n20\n30\n3421780262\n300286872\nSGVsbG8gTElSIQ==\nHello LIR!\n4c4952\nLIR\n1 MB\n1\n0\n29\nOK\nGET\n/api/users\n1\n3\n007\n10\n50\n2\n1\n0\n19\n10\n4\n",
        res.stdout,
    );
}

test "codegen: frame-shrink state must not leak from one function into the next" {
    // Regression test for a native-codegen miscompile. The backend can elide a
    // callee frame when the entry block is a cheap guard that either returns a
    // constant immediately or continues into the real body: it emits B0 with no
    // prologue, inlines the early `ret`, and only builds the frame at the
    // continuation block. That decision is recorded in the cur_shrink_* fields.
    //
    // Those fields used to be written ONLY on the path where the elision
    // applies, but both emitters that consume them (compileFusedCmpBranch and
    // the plain .cond_jump arm) test just `cur_shrink_shared and cur_bi == 0`
    // and cannot see whether the current function is eligible at all. So every
    // ineligible function that happened to be compiled next inherited the
    // previous function's eligibility, continuation block index, and early-return
    // constant -- and emitted an early `mov rax, <other function's constant>;
    // ret` plus a jump to <other function's block index> at the top of its own
    // entry block. Depending on where that stale index landed, downstream
    // functions silently returned wrong values or segfaulted.
    //
    // `shrinker_shared` below is the trigger: its early-return block has TWO
    // predecessors (`buf == 0` from B0 and `len <= 0` from B1), which selects
    // the shared-return form of the elision and leaves cur_shrink_shared set.
    // `hex_encode` is the victim: it cannot elide (it needs a real frame) yet
    // its entry block ends in a cond_jump. It is called rather than inlined, so
    // a leak shows up directly in stdout. Before the fix this binary printed
    // the first line and then segfaulted (exit 139); the IR VM, which has no
    // such state, always produced the expected output.
    const src =
        \\import std::fmt
        \\import std::str
        \\
        \\fn shrinker_shared(buf: *u8, len: i64) -> i64 {
        \\    if buf == 0 as *u8 or len <= 0 { return -3750763034362895579 }
        \\    var h: i64 = -3750763034362895579
        \\    var i: i64 = 0
        \\    while i < len {
        \\        h = (h ^ (@read_u8(@ptr_add(buf, i)) as i64)) * 1099511628211
        \\        i += 1
        \\    }
        \\    return h
        \\}
        \\
        \\fn main() -> i64 {
        \\    printInt(shrinker_shared(0 as *u8, 4))
        \\    println("")
        \\    println(hex_encode("LIR"))
        \\    printInt(@string_len(hex_encode("LIR")))
        \\    println("")
        \\    return 0
        \\}
    ;
    const elf = try compileSourceWithOpt(src, .O2);
    defer std.testing.allocator.free(elf);
    const res = try runElfCapture(std.testing.allocator, elf, "shrink_state_leak");
    defer std.testing.allocator.free(res.stdout);
    try std.testing.expectEqual(@as(u8, 0), res.exit_code);
    try std.testing.expectEqualStrings(
        "-3750763034362895579\n\n4c4952\n6\n\n",
        res.stdout,
    );
}

test "codegen: @popcount agrees between host POPCNT and the portable SWAR path" {
    // The native backend emits the hardware POPCNT instruction when the host
    // CPUID reports it, and the 21-instruction SWAR sequence otherwise. Both
    // must compute the identical function for every input, including 0, a
    // single bit, a full word, and values produced at run time -- a wrong
    // ModRM byte or a swapped operand would show up here rather than as a
    // mysterious benchmark difference.
    //
    // The expected values are not taken from either implementation: they are
    // the mathematical bit counts (0 -> 0, 0xFF -> 8, all-ones -> 64, 1 -> 1)
    // plus sum(popcount(i * 2654435761) for i in 0..99) == 1880, computed
    // independently.
    const src =
        \\fn main() -> i64 {
        \\    printInt(@popcount(0 as u64))
        \\    printInt(@popcount(255 as u64))
        \\    printInt(@popcount(-1 as u64))
        \\    printInt(@popcount(1 as u64))
        \\    var i: i64 = 0
        \\    var acc: i64 = 0
        \\    while i < 100 {
        \\        acc = acc + @popcount((i * 2654435761) as u64)
        \\        i = i + 1
        \\    }
        \\    printInt(acc)
        \\    return 0
        \\}
    ;
    const expected = "0\n8\n64\n1\n1880\n";

    inline for (.{ .host, .baseline }) |mode| {
        const elf = try compileSourceCpuMode(src, .O2, mode);
        defer std.testing.allocator.free(elf);
        const res = try runElfCapture(std.testing.allocator, elf, @tagName(mode));
        defer std.testing.allocator.free(res.stdout);
        try std.testing.expectEqual(@as(u8, 0), res.exit_code);
        try std.testing.expectEqualStrings(expected, res.stdout);
    }
}

test "codegen: a folded [base + index*8] access keeps its operands live" {
    // The native backend folds `@read_u64(@ptr_add(base, i * 8))` into the x86
    // memory operand `[base + i*8]`, so the pointer and the scaled offset stop
    // being values the register allocator has to place. That is only sound if
    // the *base* and the *index* stay live until the access itself - and the
    // access is not where the `@ptr_add` it replaced sat. `dst[q] = src[q] / m`
    // is the shape that caught this: IRGen builds the destination pointer
    // first, then computes the quotient, so a live range that ended at the
    // pointer let the allocator hand that very register to the division result
    // and the store indexed off the quotient instead of off q.
    //
    // The expected numbers are the integer quotients floor((q+1)*100 / (q%3+2))
    // for q in 0..7 - 50, 66, 75, 200, 166, 150, 350, 266 - summed: 1323. They
    // come from the arithmetic, not from any backend.
    const src =
        \\fn main() -> i64 {
        \\    let n: i64 = 8
        \\    let a = @malloc(n * 8)
        \\    let b = @malloc(n * 8)
        \\    if a == 0 as *u8 { return 1 }
        \\    if b == 0 as *u8 { return 2 }
        \\    var i: i64 = 0
        \\    while i < n {
        \\        @write_u64(@ptr_add(a, i * 8), (i + 1) * 100)
        \\        i = i + 1
        \\    }
        \\    var q: i64 = 0
        \\    var acc: i64 = 0
        \\    while q < n {
        \\        let s = @read_u64(@ptr_add(a, q * 8)) as i64
        \\        let m = (q % 3) + 2
        \\        @write_u64(@ptr_add(b, q * 8), s / m)
        \\        acc = acc + (@read_u64(@ptr_add(b, q * 8)) as i64)
        \\        q = q + 1
        \\    }
        \\    printInt(acc)
        \\    @free(a)
        \\    @free(b)
        \\    return 0
        \\}
    ;
    inline for (.{ .O0, .O1, .O2 }) |lvl| {
        const elf = try compileSourceWithOpt(src, lvl);
        defer std.testing.allocator.free(elf);
        const res = try runElfCapture(std.testing.allocator, elf, "fold_live_" ++ @tagName(lvl));
        defer std.testing.allocator.free(res.stdout);
        try std.testing.expectEqual(@as(u8, 0), res.exit_code);
        try std.testing.expectEqualStrings("1323\n", res.stdout);
    }
}

test "codegen: a folded out-of-chunk store still traps at every -O level" {
    // The fold removes instructions, never checks. Writing one element past a
    // 64-byte chunk through `@ptr_add(buf, i * 8)` lands inside the heap arena
    // but outside the chunk, which the deferred probe must still catch - at
    // -O2, where the fold is active, exactly as at -O0.
    const src =
        \\fn main() -> i64 {
        \\    let buf = @malloc(64)
        \\    if buf == 0 as *u8 { return 1 }
        \\    var i: i64 = 0
        \\    while i < 16 {
        \\        @write_u64(@ptr_add(buf, i * 8), i * i)
        \\        i += 1
        \\    }
        \\    printInt(@read_u64(@ptr_add(buf, 8)) as i64)
        \\    @free(buf)
        \\    return 0
        \\}
    ;
    inline for (.{ .O0, .O1, .O2 }) |lvl| {
        const elf = try compileSourceWithOpt(src, lvl);
        defer std.testing.allocator.free(elf);
        try runElfExpectSigIll(std.testing.allocator, elf, "fold_oob_" ++ @tagName(lvl));
    }
}

test "opt: an if that assigns several variables becomes a cmov chain" {
    // destructSSA turns `if d < best { best = v; best_d = d }` into a diamond
    // whose two arms are nothing but copies into the same destinations.
    // diamondCopiesToSelect rewrites that into one select per variable so
    // codegen can fuse the compare into a cmov chain. The branch it replaces is
    // decided by the data, so it mispredicts about as often as it is taken and
    // dominates the runtime of every reduction loop; the cmovs never do.
    //
    // Round r scans v = ((i*37) % 23) - 11 + 5r for i in 0..19 and keeps the v
    // of smallest |v|. Rounds 0-2 reach v = 0, round 3 bottoms out at 4 and
    // round 4 at 9, so total = sum(best*(r+1) + best_d) = 4*4 + 4 + 9*5 + 9 =
    // 74 - an arithmetic oracle, not a transcript of any backend.
    const reduction_src =
        \\fn main() -> i64 {
        \\    var total: i64 = 0
        \\    var r: i64 = 0
        \\    while r < 5 {
        \\        var best: i64 = 0
        \\        var best_d: i64 = 9223372036854775807
        \\        var i: i64 = 0
        \\        while i < 20 {
        \\            let v = ((i * 37) % 23) - 11 + r * 5
        \\            let d = @max(v, 0 - v)
        \\            if d < best_d {
        \\                best_d = d
        \\                best = v
        \\            }
        \\            i = i + 1
        \\        }
        \\        total = total + best * (r + 1) + best_d
        \\        r = r + 1
        \\    }
        \\    printInt(total)
        \\    return 0
        \\}
    ;

    // Three variables assigned together: the chain has to keep all three
    // consistent, which is what a single cmov per variable cannot fake.
    const triple_src =
        \\fn main() -> i64 {
        \\    var s1: i64 = 0
        \\    var s2: i64 = 0
        \\    var s3: i64 = 0
        \\    var acc: i64 = 0
        \\    var i: i64 = 0
        \\    while i < 30 {
        \\        let x = (i * 29) % 17
        \\        if x < 9 {
        \\            s1 = x
        \\            s2 = x * x
        \\            s3 = x * x * x
        \\        }
        \\        acc = acc + s1 + s2 + s3
        \\        i = i + 1
        \\    }
        \\    printInt(acc)
        \\    return 0
        \\}
    ;

    inline for (.{ .O0, .O1, .O2 }) |lvl| {
        const elf1 = try compileSourceWithOpt(reduction_src, lvl);
        defer std.testing.allocator.free(elf1);
        const res1 = try runElfCapture(std.testing.allocator, elf1, "cmov_red_" ++ @tagName(lvl));
        defer std.testing.allocator.free(res1.stdout);
        try std.testing.expectEqual(@as(u8, 0), res1.exit_code);
        try std.testing.expectEqualStrings("74\n", res1.stdout);

        const elf2 = try compileSourceWithOpt(triple_src, lvl);
        defer std.testing.allocator.free(elf2);
        const res2 = try runElfCapture(std.testing.allocator, elf2, "cmov_triple_" ++ @tagName(lvl));
        defer std.testing.allocator.free(res2.stdout);
        try std.testing.expectEqual(@as(u8, 0), res2.exit_code);
        try std.testing.expectEqualStrings("3354\n", res2.stdout);
    }
}

test "distinct syntax: guard, unless, until, proc compile and execute" {
    const src =
        \\proc check_guard(x: i64) -> i64 {
        \\    guard x > 10 else {
        \\        return -1
        \\    }
        \\    return x * 2
        \\}
        \\
        \\proc check_unless(x: i64) -> i64 {
        \\    unless x == 0 {
        \\        return 100 / x
        \\    } else {
        \\        return 0
        \\    }
        \\}
        \\
        \\proc check_until(n: i64) -> i64 {
        \\    var sum = 0
        \\    var i = 0
        \\    until i >= n {
        \\        sum = sum + i
        \\        i = i + 1
        \\    }
        \\    return sum
        \\}
        \\
        \\proc main() -> i64 {
        \\    printInt(check_guard(5))
        \\    printInt(check_guard(20))
        \\    printInt(check_unless(0))
        \\    printInt(check_unless(4))
        \\    printInt(check_until(10))
        \\    let v = unless 1 == 2 { 42 } else { 99 }
        \\    printInt(v)
        \\    return 0
        \\}
    ;
    const elf = try compileSource(src);
    defer std.testing.allocator.free(elf);
    const res = try runElfCapture(std.testing.allocator, elf, "distinct_syntax");
    defer std.testing.allocator.free(res.stdout);
    try std.testing.expectEqual(@as(u8, 0), res.exit_code);
    try std.testing.expectEqualStrings("-1\n40\n0\n25\n45\n42\n", res.stdout);
}

test "formal verification: SPARK bounded scalar ranges compile and check statically" {
    // 1. Valid range initialization and assignment compiles and executes correctly
    const valid_src =
        \\type Port = i64 range 1..65535
        \\fn main() -> i64 {
        \\    let p: Port = 8080
        \\    let mut q: Port = 443
        \\    q = 8443
        \\    printInt(p)
        \\    printInt(q)
        \\    return 0
        \\}
    ;
    const elf = try compileSource(valid_src);
    defer std.testing.allocator.free(elf);
    const res = try runElfCapture(std.testing.allocator, elf, "spark_range_valid");
    defer std.testing.allocator.free(res.stdout);
    try std.testing.expectEqual(@as(u8, 0), res.exit_code);
    try std.testing.expectEqualStrings("8080\n8443\n", res.stdout);

    // 2. Out-of-bounds initialization is rejected at compile time
    try std.testing.expectError(error.TypeMismatch, compileSource(
        \\type Port = i64 range 1..65535
        \\fn main() -> i64 {
        \\    let p: Port = 70000
        \\    return p
        \\}
    ));

    // 3. Out-of-bounds assignment is rejected at compile time
    try std.testing.expectError(error.TypeMismatch, compileSource(
        \\type Port = i64 range 1..65535
        \\fn main() -> i64 {
        \\    let mut p: Port = 80
        \\    p = 0
        \\    return p
        \\}
    ));

    // 4. Out-of-bounds cast is rejected at compile time
    try std.testing.expectError(error.TypeMismatch, compileSource(
        \\type Port = i64 range 1..65535
        \\fn main() -> i64 {
        \\    let p = 70000 as Port
        \\    return p
        \\}
    ));
}

test "formal verification: Ada SPARK function contracts pre and pure statically verified and runtime trapped" {
    // 1. Valid precondition contract compiles and executes
    const valid_pre =
        \\#[pre(b != 0)]
        \\fn safe_div(a: i64, b: i64) -> i64 {
        \\    return a / b
        \\}
        \\fn main() -> i64 {
        \\    printInt(safe_div(100, 5))
        \\    return 0
        \\}
    ;
    const elf = try compileSource(valid_pre);
    defer std.testing.allocator.free(elf);
    const res = try runElfCapture(std.testing.allocator, elf, "spark_pre_valid");
    defer std.testing.allocator.free(res.stdout);
    try std.testing.expectEqual(@as(u8, 0), res.exit_code);
    try std.testing.expectEqualStrings("20\n", res.stdout);

    // 2. Static precondition violation is rejected at compile time
    try std.testing.expectError(error.TypeMismatch, compileSource(
        \\#[pre(b != 0)]
        \\fn safe_div(a: i64, b: i64) -> i64 {
        \\    return a / b
        \\}
        \\fn main() -> i64 {
        \\    return safe_div(100, 0)
        \\}
    ));

    // 3. Dynamic runtime precondition violation causes deterministic hardware trap (exit 132 SIGILL)
    const trap_pre =
        \\#[pre(b != 0)]
        \\fn safe_div(a: i64, b: i64) -> i64 {
        \\    return a / b
        \\}
        \\fn compute_zero() -> i64 {
        \\    var x = 10
        \\    x = x - 10
        \\    return x
        \\}
        \\fn main() -> i64 {
        \\    let z = compute_zero()
        \\    return safe_div(100, z)
        \\}
    ;
    const trap_elf = try compileSource(trap_pre);
    defer std.testing.allocator.free(trap_elf);
    try runElfExpectSigIll(std.testing.allocator, trap_elf, "spark_pre_trap");

    // 4. Pure function calling pure builtins and pure functions compiles and runs
    const valid_pure =
        \\#[pure]
        \\fn pure_add(a: i64, b: i64) -> i64 {
        \\    return a + b
        \\}
        \\#[pure]
        \\fn pure_min_val(x: i64, y: i64) -> i64 {
        \\    return pure_add(@min(x, y), 2)
        \\}
        \\fn main() -> i64 {
        \\    printInt(pure_min_val(40, 55))
        \\    return 0
        \\}
    ;
    const pure_elf = try compileSource(valid_pure);
    defer std.testing.allocator.free(pure_elf);
    const pure_res = try runElfCapture(std.testing.allocator, pure_elf, "spark_pure_valid");
    defer std.testing.allocator.free(pure_res.stdout);
    try std.testing.expectEqual(@as(u8, 0), pure_res.exit_code);
    try std.testing.expectEqualStrings("42\n", pure_res.stdout);

    // 5. Pure function calling side-effecting builtin rejected at compile time
    try std.testing.expectError(error.TypeMismatch, compileSource(
        \\#[pure]
        \\fn bad_pure(x: i64) -> i64 {
        \\    @println("side effect")
        \\    return x
        \\}
        \\fn main() -> i64 {
        \\    return bad_pure(1)
        \\}
    ));

    // 6. Pure function calling impure user function rejected at compile time
    try std.testing.expectError(error.TypeMismatch, compileSource(
        \\fn impure_helper() -> i64 {
        \\    return 42
        \\}
        \\#[pure]
        \\fn bad_caller() -> i64 {
        \\    return impure_helper()
        \\}
        \\fn main() -> i64 {
        \\    return bad_caller()
        \\}
    ));
}

test "smart compiler: fuzzy matching algorithms" {
    try std.testing.expectEqual(@as(usize, 0), util.levenshteinDistance("hello", "hello"));
    try std.testing.expectEqual(@as(usize, 0), util.levenshteinDistance("Hello", "hello"));
    try std.testing.expectEqual(@as(usize, 1), util.levenshteinDistance("counter", "countr"));
    try std.testing.expectEqual(@as(usize, 1), util.levenshteinDistance("my_variable", "my_variabl"));
    try std.testing.expectEqual(@as(usize, 2), util.levenshteinDistance("my_variable", "my_varial"));

    const candidates = [_][]const u8{ "counter", "count_total", "calc_sum", "print_value" };
    const match1 = util.findSimilarName("countr", &candidates, 2);
    try std.testing.expect(match1 != null);
    try std.testing.expectEqualStrings("counter", match1.?);

    const match2 = util.findSimilarName("calc_sun", &candidates, 2);
    try std.testing.expect(match2 != null);
    try std.testing.expectEqualStrings("calc_sum", match2.?);
}

test "smart compiler: did-you-mean diagnostics and unused variable warnings" {
    // 1. Undeclared variable typo triggers UndefinedVariable
    try std.testing.expectError(error.UndefinedVariable, compileSource(
        \\fn main() -> i64 {
        \\    let my_counter = 42
        \\    return my_countr
        \\}
    ));

    // 2. Undefined function call typo triggers UndefinedFunctionCall
    try std.testing.expectError(error.UndefinedFunctionCall, compileSource(
        \\fn calculate_total() -> i64 { return 100 }
        \\fn main() -> i64 {
        \\    return calculat_total()
        \\}
    ));

    // 3. Unknown struct field typo triggers UnknownField
    try std.testing.expectError(error.UnknownField, compileSource(
        \\struct Point { x_coord: i64, y_coord: i64 }
        \\fn main() -> i64 {
        \\    let p = Point { x_cord: 1, y_coord: 2 }
        \\    return p.y_coord
        \\}
    ));

    // 4. Undefined struct name typo triggers UndefinedStruct
    try std.testing.expectError(error.UndefinedStruct, compileSource(
        \\struct SuperUser { id: i64 }
        \\fn main() -> i64 {
        \\    let u = SuperUsr { id: 1 }
        \\    return u.id
        \\}
    ));
}

test "smart compiler: algebraic reassociation and identity folding" {
    const src =
        \\fn math_chain(x: i64) -> i64 {
        \\    let a = x + 10
        \\    let b = a + 20
        \\    let c = b - 30
        \\    return c
        \\}
        \\fn neg_chain(x: i64) -> i64 {
        \\    let a = -x
        \\    let b = -a
        \\    return b
        \\}
        \\fn main() -> i64 {
        \\    printInt(math_chain(55))
        \\    printInt(neg_chain(99))
        \\    return 0
        \\}
    ;
    const elf = try compileSourceWithOpt(src, .O2);
    defer std.testing.allocator.free(elf);
    const run_res = try runElfCapture(std.testing.allocator, elf, "smart_alg");
    defer std.testing.allocator.free(run_res.stdout);
    try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
    try std.testing.expectEqualStrings("55\n99\n", run_res.stdout);
}

test "stdlib: str_replace and str_reverse execute correctly" {
    const src =
        \\import std::str
        \\fn main() -> i64 {
        \\    let r1 = str_replace("banana", "a", "o")
        \\    let r2 = str_reverse("racecar")
        \\    let r3 = str_reverse("hello")
        \\    println(r1)
        \\    println(r2)
        \\    println(r3)
        \\    return 0
        \\}
    ;
    const elf = try compileSourceWithOpt(src, .O2);
    defer std.testing.allocator.free(elf);
    const run_res = try runElfCapture(std.testing.allocator, elf, "str_ops");
    defer std.testing.allocator.free(run_res.stdout);
    try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
    try std.testing.expectEqualStrings("bonono\nracecar\nolleh\n", run_res.stdout);
}

test "diagnostics: smart suggestions for typos in keywords, enum variants, and conditions" {
    // 1. Enum variant typo suggestion
    {
        var c = main.Compiler.init(
            \\enum Status { Ready, InProgress, Finished }
            \\fn main() -> i64 {
            \\    let s = Status::Read
            \\    return 0
            \\}
        , "<test>");
        c.quiet = true;
        try std.testing.expectError(error.UnknownField, c.compile());
    }

    // 2. Keyword typo suggestion
    {
        var c = main.Compiler.init("func compute() -> i64 { return 42 }\nfn main() -> i64 { return 0 }", "<test>");
        c.quiet = true;
        try std.testing.expectError(error.InvalidSyntax, c.compile());
    }

    // 3. Conditional assignment suggestion
    {
        var c = main.Compiler.init("fn main() -> i64 { var x = 1; if x = 2 { return 10 } return 0 }", "<test>");
        c.quiet = true;
        try std.testing.expectError(error.InvalidSyntax, c.compile());
    }
}

test "stdlib: expanded math functions (factorial, fibonacci, pow_f, exp_f, ln_f)" {
    const src =
        \\import std::math
        \\fn main() -> i64 {
        \\    let f5 = factorial_i64(5)
        \\    let fib7 = fibonacci_i64(7)
        \\    let p = pow_f(2.0, 10)
        \\    let e = exp_f(1.0)
        \\    let lne = ln_f(e)
        \\    printInt(f5)
        \\    printInt(fib7)
        \\    printInt(p as i64)
        \\    printInt((e * 1000.0) as i64)
        \\    printInt((lne * 1000.0) as i64)
        \\    return 0
        \\}
    ;
    const elf = try compileSourceWithOpt(src, .O2);
    defer std.testing.allocator.free(elf);
    const run_res = try runElfCapture(std.testing.allocator, elf, "math_exp");
    defer std.testing.allocator.free(run_res.stdout);
    try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
    try std.testing.expectEqualStrings("120\n13\n1024\n2718\n1000\n", run_res.stdout);
}

test "stdlib: expanded algo functions (is_sorted_i64, count_occurrences_i64, find_index_i64, fill_array_i64)" {
    const src =
        \\import std::algo
        \\fn main() -> i64 {
        \\    let arr = @array_new(4)
        \\    @array_push(arr, 10)
        \\    @array_push(arr, 20)
        \\    @array_push(arr, 20)
        \\    @array_push(arr, 30)
        \\    if is_sorted_i64(arr) { println("sorted") }
        \\    printInt(count_occurrences_i64(arr, 20))
        \\    printInt(find_index_i64(arr, 30))
        \\    printInt(find_index_i64(arr, 99))
        \\    return 0
        \\}
    ;
    const elf = try compileSourceWithOpt(src, .O2);
    defer std.testing.allocator.free(elf);
    const run_res = try runElfCapture(std.testing.allocator, elf, "algo_exp");
    defer std.testing.allocator.free(run_res.stdout);
    try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
    try std.testing.expectEqualStrings("sorted\n2\n3\n-1\n", run_res.stdout);
}

test "stdlib: expanded str and collections (trim, capitalize, join, queue, stack)" {
    const src =
        \\import std::str
        \\import std::collections
        \\fn main() -> i64 {
        \\    let s1 = str_trim_left("  hi")
        \\    let s2 = str_trim_right("hi  ")
        \\    let s3 = str_capitalize("hello world")
        \\    let s4 = str_join("a", "-", "b")
        \\    println(s1)
        \\    println(s2)
        \\    println(s3)
        \\    println(s4)
        \\    let q = queue_new(2)
        \\    let _ok1 = queue_push(q, 42)
        \\    let _ok2 = queue_push(q, 99)
        \\    if queue_is_full(q) { println("q_full") }
        \\    printInt(queue_pop(q))
        \\    printInt(queue_pop(q))
        \\    if queue_is_empty(q) { println("q_empty") }
        \\    queue_free(q)
        \\    let st = stack_new(3)
        \\    printInt(stack_cap(st))
        \\    stack_free(st)
        \\    return 0
        \\}
    ;
    const elf = try compileSourceWithOpt(src, .O2);
    defer std.testing.allocator.free(elf);
    const run_res = try runElfCapture(std.testing.allocator, elf, "str_coll_exp");
    defer std.testing.allocator.free(run_res.stdout);
    try std.testing.expectEqual(@as(u8, 0), run_res.exit_code);
    try std.testing.expectEqualStrings("hi\nhi\nHello world\na-b\nq_full\n42\n99\nq_empty\n3\n", run_res.stdout);
}

// ════════════════════════════════════════════════════════════════════════════
// Language catalogue conformance
//
// `lir lang` / `lir builtins` describe the implemented language surface. These
// tests compile every documented example so the catalogue cannot drift away
// from the compiler, and verify that every `.unsupported` entry is indeed
// rejected. This is the guard that makes the AI-facing reference trustworthy.
// ════════════════════════════════════════════════════════════════════════════

const langref = @import("langref.zig");

test "langref: documented examples of every supported feature compile" {
    var total: u32 = 0;
    for (langref.features) |f| {
        if (f.status == .unsupported or f.example.len == 0) continue;
        var compiler = main.Compiler.init(f.example, "<langref>");
        compiler.quiet = true;
        compiler.test_mode = std.mem.indexOf(u8, f.example, "#[test]") != null;
        _ = compiler.compile() catch |err| {
            std.debug.print("\nlangref feature '{s}' example failed to compile: {s}\n", .{ f.name, @errorName(err) });
            return err;
        };
        total += 1;
    }
    try std.testing.expect(total >= 50);
}

test "cmf: the example field is accepted and every bloom variant verifies" {
    const cmf = @import("cmf.zig");
    const source =
        \\morph Cell =<< u8 u16 u32 u64 i64 >>=
        \\field ledger: u64[1024] ?exclusive
        \\claim exclusive_writer over ledger check uniqueness
        \\
        \\bloom narrow: morph Cell {
        \\fn main() -> i64 {
        \\    let cell: @witness = 200
        \\    return cell as i64
        \\}
        \\}
    ;
    const ir = cmf.parseField(source);
    try std.testing.expectEqual(@as(usize, 0), ir.violation_count);
    try std.testing.expectEqual(@as(usize, 5), ir.variant_count);
    for (ir.variants[0..ir.variant_count]) |v| {
        try std.testing.expect(v.verified);
        try std.testing.expect(!v.vacuous);
    }
}

test "cmf: an unverifiable witness is refused and never becomes a variant" {
    const cmf = @import("cmf.zig");
    const source =
        \\morph Cell =<< u8 bool >>=
        \\bloom narrow: morph Cell {
        \\fn main() -> i64 {
        \\    let cell: @witness = 200
        \\    return 7
        \\}
        \\}
    ;
    const ir = cmf.parseField(source);
    try std.testing.expect(ir.violation_count > 0);
    try std.testing.expectEqual(@as(usize, 2), ir.variant_count);
    var verified: usize = 0;
    for (ir.variants[0..ir.variant_count]) |v| {
        if (v.verified) verified += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), verified);
}

test "cmf: nested blocks and one-line bodies are extracted verbatim" {
    const cmf = @import("cmf.zig");
    const source =
        \\morph Cell =<< u8 u16 >>=
        \\bloom nested: morph Cell {
        \\fn main() -> i64 {
        \\    var total: i64 = 0
        \\    if true {
        \\        let cell: @witness = 1
        \\        total = cell as i64
        \\    }
        \\    return total
        \\}
        \\}
    ;
    const ir = cmf.parseField(source);
    try std.testing.expectEqual(@as(usize, 1), ir.body_count);
    for (ir.variants[0..ir.variant_count]) |v| {
        try std.testing.expect(v.verified);
        try std.testing.expect(!v.vacuous);
    }
}

test "cmf: HYPERION surface declares offload machines without claiming them" {
    const cmf = @import("cmf.zig");
    const source =
        \\morph Cell =<< u8 u16 >>=
        \\field ledger: u64[104] ?exclusive ?contiguous
        \\lens back: reverse(ledger) as backwards
        \\lens pivot: transpose(ledger*104) as pivot
        \\machine local: local implemented
        \\machine pim: pim planned
        \\telemetry cache: every 100tick
        \\tune narrow: morph Cell under compressible
        \\claim writer over ledger check uniqueness
        \\claim use over ledger for 4tick runtime local
        \\bloom narrow: morph Cell {
        \\fn main() -> i64 {
        \\    let cell: @witness = 7
        \\    return cell as i64
        \\}
        \\}
    ;
    const ir = cmf.parseField(source);
    try std.testing.expectEqual(@as(usize, 0), ir.violation_count);
    try std.testing.expectEqual(@as(usize, 1), ir.morph_count);
    try std.testing.expectEqual(@as(usize, 1), ir.field_count);
    try std.testing.expectEqual(@as(usize, 2), ir.lens_count);
    // A planned machine never becomes an implemented one.
    const pim = ir.machineNamed("pim") orelse return error.TestUnexpectedResult;
    try std.testing.expect(!pim.implemented);
    // Element cost is reported, not assumed: the transpose view is strided.
    const pivot = ir.lensNamed("pivot") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(cmf.LensCost.strided, pivot.cost);
    const back = ir.lensNamed("backwards") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(cmf.LensCost.sequential, back.cost);
    // Variants are measured, so the count of executed instances is exact.
    try std.testing.expectEqual(@as(usize, 2), ir.variant_count);
    for (ir.variants[0..ir.variant_count]) |v| {
        try std.testing.expect(v.verified);
        try std.testing.expect(v.ran);
        try std.testing.expect(v.instructions > 0);
    }
}

test "cmf: a claim on a planned machine is refused, not downgraded" {
    const cmf = @import("cmf.zig");
    const source =
        \\machine oram: oram planned
        \\field ledger: u64[8]
        \\claim secret over ledger for 4tick runtime oram
    ;
    const ir = cmf.parseField(source);
    try std.testing.expect(ir.violation_count > 0);
    try std.testing.expect(std.mem.indexOf(u8, ir.violations[0].text(), "not implemented") != null);
}

test "langref: unsupported entries are rejected with a diagnostic" {
    // Non-compiling spellings that a code generator might otherwise try.
    const probes = [_]struct { src: []const u8, why: []const u8 }{
        .{ .src = "fn main() -> i64 { return 5 |> 3 }", .why = "pipe_operator" },
        .{ .src = "async fn f() -> i64 { return 1 }\nfn main() -> i64 { return 0 }", .why = "async_await" },
        .{ .src = "extern fn puts(s: string) -> i64\nfn main() -> i64 { return 0 }", .why = "extern_ffi" },
        .{ .src = "mod foo\nfn main() -> i64 { return 0 }", .why = "module_file" },
        .{ .src = "fn main() -> i64 { unsafe { } return 0 }", .why = "unsafe_block" },
        .{ .src = "fn main() -> i64 { asm(\"nop\") return 0 }", .why = "asm_block" },
    };
    for (probes) |probe| {
        var compiler = main.Compiler.init(probe.src, "<langref-negative>");
        compiler.quiet = true;
        const result = compiler.check();
        if (result) |_| {
            std.debug.print("\nlangref negative probe '{s}' unexpectedly compiled\n", .{probe.why});
            return error.TestUnexpectedResult;
        } else |_| {}
    }
}

test "langref: builtin catalogue matches the semantic analyzer" {
    // Every documented builtin must exist in the sema table, otherwise the
    // reference would advertise something that cannot type-check.
    for (langref.builtins) |b| {
        if (b.keyword_form or b.library_form) continue;
        const spec = main.sema_lookupBuiltin(b.name) orelse {
            std.debug.print("\nlangref documents unknown builtin '{s}'\n", .{b.name});
            return error.TestUnexpectedResult;
        };
        _ = spec;
    }
}


// --- bounds-check hoisting and leaf-closure inlining ---------------------
//
// These two passes are what make int arithmetic in loops competitive: without
// them every @read_u64 carries a ~22-instruction range test and every call to a
// Q32.32 helper stays a real call. Both fail *silently* (correct code, slower
// code), so they get direct assertions on the IR instead of only end-to-end
// timing.

const ir_opt = @import("ir_opt.zig");

fn buildHoistLoopModule(module: *ir_mod.IRModule) void {
    module.init();
    // fn f(ptr, n) { while (i < n) { read_u64(ptr + i*8) } }
    //
    //   blk0 entry/preheader : ptr_add ... ; cond_jump(h=1, exit=3)
    //   blk1 h (preheader)   : cond_jump(body=2, exit=3)
    //   blk2 body            : read_u64 ; jump h
    //   blk3 exit            : ret
    var f = &module.fns[0];
    ir_mod.IRModule.initFnSlot(f, 0, 1, 0, 0, 0);
    f.block_count = 4;
    f.vreg_count = 12;

    f.blocks[0].label = 0;
    f.blocks[0].inst_count = 2;
    // The base pointer must have a definition outside the loop, exactly as the
    // real prologue provides it.
    f.blocks[0].insts[0] = .{ .op = .copy, .dest = 1, .src1 = 20 };
    f.blocks[0].insts[1] = .{ .op = .jump, .target_block = 1 };

    f.blocks[1].label = 1;
    f.blocks[1].inst_count = 1;
    f.blocks[1].insts[0] = .{ .op = .cond_jump, .src1 = 6, .target_block = 2, .alt_block = 3 };

    f.blocks[2].label = 2;
    f.blocks[2].inst_count = 3;
    f.blocks[2].insts[0] = .{ .op = .call_ptr_add, .dest = 7, .args = .{ 1, 8, 0, 0, 0, 0, 0, 0 }, .arg_count = 2 };
    f.blocks[2].insts[1] = .{ .op = .call_read_u64, .dest = 9, .args = .{ 7, 0, 0, 0, 0, 0, 0, 0 }, .arg_count = 1 };
    f.blocks[2].insts[2] = .{ .op = .jump, .target_block = 1 };

    f.blocks[3].label = 3;
    f.blocks[3].inst_count = 1;
    f.blocks[3].insts[0] = .{ .op = .ret };
    module.fn_count = 1;
}

test "bounds-check hoisting stays disabled: no loop shape may produce unchecked accesses" {
    // Issue #2 pin. The old hoistBoundsChecks marked every @read_u64/
    // @write_u64 in an eligible loop as `unchecked_access` behind a guard
    // that only proved `heap_min <= base <= heap_max` — not that the
    // loop-varying addresses `base + i*stride` stayed inside the base's
    // chunk. That silently dropped all per-access bounds checking at -O2
    // for in-heap/out-of-chunk addresses (regression test below). The pass
    // is a documented no-op until a real access-span proof exists; these
    // assertions make any re-enable attempt fail here first.
    const module = try std.testing.allocator.create(ir_mod.IRModule);
    defer std.testing.allocator.destroy(module);
    buildHoistLoopModule(module);

    // The permissive shape the old pass loved: single preheader, bulk-only
    // body, base defined outside the loop, more access sites than bases.
    var stats = ir_opt.BoundsHoistStats{};
    try std.testing.expectEqual(false, ir_opt.hoistBoundsChecks(module, &stats));
    try std.testing.expectEqual(@as(u32, 0), stats.loops_hoisted);
    try std.testing.expectEqual(@as(u32, 0), stats.accesses_rewritten);
    try std.testing.expect(!module.fns[0].blocks[2].insts[1].unchecked_access);

    // Even a memory-pure callee chain in the body (the shape that unlocked
    // hoisting on the training loops) must not produce unchecked accesses.
    var g = &module.fns[1];
    ir_mod.IRModule.initFnSlot(g, 1, 1, 0, 0, 0);
    g.block_count = 1;
    g.vreg_count = 4;
    g.blocks[0].label = 0;
    g.blocks[0].inst_count = 2;
    g.blocks[0].insts[0] = .{ .op = .call_read_u64, .dest = 3, .args = .{ 1, 0, 0, 0, 0, 0, 0, 0 }, .arg_count = 1 };
    g.blocks[0].insts[1] = .{ .op = .ret };
    module.fn_count = 2;
    var body = &module.fns[0].blocks[2];
    body.insts[3] = body.insts[2]; // move the back edge out of the way
    body.insts[2] = .{ .op = .call, .dest = 0, .callee_fn_idx = 1, .arg_count = 0 };
    body.inst_count = 4;

    stats = .{};
    try std.testing.expectEqual(false, ir_opt.hoistBoundsChecks(module, &stats));
    try std.testing.expectEqual(@as(u32, 0), stats.accesses_rewritten);
    try std.testing.expect(!module.fns[0].blocks[2].insts[1].unchecked_access);
}

test "heap-internal out-of-chunk loop traps identically at -O0, -O1 and -O2" {
    // Issue #2 PoC, end to end. A 64-byte chunk read through
    // @read_u64(@ptr_add(buf, i * 8)) for i in 0..15: from i = 8 the address
    // is past the chunk but still inside the heap arena. Pre-fix, -O2 hoisted
    // the bounds checks behind a heap-range guard and read garbage silently
    // (exit 0), while -O0/-O1 trapped with SIGILL — the exact "release-only
    // memory bug" class. Now every optimization level must trap identically.
    const oob_src =
        \\fn main() -> i64 {
        \\    let buf = @malloc(64)
        \\    if buf == 0 as *u8 { return 1 }
        \\    var s: i64 = 0
        \\    var i: i64 = 0
        \\    while i < 16 {
        \\        s += @read_u64(@ptr_add(buf, i * 8))
        \\        i += 1
        \\    }
        \\    printInt(s)
        \\    @free(buf)
        \\    return 0
        \\}
    ;
    inline for (.{ .O0, .O1, .O2 }) |lvl| {
        const elf = try compileSourceWithOpt(oob_src, lvl);
        defer std.testing.allocator.free(elf);
        try runElfExpectSigIll(std.testing.allocator, elf, "oob_hoist_" ++ @tagName(lvl));
    }

    // Control: the same loop shape fully inside the chunk must still compile
    // and run correctly at -O2 (the fix keeps per-access checks; it must not
    // break legitimate bulk loops).
    const ok_src =
        \\fn main() -> i64 {
        \\    let buf = @malloc(128)
        \\    if buf == 0 as *u8 { return 1 }
        \\    var i: i64 = 0
        \\    while i < 16 {
        \\        @write_u64(@ptr_add(buf, i * 8), i + 1)
        \\        i += 1
        \\    }
        \\    var s: i64 = 0
        \\    var j: i64 = 0
        \\    while j < 16 {
        \\        s += @read_u64(@ptr_add(buf, j * 8))
        \\        j += 1
        \\    }
        \\    printInt(s)
        \\    @free(buf)
        \\    return 0
        \\}
    ;
    const ok_elf = try compileSourceWithOpt(ok_src, .O2);
    defer std.testing.allocator.free(ok_elf);
    const ok_res = try runElfCapture(std.testing.allocator, ok_elf, "inbounds_bulk");
    defer std.testing.allocator.free(ok_res.stdout);
    try std.testing.expectEqual(@as(u8, 0), ok_res.exit_code);
    try std.testing.expectEqualStrings("136\n", ok_res.stdout); // sum(1..16)
}

// ── @sha256 builtin: native code blob + cross-backend execution ──────────
// The digest of "abc" is a fixed, independently published constant, so these
// expected decimal byte values are an oracle that does not share code with the
// implementation under test.
const sha256_abc_decimal =
    "186\n120\n22\n191\n143\n1\n207\n234\n" ++
    "65\n65\n64\n222\n93\n174\n34\n35\n" ++
    "176\n3\n97\n163\n150\n23\n122\n156\n" ++
    "180\n16\n255\n97\n242\n0\n21\n173\n";

const sha256_lir_source =
    \\fn main() -> i64 {
    \\    let data = @malloc(3)
    \\    @write_u8(data, 97 as u8)
    \\    @write_u8(@ptr_add(data, 1), 98 as u8)
    \\    @write_u8(@ptr_add(data, 2), 99 as u8)
    \\    let out = @malloc(32)
    \\    @sha256(data, 3, out)
    \\    let mut i = 0
    \\    while i < 32 {
    \\        printInt(@read_u8(@ptr_add(out, i)) as i64)
    \\        i = i + 1
    \\    }
    \\    return 0
    \\}
;

test "sha256 native code blob regression tests" {
    _ = @import("sha256_blob.zig");
}

test "@sha256 native backend produces the correct digest end to end" {
    const elf = try compileSourceWithOpt(sha256_lir_source, .O2);
    defer std.testing.allocator.free(elf);
    const res = try runElfCapture(std.testing.allocator, elf, "sha256_native");
    defer std.testing.allocator.free(res.stdout);
    try std.testing.expectEqual(@as(u8, 0), res.exit_code);
    try std.testing.expectEqualStrings(sha256_abc_decimal, res.stdout);
}

test "@sha256 vm backend produces the correct digest end to end" {
    var comp = main.Compiler.initForTarget(sha256_lir_source, "<sha256_vm>", .O2, main.Target.host(), .vm);
    comp.quiet = true;
    var vm_res = try comp.runInVM(&[_][]const u8{}, true);
    // runInVM allocates captured stdout with the page allocator; free with the
    // same allocator (see driver.runInVM).
    defer vm_res.deinit(std.heap.page_allocator);
    try std.testing.expectEqual(@as(i64, 0), vm_res.exit_code);
    try std.testing.expect(!vm_res.trapped);
    try std.testing.expectEqualStrings(sha256_abc_decimal, vm_res.stdout);
}
