// ════════════════════════════════════════════════════════════════════════════
// REPL — Interactive Read-Eval-Print Loop for LIR
// ════════════════════════════════════════════════════════════════════════════

const std = @import("std");
const util = @import("util.zig");
const Compiler = @import("driver.zig").Compiler;
const Target = @import("target.zig").Target;
const parser_mod = @import("parser.zig");
const lexer_mod = @import("lexer.zig");
const diag_mod = @import("diag.zig");
const main_mod = @import("main.zig");

pub fn cmdRepl() void {
    const alloc = std.heap.page_allocator;
    const stdin = std.io.getStdIn().reader();
    const is_tty = std.io.getStdIn().isTty();

    if (is_tty) {
        util.printStr(
            \\LIR Interactive REPL v2.2.0
            \\Type ':help' for commands, ':exit' to quit.
            \\
            \\
        );
    }

    var decls = std.ArrayListUnmanaged(u8){};
    defer decls.deinit(alloc);

    var stmts = std.ArrayListUnmanaged(u8){};
    defer stmts.deinit(alloc);

    var defined_fns = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (defined_fns.items) |name| alloc.free(name);
        defined_fns.deinit(alloc);
    }

    var defined_vars = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (defined_vars.items) |name| alloc.free(name);
        defined_vars.deinit(alloc);
    }

    var multi_buf = std.ArrayListUnmanaged(u8){};
    defer multi_buf.deinit(alloc);

    var line_buf: [4096]u8 = undefined;

    while (true) {
        if (multi_buf.items.len == 0) {
            if (is_tty) util.printStr("lir> ");
        } else {
            if (is_tty) util.printStr("... ");
        }

        const read_slice = stdin.readUntilDelimiterOrEof(&line_buf, '\n') catch |err| {
            if (err == error.StreamTooLong) {
                util.printErr("Error: input line too long (max 4096 bytes)\n");
                multi_buf.clearRetainingCapacity();
                continue;
            }
            break;
        };

        const raw_line = read_slice orelse {
            // EOF (Ctrl-D)
            if (is_tty) util.printStr("\n");
            break;
        };

        var line = std.mem.trim(u8, raw_line, " \t\r");

        // Check for meta-commands on single-line entry
        if (multi_buf.items.len == 0 and line.len > 0 and line[0] == ':') {
            if (std.mem.eql(u8, line, ":exit") or std.mem.eql(u8, line, ":quit") or std.mem.eql(u8, line, ":q")) {
                break;
            } else if (std.mem.eql(u8, line, ":help") or std.mem.eql(u8, line, ":h")) {
                printReplHelp();
                continue;
            } else if (std.mem.eql(u8, line, ":clear")) {
                decls.clearRetainingCapacity();
                stmts.clearRetainingCapacity();
                for (defined_fns.items) |name| alloc.free(name);
                defined_fns.clearRetainingCapacity();
                for (defined_vars.items) |name| alloc.free(name);
                defined_vars.clearRetainingCapacity();
                util.printStr("Session state cleared.\n");
                continue;
            } else if (std.mem.eql(u8, line, ":vars")) {
                if (defined_vars.items.len == 0) {
                    util.printStr("No variables defined in this session.\n");
                } else {
                    util.printStr("Defined variables:\n");
                    for (defined_vars.items) |v| {
                        util.printStr("  ");
                        util.printStr(v);
                        util.printStr("\n");
                    }
                }
                continue;
            } else if (std.mem.eql(u8, line, ":fns")) {
                if (defined_fns.items.len == 0) {
                    util.printStr("No functions defined in this session.\n");
                } else {
                    util.printStr("Defined functions:\n");
                    for (defined_fns.items) |f| {
                        util.printStr("  ");
                        util.printStr(f);
                        util.printStr("\n");
                    }
                }
                continue;
            } else if (std.mem.startsWith(u8, line, ":ast ")) {
                const expr = std.mem.trim(u8, line[5..], " \t");
                dumpReplExprAst(alloc, expr);
                continue;
            } else if (std.mem.startsWith(u8, line, ":ir ")) {
                const expr = std.mem.trim(u8, line[4..], " \t");
                dumpReplExprIr(alloc, decls.items, stmts.items, expr);
                continue;
            } else if (std.mem.startsWith(u8, line, ":explain ")) {
                const topic = std.mem.trim(u8, line[9..], " \t");
                const topic_arr = [_][]const u8{topic};
                main_mod.cmdExplain(&topic_arr);
                continue;
            } else {
                util.printErr("Unknown REPL command '");
                util.printErr(line);
                util.printErr("'. Type ':help' for available commands.\n");
                continue;
            }
        }

        if (line.len == 0 and multi_buf.items.len == 0) {
            continue;
        }

        // Accumulate into multi-line buffer
        if (multi_buf.items.len > 0) {
            multi_buf.append(alloc, '\n') catch continue;
        }
        multi_buf.appendSlice(alloc, raw_line) catch continue;

        // Check if braces are balanced
        const balance = countBraceBalance(multi_buf.items);
        if (balance > 0 and line.len > 0) {
            // Continuation line needed
            continue;
        }

        const full_input = std.mem.trim(u8, multi_buf.items, " \t\r\n");
        multi_buf.clearRetainingCapacity();

        if (full_input.len == 0) continue;

        // Evaluate input
        evalReplInput(alloc, full_input, &decls, &stmts, &defined_fns, &defined_vars);
    }
}

fn printReplHelp() void {
    util.printStr(
        \\REPL Commands:
        \\  :help, :h          Show this help message
        \\  :vars              List variables defined in this session
        \\  :fns               List functions defined in this session
        \\  :clear             Reset session state (variables & declarations)
        \\  :ast <expr>        Pretty-print the Abstract Syntax Tree for <expr>
        \\  :ir <expr>         Show the lowered, optimized IR for <expr>
        \\  :explain <topic>   Read language reference on topics (borrow, contracts, purity, etc.)
        \\  :exit, :quit, :q   Exit the REPL
        \\
        \\Syntax Examples:
        \\  lir> 10 + 20 * 3
        \\  => 70
        \\  lir> let x = 42
        \\  x = 42
        \\  lir> fn double(n: i64) -> i64 { return n * 2 }
        \\  Defined: fn double
        \\  lir> double(x)
        \\  => 84
        \\  lir> "hello " + "world"
        \\  => hello world
        \\
    );
}

fn countBraceBalance(src: []const u8) i32 {
    var depth: i32 = 0;
    var in_str = false;
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        const c = src[i];
        if (c == '\\' and in_str) {
            i += 1;
            continue;
        }
        if (c == '"') {
            in_str = !in_str;
            continue;
        }
        if (in_str) continue;
        if (c == '{' or c == '(' or c == '[') depth += 1;
        if (c == '}' or c == ')' or c == ']') depth -= 1;
    }
    return depth;
}

fn isDeclaration(input: []const u8) bool {
    const trimmed = std.mem.trimLeft(u8, input, " \t\r\n");
    return std.mem.startsWith(u8, trimmed, "fn ") or
        std.mem.startsWith(u8, trimmed, "struct ") or
        std.mem.startsWith(u8, trimmed, "enum ") or
        std.mem.startsWith(u8, trimmed, "union ") or
        std.mem.startsWith(u8, trimmed, "trait ") or
        std.mem.startsWith(u8, trimmed, "impl ") or
        std.mem.startsWith(u8, trimmed, "type ") or
        std.mem.startsWith(u8, trimmed, "const ") or
        std.mem.startsWith(u8, trimmed, "import ") or
        std.mem.startsWith(u8, trimmed, "use ");
}

fn isLetOrVar(input: []const u8) bool {
    const trimmed = std.mem.trimLeft(u8, input, " \t\r\n");
    return std.mem.startsWith(u8, trimmed, "let ") or
        std.mem.startsWith(u8, trimmed, "var ");
}

fn extractDeclName(input: []const u8) ?[]const u8 {
    var it = std.mem.tokenizeAny(u8, input, " \t\r\n({<;");
    _ = it.next(); // skip keyword (fn, struct, let, etc.)
    return it.next();
}

fn evalReplInput(
    alloc: std.mem.Allocator,
    input: []const u8,
    decls: *std.ArrayListUnmanaged(u8),
    stmts: *std.ArrayListUnmanaged(u8),
    defined_fns: *std.ArrayListUnmanaged([]const u8),
    defined_vars: *std.ArrayListUnmanaged([]const u8),
) void {
    if (isDeclaration(input)) {
        // Test compile declaration alongside existing decls
        var test_src = std.ArrayListUnmanaged(u8){};
        defer test_src.deinit(alloc);

        test_src.appendSlice(alloc, decls.items) catch return;
        test_src.appendSlice(alloc, input) catch return;
        test_src.appendSlice(alloc, "\nfn main() -> i64 { return 0 }\n") catch return;

        var compiler = Compiler.init(test_src.items, "<repl>");
        compiler.quiet = true;
        _ = compiler.runInVM(&.{}, true) catch {
            // Re-run loudly to print error to stderr
            compiler.quiet = false;
            _ = compiler.runInVM(&.{}, true) catch {};
            return;
        };

        // Success: persist declaration
        decls.appendSlice(alloc, input) catch return;
        decls.append(alloc, '\n') catch return;

        if (extractDeclName(input)) |name| {
            defined_fns.append(alloc, alloc.dupe(u8, name) catch return) catch return;
            util.printStr("Defined: ");
            util.printStr(name);
            util.printStr("\n");
        } else {
            util.printStr("Defined declaration.\n");
        }
        return;
    }

    if (isLetOrVar(input)) {
        // Test compile statement alongside existing decls & stmts
        var test_src = std.ArrayListUnmanaged(u8){};
        defer test_src.deinit(alloc);

        test_src.appendSlice(alloc, decls.items) catch return;
        test_src.appendSlice(alloc, "\nfn main() -> i64 {\n") catch return;
        test_src.appendSlice(alloc, stmts.items) catch return;
        test_src.appendSlice(alloc, input) catch return;
        test_src.appendSlice(alloc, ";\nreturn 0;\n}\n") catch return;

        var compiler = Compiler.init(test_src.items, "<repl>");
        compiler.quiet = true;
        _ = compiler.runInVM(&.{}, true) catch {
            // Re-run loudly to print error
            compiler.quiet = false;
            _ = compiler.runInVM(&.{}, true) catch {};
            return;
        };

        // Success: persist statement
        stmts.appendSlice(alloc, input) catch return;
        stmts.appendSlice(alloc, ";\n") catch return;

        if (extractDeclName(input)) |vname| {
            defined_vars.append(alloc, alloc.dupe(u8, vname) catch return) catch return;
            util.printStr(vname);
            util.printStr(" defined\n");
        } else {
            util.printStr("Defined variable.\n");
        }
        return;
    }

    // Try evaluating as integer/bool expression
    {
        var expr_src = std.ArrayListUnmanaged(u8){};
        defer expr_src.deinit(alloc);

        expr_src.appendSlice(alloc, decls.items) catch return;
        expr_src.appendSlice(alloc, "\nfn main() -> i64 {\n") catch return;
        expr_src.appendSlice(alloc, stmts.items) catch return;
        expr_src.appendSlice(alloc, "let _repl_v = (") catch return;
        expr_src.appendSlice(alloc, input) catch return;
        expr_src.appendSlice(alloc, ");\nprintInt(_repl_v);\nreturn 0;\n}\n") catch return;

        var compiler = Compiler.init(expr_src.items, "<repl>");
        compiler.quiet = true;
        if (compiler.runInVM(&.{}, true)) |vm_res| {
            var res = vm_res;
            defer res.deinit(alloc);
            if (res.stdout.len > 0) {
                util.printStr("=> ");
                util.printStr(res.stdout);
            }
            return;
        } else |_| {}
    }

    // Try evaluating as string expression
    {
        var expr_src = std.ArrayListUnmanaged(u8){};
        defer expr_src.deinit(alloc);

        expr_src.appendSlice(alloc, decls.items) catch return;
        expr_src.appendSlice(alloc, "\nfn main() -> i64 {\n") catch return;
        expr_src.appendSlice(alloc, stmts.items) catch return;
        expr_src.appendSlice(alloc, "let _repl_v = (") catch return;
        expr_src.appendSlice(alloc, input) catch return;
        expr_src.appendSlice(alloc, ");\nprintln(_repl_v);\nreturn 0;\n}\n") catch return;

        var compiler = Compiler.init(expr_src.items, "<repl>");
        compiler.quiet = true;
        if (compiler.runInVM(&.{}, true)) |vm_res| {
            var res = vm_res;
            defer res.deinit(alloc);
            if (res.stdout.len > 0) {
                util.printStr("=> ");
                util.printStr(res.stdout);
            }
            return;
        } else |_| {}
    }

    // Try evaluating as float expression
    {
        var expr_src = std.ArrayListUnmanaged(u8){};
        defer expr_src.deinit(alloc);

        expr_src.appendSlice(alloc, decls.items) catch return;
        expr_src.appendSlice(alloc, "\nfn main() -> i64 {\n") catch return;
        expr_src.appendSlice(alloc, stmts.items) catch return;
        expr_src.appendSlice(alloc, "let _repl_v = (") catch return;
        expr_src.appendSlice(alloc, input) catch return;
        expr_src.appendSlice(alloc, ");\nprintlnFloat(_repl_v);\nreturn 0;\n}\n") catch return;

        var compiler = Compiler.init(expr_src.items, "<repl>");
        compiler.quiet = true;
        if (compiler.runInVM(&.{}, true)) |vm_res| {
            var res = vm_res;
            defer res.deinit(alloc);
            if (res.stdout.len > 0) {
                util.printStr("=> ");
                util.printStr(res.stdout);
            }
            return;
        } else |_| {}
    }

    // Try evaluating as arbitrary statement or void call (e.g. println("hi"), while loops, etc.)
    {
        var stmt_src = std.ArrayListUnmanaged(u8){};
        defer stmt_src.deinit(alloc);

        stmt_src.appendSlice(alloc, decls.items) catch return;
        stmt_src.appendSlice(alloc, "\nfn main() -> i64 {\n") catch return;
        stmt_src.appendSlice(alloc, stmts.items) catch return;
        stmt_src.appendSlice(alloc, input) catch return;
        stmt_src.appendSlice(alloc, ";\nreturn 0;\n}\n") catch return;

        var compiler = Compiler.init(stmt_src.items, "<repl>");
        compiler.quiet = true;
        if (compiler.runInVM(&.{}, true)) |vm_res| {
            var res = vm_res;
            defer res.deinit(alloc);
            if (res.stdout.len > 0) {
                util.printStr(res.stdout);
            }
            return;
        } else |_| {
            // All attempts failed; re-run loudly to display exact compiler diagnostic
            compiler.quiet = false;
            _ = compiler.runInVM(&.{}, true) catch {};
        }
    }
}

fn dumpReplExprAst(alloc: std.mem.Allocator, expr: []const u8) void {
    const wrap = std.fmt.allocPrint(alloc, "fn main() -> i64 {{ let _ = ({s}); return 0 }}", .{expr}) catch return;
    defer alloc.free(wrap);

    var diag = diag_mod.DiagList.init();
    const lexer = alloc.create(lexer_mod.Lexer) catch return;
    defer alloc.destroy(lexer);
    lexer.* = lexer_mod.Lexer.init(wrap);
    lexer.tokenize();

    const ast = alloc.create(parser_mod.AST) catch return;
    defer alloc.destroy(ast);
    ast.initInPlace();
    ast.sources[0] = wrap;
    ast.source_count = 1;

    var parser = parser_mod.Parser{
        .lex = lexer,
        .pos = 0,
        .ast = ast,
        .src = wrap,
        .source_id = 0,
        .diag = &diag,
    };
    parser.parse();

    if (diag.hasErrors()) {
        diag.emitAll("<repl:ast>", wrap);
        return;
    }
    main_mod.dumpAST(ast, wrap);
}

fn dumpReplExprIr(alloc: std.mem.Allocator, decls: []const u8, stmts: []const u8, expr: []const u8) void {
    const wrap = std.fmt.allocPrint(alloc, "{s}\nfn main() -> i64 {{\n{s}\nlet _res = ({s});\nreturn _res;\n}}\n", .{ decls, stmts, expr }) catch return;
    defer alloc.free(wrap);

    var compiler = Compiler.init(wrap, "<repl:ir>");
    compiler.emit_ir = true;
    _ = compiler.runInVM(&.{}, true) catch {};
}
