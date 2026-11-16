#!/usr/bin/env python3
"""Measure raw LIR compile throughput, with process startup subtracted.

A single `lir build` on the small `bench/speed_compare` programs is dominated by
exec and dynamic-linking cost (~1 ms), which hides what the compiler actually
does. This harness times a large, legal source file (the compiler caps a unit at
256 functions, so 255 helpers + main is the maximum) and reports the median wall
time over N samples, so a change to the optimizer or the emitter is visible.

Usage:
  python3 tools/compile_bench.py --lir ./zig-out/bin/lir --samples 15
  python3 tools/compile_bench.py --lir ./zig-out/bin/lir --baseline /tmp/lir_old
"""
from __future__ import annotations

import argparse
import pathlib
import statistics
import subprocess
import sys
import tempfile
import time

LEVELS = ("-O0", "-O1", "-O2")

BODY = """fn fn{i}(a: i64, b: i64) -> i64 {{
    var x: i64 = a + b * {k}
    x = x * x + a
    return x
}}"""


def make_source(functions: int) -> str:
    parts = [BODY.format(i=i, k=(i % 97) + 1) for i in range(functions - 1)]
    parts.append("fn main() -> i64 { printInt(fn0(1,2)) return 0 }")
    return "\n".join(parts) + "\n"


def run_once(cmd: list[str]) -> float:
    start = time.perf_counter()
    done = subprocess.run(cmd, capture_output=True)
    elapsed = (time.perf_counter() - start) * 1000.0
    if done.returncode != 0:
        raise SystemExit(f"failed: {' '.join(cmd)}\n{done.stderr.decode()[:2000]}")
    return elapsed


def timed_pair(a: list[str], b: list[str] | None, samples: int, warmups: int):
    """Time `a` (and optionally `b`) interleaved, so drift hits both equally.

    Warming up one command and then timing another silently compares two
    different binaries; every command is warmed and then sampled in the same
    alternating order.
    """
    cmds = [a] + ([b] if b else [])
    for _ in range(warmups):
        for cmd in cmds:
            run_once(cmd)
    times: list[list[float]] = [[] for _ in cmds]
    for index in range(samples):
        order = range(len(cmds)) if index % 2 == 0 else reversed(range(len(cmds)))
        for slot in order:
            times[slot].append(run_once(cmds[slot]))
    return [statistics.median(t) for t in times]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--lir", required=True, help="compiler binary under test")
    ap.add_argument("--samples", type=int, default=15)
    ap.add_argument("--warmups", type=int, default=3)
    ap.add_argument("--functions", type=int, default=256)
    ap.add_argument("--baseline", help="second compiler binary to compare against")
    args = ap.parse_args()

    with tempfile.TemporaryDirectory(prefix="lir-cbench-") as td:
        tmp = pathlib.Path(td)
        src = tmp / "big.lir"
        src.write_text(make_source(args.functions))
        tiny = tmp / "tiny.lir"
        tiny.write_text("fn main() -> i64 { return 0 }\n")
        out = tmp / "out.bin"
        print(f"source: {args.functions} functions, {len(src.read_text().splitlines())} lines")
        print(f"samples: {args.samples}, warmups: {args.warmups}")
        print("net = (big file) - (one-line file), i.e. process startup removed\n")
        # Spawn cost of the binary itself, used to report net compile work.
        overhead = timed_pair([args.lir, "check", str(tiny)],
                              [args.baseline, "check", str(tiny)] if args.baseline else None,
                              args.samples, args.warmups)
        print(f"process+startup overhead: {overhead[0]:.2f} ms" +
              (f" (baseline {overhead[1]:.2f} ms)" if args.baseline else "") + "\n")

        rows = []
        for level in LEVELS:
            new_cmd = [args.lir, "build", str(src), level, "-o", str(out)]
            old_cmd = [args.baseline, "build", str(src), level, "-o", str(out)] if args.baseline else None
            measured = timed_pair(new_cmd, old_cmd, args.samples, args.warmups)
            row = {"level": level, "new": measured[0]}
            if old_cmd:
                row["old"] = measured[1]
            rows.append(row)

        for row in rows:
            row["net_new"] = row["new"] - overhead[0]
            if "old" in row:
                row["net_old"] = row["old"] - overhead[1]
                ratio = row["net_old"] / row["net_new"] if row["net_new"] > 0 else float("nan")
                print(f"{row['level']}  new {row['new']:6.2f} ms (net {row['net_new']:6.2f})"
                      f" | baseline {row['old']:6.2f} ms (net {row['net_old']:6.2f})"
                      f" | net speedup {ratio:5.2f}x")
            else:
                print(f"{row['level']}  {row['new']:6.2f} ms (net {row['net_new']:6.2f})")

        if args.baseline:
            total_new = sum(r["net_new"] for r in rows)
            total_old = sum(r["net_old"] for r in rows)
            print(f"\nnet total  new {total_new:6.2f} ms | baseline {total_old:6.2f} ms | speedup {total_old/total_new:5.2f}x")
    return 0


if __name__ == "__main__":
    sys.exit(main())
