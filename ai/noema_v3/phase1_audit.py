#!/usr/bin/env python3
"""Phase 1 audit: verifies NOEMA v3 pure-LIR kernels, central finite-diff gate,
fp32 Householder-Delta HAIB, two-level segment checkpointing, causality/reset
isolation, and LIR-PreOpt fail-closed + raw-UTF-8 micro-block step invariants.

This script is a deterministic architectural/numerical gate, not a frontier
capability claim ("Ölçmeden İddia Yok").
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIR = ROOT / "zig-out/bin/lir"
ERRORS: list[str] = []
CHECKS = 0


def check(condition: bool, msg: str) -> None:
    global CHECKS
    CHECKS += 1
    if condition:
        print(f"OK  {msg}")
    else:
        print(f"FAIL {msg}")
        ERRORS.append(msg)


def run_lir(args: list[str], timeout: int = 90) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(LIR), *args],
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

    # 1) All NOEMA v3 Phase 0 + Phase 1 LIR modules must compile-check cleanly
    #    and remain strictly isolated from legacy retrieval/decoder modules.
    v3_modules = [
        "ai/src/noema_v3/noema_v3_contract.lir",
        "ai/src/noema_v3/noema_v3_math.lir",
        "ai/src/noema_v3/noema_v3_kernels.lir",
        "ai/src/noema_v3/noema_v3_haib.lir",
        "ai/src/noema_v3/noema_v3_seg_ckpt.lir",
        "ai/src/noema_v3/noema_v3_preopt.lir",
    ]
    for mod in v3_modules:
        mod_path = ROOT / mod
        check(mod_path.exists(), f"module exists: {mod}")
        if not mod_path.exists():
            continue
        src = mod_path.read_text(encoding="utf-8")
        non_comment = "\n".join(
            ln for ln in src.splitlines() if not ln.lstrip().startswith("//")
        )
        check(
            "noema_pretrain.lir" not in non_comment
            and "noema_decoder.lir" not in non_comment,
            f"legacy isolation preserved in {mod}",
        )
        rc = run_lir(["check", mod])
        check(rc.returncode == 0, f"lir check passes: {mod}")

    # 2) Central finite-difference gate against finite_diff_harness.json contract
    fd_contract = json.loads(
        (ROOT / "ai/noema_v3/fixtures/finite_diff_harness.json").read_text(encoding="utf-8")
    )
    required_kernels = set(fd_contract["harness_contract"]["required_kernels_phase1"])
    check(
        fd_contract["threshold"]["max_relative_error"] == 1e-5,
        "finite_diff_harness.json threshold locked at 1e-5",
    )

    fd_line_re = re.compile(
        r"^FD_CHECK kernel=(\S+) param=(\S+) eps=1e-4 tol=1e-5 pass=([01])"
    )
    for backend in ["native", "vm", "c"]:
        r = run_lir(["run", "ai/tests/noema_v3_01_finite_diff.lir", f"--backend={backend}"])
        check(r.returncode == 0, f"finite-diff harness exits 0 on backend={backend}")
        lines = [ln.strip() for ln in r.stdout.splitlines() if ln.strip()]
        seen_kernels: set[str] = set()
        failed_params: list[str] = []
        for ln in lines:
            m = fd_line_re.match(ln)
            if m:
                k_name, p_name, p_flag = m.group(1), m.group(2), m.group(3)
                if p_flag == "1":
                    seen_kernels.add(k_name)
                else:
                    failed_params.append(f"{k_name}.{p_name}")
        check(
            not failed_params and "ALL_PASS" in lines,
            f"all 21 parameter groups pass <=1e-5 on backend={backend}",
        )
        missing = sorted(required_kernels - seen_kernels)
        check(
            not missing,
            f"all 7 required Phase 1 kernels covered on backend={backend} (missing={missing})",
        )

    # 3) fp32 Householder-Delta HAIB, two-level segment checkpointing, causality & reset isolation
    expected_seg_checks = {
        "fp32_haib_orthogonal_overwrite_and_reset",
        "slot_budget_512_is_25",
        "two_level_f64_matches_full_bwd",
        "two_level_fp32_drift_within_1e5",
        "no_future_leakage_haib_seq",
        "no_future_leakage_causal_conv1d",
        "reset_boundary_blocks_grad_leakage",
    }
    seg_re = re.compile(r"^SEG_HAIB_CHECK test=(\S+) pass=([01])$")
    for backend in ["native", "vm", "c"]:
        r = run_lir(["run", "ai/tests/noema_v3_02_seg_ckpt_haib.lir", f"--backend={backend}"])
        check(r.returncode == 0, f"seg_ckpt_haib suite exits 0 on backend={backend}")
        passed_seg: set[str] = set()
        for ln in r.stdout.splitlines():
            m = seg_re.match(ln.strip())
            if m and m.group(2) == "1":
                passed_seg.add(m.group(1))
        check(
            passed_seg == expected_seg_checks,
            f"all 7 HAIB/two-level-ckpt/causality/reset gates pass on backend={backend}",
        )

    # 4) LIR-PreOpt Newton-Schulz, fail-closed NaN/Inf guard, and raw-UTF-8 micro-block step
    expected_preopt_checks = {
        "newton_schulz_wide_and_tall_ortho",
        "preopt_fail_closed_nan_inf_guard",
        "preopt_lr_warmup_cosine_schedule",
        "provenance_loss_mask_zero_grad",
        "raw_utf8_microblock_bpb_descent",
    }
    preopt_re = re.compile(r"^PREOPT_CHECK test=(\S+) pass=([01])$")
    for backend in ["native", "vm", "c"]:
        r = run_lir(["run", "ai/tests/noema_v3_03_preopt_and_step.lir", f"--backend={backend}"])
        check(r.returncode == 0, f"preopt_and_step suite exits 0 on backend={backend}")
        passed_preopt: set[str] = set()
        for ln in r.stdout.splitlines():
            m = preopt_re.match(ln.strip())
            if m and m.group(2) == "1":
                passed_preopt.add(m.group(1))
        check(
            passed_preopt == expected_preopt_checks,
            f"all 5 LIR-PreOpt & raw-UTF-8 training gates pass on backend={backend}",
        )

    print(f"\n{'PASS' if not ERRORS else 'FAIL'}: {len(ERRORS)} error(s) ({CHECKS} checks)")
    return 1 if ERRORS else 0


if __name__ == "__main__":
    raise SystemExit(main())
