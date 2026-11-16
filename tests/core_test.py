#!/usr/bin/env python3
"""Core-language regression gates. Requirements match backend_test.py."""
import pathlib
import subprocess
import textwrap
import tempfile
import unittest

from backend_test import COMPILER, BACKENDS, LEVELS, EXAMPLES


class TraitConformanceTests(unittest.TestCase):
    """Trait impls must match the declaration: a mismatched signature would be
    dispatched through the trait but called with the wrong ABI."""

    def run_lir(self, source, *args):
        with tempfile.TemporaryDirectory(prefix="lir-trait-") as temp:
            path = pathlib.Path(temp) / "m.lir"
            path.write_text(textwrap.dedent(source).lstrip())
            return subprocess.run([str(COMPILER), *args, str(path)],
                                  capture_output=True, text=True, timeout=60)

    def test_matching_impls_run(self):
        source = """
            trait Reader { fn read(self) -> i64 }
            trait Writer { fn write(&mut self, v: i64) -> i64 }

            struct Buf { v: i64 }

            impl Reader for Buf { fn read(self) -> i64 { return self.v } }
            impl Writer for Buf { fn write(self: *mut Buf, v: i64) -> i64 { self.v = v return self.v } }

            fn main() -> i64 {
                var b = Buf { v: 42 }
                printInt(b.read())
                printInt(b.write(7))
                printInt(b.read())
                return 0
            }
        """
        result = self.run_lir(source, "run", "--backend=vm")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "42\n7\n7")

    def test_wrong_return_type_is_rejected(self):
        source = """
            trait T { fn m(self) -> i64 }
            struct S { v: i64 }
            impl T for S { fn m(self) -> f64 { return 1.0 } }
            fn main() -> i64 { return 0 }
        """
        result = self.run_lir(source, "check")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("LIR-E3004", result.stderr)

    def test_wrong_arity_is_rejected(self):
        source = """
            trait T { fn m(self, a: i64) -> i64 }
            struct S { v: i64 }
            impl T for S { fn m(self) -> i64 { return 1 } }
            fn main() -> i64 { return 0 }
        """
        result = self.run_lir(source, "check")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("LIR-E3005", result.stderr)

    def test_mutating_receiver_needs_mut_trait_declaration(self):
        source = """
            trait T { fn m(self) -> i64 }
            struct S { v: i64 }
            impl T for S { fn m(self: *mut S) -> i64 { self.v = 1 return self.v } }
            fn main() -> i64 { return 0 }
        """
        result = self.run_lir(source, "check")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("LIR-E3004", result.stderr)

    def test_dyn_dispatch_across_two_impls(self):
        source = """
            trait Shape { fn area(self) -> i64 }
            struct Square { s: i64 }
            struct Rect { w: i64, h: i64 }
            impl Shape for Square { fn area(self) -> i64 { return self.s * self.s } }
            impl Shape for Rect { fn area(self) -> i64 { return self.w * self.h } }
            fn total(a: dyn Shape, b: dyn Shape) -> i64 { return a.area() + b.area() }
            fn main() -> i64 { return total(Square { s: 3 }, Rect { w: 2, h: 5 }) }
        """
        result = self.run_lir(source, "run", "--backend=vm")
        self.assertEqual(result.returncode, 19, result.stderr)


class CoreTests(unittest.TestCase):
    def invoke(self, cwd, *args):
        return subprocess.run([str(COMPILER), *args], cwd=cwd,
                              capture_output=True, text=True, timeout=30)

    def test_typed_pattern_execution(self):
        fixtures = (
            ("tuple-patterns.lir", "120\n10\n7\n100\n9\n-1\n-1\n0\n1\n"),
            ("typed-match.lir", "11\n0\n-1\n251\n1\n0\n42\n7\n"),
            ("enum-patterns.lir", "1000\n400\n100\n212\n400\n300\n400\n500\n608\n700\n800\n800\n900\n901\n902\n70\n90\n5\n90\n90\n11\n-1\n"),
        )
        with tempfile.TemporaryDirectory(prefix="lir-core-") as temp:
            for fixture, expected in fixtures:
                for backend in BACKENDS:
                    for level in LEVELS:
                        with self.subTest(fixture=fixture, backend=backend, level=level):
                            args = ["run", str(EXAMPLES / fixture), level, "--backend=" + backend]
                            if backend == "wasm":
                                args.append("--target=wasm32-wasi")
                            result = self.invoke(temp, *args)
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertEqual(result.stdout, expected)

    def test_invalid_patterns_and_types(self):
        cases = (
            ("guard_type", 'fn main() -> i64 { return match 1 { 1 if 5 => 1, _ => 0 } }', "guard must be bool"),
            ("arm_types", 'fn main() -> i64 { let v = match 1 { 1 => 1, _ => "bad" } return 0 }', "incompatible result"),
            ("void_arm", 'fn main() -> i64 { let v = match 1 { 1 => println("x"), _ => 1 } return 0 }', "incompatible result"),
            ("bool_pattern", 'fn main() -> i64 { return match true { 1 => 1, _ => 0 } }', "pattern type"),
            ("string_pattern", 'fn main() -> i64 { return match 1 { "x" => 1, _ => 0 } }', "pattern type"),
            ("tuple_shape", 'fn main() -> i64 { return match (1, 2) { (x, y, z) => 1, _ => 0 } }', "expected 2"),
            ("not_tuple", 'fn main() -> i64 { return match 1 { (x, y) => 1, _ => 0 } }', "tuple scrutinee"),
            ("tuple_field_type", 'fn main() -> i64 { return match (1, true) { ("x", _) => 1, _ => 0 } }', "pattern type"),
            ("duplicate_binding", 'fn main() -> i64 { return match (1, 2) { (x, x) => x, _ => 0 } }', "duplicate pattern"),
            ("alternative_binding", 'fn main() -> i64 { return match 1 { x | y => x, _ => 0 } }', "alternative patterns"),
            ("wildcard_order", 'fn main() -> i64 { return match 1 { _ => 0, 1 => 1 } }', "must be last"),
            ("duplicate_wildcard", 'fn main() -> i64 { return match 1 { _ => 0, _ => 1 } }', "must be last"),
            ("guard_not_exhaustive", 'fn main() -> i64 { return match 1 { _ if true => 1 } }', "non-exhaustive"),
            ("range_types", 'fn main() -> i64 { return match "x" { 1..3 => 1, _ => 0 } }', "integer bounds"),
            ("dynamic_range", 'fn pick(n: i64) -> i64 { return match 1 { 0..n => 1, _ => 0 } } fn main() -> i64 { return pick(3) }', "compile-time constants"),
            ("tuple_destruct_shape", 'fn main() -> i64 { let (a, b) = (1, 2, 3) return 0 }', "same number"),
            ("scalar_destruct", 'fn main() -> i64 { let (a, b) = 1 return 0 }', "same number"),
            ("tuple_capacity", 'fn main() -> i64 { let t = (1,2,3,4,5,6,7,8,9) return 0 }', "at most 8"),
            ("nested_tuple_type", 'fn take(t: ((i64, bool), i64)) -> i64 { return 0 } fn main() -> i64 { return take(((1, 2), 3)) }', "mismatches"),
            ("tuple_width_preserved", 'fn main() -> i64 { let t = (1 as u8, true) return match t { (n, _) => @signum(n) } }', "must be i64"),
            ("binding_scope", 'fn main() -> i64 { let v = match (1, 2) { (a,b) => a+b } return a }', "undeclared"),
            ("payload_arity", 'enum E { A(i64), B } fn pick(e: E) -> i64 { return match e { E::A(x,y) => x, E::B => 0 } } fn main() -> i64 { return 0 }', "payload patterns"),
            ("missing_payload", 'enum E { A(i64), B } fn pick(e: E) -> i64 { return match e { E::A => 1, E::B => 0 } } fn main() -> i64 { return 0 }', "payload patterns"),
            ("payload_literal_type", 'enum E { A(i64), B } fn pick(e: E) -> i64 { return match e { E::A("bad") => 1, _ => 0 } } fn main() -> i64 { return 0 }', "pattern type"),
            ("partial_payload_coverage", 'enum E { A(i64), B } fn pick(e: E) -> i64 { return match e { E::A(7) => 1, E::B => 0 } } fn main() -> i64 { return 0 }', "non-exhaustive"),
            ("partial_bool_coverage", 'enum E { A(bool), B } fn pick(e: E) -> i64 { return match e { E::A(true) => 1, E::B => 0 } } fn main() -> i64 { return 0 }', "non-exhaustive"),
            ("nested_payload_arity", 'enum I { A(i64) } enum E { Wrap(I) } fn pick(e: E) -> i64 { return match e { E::Wrap(I::A(x,y)) => x, _ => 0 } } fn main() -> i64 { return 0 }', "payload patterns"),
            ("nested_payload_type", 'enum E { A((i64, bool)) } fn pick(e: E) -> i64 { return match e { E::A((x, 1)) => x, _ => 0 } } fn main() -> i64 { return 0 }', "pattern type"),
            ("duplicate_payload_binding", 'enum E { A(i64, i64) } fn pick(e: E) -> i64 { return match e { E::A(x,x) => x } } fn main() -> i64 { return 0 }', "duplicate pattern"),
            ("payload_binding_escape", 'enum E { A(i64), B } fn pick(e: E) -> i64 { let v = match e { E::A(x) => x, E::B => 0 } return x } fn main() -> i64 { return 0 }', "undeclared"),
            ("enum_scrutinee_type", 'enum E { A, B } fn main() -> i64 { return match 1 { E::A => 1, _ => 0 } }', "scrutinee enum"),
        )
        with tempfile.TemporaryDirectory(prefix="lir-core-invalid-") as temp:
            source = pathlib.Path(temp) / "bad.lir"
            for name, text, diagnostic in cases:
                with self.subTest(case=name):
                    source.write_text(text)
                    result = self.invoke(temp, "check", str(source))
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertIn(diagnostic, result.stderr)



class MutableReassignmentTests(unittest.TestCase):
    """A `let mut`/`var` binding must never be treated as a compile-time
    constant. The AST optimizer's constant tracker is keyed by name, so
    tracking a mutable binding makes a later assignment look like a redundant
    store and lets a folding pass drop it -- the variable then keeps reading
    its initial value. These cases pin the behaviour at every optimization
    level, which is where the bug appeared."""

    def run_lir(self, source, *args):
        with tempfile.TemporaryDirectory(prefix="lir-mut-") as temp:
            path = pathlib.Path(temp) / "m.lir"
            path.write_text(textwrap.dedent(source).lstrip())
            return subprocess.run([str(COMPILER), *args, str(path)],
                                  capture_output=True, text=True, timeout=60)

    def test_assignment_inside_folded_then_branch(self):
        # The condition folds to true, so the assignment is the only statement
        # that reaches the print. Losing it prints 0 instead of 7.
        source = """
            fn main() -> i64 {
                var a: i64 = 0
                if 0 == 0 { a = 7 }
                printInt(a)
                return 0
            }
        """
        for level in LEVELS:
            for backend in ("native", "vm", "c"):
                with self.subTest(level=level, backend=backend):
                    result = self.run_lir(source, "run", f"--backend={backend}", level)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(), "7")

    def test_var_reassigned_after_constant_initializer(self):
        source = """
            fn main() -> i64 {
                var a: i64 = 1
                a = 2
                printInt(a)
                return 0
            }
        """
        for level in LEVELS:
            with self.subTest(level=level):
                result = self.run_lir(source, "run", level)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "2")

    def test_immutable_let_still_folds(self):
        # The whole point of the tracker: an immutable scalar `let` must still
        # propagate, otherwise the fix would have traded a bug for a pessimisation.
        source = """
            fn main() -> i64 {
                let c: i64 = 21
                printInt(c * 2)
                return 0
            }
        """
        for level in LEVELS:
            with self.subTest(level=level):
                result = self.run_lir(source, "run", level)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "42")

    def test_mutable_reassigned_in_folded_loop(self):
        source = """
            fn main() -> i64 {
                var sum: i64 = 0
                var i: i64 = 0
                while i < 5 {
                    sum = sum + i
                    i = i + 1
                }
                printInt(sum)
                return 0
            }
        """
        for level in LEVELS:
            with self.subTest(level=level):
                result = self.run_lir(source, "run", level)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "10")



class OptimizationEquivalenceTests(unittest.TestCase):
    """-O0, -O1 and -O2 must agree, and must agree with a differential oracle.

    The optimizer is written against fixed-capacity tables and repeatedly runs
    stateful passes over them; a pass that keeps stale per-function or
    per-block state produces a plausible-looking but wrong answer instead of a
    crash. These two gates target that failure mode directly.
    """

    def run_lir(self, source, *args):
        with tempfile.TemporaryDirectory(prefix="lir-oeq-") as temp:
            path = pathlib.Path(temp) / "m.lir"
            path.write_text(textwrap.dedent(source).lstrip())
            return subprocess.run([str(COMPILER), *args, str(path)],
                                  capture_output=True, text=True, timeout=60)

    def test_levels_agree_on_generated_functions(self):
        """A module of many small functions exercises the per-function state
        resets; every level must print the same values."""
        parts = []
        for index in range(40):
            parts.append(
                f"fn fn{index}(a: i64, b: i64) -> i64 {{\n"
                f"    var x: i64 = a + b * {index % 7 + 1}\n"
                f"    x = x * x + a\n"
                f"    return x\n"
                f"}}"
            )
        prints = "\n".join(f"    printInt(fn{i}({i + 1}, {i % 5}))" for i in range(40))
        source = "\n".join(parts) + f"\nfn main() -> i64 {{\n{prints}\n    return 0\n}}\n"

        outputs = {}
        for level in LEVELS:
            result = self.run_lir(source, "run", level)
            self.assertEqual(result.returncode, 0, f"{level}: {result.stderr}")
            outputs[level] = result.stdout
        for level in LEVELS:
            self.assertEqual(outputs[level], outputs["-O0"],
                             f"{level} disagrees with -O0")

    def test_random_programs_match_python_oracle(self):
        """Random straight-line and branching programs, checked against an
        independent Python evaluation of the same semantics."""
        import random

        rng = random.Random(20261116)
        for case in range(25):
            lines = ["fn work(a: i64, b: i64) -> i64 {", "    var acc: i64 = a"]
            expected = None
            # Emit a program whose value Python can recompute exactly.
            acc = "a"
            b_val = rng.randrange(1, 9)
            a_val = rng.randrange(1, 9)
            py = {"a": a_val, "b": b_val}
            for _ in range(rng.randrange(3, 7)):
                choice = rng.randrange(4)
                const = rng.randrange(1, 6)
                if choice == 0:
                    lines.append(f"    acc = acc + b * {const}")
                    acc = f"({acc}) + b*{const}"
                elif choice == 1:
                    lines.append(f"    if acc % {2 * const + 1} == 0 {{ acc = acc + {const} }}")
                    acc = f"(({acc}) + {const} if ({acc}) % {2 * const + 1} == 0 else ({acc}))"
                elif choice == 2:
                    lines.append(f"    acc = acc - {const}")
                    acc = f"({acc}) - {const}"
                else:
                    lines.append(f"    acc = acc * 2 + {const}")
                    acc = f"({acc})*2 + {const}"
            lines.append("    return acc")
            lines.append("}")
            lines.append("fn main() -> i64 {")
            lines.append(f"    printInt(work({a_val}, {b_val}))")
            lines.append("    return 0")
            lines.append("}")
            source = "\n".join(lines) + "\n"
            expected = eval(acc, {}, py)  # noqa: S307 - fixed, generated arithmetic

            with self.subTest(case=case):
                outputs = {}
                for level in LEVELS:
                    result = self.run_lir(source, "run", level)
                    self.assertEqual(result.returncode, 0, f"{level}: {result.stderr}\n{source}")
                    outputs[level] = result.stdout.strip()
                for level in LEVELS:
                    self.assertEqual(outputs[level], str(expected),
                                     f"{level} computed {outputs[level]}, expected {expected}\n{source}")


def _expected_branchy_total(n):
    total = 0
    for i in range(1, n + 1):
        total += i % 1009 if i % 7 == 0 else i % 97
    return total


def _expected_scaled_total(upto):
    total = 0
    for i in range(1, upto + 1):
        t = (i * i) // 10000 + ((i + 3) * (i + 3)) // 10000
        if i % 2 == 0:
            total += t
    return total


class LoopOptimizationSoundnessTests(unittest.TestCase):
    """Loops whose bodies update several variables must keep their trip count.

    These three programs each used to print a wrong number while every level
    reported success, because three optimizer passes were unsound in ways a
    smoke test cannot see:

      * loop unrolling advanced the induction variable once per *unrolled
        repetition*, not once per iteration (the write-back also copied a
        stale definition);
      * copy coalescing wrote a result into a destination that was still read
        further down the block, which turned `x = x + 1; y = x + 1; x = y + 1`
        into `x = x + 1; y = x + 1; x = x + 1`;
      * loop rotation ran on a function that still carried phis, where it
        silently invalidated values.

    Every case is checked at each level, on both backends, against a trip
    count that is written out by hand.
    """

    def run_source(self, source, level, backend=None):
        args = ["run", level]
        if backend:
            args.append(f"--backend={backend}")
        return self.run_lir(source, *args)

    def run_lir(self, source, *args):
        with tempfile.TemporaryDirectory(prefix="lir-loop-") as temp:
            path = pathlib.Path(temp) / "m.lir"
            path.write_text(textwrap.dedent(source).lstrip())
            return subprocess.run([str(COMPILER), *args, str(path)],
                                  capture_output=True, text=True, timeout=120)

    def assert_all_levels(self, source, expected):
        for level in LEVELS:
            for backend in (None, "vm"):
                with self.subTest(level=level, backend=backend or "native"):
                    result = self.run_source(source, level, backend)
                    self.assertEqual(result.returncode, 0,
                                     f"{level}: {result.stderr}\n{source}")
                    self.assertEqual(result.stdout.strip(), str(expected),
                                     f"{level} ({backend or 'native'}) printed "
                                     f"{result.stdout.strip()}, expected {expected}\n{source}")

    def test_counter_loop_trip_count(self):
        self.assert_all_levels("""
            fn main() -> i64 {
                var n: i64 = 2
                var count: i64 = 0
                while n <= 10 {
                    count += 1
                    n += 1
                }
                printInt(count)
                return 0
            }
        """, 9)

    def test_two_loops_with_strided_update(self):
        self.assert_all_levels("""
            fn main() -> i64 {
                var n: i64 = 2
                var count: i64 = 0
                while n <= 10 {
                    count += 1
                    n += 1
                }
                var acc: i64 = 0
                while acc < 7 {
                    acc += 2
                }
                printInt(count + acc)
                return 0
            }
        """, 17)  # 9 iterations + acc reaching 8

    def test_nested_loops_with_break_and_early_exit(self):
        self.assert_all_levels("""
            fn count_primes(limit: i64) -> i64 {
                var count: i64 = 0
                var n: i64 = 2
                while n <= limit {
                    var is_p: i64 = 1
                    var d: i64 = 2
                    while d * d <= n {
                        if n % d == 0 {
                            is_p = 0
                            break
                        }
                        d += 1
                    }
                    count += is_p
                    n += 1
                }
                return count
            }
            fn main() -> i64 {
                printInt(count_primes(100))
                return 0
            }
        """, 25)

    def test_branchy_loop_accumulator(self):
        """Accumulating from two branches into one variable (the -O1 hazard:
        a copy coalesced into a destination that was read later)."""
        self.assert_all_levels("""
            fn work(n: i64) -> i64 {
                var total: i64 = 0
                var i: i64 = 1
                while i <= n {
                    if i % 7 == 0 { total += i % 1009 } else { total += i % 97 }
                    i += 1
                }
                return total
            }
            fn main() -> i64 {
                printInt(work(100000))
                return 0
            }
        """, _expected_branchy_total(100000))

    def test_division_by_constant_after_copy(self):
        """A copy of a constant divisor must not force a real idiv path.

        The observable result is the same either way; this guards the shape that
        makes `x / 10000` lower to a multiply, which the K1 mandelbrot benchmark
        depends on."""
        self.assert_all_levels("""
            fn scaled(a: i64, b: i64) -> i64 {
                let s: i64 = 10000
                return (a * a) / s + (b * b) / s
            }
            fn main() -> i64 {
                var total: i64 = 0
                var i: i64 = 1
                while i < 500 {
                    var t: i64 = scaled(i, i + 3)
                    if i % 2 == 0 { total += t }
                    i += 1
                }
                printInt(total)
                return 0
            }
        """, _expected_scaled_total(499))


if __name__ == "__main__":
    unittest.main()
