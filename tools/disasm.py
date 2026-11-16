#!/usr/bin/env python3
"""Disassemble a LIR-produced ELF64 executable.

The bootstrap compiler emits a minimal `ET_EXEC` binary with program headers
only (no section header table), so `objdump -d` cannot be pointed at it
directly. This helper walks `PT_LOAD` segments, extracts the executable one,
and pipes the bytes through `objdump -D -b binary -m i386:x86-64`.

Usage:
  python3 tools/disasm.py /tmp/hello            # whole code segment
  python3 tools/disasm.py /tmp/hello --grep main
"""
from __future__ import annotations

import argparse
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

PT_LOAD = 1
PF_X = 1


def segments(data: bytes) -> list[tuple[int, int, int, int]]:
    """Yield (vaddr, offset, filesz, flags) for every PT_LOAD segment."""
    phoff = struct.unpack_from("<Q", data, 0x20)[0]
    phentsize = struct.unpack_from("<H", data, 0x36)[0]
    phnum = struct.unpack_from("<H", data, 0x38)[0]
    out = []
    for index in range(phnum):
        base = phoff + index * phentsize
        p_type, p_flags = struct.unpack_from("<II", data, base)
        p_offset, p_vaddr, _, p_filesz = struct.unpack_from("<QQQQ", data, base + 8)
        if p_type == PT_LOAD:
            out.append((p_vaddr, p_offset, p_filesz, p_flags))
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--grep", default=None, help="only show disassembly after a matching instruction")
    parser.add_argument("--limit", type=int, default=400, help="max instructions to print")
    args = parser.parse_args()

    data = args.binary.read_bytes()
    if data[:4] != b"\x7fELF":
        print("not an ELF file", file=sys.stderr)
        return 2

    exec_segments = [s for s in segments(data) if s[3] & PF_X]
    if not exec_segments:
        print("no executable PT_LOAD segment", file=sys.stderr)
        return 2

    for vaddr, offset, filesz, _ in exec_segments:
        code = data[offset : offset + filesz]
        with tempfile.NamedTemporaryFile(suffix=".bin") as tmp:
            tmp.write(code)
            tmp.flush()
            proc = subprocess.run(
                [
                    "objdump",
                    "-D",
                    "-b",
                    "binary",
                    "-m",
                    "i386:x86-64",
                    f"--adjust-vma=0x{vaddr:x}",
                    "--no-show-raw-insn",
                    tmp.name,
                ],
                capture_output=True,
                text=True,
            )
        if proc.returncode != 0:
            print(proc.stderr, file=sys.stderr)
            return proc.returncode
        lines = proc.stdout.splitlines()
        if args.grep:
            lines = [ln for ln in lines if args.grep in ln]
        print(f"# segment vaddr=0x{vaddr:x} size={filesz} B")
        print("\n".join(lines[: args.limit]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
