#!/usr/bin/env python3
"""Dependency-free CLI regression tests; all outputs stay in a temp directory."""
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

COMPILER = pathlib.Path(sys.argv.pop(1) if len(sys.argv) > 1 else "zig-out/bin/lir").resolve()


class CliTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="lir-cli-")
        self.addCleanup(self.temp.cleanup)
        self.cwd = pathlib.Path(self.temp.name)
        (self.cwd / "main.lir").write_text('fn main() -> i64 { println("42") 0 }\n')

    def run_cli(self, *args, ok=True):
        result = subprocess.run([str(COMPILER), *args], cwd=self.cwd,
                                capture_output=True, text=True, timeout=30)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("Error:", result.stderr)
        return result

    def test_metadata(self):
        self.assertIn("lir ", self.run_cli("version").stdout)

    def test_target_triples_printed_by_targets_are_accepted(self):
        listing = self.run_cli("targets").stdout
        triples = re.findall(r"^  ([a-z0-9_]+-[a-z0-9]+)\s", listing, re.M)
        self.assertGreaterEqual(len(triples), 10)
        with tempfile.TemporaryDirectory(prefix="lir-targets-") as temp:
            src = pathlib.Path(temp) / "main.lir"
            src.write_text("fn main() -> i64 { return 3 }\n")
            out = pathlib.Path(temp) / "out.c"
            for triple in triples:
                with self.subTest(triple=triple):
                    result = self.run_cli("build", str(src), "--emit-c",
                                          "-o", str(out), f"--target={triple}")
                    self.assertEqual(result.returncode, 0, result.stderr)
            # Well-known GNU spellings resolve to the same targets.
            for alias in ("x86_64-unknown-linux-gnu", "aarch64-unknown-linux-gnu",
                          "wasm32-unknown-wasi", "x86_64-pc-windows-gnu"):
                with self.subTest(alias=alias):
                    result = self.run_cli("build", str(src), "--emit-c",
                                          "-o", str(out), f"--target={alias}")
                    self.assertEqual(result.returncode, 0, result.stderr)
            for bogus in ("bogus", "x86_64-plan9", "aarch64-"):
                with self.subTest(bogus=bogus):
                    result = self.run_cli("build", str(src), "--emit-c",
                                          "-o", str(out), f"--target={bogus}", ok=False)
                    self.assertIn("unsupported target", result.stderr)

    def test_help_flags_and_unknown_options(self):
        for command in ("lang", "builtins"):
            with self.subTest(command=command):
                self.assertIn("Usage: lir " + command,
                              self.run_cli(command, "--help").stdout)
        self.assertIn("LIR knowledge base", self.run_cli("explain", "--help").stdout)
        for args in (("lang", "--nope"), ("builtins", "--nope"),
                     ("lang", "--status=bogus"), ("lang", "--category=bogus")):
            with self.subTest(args=args):
                self.run_cli(*args, ok=False)

    def test_version_matches_package_manifest(self):
        manifest = pathlib.Path(__file__).resolve().parents[1] / "build.zig.zon"
        declared = re.search(r'\.version = "([^"]+)"', manifest.read_text()).group(1)
        self.assertIn(declared, self.run_cli("version").stdout)
        self.assertIn(declared, self.run_cli("help").stdout)
        self.assertIn("Usage:", self.run_cli("help").stdout)
        self.assertIn("wasm32-wasi", self.run_cli("targets").stdout)

    def test_extra_arguments_are_rejected(self):
        for command in ("build", "check", "ir", "test"):
            with self.subTest(command=command):
                self.run_cli(command, "main.lir", "extra.lir", ok=False)
        self.run_cli("init", "demo", "extra", ok=False)

    def test_unknown_options_are_rejected(self):
        for command in ("build", "check", "ir", "test"):
            with self.subTest(command=command):
                self.run_cli(command, "main.lir", "--typo", ok=False)

    def test_missing_flag_values(self):
        for command in ("build", "check", "ir", "test"):
            self.run_cli(command, "main.lir", "--target", ok=False)
        self.run_cli("build", "main.lir", "-o", ok=False)

    def test_init_is_non_destructive_and_buildable(self):
        self.run_cli("init", "demo")
        source = self.cwd / "demo/src/main.lir"
        before = source.read_bytes()
        self.run_cli("init", "demo", ok=False)
        self.assertEqual(source.read_bytes(), before)
        self.assertFalse((self.cwd / "project.manifest").exists())
        self.run_cli("check", "demo/src/main.lir")
        for name in (".", "..", "../escape", "bad/name"):
            self.run_cli("init", name, ok=False)

    def test_build_check_vm_and_c_emission(self):
        self.run_cli("check", "main.lir")
        self.assertIn("42", self.run_cli("run", "main.lir", "--backend=vm").stdout)
        self.run_cli("build", "main.lir", "-o", "program")
        self.assertTrue((self.cwd / "program").is_file())
        self.run_cli("build", "main.lir", "--emit-c", "-o", "program.c")
        self.assertIn("#include", (self.cwd / "program.c").read_text())

    def test_failed_build_preserves_existing_output(self):
        (self.cwd / "program").write_bytes(b"existing artifact")
        (self.cwd / "bad.lir").write_text('fn main() { let x = "unterminated }')
        result = subprocess.run([str(COMPILER), "build", "bad.lir", "-o", "program"],
                                cwd=self.cwd, capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.cwd / "program").read_bytes(), b"existing artifact")
        self.assertFalse(list(self.cwd.glob("*.lir_tmp_*")))

    def test_repl_evaluation(self):
        script = "10 + 32\nlet x = 5\nx * 7\n:exit\n"
        proc = subprocess.run([str(COMPILER), "repl"], input=script, text=True, capture_output=True, timeout=30)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("=> 42", proc.stdout)
        self.assertIn("=> 35", proc.stdout)


if __name__ == "__main__":
    unittest.main()
