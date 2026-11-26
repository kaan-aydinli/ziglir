#!/usr/bin/env python3
"""
NOEMA v3 Phase 6 Gate Audit:
  1. Static purity & legacy isolation across noema_v3_ground_promote.lir,
     noema_v3_promote_cli.lir, noema_v3_chat_backend.lir, and noema_v3_09_grounding_and_promotion.lir.
  2. Promoted NPG-v3 binary checkpoint header & SHA-256 consistency against phase6_promotion_report.json.
  3. Strict lexicographic Q-vector dominance (test_bpb & test_ece both strictly improved over Phase 5)
     and upper-gate masking prohibition.
  4. Differential execution of ai/tests/noema_v3_09_grounding_and_promotion.lir across native, vm, and c.
  5. Live HTTP verification of KHG pointer-addressed grounding telemetry (khgObservedSpans > 0,
     noSpanCopyVerified == 1, storedExemplars == 0) in apps/noema-chat/server.mjs.
"""

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


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def main() -> int:
    print("=== NOEMA v3 Phase 6 Audit ===")

    # 1) Static purity & legacy isolation
    p6_files = [
        ROOT / "ai" / "src" / "noema_v3" / "noema_v3_ground_promote.lir",
        ROOT / "ai" / "noema_v3_promote_cli.lir",
        ROOT / "ai" / "noema_v3_chat_backend.lir",
        ROOT / "ai" / "tests" / "noema_v3_09_grounding_and_promotion.lir",
    ]
    forbidden = [
        "noema_pretrain",
        "noema_decoder",
        ".nps\"",
        "torch",
        "tiktoken",
        "sentencepiece",
        "chromadb",
        "faiss",
    ]
    for fp in p6_files:
        check(fp.exists(), f"exists: {fp.relative_to(ROOT)}")
        if fp.exists():
            code = "\n".join(
                ln for ln in fp.read_text(encoding="utf-8").splitlines() if not ln.lstrip().startswith("//")
            )
            bad = [tok for tok in forbidden if tok in code]
            check(len(bad) == 0, f"purity & zero legacy/external imports in {fp.name} (bad={bad})")
            rc = subprocess.run([str(LIR_BIN), "check", str(fp)], cwd=ROOT, capture_output=True)
            check(rc.returncode == 0, f"lir check passes: {fp.relative_to(ROOT)}")

    # 2) Promoted NPG-v3 checkpoint & phase6_promotion_report.json invariants
    base_ckpt = ROOT / "ai" / "noema_v3" / "checkpoints" / "noema_v3_locked.npg3"
    prom_ckpt = ROOT / "ai" / "noema_v3" / "checkpoints" / "noema_v3_promoted.npg3"
    rep_path = ROOT / "ai" / "noema_v3" / "reports" / "phase6_promotion_report.json"
    check(prom_ckpt.exists(), "promoted NPG-v3 checkpoint exists")
    check(rep_path.exists(), "phase6_promotion_report.json exists")
    if prom_ckpt.exists() and rep_path.exists():
        raw = prom_ckpt.read_bytes()
        rep = json.loads(rep_path.read_text(encoding="utf-8"))
        check(len(raw) >= 88 and raw[:8] == b"NPGv3\x00\x03\x00", "promoted NPG-v3 binary magic valid")
        ver = struct.unpack_from("<Q", raw, 8)[0]
        check(ver == 3, "promoted NPG-v3 schema_version == 3")
        check(rep["base_checkpoint"]["sha256"] == sha256_file(base_ckpt), "base checkpoint SHA-256 matches report")
        check(rep["promoted_checkpoint"]["sha256"] == sha256_file(prom_ckpt), "promoted checkpoint SHA-256 matches report")
        check(
            rep["promoted_checkpoint"]["locked_test_bpb"] < rep["base_checkpoint"]["locked_test_bpb"] - 0.20,
            f"locked test bpb improved > 0.20 bpb ({rep['base_checkpoint']['locked_test_bpb']} -> {rep['promoted_checkpoint']['locked_test_bpb']})",
        )
        check(
            rep["promoted_checkpoint"]["locked_test_ece"] < rep["base_checkpoint"]["locked_test_ece"],
            f"locked test ECE improved ({rep['base_checkpoint']['locked_test_ece']} -> {rep['promoted_checkpoint']['locked_test_ece']})",
        )
        gate = rep["lexicographic_promotion_gate"]
        check(gate["promoted"] is True and gate["lex_cmp"] == 1, "lexicographic Q promotion succeeded")
        check(gate["upper_gate_masking_regression_blocked"] is True, "upper-gate regression masking blocked")

    # 3) Differential execution across native, vm, and c
    exp = (ROOT / "ai" / "tests" / "noema_v3_09_grounding_and_promotion.expected").read_text(encoding="utf-8")
    for backend in ("native", "vm", "c"):
        r = subprocess.run(
            [str(LIR_BIN), "run", f"--backend={backend}", "ai/tests/noema_v3_09_grounding_and_promotion.lir"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        check(
            r.returncode == 0 and r.stdout == exp,
            f"noema_v3_09_grounding_and_promotion matches expected on --backend={backend}",
        )

    # 4) Live HTTP check on apps/noema-chat/server.mjs for KHG pointer grounding & zero span copy
    port = free_port()
    env = dict(os.environ, PORT=str(port), LIR_BIN=str(LIR_BIN))
    srv = subprocess.Popen(
        ["node", "apps/noema-chat/server.mjs"],
        cwd=ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        base = f"http://127.0.0.1:{port}"
        health = None
        for _ in range(30):
            try:
                with urllib.request.urlopen(base + "/api/health", timeout=2) as resp:
                    health = json.loads(resp.read().decode("utf-8"))
                    break
            except Exception:
                time.sleep(0.15)
        check(health is not None and health.get("ok") is True, "/api/health responds ok=true")
        if health:
            models = {m["id"]: m for m in health.get("models", [])}
            check(
                models.get("noema_v3", {}).get("fileName") == "noema_v3_promoted.npg3",
                "/api/health resolves noema_v3 to Q-promoted noema_v3_promoted.npg3",
            )
            req = urllib.request.Request(
                base + "/api/chat",
                data=json.dumps({"modelId": "noema_v3", "message": "İlke: Kuvvet kütle"}).encode("utf-8"),
                headers={"content-type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=15) as resp:
                chat = json.loads(resp.read().decode("utf-8"))
            m = chat.get("metrics", {})
            check(
                m.get("outputMode") == "noema_v3_weight_generation"
                and m.get("khgObservedSpans", 0) >= 1
                and m.get("khgVerifiedSpans", 0) >= 1
                and m.get("noSpanCopyVerified") == 1
                and m.get("storedExemplars") == 0
                and m.get("trainingRecords") == 48,
                "/api/chat serves Q-promoted 48-step NPG-v3 with KHG pointer grounding & verified zero span copy",
            )
    finally:
        srv.terminate()
        try:
            srv.wait(timeout=5)
        except subprocess.TimeoutExpired:
            srv.kill()

    print(f"\n{'PASS' if not ERRORS else 'FAIL'}: {len(ERRORS)} error(s) across {CHECKS} checks")
    return 1 if ERRORS else 0


if __name__ == "__main__":
    raise SystemExit(main())
