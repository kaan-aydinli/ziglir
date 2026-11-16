// ════════════════════════════════════════════════════════════════════════════
// CMF — Causal Morphogenetic Field
//
// A second paradigm for LIR that is not object-oriented, not functional and
// not procedural: the program is a *morphogenetic field of claims*, and the
// compiler's job is to make those claims falsifiable before the program runs.
//
// Three motions, no classes, no inheritance, no message passing:
//
//   morph  <name>          shapes      — a named generative shape (parameterised
//                                         by a witness, so it is not a type)
//   field  <name>: M<T>    fields      — the shared substrate; mutation is an
//                                         event others observe, never a call
//   claim  <name>          commitments — an assertion that must be discharged
//                                         now, or bound to an adjudicator that
//                                         falsifies it later
//   bloom  <name>: morph   expression  — express one claim over another shape;
//                                         each concrete witness instance is
//                                         compiled and verified on its own
//
// The load-bearing difference from every object-oriented language: there is no
// "is-a" and no dispatch table. A morph that fails to verify *never becomes a
// variant* (fails closed), and a claim that no check and no adjudicator covers
// is an error, not a runtime surprise.
//
// This module is deliberately conservative and honest: `lir cmf` performs
// *static* checking only. It makes no latency, energy or hardware claim.
// ════════════════════════════════════════════════════════════════════════════

const std = @import("std");
const util = @import("util.zig");
const diag_mod = @import("diag.zig");
const parser_mod = @import("parser.zig");

const eql = util.eql;
const Lexer = @import("lexer.zig").Lexer;
const TokenKind = @import("lexer.zig").TokenKind;
const Token = @import("lexer.zig").Token;

// ── Tiny line-oriented reader ────────────────────────────────────────────────
//
// CMF headers are line-oriented on purpose: a field declaration is a *fact
// about a surface*, and facts that fit on one line can be diffed, reviewed and
// generated. Bodies are ordinary LIR and are handed to the real parser.

const Word = struct {
    text: []const u8,
    line: u32,
    col: u32,
};

fn isSpace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\r';
}

fn isIdentStart(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or ch == '_';
}

fn isIdentChar(ch: u8) bool {
    return isIdentStart(ch) or (ch >= '0' and ch <= '9');
}

/// Walks a single line producing identifiers, `::`, and punctuation tokens;
/// skips the trailing `//` comment and string literals become opaque words.
const LineScanner = struct {
    src: []const u8,
    pos: usize = 0,
    col: u32 = 1,

    fn skipSpace(self: *LineScanner) void {
        while (self.pos < self.src.len and isSpace(self.src[self.pos])) {
            self.pos += 1;
            self.col += 1;
        }
    }

    fn atEnd(self: *LineScanner) bool {
        self.skipSpace();
        if (self.pos >= self.src.len) return true;
        return self.src[self.pos] == '/' and self.pos + 1 < self.src.len and self.src[self.pos + 1] == '/';
    }

    fn next(self: *LineScanner) ?Word {
        self.skipSpace();
        if (self.atEnd()) return null;
        const start_col = self.col;
        const start = self.pos;
        const ch = self.src[self.pos];

        if (isIdentStart(ch)) {
            while (self.pos < self.src.len and isIdentChar(self.src[self.pos])) self.pos += 1;
            // `::` is part of a path word
            while (self.pos + 1 < self.src.len and self.src[self.pos] == ':' and self.src[self.pos + 1] == ':') {
                self.pos += 2;
                while (self.pos < self.src.len and isIdentChar(self.src[self.pos])) self.pos += 1;
            }
            const text = self.src[start..self.pos];
            self.col += @intCast(text.len);
            return .{ .text = text, .line = 0, .col = start_col };
        }

        if (ch >= '0' and ch <= '9') {
            while (self.pos < self.src.len and (isIdentChar(self.src[self.pos]))) self.pos += 1;
            const text = self.src[start..self.pos];
            self.col += @intCast(text.len);
            return .{ .text = text, .line = 0, .col = start_col };
        }

        // `=<<` / `>>=` / `=<>` / `<>=` are the instance delimiters
        if (ch == '=' and self.pos + 2 < self.src.len and self.src[self.pos + 1] == '<' and self.src[self.pos + 2] == '<') {
            self.pos += 3;
            self.col += 3;
            return .{ .text = "=<<", .line = 0, .col = start_col };
        }
        if (ch == '=' and self.pos + 2 < self.src.len and self.src[self.pos + 1] == '<' and self.src[self.pos + 2] == '>') {
            self.pos += 3;
            self.col += 3;
            return .{ .text = "=<>", .line = 0, .col = start_col };
        }
        if (ch == '>' and self.pos + 2 < self.src.len and self.src[self.pos + 1] == '>' and self.src[self.pos + 2] == '=') {
            self.pos += 3;
            self.col += 3;
            return .{ .text = ">>=", .line = 0, .col = start_col };
        }
        if (ch == '<' and self.pos + 2 < self.src.len and self.src[self.pos + 1] == '>' and self.src[self.pos + 2] == '=') {
            self.pos += 3;
            self.col += 3;
            return .{ .text = "<>=", .line = 0, .col = start_col };
        }
        // Single-character punctuation we care about, plus `->`, `<=`, `>=`
        if (ch == '-' and self.pos + 1 < self.src.len and self.src[self.pos + 1] == '>') {
            self.pos += 2;
            self.col += 2;
            return .{ .text = "->", .line = 0, .col = start_col };
        }
        self.pos += 1;
        self.col += 1;
        const one = self.src[start..self.pos];
        return .{ .text = one, .line = 0, .col = start_col };
    }
};

/// Splits `src` into logical lines, dropping blank lines and `//` comments.
const LogicalLine = struct {
    text: []const u8,
    line: u32,
};

const LineList = struct {
    items: [512]LogicalLine = undefined,
    count: usize = 0,

    fn push(self: *LineList, text: []const u8, line: u32) void {
        if (self.count >= self.items.len) return;
        self.items[self.count] = .{ .text = text, .line = line };
        self.count += 1;
    }

    fn slice(self: *const LineList) []const LogicalLine {
        return self.items[0..self.count];
    }
};

fn splitLines(src: []const u8, out: *LineList) void {
    var start: usize = 0;
    var line: u32 = 1;
    var i: usize = 0;
    while (i <= src.len) : (i += 1) {
        const at_eof = i == src.len;
        if (!at_eof and src[i] != '\n') continue;
        var text = src[start..i];
        // strip a trailing `//` comment that is not inside a string
        var in_string = false;
        var j: usize = 0;
        while (j + 1 < text.len) : (j += 1) {
            if (text[j] == '"') in_string = !in_string;
            if (!in_string and text[j] == '/' and text[j + 1] == '/') {
                text = text[0..j];
                break;
            }
        }
        const trimmed = std.mem.trim(u8, text, " \t\r");
        if (trimmed.len > 0) out.push(trimmed, line);
        start = i + 1;
        line += 1;
    }
}

// ── Model ───────────────────────────────────────────────────────────────────

pub const MorphKind = enum {
    /// Closed shape: the instance set is exactly the witness list.
    closed,
    /// Open shape: instances are generated from the bound domains, first_match wins.
    open,
};

pub const Morph = struct {
    name: []const u8,
    kind: MorphKind,
    witnesses: [64][]const u8 = undefined,
    witness_count: usize = 0,
    line: u32,
};

pub const FieldKind = enum {
    /// A region with a fixed byte length: uniqueness is checkable.
    exclusive,
    /// A shared region: concurrency is checkable, uniqueness is not required.
    shared,
};

pub const Field = struct {
    name: []const u8,
    cell: []const u8,
    len: u64,
    kind: FieldKind,
    line: u32,
};

pub const ClaimKind = enum {
    /// Discharged by a static check (`check` names it).
    linear,
    /// Discharged at runtime by an adjudicator (`runtime` names it).
    runtime,
    /// Purely structural: no uniqueness/concurrency obligation, so no judgment.
    structural,
};

pub const Claim = struct {
    name: []const u8,
    over: ?[]const u8,
    duration: i64,
    /// null until the claim says how it is judged; checkField rejects null.
    kind: ?ClaimKind,
    basis: ?[]const u8,
    line: u32,
};

pub const Bloom = struct {
    name: []const u8,
    morph: []const u8,
    line: u32,
};

pub const Violation = struct {
    code: diag_mod.Code,
    line: u32,
    col: u32,
    msg: [diag_mod.MAX_MSG]u8 = undefined,
    msg_len: usize = 0,
    help: [diag_mod.MAX_HELP]u8 = undefined,
    help_len: usize = 0,

    pub fn text(self: *const Violation) []const u8 {
        return self.msg[0..self.msg_len];
    }

    pub fn helpText(self: *const Violation) []const u8 {
        return self.help[0..self.help_len];
    }
};

/// Outcome of compiling one concrete instance of a bloom.
pub const Variant = struct {
    bloom: []const u8,
    morph: []const u8,
    witness: []const u8,
    verified: bool = false,
    /// True when the placeholder never appeared in the body, so the variant is
    /// vacuous: it compiled, but it proves nothing about the witness.
    vacuous: bool = false,
};

pub const FieldIR = struct {
    morphs: [64]Morph = undefined,
    morph_count: usize = 0,
    fields: [64]Field = undefined,
    field_count: usize = 0,
    claims: [64]Claim = undefined,
    claim_count: usize = 0,
    blooms: [64]Bloom = undefined,
    bloom_count: usize = 0,
    violations: [64]Violation = undefined,
    violation_count: usize = 0,
    /// Highest morph instantiation count, which bounds how many concrete
    /// variants a `bloom` can produce. Reported, never assumed.
    max_variants: usize = 0,
    variants: [128]Variant = undefined,
    variant_count: usize = 0,
    bodies: [32]Body = undefined,
    body_count: usize = 0,

    pub fn morphNamed(self: *const FieldIR, name: []const u8) ?*const Morph {
        for (self.morphs[0..self.morph_count]) |*m| {
            if (eql(m.name, name)) return m;
        }
        return null;
    }

    pub fn fieldNamed(self: *const FieldIR, name: []const u8) ?*const Field {
        for (self.fields[0..self.field_count]) |*f| {
            if (eql(f.name, name)) return f;
        }
        return null;
    }

    pub fn claimNamed(self: *const FieldIR, name: []const u8) ?*const Claim {
        for (self.claims[0..self.claim_count]) |*c| {
            if (eql(c.name, name)) return c;
        }
        return null;
    }

    fn fail(self: *FieldIR, code: diag_mod.Code, line: u32, col: u32, comptime fmt: []const u8, args: anytype) usize {
        if (self.violation_count >= self.violations.len) return 0;
        var v = Violation{ .code = code, .line = line, .col = col };
        const text = std.fmt.bufPrint(&v.msg, fmt, args) catch v.msg[0..];
        v.msg_len = text.len;
        self.violations[self.violation_count] = v;
        self.violation_count += 1;
        return self.violation_count - 1;
    }

    pub fn failHelp(self: *FieldIR, index: usize, comptime fmt: []const u8, args: anytype) void {
        if (index >= self.violation_count) return;
        const text = std.fmt.bufPrint(&self.violations[index].help, fmt, args) catch self.violations[index].help[0..];
        self.violations[index].help_len = text.len;
    }

    pub fn ok(self: *const FieldIR) bool {
        return self.violation_count == 0;
    }
};

// ── Parser + checker ────────────────────────────────────────────────────────

/// Parse a whole CMF file: headers, attached bodies, cross-references, and the
/// construction of every bloom variant. Violations accumulate in the result.
pub fn parseField(source: []const u8) FieldIR {
    var ir = FieldIR{};
    var lines = LineList{};
    extractBodies(source, &ir, &lines);
    parseLines(&ir, lines.slice());
    checkField(&ir);
    _ = buildVariants(&ir, ir.bodies[0..ir.body_count]);
    return ir;
}

/// Splits `source` into header lines and braced bodies. A `bloom <name> ... {`
/// header opens a body that ends at the `}` which brings the brace depth back to
/// zero, so nested blocks, strings and comments are preserved verbatim.
fn extractBodies(source: []const u8, ir: *FieldIR, lines: *LineList) void {
    const alloc = std.heap.page_allocator;
    var open_name: ?[]const u8 = null;
    var depth: i32 = 0;
    var body_buf = std.ArrayListUnmanaged(u8){};
    var line_no: u32 = 1;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= source.len) : (i += 1) {
        if (i != source.len and source[i] != '\n') continue;
        const raw = source[start..i];
        start = i + 1;
        const this_line = line_no;
        line_no += 1;

        const trimmed = std.mem.trim(u8, raw, " \t\r");

        if (open_name) |name| {
            // depth counts the body's unmatched braces; the closing `}` of the
            // bloom itself arrives at depth 0 and is not part of the body.
            if (depth == 0 and std.mem.eql(u8, trimmed, "}")) {
                if (ir.body_count < ir.bodies.len) {
                    const text = alloc.dupe(u8, body_buf.items) catch "";
                    ir.bodies[ir.body_count] = .{ .bloom = name, .source = text };
                    ir.body_count += 1;
                }
                body_buf.clearRetainingCapacity();
                open_name = null;
                continue;
            }
            body_buf.appendSlice(alloc, raw) catch {};
            body_buf.append(alloc, '\n') catch {};
            depth += braceDelta(raw);
            if (depth < 0) depth = 0;
            continue;
        }

        // A bloom header that opens a body: `bloom <name> ... {`
        if (trimmed.len > 0 and std.mem.endsWith(u8, trimmed, "{")) {
            var sc = LineScanner{ .src = trimmed };
            if (sc.next()) |head| {
                if (eql(head.text, "bloom")) {
                    if (sc.next()) |name_tok| {
                        open_name = alloc.dupe(u8, name_tok.text) catch null;
                        depth = braceDeltaAfterHeader(trimmed);
                        if (depth < 0) depth = 0;
                        body_buf.clearRetainingCapacity();
                        lines.push(trimmed, this_line);
                        continue;
                    }
                }
            }
        }
        if (trimmed.len > 0) lines.push(trimmed, this_line);
    }
    if (open_name) |name| {
        if (ir.body_count < ir.bodies.len) {
            const text = alloc.dupe(u8, body_buf.items) catch "";
            ir.bodies[ir.body_count] = .{ .bloom = name, .source = text };
            ir.body_count += 1;
        }
        _ = ir.fail(.cmf_syntax, line_no - 1, 1, "bloom '{s}' body is never closed with '}}'", .{name});
    }
}

/// Net brace balance of a line, ignoring string literals and `//` comments.
fn braceDelta(text: []const u8) i32 {
    var delta: i32 = 0;
    var in_string = false;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const ch = text[i];
        if (in_string) {
            if (ch == '\\') {
                i += 1;
            } else if (ch == '"') {
                in_string = false;
            }
            continue;
        }
        if (ch == '"') {
            in_string = true;
        } else if (ch == '/' and i + 1 < text.len and text[i + 1] == '/') {
            break;
        } else if (ch == '{') {
            delta += 1;
        } else if (ch == '}') {
            delta -= 1;
        }
    }
    return delta;
}

/// The header line's own `{` opens the body, so it is not counted as body depth.
fn braceDeltaAfterHeader(header: []const u8) i32 {
    return braceDelta(header) - 1;
}

fn parseLines(ir: *FieldIR, lines: []const LogicalLine) void {
    for (lines) |line| {
        var sc = LineScanner{ .src = line.text };
        const head = sc.next() orelse continue;
        // `#` and `//` both start a comment, matching the LIR lexer's rule that
        // `#` not followed by `[` or `{` runs to end of line.
        if (head.text[0] == '#') continue;
        if (eql(head.text, "morph")) {
            parseMorph(ir, line, &sc, head);
        } else if (eql(head.text, "field")) {
            parseFieldDecl(ir, line, &sc, head);
        } else if (eql(head.text, "claim")) {
            parseClaim(ir, line, &sc, head);
        } else if (eql(head.text, "bloom")) {
            parseBloom(ir, line, &sc, head);
        } else if (eql(head.text, "fn") or eql(head.text, "struct") or eql(head.text, "enum")) {
            // Ordinary LIR declaration inside a CMF file: checked by the real
            // front end (`lir check`), ignored by the field checker.
            continue;
        } else {
            _ = ir.fail(.cmf_syntax, line.line, head.col, "unknown field directive '{s}' (expected morph, field, claim, bloom, fn, struct or enum)", .{head.text});
        }
    }
}

fn parseMorph(ir: *FieldIR, line: LogicalLine, sc: *LineScanner, head: Word) void {
    _ = head;
    const name = sc.next() orelse {
        _ = ir.fail(.cmf_syntax, line.line, 1, "morph needs a name", .{});
        return;
    };
    var kind: ?MorphKind = null;
    var witnesses: [64][]const u8 = undefined;
    var wcount: usize = 0;
    while (sc.next()) |w| {
        if (eql(w.text, "=<<")) {
            kind = .closed;
        } else if (eql(w.text, ">>=")) {
        } else if (eql(w.text, "=<>")) {
            kind = .open;
        } else if (eql(w.text, "<>=")) {
        } else if (eql(w.text, "witnesses")) {
        } else if (isIdentStart(w.text[0])) {
            if (wcount < witnesses.len) {
                witnesses[wcount] = w.text;
                wcount += 1;
            }
        } else {
            _ = ir.fail(.cmf_syntax, line.line, w.col, "unexpected '{s}' in morph '{s}'", .{ w.text, name.text });
            return;
        }
    }
    if (kind == null) {
        _ = ir.fail(.cmf_syntax, line.line, name.col, "morph '{s}' declares no instance form (use =<< a b c >>= or =<> u8 u16 u32 <>=)", .{name.text});
        return;
    }
    if (kind.? == .closed and wcount == 0) {
        _ = ir.fail(.cmf_morph_empty, line.line, name.col, "closed morph '{s}' has no witnesses, so it can never be instantiated", .{name.text});
        return;
    }
    if (ir.morphNamed(name.text) != null) {
        _ = ir.fail(.cmf_duplicate, line.line, name.col, "morph '{s}' is already declared", .{name.text});
        return;
    }
    if (ir.morph_count >= ir.morphs.len) return;
    var m = Morph{ .name = name.text, .kind = kind.?, .line = line.line };
    var i: usize = 0;
    while (i < wcount) : (i += 1) m.witnesses[i] = witnesses[i];
    m.witness_count = wcount;
    ir.morphs[ir.morph_count] = m;
    ir.morph_count += 1;
}

fn parseFieldDecl(ir: *FieldIR, line: LogicalLine, sc: *LineScanner, head: Word) void {
    _ = head;
    const name = sc.next() orelse {
        _ = ir.fail(.cmf_syntax, line.line, 1, "field needs a name", .{});
        return;
    };
    // name : cell [len] ?exclusive|?shared
    var cell: ?[]const u8 = null;
    var len: u64 = 1;
    var kind: ?FieldKind = null;
    while (sc.next()) |w| {
        if (eql(w.text, ":")) continue;
        if (eql(w.text, "?")) {
            const tag = sc.next() orelse continue;
            if (eql(tag.text, "exclusive")) {
                kind = .exclusive;
            } else if (eql(tag.text, "shared")) {
                kind = .shared;
            } else {
                _ = ir.fail(.cmf_syntax, line.line, tag.col, "unknown field refinement '?{s}' (expected ?shared or ?exclusive)", .{tag.text});
            }
            continue;
        }
        if (eql(w.text, "[")) {
            const num = sc.next() orelse {
                _ = ir.fail(.cmf_syntax, line.line, w.col, "field length needs a positive integer", .{});
                return;
            };
            len = std.fmt.parseInt(u64, num.text, 10) catch {
                _ = ir.fail(.cmf_syntax, line.line, num.col, "field length '{s}' is not an integer", .{num.text});
                return;
            };
            _ = sc.next(); // ']'
            continue;
        }
        if (isIdentStart(w.text[0]) and cell == null) {
            cell = w.text;
            continue;
        }
        _ = ir.fail(.cmf_syntax, line.line, w.col, "unexpected '{s}' in field declaration", .{w.text});
        return;
    }
    const cell_type = cell orelse {
        _ = ir.fail(.cmf_syntax, line.line, name.col, "field '{s}' has no cell type (write: field {s}: i64[8] ?shared)", .{ name.text, name.text });
        return;
    };
    if (len == 0) {
        _ = ir.fail(.cmf_field_empty, line.line, name.col, "field '{s}' has length 0, so it reserves nothing", .{name.text});
        return;
    }
    if (ir.fieldNamed(name.text) != null) {
        _ = ir.fail(.cmf_duplicate, line.line, name.col, "field '{s}' is already declared", .{name.text});
        return;
    }
    if (ir.field_count >= ir.fields.len) return;
    ir.fields[ir.field_count] = .{
        .name = name.text,
        .cell = cell_type,
        .len = len,
        .kind = kind orelse .exclusive,
        .line = line.line,
    };
    ir.field_count += 1;
}

fn parseClaim(ir: *FieldIR, line: LogicalLine, sc: *LineScanner, head: Word) void {
    _ = head;
    const name = sc.next() orelse {
        _ = ir.fail(.cmf_syntax, line.line, 1, "claim needs a name", .{});
        return;
    };
    var over: ?[]const u8 = null;
    var duration: i64 = 0;
    var kind: ?ClaimKind = null;
    var basis: ?[]const u8 = null;
    var expecting_basis = false;
    var expecting_field = false;
    while (sc.next()) |w| {
        if (expecting_basis) {
            basis = w.text;
            expecting_basis = false;
            continue;
        }
        if (expecting_field) {
            over = w.text;
            expecting_field = false;
            continue;
        }
        if (eql(w.text, "over") or eql(w.text, ":")) {
            if (eql(w.text, "over")) expecting_field = true;
        } else if (eql(w.text, "for")) {
            const dur = sc.next() orelse {
                _ = ir.fail(.cmf_claim_conflict, line.line, name.col, "claim '{s}' says 'for' but no duration follows", .{name.text});
                return;
            };
            duration = parseDuration(dur.text) catch {
                _ = ir.fail(.cmf_claim_conflict, line.line, dur.col, "claim '{s}' has duration '{s}' that is not of the form <n>cycle|tick|span", .{ name.text, dur.text });
                return;
            };
        } else if (eql(w.text, "check")) {
            kind = .linear;
            expecting_basis = true;
        } else if (eql(w.text, "runtime")) {
            kind = .runtime;
            expecting_basis = true;
        } else if (eql(w.text, "structural")) {
            kind = .structural;
        } else if (eql(w.text, "{")) {
            break;
        }
    }
    if (ir.claimNamed(name.text) != null) {
        _ = ir.fail(.cmf_duplicate, line.line, name.col, "claim '{s}' is already declared", .{name.text});
        return;
    }
    if (ir.claim_count >= ir.claims.len) return;
    ir.claims[ir.claim_count] = .{
        .name = name.text,
        .over = over,
        .duration = duration,
        .kind = kind,
        .basis = basis,
        .line = line.line,
    };
    ir.claim_count += 1;
}

fn parseDuration(text: []const u8) !i64 {
    const specs = [_][]const u8{ "cycle", "tick", "span" };
    for (specs) |suffix| {
        if (text.len > suffix.len and std.mem.endsWith(u8, text, suffix)) {
            return try std.fmt.parseInt(i64, text[0 .. text.len - suffix.len], 10);
        }
    }
    return error.NotADuration;
}

fn parseBloom(ir: *FieldIR, line: LogicalLine, sc: *LineScanner, head: Word) void {
    _ = head;
    const name = sc.next() orelse {
        _ = ir.fail(.cmf_syntax, line.line, 1, "bloom needs a name", .{});
        return;
    };
    // bloom <name> : morph <target>
    _ = sc.next(); // ':'
    const kw = sc.next() orelse {
        _ = ir.fail(.cmf_syntax, line.line, name.col, "bloom '{s}' needs a form (bloom {s}: morph <name>)", .{ name.text, name.text });
        return;
    };
    if (!eql(kw.text, "morph")) {
        _ = ir.fail(.cmf_syntax, line.line, kw.col, "bloom form must be 'morph', found '{s}'", .{kw.text});
        return;
    }
    const target = sc.next() orelse {
        _ = ir.fail(.cmf_syntax, line.line, name.col, "bloom '{s}' names no morph", .{name.text});
        return;
    };
    if (!isIdentStart(target.text[0])) {
        _ = ir.fail(.cmf_syntax, line.line, target.col, "bloom '{s}' needs a morph name, found '{s}'", .{ name.text, target.text });
        return;
    }
    if (ir.bloom_count >= ir.blooms.len) return;
    ir.blooms[ir.bloom_count] = .{ .name = name.text, .morph = target.text, .line = line.line };
    ir.bloom_count += 1;
}

/// Semantic pass: every cross-reference must resolve, every claim must be
/// dischargeable, and every field-to-claim overlap must be honest.
pub fn checkField(ir: *FieldIR) void {
    // 1. blooms must name a declared morph, and reachable variants are counted.
    for (ir.blooms[0..ir.bloom_count]) |*b| {
        if (ir.morphNamed(b.morph) == null) {
            _ = ir.fail(.cmf_bloom_unsupported, b.line, 1, "bloom '{s}' expands morph '{s}', which is not declared", .{ b.name, b.morph });
        }
    }

    // 2. morph instance counts: a bloom over a morph yields one variant per
    //    witness, so the variant surface is exactly countable.
    var total: usize = 0;
    for (ir.morphs[0..ir.morph_count]) |*m| {
        total += @max(m.witness_count, 1);
    }
    ir.max_variants = total;

    // 3. claims over an undeclared field, or with a non-existent adjudicator.
    for (ir.claims[0..ir.claim_count]) |*c| {
        if (c.over) |field_name| {
            if (ir.fieldNamed(field_name) == null) {
                const vi = ir.fail(.cmf_claim_unsupported, c.line, 1, "claim '{s}' is made over '{s}', which is not a declared field", .{ c.name, field_name });
                ir.failHelp(vi, "declare it first: field {s}: i64[64]", .{field_name});
            }
        }
        if (c.kind) |kind| switch (kind) {
            .linear => {
                const basis = c.basis orelse "";
                const known = [_][]const u8{ "uniqueness", "concurrency", "totality", "absence" };
                var found = false;
                for (known) |k| {
                    if (eql(basis, k)) found = true;
                }
                if (!found) {
                    _ = ir.fail(.cmf_claim_unsupported, c.line, 1, "claim '{s}' names check '{s}', which no checker implements (uniqueness, concurrency, totality, absence)", .{ c.name, basis });
                }
                if (c.over == null) {
                    _ = ir.fail(.cmf_claim_unsupported, c.line, 1, "claim '{s}' uses check '{s}' but names no field to check", .{ c.name, basis });
                }
            },
            .runtime => {
                if (c.basis == null) {
                    _ = ir.fail(.cmf_claim_unsupported, c.line, 1, "claim '{s}' is discharged at runtime but names no adjudicator", .{c.name});
                }
                if (c.duration <= 0) {
                    _ = ir.fail(.cmf_claim_conflict, c.line, 1, "claim '{s}' has an adjudicator but no bounded duration (add: for <n>tick)", .{c.name});
                }
            },
            .structural => {
                if (c.duration != 0) {
                    _ = ir.fail(.cmf_claim_unsupported, c.line, 1, "claim '{s}' carries a duration but names no adjudicator (add: runtime <name>)", .{c.name});
                }
            },
        };
        if (c.over) |field_name| {
            if (ir.fieldNamed(field_name)) |f| {
                const wants_unique = c.kind != null and c.kind.? == .linear and eql(c.basis orelse "", "uniqueness");
                if (!eql(f.cell, "u64") and wants_unique) {
                    _ = ir.fail(.cmf_claim_conflict, c.line, 1, "claim '{s}' asks for uniqueness over '{s}', whose cell type is '{s}' rather than u64", .{ c.name, field_name, f.cell });
                }
            }
        }
        // A claim that is neither checked, adjudicated nor structural has no
        // meaning at all: fail closed rather than silently passing.
        if (c.kind == null) {
            if (c.duration != 0) {
                _ = ir.fail(.cmf_claim_unsupported, c.line, 1, "claim '{s}' carries a duration but names no adjudicator (runtime <name>)", .{c.name});
            } else {
                _ = ir.fail(.cmf_claim_unsupported, c.line, 1, "claim '{s}' states no judgment: nothing would ever falsify it", .{c.name});
            }
        } else if (c.kind != .structural and c.basis == null) {
            _ = ir.fail(.cmf_claim_unsupported, c.line, 1, "claim '{s}' is asserted but names no checker or adjudicator", .{c.name});
        }
    }
}

// ── Construction: bloom one witness into a real, verified variant ───────────
//
// This is the part that makes the paradigm more than a notation. A bloom names
// a morph; the morph's witnesses are *substituted into a real program body*;
// each resulting program is handed to the ordinary LIR front end (parser +
// semantic analysis + IR verification). Only witnesses whose expansion verifies
// become variants; the rest are never emitted, so an unverifiable instance can
// never be selected at runtime because it does not exist.
//
// The witness placeholder is the identifier `@witness` (an at-name, so it can
// never collide with a user binding).

pub const placeholder = "@witness";

/// `src` is the body attached to a bloom: `bloom <name> -> <...>` followed by
/// ordinary LIR that may mention `@witness`.
pub const BuildStats = struct {
    attempted: usize = 0,
    verified: usize = 0,
    rejected: usize = 0,
    vacuous: usize = 0,
};

pub fn buildVariants(ir: *FieldIR, bodies: []const Body) BuildStats {
    var stats = BuildStats{};
    for (ir.blooms[0..ir.bloom_count]) |*b| {
        const morph = ir.morphNamed(b.morph) orelse continue;
        const body = findBody(bodies, b.name) orelse {
            _ = ir.fail(.cmf_bloom_unsupported, b.line, 1, "bloom '{s}' has no body to expand ('bloom {s} -> {{ ... }}')", .{ b.name, b.name });
            continue;
        };
        if (morph.witness_count == 0) {
            _ = ir.fail(.cmf_bloom_unsupported, b.line, 1, "bloom '{s}' expands morph '{s}', which has no witnesses", .{ b.name, b.morph });
            continue;
        }
        for (morph.witnesses[0..morph.witness_count]) |witness| {
            if (ir.variant_count >= ir.variants.len) break;
            stats.attempted += 1;
            var v = Variant{ .bloom = b.name, .morph = b.morph, .witness = witness };
            var buf: [64 * 1024]u8 = undefined;
            const expanded = substitute(&buf, body.source, witness) orelse {
                _ = ir.fail(.cmf_variant_invalid, b.line, 1, "bloom '{s}' body is larger than the expansion buffer", .{b.name});
                stats.rejected += 1;
                continue;
            };
            v.vacuous = !containsPlaceholder(body.source);
            const verdict = verifyProgram(expanded);
            v.verified = verdict == .ok;
            if (!v.verified) {
                stats.rejected += 1;
                _ = ir.fail(.cmf_variant_invalid, b.line, 1, "bloom '{s}' witness '{s}' does not verify: {s}", .{ b.name, witness, verdictMessage(verdict) });
            } else {
                stats.verified += 1;
                if (v.vacuous) stats.vacuous += 1;
            }
            ir.variants[ir.variant_count] = v;
            ir.variant_count += 1;
        }
    }
    return stats;
}

const Verdict = enum { ok, parse_failed, sema_failed, ir_failed };

fn verdictMessage(v: Verdict) []const u8 {
    return switch (v) {
        .ok => "accepted",
        .parse_failed => "the expansion is not valid LIR syntax",
        .sema_failed => "the expansion fails type checking",
        .ir_failed => "the expansion fails IR verification",
    };
}

fn verifyProgram(text: []const u8) Verdict {
    const lexer_mod = @import("lexer.zig");
    _ = lexer_mod;
    const alloc = std.heap.page_allocator;
    const ir_module = alloc.create(@import("ir.zig").IRModule) catch return .ir_failed;
    defer alloc.destroy(ir_module);
    ir_module.init();
    var compiler = @import("driver.zig").Compiler.init(text, "<cmf-variant>");
    compiler.quiet = true;
    compiler.compileToIR(ir_module) catch |err| {
        return switch (err) {
            error.InvalidToken, error.InvalidSyntax, error.InvalidIntegerLiteral, error.UnsupportedFloatLiteral => .parse_failed,
            error.TooManyTokens, error.TooManyASTNodes, error.TooManySources, error.ImportNotFound => .parse_failed,
            error.UndefinedFunctionCall, error.DuplicateDeclaration, error.UndefinedVariable,
            error.UndefinedStruct, error.UnknownField, error.InvalidArgumentCount,
            error.TooManyArguments, error.LoopControlOutsideLoop, error.InvalidAddressOf,
            error.InvalidAssignmentTarget, error.TypeMismatch, error.TooManySymbols => .sema_failed,
            else => .ir_failed,
        };
    };
    return .ok;
}

fn containsPlaceholder(text: []const u8) bool {
    return std.mem.indexOf(u8, text, placeholder) != null;
}

/// Replace every `@witness` with `witness`. Returns null when it does not fit.
fn substitute(buf: []u8, text: []const u8, witness: []const u8) ?[]u8 {
    var out: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        if (i + placeholder.len <= text.len and std.mem.eql(u8, text[i .. i + placeholder.len], placeholder)) {
            if (out + witness.len > buf.len) return null;
            @memcpy(buf[out .. out + witness.len], witness);
            out += witness.len;
            i += placeholder.len;
        } else {
            if (out >= buf.len) return null;
            buf[out] = text[i];
            out += 1;
            i += 1;
        }
    }
    return buf[0..out];
}

pub const Body = struct {
    bloom: []const u8,
    source: []const u8,
};

fn findBody(bodies: []const Body, bloom_name: []const u8) ?Body {
    for (bodies) |b| {
        if (eql(b.bloom, bloom_name)) return b;
    }
    return null;
}

// ── Rendering ───────────────────────────────────────────────────────────────

fn jsonEscape(text: []const u8) void {
    util.printStr("\"");
    for (text) |ch| {
        switch (ch) {
            '"' => util.printStr("\\\""),
            '\\' => util.printStr("\\\\"),
            '\n' => util.printStr("\\n"),
            else => util.printStr(&[_]u8{ch}),
        }
    }
    util.printStr("\"");
}

pub fn renderHuman(ir: *const FieldIR, path: []const u8) void {
    util.printStr("CMF field: ");
    util.printStr(path);
    util.printStr("\n");
    var buf: [128]u8 = undefined;

    if (ir.morph_count > 0) {
        util.printStr("\n  morphs (shapes)\n");
        for (ir.morphs[0..ir.morph_count]) |*m| {
            util.printStr("    ");
            util.printStr(m.name);
            util.printStr(if (m.kind == .closed) "  =<< closed, " else "  =<> open, ");
            util.printStr(std.fmt.bufPrint(&buf, "{d} witness", .{m.witness_count}) catch "");
            if (m.witness_count != 1) util.printStr("es");
            if (m.witness_count > 0 and m.kind == .closed) {
                util.printStr(": ");
                for (m.witnesses[0..m.witness_count], 0..) |w, i| {
                    if (i > 0) util.printStr(", ");
                    util.printStr(w);
                }
            }
            util.printStr("\n");
        }
    }

    if (ir.field_count > 0) {
        util.printStr("\n  fields (substrate)\n");
        for (ir.fields[0..ir.field_count]) |*f| {
            util.printStr("    ");
            util.printStr(f.name);
            util.printStr(": ");
            util.printStr(f.cell);
            util.printStr("[");
            util.printStr(std.fmt.bufPrint(&buf, "{d}", .{f.len}) catch "");
            util.printStr("] ");
            util.printStr(if (f.kind == .exclusive) "?exclusive" else "?shared");
            util.printStr("\n");
        }
    }

    if (ir.claim_count > 0) {
        util.printStr("\n  claims (commitments)\n");
        for (ir.claims[0..ir.claim_count]) |*c| {
            util.printStr("    ");
            util.printStr(c.name);
            if (c.over) |o| {
                util.printStr(" over ");
                util.printStr(o);
            }
            util.printStr("  ");
            util.printStr(if (c.kind) |k| switch (k) {
                .linear => "checked",
                .runtime => "adjudicated",
                .structural => "structural",
            } else "unjudged");
            if (c.basis) |b| {
                util.printStr(" by ");
                util.printStr(b);
                util.printStr("()");
            }
            if (c.duration != 0) {
                util.printStr(" within ");
                util.printStr(std.fmt.bufPrint(&buf, "{d}", .{c.duration}) catch "");
                util.printStr(" units");
            }
            util.printStr("\n");
        }
    }

    if (ir.bloom_count > 0) {
        util.printStr("\n  blooms (expression)\n");
        for (ir.blooms[0..ir.bloom_count]) |*b| {
            util.printStr("    ");
            util.printStr(b.name);
            util.printStr(" -> morph ");
            util.printStr(b.morph);
            util.printStr("\n");
        }
    }

    if (ir.variant_count > 0) {
        util.printStr("\n  variants (constructed, not declared)\n");
        for (ir.variants[0..ir.variant_count]) |*v| {
            util.printStr("    ");
            util.printStr(v.bloom);
            util.printStr("/");
            util.printStr(v.witness);
            util.printStr("  ");
            if (!v.verified) {
                util.printStr("rejected (never emitted)");
            } else if (v.vacuous) {
                util.printStr("verified, but the body never uses @witness (vacuous)");
            } else {
                util.printStr("verified: the expansion type-checks and passes IR verification");
            }
            util.printStr("\n");
        }
    }

    util.printStr("\n  variant surface: ");
    util.printStr(std.fmt.bufPrint(&buf, "{d} witness instance", .{ir.max_variants}) catch "");
    if (ir.max_variants != 1) util.printStr("s");
    util.printStr(" advertised, ");
    var verified: usize = 0;
    var rejected: usize = 0;
    for (ir.variants[0..ir.variant_count]) |*v| {
        if (v.verified) verified += 1 else rejected += 1;
    }
    util.printStr(std.fmt.bufPrint(&buf, "{d} constructed and verified", .{verified}) catch "");
    if (rejected > 0) {
        util.printStr(", ");
        util.printStr(std.fmt.bufPrint(&buf, "{d} refused", .{rejected}) catch "");
    }
    util.printStr("\n");

    if (ir.ok()) {
        util.printStr("\n  every claim is covered by a check or an adjudicator: accepted\n");
    } else {
        util.printStr("\n");
        util.printStr(std.fmt.bufPrint(&buf, "  {d} violation", .{ir.violation_count}) catch "");
        if (ir.violation_count != 1) util.printStr("s");
        util.printStr(": rejected\n");
    }
}

pub const CmfFormat = enum { human, json };

pub fn renderJson(ir: *const FieldIR, path: []const u8) void {
    util.printStr("{\"schema\":\"lir.cmf.v1\",\"path\":");
    jsonEscape(path);
    util.printStr(",\"status\":");
    jsonEscape(if (ir.ok()) "ok" else "rejected");
    util.printStr(",\"variant_surface\":");
    var buf: [64]u8 = undefined;
    util.printStr(std.fmt.bufPrint(&buf, "{d}", .{ir.max_variants}) catch "0");

    util.printStr(",\"morphs\":[");
    for (ir.morphs[0..ir.morph_count], 0..) |*m, i| {
        if (i > 0) util.printStr(",");
        util.printStr("{\"name\":");
        jsonEscape(m.name);
        util.printStr(",\"form\":");
        jsonEscape(if (m.kind == .closed) "closed" else "open");
        util.printStr(",\"witnesses\":[");
        for (m.witnesses[0..m.witness_count], 0..) |w, j| {
            if (j > 0) util.printStr(",");
            jsonEscape(w);
        }
        util.printStr("]}");
    }
    util.printStr("],\"fields\":[");
    for (ir.fields[0..ir.field_count], 0..) |*f, i| {
        if (i > 0) util.printStr(",");
        util.printStr("{\"name\":");
        jsonEscape(f.name);
        util.printStr(",\"cell\":");
        jsonEscape(f.cell);
        util.printStr(",\"len\":");
        util.printStr(std.fmt.bufPrint(&buf, "{d}", .{f.len}) catch "0");
        util.printStr(",\"access\":");
        jsonEscape(if (f.kind == .exclusive) "exclusive" else "shared");
        util.printStr("}");
    }
    util.printStr("],\"claims\":[");
    for (ir.claims[0..ir.claim_count], 0..) |*c, i| {
        if (i > 0) util.printStr(",");
        util.printStr("{\"name\":");
        jsonEscape(c.name);
        util.printStr(",\"over\":");
        if (c.over) |o| jsonEscape(o) else util.printStr("null");
        util.printStr(",\"judgment\":");
        jsonEscape(if (c.kind) |k| switch (k) {
            .linear => "checked",
            .runtime => "adjudicated",
            .structural => "structural",
        } else "unjudged");
        util.printStr(",\"basis\":");
        if (c.basis) |b| jsonEscape(b) else util.printStr("null");
        util.printStr(",\"duration\":");
        util.printStr(std.fmt.bufPrint(&buf, "{d}", .{c.duration}) catch "0");
        util.printStr("}");
    }
    util.printStr("],\"blooms\":[");
    for (ir.blooms[0..ir.bloom_count], 0..) |*b, i| {
        if (i > 0) util.printStr(",");
        util.printStr("{\"name\":");
        jsonEscape(b.name);
        util.printStr(",\"morph\":");
        jsonEscape(b.morph);
        util.printStr("}");
    }
    util.printStr("],\"variants\":[");
    for (ir.variants[0..ir.variant_count], 0..) |*v, i| {
        if (i > 0) util.printStr(",");
        util.printStr("{\"bloom\":");
        jsonEscape(v.bloom);
        util.printStr(",\"morph\":");
        jsonEscape(v.morph);
        util.printStr(",\"witness\":");
        jsonEscape(v.witness);
        util.printStr(",\"status\":");
        jsonEscape(if (!v.verified) "rejected" else if (v.vacuous) "vacuous" else "verified");
        util.printStr("}");
    }
    util.printStr("],\"violations\":[");
    for (ir.violations[0..ir.violation_count], 0..) |*v, i| {
        if (i > 0) util.printStr(",");
        var code_buf: [16]u8 = undefined;
        util.printStr("{\"code\":");
        const d = diag_mod.Diagnostic{
            .severity = .err,
            .code = v.code.number(),
            .line = v.line,
            .col = v.col,
            .span_len = 1,
            .msg = undefined,
            .msg_len = 0,
        };
        jsonEscape(d.codeText(&code_buf));
        util.printStr(",\"line\":");
        util.printStr(std.fmt.bufPrint(&buf, "{d}", .{v.line}) catch "0");
        util.printStr(",\"message\":");
        jsonEscape(v.text());
        util.printStr("}");
    }
    util.printStr("]}\n");
}

/// Re-emit a CMF file into the diagnostics pipeline so editors and agents see
/// exactly the same envelope as any other compiler error.
pub fn emitViolations(ir: *const FieldIR, diags: *diag_mod.DiagList) void {
    for (ir.violations[0..ir.violation_count]) |*v| {
        if (diags.push(v.code, .err, 0, v.line, v.col, 1, v.text())) |d| {
            if (v.help_len > 0) {
                const idx = diags.count - 1;
                diags.helpAt(idx, v.helpText());
            }
            _ = d;
        }
    }
}

// ── CLI ─────────────────────────────────────────────────────────────────────

pub fn cmdCmf(args: []const []const u8) void {
    var path: ?[]const u8 = null;
    var format: CmfFormat = .human;
    var idx: usize = 0;
    while (idx < args.len) : (idx += 1) {
        const arg = args[idx];
        if (eql(arg, "--json")) {
            format = .json;
        } else if (eql(arg, "--help") or eql(arg, "-h")) {
            printCmfUsage();
            return;
        } else if (arg.len > 0 and arg[0] == '-') {
            util.printErr("Error: unexpected argument '");
            util.printErr(arg);
            util.printErr("'\n");
            util.sysExit(1);
        } else {
            path = arg;
        }
    }
    const file = path orelse {
        printCmfUsage();
        util.sysExit(1);
    };
    const source = util.readFileAlloc(std.heap.page_allocator, file) catch {
        util.printErr("Error: cannot read '");
        util.printErr(file);
        util.printErr("'\n");
        util.sysExit(1);
    };
    defer std.heap.page_allocator.free(source);

    var ir = parseField(source);

    if (format == .json) {
        renderJson(&ir, file);
    } else {
        renderHuman(&ir, file);
        if (!ir.ok()) {
            var diags = diag_mod.DiagList.init();
            emitViolations(&ir, &diags);
            diags.emitAll(file, source);
        }
    }
    if (!ir.ok()) util.sysExit(1);
}

pub fn printCmfUsage() void {
    util.printStr(
        \\Usage: lir cmf <file.cmf> [--json]
        \\
        \\Reads a Causal Morphogenetic Field and checks every claim in it.
        \\A field is a declarative surface: shapes (morph), substrate (field),
        \\commitments (claim) and expression (bloom). Blooms are constructed: each
        \\witness is substituted into the body and the result is type-checked and
        \\IR-verified. Nothing is executed, and a refused variant is never emitted.
        \\
        \\  morph Transition =<< t1 t2 t3 >>=      closed shape: exactly those instances
        \\  morph Any       =<> u8 u16 u32 u64 <>= open shape: instances from domains
        \\  field ledger: u64[1024] ?exclusive      substrate with a checkable surface
        \\  field window: i64[8] ?shared            substrate with no uniqueness claim
        \\  claim linear_ledger over ledger for 4tick runtime adjudicate  -> checked
        \\  claim total_order   over ledger check uniqueness               -> checked
        \\
        \\Every claim must be covered by a check or an adjudicator, and every
        \\reference must resolve. Uncovered claims are errors, not runtime surprises.
        \\Exit codes: 0 accepted, 1 rejected (violations printed on stderr).
        \\
    );
}

// ── Tests ───────────────────────────────────────────────────────────────────

test "a well-formed field is accepted and its variant surface is counted" {
    const src =
        \\morph Transition =<< t1 t2 t3 >>=
        \\field ledger: u64[1024] ?exclusive
        \\claim total over ledger for 4tick runtime adjudicate
        \\claim exclusive_writer over ledger check uniqueness
    ;
    const ir = parseField(src);
    try std.testing.expect(ir.violation_count == 0);
    try std.testing.expectEqual(@as(usize, 1), ir.morph_count);
    try std.testing.expectEqual(@as(usize, 3), ir.max_variants);
}

test "a claim nobody falsifies is rejected" {
    const src =
        \\field ledger: u64[8]
        \\claim slow over ledger for 3tick
    ;
    const ir = parseField(src);
    try std.testing.expect(ir.violation_count > 0);
}

test "a check that is not implemented is rejected with the implemented list" {
    const src =
        \\field ledger: u64[8]
        \\claim magic over ledger check vibes
    ;
    const ir = parseField(src);
    try std.testing.expect(ir.violation_count > 0);
    try std.testing.expect(std.mem.indexOf(u8, ir.violations[0].text(), "no checker implements") != null);
}

test "a bloom over an undeclared morph fails closed" {
    const src =
        \\bloom expand: morph Ghost
    ;
    const ir = parseField(src);
    try std.testing.expect(ir.violation_count > 0);
}

test "unknown directives are named in the diagnostic" {
    const src =
        \\morph M =<< a >>=
        \\teleport x
    ;
    const ir = parseField(src);
    try std.testing.expect(ir.violation_count > 0);
    try std.testing.expect(std.mem.indexOf(u8, ir.violations[0].text(), "teleport") != null);
}
