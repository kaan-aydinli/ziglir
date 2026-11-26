#!/usr/bin/env python3
"""Differential execution tests with independent expected outputs (Linux x86-64).

Requires a host C compiler for --backend=c and Node 22+ or Wasmtime for Wasm. Uses no third-party Python packages.
Every subprocess has a timeout; all generated artifacts live in temporary dirs.
"""
import pathlib
import subprocess
import sys
import tempfile
import unittest

COMPILER = pathlib.Path(sys.argv.pop(1) if len(sys.argv) > 1 else "zig-out/bin/lir").resolve()
BACKENDS = ("native", "vm", "c", "wasm")
LEVELS = ("-O0", "-O1", "-O2")
CASES = (
    ("recursion", '''
fn fib(n: i64) -> i64 {
    if n <= 1 { return n }
    return fib(n - 1) + fib(n - 2)
}
fn main() -> i64 { printInt(fib(10)) return 7 }
''', "55\n", 7),
    ("signed_arithmetic", '''
fn calc(a: i64, b: i64) -> i64 {
    printInt(a / b)
    printInt(a % b)
    printInt(a >> 2)
    printInt((b << 3) | 1)
    return 0
}
fn main() -> i64 { return calc(-37, 5) }
''', "-7\n-2\n-10\n41\n", 0),
    ("loop_and_branch", '''
fn sum(n: i64) -> i64 {
    let mut i = 0
    let mut total = 0
    while i < n {
        if i % 2 == 0 { total = total + i } else { total = total - 1 }
        i = i + 1
    }
    return total
}
fn main() -> i64 { printInt(sum(10)) return 0 }
''', "15\n", 0),
    ("strings_and_arrays", '''
fn main() -> i64 {
    let values = [4, 8, 15, 16]
    printInt(values[0] + values[3])
    let a = "hello"
    let b = " world"
    println(a + b)
    return 0
}
''', "20\nhello world\n", 0),
)


# Keep executable examples under the same cross-backend regression gates.
EXAMPLES = pathlib.Path(__file__).resolve().parents[1] / "examples"
CASES += (
    ("integer_intrinsics", (EXAMPLES / "integer-intrinsics.lir").read_text(),
     "-9223372036854775808\n-9223372036854775808\n123\n2\n"
     "-9223372036854775808\n12345\n-1\n0\n1\n"
     "-9223372036854775808\n9223372036854775807\n-2\npower\nzero\nnegative\nnot power\n", 0),
    ("integer_power", (EXAMPLES / "integer-power.lir").read_text(),
     "512\n-4\n-8\n19\n81\n1\n1\n-9223372036854775808\n0\n-1\n", 0),
    ("loop_control", (EXAMPLES / "loop-control.lir").read_text(),
     "13\nleaving loop\n3\n-7\n12\n1.5", 0),
    ("intrinsic_evaluation_order", '''
fn next(p: *i64) -> i64 { *p = *p + 1 return *p }
fn main() -> i64 {
    let mut n = 0
    printInt(@wrapping_sub(next(&n), next(&n)))
    printInt(n)
    printInt(@rotl(next(&n), next(&n)))
    printInt(n)
    return 0
}
''', "-1\n2\n48\n4\n", 0),
    ("integer_power_assignment", '''
fn main() -> i64 {
    var value = 2
    value **= 3
    printInt(value)
    value **= 2
    printInt(value)
    return 0
}
''', "8\n64\n", 0),
    ("unsigned_float_casts", '''
fn main() -> i64 {
    let zero = (0 as u64) as f64
    let one = (1 as u64) as f64
    let high_bit = ((9223372036854775807 as u64 + 1 as u64) as f64)
    let max_u64 = ((-1) as u64) as f64
    let max_u32 = (4294967295 as u32) as f64
    let f32_round = ((16777217 as u32) as f32) as f64
    let f64_to_u64_high = (9223372036854775808.0 as u64) as f64
    let f64_to_u64_near_max = (18446744073709549568.0 as u64) as f64
    let f64_to_u8 = (255.9 as u8) as i64
    let f64_to_u8_wrap = (256.9 as u8) as i64
    if zero == 0.0 { println("zero-ok") } else { println("zero-bad") }
    if one == 1.0 { println("one-ok") } else { println("one-bad") }
    if high_bit == 9223372036854775808.0 { println("high-ok") } else { println("high-bad") }
    if max_u64 == 18446744073709551616.0 { println("max64-ok") } else { println("max64-bad") }
    if max_u32 == 4294967295.0 { println("max32-ok") } else { println("max32-bad") }
    if f32_round == 16777216.0 { println("f32-round-ok") } else { println("f32-round-bad") }
    if f64_to_u64_high == 9223372036854775808.0 { println("ftou-high-ok") } else { println("ftou-high-bad") }
    if f64_to_u64_near_max == 18446744073709549568.0 { println("ftou-max-ok") } else { println("ftou-max-bad") }
    if f64_to_u8 == 255 and f64_to_u8_wrap == 0 { println("ftou-narrow-ok") } else { println("ftou-narrow-bad") }
    return 0
}
''', "zero-ok\none-ok\nhigh-ok\nmax64-ok\nmax32-ok\nf32-round-ok\nftou-high-ok\nftou-max-ok\nftou-narrow-ok\n", 0),
)


def integer_edge_case():
    """Expected bit patterns come from Python, not a second LIR backend."""
    mask = (1 << 64) - 1
    def signed(value):
        value &= mask
        return value if value < (1 << 63) else value - (1 << 64)
    source = ["fn reverse(x: i64) -> i64 { return @bit_reverse(x) }",
              "fn rotate(x: i64, n: i64) -> i64 { return @rotl(x, n) }",
              "fn main() -> i64 {"]
    expected = []
    values = [0, 1, -1, 123456789, -123456789, (1 << 63) - 1, -(1 << 63)]
    for value in values:
        # Spell MIN_I64 using a valid positive literal followed by subtraction.
        literal = str(value) if value != -(1 << 63) else "(-9223372036854775807 - 1)"
        source.append(f"printInt(reverse({literal}))")
        expected.append(signed(int(f"{value & mask:064b}"[::-1], 2)))
        for count in [-65, -1, 0, 1, 63, 64, 65]:
            n = count & 63
            bits = value & mask
            expected.append(signed((bits << n) | (bits >> ((-n) & 63))))
            source.append(f"printInt(rotate({literal}, {count}))")
    source.append("return 0 }")
    return ("integer_edges", "\n".join(source),
            "".join(f"{value}\n" for value in expected), 0)


def signed_constant_division_case():
    """Verify magic-number division against Python's exact signed arithmetic."""
    divisors = (3, 7, 8, 97, 1009, 1000000007,
                (1 << 62) + 1, (1 << 63) - 1, -7, -1009)
    values = (-(1 << 63), -(1 << 63) + 1, -1234567, -1009, -7, -1,
              0, 1, 7, 1009, 1234567, (1 << 63) - 1)
    helpers = []
    calls = []
    expected = []
    for divisor in divisors:
        ident = f"d{abs(divisor)}_{'neg' if divisor < 0 else 'pos'}"
        helpers.append(f"fn div_{ident}(x: i64) -> i64 {{ return x / ({divisor}) }}")
        helpers.append(f"fn rem_{ident}(x: i64) -> i64 {{ return x % ({divisor}) }}")
        for value in values:
            literal = str(value) if value != -(1 << 63) else "(-9223372036854775807 - 1)"
            calls.append(f"printInt(div_{ident}({literal}))")
            calls.append(f"printInt(rem_{ident}({literal}))")
            quotient = abs(value) // abs(divisor)
            if (value < 0) != (divisor < 0):
                quotient = -quotient
            remainder = value - quotient * divisor
            expected.extend((quotient, remainder))
    source = helpers + ["fn main() -> i64 {"] + calls + ["return 0 }"]
    return ("signed_constant_division", "\n".join(source),
            "".join(f"{value}\n" for value in expected), 0)


CASES += (integer_edge_case(), signed_constant_division_case())

# Threads: a joined thread must report its return value on every host backend.
# (wasm32-wasi has no OS threads and is expected to reject the program.)
THREAD_CASE = (
    "thread_join_value",
    """
fn worker(arg: i64) -> i64 {
    return arg * 2
}
fn main() -> i64 {
    let h = @thread_create("worker", 21)
    printInt(@thread_join(h))
    let h2 = spawn { return 5 }
    printInt(@thread_join(h2))
    return 0
}
""",
    "42\n5\n",
    0,
)

# Positional I/O (@pread/@pwrite/@lseek): the O(1) deep-offset, stateless,
# thread-safe primitives that PB-scale multi-shard streaming ingest relies on.
# File I/O is -ENOSYS on bare wasm32-wasi (same as @open/@read), so this runs
# on the host backends only, mirroring the thread case.
POSITIONAL_IO_CASE = (
    "positional_io",
    """
fn main() -> i64 {
    let path = "pos_io.bin"
    let fdw = @open(path, 577, 420)
    if fdw < 0 { println("open_w_fail") return 1 }
    let target = "TARGETOK"
    let nw = @pwrite(fdw, target.ptr as *u8, 8, 4096)
    @close(fdw)
    println("pwrite=" + @int_to_string(nw))
    let fdr = @open(path, 0, 0)
    if fdr < 0 { println("open_r_fail") return 1 }
    let dst = @malloc(8)
    let nr = @pread(fdr, dst, 8, 4096)
    var okm = 1
    var i: i64 = 0
    while i < 8 { if @read_u8(@ptr_add(dst, i)) != @read_u8(@ptr_add(target.ptr, i)) { okm = 0 } i = i + 1 }
    println("pread=" + @int_to_string(nr) + " match=" + @int_to_string(okm))
    let p0 = @lseek(fdr, 0, 1)
    let _x = @pread(fdr, dst, 8, 16)
    let p1 = @lseek(fdr, 0, 1)
    var stateless = 0
    if p0 == p1 { stateless = 1 }
    println("stateless=" + @int_to_string(stateless))
    @free(dst)
    @close(fdr)
    let _u = @unlink(path)
    return 0
}
""",
    "pwrite=8\npread=8 match=1\nstateless=1\n",
    0,
)



class BackendTests(unittest.TestCase):
    def test_execution_matrix(self):
        with tempfile.TemporaryDirectory(prefix="lir-backends-") as temp:
            cwd = pathlib.Path(temp)
            for name, source, expected, exit_code in CASES:
                path = cwd / (name + ".lir")
                path.write_text(source)
                for backend in BACKENDS:
                    for level in LEVELS:
                        with self.subTest(case=name, backend=backend, level=level):
                            result = subprocess.run(
                                [str(COMPILER), "run", str(path), "--backend=" + backend, level]
                                + (["--target=wasm32-wasi"] if backend == "wasm" else []),
                                cwd=cwd, capture_output=True, text=True, timeout=30)
                            self.assertEqual(result.returncode, exit_code, result.stderr)
                            self.assertEqual(result.stdout, expected, result.stderr)

    def test_thread_join_reports_child_value(self):
        """Native/C join must return the child's value, not a wait status."""
        name, source, expected, exit_code = THREAD_CASE
        with tempfile.TemporaryDirectory(prefix="lir-threads-") as temp:
            cwd = pathlib.Path(temp)
            path = cwd / (name + ".lir")
            path.write_text(source)
            for backend in ("native", "vm", "c"):
                for level in LEVELS:
                    with self.subTest(backend=backend, level=level):
                        result = subprocess.run(
                            [str(COMPILER), "run", str(path), "--backend=" + backend, level],
                            cwd=cwd, capture_output=True, text=True, timeout=60)
                        self.assertEqual(result.returncode, exit_code, result.stderr)
                        self.assertEqual(result.stdout, expected, result.stderr)

    def test_positional_io_pread_pwrite_lseek(self):
        """@pwrite/@pread/@lseek: correct deep-offset I/O, and @pread is
        stateless (must not move the shared file offset). Host backends only;
        bare wasm32-wasi returns -ENOSYS for all file I/O like @open/@read."""
        name, source, expected, exit_code = POSITIONAL_IO_CASE
        with tempfile.TemporaryDirectory(prefix="lir-posio-") as temp:
            cwd = pathlib.Path(temp)
            path = cwd / (name + ".lir")
            path.write_text(source)
            for backend in ("native", "vm", "c"):
                for level in LEVELS:
                    with self.subTest(backend=backend, level=level):
                        result = subprocess.run(
                            [str(COMPILER), "run", str(path), "--backend=" + backend, level],
                            cwd=cwd, capture_output=True, text=True, timeout=60)
                        self.assertEqual(result.returncode, exit_code, result.stderr)
                        self.assertEqual(result.stdout, expected, result.stderr)

    def test_wasm_rejects_threads_with_a_diagnostic(self):
        """wasm32-wasi has no OS threads: fail closed instead of trapping."""
        name, source, _expected, _exit_code = THREAD_CASE
        with tempfile.TemporaryDirectory(prefix="lir-threads-wasm-") as temp:
            cwd = pathlib.Path(temp)
            path = cwd / (name + ".lir")
            path.write_text(source)
            result = subprocess.run(
                [str(COMPILER), "run", str(path), "--backend=wasm", "--target=wasm32-wasi"],
                cwd=cwd, capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("LIR-E7004", result.stderr)
            self.assertNotIn("RuntimeError", result.stdout + result.stderr)

    def test_negative_runtime_exponent_traps(self):
        with tempfile.TemporaryDirectory(prefix="lir-power-trap-") as temp:
            cwd = pathlib.Path(temp)
            path = cwd / "main.lir"
            sources = (
                "fn power(x: i64, n: i64) -> i64 { return x ** n }\n"
                "fn main() -> i64 { printInt(power(2, -1)) return 0 }",
                "fn main() -> i64 { var value = 2 let exponent = -1 "
                "value **= exponent return value }",
            )
            for source in sources:
                path.write_text(source)
                check = subprocess.run([str(COMPILER), "check", str(path)],
                                       capture_output=True, text=True, timeout=30)
                self.assertEqual(check.returncode, 0, check.stderr)
                for backend in BACKENDS:
                    for level in LEVELS:
                        with self.subTest(source=source, backend=backend, level=level):
                            args = [str(COMPILER), "run", str(path), "--backend=" + backend, level]
                            if backend == "wasm":
                                args.append("--target=wasm32-wasi")
                            result = subprocess.run(args, cwd=cwd, capture_output=True,
                                                    text=True, timeout=30)
                            self.assertNotEqual(result.returncode, 0)
                            self.assertEqual(result.stdout, "")

    def test_invalid_float_to_unsigned_traps(self):
        sources = (
            "fn main() -> i64 { printInt((-1.0 as u64) as i64) return 0 }",
            "fn main() -> i64 { printInt((18446744073709551616.0 as u64) as i64) return 0 }",
            "fn main() -> i64 { printInt(((0.0 / 0.0) as u64) as i64) return 0 }",
        )
        with tempfile.TemporaryDirectory(prefix="lir-ftou-traps-") as temp:
            cwd = pathlib.Path(temp)
            path = cwd / "main.lir"
            for source in sources:
                path.write_text(source)
                for backend in BACKENDS:
                    for level in LEVELS:
                        with self.subTest(source=source, backend=backend, level=level):
                            args = [str(COMPILER), "run", str(path), "--backend=" + backend, level]
                            if backend == "wasm":
                                args.append("--target=wasm32-wasi")
                            result = subprocess.run(args, cwd=cwd, capture_output=True,
                                                    text=True, timeout=30)
                            self.assertNotEqual(result.returncode, 0)
                            self.assertEqual(result.stdout, "")

    def test_language_feature_diagnostics(self):
        invalid = [
            ('+"text"', "numeric"),
            ('2 ** -1', "nonnegative"),
            ('2.0 ** 3.0', "i64"),
            ('true ** 3', "i64"),
            ('(2 as u64) ** 3', "i64"),
            ('@rotl(1)', "arguments"),
            ('@rotr(1, 2, 3)', "arguments"),
            ('@bit_reverse(1.5)', "i64"),
            ('@signum(true)', "i64"),
            ('@is_power_of_two("8")', "i64"),
            ('@wrapping_add(1, false)', "i64"),
            ('@wrapping_sub(1 as u64, 1)', "i64"),
            ('@wrapping_mul(1 as i32, 2)', "i64"),
        ]
        with tempfile.TemporaryDirectory(prefix="lir-invalid-features-") as temp:
            cwd = pathlib.Path(temp)
            for expression, message in invalid:
                with self.subTest(expression=expression):
                    path = cwd / "bad.lir"
                    path.write_text(f"fn main() -> i64 {{ let value = {expression} return 0 }}")
                    result = subprocess.run([str(COMPILER), "check", str(path)],
                                            capture_output=True, text=True, timeout=30)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(message, result.stderr)
            path.write_text("fn main() -> i64 { loop return 0 }")
            result = subprocess.run([str(COMPILER), "check", str(path)],
                                    capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            path.write_text("fn main() -> i64 { var value = 2 value **= -1 return value }")
            result = subprocess.run([str(COMPILER), "check", str(path)],
                                    capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("nonnegative", result.stderr)

    def test_o0_build_ir_matches_unoptimized_ir_command(self):
        # This specifically detects silent CLI -O0 -> -O2 promotion, rather than
        # only checking output parity (which an optimizing compiler can pass).
        with tempfile.TemporaryDirectory(prefix="lir-opt-") as temp:
            cwd = pathlib.Path(temp)
            path = cwd / "main.lir"
            path.write_text('fn main() -> i64 { let a = 6 let b = 7 printInt(a * b) return 0 }')
            def invoke(*args):
                result = subprocess.run([str(COMPILER), *args], cwd=cwd,
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)
                return result.stdout
            ir = invoke("ir", str(path), "-O0")
            optimized = invoke("ir", str(path), "-O2")
            self.assertNotEqual(ir, optimized, "fixture must distinguish optimization levels")
            build = invoke("build", str(path), "-O0", "--emit-ir", "-o", "program")
            # Build appends its artifact-size status line after the IR dump.
            self.assertIn(ir, build)
            self.assertNotIn(optimized, build)


if __name__ == "__main__":
    unittest.main()
