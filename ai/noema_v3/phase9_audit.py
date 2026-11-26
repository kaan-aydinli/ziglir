#!/usr/bin/env python3
"""
NOEMA v3 Phase 9 Gate Audit:
  1. Multi-shard `<veriayrimi>` corpus + `manifest_guard.py` zero-leakage validation.
  2. `noema_v3_scaled.npg3` binary header & SHA-256 match against `phase9_full_benchmark_report.json`.
  3. Side-by-side locked benchmark dominance (`test_bpb`, `test_ece`, `Q`-gate, `12/12` proof suite,
     and strict 'Olcmeden Iddia Yok' `external_frontier_claim == False`).
  4. SHA-256 blinded human-evaluation packet cryptographic commitment & zero model-identity leak.
  5. Differential execution of `noema_v3_12_phase9_scaled_bench.lir` across `native`, `vm`, and `c`.
  6. Live ephemeral-port HTTP check of `apps/noema-chat/server.mjs` (`/pretraining.html` `<veriayrimi>`
     guide + `/api/chat` Phase 8 symbolic proof telemetry).
"""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import socket
import struct
import subprocess
import sys
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
import ai.noema_v3.manifest_guard as mg  # type: ignore

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


def sha256_file(p: pathlib.Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def sha256_str(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def main() -> int:
    print("=== NOEMA v3 Phase 9 Audit ===")

    # 1) Multi-shard <veriayrimi> corpus + manifest split guard
    corp_root = ROOT / "ai" / "noema_v3" / "corpus_v3_multishard"
    manifest_path = corp_root / "manifest_multishard.jsonl"
    entries = mg.load_manifest(manifest_path)
    val_errs = []
    for idx, e in enumerate(entries):
        val_errs.extend(mg.validate_entry(e, idx))
    split_errs = mg.audit_splits(entries)
    check(len(entries) == 24 and len(val_errs) == 0, "manifest_multishard.jsonl schema valid (24 entries)")
    check(len(split_errs) == 0, "Zero exact, near-duplicate, or family/cluster leakage across train/dev/test")

    for sh_name in ["train_shard_0", "train_shard_1", "val_soa", "test_soa"]:
        sh_errs = mg.validate_soa_dir(corp_root / sh_name)
        check(len(sh_errs) == 0, f"NV3D v3 SoA shard {sh_name} passes binary & FNV-1a64 verification")

    # 2) Scaled checkpoint & benchmark report consistency
    report_path = ROOT / "ai" / "noema_v3" / "reports" / "phase9_full_benchmark_report.json"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    scaled_ckpt = ROOT / "ai" / "noema_v3" / "checkpoints" / "noema_v3_scaled.npg3"
    ckpt_raw = scaled_ckpt.read_bytes()
    magic0, magic1, schema_ver = struct.unpack("<IIQ", ckpt_raw[:16])

    check(magic0 == 0x7647504E and magic1 == 0x00030033 and schema_ver == 3, "noema_v3_scaled.npg3 valid NPGv3 header")
    check(sha256_file(scaled_ckpt) == report["scaled_checkpoint"]["sha256"], "noema_v3_scaled.npg3 SHA-256 matches report")
    check(report.get("topic_delimiter") == "<veriayrimi>", "Benchmark report records <veriayrimi> delimiter")

    # 3) Honesty policy & side-by-side locked dominance
    hp = report["honesty_policy"]
    check(hp.get("principle") == "Olcmeden Iddia Yok" and hp.get("external_frontier_claim") is False, "Strict 'Olcmeden Iddia Yok' honesty attestation (external_frontier_claim == False)")
    check(report["worker_determinism"]["grad_max_abs_diff"] < 1e-11, "OS-thread worker gradient determinism < 1e-11")

    sbs = report["side_by_side_comparison"]
    check(sbs["locked_test_bpb_delta"] < -1.0, f"Scaled multi-shard test_bpb improves over baseline by {sbs['locked_test_bpb_delta']} bpb")
    check(sbs["locked_test_ece_delta"] < 0.0, f"Scaled multi-shard test_ece improves over baseline by {sbs['locked_test_ece_delta']}")
    check(report["lexicographic_q_gate"]["q_scaled_pass"] is True, "Scaled checkpoint passes all 7 absolute Q thresholds")
    check(report["lexicographic_q_gate"]["q_lex_scaled_dominates_base"] is True, "Scaled checkpoint strictly dominates unscaled baseline under lexicographic Q")
    check(report["neuro_symbolic_proof_benchmark"]["passed"] == 12 and report["neuro_symbolic_proof_benchmark"]["total"] == 12, "Neuro-symbolic proof benchmark 12/12 PASS")

    # 4) Blinded human-evaluation packet audit
    packet_path = ROOT / "ai" / "noema_v3" / "reports" / "phase9_blind_eval_packet.jsonl"
    key_path = ROOT / "ai" / "noema_v3" / "reports" / "phase9_blind_eval_key_sha256.json"
    packet_txt = packet_path.read_text(encoding="utf-8")
    check(
        "noema_v3_scaled" not in packet_txt and "unscaled_single_shard" not in packet_txt,
        "Blinded human-eval packet contains zero model-identity labels",
    )
    check(sha256_file(packet_path) == report["blind_human_eval_artifacts"]["packet_sha256"], "Blinded packet SHA-256 matches report")

    packet_items = [json.loads(ln) for ln in packet_txt.splitlines() if ln.strip()]
    key_items = json.loads(key_path.read_text(encoding="utf-8"))["items"]
    commit_ok = len(packet_items) == 4 and len(key_items) == 4
    for p_it, k_it in zip(packet_items, key_items):
        recomputed = sha256_str(f"{k_it['item_id']}|A={k_it['option_A_model']}|B={k_it['option_B_model']}|{k_it['salt_prefix']}")
        if recomputed != p_it["assignment_commitment_sha256"]:
            commit_ok = False
    check(commit_ok, "All 4 blinded A/B evaluation pairs verify against salted SHA-256 reveal commitments")

    # 5) Differential execution of noema_v3_12_phase9_scaled_bench.lir across native, vm, c
    expected_p9 = (ROOT / "ai" / "tests" / "noema_v3_12_phase9_scaled_bench.expected").read_text(encoding="utf-8").strip()
    for backend in ["native", "vm", "c"]:
        p9 = subprocess.run(
            [str(LIR_BIN), "run", f"--backend={backend}", "ai/tests/noema_v3_12_phase9_scaled_bench.lir"],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        check(
            p9.returncode == 0 and p9.stdout.strip() == expected_p9,
            f"noema_v3_12_phase9_scaled_bench.lir passes bit-identically on {backend}",
        )

    # 6) Live HTTP verification of <veriayrimi> UI + Phase 8 proof telemetry in apps/noema-chat
    port = free_port()
    env = dict(os.environ, PORT=str(port), HOST="127.0.0.1")
    srv = subprocess.Popen(
        ["node", "apps/noema-chat/server.mjs"],
        cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    try:
        ready = False
        for _ in range(30):
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/health", timeout=2) as r:
                    if r.status == 200:
                        ready = True
                        break
            except Exception:
                time.sleep(0.2)
        check(ready, "apps/noema-chat/server.mjs booted cleanly on ephemeral port")
        if ready:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/pretraining.html", timeout=5) as r:
                html = r.read().decode("utf-8")
            check("&lt;veriayrimi&gt;" in html, "Live /pretraining.html serves <veriayrimi> format guide")

            req = urllib.request.Request(
                f"http://127.0.0.1:{port}/api/chat",
                data=json.dumps({"modelId": "noema_v3", "message": "1/3 + 1/6 = 1/2; 2 km = 2000 m"}).encode("utf-8"),
                headers={"content-type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=15) as r:
                body = json.loads(r.read().decode("utf-8"))
            met = body.get("metrics", {})
            check(
                body.get("ok") is True and met.get("proofVerifiedClaims") == 2 and met.get("proofRefutedClaims") == 0,
                "Live /api/chat returns Phase 8 proofVerifiedClaims=2, proofRefutedClaims=0 on verified claims",
            )
    finally:
        srv.terminate()
        try:
            srv.wait(timeout=5)
        except subprocess.TimeoutExpired:
            srv.kill()

    print(f"\nPHASE 9 AUDIT: {CHECKS - len(ERRORS)}/{CHECKS} checks PASS, {len(ERRORS)} errors")
    return 1 if ERRORS else 0


if __name__ == "__main__":
    raise SystemExit(main())
