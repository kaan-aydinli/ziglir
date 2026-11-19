#!/usr/bin/env python3
"""SEL test çalıştırıcısı — beş test, üç backend.

Kullanım: python3 ai/run_tests.py
Çıkış kodu 0 ise hepsi geçti.
"""
import glob
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIR = os.path.join(ROOT, "zig-out", "bin", "lir")
BACKENDS = ["native", "vm", "c"]


def main():
    if not os.path.exists(LIR):
        print(f"hata: {LIR} yok — once `zig build -Doptimize=ReleaseFast`")
        return 1
    tests = sorted(glob.glob(os.path.join(ROOT, "ai", "tests", "*.lir")))
    if not tests:
        print("hata: ai/tests/*.lir bulunamadi")
        return 1

    passed = failed = 0
    for t in tests:
        name = os.path.basename(t)[:-4]
        exp_path = t[:-4] + ".expected"
        if not os.path.exists(exp_path):
            print(f"  ATLA {name} (beklenen dosya yok)")
            continue
        with open(exp_path) as f:
            expected = [l for l in f.read().splitlines() if l.strip()]
        for b in BACKENDS:
            r = subprocess.run([LIR, "run", t, "--backend=" + b],
                               capture_output=True, text=True)
            got = [l for l in r.stdout.splitlines() if l.strip()]
            ok = got == expected
            if ok:
                passed += 1
                print(f"  ok   {name:<16} {b}")
            else:
                failed += 1
                print(f"  FAIL {name:<16} {b}")
                print(f"       beklenen: {expected}")
                print(f"       alinan  : {got}")
                if r.stderr.strip():
                    print(f"       stderr: {r.stderr[:300]}")
    print(f"\ngecen: {passed}  basarisiz: {failed}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
