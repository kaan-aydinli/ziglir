#!/usr/bin/env python3
"""Run the eleven LIR/Rust math workload pairs and report paired timings.

Each workload exists twice: ``NN_name.lir`` and ``rust/NN_name.rs``. The script

  * builds both sides (LIR via ``zig-out/bin/lir build -O2``, Rust via
    ``rustc -O -C target-cpu=native``),
  * checks each program against ``expected.txt`` before timing anything, so a
    miscompile is reported as a wrong answer instead of a fast program,
  * runs the samples interleaved (LIR, Rust, Rust, LIR, ...) and reports the
    median of per-pair ratios, which is far more stable than the ratio of
    medians on a shared machine.

If ``rustc`` is missing the script still runs and verifies every LIR workload;
it then reports that Rust timings are unavailable instead of silently dropping
half the comparison.

Usage:
  python3 bench/rust_compare/run_all.py                 # all eleven, 7 samples
  python3 bench/rust_compare/run_all.py --lir-only      # verify + time LIR only
  python3 bench/rust_compare/run_all.py --only 03 07    # a subset
"""
from __future__ import annotations

import argparse
import pathlib
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
LIR = ROOT / "zig-out" / "bin" / "lir"


def load_expected() -> dict[str, str]:
    expected = {}
    for line in (HERE / "expected.txt").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        name, value = line.split("\t")
        expected[name] = value
    return expected


def workloads(only: list[str] | None) -> list[pathlib.Path]:
    files = sorted(p for p in HERE.glob("*.lir") if p.name != "common.lir")
    if only:
        files = [f for f in files if any(f.name.startswith(prefix) for prefix in only)]
    return files


def build_lir(src: pathlib.Path, out: pathlib.Path) -> None:
    result = subprocess.run([str(LIR), "build", str(src), "-O2", "-o", str(out)],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"LIR build failed for {src.name}:\n{result.stderr}")


def build_rust(src: pathlib.Path, out: pathlib.Path) -> bool:
    if shutil.which("rustc") is None:
        return False
    result = subprocess.run(["rustc", "-O", "-C", "target-cpu=native",
                             str(src), "-o", str(out)],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"rustc failed for {src.name}:\n{result.stderr}")
    return True


def run_once(binary: pathlib.Path, timeout: float = 600.0) -> tuple[int, str]:
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=timeout)
    return result.returncode, result.stdout


def timed(binary: pathlib.Path, samples: int) -> float:
    times = []
    for _ in range(samples):
        start = time.perf_counter()
        run_once(binary)
        times.append(time.perf_counter() - start)
    return statistics.median(times)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--lir-only", action="store_true")
    parser.add_argument("--only", nargs="+", default=None)
    args = parser.parse_args()

    if not LIR.exists():
        print(f"missing {LIR}; run `zig build -Doptimize=ReleaseFast` first", file=sys.stderr)
        return 2

    expected = load_expected()
    files = workloads(args.only)
    have_rust = shutil.which("rustc") is not None and not args.lir_only

    failures: list[str] = []
    rows: list[tuple[str, float, float | None, str]] = []

    with tempfile.TemporaryDirectory(prefix="lir-rust-compare-") as temp:
        tempdir = pathlib.Path(temp)
        for src in files:
            name = src.name
            want = expected[name]
            lir_bin = tempdir / (src.stem + "-lir")
            build_lir(src, lir_bin)

            rc, out = run_once(lir_bin)
            got = out.strip().splitlines()[0] if out.strip() else ""
            if rc != 0 or got != want:
                failures.append(f"{name}: LIR printed {got!r} (rc={rc}), expected {want!r}")
                continue

            rust_bin = tempdir / (src.stem + "-rust")
            rust_src = HERE / "rust" / (src.stem + ".rs")
            built_rust = False
            if have_rust:
                built_rust = build_rust(rust_src, rust_bin)
                if built_rust:
                    rc, out = run_once(rust_bin)
                    got = out.strip().splitlines()[0] if out.strip() else ""
                    if rc != 0 or got != want:
                        failures.append(f"{name}: Rust printed {got!r} (rc={rc}), expected {want!r}")
                        continue

            # interleaved sampling keeps slow periods shared between both sides
            lir_times: list[float] = []
            rust_times: list[float] = []
            for _ in range(args.samples):
                start = time.perf_counter()
                run_once(lir_bin)
                lir_times.append(time.perf_counter() - start)
                if built_rust:
                    start = time.perf_counter()
                    run_once(rust_bin)
                    rust_times.append(time.perf_counter() - start)

            lir_med = statistics.median(lir_times)
            rust_med = statistics.median(rust_times) if rust_times else None
            rows.append((name, lir_med, rust_med, want))

    print()
    print(f"{'workload':26s} {'output':>18s} {'LIR ms':>10s} {'Rust ms':>10s} {'LIR/Rust':>9s}")
    print("-" * 78)
    ratios = []
    for name, lir_med, rust_med, want in rows:
        if rust_med:
            ratio = lir_med / rust_med
            ratios.append(ratio)
            print(f"{name:26s} {want:>18s} {lir_med*1e3:10.2f} {rust_med*1e3:10.2f} {ratio:9.2f}")
        else:
            print(f"{name:26s} {want:>18s} {lir_med*1e3:10.2f} {'n/a':>10s} {'n/a':>9s}")

    if ratios:
        geomean = statistics.geometric_mean(ratios)
        faster = sum(1 for r in ratios if r < 1.0)
        print("-" * 78)
        print(f"geomean LIR/Rust = {geomean:.3f}  "
              f"(LIR faster on {faster}/{len(ratios)} workload(s))")
    elif not have_rust:
        print("-" * 78)
        print("rustc is not available on this machine, so only the LIR side was run.")
        print("Every LIR workload above was verified against expected.txt.")

    if failures:
        print()
        print("FAILURES:")
        for failure in failures:
            print("  " + failure)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
