#!/usr/bin/env python3
"""Phase 0 audit: verifies isolation/reporting/fixture contracts for NOEMA v3.

This script is a deterministic guardrail, not a capability benchmark.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ERRORS: list[str] = []


def check(condition: bool, msg: str) -> None:
    if condition:
        print(f"OK  {msg}")
    else:
        print(f"FAIL {msg}")
        ERRORS.append(msg)


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def load_json(path: str):
    return json.loads(read(path))


def main() -> int:
    # 1) Legacy backend must report legacy output_mode, never v3 weight generation.
    backend = read("ai/chat_site_backend.lir")
    check("output_mode=legacy_retrieval_exemplar" in backend, "legacy backend emits legacy_retrieval_exemplar")
    check("noema_v3_weight_generation" not in backend, "legacy backend does not emit noema_v3_weight_generation")

    server = read("apps/noema-chat/server.mjs")
    check("values.output_mode" in server, "server reads output_mode from backend")
    check("legacy_retrieval_exemplar" in server, "server has legacy fallback/output mode")
    check("output_mode_contract" in server, "health endpoint exposes output_mode_contract")

    # 2) Isolation markers present.
    for path, marker in [
        ("ai/src/noema_pretrain.lir", "LEGACY / ISOLATED (NOEMA v3 Phase 0)"),
        ("ai/src/noema_decoder.lir", "LEGACY / ISOLATED (NOEMA v3 Phase 0)"),
        ("ai/src/noema_v3/noema_v3_contract.lir", "NOEMA_V3_OUTPUT_WEIGHT_GENERATION"),
    ]:
        check(marker in read(path), f"isolation/contract marker present: {path}")

    # 3) Manifest schema required fields.
    schema = load_json("ai/noema_v3/data/manifest_schema.json")
    required = set(schema.get("required", []))
    for field in ["source_id", "source_family", "license", "language", "acquired_date",
                  "content_sha256", "content_blake3", "near_duplicate_cluster_id"]:
        check(field in required, f"manifest schema requires {field}")

    # 4) Split policy rules.
    policy = load_json("ai/noema_v3/data/split_policy.json")
    rules = "\n".join(policy.get("rules", []))
    check("source_family" in rules and "near_duplicate_cluster_id" in rules, "split policy enforces family+near-dup isolation")
    check("never by individual row/example" in rules.lower() or "never by individual row" in rules, "split policy forbids row-level split")
    check("Test split is locked" in rules or "locked before autonomous hyperparameter search" in rules, "split policy locks test split")

    # 5) Fixtures present and well-formed.
    for path in [
        "ai/noema_v3/fixtures/future_leakage_negative.json",
        "ai/noema_v3/fixtures/finite_diff_harness.json",
        "ai/noema_v3/fixtures/reasoning_fixtures.json",
        "ai/noema_v3/fixtures/split_audit_cases.json",
    ]:
        obj = load_json(path)
        check(obj.get("version"), f"fixture has version: {path}")
        check(obj.get("name"), f"fixture has name: {path}")

    # 6) Finite-diff threshold.
    fd = load_json("ai/noema_v3/fixtures/finite_diff_harness.json")
    thr = fd.get("threshold", {}).get("max_relative_error")
    check(thr == 1e-5, "finite-diff relative error threshold is 1e-5")

    # 7) Reasoning fixtures contain required kernel classes.
    rf = load_json("ai/noema_v3/fixtures/reasoning_fixtures.json")
    kernels = {f.get("kernel") for f in rf.get("fixtures", [])}
    for k in ["bigint_rational", "si_unit_algebra", "constraint_logic", "temporal_consistency", "evidence_gate", "provenance_isolation"]:
        check(k in kernels, f"reasoning fixture covers kernel {k}")

    # 8) Split audit has pass and fail cases.
    sa = load_json("ai/noema_v3/fixtures/split_audit_cases.json")
    outcomes = {c.get("expected", {}).get("pass") for c in sa.get("cases", [])}
    check(True in outcomes and False in outcomes, "split audit has both pass and fail cases")

    # 9) Manifest/SOA guard executable and self-test passes.
    guard = ROOT / "ai/noema_v3/manifest_guard.py"
    check(guard.exists(), "manifest_guard.py exists")
    if guard.exists():
        import subprocess
        r = subprocess.run([sys.executable, str(guard), "--self-test"], cwd=ROOT, capture_output=True, text=True)
        check(r.returncode == 0, "manifest_guard --self-test passes")
        if r.returncode != 0:
            print(r.stdout)
            print(r.stderr)
        sample_soa = ROOT / "ai/noema_v3/fixtures/soa_shard_sample"
        if sample_soa.exists():
            r2 = subprocess.run([sys.executable, str(guard), "--soa-dir", str(sample_soa)], cwd=ROOT, capture_output=True, text=True)
            check(r2.returncode == 0, "manifest_guard validates sample SoA shard fixture")
            if r2.returncode != 0:
                print(r2.stdout)
                print(r2.stderr)
        sample_manifest = ROOT / "ai/noema_v3/fixtures/sample_manifest.jsonl"
        if sample_manifest.exists():
            r3 = subprocess.run([sys.executable, str(guard), "--manifest", str(sample_manifest), "--audit-split"], cwd=ROOT, capture_output=True, text=True)
            check(r3.returncode == 0, "manifest_guard validates sample manifest fixture")
            if r3.returncode != 0:
                print(r3.stdout)
                print(r3.stderr)

    print(f"\n{'PASS' if not ERRORS else 'FAIL'}: {len(ERRORS)} error(s)")
    return 1 if ERRORS else 0


if __name__ == "__main__":
    raise SystemExit(main())
