#!/usr/bin/env python3
"""Paired, interleaved A/B harness for LIR-generated and Zig-generated binaries.

The point of this script is *reliability on a noisy, shared virtual machine*.
Naively running every sample of binary A and then every sample of binary B
conflates a real code difference with whatever else the host was doing during
that window. Instead this script:

  * compiles both sides once, validates that their stdout matches,
  * walks the samples in an interleaved (A, B, B, A, ...) order so slow
    periods hurt both sides equally,
  * reports the median of per-pair ratios rather than the ratio of medians,
  * reports a bootstrap confidence interval for the ratio and the coefficient
    of variation, so "no measurable difference" is visible instead of being
    hidden inside a single noisy 1.2x.

Usage:
  python3 tools/ab_bench.py --lir ./zig-out/bin/lir --zig zig \
      --workload fib_recursive_38 --workload branch_mix_30m --samples 15
"""
from __future__ import annotations

import argparse
import platform
import random
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKLOAD_DIR = ROOT / "bench" / "speed_compare"

ALL_WORKLOADS = (
    "fib_recursive_38",
    "fib_mod_30m",
    "branch_mix_30m",
    "collatz_sequence_1m",
    "prime_count_500k",
    "mandelbrot_fixed_2d",
    "bitwise_hash_20m",
    "nested_matrix_loop_4m",
    "tak_recursive_27",
)


def run_once(path: Path) -> tuple[float, bytes]:
    start = time.perf_counter_ns()
    proc = subprocess.run([str(path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    elapsed = (time.perf_counter_ns() - start) / 1e6
    if proc.returncode != 0:
        raise RuntimeError(f"{path} exited {proc.returncode}: {proc.stderr.decode(errors='replace')}")
    return elapsed, proc.stdout


def bootstrap_ci(values: list[float], rounds: int = 2000) -> tuple[float, float]:
    if len(values) < 3:
        return (min(values), max(values))
    rng = random.Random(0xC0FFEE)
    medians = []
    for _ in range(rounds):
        sample = [values[rng.randrange(len(values))] for _ in values]
        medians.append(statistics.median(sample))
    medians.sort()
    return medians[int(0.025 * len(medians))], medians[int(0.975 * len(medians))]


def cv(values: list[float]) -> float:
    if len(values) < 2:
        return 0.0
    mean = statistics.fmean(values)
    return statistics.stdev(values) / mean * 100.0 if mean else 0.0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lir", required=True)
    ap.add_argument("--zig", default="zig")
    ap.add_argument("--workload", action="append", choices=ALL_WORKLOADS)
    ap.add_argument("--samples", type=int, default=11)
    ap.add_argument("--warmups", type=int, default=3)
    ap.add_argument("--no-zig", action="store_true", help="time LIR binaries only")
    args = ap.parse_args()

    workloads = args.workload or list(ALL_WORKLOADS)
    print(f"host: {platform.platform()} | {platform.processor() or 'unknown CPU'}")
    print(f"interleaved samples per side: {args.samples}, warmups: {args.warmups}\n")

    failures = 0
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        for name in workloads:
            lir_src = WORKLOAD_DIR / f"{name}.lir"
            zig_src = WORKLOAD_DIR / f"{name}.zig"
            lir_bin = tmp / f"{name}.lir.bin"
            zig_bin = tmp / f"{name}.zig.bin"

            build = subprocess.run(
                [args.lir, "build", str(lir_src), "-o", str(lir_bin)],
                capture_output=True,
                text=True,
            )
            if build.returncode != 0:
                print(f"{name}: LIR BUILD FAILED\n{build.stderr}")
                failures += 1
                continue

            if not args.no_zig:
                zbuild = subprocess.run(
                    [args.zig, "build-exe", str(zig_src), "-O", "ReleaseFast", f"-femit-bin={zig_bin}"],
                    capture_output=True,
                    text=True,
                )
                if zbuild.returncode != 0:
                    print(f"{name}: ZIG BUILD FAILED\n{zbuild.stderr[-800:]}")
                    failures += 1
                    continue

            _, lir_out = run_once(lir_bin)
            if not args.no_zig:  # validate equal output before timing anything
                # Zig's std.debug.print writes to stderr; compare both streams.
                zig_proc = subprocess.run([str(zig_bin)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                lir_proc = subprocess.run([str(lir_bin)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                lir_out = lir_proc.stdout + lir_proc.stderr
                zig_out = zig_proc.stdout + zig_proc.stderr
                if lir_out.strip() != zig_out.strip():
                    print(f"{name}: OUTPUT MISMATCH lir={lir_out!r} zig={zig_out!r}")
                    failures += 1
                    continue

            for _ in range(args.warmups):
                run_once(lir_bin)
                if not args.no_zig:
                    run_once(zig_bin)

            lir_times: list[float] = []
            zig_times: list[float] = []
            for i in range(args.samples):
                if args.no_zig:
                    order = (lir_bin,)
                else:
                    # Alternate which side runs first so drift hits both equally.
                    order = (lir_bin, zig_bin) if i % 2 == 0 else (zig_bin, lir_bin)
                for binary in order:
                    elapsed, _ = run_once(binary)
                    (lir_times if binary == lir_bin else zig_times).append(elapsed)

            if args.no_zig:
                med = statistics.median(lir_times)
                print(f"{name:26s} lir {med:8.2f} ms  (cv {cv(lir_times):5.1f}%)  min {min(lir_times):7.2f}")
                continue

            ratios = [a / b for a, b in zip(lir_times, zig_times)]
            ratio = statistics.median(ratios)
            lo, hi = bootstrap_ci(ratios)
            verdict = "LIR faster" if ratio < 0.97 else ("Zig faster" if ratio > 1.03 else "equivalent")
            print(
                f"{name:26s} lir {statistics.median(lir_times):8.2f} ms | "
                f"zig {statistics.median(zig_times):8.2f} ms | "
                f"ratio {ratio:5.3f} [{lo:5.3f},{hi:5.3f}] "
                f"cv lir {cv(lir_times):4.1f}% zig {cv(zig_times):4.1f}%  {verdict}"
            )

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
