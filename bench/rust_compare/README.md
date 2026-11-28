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
| 01_matrix_mul | 1.09 | 1.56 | 1.61 | 0.70 | 0.68 |
| 02_nbody | 16.62 | 13.76 | 14.82 | 1.21 | 1.12 |
| 03_sieve | 23.45 | 18.39 | 20.05 | 1.28 | 1.17 |
| 04_mandelbrot | 57.07 | 49.73 | 46.34 | 1.15 | 1.23 |
| 05_collatz | 125.94 | 136.25 | 203.11 | 0.92 | 0.62 |
| 06_fib_mod | 24.45 | 25.09 | 25.13 | 0.97 | 0.97 |
| 07_prime_count | 146.41 | 145.08 | 234.32 | 1.01 | 0.62 |
| 08_bitmix | 28.91 | 24.44 | 46.62 | 1.18 | 0.62 |
| 09_tak | 2.60 | 3.28 | 3.16 | 0.79 | 0.82 |
| 10_isqrt | 85.21 | 66.79 | 84.14 | 1.28 | 1.01 |
| 11_kmeans | 9.37 | 6.42 | 12.13 | 1.46 | 0.77 |
| **geomean** | | | | **1.063** | **0.848** |

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
addressed without a reload. `11_kmeans` still pays a bounds check per point
assignment that the C twins do not pay at all; that one is the price of memory
safety and is not coming down without a range proof for a data-dependent index.

`11_kmeans` is worth spelling out, because the last two turns guessed wrong
about it and the measurement that settled it is cheap to repeat.

The guess was that its centroid loop was the problem: twelve instructions per
centroid against clang's ten, with a `best_d` -> `cmp` -> `cmovl` -> `best_d`
two-cycle recurrence, so unrolling the eight centroids was the fix to reach
for. Disassembling the clang twin killed that twice over. It contains five
vector instructions in total, all of them zeroing the centroid, sum and count
buffers, so there is no SIMD to imitate; and its centroid reduction is *not* a
tree - it is the same serial `cmp`/`cmovge` chain LIR emits, one link per
centroid. Unrolling would not have bought much either: the trip count is eight,
so an unrolled body needs its `iv <= limit - factor` guard re-evaluated once per
point, and counting the guard, the per-repetition index `lea`s and the
write-backs, the unrolled form comes out within a few instructions of the loop.

What the centroid loop was hiding is the block after it. Assigning one point
runs `sum[best] += v` and `cnt[best] += 1`, and each of those lowered to two
independent heap accesses with two `@ptr_add`s, two probe `lea`s and two full
bounds checks - twenty-six instructions where clang emits two, because
`best` is a runtime index that access-span hoisting cannot prove a range for.
The second check of each pair tests the same pointer against the same
single-entry chunk cache a few instructions after the first one did, with
nothing in between that can move that cache, so it is a tautology at runtime.
`dedupAccessChecks` now marks it `unchecked_access`, which drops the probe `lea`
and the four check instructions and lets the access fold back into its SIB
operand. Ten instructions per point, 21% off the wall clock (11.53 -> 9.41 ms),
ratio 1.83 -> 1.50 - and the first check still traps, which the out-of-chunk
regression test pins at all three optimisation levels.

The general lesson is the one worth keeping: the backend is now close enough to
the twins that per-loop instruction counts no longer point at the gap. Find it
by disassembling both sides and counting instructions per *iteration of the
outermost hot loop*, not per inner-loop body.

Separately, `unrollCountedLoops` was instrumented this turn and never fires -
not on the eleven workloads, not on any of the 226 `.lir` files in the
repository. The rejection reasons, counted over the eleven
workloads plus a synthetic counted-loop probe, say what enabling it would
actually cost. 24 candidate loops fail the purity test because the body
contains a call - and the same 24 report `iv_defs = 0`, meaning the induction
variable is not updated inside the header block at all, so those are multi-block
loops the pass's single-block shape cannot describe even with calls admitted.
12 fail because the block's exit test is not a plain `cmp_lt`/`cmp_le` feeding
the back-edge branch. 4 are longer than the pass's 14-instruction limit. And 2
reach the induction-variable check and fail it because out-of-SSA code hands
over `t = add iv, 1; iv = copy t` where the pass only recognises an in-place
`iv = add iv, 1`. Its unroll guard is fine, incidentally: it reuses the loop's
own comparison op against `limit - (factor - 1)`, which is the correct bound
for both `cmp_lt` and `cmp_le`. Reviving it would mean handling multi-block
bodies and the post-SSA induction-variable form, a much larger change than the
counts suggest - and after the measurement above, no longer the obvious next
step for kmeans.

`08_bitmix` came down from 1.39 to 1.18 without touching its arithmetic. Its
loop body updates three variables, and `destructSSA` emits out-of-SSA updates as
three definitions followed by three grouped copies:

    [9]  v13 = add v51, v12       [13] v51 = copy v13
    [11] v17 = add v52, v16       [14] v52 = copy v17
    [12] v20 = add v53, v19       [15] v53 = copy v20

`coalesceCopiesPostSSA` will not touch these - `def_cnt[v51] != 1`, and relaxing
that check once already broke `a = b; b = t` swaps - so the register allocator
handles them instead, by giving the temporary the operand's register and letting
the copy emit nothing. That aliasing existed but only matched when the copy was
the *immediately next* instruction, which grouped copies never are. Widening the
match to a copy later in the same block turns each pair into one in-place `add`
and took five instructions out of a twenty-seven-instruction loop; the same
shape appears in nine of the eleven workloads, worth 2 to 15 instructions each.

The gap is what makes it interesting. Sharing a register across a distance is
only sound if nothing in between reads the operand, and one thing reads it
without saying so in the IR: a `@read_u64` whose address `planAddrFolds` folded
into a SIB operand reads its base and index *at the access*, not at the
`@ptr_add` that built it. `02_nbody`'s accumulation loop has exactly that in the
gap, and aliasing through it made the loop counter advance before the load used
it as an index - reading one element further each iteration, past the end of a
buffer whose checks span hoisting had already removed, and printing a different
wrong number on every run. `instReadsVregFolded` is the read-side twin of the
exception the live-range builder already carries for the same fold, and the
regression test for it records the three garbage values the unguarded build
produced.

Two caveats worth repeating before anyone reads a single row too closely. The
workloads are ~1-150 ms and the harness interleaves rounds, so a row whose
kernel is under a millisecond (`01`, `09`) carries several percent of process
startup and code-layout noise: `01_matrix_mul` measures up to 6% either way
between builds whose hot loop is byte-identical. Absolute milliseconds also
drift between runs of this whole table - the run above measured `03_sieve` at
23.45 ms and the run before it at 20.03 ms, with the clang twin moving from
15.06 to 18.39 ms alongside it, so neither LIR nor the twin got slower. Only
the ratio column is comparable across runs, because both sides of a ratio are
timed in the same run on the same loaded 2-core VM. And the C columns are
hand-written twins of the Rust sources, not Rust; see the top of this file for
why that substitution was necessary.

`08_bitmix` used to disagree with its twin by 7.4e12. The benchmark was wrong,
not the compiler: the LIR source shifted a signed value (arithmetic `>>`) while
the Rust twin cast to `u64` first (logical `>>`), so the two were computing
different functions. The LIR side now bridges through `u64` explicitly and all
three implementations print `1335377554`.
