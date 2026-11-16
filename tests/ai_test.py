#!/usr/bin/env python3
"""Machine-contract regression gate for AI/tooling integrations.

Everything an automated consumer relies on is asserted here:

* `lir lang --json` / `lir builtins --json` parse, are complete and internally
  consistent (unique names, every builtin signature well formed).
* Every `supported` catalogue example is a valid program (`lir check` passes)
  and every `unsupported` entry really is rejected.
* `lir check --json` keeps a single JSON object on stdout and emits
  `lir.diagnostics.v1` on stderr with stable codes and `expect` metadata.
* `lir build --json` describes the artifact.
* `lir explain` resolves topics, aliases and diagnostic codes.
* `lir init --ai` produces AGENTS.md + lir.agent.json that reference real
  commands.

Usage: python3 tests/ai_test.py [path/to/lir]
"""
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

COMPILER = pathlib.Path(sys.argv.pop(1) if len(sys.argv) > 1 else "zig-out/bin/lir").resolve()


def run(*args, cwd=None, ok=True):
    result = subprocess.run([str(COMPILER), *args], cwd=cwd,
                            capture_output=True, text=True, timeout=60)
    if ok is True:
        assert result.returncode == 0, f"{args} failed: {result.stderr}"
    elif ok is False:
        assert result.returncode != 0, f"{args} unexpectedly succeeded: {result.stdout}"
    # ok=None: caller inspects the exit status itself
    return result


class CatalogueTests(unittest.TestCase):
    def test_lang_json_contract(self):
        doc = json.loads(run("lang", "--json").stdout)
        self.assertEqual(doc["schema"], "lir.lang.v1")
        self.assertEqual(doc["language"], "lir")
        features = doc["features"]
        self.assertGreaterEqual(len(features), 60)
        names = [f["name"] for f in features]
        self.assertEqual(len(names), len(set(names)), "duplicate feature names")
        statuses = {f["status"] for f in features}
        self.assertTrue(statuses <= {"supported", "partial", "legacy", "unsupported"})
        for f in features:
            for key in ("name", "status", "category", "syntax", "notes"):
                self.assertIn(key, f, f"feature {f.get('name')} missing {key}")
            if f["status"] == "supported":
                self.assertIn("example", f, f"supported feature {f['name']} has no example")
        # counts block must agree with the list
        counted = {}
        for f in features:
            counted[f["status"]] = counted.get(f["status"], 0) + 1
        for status, n in counted.items():
            self.assertEqual(doc["counts"][status], n, status)

    def test_unsupported_entries_document_what_to_avoid(self):
        doc = json.loads(run("lang", "--json", "--status=unsupported").stdout)
        self.assertGreaterEqual(len(doc["features"]), 5)
        for f in doc["features"]:
            self.assertIn("avoid", f, f"{f['name']} must name what not to write")
            self.assertNotIn("example", f)

    def test_every_supported_example_checks(self):
        doc = json.loads(run("lang", "--json", "--status=supported").stdout)
        with tempfile.TemporaryDirectory(prefix="lir-ai-") as temp:
            for f in doc["features"]:
                example = f.get("example")
                if not example:
                    continue
                path = pathlib.Path(temp) / f"{f['name']}.lir"
                path.write_text(example + "\n")
                result = run("check", str(path), ok=None)
                self.assertEqual(result.returncode, 0,
                                 f"{f['name']} example rejected:\n{result.stderr}")

    def test_unsupported_spellings_are_rejected(self):
        probes = {
            "pipe": "fn main() -> i64 { return 5 |> 3 }",
            "async": "async fn f() -> i64 { return 1 }\nfn main() -> i64 { return 0 }",
            "extern": "extern fn puts(s: string) -> i64\nfn main() -> i64 { return 0 }",
            "mod": "mod foo\nfn main() -> i64 { return 0 }",
            "unsafe": "fn main() -> i64 { unsafe { } return 0 }",
            "asm": 'fn main() -> i64 { asm("nop") return 0 }',
            "i128": "fn main() -> i64 { let x: i128 = 5 return 0 }",
            "not_kw": "fn main() -> i64 { if not false { return 1 } return 0 }",
            "nested_fn": "fn main() -> i64 { fn inner() -> i64 { return 1 } return inner() }",
            "labelled": "fn main() -> i64 { 'outer: for i in 0..3 { break } return 0 }",
            "index_pair": "fn main() -> i64 { let a = [1,2] for i, v in a { } return 0 }",
            "pure_fn": "pure fn f(x: i64) -> i64 { return x }\nfn main() -> i64 { return 0 }",
            "requires": "fn f(a: i64) -> i64 requires a > 0 { return a }\nfn main() -> i64 { return 0 }",
            "println_num": "fn main() -> i64 { println(42) return 0 }",
            "struct_field": "struct A { b: B }\nstruct B { v: i64 }\nfn main() -> i64 { return 0 }",
            "nested_generic": "fn f() -> Option<Option<i64>> { return None }\nfn main() -> i64 { return 0 }",
        }
        with tempfile.TemporaryDirectory(prefix="lir-ai-neg-") as temp:
            for name, source in probes.items():
                path = pathlib.Path(temp) / f"{name}.lir"
                path.write_text(source + "\n")
                result = run("check", str(path), ok=None)
                self.assertNotEqual(result.returncode, 0,
                                    f"{name} unexpectedly compiled: {source}")

    def test_every_stdlib_module_imports(self):
        modules = ["core", "io", "os", "sys", "net", "crypto", "json", "math",
                   "testing", "str", "algo", "collections", "hash", "fmt",
                   "time", "http"]
        with tempfile.TemporaryDirectory(prefix="lir-ai-std-") as temp:
            for module in modules:
                path = pathlib.Path(temp) / f"{module}.lir"
                path.write_text(f"import {module}\nfn main() -> i64 {{ return 0 }}\n")
                result = run("check", str(path), ok=None)
                self.assertEqual(result.returncode, 0,
                                 f"import {module} failed:\n{result.stderr}")

    def test_unknown_module_is_a_hard_error_with_suggestion(self):
        with tempfile.TemporaryDirectory(prefix="lir-ai-imp-") as temp:
            path = pathlib.Path(temp) / "bad.lir"
            path.write_text("import Str\nfn main() -> i64 { return 0 }\n")
            result = run("check", str(path), "--json", ok=False)
            diag = json.loads(result.stderr)
            first = diag["diagnostics"][0]
            self.assertEqual(first["code"], "LIR-E4004")
            self.assertEqual(first["expect"], {"kind": "module", "value": "str"})

    def test_keyword_list_is_published_and_accurate(self):
        doc = json.loads(run("lang", "--json").stdout)
        keywords = doc["keywords"]
        self.assertGreaterEqual(len(keywords), 60)
        self.assertEqual(len(keywords), len(set(keywords)))
        for required in ("fn", "let", "mut", "match", "spawn", "comptime",
                         "i128", "unsafe", "asm", "extern", "async", "await"):
            self.assertIn(required, keywords)
        only = json.loads(run("lang", "--keywords", "--json").stdout)
        self.assertEqual(only["schema"], "lir.keywords.v1")
        self.assertEqual(sorted(only["keywords"]), sorted(keywords))
        self.assertEqual(only["count"], len(keywords))
        short = run("lang", "--keywords", "--short").stdout.split()
        self.assertEqual(sorted(short), sorted(keywords))
        # No reserved word may be usable as an identifier.
        with tempfile.TemporaryDirectory(prefix="lir-ai-kw-") as temp:
            for word in keywords:
                path = pathlib.Path(temp) / "kw.lir"
                path.write_text(f"fn main() -> i64 {{ let {word} = 1 return 0 }}\n")
                self.assertNotEqual(run("check", str(path), ok=None).returncode, 0,
                                    f"reserved word '{word}' was accepted as an identifier")

    def test_cheatsheet_is_generated_and_complete(self):
        repo = COMPILER.parent.parent.parent
        generated = run("lang", "--cheatsheet").stdout
        # The checked-in copy must match the compiler (CI diffs it too).
        checked_in = (repo / "docs" / "CHEATSHEET.md").read_text()
        self.assertEqual(checked_in, generated,
                         "docs/CHEATSHEET.md is stale: regenerate with 'lir lang --cheatsheet'")
        doc = json.loads(run("lang", "--json").stdout)
        for feature in doc["features"]:
            self.assertIn(f"`{feature['name']}`", generated)
        for keyword in doc["keywords"]:
            self.assertIn(f"`{keyword}`", generated)
        for builtin in json.loads(run("builtins", "--json").stdout)["builtins"]:
            self.assertIn(f"`{builtin['name']}`", generated)

    def test_builtins_json_contract(self):
        doc = json.loads(run("builtins", "--json").stdout)
        self.assertEqual(doc["schema"], "lir.builtins.v1")
        names = [b["name"] for b in doc["builtins"]]
        self.assertGreaterEqual(len(names), 120)
        self.assertEqual(len(names), len(set(names)))
        groups = {b["group"] for b in doc["builtins"]}
        self.assertGreaterEqual(len(groups), 12)
        for b in doc["builtins"]:
            self.assertTrue(b["signature"].endswith("-> " + b["signature"].rsplit("-> ", 1)[-1]))
            self.assertIn("->", b["signature"])
            self.assertTrue(b["group"])
        for required in ("print", "println", "printInt", "printlnFloat",
                         "@array_new", "@array_push", "@map_get", "@string_len",
                         "@malloc", "@thread_create", "@chan_new", "@sqrt",
                         "@random_u64", "@syscall"):
            self.assertIn(required, names)

    def test_lang_selectors_and_filters(self):
        for feature in ("fn", "closure", "match", "option", "closure"):
            out = run("lang", feature).stdout
            self.assertIn("status:", out)
            self.assertIn("example:", out)
        short = run("lang", "--short").stdout.splitlines()
        self.assertTrue(all(len(line.split(" ")) == 3 for line in short))
        only_supported = run("lang", "--short", "--status=supported").stdout.splitlines()
        self.assertTrue(all(line.split(" ")[1] == "supported" for line in only_supported))


class DiagnosticsContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="lir-ai-diag-")
        self.addCleanup(self.temp.cleanup)
        self.dir = pathlib.Path(self.temp.name)

    def write(self, name, source):
        path = self.dir / name
        path.write_text(source)
        return path

    def test_check_ok_envelope(self):
        good = self.write("ok.lir", "fn main() -> i64 { return 0 }\n")
        result = run("check", str(good), "--json")
        doc = json.loads(result.stdout)
        self.assertEqual(doc["schema"], "lir.check.v1")
        self.assertEqual(doc["status"], "ok")
        self.assertEqual(doc["target"], "x86_64-linux")
        self.assertEqual(result.stderr.strip(), "")

    def test_error_envelopes_and_expect_metadata(self):
        bad = self.write("bad.lir", "fn main() -> i64 { printint(3) return 0 }\n")
        result = run("check", str(bad), "--json", ok=False)
        # stdout: exactly one JSON object
        out = json.loads(result.stdout)
        self.assertEqual(out["schema"], "lir.check.v1")
        self.assertEqual(out["status"], "error")
        # stderr: diagnostics document
        diag = json.loads(result.stderr)
        self.assertEqual(diag["schema"], "lir.diagnostics.v1")
        self.assertEqual(diag["status"], "error")
        self.assertEqual(diag["errors"], 1)
        first = diag["diagnostics"][0]
        self.assertEqual(first["code"], "LIR-E3002")
        self.assertEqual(first["severity"], "error")
        self.assertEqual(first["line"], 1)
        self.assertEqual(first["column"], 20)
        self.assertEqual(first["expect"]["kind"], "function")
        self.assertEqual(first["expect"]["value"], "printInt")

    def test_short_format_is_line_oriented(self):
        bad = self.write("bad2.lir", 'fn main() -> i64 { let x: i64 = "s" return x }\n')
        result = run("check", str(bad), "--diagnostics=short", ok=False)
        line = result.stderr.splitlines()[0]
        self.assertTrue(line.startswith("LIR-E3004 "))
        self.assertIn("error", line)
        self.assertIn("type", line)

    def test_help_line_present_for_actionable_errors(self):
        bad = self.write("bad3.lir", 'fn main() -> i64 { let x: i64 = "s" return x }\n')
        result = run("check", str(bad), ok=False)
        self.assertIn("error[LIR-E3004]", result.stderr)
        self.assertIn("= help:", result.stderr)
        self.assertIn("'string'", result.stderr)
        self.assertIn("'i64'", result.stderr)

    def test_codes_are_explained(self):
        for query in ("LIR-E3004", "e3001", "3002", "LIR-2001"):
            out = run("explain", query).stdout
            self.assertIn("===", out)
        listed = json.loads(run("explain", "--list", "--json").stdout)
        self.assertEqual(listed["schema"], "lir.explain.v1")
        self.assertGreaterEqual(len(listed["topics"]), 12)
        self.assertGreaterEqual(len(listed["codes"]), 10)

    def test_build_json_envelope(self):
        src = self.write("app.lir", "fn main() -> i64 { return 3 }\n")
        target = self.dir / "app.out"
        doc = json.loads(run("build", str(src), "-o", str(target), "--json").stdout)
        self.assertEqual(doc["schema"], "lir.build.v1")
        self.assertEqual(doc["status"], "ok")
        self.assertEqual(doc["backend"], "native-elf")
        self.assertGreater(doc["bytes"], 0)
        self.assertTrue(target.exists())

    def test_explain_ai_mentions_contracts(self):
        out = run("explain", "ai").stdout
        for needle in ("lir lang --json", "lir check", "lir.diagnostics", "--backend=vm"):
            self.assertIn(needle, out)
        limitations = run("explain", "limitations").stdout
        for needle in ("async", "unsafe", "extern", "i128", "char"):
            self.assertIn(needle, limitations)


class CanonicalTourTests(unittest.TestCase):
    """The tour is the reference program: every documented feature in one file.

    It must run identically on the IR VM, the native ELF backend and the C11
    backend — that is the cross-backend semantic baseline for generated code.
    """

    EXPECTED = """control total=10 label=big down=2
comptime fib(10)=55 limit=9
36
44

1
2

16
9
7
0
25

7
9
-1
5

10

9
3
3

4

42

55

deferred-first
deferred-last
"""

    def test_tour_is_consistent_across_backends(self):
        repo = COMPILER.parent.parent.parent
        tour = repo / "examples" / "canonical-tour.lir"
        self.assertTrue(tour.exists(), f"missing {tour}")
        for backend in ("vm", "native", "c"):
            with self.subTest(backend=backend):
                result = run("run", str(tour), f"--backend={backend}")
                self.assertEqual(result.stdout, self.EXPECTED,
                                 f"{backend} output diverged")
                self.assertEqual(result.returncode, 0)

    def test_tour_exit_code(self):
        repo = COMPILER.parent.parent.parent
        tour = repo / "examples" / "canonical-tour.lir"
        # main returns min(total,100)-10 == 0
        self.assertEqual(run("run", str(tour), "--backend=vm").returncode, 0)


class ScaffoldTests(unittest.TestCase):
    def test_init_ai_writes_agent_files(self):
        with tempfile.TemporaryDirectory(prefix="lir-ai-init-") as temp:
            result = run("init", "demo", "--ai", cwd=temp)
            root = pathlib.Path(temp) / "demo"
            self.assertTrue((root / "AGENTS.md").exists())
            manifest_path = root / "lir.agent.json"
            self.assertTrue(manifest_path.exists())
            manifest = json.loads(manifest_path.read_text())
            self.assertEqual(manifest["schema"], "lir.agent.v1")
            self.assertTrue(manifest["validate_before_claiming_success"])
            guide = (root / "AGENTS.md").read_text()
            for needle in ("lir lang --json", "lir check", "lir builtins",
                           "lir lang --keywords"):
                self.assertIn(needle, guide)
            # The scaffolded project must build, run and test cleanly.
            self.assertEqual(run("check", cwd=root).returncode, 0)
            self.assertIn("Hello from LIR", run("run", cwd=root).stdout)
            self.assertIn("PASS", run("test", cwd=root).stdout)
            self.assertIn("AGENTS.md", result.stdout)


if __name__ == "__main__":
    # `ok=None` means "accept any exit status"; run() only asserts when ok is bool.
    unittest.main(verbosity=2)
