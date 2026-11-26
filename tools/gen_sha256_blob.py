#!/usr/bin/env python3
"""Regenerate the hex blob literal in src/bootstrap/sha256_blob.zig.

Usage:
    zig build-obj tools/sha256_native.zig -OReleaseFast -fPIC -target x86_64-linux-gnu
    objcopy -O binary --only-section=.text tools/sha256_native.o /tmp/sha256_text.bin
    python3 tools/gen_sha256_blob.py /tmp/sha256_text.bin

Rewrites only the `sha256_code_hex` literal and the size guard, leaving the rest
of the file intact. The blob must have zero .text relocations (K is passed in);
verify with: readelf -r tools/sha256_native.o | grep -A2 rela.text
"""
import re
import sys

def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    blob = open(sys.argv[1], "rb").read()
    hexstr = blob.hex()
    chunks = [hexstr[i:i + 64] for i in range(0, len(hexstr), 64)]
    lit = " ++\n    ".join(f'"{c}"' for c in chunks)
    path = "src/bootstrap/sha256_blob.zig"
    src = open(path).read()
    src = re.sub(r"pub const sha256_code_hex =\n(?:    .*?\n)*?;",
                 f"pub const sha256_code_hex =\n    {lit};", src, count=1)
    src = re.sub(r"if \(sha256_code\.len != \d+\)",
                 f"if (sha256_code.len != {len(blob)})", src, count=1)
    open(path, "w").write(src)
    print(f"updated {path}: {len(blob)} bytes -> {len(chunks)} hex lines")

if __name__ == "__main__":
    main()
