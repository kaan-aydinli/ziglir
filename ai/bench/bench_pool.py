#!/usr/bin/env python3
"""Havuz benchmark'ı: seri forward vs kalıcı işçi havuzu.

Ölçüm yöntemi: her ikili için ayrı süreç, medyan. Tek koşu A/B gürültülü
olduğu için 7 tur alınıyor ve medyan raporlanıyor.

Kullanım: python3 ai/bench/bench_pool.py
"""
import os
import statistics
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIR = os.path.join(ROOT, "zig-out", "bin", "lir")
TMP = "/tmp"


def build(src, out):
    r = subprocess.run([LIR, "build", src, "-O2", "-o", out],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(f"derleme hatasi {src}: {r.stderr[:400]}")
        sys.exit(1)


def median_ms(exe, rounds=7):
    ts = []
    for _ in range(rounds):
        t0 = time.perf_counter()
        subprocess.run([exe], capture_output=True, timeout=600)
        ts.append(time.perf_counter() - t0)
    return statistics.median(ts) * 1e3


def main():
    if not os.path.exists(LIR):
        print(f"hata: {LIR} yok — once `zig build -Doptimize=ReleaseFast`")
        return 1

    serial = os.path.join(TMP, "b_pool_serial")
    pooled = os.path.join(TMP, "b_pool_parallel")
    build(os.path.join(ROOT, "ai", "bench", "_pool_serial.lir"), serial)
    build(os.path.join(ROOT, "ai", "bench", "b_pool.lir"), pooled)

    r = subprocess.run([pooled], capture_output=True, text=True, timeout=600)
    eq = r.stdout.split()[:1]
    ok = eq and eq[0] == "1"

    s = median_ms(serial)
    p = median_ms(pooled)

    print(f"  seri  (1 cekirdek, 6000 adim): {s:8.1f} ms")
    print(f"  havuz (2 cekirdek, 6000 adim): {p:8.1f} ms")
    print(f"  oran                          : {s / p:8.2f}x")
    print(f"  cikti esitligi                : {'EVET' if ok else 'HAYIR'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
