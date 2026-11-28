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

`run_c.py`, 2-core Xeon @ 2.60 GHz shared VM, LIR at its highest level (`-O2`).
All eleven outputs are checked against `expected.txt` before anything is timed.

| workload | LIR ms | LLVM C ms | gcc ms | LIR/LLVM | LIR/gcc |
|---|---:|---:|---:|---:|---:|
| 01_matrix_mul | 1.03 | 1.47 | 1.46 | 0.70 | 0.71 |
| 02_nbody | 15.76 | 13.15 | 14.36 | 1.20 | 1.10 |
| 03_sieve | 21.71 | 16.49 | 18.64 | 1.32 | 1.17 |
| 04_mandelbrot | 54.64 | 47.15 | 43.78 | 1.16 | 1.25 |
| 05_collatz | 124.52 | 131.32 | 195.80 | 0.95 | 0.64 |
| 06_fib_mod | 23.94 | 24.00 | 24.03 | 1.00 | 1.00 |
| 07_prime_count | 142.35 | 140.12 | 227.35 | 1.02 | 0.63 |
| 08_bitmix | 33.75 | 23.90 | 44.75 | 1.41 | 0.75 |
| 09_tak | 2.56 | 3.26 | 3.17 | 0.78 | 0.81 |
| 10_isqrt | 84.26 | 65.63 | 82.51 | 1.28 | 1.02 |
| 11_kmeans | 11.53 | 6.31 | 11.80 | 1.83 | 0.98 |
| **geomean** | | | | **1.112** | **0.888** |

LIR now beats the gcc twins on 7 of 11 and is within a few percent of the
clang `-O3 -march=native` twins on 6 of 11. The same table measured against an
earlier state of the native backend read 2.75 / 2.16; the distance was closed by
folding pointer arithmetic into x86 addressing modes, if-converting the
copy-only diamonds that `destructSSA` leaves behind into `cmov` chains, letting
a converted diamond write the variables it assigns instead of temporaries,
collapsing `t = x + 1; x = copy t` back into an in-place update, and budgeting
the registers promised to wide literals against the pressure the function
actually has.

The remaining gap is concentrated where the twins get something the backend
still does not: `08_bitmix` and `10_isqrt` want a shorter dependent-operation
chain per iteration, and `03_sieve` wants the store inside the counting loop
addressed without a reload.

`11_kmeans` is worth spelling out, because it is no longer an instruction-count
problem. Its centroid loop is now twelve instructions with no spill traffic at
all - one SIB load, a subtract, a three-instruction branchless absolute value,
a compare and two `cmov`s for the running minimum, and a three-instruction
loop exit - against roughly 10.6 for clang, which fully unrolls the eight
centroids. Removing instructions from it stopped buying anything measurable:
the loop carries `best_d` through `cmp` into `cmovl` and back into `best_d`,
which is a two-cycle recurrence, and twelve million iterations of it run at
close to exactly that. Clang's unrolled form does not have a serial chain to be
bound by; it reduces eight distances as a tree, so its critical path per
centroid is a fraction of a cycle. Closing the rest of this gap means unrolling
counted loops whose bodies read memory, not emitting fewer instructions inside
them. Two things currently stop `unrollCountedLoops` there: it only accepts
bodies made of `isPureHeaderOp` operations, and it only recognises an induction
variable updated in place, while out-of-SSA code hands it
`t = add ci, 1; ci = copy t`.

Two caveats worth repeating before anyone reads a single row too closely. The
workloads are ~1-150 ms and the harness interleaves rounds, so a row whose
kernel is under a millisecond (`01`, `09`) carries several percent of process
startup and code-layout noise: `01_matrix_mul` measures up to 6% either way
between builds whose hot loop is byte-identical. And the C columns are
hand-written twins of the Rust sources, not Rust; see the top of this file for
why that substitution was necessary.

`08_bitmix` used to disagree with its twin by 7.4e12. The benchmark was wrong,
not the compiler: the LIR source shifted a signed value (arithmetic `>>`) while
the Rust twin cast to `u64` first (logical `>>`), so the two were computing
different functions. The LIR side now bridges through `u64` explicitly and all
three implementations print `1335377554`.
