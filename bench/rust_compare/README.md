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
