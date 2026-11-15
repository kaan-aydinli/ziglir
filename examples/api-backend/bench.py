#!/usr/bin/env python3
"""
LIR vs Zig API Backend Benchmark & Comparison Suite
Evaluates:
  1. Compile Speed (build time)
  2. Binary Size (bytes)
  3. Memory Footprint (RSS in KB)
  4. Latency & Throughput (p50, p90, p99, RPS) across endpoints
"""

import time
import socket
import os
import subprocess
import statistics
import json

ENDPOINTS = [
    ("GET /api/v1/health", b"GET /api/v1/health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"),
    ("GET /api/v1/users", b"GET /api/v1/users HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"),
    ("POST /api/v1/users (Auth)", b"POST /api/v1/users HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer lir-secret-token-2026\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"),
]

def benchmark_endpoint(port, payload, count=500):
    latencies = []
    success = 0
    start_total = time.perf_counter()
    for _ in range(count):
        t0 = time.perf_counter()
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.connect(("127.0.0.1", port))
            s.sendall(payload)
            resp = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                resp += chunk
            s.close()
            t1 = time.perf_counter()
            if b"200 OK" in resp or b"201 Created" in resp:
                success += 1
            latencies.append((t1 - t0) * 1000.0) # ms
        except Exception as e:
            pass
    total_time = time.perf_counter() - start_total
    rps = success / total_time if total_time > 0 else 0
    latencies.sort()
    p50 = statistics.median(latencies) if latencies else 0
    p90 = latencies[int(len(latencies) * 0.90)] if latencies else 0
    p99 = latencies[int(len(latencies) * 0.99)] if latencies else 0
    mean_lat = statistics.mean(latencies) if latencies else 0

    return {
        "count": count,
        "success": success,
        "total_time_s": round(total_time, 4),
        "rps": round(rps, 1),
        "mean_ms": round(mean_lat, 3),
        "p50_ms": round(p50, 3),
        "p90_ms": round(p90, 3),
        "p99_ms": round(p99, 3),
    }

def measure_rss(binary_name):
    try:
        out = subprocess.check_output(["pgrep", "-f", binary_name]).decode().strip().split()
        if not out:
            return 0
        pid = out[0]
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("VmRSS:"):
                    parts = line.split()
                    return int(parts[1]) # KB
    except Exception:
        return 0

def measure_compile_time(cmd, rounds=3):
    durations = []
    for _ in range(rounds):
        t0 = time.perf_counter()
        subprocess.check_call(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        durations.append((time.perf_counter() - t0) * 1000.0)
    return round(statistics.mean(durations), 1)

def run():
    print("=" * 70)
    print("   LIR vs ZIG API BACKEND COMPREHENSIVE BENCHMARK")
    print("=" * 70)

    # 1. Compile time
    print("\n[1/4] Derleme Süresi (Compile Time) Ölçülüyor (3 tur ortalaması)...")
    lir_compile_ms = measure_compile_time("./bin/lir build examples/api-backend/lir/main.lir -O2 -o bin/api_lir")
    print(f"  -> LIR  derleme süresi: {lir_compile_ms} ms")
    zig_compile_ms = measure_compile_time("zig build-exe -OReleaseFast examples/api-backend/zig/main.zig -femit-bin=bin/api_zig")
    print(f"  -> ZIG  derleme süresi: {zig_compile_ms} ms")

    # 2. Binary size
    lir_bin_size = os.path.getsize("bin/api_lir")
    zig_bin_size = os.path.getsize("bin/api_zig")
    print("\n[2/4] İkili Dosya Boyutu (Binary Size):")
    print(f"  -> LIR  Binary: {lir_bin_size:,} bayt ({lir_bin_size / 1024:.1f} KB)")
    print(f"  -> ZIG  Binary: {zig_bin_size:,} bayt ({zig_bin_size / 1024:.1f} KB)")

    # 3. Memory RSS
    lir_rss = measure_rss("bin/api_lir")
    zig_rss = measure_rss("bin/api_zig")
    print("\n[3/4] Bellek Tüketimi (Memory RSS):")
    print(f"  -> LIR  RSS: {lir_rss} KB")
    print(f"  -> ZIG  RSS: {zig_rss} KB")

    # 4. HTTP Benchmark
    print("\n[4/4] HTTP İstek Başarımı & Gecikme (RPS & Latency):")
    results = {
        "compile_ms": {"lir": lir_compile_ms, "zig": zig_compile_ms},
        "binary_bytes": {"lir": lir_bin_size, "zig": zig_bin_size},
        "rss_kb": {"lir": lir_rss, "zig": zig_rss},
        "endpoints": {}
    }

    for name, req_bytes in ENDPOINTS:
        print(f"\n  Testing Endpoint: {name}")
        lir_res = benchmark_endpoint(8081, req_bytes, count=1000)
        zig_res = benchmark_endpoint(8082, req_bytes, count=1000)
        print(f"    LIR -> RPS: {lir_res['rps']:>7} req/s | p50: {lir_res['p50_ms']} ms | p99: {lir_res['p99_ms']} ms")
        print(f"    ZIG -> RPS: {zig_res['rps']:>7} req/s | p50: {zig_res['p50_ms']} ms | p99: {zig_res['p99_ms']} ms")
        results["endpoints"][name] = {"lir": lir_res, "zig": zig_res}

    with open("examples/api-backend/bench_results.json", "w") as f:
        json.dump(results, f, indent=2)

    print("\n" + "=" * 70)
    print("Benchmark tamamlandı! Sonuçlar examples/api-backend/bench_results.json dosyasına yazıldı.")
    print("=" * 70)

if __name__ == "__main__":
    run()
