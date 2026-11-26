#!/usr/bin/env python3
"""
NOEMA v3 Phase 7 Gate Audit:
  1. Universal `<veriayrimi>` topic-delimiter enforcement across legacy pretraining,
     NOEMA v3 SoA ingestion (`nv3_soa_pack_veriayrimi`), Turkish corpora, and Web UI/server.
  2. Static purity & legacy isolation on `noema_v3_scale_mt.lir` + 4-way unrolled linear kernels.
  3. Differential execution of `48_noema_pretrain_plaintext.lir` and
     `noema_v3_10_phase7_mt_multishard.lir` across `native`, `vm`, and `c`.
"""
from __future__ import annotations

import pathlib
import subprocess
import sys

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


def main() -> int:
    print("=== NOEMA v3 Phase 7 Audit ===")

    # 1) <veriayrimi> delimiter audit across codebase & corpora
    pretrain_lir = (ROOT / "ai" / "src" / "noema_pretrain.lir").read_text(encoding="utf-8")
    soa_lir = (ROOT / "ai" / "src" / "noema_v3" / "noema_v3_soa.lir").read_text(encoding="utf-8")
    server_mjs = (ROOT / "apps" / "noema-chat" / "server.mjs").read_text(encoding="utf-8")
    pretrain_html = (ROOT / "apps" / "noema-chat" / "pretraining.html").read_text(encoding="utf-8")
    corp_small = (ROOT / "ai" / "noema-training" / "pretrain_corpus.tr.txt").read_text(encoding="utf-8")
    corp_large = (ROOT / "ai" / "noema-training" / "pretrain_corpus_large.tr.txt").read_text(encoding="utf-8")

    check("np_is_veriayrimi" in pretrain_lir, "noema_pretrain.lir uses <veriayrimi> topic parser")
    check("nv3_soa_pack_veriayrimi" in soa_lir, "noema_v3_soa.lir exposes nv3_soa_pack_veriayrimi")
    check("'<veriayrimi>'" in server_mjs, "apps/noema-chat/server.mjs splits uploads on <veriayrimi>")
    check("&lt;veriayrimi&gt;" in pretrain_html and "\n---\n" not in pretrain_html, "pretraining.html documents <veriayrimi>")
    check("<veriayrimi>" in corp_small and "\n---\n" not in corp_small, "pretrain_corpus.tr.txt uses <veriayrimi> with zero standalone ---")
    check("<veriayrimi>" in corp_large and "\n---\n" not in corp_large, "pretrain_corpus_large.tr.txt uses <veriayrimi> with zero standalone ---")

    # 2) Static purity & kernel unrolling check
    kernels_lir = (ROOT / "ai" / "src" / "noema_v3" / "noema_v3_kernels.lir").read_text(encoding="utf-8")
    mt_lir = (ROOT / "ai" / "src" / "noema_v3" / "noema_v3_scale_mt.lir").read_text(encoding="utf-8")
    check("while (k + 4) <= out_dim" in kernels_lir and "while (o + 4) <= out_dim" in kernels_lir, "noema_v3_kernels.lir uses 4-way unrolled unit-stride linear fwd/bwd")
    check('@thread_create("nv3_dp_worker_main"' in mt_lir and "@thread_join(" in mt_lir, "noema_v3_scale_mt.lir uses native OS thread fork-join")
    check("nv3_soa_stream_window" in mt_lir, "noema_v3_scale_mt.lir implements paged zero-parse document-window streaming")
    for banned in ["noema_pretrain.lir", "noema_decoder.lir", "chat_site_backend.lir"]:
        check(banned not in mt_lir, f"noema_v3_scale_mt.lir has zero reference to legacy {banned}")

    # 3) Differential execution of 48_noema_pretrain_plaintext.lir (<veriayrimi>)
    for backend in ["native", "vm", "c"]:
        p48 = subprocess.run(
            [str(LIR_BIN), "run", f"--backend={backend}", "ai/tests/48_noema_pretrain_plaintext.lir"],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        out48 = "".join(p48.stdout.split())
        check(p48.returncode == 0 and out48 == "4/4", f"48_noema_pretrain_plaintext.lir (<veriayrimi>) passes on {backend}")

    # 4) Differential execution of noema_v3_10_phase7_mt_multishard.lir across native, vm, c
    expected_p7 = (ROOT / "ai" / "tests" / "noema_v3_10_phase7_mt_multishard.expected").read_text(encoding="utf-8").strip()
    for backend in ["native", "vm", "c"]:
        p7 = subprocess.run(
            [str(LIR_BIN), "run", f"--backend={backend}", "ai/tests/noema_v3_10_phase7_mt_multishard.lir"],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        check(
            p7.returncode == 0 and p7.stdout.strip() == expected_p7,
            f"noema_v3_10_phase7_mt_multishard.lir passes bit-identically on {backend}",
        )

    print(f"\nPHASE 7 AUDIT: {CHECKS - len(ERRORS)}/{CHECKS} checks PASS, {len(ERRORS)} errors")
    return 1 if ERRORS else 0


if __name__ == "__main__":
    raise SystemExit(main())
