#!/usr/bin/env python3
"""Phase 2 audit: verifies NOEMA v3 pure-LIR 3-level EK-HNB causal/folding
backbone, reverse-prompt exact causality (leak_001..003), provenance authority
isolation, SoA NV3D v3 binary ingestion + split audit, NPG-v3 checkpoint
serialization/validation, and raw-UTF-8 held-out bpb descent across native/vm/c.

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

FORBIDDEN_TOKENS = (
    "noema_pretrain.lir",
    "noema_decoder.lir",
    "import torch",
    "import jax",
    "tensorflow",
    "tiktoken",
    "sentencepiece",
    "transformers",
    "onnxruntime",
    "chromadb",
    "faiss",
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

    # 1) Phase 2 LIR modules: existence, zero-external-dependency / legacy isolation, lir check
    phase2_modules = [
        "ai/src/noema_v3/noema_v3_soa.lir",
        "ai/src/noema_v3/noema_v3_ek_hnb.lir",
        "ai/src/noema_v3/noema_v3_checkpoint.lir",
        "ai/src/noema_v3/noema_v3_trainer.lir",
    ]
    for mod in phase2_modules:
        mod_path = ROOT / mod
        check(mod_path.exists(), f"module exists: {mod}")
        if not mod_path.exists():
            continue
        src = mod_path.read_text(encoding="utf-8")
        non_comment = "\n".join(
            ln for ln in src.splitlines() if not ln.lstrip().startswith("//")
        )
        clean_deps = all(tok not in non_comment for tok in FORBIDDEN_TOKENS)
        check(clean_deps, f"zero external dependency & legacy isolation preserved in {mod}")
        rc = run_cmd([str(LIR), "check", mod])
        check(rc.returncode == 0, f"lir check passes: {mod}")

    # 2) Causality negative-test contract coverage (leak_001..003)
    leak_fixture = json.loads(
        (ROOT / "ai/noema_v3/fixtures/future_leakage_negative.json").read_text(encoding="utf-8")
    )
    case_ids = {c["id"] for c in leak_fixture.get("cases", [])}
    check(
        {"leak_001", "leak_002", "leak_003"}.issubset(case_ids),
        "future_leakage_negative.json defines leak_001..003",
    )
    t04_src = (ROOT / "ai/tests/noema_v3_04_ek_hnb_causality.lir").read_text(encoding="utf-8")
    check(
        all(k in t04_src for k in ("leak_001_prompt_only_reverse", "leak_002_future_response_mask", "leak_003_cross_document_reset")),
        "noema_v3_04_ek_hnb_causality.lir exercises leak_001..003",
    )

    # 3) Manifest & NV3D v3 binary SoA shard split audits (train + disjoint heldout)
    for soa_dir in ("ai/noema_v3/fixtures/soa_shard_sample", "ai/noema_v3/fixtures/soa_shard_heldout"):
        mg = run_cmd(
            [
                sys.executable,
                "ai/noema_v3/manifest_guard.py",
                "--manifest",
                "ai/noema_v3/fixtures/phase2_corpus_manifest.jsonl",
                "--audit-split",
                "--soa-dir",
                soa_dir,
            ]
        )
        check(
            mg.returncode == 0,
            f"manifest_guard split + NV3D v3 binary SoA audit passes for {soa_dir}",
        )

    # 4) Differential execution of Phase 2 test suites across native, vm, and c
    phase2_tests = [
        ("ai/tests/noema_v3_04_ek_hnb_causality.lir", "ai/tests/noema_v3_04_ek_hnb_causality.expected"),
        ("ai/tests/noema_v3_05_soa_npg_bpb.lir", "ai/tests/noema_v3_05_soa_npg_bpb.expected"),
    ]
    for lir_test, exp_file in phase2_tests:
        exp_lines = norm_lines((ROOT / exp_file).read_text(encoding="utf-8"))
        rc_chk = run_cmd([str(LIR), "check", lir_test])
        check(rc_chk.returncode == 0, f"lir check passes: {lir_test}")
        for backend in ("native", "vm", "c"):
            res = run_cmd([str(LIR), "run", lir_test, f"--backend={backend}"], timeout=120)
            got_lines = norm_lines(res.stdout)
            ok = res.returncode == 0 and got_lines == exp_lines
            check(ok, f"{lir_test} differential parity on --backend={backend}")
            if not ok:
                print(f"--- {lir_test} [{backend}] rc={res.returncode} ---")
                print("got:", got_lines)
                print("exp:", exp_lines)
                if res.stderr:
                    print("stderr:", res.stderr[:800])

    if ERRORS:
        print(f"\nFAIL: {len(ERRORS)} error(s) ({CHECKS} checks)")
        return 1
    print(f"\nPASS: 0 errors ({CHECKS} checks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
