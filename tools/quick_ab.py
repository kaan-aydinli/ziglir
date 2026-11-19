#!/usr/bin/env python3
"""Quick A/B harness: median wall time of one workload at several opt levels."""
import statistics
import subprocess
import sys
import time

lir = sys.argv[1]
src = sys.argv[2]
rounds = int(sys.argv[3]) if len(sys.argv) > 3 else 7
levels = sys.argv[4].split(",") if len(sys.argv) > 4 else ["-O0", "-O2"]

bins = {}
for lv in levels:
    out = f"/tmp/ab_{abs(hash(src+lv))%100000}"
    subprocess.run([lir, "build", src, lv, "-o", out], capture_output=True, check=True)
    bins[lv] = out

times = {lv: [] for lv in levels}
for _ in range(rounds):
    for lv in levels:
        t = time.perf_counter()
        subprocess.run([bins[lv]], capture_output=True)
        times[lv].append(time.perf_counter() - t)
    for lv in reversed(levels):
        t = time.perf_counter()
        subprocess.run([bins[lv]], capture_output=True)
        times[lv].append(time.perf_counter() - t)

base = None
for lv in levels:
    med = statistics.median(times[lv]) * 1e3
    if base is None:
        base = med
    print(f"{lv:4s} {med:9.2f} ms  ratio {med/base:6.3f}")
