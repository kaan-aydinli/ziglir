// ════════════════════════════════════════════════════════════════════════════
// LANGCMD — `lir lang` and `lir builtins` implementations
//
// Both commands render `langref.zig`, the single source of truth for the
// implemented language surface. Formats:
//   human (default) | --json | --markdown | --short
// Filters:
//   --status=supported|partial|legacy|unsupported
//   --category=declaration|statement|expression|type|attribute|builtin|pattern
//
// Exit codes: 0 success, 1 unknown feature/format/filter.
// ════════════════════════════════════════════════════════════════════════════

const std = @import("std");
const util = @import("util.zig");
const langref = @import("langref.zig");
const lex = @import("lexer.zig");
const diag_mod = @import("diag.zig");

const printStr = util.printStr;
const printErr = util.printErr;
const printUsize = util.printUsize;
const eql = util.eql;

const OutFormat = enum { human, json, markdown, short };

fn parseOutFormat(s: []const u8) ?OutFormat {
    if (eql(s, "human") or eql(s, "text")) return .human;
    if (eql(s, "json")) return .json;
    if (eql(s, "markdown") or eql(s, "md")) return .markdown;
    if (eql(s, "short")) return .short;
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

const Filter = struct {
    status: ?langref.Status = null,
    category: ?langref.Category = null,
    group: ?[]const u8 = null,

    fn acceptsFeature(self: Filter, f: langref.Feature) bool {
        if (self.status) |s| if (f.status != s) return false;
        if (self.category) |c| if (f.category != c) return false;
        return true;
    }

    fn acceptsBuiltin(self: Filter, b: langref.Builtin) bool {
        if (self.status != null and self.status.? != .supported) return false;
        if (self.category != null and self.category.? != .builtin) return false;
        if (self.group) |g| if (!eql(b.group, g)) return false;
        return true;
    }
};

fn parseFilterWith(args: []const []const u8, filter: *Filter, out_fmt: *OutFormat, selector: *?[]const u8) void {
    var idx: usize = 0;
    while (idx < args.len) : (idx += 1) {
        const arg = args[idx];
        if (eql(arg, "--json")) {
            out_fmt.* = .json;
        } else if (eql(arg, "--markdown") or eql(arg, "--md")) {
            out_fmt.* = .markdown;
        } else if (eql(arg, "--short")) {
            out_fmt.* = .short;
        } else if (eql(arg, "--human")) {
            out_fmt.* = .human;
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            out_fmt.* = parseOutFormat(arg["--format=".len..]) orelse unknownFormat(arg["--format=".len..]);
        } else if (eql(arg, "--keywords") or eql(arg, "--reserved")) {
            // handled by the caller; accepted here so it is not an unknown option
        } else if (eql(arg, "--cheatsheet") or eql(arg, "--cheat")) {
            // handled by the caller
        } else if (std.mem.startsWith(u8, arg, "--out=")) {
            out_fmt.* = parseOutFormat(arg["--out=".len..]) orelse unknownFormat(arg["--out=".len..]);
        } else if (std.mem.startsWith(u8, arg, "--status=")) {
            filter.status = langref.Status.parse(arg["--status=".len..]) orelse unknownStatus(arg["--status=".len..]);
        } else if (std.mem.startsWith(u8, arg, "--category=")) {
            const cat = arg["--category=".len..];
            filter.category = if (eql(cat, "declaration")) .declaration else if (eql(cat, "statement")) .statement else if (eql(cat, "expression")) .expression else if (eql(cat, "type") or eql(cat, "type_syntax")) .type_syntax else if (eql(cat, "attribute")) .attribute else if (eql(cat, "builtin")) .builtin else if (eql(cat, "pattern")) .pattern else unknownCategory(cat);
        } else if (std.mem.startsWith(u8, arg, "--group=")) {
            filter.group = arg["--group=".len..];
        } else if (arg.len > 0 and arg[0] == '-') {
            printErr("Error: unknown option '");
            printErr(arg);
            printErr("'\n");
            util.sysExit(1);
        } else if (selector.* == null) {
            selector.* = arg;
        } else {
            printErr("Error: unexpected extra argument '");
            printErr(arg);
            printErr("'\n");
            util.sysExit(1);
        }
    }
}

fn unknownFormat(spec: []const u8) noreturn {
    printErr("Error: unknown output format '");
    printErr(spec);
    printErr("' (expected human, json, markdown, or short)\n");
    util.sysExit(1);
}

fn unknownStatus(spec: []const u8) noreturn {
    printErr("Error: unknown status '");
    printErr(spec);
    printErr("' (expected supported, partial, legacy, or unsupported)\n");
    util.sysExit(1);
}

fn unknownCategory(spec: []const u8) noreturn {
    printErr("Error: unknown category '");
    printErr(spec);
    printErr("' (expected declaration, statement, expression, type, attribute, builtin, or pattern)\n");
    util.sysExit(1);
}

// ════════════════════════════════════════════════════════════════════════════
// lir lang
// ════════════════════════════════════════════════════════════════════════════

pub fn cmdLang(args: []const []const u8) void {
    var filter = Filter{};
    var out_fmt: OutFormat = .human;
    var selector: ?[]const u8 = null;
    var print_keywords = false;
    var print_cheatsheet = false;
    var wants_help = false;
    for (args) |arg| {
        if (eql(arg, "--keywords") or eql(arg, "--reserved")) print_keywords = true;
        if (eql(arg, "--cheatsheet") or eql(arg, "--cheat")) print_cheatsheet = true;
        if (eql(arg, "--help") or eql(arg, "-h")) wants_help = true;
    }

    if (wants_help) {
        printLangHelp();
        return;
    }
    parseFilterWith(args, &filter, &out_fmt, &selector);

    if (print_keywords) {
        renderKeywords(out_fmt);
        return;
    }

    if (print_cheatsheet) {
        renderCheatsheet();
        return;
    }

    if (selector) |name| {
        const f = langref.featureByName(name) orelse {
            printErr("Error: unknown language feature '");
            printErr(name);
            printErr("'. Run 'lir lang --short' to list feature names.\n");
            util.sysExit(1);
        };
        renderFeatureDetail(f, out_fmt);
        return;
    }

    switch (out_fmt) {
        .json => renderLangJson(filter),
        .markdown => renderLangMarkdown(filter),
        .short => renderLangShort(filter),
        .human => renderLangHuman(filter),
    }
}

fn printLangHelp() void {
    printStr(
        \\Usage: lir lang [feature] [options]
        \\
        \\Prints the implemented LIR language surface. This command is the
        \\authoritative answer to "does LIR support X?"; the table is compiled and
        \\executed by 'zig build test', so it cannot silently drift from the compiler.
        \\
        \\Options:
        \\  --json                 Machine-readable catalogue (schema lir.lang.v1)
        \\  --keywords             Only the reserved-word list (with --json: lir.keywords.v1)
        \\  --cheatsheet           One-page generated summary for small context windows
        \\  --markdown             Markdown reference (used to generate docs/)
        \\  --short                One line per feature: name status category
        \\  --format=<fmt>         human | json | markdown | short
        \\  --status=<s>           supported | partial | legacy | unsupported
        \\  --category=<c>         declaration | statement | expression | type | attribute
        \\
        \\Examples:
        \\  lir lang
        \\  lir lang closure
        \\  lir lang --status=unsupported --short
        \\  lir lang --json > lang.json
        \\  lir lang --markdown > docs/LANGUAGE_REFERENCE.md
        \\
    );
}

fn categoryTitle(c: langref.Category) []const u8 {
    return switch (c) {
        .declaration => "Declarations",
        .statement => "Statements",
        .expression => "Expressions",
        .type_syntax => "Types",
        .attribute => "Attributes",
        .builtin => "Builtins",
        .pattern => "Patterns",
    };
}

const category_order = [_]langref.Category{ .declaration, .statement, .expression, .type_syntax, .pattern, .attribute, .builtin };

fn renderLangHuman(filter: Filter) void {
    printStr("LIR language reference (bootstrap compiler)\n\n");
    printStr("Status legend: supported = safe to generate, partial = read notes first,\n");
    printStr("legacy = accepted but prefer the canonical spelling, unsupported = rejected.\n\n");
    for (category_order) |cat| {
        if (filter.category) |only| if (only != cat) continue;
        var printed_header = false;
        for (langref.features) |f| {
            if (f.category != cat) continue;
            if (!filter.acceptsFeature(f)) continue;
            if (!printed_header) {
                printStr("── ");
                printStr(categoryTitle(cat));
                printStr("\n");
                printed_header = true;
            }
            printStr("  ");
            printStr(f.name);
            const pad = if (f.name.len < 24) 24 - f.name.len else 1;
            var i: usize = 0;
            while (i < pad) : (i += 1) printStr(" ");
            printStr("[");
            printStr(f.status.label());
            printStr("] ");
            printStr(f.syntax);
            printStr("\n");
        }
        if (printed_header) printStr("\n");
    }
    var su: usize = 0;
    var pa: usize = 0;
    var le: usize = 0;
    var no: usize = 0;
    for (langref.features) |f| switch (f.status) {
        .supported => su += 1,
        .partial => pa += 1,
        .legacy => le += 1,
        .unsupported => no += 1,
    };
    printStr("Totals: ");
    printUsize(su);
    printStr(" supported, ");
    printUsize(pa);
    printStr(" partial, ");
    printUsize(le);
    printStr(" legacy, ");
    printUsize(no);
    printStr(" unsupported. Detailed help: lir lang <feature>\n");
    printStr("Machine-readable: lir lang --json   Builtins: lir builtins --json\n");
}

fn renderLangShort(filter: Filter) void {
    for (langref.features) |f| {
        if (!filter.acceptsFeature(f)) continue;
        printStr(f.name);
        printStr(" ");
        printStr(f.status.label());
        printStr(" ");
        printStr(f.category.label());
        printStr("\n");
    }
}

fn renderFeatureDetail(f: *const langref.Feature, out_fmt: OutFormat) void {
    switch (out_fmt) {
        .json => {
            printStr("{\"schema\":\"lir.lang.v1\",\"feature\":");
            writeFeatureJson(f.*);
            printStr("}\n");
        },
        .markdown => writeFeatureMarkdown(f.*),
        .short => {
            printStr(f.name);
            printStr(" ");
            printStr(f.status.label());
            printStr(" ");
            printStr(f.category.label());
            printStr("\n");
        },
        .human => {
            printStr("══ ");
            printStr(f.name);
            printStr(" ══\n");
            printStr("status:   ");
            printStr(f.status.label());
            printStr("\ncategory: ");
            printStr(f.category.label());
            printStr("\nsyntax:\n  ");
            printStr(f.syntax);
            printStr("\n\nnotes:\n  ");
            printStr(f.notes);
            printStr("\n");
            if (f.prefer.len > 0) {
                printStr("\nprefer:\n  ");
                printStr(f.prefer);
                printStr("\n");
            }
            if (f.avoid.len > 0) {
                printStr("\navoid:\n  ");
                printStr(f.avoid);
                printStr("\n");
            }
            if (f.example.len > 0) {
                printStr("\nexample:\n");
                writeIndented(f.example, "  ");
                printStr("\n");
            }
        },
    }
}

fn writeIndented(text: []const u8, prefix: []const u8) void {
    printStr(prefix);
    for (text) |ch| {
        const one = [_]u8{ch};
        printStr(one[0..]);
        if (ch == '\n' and text.len > 0) printStr(prefix);
    }
}

fn writeFeatureJson(f: langref.Feature) void {
    printStr("{\"name\":");
    jsonStr(f.name);
    printStr(",\"status\":");
    jsonStr(f.status.label());
    printStr(",\"category\":");
    jsonStr(f.category.label());
    printStr(",\"syntax\":");
    jsonStr(f.syntax);
    printStr(",\"notes\":");
    jsonStr(f.notes);
    if (f.example.len > 0) {
        printStr(",\"example\":");
        jsonStr(f.example);
    }
    if (f.avoid.len > 0) {
        printStr(",\"avoid\":");
        jsonStr(f.avoid);
    }
    if (f.prefer.len > 0) {
        printStr(",\"prefer\":");
        jsonStr(f.prefer);
    }
    printStr("}");
}

fn renderLangJson(filter: Filter) void {
    printStr("{\"schema\":\"lir.lang.v1\",\"language\":\"lir\",\"compiler\":\"ziglir-bootstrap\",\"features\":[");
    var first = true;
    for (langref.features) |f| {
        if (!filter.acceptsFeature(f)) continue;
        if (!first) printStr(",");
        first = false;
        writeFeatureJson(f);
    }
    printStr("],\"keywords\":[");
    for (lex.keyword_entries, 0..) |entry, i| {
        if (i != 0) printStr(",");
        jsonStr(entry.word);
    }
    printStr("],\"counts\":{\"supported\":");
    printUsize(langref.countByStatus(.supported));
    printStr(",\"partial\":");
    printUsize(langref.countByStatus(.partial));
    printStr(",\"legacy\":");
    printUsize(langref.countByStatus(.legacy));
    printStr(",\"unsupported\":");
    printUsize(langref.countByStatus(.unsupported));
    printStr("}}\n");
    _ = diag_mod.default_format;
}

/// One compact page derived from the catalogue: enough to generate valid LIR
/// inside a small context window. Generated, not hand-written, so it cannot
/// drift from the compiler (CI diffs docs/CHEATSHEET.md against this output).
fn renderCheatsheet() void {
    printStr("# LIR cheatsheet (generated by `lir lang --cheatsheet`)\n\n");
    printStr("Language surface: ");
    printUsize(langref.countByStatus(.supported));
    printStr(" supported constructs, ");
    printUsize(lex.keyword_entries.len);
    printStr(" reserved words, ");
    printUsize(langref.builtins.len);
    printStr(" builtins. Validate with `lir check f.lir --json`; run with `lir run f.lir --backend=vm`.\n\n");

    printStr("## Program skeleton\n\n```lir\nfn main() -> i64 {\n    println(\"hello\")\n    return 0\n}\n```\n\n");
    printStr("Exactly one `fn main() -> i64`; its return value is the exit code. Newline-separated statements, braces on every block, no `not`, no `;` between blocks.\n\n");

    for (category_order) |cat| {
        printStr("## ");
        printStr(categoryTitle(cat));
        printStr("\n\n| Construct | Canonical form | Notes |\n|---|---|---|\n");
        for (langref.features) |f| {
            if (f.category != cat) continue;
            if (f.status != .supported) continue;
            printStr("| `");
            printStr(f.name);
            printStr("` | `");
            writeOneLine(f.syntax);
            printStr("` | ");
            writeShort(f.notes, 110);
            printStr(" |\n");
        }
        printStr("\n");
    }

    printStr("## Do not emit (rejected by the compiler)\n\n| Construct | Why / instead |\n|---|---|\n");
    for (langref.features) |f| {
        if (f.status == .supported) continue;
        printStr("| `");
        printStr(f.name);
        printStr("` (");
        printStr(f.status.label());
        printStr(") | ");
        if (f.avoid.len > 0) {
            writeOneLine(f.avoid);
        } else {
            writeShort(f.notes, 120);
        }
        printStr(" |\n");
    }
    printStr("\n## Reserved words (never identifiers)\n\n");
    for (lex.keyword_entries, 0..) |entry, i| {
        printStr("`");
        printStr(entry.word);
        printStr("`");
        if (i + 1 != lex.keyword_entries.len) printStr(", ");
    }
    printStr("\n\n## Builtins\n\n| Builtin | Signature |\n|---|---|\n");
    for (langref.builtins) |b| {
        printStr("| `");
        printStr(b.name);
        printStr("` | `");
        printStr(b.signature);
        printStr("` |\n");
    }
    printStr("\n## Repair loop\n\n```sh\nlir check f.lir --json   # status \"ok\" => valid\nlir run f.lir --backend=vm\n```\n\nDiagnostics: `code`, `help`, `expect{kind,value}` (`lir.diagnostics.v1`). Codes: `lir explain --list`.\n");
}

/// Collapses a multi-line syntax field onto one table cell.
fn writeOneLine(text: []const u8) void {
    var last_was_space = false;
    var wrote = false;
    for (text) |ch| {
        if (ch == '\n' or ch == '\r' or ch == '\t') {
            if (wrote and !last_was_space) printStr(" ");
            last_was_space = true;
            continue;
        }
        if (ch == '|') {
            printStr("\\|");
            last_was_space = false;
            wrote = true;
            continue;
        }
        const one = [_]u8{ch};
        printStr(one[0..]);
        last_was_space = ch == ' ';
        wrote = true;
    }
}

/// Prints at most `max` bytes of a note, cut at a word boundary.
fn writeShort(text: []const u8, max: usize) void {
    var end = @min(text.len, max);
    if (end < text.len) {
        while (end > 0 and text[end] != ' ') end -= 1;
        if (end == 0) end = @min(text.len, max);
    }
    writeOneLine(text[0..end]);
    if (end < text.len) printStr(" …");
}

fn renderKeywords(fmt: OutFormat) void {
    switch (fmt) {
        .json => {
            printStr("{\"schema\":\"lir.keywords.v1\",\"language\":\"lir\",\"count\":");
            printUsize(lex.keyword_entries.len);
            printStr(",\"keywords\":[");
            for (lex.keyword_entries, 0..) |entry, i| {
                if (i != 0) printStr(",");
                jsonStr(entry.word);
            }
            printStr("]}\n");
        },
        else => {
            for (lex.keyword_entries) |entry| {
                printStr(entry.word);
                if (fmt == .human) {
                    printStr("\t");
                    printStr(@tagName(entry.kind));
                }
                printStr("\n");
            }
        },
    }
}

fn writeFeatureMarkdown(f: langref.Feature) void {
    printStr("### `");
    printStr(f.name);
    printStr("` — ");
    printStr(f.status.label());
    printStr("\n\n```lir\n");
    printStr(f.syntax);
    printStr("\n```\n\n");
    printStr(f.notes);
    printStr("\n\n");
    if (f.prefer.len > 0) {
        printStr("**Prefer:** ");
        printStr(f.prefer);
        printStr("\n\n");
    }
    if (f.avoid.len > 0) {
        printStr("**Avoid:** ");
        printStr(f.avoid);
        printStr("\n\n");
    }
    if (f.example.len > 0) {
        printStr("```lir\n");
        printStr(f.example);
        printStr("\n```\n\n");
    }
}

fn renderLangMarkdown(filter: Filter) void {
    printStr("# LIR Language Reference (generated)\n\n");
    printStr("Generated by `lir lang --markdown`. Do not edit by hand: change\n");
    printStr("`src/bootstrap/langref.zig` and regenerate. Every `supported` example below\n");
    printStr("is compiled and executed by `zig build test`.\n\n");
    printStr("Status: **supported** = safe to generate, **partial** = read the notes,\n");
    printStr("**legacy** = accepted but prefer the canonical spelling, **unsupported** = rejected.\n\n");
    // Reserved words: published from the lexer so generators never guess.
    printStr("## Reserved words\n\n");
    printStr("Never emit these as identifiers, parameter names, field names or function\n");
    printStr("names. The list comes from the lexer (`lir lang --keywords --json`,\n");
    printStr("schema `lir.keywords.v1`) and includes words that are reserved but not\n");
    printStr("implemented (`async`, `await`, `unsafe`, `asm`, `extern`, `mod`, `i128`, …).\n\n");
    for (lex.keyword_entries, 0..) |entry, i| {
        printStr("`");
        printStr(entry.word);
        printStr("`");
        if (i + 1 != lex.keyword_entries.len) printStr(", ");
    }
    printStr("\n\n");
    for (category_order) |cat| {
        if (filter.category) |only| if (only != cat) continue;
        var header = false;
        for (langref.features) |f| {
            if (f.category != cat) continue;
            if (!filter.acceptsFeature(f)) continue;
            if (!header) {
                printStr("## ");
                printStr(categoryTitle(cat));
                printStr("\n\n");
                header = true;
            }
            writeFeatureMarkdown(f);
        }
    }
    printStr("## Builtins\n\n| Builtin | Signature | Behaviour |\n|---|---|---|\n");
    for (langref.builtins) |b| {
        printStr("| `");
        printStr(b.name);
        printStr("` | `");
        printStr(b.signature);
        printStr("` | ");
        printStr(b.summary);
        printStr(" |\n");
    }
}

// ════════════════════════════════════════════════════════════════════════════
// lir builtins
// ════════════════════════════════════════════════════════════════════════════

pub fn cmdBuiltins(args: []const []const u8) void {
    var filter = Filter{};
    var out_fmt: OutFormat = .human;
    var selector: ?[]const u8 = null;
    var wants_help = false;
    for (args) |arg| {
        if (eql(arg, "--help") or eql(arg, "-h")) wants_help = true;
    }
    if (wants_help) {
        printStr(
            \\Usage: lir builtins [name] [options]
            \\
            \\Lists the builtin functions and intrinsics of the bootstrap compiler with
            \\their signatures. Groups: int, math, io, process, memory, string, array,
            \\collection, concurrency, net, terminal, crypto, reflection, testing
            \\(14 groups, 131 builtins).
            \\
            \\Options:
            \\  --json              Machine-readable catalogue (schema lir.builtins.v1)
            \\  --markdown          Markdown table
            \\  --short             name signature (tab separated)
            \\  --group=<g>         Restrict to one group
            \\
            \\Examples:
            \\  lir builtins --group=string
            \\  lir builtins @array_push
            \\  lir builtins --json
            \\
        );
        return;
    }
    parseFilterWith(args, &filter, &out_fmt, &selector);

    if (selector) |name| {
        const b = langref.builtinByName(name) orelse {
            // Tolerate a missing '@' prefix and suggest the exact spelling.
            var cands: [langref.builtins.len][]const u8 = undefined;
            for (langref.builtins, 0..) |item, i| cands[i] = item.name;
            printErr("Error: unknown builtin '");
            printErr(name);
            printErr("'.");
            if (util.findSimilarName(name, &cands, 2)) |sugg| {
                printErr(" Did you mean '");
                printErr(sugg);
                printErr("'?");
            }
            printErr("\nRun 'lir builtins' to list all builtins.\n");
            util.sysExit(1);
        };
        switch (out_fmt) {
            .json => {
                printStr("{\"schema\":\"lir.builtins.v1\",\"builtin\":");
                writeBuiltinJson(b.*);
                printStr("}\n");
            },
            .markdown => {
                printStr("| Builtin | Signature | Behaviour |\n|---|---|---|\n");
                printStr("| `");
                printStr(b.name);
                printStr("` | `");
                printStr(b.signature);
                printStr("` | ");
                printStr(b.summary);
                printStr(" |\n");
            },
            .short, .human => {
                printStr(b.name);
                printStr("\n  signature: ");
                printStr(b.signature);
                printStr("\n  group:     ");
                printStr(b.group);
                printStr("\n  summary:   ");
                printStr(b.summary);
                printStr("\n");
            },
        }
        return;
    }

    switch (out_fmt) {
        .json => {
            printStr("{\"schema\":\"lir.builtins.v1\",\"builtins\":[");
            var first = true;
            for (langref.builtins) |b| {
                if (!filter.acceptsBuiltin(b)) continue;
                if (!first) printStr(",");
                first = false;
                writeBuiltinJson(b);
            }
            printStr("]}\n");
        },
        .markdown => {
            printStr("| Builtin | Signature | Behaviour |\n|---|---|---|\n");
            for (langref.builtins) |b| {
                if (!filter.acceptsBuiltin(b)) continue;
                printStr("| `");
                printStr(b.name);
                printStr("` | `");
                printStr(b.signature);
                printStr("` | ");
                printStr(b.summary);
                printStr(" |\n");
            }
        },
        .short => {
            for (langref.builtins) |b| {
                if (!filter.acceptsBuiltin(b)) continue;
                printStr(b.name);
                printStr("\t");
                printStr(b.signature);
                printStr("\n");
            }
        },
        .human => {
            var group: []const u8 = "";
            var count: usize = 0;
            for (langref.builtins) |b| {
                if (!filter.acceptsBuiltin(b)) continue;
                if (!eql(group, b.group)) {
                    group = b.group;
                    printStr("\n── ");
                    printStr(group);
                    printStr("\n");
                }
                printStr("  ");
                printStr(b.signature);
                const pad: usize = if (b.signature.len < 46) 46 - b.signature.len else 1;
                var i: usize = 0;
                while (i < pad) : (i += 1) printStr(" ");
                printStr(b.summary);
                printStr("\n");
                count += 1;
            }
            printStr("\n");
            printUsize(count);
            printStr(" builtins. Details: lir builtins <name>   JSON: lir builtins --json\n");
        },
    }
}

fn writeBuiltinJson(b: langref.Builtin) void {
    printStr("{\"name\":");
    jsonStr(b.name);
    printStr(",\"signature\":");
    jsonStr(b.signature);
    printStr(",\"group\":");
    jsonStr(b.group);
    printStr(",\"summary\":");
    jsonStr(b.summary);
    printStr("}");
}

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "language catalogue is internally consistent" {
    // Unique feature names
    var i: usize = 0;
    while (i < langref.features.len) : (i += 1) {
        var j = i + 1;
        while (j < langref.features.len) : (j += 1) {
            try std.testing.expect(!eql(langref.features[i].name, langref.features[j].name));
        }
    }
    // Every supported/partial feature that claims an example has a main or test.
    for (langref.features) |f| {
        if (f.status == .unsupported) {
            try std.testing.expect(f.example.len == 0);
            continue;
        }
        if (f.example.len == 0) continue;
        const has_main = std.mem.indexOf(u8, f.example, "fn main") != null;
        const has_test = std.mem.indexOf(u8, f.example, "#[test]") != null;
        try std.testing.expect(has_main or has_test);
    }
}

test "every categorical builtin is documented once" {
    var i: usize = 0;
    while (i < langref.builtins.len) : (i += 1) {
        var j = i + 1;
        while (j < langref.builtins.len) : (j += 1) {
            try std.testing.expect(!eql(langref.builtins[i].name, langref.builtins[j].name));
        }
    }
}
