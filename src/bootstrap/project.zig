//! Safe starter-project creation. Existing directories are never modified.
const std = @import("std");

pub fn validName(name: []const u8) bool {
    if (name.len == 0 or name.len > 128 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) return false;
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_' and c != '.') return false;
    }
    return true;
}

/// One-line orientation file that makes any agent (or human) productive
/// immediately: the invariants that most often cause a failed first attempt.
pub const agent_guide =
    \\# LIR — orientation for AI agents and new contributors
    \\
    \\This project is written in LIR. The compiler is `lir` (Ziglir bootstrap,
    \\implemented in Zig). Before writing code, orient yourself with the
    \\*compiler itself* instead of guessing from C/Rust/Zig habits:
    \\
    \\```sh
    \\lir lang --json                 # every feature: status + compilable example
    \\lir lang --keywords             # reserved words: never use these as names
    \\lir lang --cheatsheet           # whole language on one page
    \\lir lang <feature>              # canonical syntax, notes, "avoid" list
    \\lir builtins --json             # every builtin + signature
    \\lir explain ai                  # agent integration workflow
    \\lir explain limitations         # constructs that DO NOT compile
    \\lir check file.lir --json       # validate; diagnostics on stderr as JSON
    \\lir run file.lir --backend=vm   # execute anywhere, no toolchain needed
    \\```
    \\
    \\Non-obvious rules that break generated code most often:
    \\
    \\1. Statements are newline separated. No trailing `;` is needed; never use
    \\   `;` between `if` and `else`.
    \\2. Every control-flow body needs braces. `if c { } else { }`, `while c { }`.
    \\3. Use `fn` (not `proc`), `let mut` (not `var`), `and`/`or`/`!` (no `not`).
    \\4. Closures are `|x: i64| x + 1`; `fn(x){}` literals and nested `fn` are
    \\   not supported.
    \\5. Numeric conversions are always explicit: write `x as i64`.
    \\6. Printing: `print`/`println` take strings only, numbers use `printInt`,
    \\   `printFloat`. Interpolation is `"{a + b}"` with no format specifiers.
    \\7. `match` is an expression and must be exhaustive: add a `_` arm for
    \\   integers.
    \\8. `Some`/`None`/`Ok`/`Err` need context; write `let x: ?i64 = None`.
    \\9. Arrays: `[1, 2, 3]` is fixed-size; `@array_new` is growable, and
    \\   `for i, v in arr` does not exist.
    \\10. Do not emit `unsafe`, `asm`, `extern`, `mod`, `async`/`await`,
    \\    `i128`, `char`, labels or slice ranges: they are rejected.
    \\11. Reserved words are never identifiers. Get the list from
    \\    `lir lang --keywords` before inventing names (`type`, `string`, `as`,
    \\    `in`, `match`, `loop`, `spawn` … are all reserved).
    \\
    \\ALWAYS validate before claiming success:
    \\
    \\```sh
    \\lir check src/main.lir --json     # status must be "ok"
    \\lir test                          # run the #[test] suite
    \\```
    \\
    \\Canonical reference: docs/AI.md (machine contracts) and
    \\docs/LANGUAGE_REFERENCE.md (generated catalogue).
    \\
;

/// Machine-readable capability manifest written next to `project.manifest`
/// when `lir init --ai` is used. Deliberately small: it points at the commands
/// that produce the authoritative data instead of duplicating it.
pub const agent_manifest =
    \\{
    \\  "schema": "lir.agent.v1",
    \\  "language": "lir",
    \\  "compiler": "ziglir-bootstrap",
    \\  "commands": {
    \\    "catalogue": "lir lang --json",
    \\    "builtins": "lir builtins --json",
    \\    "check": "lir check <file> --json",
    \\    "run": "lir run <file> --backend=vm",
    \\    "test": "lir test"
    \\  },
    \\  "diagnostics": "lir.diagnostics.v1 (stderr JSON, stable codes LIR-Exxxx)",
    \\  "exit_codes": { "ok": 0, "compile_error": 1, "trap": 132 },
    \\  "validate_before_claiming_success": true
    \\}
    \\
;

pub fn create(parent: std.fs.Dir, name: []const u8) !void {
    if (!validName(name)) return error.InvalidProjectName;
    // Unlike makePath, makeDir fails if the destination already exists.
    try parent.makeDir(name);
    errdefer parent.deleteTree(name) catch {};
    var dir = try parent.openDir(name, .{});
    defer dir.close();
    try dir.makeDir("src");
    var manifest_buf: [512]u8 = undefined;
    const manifest = try std.fmt.bufPrint(&manifest_buf,
        \\{{
        \\  "name": "{s}",
        \\  "version": "0.1.0",
        \\  "entry": "main.lir",
        \\  "source_dir": "src",
        \\  "test_entry": "tests.lir"
        \\}}
        \\
    , .{name});
    const manifest_file = try dir.createFile("project.manifest", .{ .exclusive = true });
    defer manifest_file.close();
    try manifest_file.writeAll(manifest);
    const source_file = try dir.createFile("src/main.lir", .{ .exclusive = true });
    defer source_file.close();
    try source_file.writeAll(
        \\// Main entry point
        \\import core
        \\import "lib.lir"
        \\
        \\fn main() -> i64 {
        \\    println(greeting())
        \\    0
        \\}
        \\
    );
    const library_file = try dir.createFile("src/lib.lir", .{ .exclusive = true });
    defer library_file.close();
    try library_file.writeAll("fn greeting() -> string { return \"Hello from LIR!\" }\n");
    const tests_file = try dir.createFile("src/tests.lir", .{ .exclusive = true });
    defer tests_file.close();
    try tests_file.writeAll(
        \\import "lib.lir"
        \\#[test]
        \\fn greeting_test() {
        \\    @assert(greeting() == "Hello from LIR!")
        \\}
        \\ 
    );
    const ignore_file = try dir.createFile(".gitignore", .{ .exclusive = true });
    defer ignore_file.close();
    try ignore_file.writeAll("*.out\n*.out.exe\n*.out.wasm\n");
}

/// Adds AI-facing scaffolding (AGENTS.md + lir.agent.json) to a project that
/// was just created. Kept separate so plain `lir init` stays minimal.
pub fn addAgentScaffold(parent: std.fs.Dir, name: []const u8) !void {
    var dir = try parent.openDir(name, .{});
    defer dir.close();
    const agents = try dir.createFile("AGENTS.md", .{ .exclusive = true });
    defer agents.close();
    try agents.writeAll(agent_guide);
    const manifest = try dir.createFile("lir.agent.json", .{ .exclusive = true });
    defer manifest.close();
    try manifest.writeAll(agent_manifest);
}

test "project names reject traversal and unsafe paths" {
    for ([_][]const u8{ "", ".", "..", "../demo", "a/b", "a\\b", "a\"b", "a\nb" }) |name| {
        try std.testing.expect(!validName(name));
    }
    try std.testing.expect(validName("hello-world_2.0"));
    try std.testing.expect(!validName(&([_]u8{'a'} ** 129)));
}

test "project creation is isolated and never overwrites existing work" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try create(tmp.dir, "demo");
    const source = try tmp.dir.readFileAlloc(std.testing.allocator, "demo/src/main.lir", 4096);
    defer std.testing.allocator.free(source);
    try std.testing.expect(std.mem.indexOf(u8, source, "fn main()") != null);
    const manifest = try tmp.dir.readFileAlloc(std.testing.allocator, "demo/project.manifest", 4096);
    defer std.testing.allocator.free(manifest);
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, manifest, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("demo", parsed.value.object.get("name").?.string);
    try std.testing.expectError(error.PathAlreadyExists, create(tmp.dir, "demo"));
    const after = try tmp.dir.readFileAlloc(std.testing.allocator, "demo/src/main.lir", 4096);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualStrings(source, after);
    try std.testing.expectError(error.InvalidProjectName, create(tmp.dir, ".."));
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("project.manifest", .{}));
}
