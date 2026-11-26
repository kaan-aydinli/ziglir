#!/usr/bin/env python3
"""Phase 3 audit: verifies NOEMA v3 Pointer-Addressed KHG graph memory and all 6
pure-LIR step-budgeted deterministic verification kernels (BigInt/Rational,
SI Unit Algebra, Constraint/Logic DPLL + Unsat Core, Temporal Consistency,
Evidence/Abstain Gate, Provenance Isolation), plus zero hardcoded fixture
leakage into runtime modules and differential parity across native, vm, and c.

This script is a deterministic architectural/numerical gate, not a frontier
capability claim ("Ölçmeden İddia Yok").
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIR = ROOT / "zig-out/bin/lir"
ERRORS: list[str] = []
CHECKS = 0

FORBIDDEN_RUNTIME_STRINGS = (
    "noema_pretrain.lir",
    "noema_decoder.lir",
    "reasoning_fixtures.json",
    "Zorblax",
    "99999999999999999999",
    "import torch",
    "import jax",
    "tiktoken",
    "sentencepiece",
    "transformers",
    "faiss",
    "chromadb",
    "@syscall",
    "@tcp_connect",
)


def check(condition: bool, msg: str) -> None:
    global CHECKS
    CHECKS += 1
    if condition:
        print(f"OK  {msg}")
    else:
        print(f"FAIL {msg}")
        ERRORS.append(msg)


def norm_lines(text: str) -> list[str]:
    return [ln.strip() for ln in text.splitlines() if ln.strip()]


def run_cmd(cmd: list[str], timeout: int = 120) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def main() -> int:
    check(LIR.exists(), "zig-out/bin/lir compiler binary exists")
    if not LIR.exists():
        print(f"\nFAIL: {len(ERRORS)} error(s) ({CHECKS} checks)")
        return 1

    phase3_modules = [
        "ai/src/noema_v3/noema_v3_khg.lir",
        "ai/src/noema_v3/noema_v3_verify_math.lir",
        "ai/src/noema_v3/noema_v3_verify_logic.lir",
    ]
    for mod in phase3_modules:
        mod_path = ROOT / mod
        check(mod_path.exists(), f"module exists: {mod}")
        if not mod_path.exists():
            continue
        src = mod_path.read_text(encoding="utf-8")
        non_comment = "\n".join(
            ln for ln in src.splitlines() if not ln.lstrip().startswith("//")
        )
        check(
            all(tok not in non_comment for tok in FORBIDDEN_RUNTIME_STRINGS),
            f"zero external dependency & zero fixture hardcoding in {mod}",
        )
        rc = run_cmd([str(LIR), "check", mod])
        check(rc.returncode == 0, f"lir check passes: {mod}")

    # Verify all 8 reasoning_fixtures.json IDs are exercised in test suite
    rf = json.loads(
        (ROOT / "ai/noema_v3/fixtures/reasoning_fixtures.json").read_text(encoding="utf-8")
    )
    fixture_ids = {f["id"] for f in rf.get("fixtures", [])}
    check(
        len(fixture_ids) == 8,
        "reasoning_fixtures.json contains all 8 deterministic verification contracts",
    )
    t06_src = (ROOT / "ai/tests/noema_v3_06_khg_and_kernels.lir").read_text(encoding="utf-8")
    check(
        all(fid in t06_src for fid in fixture_ids),
        "noema_v3_06_khg_and_kernels.lir exercises all 8 fixture contracts",
    )

    exp_lines = norm_lines(
        (ROOT / "ai/tests/noema_v3_06_khg_and_kernels.expected").read_text(encoding="utf-8")
    )
    rc_chk = run_cmd([str(LIR), "check", "ai/tests/noema_v3_06_khg_and_kernels.lir"])
    check(rc_chk.returncode == 0, "lir check passes: ai/tests/noema_v3_06_khg_and_kernels.lir")

    for backend in ("native", "vm", "c"):
        res = run_cmd(
            [str(LIR), "run", "ai/tests/noema_v3_06_khg_and_kernels.lir", f"--backend={backend}"],
            timeout=120,
        )
        got_lines = norm_lines(res.stdout)
        ok = res.returncode == 0 and got_lines == exp_lines
        check(ok, f"noema_v3_06_khg_and_kernels.lir differential parity on --backend={backend}")
        if not ok:
            print(f"--- [{backend}] rc={res.returncode} ---")
            print("got:", got_lines)
            print("exp:", exp_lines)

    if ERRORS:
        print(f"\nFAIL: {len(ERRORS)} error(s) ({CHECKS} checks)")
        return 1
    print(f"\nPASS: 0 errors ({CHECKS} checks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
