#!/usr/bin/env python3
"""Measure LIR against LLVM-compiled C twins of the Rust workloads.

Rust cannot be executed in this environment (no rustc/cargo, and the download
hosts for a toolchain are unreachable), so this script times three sides of the
same eleven workloads:

  LIR        ``NN_name.lir`` built by ``lir build -O2`` -- the subject.
  clang      ``c/NN_name.c`` built with ``zig cc -O3 -march=native``. There is
             only one C source per workload; both C columns are the *same*
             hand-written twin, compiled by two different compilers. The clang
             column is the closer proxy for Rust because rustc emits LLVM IR and
             uses LLVM's optimiser and x86-64 backend. Label it "LLVM C twin",
             never "Rust".
  gcc        the same source built with ``gcc -O2``, as an independent second
             reference point.

Every program is checked against ``expected.txt`` *before* anything is timed, so
a miscompile shows up as a wrong answer rather than as a suspiciously fast
binary. Samples are interleaved (LIR, clang, gcc, gcc, clang, LIR, ...) and the
reported ratio is the median of per-round ratios, which is much more stable on a
shared machine than the ratio of medians.

Usage:
  python3 bench/rust_compare/run_c.py                  # all eleven, 13 rounds
  python3 bench/rust_compare/run_c.py --rounds 21
  python3 bench/rust_compare/run_c.py --only 05 08
  python3 bench/rust_compare/run_c.py --verify-only     # outputs only, no timing
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
CSRC = HERE / "c"


def zig_cc() -> str | None:
    """zig provides a clang driver; prefer it, fall back to a real clang."""
    for candidate in ("zig", "clang"):
        path = shutil.which(candidate)
        if path:
            return path
    return None


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
        files = [f for f in files if any(f.name.startswith(p) for p in only)]
    return files


def build_lir(src: pathlib.Path, out: pathlib.Path) -> None:
    result = subprocess.run([str(LIR), "build", str(src), "-O2", "-o", str(out)],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"LIR build failed for {src.name}:\n{result.stderr}")


def build_c(src: pathlib.Path, out: pathlib.Path, compiler: str, flags: list[str]) -> None:
    cmd = [compiler]
    if pathlib.Path(compiler).name == "zig":
        cmd.append("cc")
    cmd += flags + ["-I", str(CSRC), str(src), "-o", str(out)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"C build failed for {src.name} with {compiler}:\n{result.stderr}")
    # glibc needs a frame pointer on some builds; nothing to do here, but keep
    # -lm-style linking explicit in the per-workload files instead of flags.


def run_once(binary: pathlib.Path, timeout: float = 900.0) -> tuple[int, str]:
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=timeout)
    return result.returncode, result.stdout


def first_line(out: str) -> str:
    stripped = out.strip()
    return stripped.splitlines()[0] if stripped else ""


def median_ratio(pairs: list[tuple[float, float]]) -> float:
    return statistics.median(a / b for a, b in pairs if b > 0)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--rounds", type=int, default=13,
                        help="interleaved rounds per workload (default 13)")
    parser.add_argument("--only", nargs="+", default=None)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()

    if not LIR.exists():
        print(f"missing {LIR}; run `zig build -Doptimize=ReleaseFast` first", file=sys.stderr)
        return 2

    compiler = zig_cc()
    have_clang = compiler is not None
    have_gcc = shutil.which("gcc") is not None
    if not have_clang and not have_gcc:
        print("no C compiler available (need zig or clang, ideally gcc too)", file=sys.stderr)
        return 2

    expected = load_expected()
    files = workloads(args.only)
    failures: list[str] = []
    rows: list[tuple[str, str, float, float | None, float | None]] = []

    with tempfile.TemporaryDirectory(prefix="lir-c-compare-") as temp:
        tempdir = pathlib.Path(temp)
        for src in files:
            name = src.name
            want = expected[name]

            lir_bin = tempdir / (src.stem + "-lir")
            build_lir(src, lir_bin)
            rc, out = run_once(lir_bin)
            got = first_line(out)
            if rc != 0 or got != want:
                failures.append(f"{name}: LIR printed {got!r} (rc={rc}), expected {want!r}")
                continue

            clang_bin = gcc_bin = None
            if have_clang:
                clang_bin = tempdir / (src.stem + "-llvm")
                build_c(CSRC / (src.stem + ".c"), clang_bin, compiler,
                        ["-O3", "-march=native"])
                rc, out = run_once(clang_bin)
                got = first_line(out)
                if rc != 0 or got != want:
                    failures.append(
                        f"{name}: LLVM C twin printed {got!r} (rc={rc}), expected {want!r}")
                    continue

            if have_gcc:
                gcc_bin = tempdir / (src.stem + "-gcc")
                build_c(CSRC / (src.stem + ".c"), gcc_bin, "gcc", ["-O2"])
                rc, out = run_once(gcc_bin)
                got = first_line(out)
                if rc != 0 or got != want:
                    failures.append(
                        f"{name}: gcc C twin printed {got!r} (rc={rc}), expected {want!r}")
                    continue

            if args.verify_only:
                rows.append((name, want, 0.0, None, None))
                continue

            # Interleaved, symmetric ordering: any drift in machine load lands on
            # all three sides equally.
            lir_times: list[float] = []
            clang_times: list[float] = []
            gcc_times: list[float] = []
            order = [("lir", lir_bin), ("clang", clang_bin), ("gcc", gcc_bin)]
            for _ in range(args.rounds):
                for label, binary in order:
                    if binary is None:
                        continue
                    start = time.perf_counter()
                    run_once(binary)
                    elapsed = time.perf_counter() - start
                    {"lir": lir_times, "clang": clang_times, "gcc": gcc_times}[label].append(elapsed)
                for label, binary in reversed(order):
                    if binary is None:
                        continue
                    start = time.perf_counter()
                    run_once(binary)
                    elapsed = time.perf_counter() - start
                    {"lir": lir_times, "clang": clang_times, "gcc": gcc_times}[label].append(elapsed)

            rows.append((
                name,
                want,
                statistics.median(lir_times),
                statistics.median(clang_times) if clang_times else None,
                statistics.median(gcc_times) if gcc_times else None,
            ))

    print()
    if args.verify_only:
        for name, want, *_ in rows:
            print(f"{name:26s} {want:>18s}  verified")
        print(f"\n{len(rows)}/{len(files)} workload(s) verified against expected.txt")
    else:
        print(f"{'workload':22s} {'output':>12s} {'LIR ms':>9s} {'LLVM C':>9s} "
              f"{'gcc ms':>9s} {'LIR/LLVM':>9s} {'LIR/gcc':>8s}")
        print("-" * 84)
        r_clang: list[float] = []
        r_gcc: list[float] = []
        for name, want, lir_ms, clang_ms, gcc_ms in rows:
            name_s = name.replace(".lir", "")
            c1 = c2 = ""
            if clang_ms:
                ratio = lir_ms / clang_ms
                r_clang.append(ratio)
                c1 = f"{ratio:9.2f}"
            if gcc_ms:
                ratio = lir_ms / gcc_ms
                r_gcc.append(ratio)
                c2 = f"{ratio:8.2f}"
            print(f"{name_s:22s} {want:>12s} {lir_ms*1e3:9.2f} "
                  f"{(clang_ms or 0)*1e3:9.2f} {(gcc_ms or 0)*1e3:9.2f} {c1:>9s} {c2:>8s}")
        print("-" * 84)
        if r_clang:
            g = statistics.geometric_mean(r_clang)
            faster = sum(1 for r in r_clang if r < 1.0)
            print(f"geomean LIR/LLVM-C = {g:.3f}  (LIR faster on {faster}/{len(r_clang)})")
        if r_gcc:
            g = statistics.geometric_mean(r_gcc)
            faster = sum(1 for r in r_gcc if r < 1.0)
            print(f"geomean LIR/gcc    = {g:.3f}  (LIR faster on {faster}/{len(r_gcc)})")
        print("\nLower LIR/C is better for LIR. The C columns are hand-written twins "
              "of the Rust sources,\nnot Rust itself; see the README for why that "
              "substitution was necessary.")

    if failures:
        print("\nFAILURES:")
        for failure in failures:
            print("  " + failure)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
