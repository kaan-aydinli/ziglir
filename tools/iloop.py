#!/usr/bin/env python3
"""Deterministic cost model for the hot loop of a LIR-generated binary.

Wall-clock measurement on a shared VM cannot separate a 5% code-quality change
from scheduler noise. This tool instead *counts*: it disassembles the emitted
code, finds the innermost loop (the largest backward branch), reads the trip
count from the comparison that guards it, and reports

  * instructions in the loop body,
  * modelled executed instructions = body + control overhead, times trips,
  * the same for a reference binary.

The model is deliberately simple and stated here so the numbers can be argued
with: a taken conditional branch counts 1, an untaken one counts 1, and every
instruction costs 1 regardless of execution ports. It is a proxy for front-end
work, not a cycle-accurate simulation.

Usage:
  python3 tools/iloop.py --binary /tmp/bm_new --reference /tmp/bm_old
  python3 tools/iloop.py --binary /tmp/bm_new --json
"""
from __future__ import annotations

import argparse
import json
import pathlib
import struct
import sys

try:
    import capstone
except ImportError:  # pragma: no cover - developer tool
    raise SystemExit("needs capstone: pip install capstone")


def code_bytes(binary: pathlib.Path) -> tuple[bytes, int]:
    data = binary.read_bytes()
    phoff = struct.unpack_from("<Q", data, 0x20)[0]
    phentsize = struct.unpack_from("<H", data, 0x36)[0]
    phnum = struct.unpack_from("<H", data, 0x38)[0]
    for index in range(phnum):
        base = phoff + index * phentsize
        p_type, p_flags = struct.unpack_from("<II", data, base)
        p_offset, p_vaddr, _, p_filesz = struct.unpack_from("<QQQQ", data, base + 8)
        if p_type == 1 and p_flags & 1:
            return data[p_offset:p_offset + p_filesz], p_vaddr
    raise SystemExit(f"{binary}: no executable PT_LOAD segment")


def disassemble(binary: pathlib.Path):
    blob, vaddr = code_bytes(binary)
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = True
    md.skipdata = True
    return blob, vaddr, list(md.disasm(blob, vaddr))


def is_jump(ins) -> bool:
    """True for real jump instructions (skipdata pseudos have no details)."""
    try:
        return ins.group(capstone.CS_GRP_JUMP) != 0
    except capstone.CsError:
        return False


def backward_branches(insns):
    """Yield (index, target_index) for every taken-capable backward branch."""
    addr_to_index = {ins.address: i for i, ins in enumerate(insns)}
    for i, ins in enumerate(insns):
        if is_jump(ins) and ins.operands:
            op = ins.operands[0]
            if op.type == capstone.x86.X86_OP_IMM:
                target = op.imm
                if target < ins.address and target in addr_to_index:
                    yield i, addr_to_index[target]


def loop_trips(insns, start: int, end: int) -> int | None:
    """Read the trip count from the comparison that guards the loop back edge.

    Handles the shapes this compiler emits: `cmp $imm, reg` followed by a
    conditional jump, where the register is incremented by a constant inside
    the loop. Returns None when the shape is not recognised, in which case the
    loop is reported as "count 1 per entry" (structural cost only).
    """
    for i in range(end, start - 1, -1):
        ins = insns[i]
        if ins.mnemonic != "cmp" or len(ins.operands) != 2:
            continue
        dst, src = ins.operands
        if dst.type != capstone.x86.X86_OP_REG:
            continue
        if src.type != capstone.x86.X86_OP_IMM:
            continue
        reg = ins.reg_name(dst.reg)
        bound = src.imm & 0xFFFFFFFFFFFFFFFF
        if bound >= 1 << 63:
            bound -= 1 << 64
        # find the increment of `reg` inside the loop
        for j in range(start, i):
            inner = insns[j]
            if inner.mnemonic == "add" and len(inner.operands) == 2:
                d2, s2 = inner.operands
                if (d2.type == capstone.x86.X86_OP_REG and inner.reg_name(d2.reg) == reg
                        and s2.type == capstone.x86.X86_OP_IMM and s2.imm > 0):
                    return max(0, bound // s2.imm)
        return None
    return None


def analyse(binary: pathlib.Path) -> dict:
    _, vaddr, insns = disassemble(binary)
    loops = []
    for end, start in backward_branches(insns):
        body = end - start + 1        # inclusive of the back edge
        trips = loop_trips(insns, start, end) or 1
        loops.append({
            "start": hex(insns[start].address),
            "end": hex(insns[end].address),
            "body": body,
            "trips": trips,
            "modelled": body * trips,
        })
    loops.sort(key=lambda l: l["modelled"], reverse=True)
    return {
        "binary": str(binary),
        "loops": loops,
        "total_loop_instructions": sum(l["modelled"] for l in loops),
    }


def describe(result: dict, reference: dict | None) -> str:
    out = [f"{result['binary']}: {len(result['loops'])} loop(s)"]
    for l in result["loops"][:6]:
        out.append(f"  {l['start']}..{l['end']}  body {l['body']:4d}  trips {l['trips']:10d}  modelled {l['modelled']:14d}")
    if reference is not None:
        a = result["total_loop_instructions"]
        b = reference["total_loop_instructions"]
        ratio = a / b if b else float("nan")
        out.append(f"  reference total {b}")
        out.append(f"  this total      {a}   ({ratio:.4f}x of reference)")
    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--binary", required=True)
    ap.add_argument("--reference")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    result = analyse(pathlib.Path(args.binary))
    reference = analyse(pathlib.Path(args.reference)) if args.reference else None
    if args.json:
        print(json.dumps({"candidate": result, "reference": reference}, indent=2))
    else:
        print(describe(result, reference))
    return 0


if __name__ == "__main__":
    sys.exit(main())
