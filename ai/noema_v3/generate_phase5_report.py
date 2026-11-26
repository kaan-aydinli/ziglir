#!/usr/bin/env python3
"""
NOEMA v3 Phase 5 — Locked Multi-Domain Pretraining & Q-Vector Benchmark Runner.

Executes pure-LIR training + verified self-play (`ai/noema_v3_train_cli.lir`),
verifies split-disjoint SoA integrity (`manifest_guard.py`), validates NPG-v3
binary header invariants, and emits `ai/noema_v3/reports/phase5_locked_q_report.json`.
"""

import hashlib
import json
import pathlib
import struct
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
LIR_BIN = ROOT / "zig-out" / "bin" / "lir"
TRAIN_CLI = ROOT / "ai" / "noema_v3_train_cli.lir"
MANIFEST = ROOT / "ai" / "noema_v3" / "corpus_locked" / "manifest.jsonl"
CKPT = ROOT / "ai" / "noema_v3" / "checkpoints" / "noema_v3_locked.npg3"
REPORT_OUT = ROOT / "ai" / "noema_v3" / "reports" / "phase5_locked_q_report.json"


def sha256_file(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_kv(stdout: str) -> dict:
    lines = [ln.strip() for ln in stdout.splitlines() if ln.strip()]
    if not lines or lines[0] != "NOEMA_V3_TRAIN_REPORT_V1":
        raise RuntimeError(f"Unexpected train CLI header: {lines[:3]}")
    kv = {}
    for ln in lines[1:]:
        if "=" in ln:
            k, v = ln.split("=", 1)
            kv[k.strip()] = v.strip()
    return kv


def main() -> int:
    # 1. Verify locked corpus manifest + split-disjoint SoA shards
    for split in ("train", "dev", "test"):
        soa_dir = ROOT / "ai" / "noema_v3" / "corpus_locked" / f"{split}_soa"
        p = subprocess.run(
            [
                sys.executable,
                str(ROOT / "ai" / "noema_v3" / "manifest_guard.py"),
                "--manifest",
                str(MANIFEST),
                "--audit-split",
                "--soa-dir",
                str(soa_dir),
            ],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
        )
        if p.returncode != 0:
            raise RuntimeError(f"manifest_guard failed on {split}: {p.stderr or p.stdout}")

    # 2. Run pure-LIR locked training + verified self-play + Q evaluation
    run = subprocess.run(
        [str(LIR_BIN), "run", "--backend=native", str(TRAIN_CLI)],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
    )
    if run.returncode != 0:
        raise RuntimeError(f"noema_v3_train_cli failed ({run.returncode}):\n{run.stdout}\n{run.stderr}")

    kv = parse_kv(run.stdout)
    if kv.get("ok") != "1" or kv.get("q_gate_pass") != "1" or kv.get("all_splits_bpb_improved") != "1":
        raise RuntimeError(f"Q-gate or cross-split bpb improvement failed: {kv}")

    # 3. Validate NPG-v3 binary header (magic 'NPGv3\x00\x03\x00', 88B header, schema_version = 3)
    raw_ckpt = CKPT.read_bytes()
    if len(raw_ckpt) < 88 or raw_ckpt[:8] != b"NPGv3\x00\x03\x00":
        raise RuntimeError(f"Invalid NPG-v3 checkpoint magic or length: {raw_ckpt[:8]!r}")
    schema_ver = struct.unpack_from("<Q", raw_ckpt, 8)[0]
    if schema_ver != 3:
        raise RuntimeError(f"Unexpected NPG-v3 schema version: {schema_ver}")

    REPORT_OUT.parent.mkdir(parents=True, exist_ok=True)
    report = {
        "schema": "noema_v3.locked_q_report.v1",
        "architecture": "NOEMA v3 (EK-HNB + HAIB + KHG + LIR-PreOpt)",
        "implementation": "100% pure LIR (zero external LLM/LMM/tokenizer/optimizer/autodiff)",
        "claim_policy": "measured_internal_locked_benchmark_only_no_unmeasured_frontier_claim",
        "corpus": {
            "manifest_path": "ai/noema_v3/corpus_locked/manifest.jsonl",
            "manifest_sha256": sha256_file(MANIFEST),
            "splits": {
                sp: {
                    "soa_dir": f"ai/noema_v3/corpus_locked/{sp}_soa",
                    "stream_sha256": sha256_file(
                        ROOT / "ai" / "noema_v3" / "corpus_locked" / f"{sp}_soa" / "stream.bin"
                    ),
                }
                for sp in ("train", "dev", "test")
            },
            "split_disjointness_verified": True,
        },
        "checkpoint": {
            "path": "ai/noema_v3/checkpoints/noema_v3_locked.npg3",
            "magic_hex": raw_ckpt[:8].hex(),
            "schema_version": schema_ver,
            "byte_size": len(raw_ckpt),
            "sha256": sha256_file(CKPT),
            "total_params": int(kv["total_params"]),
            "trained_steps": int(kv["trained_steps"]),
        },
        "verified_selfplay": {
            "candidates_total": int(kv["selfplay_total"]),
            "admitted_verified": int(kv["selfplay_admitted"]),
            "rejected_unverified_or_contradicted": int(kv["selfplay_rejected"]),
        },
        "bpb_trajectory": {
            "train": {
                "init": float(kv["train_bpb_init"]),
                "final": float(kv["train_bpb_final"]),
                "delta": round(float(kv["train_bpb_final"]) - float(kv["train_bpb_init"]), 6),
            },
            "dev": {
                "init": float(kv["dev_bpb_init"]),
                "final": float(kv["dev_bpb_final"]),
                "delta": round(float(kv["dev_bpb_final"]) - float(kv["dev_bpb_init"]), 6),
            },
            "test": {
                "init": float(kv["test_bpb_init"]),
                "final": float(kv["test_bpb_final"]),
                "delta": round(float(kv["test_bpb_final"]) - float(kv["test_bpb_init"]), 6),
            },
            "all_splits_improved": kv["all_splits_bpb_improved"] == "1",
        },
        "lexicographic_q_vector": {
            "q0_integrity_safety": float(kv["q0_integrity_safety"]),
            "q1_verified_reasoning": float(kv["q1_verified_reasoning"]),
            "q2_unsupported_claim_rate": float(kv["q2_unsupported_claim_rate"]),
            "q3_compositional_gen": float(kv["q3_compositional_gen"]),
            "q4_calibration_ece": float(kv["q4_calibration_ece_final"]),
            "q5_heldout_bpb": float(kv["q5_heldout_bpb"]),
            "q6_compute_cost_ms": float(kv["q6_compute_cost_ms"]),
            "all_gates_passed": kv["q_gate_pass"] == "1",
            "first_failed_gate": int(kv["q_first_failed_gate"]),
        },
    }
    REPORT_OUT.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"WROTE {REPORT_OUT.relative_to(ROOT)} (test_bpb={report['bpb_trajectory']['test']['final']}, q_pass={report['lexicographic_q_vector']['all_gates_passed']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
