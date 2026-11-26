# NOEMA v3 Deterministic Fixtures (Phase 0)

These fixtures are **test contracts**, not model training answers and not runtime lookup tables.
They exist to verify isolation, determinism, and kernel correctness.

## Files

- `future_leakage_negative.json` — inference-time future-byte leakage negative cases.
- `finite_diff_harness.json` — central finite-difference gradient check contract (<= 1e-5 relative error).
- `reasoning_fixtures.json` — deterministic kernel fixtures for arithmetic/unit/logic/temporal/abstain/contradiction.
- `split_audit_cases.json` — leakage-free split audit cases (source family / near-duplicate cluster).

## Rules

- Fixtures must be deterministic and versioned.
- Passing a fixture does not imply general capability; it only validates the targeted contract.
- No fixture may be copied into runtime response generation as a hardcoded answer table.
- Test split fixtures used for final reporting must be locked and excluded from tuning.
