// ════════════════════════════════════════════════════════════════════════════
// DIAGNOSTICS — Structured compiler errors/warnings for humans AND machines
//
// Every diagnostic carries:
//   * a stable machine-readable code  (LIR-Exxxx / LIR-Wxxxx)
//   * severity, source span (file, line, column, length)
//   * a one-line message
//   * an optional "help" line with the concrete fix
//   * an optional machine-readable expectation (kind + value) so an automated
//     consumer can learn exactly which token/name/type was legal there.
//
// Two output formats are supported (selected with `--diagnostics=`):
//   human  → `<file>:<line>:<col>: error[LIR-Exxxx]: msg` + source snippet + help
//   json   → one compact JSON object (schema `lir.diagnostics.v1`) on stdout
//   short  → one machine-friendly line per diagnostic, no source snippets
//
// The JSON form is the contract used by tooling and AI agents; keep the schema
// stable and additive. See docs/AI.md.
// ════════════════════════════════════════════════════════════════════════════

const std = @import("std");
const util = @import("util.zig");

pub const Severity = enum(u8) {
    err,
    warning,
    note,

    pub fn label(self: Severity) []const u8 {
        return switch (self) {
            .err => "error",
            .warning => "warning",
            .note => "note",
        };
    }

    pub fn code_prefix(self: Severity) u8 {
        return switch (self) {
            .err => 'E',
            .warning => 'W',
            .note => 'N',
        };
    }
};

/// Output format for diagnostics. `json` also suppresses the human rendering.
pub const Format = enum(u8) {
    human,
    short,
    json,

    pub fn parse(s: []const u8) ?Format {
        if (std.mem.eql(u8, s, "human") or std.mem.eql(u8, s, "text")) return .human;
        if (std.mem.eql(u8, s, "short") or std.mem.eql(u8, s, "line")) return .short;
        if (std.mem.eql(u8, s, "json")) return .json;
        return null;
    }
};

/// Process-wide default, set once from the CLI/env before compilation starts.
pub var default_format: Format = .human;

/// Stable diagnostic codes. Codes never change meaning across releases; new
/// codes are appended. The human message text may be reworded freely.
pub const Code = enum(u16) {
    // ── Frontend: lexer (1000-1099) ────────────────────────────────────────
    lex_invalid_character = 1001,
    lex_unterminated_literal = 1002,
    lex_token_capacity = 1003,
    lex_integer_literal = 1004,
    // ── Frontend: parser (2000-2099) ───────────────────────────────────────
    parse_syntax = 2001,
    parse_unsupported_statement = 2002,
    parse_unsupported_declaration = 2003,
    parse_recursion_depth = 2004,
    parse_unsupported_type = 2005,
    parse_unsupported_float = 2006,
    // ── Semantic analysis (3000-3099) ──────────────────────────────────────
    sema_generic = 3000,
    sema_undefined_variable = 3001,
    sema_undefined_function = 3002,
    sema_duplicate_declaration = 3003,
    sema_type_mismatch = 3004,
    sema_argument_count = 3005,
    sema_unknown_field = 3006,
    sema_undefined_struct = 3007,
    sema_loop_control = 3008,
    sema_invalid_assignment = 3009,
    sema_invalid_address_of = 3010,
    sema_symbol_capacity = 3011,
    // ── Modules / imports (4000-4099) ──────────────────────────────────────
    module_unresolved = 4001,
    module_read_failed = 4002,
    module_capacity = 4003,
    module_unknown = 4004,
    // ── Capacity limits (5000-5099) ────────────────────────────────────────
    limit_ast_capacity = 5001,
    limit_ir_strings = 5002,
    // ── Backend / verification (6000-6099) ─────────────────────────────────
    backend_ir_invalid = 6001,
    backend_emit_failed = 6002,
    // ── Driver / target selection (7000-7099) ──────────────────────────────
    driver_unsupported_target = 7001,
    driver_missing_main = 7002,
    driver_missing_input = 7003,
    target_missing_builtin = 7004,
    // ── Causal Morphogenetic Field (8000-8099) ─────────────────────────────
    cmf_syntax = 8001,
    cmf_duplicate = 8002,
    cmf_morph_empty = 8003,
    cmf_field_empty = 8004,
    cmf_claim_unsupported = 8005,
    cmf_claim_conflict = 8006,
    cmf_bloom_unsupported = 8007,
    cmf_variant_invalid = 8008,
    cmf_lens_unsupported = 8009,
    cmf_machine_unsupported = 8010,
    cmf_telemetry_unsupported = 8011,
    cmf_tuning_unsupported = 8012,
    // ── Internal (9000-9099) ───────────────────────────────────────────────
    internal = 9000,

    pub fn number(self: Code) u16 {
        return @intFromEnum(self);
    }
};

/// What an automated consumer should have written instead. Emitted in the JSON
/// form as `"expect": {"kind": "...", "value": "..."}`.
pub const Expect = struct {
    kind: []const u8 = "",
    value: [72]u8 = undefined,
    value_len: u8 = 0,

    pub fn text(self: *const Expect) []const u8 {
        return self.value[0..self.value_len];
    }
};

pub const MAX_MSG: usize = 192;
pub const MAX_HELP: usize = 224;

pub const Diagnostic = struct {
    severity: Severity,
    code: u16 = 0,
    source_id: u32 = 0,
    line: u32,
    col: u32,
    span_len: u32,
    msg: [MAX_MSG]u8,
    msg_len: u16,
    help: [MAX_HELP]u8 = undefined,
    help_len: u16 = 0,
    expect: Expect = .{},

    pub fn text(self: *const Diagnostic) []const u8 {
        return self.msg[0..self.msg_len];
    }

    pub fn helpText(self: *const Diagnostic) []const u8 {
        return self.help[0..self.help_len];
    }

    /// `LIR-E3001` style identifier, written into `buf` (min 16 bytes).
    pub fn codeText(self: *const Diagnostic, buf: *[16]u8) []const u8 {
        const n = if (self.code == 0) Code.internal.number() else self.code;
        return std.fmt.bufPrint(buf, "LIR-{c}{d:0>4}", .{ self.severity.code_prefix(), n }) catch "LIR-E9000";
    }
};

pub const DiagList = struct {
    items: [64]Diagnostic = undefined,
    count: u32 = 0,
    error_count: u32 = 0,
    warning_count: u32 = 0,
    overflowed: bool = false,
    quiet: bool = false,
    format: Format = .human,

    pub fn init() DiagList {
        return .{ .format = default_format };
    }

    pub fn initAs(format: Format) DiagList {
        return .{ .format = format };
    }

    /// True when the caller should not write human-readable output.
    pub fn machineOnly(self: *const DiagList) bool {
        return self.format == .json;
    }

    // ── primary constructors (code + message) ─────────────────────────────

    pub fn addAt(self: *DiagList, severity: Severity, source_id: u32, line: u32, col: u32, span_len: u32, message: []const u8) void {
        self.addCodedAt(.internal, severity, source_id, line, col, span_len, message);
    }

    pub fn addFmtAt(self: *DiagList, severity: Severity, source_id: u32, line: u32, col: u32, span_len: u32, comptime fmt: []const u8, args: anytype) void {
        self.addCodedFmtAt(.internal, severity, source_id, line, col, span_len, fmt, args);
    }

    pub fn add(self: *DiagList, severity: Severity, line: u32, col: u32, span_len: u32, message: []const u8) void {
        self.addCodedAt(.internal, severity, 0, line, col, span_len, message);
    }

    pub fn addFmt(self: *DiagList, severity: Severity, line: u32, col: u32, span_len: u32, comptime fmt: []const u8, args: anytype) void {
        self.addCodedFmtAt(.internal, severity, 0, line, col, span_len, fmt, args);
    }

    pub fn addCodedAt(self: *DiagList, code: Code, severity: Severity, source_id: u32, line: u32, col: u32, span_len: u32, message: []const u8) void {
        _ = self.push(code, severity, source_id, line, col, span_len, message);
    }

    pub fn addCodedFmtAt(self: *DiagList, code: Code, severity: Severity, source_id: u32, line: u32, col: u32, span_len: u32, comptime fmt: []const u8, args: anytype) void {
        var buf: [MAX_MSG]u8 = undefined;
        const slice = std.fmt.bufPrint(&buf, fmt, args) catch buf[0..];
        _ = self.push(code, severity, source_id, line, col, span_len, slice);
    }

    /// Adds a diagnostic and returns its index (or null when the list is full).
    pub fn push(self: *DiagList, code: Code, severity: Severity, source_id: u32, line: u32, col: u32, span_len: u32, message: []const u8) ?*Diagnostic {
        if (severity == .err) self.error_count += 1;
        if (severity == .warning) self.warning_count += 1;
        if (self.count >= self.items.len) {
            self.overflowed = true;
            return null;
        }
        const copy_len: usize = @min(message.len, MAX_MSG);
        var d = Diagnostic{
            .severity = severity,
            .code = code.number(),
            .source_id = source_id,
            .line = if (line == 0) 1 else line,
            .col = if (col == 0) 1 else col,
            .span_len = @max(@as(u32, 1), span_len),
            .msg = undefined,
            .msg_len = @intCast(copy_len),
        };
        @memcpy(d.msg[0..copy_len], message[0..copy_len]);
        self.items[self.count] = d;
        self.count += 1;
        return &self.items[self.count - 1];
    }

    // ── secondary decoration (help / expectation) ─────────────────────────

    pub fn helpAt(self: *DiagList, index: usize, text: []const u8) void {
        if (index >= self.count) return;
        const copy_len: usize = @min(text.len, MAX_HELP);
        @memcpy(self.items[index].help[0..copy_len], text[0..copy_len]);
        self.items[index].help_len = @intCast(copy_len);
    }

    pub fn helpFmtAt(self: *DiagList, index: usize, comptime fmt: []const u8, args: anytype) void {
        var buf: [MAX_HELP]u8 = undefined;
        const slice = std.fmt.bufPrint(&buf, fmt, args) catch buf[0..];
        self.helpAt(index, slice);
    }

    pub fn expectAt(self: *DiagList, index: usize, kind: []const u8, value: []const u8) void {
        if (index >= self.count) return;
        const copy_len: usize = @min(value.len, self.items[index].expect.value.len);
        @memcpy(self.items[index].expect.value[0..copy_len], value[0..copy_len]);
        self.items[index].expect.value_len = @intCast(copy_len);
        self.items[index].expect.kind = kind;
    }

    pub fn hasErrors(self: *const DiagList) bool {
        return self.error_count > 0;
    }

    // ── rendering ─────────────────────────────────────────────────────────

    pub fn emitAll(self: *const DiagList, filename: []const u8, src: []const u8) void {
        const fnames = [_][]const u8{filename};
        const srcs = [_][]const u8{src};
        self.emitAllSources(&fnames, &srcs);
    }

    pub fn emitAllSources(self: *const DiagList, filenames: []const []const u8, sources: []const []const u8) void {
        if (self.quiet) return;
        switch (self.format) {
            .json => self.emitJson(filenames, sources),
            .short => self.emitShort(filenames, sources),
            .human => self.emitHuman(filenames, sources),
        }
    }

    fn emitHuman(self: *const DiagList, filenames: []const []const u8, sources: []const []const u8) void {
        if (filenames.len == 0 or sources.len == 0) return;
        var code_buf: [16]u8 = undefined;
        for (self.items[0..self.count]) |*d| {
            const sid = if (d.source_id < filenames.len and d.source_id < sources.len) d.source_id else 0;
            const filename = filenames[sid];
            const src = sources[sid];

            util.printErr(filename);
            util.printErr(":");
            util.printErrUsize(d.line);
            util.printErr(":");
            util.printErrUsize(d.col);
            util.printErr(": ");
            util.printErr(d.severity.label());
            util.printErr("[");
            util.printErr(d.codeText(&code_buf));
            util.printErr("]: ");
            util.printErr(d.text());
            util.printErr("\n");

            if (lineSlice(src, d.line)) |src_line| {
                util.printErr("   ");
                util.printErrUsize(d.line);
                util.printErr(" | ");
                util.printErr(src_line);
                util.printErr("\n");

                // Caret underline
                util.printErr("     | ");
                const col_zero = if (d.col > 0) d.col - 1 else 0;
                const spaces = @min(@as(usize, col_zero), src_line.len + 16);
                var s_idx: usize = 0;
                while (s_idx < spaces) : (s_idx += 1) {
                    if (s_idx < src_line.len and src_line[s_idx] == '\t') {
                        util.printErr("\t");
                    } else {
                        util.printErr(" ");
                    }
                }
                const carets = @min(@as(usize, d.span_len), 40);
                var c_idx: usize = 0;
                while (c_idx < carets) : (c_idx += 1) {
                    util.printErr("^");
                }
                util.printErr("\n");
            }
            if (d.help_len > 0) {
                util.printErr("     = help: ");
                util.printErr(d.helpText());
                util.printErr("\n");
            }
        }
        if (self.overflowed) {
            util.printErr(filenames[0]);
            util.printErr(": note: additional diagnostics omitted (maximum 64)\n");
        }
    }

    /// One line per diagnostic, stable field order, no source snippets:
    ///   LIR-E3001 1:27 error undefined_identifier name=g g
    fn emitShort(self: *const DiagList, filenames: []const []const u8, sources: []const []const u8) void {
        _ = sources;
        var code_buf: [16]u8 = undefined;
        for (self.items[0..self.count]) |*d| {
            util.printErr(d.codeText(&code_buf));
            util.printErr(" ");
            util.printErrUsize(d.line);
            util.printErr(":");
            util.printErrUsize(d.col);
            util.printErr(" ");
            util.printErr(d.severity.label());
            util.printErr(" ");
            if (d.expect.kind.len > 0) util.printErr(d.expect.kind) else util.printErr("-");
            util.printErr(" ");
            util.printErr(d.text());
            if (d.expect.value_len > 0) {
                util.printErr(" [");
                util.printErr(d.expect.text());
                util.printErr("]");
            }
            if (filenames.len > 0 and d.source_id < filenames.len) {
                util.printErr(" (");
                util.printErr(filenames[d.source_id]);
                util.printErr(")");
            }
            util.printErr("\n");
        }
    }

    /// JSON diagnostics go to **stderr** so that stdout stays a single, complete
    /// JSON document describing the command result (see docs/AI.md). Both
    /// streams are JSON; consumers normally read stdout and parse stderr only
    /// when it is non-empty.
    fn emitJson(self: *const DiagList, filenames: []const []const u8, sources: []const []const u8) void {
        _ = sources;
        var out = std.io.getStdErr();
        const w = out.writer();
        w.print("{{\"schema\":\"lir.diagnostics.v1\",\"status\":\"{s}\",\"errors\":{d},\"warnings\":{d},\"truncated\":{s},\"diagnostics\":[", .{
            if (self.error_count > 0) "error" else if (self.warning_count > 0) "warning" else "ok",
            self.error_count,
            self.warning_count,
            if (self.overflowed) "true" else "false",
        }) catch return;
        var code_buf: [16]u8 = undefined;
        for (self.items[0..self.count], 0..) |*d, i| {
            if (i > 0) w.print(",", .{}) catch return;
            const file = if (filenames.len > 0 and d.source_id < filenames.len) filenames[d.source_id] else "";
            w.print("{{\"code\":\"{s}\",\"severity\":\"{s}\",\"file\":", .{ d.codeText(&code_buf), d.severity.label() }) catch return;
            writeJsonString(w, file) catch return;
            w.print(",\"line\":{d},\"column\":{d},\"length\":{d},\"message\":", .{ d.line, d.col, d.span_len }) catch return;
            writeJsonString(w, d.text()) catch return;
            if (d.help_len > 0) {
                w.print(",\"help\":", .{}) catch return;
                writeJsonString(w, d.helpText()) catch return;
            }
            if (d.expect.kind.len > 0) {
                w.print(",\"expect\":{{\"kind\":", .{}) catch return;
                writeJsonString(w, d.expect.kind) catch return;
                w.print(",\"value\":", .{}) catch return;
                writeJsonString(w, d.expect.text()) catch return;
                w.print("}}", .{}) catch return;
            }
            w.print("}}", .{}) catch return;
        }
        w.print("]}}\n", .{}) catch return;
    }
};

fn writeJsonString(w: anytype, s: []const u8) !void {
    try w.writeByte('"');
    for (s) |ch| {
        switch (ch) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => {
                if (ch < 0x20) {
                    try w.print("\\u{x:0>4}", .{ch});
                } else {
                    try w.writeByte(ch);
                }
            },
        }
    }
    try w.writeByte('"');
}

fn lineSlice(src: []const u8, target_line: u32) ?[]const u8 {
    if (target_line == 0 or src.len == 0) return null;
    var cur_line: u32 = 1;
    var line_start: usize = 0;
    var i: usize = 0;
    while (i <= src.len) : (i += 1) {
        const at_end = (i == src.len);
        if (at_end or src[i] == '\n') {
            if (cur_line == target_line) {
                var end = i;
                if (end > line_start and src[end - 1] == '\r') end -= 1;
                return src[line_start..end];
            }
            cur_line += 1;
            line_start = i + 1;
        }
    }
    return null;
}

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "diagnostic codes are stable and unique" {
    // Guard against accidental renumbering: these numbers are part of the
    // machine contract (docs/AI.md) and must never change meaning.
    try std.testing.expectEqual(@as(u16, 1001), Code.lex_invalid_character.number());
    try std.testing.expectEqual(@as(u16, 2001), Code.parse_syntax.number());
    try std.testing.expectEqual(@as(u16, 3001), Code.sema_undefined_variable.number());
    try std.testing.expectEqual(@as(u16, 3004), Code.sema_type_mismatch.number());
    try std.testing.expectEqual(@as(u16, 6001), Code.backend_ir_invalid.number());
    try std.testing.expectEqual(@as(u16, 7001), Code.driver_unsupported_target.number());
}

test "diagnostics carry code, help and expectation" {
    var diags = DiagList.initAs(.human);
    _ = diags.push(.sema_type_mismatch, .err, 0, 7, 3, 5, "expected i64, found string").?;
    diags.helpAt(diags.count - 1, "use an integer literal or cast with 'as'");
    diags.expectAt(diags.count - 1, "type", "i64");
    try std.testing.expectEqual(@as(u32, 1), diags.error_count);
    var code_buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("LIR-E3004", diags.items[0].codeText(&code_buf));
    try std.testing.expectEqualStrings("use an integer literal or cast with 'as'", diags.items[0].helpText());
    try std.testing.expectEqualStrings("i64", diags.items[0].expect.text());
    try std.testing.expectEqualStrings("type", diags.items[0].expect.kind);
}

test "diagnostic output formats are selectable" {
    try std.testing.expectEqual(Format.json, Format.parse("json").?);
    try std.testing.expectEqual(Format.short, Format.parse("short").?);
    try std.testing.expectEqual(Format.human, Format.parse("human").?);
    try std.testing.expect(Format.parse("xml") == null);
}
