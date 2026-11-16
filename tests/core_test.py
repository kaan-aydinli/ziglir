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


if __name__ == "__main__":
    unittest.main()
