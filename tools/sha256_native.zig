// Self-contained, position-independent software SHA-256. K passed in (rcx) -> .text relocatable.
pub export fn lir_sha256(data: [*]const u8, len: u64, out: [*]u8, K: [*]const u32) callconv(.C) void {
    var h = [_]u32{ 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19 };
    var w: [64]u32 = undefined;
    var i: usize = 0;
    var idx: usize = 0;
    while (idx + 64 <= len) : (idx += 64) {
        loadBlock(data, idx, &w);
        sched(&w);
        compress(&h, &w, K);
    }
    var tail: [128]u8 = undefined;
    { var zi: usize = 0; while (zi < 128) : (zi += 1) { tail[zi] = 0; asm volatile ("" ::: "memory"); } }
    const rem = len - idx;
    i = 0; while (i < rem) : (i += 1) { tail[i] = data[idx + i]; asm volatile ("" ::: "memory"); }
    tail[rem] = 0x80;
    const tl: usize = if (rem >= 56) 128 else 64;
    const bits: u64 = len * 8;
    i = 0; while (i < 8) : (i += 1) tail[tl - 1 - i] = @truncate(bits >> @as(u6, @intCast(i * 8)));
    var nb: usize = 0;
    while (nb < tl) : (nb += 64) {
        loadBlock(@as([*]const u8, @ptrCast(&tail)), nb, &w);
        sched(&w);
        compress(&h, &w, K);
    }
    i = 0; while (i < 8) : (i += 1) {
        out[i*4]   = @truncate(h[i] >> 24);
        out[i*4+1] = @truncate(h[i] >> 16);
        out[i*4+2] = @truncate(h[i] >> 8);
        out[i*4+3] = @truncate(h[i]);
    }
}
fn loadBlock(p: [*]const u8, off: usize, w: *[64]u32) void {
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        w[i] = (@as(u32,p[off+i*4])<<24) | (@as(u32,p[off+i*4+1])<<16) | (@as(u32,p[off+i*4+2])<<8) | @as(u32,p[off+i*4+3]);
    }
}
fn sched(w: *[64]u32) void {
    var i: usize = 16;
    while (i < 64) : (i += 1) {
        const s0 = rotr(w[i-15],7) ^ rotr(w[i-15],18) ^ (w[i-15]>>3);
        const s1 = rotr(w[i-2],17) ^ rotr(w[i-2],19) ^ (w[i-2]>>10);
        w[i] = w[i-16] +% s0 +% w[i-7] +% s1;
    }
}
fn rotr(x: u32, comptime n: comptime_int) u32 { return (x >> @as(u5,@intCast(n))) | (x << @as(u5,@intCast(32 - n))); }
fn compress(h: *[8]u32, w: *const [64]u32, K: [*]const u32) void {
    var a=h[0]; var b=h[1]; var c=h[2]; var d=h[3]; var e=h[4]; var f=h[5]; var g=h[6]; var hh=h[7];
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        const S1 = rotr(e,6) ^ rotr(e,11) ^ rotr(e,25);
        const ch = (e & f) ^ (~e & g);
        const t1 = hh +% S1 +% ch +% K[i] +% w[i];
        const S0 = rotr(a,2) ^ rotr(a,13) ^ rotr(a,22);
        const mj = (a & b) ^ (a & c) ^ (b & c);
        const t2 = S0 +% mj;
        hh=g; g=f; f=e; e=d +% t1; d=c; c=b; b=a; a=t1 +% t2;
    }
    h[0]+%=a; h[1]+%=b; h[2]+%=c; h[3]+%=d; h[4]+%=e; h[5]+%=f; h[6]+%=g; h[7]+%=hh;
}
