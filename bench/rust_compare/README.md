# LIR vs optimized Rust: heavy integer math workloads

Eleven programs, each written **twice**: once in LIR (`NN_name.lir`) and once in
Rust (`rust/NN_name.rs`). Every pair computes exactly the same thing and prints
exactly the same number, so a timing difference is a code-generation difference
and not a difference in what the program does.

## Running

```
# LIR side
./zig-out/bin/lir build 01_matrix_mul.lir -O2 -o /tmp/m01 && /tmp/m01

# Rust side (needs rustc; see "Toolchain" below)
rustc -O -C target-cpu=native rust/01_matrix_mul.rs -o /tmp/r01 && /tmp/r01
```

`run_all.py` does both sides for all eleven programs and prints a table.

## Running without a Rust toolchain

If `rustc` cannot be installed, `c/NN_name.c` holds a hand-written C twin of each
Rust source (same constants, same order of operations, same printed value) and
`run_c.py` times three binaries per workload:

```
python3 run_c.py                 # LIR -O2 vs zig cc -O3 -march=native vs gcc -O2
python3 run_c.py --verify-only   # check outputs only, no timing
```

It verifies every side against `expected.txt` before timing, samples the three
binaries interleaved and in both orders, and reports the median of the per-round
ratios. The `zig cc` column is labelled **LLVM C twin**, not Rust: rustc emits
LLVM IR and uses the same optimiser and x86-64 backend, so it is the closest
available proxy, but it is not the Rust compiler.

## The workloads

| # | file | kernel | what it stresses |
|---|------|--------|------------------|
| 01 | `01_matrix_mul` | 60x60 integer matmul, i-k-j order, 3 reps | memory traffic, inner-loop addressing |
| 02 | `02_nbody` | 500 bodies x 200 steps, integer pairwise forces | nested loops with two divisions in the body |
| 03 | `03_sieve` | sieve to 2,000,000 x 5 passes | byte stores with stride, tight counting loop |
| 04 | `04_mandelbrot` | 800x800 16.16 fixed-point escape time | dependent multiply chain, data-dependent exit |
| 05 | `05_collatz` | total stopping time below 2,000,000 | unpredictable branches, divide-by-two |
| 06 | `06_fib_mod` | Fibonacci mod 2^31-1, 30,000,000 iterations | the tightest possible loop body |
| 07 | `07_prime_count` | pi(2,000,000) by trial division | division, early exits |
| 08 | `08_bitmix` | splitmix64 over 20,000,000 values + popcount | multiplies, shifts, popcount |
| 09 | `09_tak` | tak(24,16,8) | call overhead, deep recursion |
| 10 | `10_isqrt` | isqrt over 5,000,000 values + icbrt | division with input-dependent trip count |
| 11 | `11_kmeans` | 1-D k-means, 200,000 points, k=8, 30 iterations | pointer loads/stores, nearest-centroid search |

All arithmetic is 64-bit integer. Moduli are kept below 2^31 wherever a product
is reduced, so a single 64-bit multiply followed by `%` is exact and cannot wrap;
the two places that do need full 64-bit wrap use `@wrapping_mul` (LIR) and
`wrapping_mul` (Rust) on both sides.

## Expected outputs

`expected.txt` holds the value each program must print. Both sides are checked
against it before any timing is reported.

## Toolchain

The LIR side needs only `zig build -Doptimize=ReleaseFast` to produce
`zig-out/bin/lir`. The Rust side needs `rustc`; if it is not installed,
`run_all.py --lir-only` still runs and checks all eleven LIR programs.

## Measured results

Median of 13 interleaved rounds, 2-core Xeon @ 2.60 GHz shared VM, LIR at its
highest level (`-O2`):

| workload | LIR ms | LLVM C ms | gcc ms | LIR/LLVM | LIR/gcc |
|---|---:|---:|---:|---:|---:|
| 01_matrix_mul | 11.37 | 2.12 | 2.13 | 5.36 | 5.34 |
| 02_nbody | 112.43 | 14.44 | 18.04 | 7.79 | 6.23 |
| 03_sieve | 71.83 | 30.32 | 28.56 | 2.37 | 2.52 |
| 04_mandelbrot | 178.28 | 52.24 | 54.38 | 3.41 | 3.28 |
| 05_collatz | 516.85 | 137.26 | 276.50 | 3.77 | 1.87 |
| 06_fib_mod | 70.54 | 30.14 | 32.81 | 2.34 | 2.15 |
| 07_prime_count | 181.77 | 174.16 | 277.59 | 1.04 | 0.65 |
| 08_bitmix | 100.04 | 42.18 | 82.35 | 2.37 | 1.21 |
| 09_tak | 5.10 | 5.41 | 5.41 | 0.94 | 0.94 |
| 10_isqrt | 125.28 | 98.90 | 105.53 | 1.27 | 1.19 |
| 11_kmeans | 75.88 | 9.70 | 15.27 | 7.82 | 4.97 |
| **geomean** | | | | **2.75** | **2.16** |

LIR is at parity where the work is dominated by division or unpredictable
branches (`07`, `09`, `10`) and loses badly where the backend is weakest:
inner-loop addressing (`01`, `11`), call-heavy loops (`02`), dependent multiply
chains (`04`).

`08_bitmix` used to disagree with its twin by 7.4e12. The benchmark was wrong,
not the compiler: the LIR source shifted a signed value (arithmetic `>>`) while
the Rust twin cast to `u64` first (logical `>>`), so the two were computing
different functions. The LIR side now bridges through `u64` explicitly and all
three implementations print `1335377554`.
