#!/usr/bin/env python3
"""Compare two LIR-generated binaries (or LIR vs Zig) with a stability check.

Wall-clock time on a shared VM moves by more than the effects being measured:
an earlier session saw absolute throughput drift ~1.8x between two runs of
byte-identical binaries. So this harness reports, for every workload:

  * the median of per-pair ratios (A/B) rather than a ratio of medians, so a
    slow period hits both sides equally,
  * a bootstrap 95% interval for that ratio,
  * the coefficient of variation of each side, and
  * a "stable" verdict that is false when the interval is wider than the
    effect (|1 - ratio|), i.e. when the sample cannot support a claim.

Usage:
  python3 tools/rt_compare.py --a ./zig-out/bin/lir --b /tmp/lir_old
  python3 tools/rt_compare.py --a ./zig-out/bin/lir --zig zig
"""
from __future__ import annotations

import argparse
import pathlib
import random
import statistics
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKLOAD_DIR = ROOT / "bench" / "speed_compare"
WORKLOADS = sorted(p.stem for p in WORKLOAD_DIR.glob("*.lir"))


def build(lir: str, src: pathlib.Path, out: pathlib.Path, level: str) -> None:
    done = subprocess.run([lir, "build", str(src), level, "-o", str(out)],
                          capture_output=True, text=True)
    if done.returncode != 0:
        raise SystemExit(f"build failed for {src.name} with {lir}\n{done.stderr[:2000]}")


def run_once(binary: pathlib.Path) -> tuple[float, bytes]:
    import time
    start = time.perf_counter()
    done = subprocess.run([str(binary)], capture_output=True)
    return (time.perf_counter() - start) * 1000.0, done.stdout + done.stderr


def bootstrap_ci(values: list[float], rounds: int = 2000) -> tuple[float, float]:
    rng = random.Random(12345)
    n = len(values)
    medians = []
    for _ in range(rounds):
        medians.append(statistics.median(rng.choices(values, k=n)))
    medians.sort()
    return medians[int(0.025 * rounds)], medians[int(0.975 * rounds)]


def cv(values: list[float]) -> float:
    mean = statistics.fmean(values)
    return 0.0 if mean == 0 else statistics.pstdev(values) / mean * 100.0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--a", required=True, help="compiler producing the candidate binary")
    ap.add_argument("--b", help="compiler producing the reference binary")
    ap.add_argument("--zig", help="compare against Zig instead of a second LIR compiler")
    ap.add_argument("--level", default="-O2")
    ap.add_argument("--samples", type=int, default=11)
    ap.add_argument("--warmups", type=int, default=3)
    ap.add_argument("--workload", action="append", default=None)
    args = ap.parse_args()
    if not args.b and not args.zig:
        ap.error("give --b or --zig")
    if args.level not in ("-O0", "-O1", "-O2"):
        ap.error("level must be -O0, -O1 or -O2")

    names = args.workload or WORKLOADS
    unstable = 0
    with tempfile.TemporaryDirectory(prefix="lir-rt-") as td:
        tmp = pathlib.Path(td)
        print(f"A={args.a} B={args.b or 'zig ' + str(args.zig)} level={args.level}")
        print(f"paired samples={args.samples} warmups={args.warmups}\n")
        print(f"{'workload':26s} {'A ms':>8s} {'B ms':>8s} {'A/B':>6s} {'95% CI':>15s} {'cvA':>6s} {'cvB':>6s}  verdict")
        for name in names:
            src = WORKLOAD_DIR / f"{name}.lir"
            a_bin = tmp / f"{name}.a"
            b_bin = tmp / f"{name}.b"
            build(args.a, src, a_bin, args.level)
            if args.zig:
                zsrc = WORKLOAD_DIR / f"{name}.zig"
                b_bin = tmp / f"{name}.z"
                done = subprocess.run([args.zig, "build-exe", str(zsrc), "-O", "ReleaseFast",
                                       f"-femit-bin={b_bin}"], capture_output=True, text=True)
                if done.returncode != 0:
                    raise SystemExit(f"zig build failed for {name}\n{done.stderr[:1500]}")
            else:
                build(args.b, src, b_bin, args.level)

            a_out = run_once(a_bin)[1]
            b_out = run_once(b_bin)[1]
            if a_out.strip() != b_out.strip():
                print(f"{name:26s} OUTPUT MISMATCH a={a_out[:60]!r} b={b_out[:60]!r}")
                unstable += 1
                continue

            for _ in range(args.warmups):
                run_once(a_bin)
                run_once(b_bin)
            a_times: list[float] = []
            b_times: list[float] = []
            for index in range(args.samples):
                order = (a_bin, b_bin) if index % 2 == 0 else (b_bin, a_bin)
                for binary in order:
                    elapsed, _ = run_once(binary)
                    (a_times if binary == a_bin else b_times).append(elapsed)

            ratios = [a / b for a, b in zip(a_times, b_times)]
            median_ratio = statistics.median(ratios)
            lo, hi = bootstrap_ci(ratios)
            effect = abs(1.0 - median_ratio)
            half_width = (hi - lo) / 2.0
            if half_width > effect:
                verdict = "unstable (interval wider than effect)"
                unstable += 1
            elif median_ratio < 1.0:
                verdict = f"A faster {1/median_ratio:.2f}x"
            elif median_ratio > 1.0:
                verdict = f"B faster {median_ratio:.2f}x"
            else:
                verdict = "equal"
            print(f"{name:26s} {statistics.median(a_times):8.2f} {statistics.median(b_times):8.2f} "
                  f"{median_ratio:6.3f} [{lo:.3f},{hi:.3f}] {cv(a_times):6.1f} {cv(b_times):6.1f}  {verdict}")
    if unstable:
        print(f"\n{unstable} workload(s) could not be decided from this sample size.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
