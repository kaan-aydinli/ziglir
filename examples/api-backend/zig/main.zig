// ════════════════════════════════════════════════════════════════════════════
// Zig Enterprise API Backend (LirStore REST API Match)
//
// Standart Zig kütüphanesi (std.net, std.posix) ile yazılmış,
// LIR implementasyonu ile birebir aynı veri modellerini, uç noktaları
// ve iş mantığını içeren RESTful API mikroservisi.
// ════════════════════════════════════════════════════════════════════════════

const std = @import("std");
const net = std.net;
const posix = std.posix;

const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    role: []const u8,
    balance: i64,
    active: bool,
};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("================================================================\n", .{});
    try stdout.print("  ZIG ENTERPRISE API BACKEND\n", .{});
    try stdout.print("================================================================\n", .{});

    var users: [64]User = undefined;
    users[0] = .{ .id = 1, .name = "Alice Smith", .email = "alice@lir.org", .role = "admin", .balance = 5000, .active = true };
    users[1] = .{ .id = 2, .name = "Bob Jones", .email = "bob@lir.org", .role = "engineer", .balance = 3200, .active = true };
    users[2] = .{ .id = 3, .name = "David Miller", .email = "david@lir.org", .role = "designer", .balance = 2800, .active = true };

    var user_count: usize = 3;
    var next_user_id: i64 = 4;
    var req_counter: i64 = 0;

    const address = try net.Address.parseIp4("0.0.0.0", 8082);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    try stdout.print("Zig REST API Servisi dinliyor -> http://0.0.0.0:8082\n", .{});

    var req_buf: [4096]u8 = undefined;
    var resp_buf: [16384]u8 = undefined;

    while (true) {
        const connection = try server.accept();
        defer connection.stream.close();

        const read_bytes = try connection.stream.read(&req_buf);
        if (read_bytes == 0) continue;

        req_counter += 1;
        const req = req_buf[0..read_bytes];

        if (std.mem.startsWith(u8, req, "OPTIONS ")) {
            try sendResponse(connection.stream, 204, "No Content", "text/plain", "");
        } else if (std.mem.indexOf(u8, req, "GET /api/v1/health") != null) {
            const body = try std.fmt.bufPrint(&resp_buf,
                "{{\"status\":\"healthy\",\"engine\":\"Zig 0.13.0\",\"total_requests\":{d},\"uptime_ticks\":{d},\"memory\":\"manual-arena\"}}\n",
                .{ req_counter, req_counter * 3 },
            );
            try sendResponse(connection.stream, 200, "OK", "application/json", body);
        } else if (std.mem.indexOf(u8, req, "GET /api/v1/stats") != null) {
            var total_bal: i64 = 0;
            var active_cnt: i64 = 0;
            for (users[0..user_count]) |u| {
                if (u.active) {
                    active_cnt += 1;
                    total_bal += u.balance;
                }
            }
            const body = try std.fmt.bufPrint(&resp_buf,
                "{{\"total_users\":{d},\"active_users\":{d},\"total_balance\":{d},\"requests_processed\":{d}}}\n",
                .{ user_count, active_cnt, total_bal, req_counter },
            );
            try sendResponse(connection.stream, 200, "OK", "application/json", body);
        } else if (std.mem.indexOf(u8, req, "GET /api/v1/users/") != null) {
            const id = parseUserId(req);
            var found_user: ?User = null;
            for (users[0..user_count]) |u| {
                if (u.id == id and u.active) {
                    found_user = u;
                    break;
                }
            }
            if (found_user) |u| {
                const body = try std.fmt.bufPrint(&resp_buf,
                    "{{\"id\":{d},\"name\":\"{s}\",\"email\":\"{s}\",\"role\":\"{s}\",\"balance\":{d},\"active\":true}}\n",
                    .{ u.id, u.name, u.email, u.role, u.balance },
                );
                try sendResponse(connection.stream, 200, "OK", "application/json", body);
            } else {
                try sendResponse(connection.stream, 404, "Not Found", "application/json", "{\"error\":\"UserNotFound\",\"code\":404,\"message\":\"Kullanici bulunamadi\"}\n");
            }
        } else if (std.mem.indexOf(u8, req, "GET /api/v1/users") != null) {
            var fbs = std.io.fixedBufferStream(&resp_buf);
            const w = fbs.writer();
            try w.print("{{\"count\":{d},\"users\":[", .{user_count});
            var first = true;
            for (users[0..user_count]) |u| {
                if (u.active) {
                    if (!first) try w.writeAll(",");
                    first = false;
                    try w.print("{{\"id\":{d},\"name\":\"{s}\",\"email\":\"{s}\",\"role\":\"{s}\",\"balance\":{d}}}", .{ u.id, u.name, u.email, u.role, u.balance });
                }
            }
            try w.writeAll("]}\n");
            try sendResponse(connection.stream, 200, "OK", "application/json", fbs.getWritten());
        } else if (std.mem.indexOf(u8, req, "POST /api/v1/users") != null) {
            const has_auth = std.mem.indexOf(u8, req, "Bearer lir-secret-token-2026") != null;
            if (!has_auth) {
                try sendResponse(connection.stream, 401, "Unauthorized", "application/json", "{\"error\":\"Unauthorized\",\"code\":401,\"message\":\"Gecersiz veya eksik Bearer token\"}\n");
            } else if (user_count >= 63) {
                try sendResponse(connection.stream, 507, "Insufficient Storage", "application/json", "{\"error\":\"CapacityExceeded\",\"code\":507,\"message\":\"Kullanici kapasitesi dolu\"}\n");
            } else {
                const new_id = next_user_id;
                next_user_id += 1;
                users[user_count] = .{
                    .id = new_id,
                    .name = "New User",
                    .email = "newuser@lir.org",
                    .role = "member",
                    .balance = 1000,
                    .active = true,
                };
                user_count += 1;

                const body = try std.fmt.bufPrint(&resp_buf,
                    "{{\"message\":\"UserCreated\",\"id\":{d},\"name\":\"New User\",\"status\":\"created\"}}\n",
                    .{new_id},
                );
                try sendResponse(connection.stream, 201, "Created", "application/json", body);
            }
        } else if (std.mem.indexOf(u8, req, "DELETE /api/v1/users/") != null) {
            const has_auth = std.mem.indexOf(u8, req, "Bearer lir-secret-token-2026") != null;
            if (!has_auth) {
                try sendResponse(connection.stream, 401, "Unauthorized", "application/json", "{\"error\":\"Unauthorized\",\"code\":401,\"message\":\"Gecersiz veya eksik Bearer token\"}\n");
            } else {
                const target_id = parseUserId(req);
                var found = false;
                for (users[0..user_count]) |*u| {
                    if (u.id == target_id and u.active) {
                        u.active = false;
                        found = true;
                        break;
                    }
                }
                if (found) {
                    const body = try std.fmt.bufPrint(&resp_buf,
                        "{{\"message\":\"UserDeleted\",\"id\":{d},\"success\":true}}\n",
                        .{target_id},
                    );
                    try sendResponse(connection.stream, 200, "OK", "application/json", body);
                } else {
                    try sendResponse(connection.stream, 404, "Not Found", "application/json", "{\"error\":\"UserNotFound\",\"code\":404,\"message\":\"Silinecek kullanici bulunamadi\"}\n");
                }
            }
        } else {
            try sendResponse(connection.stream, 404, "Not Found", "application/json", "{\"error\":\"NotFound\",\"code\":404,\"message\":\"Gecersiz API rotasi\"}\n");
        }
    }
}

fn parseUserId(req: []const u8) i64 {
    const prefix = "/api/v1/users/";
    const idx = std.mem.indexOf(u8, req, prefix) orelse return -1;
    var k = idx + prefix.len;
    var id: i64 = 0;
    var found = false;
    while (k < req.len) : (k += 1) {
        const c = req[k];
        if (c >= '0' and c <= '9') {
            id = id * 10 + (c - '0');
            found = true;
        } else {
            break;
        }
    }
    return if (found) id else -1;
}

fn sendResponse(stream: net.Stream, code: u16, text: []const u8, content_type: []const u8, body: []const u8) !void {
    var hdr_buf: [1024]u8 = undefined;
    const hdr = try std.fmt.bufPrint(&hdr_buf,
        "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: Authorization, Content-Type\r\nAccess-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\nConnection: close\r\n\r\n",
        .{ code, text, content_type, body.len },
    );
    try stream.writeAll(hdr);
    if (body.len > 0) {
        try stream.writeAll(body);
    }
}
