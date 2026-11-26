#!/usr/bin/env python3
"""
NOEMA v3 Phase 8 Gate Audit:
  1. Static purity & zero-keyword routing enforcement on `noema_v3_proof_search.lir`.
  2. Differential execution of `ai/tests/noema_v3_11_phase8_proof_search.lir` across `native`, `vm`, and `c`.
  3. Live `ai/noema_v3_chat_backend.lir` symbolic claim verification & refutation telemetry.
"""
from __future__ import annotations

import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
LIR_BIN = ROOT / "zig-out" / "bin" / "lir"
ERRORS: list[str] = []
CHECKS = 0


def check(cond: bool, msg: str) -> None:
    global CHECKS
    CHECKS += 1
    if cond:
        print(f"  [OK]   {msg}")
    else:
        print(f"  [FAIL] {msg}")
        ERRORS.append(msg)


def run_v3_backend(prompt: str) -> dict[str, str]:
    proc = subprocess.run(
        [str(LIR_BIN), "run", "--backend=native", "ai/noema_v3_chat_backend.lir"],
        input=f"noema_v3\n{prompt}",
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    kv = {}
    for line in proc.stdout.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            kv[k.strip()] = v.strip()
    return kv


def main() -> int:
    print("=== NOEMA v3 Phase 8 Audit ===")

    ps_lir = (ROOT / "ai" / "src" / "noema_v3" / "noema_v3_proof_search.lir").read_text(encoding="utf-8")
    check("nv3_regime_head_fwd_bwd" in ps_lir, "Trainable neural epistemic regime proposal head present")
    check("nv3_proof_guided_search_candidates" in ps_lir, "K-branch proof-guided backtracking search present")
    check("NOEMA_V3_OUTPUT_WEIGHT_GENERATION_ABSTAIN" in ps_lir, "Honest epistemic abstention fallback present")

    # Verify zero natural-language keyword heuristics inside regime feature extractor
    feat_fn = ps_lir.split("fn nv3_regime_extract_byte_features", 1)[1].split("fn nv3_regime_head_init", 1)[0]
    check("@string_eq" not in feat_fn and '"' not in feat_fn, "nv3_regime_extract_byte_features contains zero string/keyword literals")

    for banned in ["noema_pretrain.lir", "noema_decoder.lir", "chat_site_backend.lir"]:
        check(banned not in ps_lir, f"noema_v3_proof_search.lir has zero reference to legacy {banned}")

    # Differential execution across native, vm, c
    expected_p8 = (ROOT / "ai" / "tests" / "noema_v3_11_phase8_proof_search.expected").read_text(encoding="utf-8").strip()
    for backend in ["native", "vm", "c"]:
        p8 = subprocess.run(
            [str(LIR_BIN), "run", f"--backend={backend}", "ai/tests/noema_v3_11_phase8_proof_search.lir"],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        check(
            p8.returncode == 0 and p8.stdout.strip() == expected_p8,
            f"noema_v3_11_phase8_proof_search.lir passes bit-identically on {backend}",
        )

    # Live chat backend proof telemetry on verified vs refuted claims
    kv_ver = run_v3_backend("1/3 + 1/6 = 1/2; 2 km = 2000 m; A=>B, A |- B")
    check(
        kv_ver.get("ok") == "1" and kv_ver.get("proof_verified_claims") == "3" and kv_ver.get("proof_refuted_claims") == "0",
        "noema_v3_chat_backend.lir certifies 3/3 verified multi-domain claims (Rational + SI + Logic)",
    )
    kv_ref = run_v3_backend("1/3 + 1/6 = 2/3; 5 kg = 5 m")
    check(
        kv_ref.get("ok") == "1" and kv_ref.get("proof_refuted_claims") == "2",
        "noema_v3_chat_backend.lir detects and flags 2/2 refuted mathematical/dimensional claims",
    )

    print(f"\nPHASE 8 AUDIT: {CHECKS - len(ERRORS)}/{CHECKS} checks PASS, {len(ERRORS)} errors")
    return 1 if ERRORS else 0


if __name__ == "__main__":
    raise SystemExit(main())
