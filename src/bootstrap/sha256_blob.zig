//! Native SHA-256 code blob for the freestanding x86-64 backend (`ir_codegen.zig`).
//!
//! The native backend emits a standalone ELF with no libc and no dynamic loader,
//! so it cannot call into Zig's std or OpenSSL. Instead, the SHA-256 compression
//! is shipped as a precompiled, position-independent machine-code blob that the
//! emitter copies verbatim into the runtime section and calls through the
//! `.sha256_fn` relocation target.
//!
//! The blob is the `.text` of `tools/sha256_native.zig`, compiled with:
//!
//!     zig build-obj tools/sha256_native.zig -OReleaseFast -fPIC -target x86_64-linux-gnu
//!     objcopy -O binary --only-section=.text tools/sha256_native.o sha256_text.bin
//!
//! It has ZERO `.text` relocations: the SHA-256 round constants `K` are passed in
//! as the 4th argument (rcx) rather than referenced from rodata, so the code is
//! fully position-independent and can be copied to any address. Calling
//! convention (SysV AMD64): `lir_sha256(data: rdi, len: rsi, out: rdx, K: rcx)`.
//!
//! Regenerate the hex literal below with `tools/gen_sha256_blob.py` after any
//! change to `tools/sha256_native.zig`. Correctness is pinned by the
//! "native @sha256 blob" test in `tests.zig` (known-answer vectors), so a stale
//! or corrupt blob fails the build.
const std = @import("std");

/// Hex-encoded `.text` of the position-independent SHA-256 routine.
pub const sha256_code_hex =
    "554157415641554154534881ecb80100004989ce488954243048897424204883" ++
    "fe407334bb67e6096a41bb85ae67bb41bf72f36e3c31f641ba3af54fa5ba7f52" ++
    "0e5141b98c68059b41b8abd9831fb919cde05be9bb01000041bd67e6096ab840" ++
    "00000041bc85ae67bbc7042472f36e3cc74424043af54fa5c74424087f520e51" ++
    "c744240c8c68059bc7442410abd9831fbd19cde05b31f648897c24280f1f4000" ++
    "4889442418488d542438e891040000b8100000008b4c24380f1f840000000000" ++
    "8b5484fc8b74843089d7c1c7194189d041c1c00e4131f889d74189f141c1c10f" ++
    "c1ef034189f241c1c20d4431c74531cac1ee0a4431d6034c841c01f901f1894c" ++
    "84384883c00189d14883f84075b24489eb4589e3448b3c2431c0448b5424048b" ++
    "542408448b4c240c448b442410896c241489e9662e0f1f8400000000000f1f00" ++
    "4489c74589c84189d14489d54589fa4589dfc1c21a4489cec1c61531d64489ca" ++
    "c1c20731f24489c64421ce01ce4489c9f7d121f901f101d141030c86034c8438" ++
    "4189db89dac1c21e89dec1c61331d689dac1c20a31f24489d64431fe21de4489" ++
    "d34421fb31f301d389ea01ca01cb89f94883c0014883f84075864401eb4501e3" ++
    "44033c2444035424040354240844034c240c4403442410034c2414488b742418" ++
    "488d464089cd448944241044894c240c89542408448954240444893c244589dc" ++
    "4189dd483b442420488b7c24280f868dfeffff44895c2414448954241844893c" ++
    "248954240444894c2408448944240c894c241031c0662e0f1f84000000000090" ++
    "c6840438010000004883c001483d8000000075ec488b4c24204829f174264801" ++
    "f731c0662e0f1f8400000000000f1f000fb61407889404380100004883c00148" ++
    "39c175ecc6840c380100008031c04883f9380f93c0c1e006488d484048894c24" ++
    "28488b5424208d0cd500000000488db42438010000884c303f89d1c1e905884c" ++
    "303e89d1c1e90d884c303d89d1c1e915884c303c4889d148c1e91d884c303b48" ++
    "89d148c1e925884c303a4889d148c1e92d884c303948c1ea35885430384531ff" ++
    "488dbc24380100004c89fe488d542438e82b020000b8100000008b4c24386690" ++
    "8b5484fc8b74843089d7c1c7194189d041c1c00e4131f889d74189f141c1c10f" ++
    "c1ef034189f241c1c20d4431c74531cac1ee0a4431d6034c841c01f901f1894c" ++
    "84384883c00189d14883f84075b24189da448b5c2414448b04248b6c24188b74" ++
    "24048b442408448b6c240c448b6424104531c9662e0f1f8400000000000f1f00" ++
    "4489e24589ec4189c589f089ee4489c54589d84189c341c1c31a89c1c1c11544" ++
    "31d94189c341c1c3074131cb4489e921c101d189c2f7d24421e201ca4401da43" ++
    "03148e4203548c384589d34489d1c1c11e41c1c2134131ca4489d9c1c10a4431" ++
    "d189ef4431c74421df4189ea4521c24131fa4101ca01d64101d24983c1014983" ++
    "f9400f8578ffffff4401d344015c241444010424016c24180174240401442408" ++
    "44016c240c44016424104983c7404c3b7c24280f82a7feffff89d8c1e818488b" ++
    "4c2430880189d8c1e8108841018879028859038b54241489d0c1e81888410489" ++
    "d0c1e8108841058871068851078b142489d0c1e81888410889d0c1e810884109" ++
    "88710a88510b8b54241889d0c1e81888410c89d0c1e81088410d88710e88510f" ++
    "8b54240489d0c1e81888411089d0c1e8108841118871128851138b54240889d0" ++
    "c1e81888411489d0c1e8108841158871168851178b54240c89d0c1e818884118" ++
    "89d0c1e81088411988711a88511b8b54241089d0c1e81888411c89d0c1e81088" ++
    "411d88711e88511f4881c4b80100005b415c415d415e415f5dc3660f1f440000" ++
    "8b04370fc889028b4437040fc88942048b4437080fc88942088b44370c0fc889" ++
    "420c8b4437100fc88942108b4437140fc88942148b4437180fc88942188b4437" ++
    "1c0fc889421c8b4437200fc88942208b4437240fc88942248b4437280fc88942" ++
    "288b44372c0fc889422c8b4437300fc88942308b4437340fc88942348b443738" ++
    "0fc88942388b44373c0fc889423cc3";

/// Decoded machine-code bytes (1487 bytes), ready to copy into the runtime.
pub const sha256_code: [sha256_code_hex.len / 2]u8 = blk: {
    @setEvalBranchQuota(8 * sha256_code_hex.len);
    var buf: [sha256_code_hex.len / 2]u8 = undefined;
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        buf[i] = (hexVal(sha256_code_hex[2 * i]) << 4) | hexVal(sha256_code_hex[2 * i + 1]);
    }
    break :blk buf;
};

fn hexVal(c: u8) u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => unreachable,
    };
}

/// SHA-256 round constants (first 32 bits of the fractional parts of the cube
/// roots of the first 64 primes). Passed to the blob in rcx; also written into
/// the emitted binary's rodata so the blob can reference them positionally.
pub const sha256_k: [64]u32 = .{
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

comptime {
    // Guard the blob/constant sizes the emitter relies on.
    if (sha256_code.len != 1487) @compileError("sha256 blob size changed; update emitter");
    if (sha256_k.len != 64) @compileError("sha256 K table must have 64 entries");
}

test "sha256 blob known-answer vectors" {
    // Run the position-independent blob from a freshly mapped (relocated) page to
    // prove it carries no absolute addresses, then check known SHA-256 digests.
    const page_len = ((sha256_code.len + 4095) / 4096) * 4096;
    const mem = try std.posix.mmap(
        null,
        page_len,
        std.posix.PROT.READ | std.posix.PROT.WRITE | std.posix.PROT.EXEC,
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    );
    defer std.posix.munmap(mem);
    @memcpy(mem[0..sha256_code.len], &sha256_code);

    const Sha = *const fn ([*]const u8, u64, [*]u8, [*]const u32) callconv(.C) void;
    const sha: Sha = @ptrCast(@alignCast(mem.ptr));

    const Case = struct { input: []const u8, digest: [32]u8 };
    const cases = [_]Case{
        .{ .input = "abc", .digest = hexToBytes("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") },
        .{ .input = "", .digest = hexToBytes("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") },
        .{ .input = "hello", .digest = hexToBytes("2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824") },
    };
    for (cases) |case| {
        var out: [32]u8 = undefined;
        sha(case.input.ptr, case.input.len, @ptrCast(&out), @ptrCast(&sha256_k));
        try std.testing.expectEqualSlices(u8, &case.digest, &out);
    }
}

fn hexToBytes(comptime hex: []const u8) [hex.len / 2]u8 {
    var buf: [hex.len / 2]u8 = undefined;
    for (&buf, 0..) |*b, i| b.* = (hexVal(hex[2 * i]) << 4) | hexVal(hex[2 * i + 1]);
    return buf;
}
