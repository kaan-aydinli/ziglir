#!/usr/bin/env python3
"""SEL benchmark suite — tüm ölçümleri yeniden üretir.

Kullanım:
    python3 ai/bench/run.py            # tabloyu bas
    python3 ai/bench/run.py --write    # results.md'yi yeniden yaz

Her sayı bu betik tarafından ÖLÇÜLÜR; hiçbiri elle yazılmaz.
Benchmark'lar gerçek iş yapar: boş döngü yok, sonuç yazdırılır ki
derleyici işi eleyemesin.
"""
import os
import statistics
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIR = os.path.join(ROOT, "zig-out", "bin", "lir")

CASES = [
    # (ad, dosya, tur, aciklama)
    ("fixed ops", "ai/bench/b_fixed_ops.lir", 5,
     "mul + div + sat_add, 1M yineleme"),
    ("forward", "ai/bench/b_forward.lir", 5,
     "24 kenarlık SEL ileri geçişi, 100k çağrı"),
    ("forward+learn", "ai/bench/b_learn.lir", 5,
     "24 kenarlık ileri + eikonal güncelleme, 100k"),
    ("xor train", "ai/tests/03_xor.lir", 5,
     "XOR, 3000 epoch x 4 desen = 12000 güncelleme"),
    ("3-layer net", "ai/bench/b_net3.lir", 5,
     "128 nöron x 3 katman, K=8, 2000 adım"),
    ("search", "ai/bench/b_search.lir", 5,
     "1M gönderilik ters indeks, 1 sorgu"),
    ("matmul 96", "ai/bench/b_matmul.lir", 5,
     "96x96 Q32.32 matris çarpımı"),
]


def build(src, out):
    r = subprocess.run([LIR, "build", src, "-O2", "-o", out],
                       capture_output=True, text=True)
    return r.returncode == 0, r.stderr


def timeit(exe, rounds):
    ts = []
    for _ in range(rounds):
        t = time.perf_counter()
        subprocess.run([exe], capture_output=True)
        ts.append(time.perf_counter() - t)
    return statistics.median(ts)


def main():
    if not os.path.exists(LIR):
        print(f"hata: {LIR} yok — once `zig build -Doptimize=ReleaseFast`", file=sys.stderr)
        return 1

    tmp = "/tmp/sel_bench"
    os.makedirs(tmp, exist_ok=True)
    rows = []
    for name, src, rounds, desc in CASES:
        path = os.path.join(ROOT, src)
        if not os.path.exists(path):
            rows.append((name, desc, None))
            continue
        exe = os.path.join(tmp, name.replace(" ", "_").replace("+", "p"))
        ok, err = build(path, exe)
        if not ok:
            print(f"[derleme hatasi] {name}: {err[:200]}", file=sys.stderr)
            rows.append((name, desc, None))
            continue
        ms = timeit(exe, rounds) * 1e3
        rows.append((name, desc, ms))

    print(f"{'is':<16} {'sure (ms)':>12}  aciklama")
    print("-" * 78)
    for name, desc, ms in rows:
        val = f"{ms:12.2f}" if ms is not None else f"{'HATA':>12}"
        print(f"{name:<16} {val}  {desc}")

    if "--write" in sys.argv:
        write_md(rows)
    return 0


def write_md(rows):
    path = os.path.join(ROOT, "ai", "bench", "results.md")
    stamp = time.strftime("%Y-%m-%d %H:%M")
    lines = [
        "# SEL — ölçüm sonuçları",
        "",
        f"Üretim: `python3 ai/bench/run.py --write` · {stamp}",
        "",
        "| iş | süre (ms) | açıklama |",
        "|---|---:|---|",
    ]
    for name, desc, ms in rows:
        v = f"{ms:.2f}" if ms is not None else "HATA"
        lines.append(f"| {name} | {v} | {desc} |")
    lines.append("")
    with open(path, "w") as f:
        f.write("\n".join(lines))
    print(f"\nyazildi: {path}")


if __name__ == "__main__":
    sys.exit(main())
