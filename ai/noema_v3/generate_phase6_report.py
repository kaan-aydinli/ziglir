#!/usr/bin/env python3
"""
NOEMA v3 Phase 6 — Candidate Training, Lexicographic Q-Gate Promotion &
Pointer-Addressed KHG Grounding Report Generator.
"""

import hashlib
import json
import pathlib
import struct
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
LIR_BIN = ROOT / "zig-out" / "bin" / "lir"
PROMOTE_CLI = ROOT / "ai" / "noema_v3_promote_cli.lir"
BASE_CKPT = ROOT / "ai" / "noema_v3" / "checkpoints" / "noema_v3_locked.npg3"
PROM_CKPT = ROOT / "ai" / "noema_v3" / "checkpoints" / "noema_v3_promoted.npg3"
REPORT_OUT = ROOT / "ai" / "noema_v3" / "reports" / "phase6_promotion_report.json"


def sha256_file(p: pathlib.Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def parse_kv(stdout: str) -> dict:
    lines = [ln.strip() for ln in stdout.splitlines() if ln.strip()]
    if not lines or lines[0] != "NOEMA_V3_PROMOTE_REPORT_V1":
        raise RuntimeError(f"Unexpected promote CLI header: {lines[:3]}")
    kv = {}
    for ln in lines[1:]:
        if "=" in ln:
            k, v = ln.split("=", 1)
            kv[k.strip()] = v.strip()
    return kv


def main() -> int:
    run = subprocess.run(
        [str(LIR_BIN), "run", "--backend=native", str(PROMOTE_CLI)],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
    )
    if run.returncode != 0:
        raise RuntimeError(f"noema_v3_promote_cli failed ({run.returncode}):\n{run.stdout}\n{run.stderr}")

    kv = parse_kv(run.stdout)
    if kv.get("ok") != "1" or kv.get("promoted") != "1" or kv.get("masking_regression_blocked") != "1":
        raise RuntimeError(f"Promotion invariant check failed: {kv}")

    raw_prom = PROM_CKPT.read_bytes()
    if len(raw_prom) < 88 or raw_prom[:8] != b"NPGv3\x00\x03\x00":
        raise RuntimeError("Invalid promoted NPG-v3 magic or header length")
    schema_ver = struct.unpack_from("<Q", raw_prom, 8)[0]
    if schema_ver != 3:
        raise RuntimeError(f"Unexpected promoted NPG-v3 schema version: {schema_ver}")

    REPORT_OUT.parent.mkdir(parents=True, exist_ok=True)
    report = {
        "schema": "noema_v3.phase6_promotion_report.v1",
        "claim_policy": "measured_internal_locked_benchmark_only_no_unmeasured_frontier_claim",
        "base_checkpoint": {
            "path": "ai/noema_v3/checkpoints/noema_v3_locked.npg3",
            "sha256": sha256_file(BASE_CKPT),
            "steps": int(kv["base_steps"]),
            "locked_test_bpb": float(kv["base_test_bpb"]),
            "locked_test_ece": float(kv["base_test_ece"]),
        },
        "promoted_checkpoint": {
            "path": "ai/noema_v3/checkpoints/noema_v3_promoted.npg3",
            "magic_hex": raw_prom[:8].hex(),
            "schema_version": schema_ver,
            "byte_size": len(raw_prom),
            "sha256": sha256_file(PROM_CKPT),
            "steps": int(kv["cand_steps"]),
            "locked_test_bpb": float(kv["cand_test_bpb"]),
            "locked_test_ece": float(kv["cand_test_ece"]),
            "bpb_delta_vs_base": round(float(kv["cand_test_bpb"]) - float(kv["base_test_bpb"]), 6),
            "ece_delta_vs_base": round(float(kv["cand_test_ece"]) - float(kv["base_test_ece"]), 6),
        },
        "lexicographic_promotion_gate": {
            "promoted": kv["promoted"] == "1",
            "lex_cmp": int(kv["lex_cmp"]),
            "upper_gate_masking_regression_blocked": kv["masking_regression_blocked"] == "1",
            "candidate_q_vector": {
                "q0_integrity_safety": float(kv["cand_q0_safety"]),
                "q1_verified_reasoning": float(kv["cand_q1_reasoning"]),
                "q2_unsupported_claim_rate": float(kv["cand_q2_unsupported"]),
                "q3_compositional_gen": float(kv["cand_q3_compositional"]),
                "q4_calibration_ece": float(kv["cand_test_ece"]),
                "q5_heldout_bpb": float(kv["cand_test_bpb"]),
                "q6_compute_cost_ms": float(kv["cand_compute_ms"]),
            },
        },
    }
    REPORT_OUT.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(
        f"WROTE {REPORT_OUT.relative_to(ROOT)} "
        f"(base_bpb={kv['base_test_bpb']} -> cand_bpb={kv['cand_test_bpb']}, "
        f"base_ece={kv['base_test_ece']} -> cand_ece={kv['cand_test_ece']})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
