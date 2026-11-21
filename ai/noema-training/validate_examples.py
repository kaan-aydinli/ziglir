#!/usr/bin/env python3
"""Dependency-free structural validator for NOEMA's illustrative training files.

This validates schemas and cross-record invariants only. It does NOT verify media
payloads, licenses, consent authenticity, labels, proofs, hashes, or model quality.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parent
DATASETS = {
    "examples": ROOT / "example.jsonl",
    "universal": ROOT / "universal_examples.jsonl",
    "outputs": ROOT / "output_examples.jsonl",
    "events": ROOT / "continual_events.jsonl",
}
DECISIONS = {"answer", "ask", "abstain", "tool", "unsupported"}
SPLITS = {"train", "dev", "test", "retention", "redteam"}
EVENT_TYPES = {"observation", "correction", "candidate_update", "evaluation", "promotion", "rejection", "rollback", "deletion"}
EXAMPLE_REQUIRED = {"id", "split", "seed", "task", "input", "context", "target_graph", "target", "evidence", "decision", "validator", "provenance"}
UNIVERSAL_REQUIRED = {"schema", "id", "split", "group_key", "seed", "task", "conversation", "context", "target", "grounding", "evidence", "tools", "safety", "quality", "provenance"}
OUTPUT_REQUIRED = {"schema", "id", "task", "split", "request_ref", "decision", "obligations", "artifacts", "validation", "provenance"}
EVAL_REQUIRED = {"schema", "id", "split", "group_key", "task", "language", "input", "context", "reference", "criterion", "checker", "risk", "provenance"}
MANIFEST_REQUIRED = {"schema", "run_id", "parent_release", "data_manifests", "split_manifest", "generator_versions", "task_families", "modules_to_update", "update_methods", "seed", "compute_budget", "policy_version", "schema_versions", "gate_set", "replay_plan", "artifact_retention", "review_policy"}
EVENT_REQUIRED = {
    "observation": {"event_id", "event_type", "schema_version", "run_id", "timestamp", "provenance_id", "raw_object", "sample_type", "consent"},
    "candidate_update": {"event_id", "event_type", "schema_version", "run_id", "timestamp", "provenance_id", "parent_snapshot", "data_manifest", "algorithm", "seed", "candidate_snapshot"},
    "evaluation": {"event_id", "event_type", "schema_version", "run_id", "timestamp", "provenance_id", "candidate_snapshot", "gate_set", "results", "decision"},
    "promotion": {"event_id", "event_type", "schema_version", "run_id", "timestamp", "provenance_id", "candidate_snapshot", "previous_snapshot", "gate_set", "approver", "signature", "decision"},
    "deletion": {"event_id", "event_type", "schema_version", "run_id", "timestamp", "provenance_id", "subject_ref", "scope", "completion", "tombstone"},
}


class ValidationError(Exception):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def _object(value: Any, where: str) -> dict[str, Any]:
    _require(isinstance(value, dict), f"{where}: expected object")
    return value


def _required(obj: dict[str, Any], keys: Iterable[str], where: str) -> None:
    missing = sorted(set(keys) - obj.keys())
    _require(not missing, f"{where}: missing keys: {', '.join(missing)}")


def _nonempty_string(value: Any, where: str) -> None:
    _require(isinstance(value, str) and bool(value.strip()), f"{where}: expected non-empty string")


def _enum(value: Any, allowed: set[str], where: str) -> None:
    _require(isinstance(value, str) and value in allowed, f"{where}: unsupported value {value!r}")


def _load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    try:
        with path.open(encoding="utf-8") as stream:
            for line_no, raw in enumerate(stream, 1):
                if not raw.strip():
                    continue
                try:
                    value = json.loads(raw)
                except json.JSONDecodeError as exc:
                    raise ValidationError(f"{path}:{line_no}: invalid JSON: {exc.msg}") from exc
                rows.append(_object(value, f"{path}:{line_no}"))
    except OSError as exc:
        raise ValidationError(f"{path}: {exc}") from exc
    _require(bool(rows), f"{path}: no records")
    return rows


def validate_example_rows(rows: list[dict[str, Any]], where: str = "examples") -> None:
    ids: set[str] = set()
    for i, row in enumerate(rows, 1):
        loc = f"{where}:{i}"
        _required(row, EXAMPLE_REQUIRED, loc)
        _nonempty_string(row["id"], f"{loc}.id")
        _require(row["id"] not in ids, f"{loc}: duplicate id {row['id']!r}")
        ids.add(row["id"])
        _enum(row["split"], SPLITS, f"{loc}.split")
        _require(isinstance(row["seed"], int) and not isinstance(row["seed"], bool), f"{loc}.seed: expected integer")
        _nonempty_string(row["task"], f"{loc}.task")
        _require(isinstance(row["input"], str), f"{loc}.input: expected string")
        _require(isinstance(row["context"], dict), f"{loc}.context: expected object")
        _require(isinstance(row["decision"], str), f"{loc}.decision: expected string")
        _require(isinstance(row["evidence"], dict), f"{loc}.evidence: expected object")
        _require(isinstance(row["validator"], dict), f"{loc}.validator: expected object")
        _require(isinstance(row["provenance"], (dict, str)), f"{loc}.provenance: expected object or string")


def validate_universal_rows(rows: list[dict[str, Any]], where: str = "universal") -> None:
    ids: set[str] = set()
    for i, row in enumerate(rows, 1):
        loc = f"{where}:{i}"
        _required(row, UNIVERSAL_REQUIRED, loc)
        _require(row["schema"] == "noema.example.v2", f"{loc}.schema: unsupported schema")
        _nonempty_string(row["id"], f"{loc}.id")
        _require(row["id"] not in ids, f"{loc}: duplicate id {row['id']!r}")
        ids.add(row["id"])
        _enum(row["split"], SPLITS, f"{loc}.split")
        _nonempty_string(row["group_key"], f"{loc}.group_key")
        _require(isinstance(row["task"], dict) and isinstance(row["task"].get("family"), str), f"{loc}.task.family: expected string")
        _require(isinstance(row["conversation"], list) and bool(row["conversation"]), f"{loc}.conversation: expected non-empty list")
        for t, turn in enumerate(row["conversation"]):
            _require(isinstance(turn, dict) and isinstance(turn.get("role"), str), f"{loc}.conversation[{t}]: invalid turn")
            _require(isinstance(turn.get("parts"), list), f"{loc}.conversation[{t}].parts: expected list")
            for p, part in enumerate(turn["parts"]):
                _require(isinstance(part, dict) and isinstance(part.get("kind"), str), f"{loc}.conversation[{t}].parts[{p}]: invalid part")
        _require(isinstance(row["target"], dict), f"{loc}.target: expected object")
        _enum(row["target"].get("decision"), DECISIONS, f"{loc}.target.decision")
        _require(isinstance(row["context"], dict), f"{loc}.context: expected object")
        for key in ("grounding",):
            _require(isinstance(row[key], list), f"{loc}.{key}: expected list")
        for key in ("evidence", "tools", "safety", "quality", "provenance"):
            _require(isinstance(row[key], dict), f"{loc}.{key}: expected object")


def validate_output_rows(rows: list[dict[str, Any]], where: str = "outputs") -> None:
    ids: set[str] = set()
    for i, row in enumerate(rows, 1):
        loc = f"{where}:{i}"
        _required(row, OUTPUT_REQUIRED, loc)
        _require(row["schema"] == "noema.output_example.v1", f"{loc}.schema: unsupported schema")
        _nonempty_string(row["id"], f"{loc}.id")
        _require(row["id"] not in ids, f"{loc}: duplicate id {row['id']!r}")
        ids.add(row["id"])
        _enum(row["split"], SPLITS, f"{loc}.split")
        _enum(row["decision"], DECISIONS, f"{loc}.decision")
        _require(isinstance(row["obligations"], list), f"{loc}.obligations: expected list")
        obligation_ids: set[str] = set()
        evidence_ids: set[str] = set()
        evidence_by_obligation: dict[str, str] = {}
        for j, obligation in enumerate(row["obligations"]):
            _require(isinstance(obligation, dict), f"{loc}.obligations[{j}]: expected object")
            _nonempty_string(obligation.get("obligation_id"), f"{loc}.obligations[{j}].obligation_id")
            _require(obligation["obligation_id"] not in obligation_ids, f"{loc}: duplicate obligation id {obligation['obligation_id']!r}")
            obligation_ids.add(obligation["obligation_id"])
            _nonempty_string(obligation.get("evidence_id"), f"{loc}.obligations[{j}].evidence_id")
            _require(obligation["evidence_id"] not in evidence_ids, f"{loc}: duplicate evidence id {obligation['evidence_id']!r}")
            evidence_ids.add(obligation["evidence_id"])
            evidence_by_obligation[obligation["obligation_id"]] = obligation["evidence_id"]
        _require(isinstance(row["artifacts"], list), f"{loc}.artifacts: expected list")
        if row["decision"] == "unsupported":
            _require(not row["artifacts"], f"{loc}: unsupported output must not claim artifacts")
        for j, artifact in enumerate(row["artifacts"]):
            _required(_object(artifact, f"{loc}.artifacts[{j}]"), {"artifact_id", "kind", "media_type", "payload_ref", "payload_hash", "source_obligations", "source_evidence", "evidence_level", "generator_version", "safety_labels", "user_rights"}, f"{loc}.artifacts[{j}]")
            _require(isinstance(artifact["source_obligations"], list), f"{loc}.artifacts[{j}].source_obligations: expected list")
            for ref_index, ref in enumerate(artifact["source_obligations"]):
                _nonempty_string(ref, f"{loc}.artifacts[{j}].source_obligations[{ref_index}]")
            dangling = set(artifact["source_obligations"]) - obligation_ids
            _require(not dangling, f"{loc}.artifacts[{j}]: unknown obligation refs: {sorted(dangling)}")
            _require(isinstance(artifact["source_evidence"], list), f"{loc}.artifacts[{j}].source_evidence: expected list")
            for ref_index, ref in enumerate(artifact["source_evidence"]):
                _nonempty_string(ref, f"{loc}.artifacts[{j}].source_evidence[{ref_index}]")
            expected_evidence = {evidence_by_obligation[ref] for ref in artifact["source_obligations"] if ref in evidence_by_obligation}
            actual_evidence = set(artifact["source_evidence"])
            _require(actual_evidence == expected_evidence, f"{loc}.artifacts[{j}]: evidence refs do not match obligation refs")
        _require(isinstance(row["validation"], dict), f"{loc}.validation: expected object")


def validate_eval_rows(rows: list[dict[str, Any]], where: str = "capability-eval") -> None:
    ids: set[str] = set()
    for i, row in enumerate(rows, 1):
        loc = f"{where}:{i}"
        _required(row, EVAL_REQUIRED, loc)
        _require(row["schema"] == "noema.capability_eval.v1", f"{loc}.schema: unsupported schema")
        _nonempty_string(row["id"], f"{loc}.id")
        _require(row["id"] not in ids, f"{loc}: duplicate id {row['id']!r}")
        ids.add(row["id"])
        _enum(row["split"], SPLITS, f"{loc}.split")
        _nonempty_string(row["group_key"], f"{loc}.group_key")
        _require(isinstance(row["task"], dict) and isinstance(row["task"].get("family"), str), f"{loc}.task.family: expected string")
        _nonempty_string(row["language"], f"{loc}.language")
        _require(isinstance(row["input"], str), f"{loc}.input: expected string")
        for key in ("context", "reference", "criterion", "checker", "provenance"):
            _require(isinstance(row[key], dict), f"{loc}.{key}: expected object")


def validate_event_rows(rows: list[dict[str, Any]], where: str = "events") -> None:
    ids: set[str] = set()
    for i, row in enumerate(rows, 1):
        loc = f"{where}:{i}"
        _enum(row.get("event_type"), EVENT_TYPES, f"{loc}.event_type")
        event_type = row["event_type"]
        _required(row, EVENT_REQUIRED.get(event_type, {"event_id", "event_type", "schema_version", "run_id", "timestamp", "provenance_id"}), loc)
        _nonempty_string(row["event_id"], f"{loc}.event_id")
        _require(row["event_id"] not in ids, f"{loc}: duplicate event_id {row['event_id']!r}")
        ids.add(row["event_id"])
        _require(isinstance(row["schema_version"], int) and row["schema_version"] > 0, f"{loc}.schema_version: expected positive integer")
        if event_type == "deletion":
            _require(isinstance(row["tombstone"], dict) and "content_included" in row["tombstone"], f"{loc}.tombstone: invalid tombstone")
            _require(row["tombstone"]["content_included"] is False, f"{loc}: tombstone must not include deleted content")


def validate_manifest(path: Path) -> None:
    try:
        manifest = _object(json.loads(path.read_text(encoding="utf-8")), str(path))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidationError(f"{path}: {exc}") from exc
    _required(manifest, MANIFEST_REQUIRED, str(path))
    _require(manifest["schema"] == "noema.training_run.v1", f"{path}.schema: unsupported schema")
    _require(isinstance(manifest["seed"], int), f"{path}.seed: expected integer")
    for key in ("data_manifests", "generator_versions", "task_families", "modules_to_update", "update_methods", "schema_versions"):
        _require(isinstance(manifest[key], list), f"{path}.{key}: expected list")
    budget = _object(manifest["compute_budget"], f"{path}.compute_budget")
    for key, value in budget.items():
        _require(value is None or (isinstance(value, (int, float)) and not isinstance(value, bool) and value >= 0), f"{path}.compute_budget.{key}: expected non-negative number or null")
    review = _object(manifest["review_policy"], f"{path}.review_policy")
    _require(review.get("online_weight_update") is False, f"{path}: example policy must keep online weight update disabled")


def validate_all(base: Path = ROOT) -> list[str]:
    files = {
        "examples": base / "example.jsonl",
        "universal": base / "universal_examples.jsonl",
        "outputs": base / "output_examples.jsonl",
        "capability-eval": base / "capability_eval.example.jsonl",
        "events": base / "continual_events.jsonl",
    }
    validators = {
        "examples": validate_example_rows,
        "universal": validate_universal_rows,
        "outputs": validate_output_rows,
        "capability-eval": validate_eval_rows,
        "events": validate_event_rows,
    }
    messages: list[str] = []
    for name, path in files.items():
        rows = _load_jsonl(path)
        validators[name](rows, str(path))
        messages.append(f"{path.name}: {len(rows)} records OK")
    manifest = base / "run_manifest.example.json"
    validate_manifest(manifest)
    messages.append(f"{manifest.name}: valid")
    return messages


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=ROOT, help="directory containing the example files")
    args = parser.parse_args(argv)
    try:
        for message in validate_all(args.directory):
            print(message)
    except ValidationError as exc:
        print(f"INVALID: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
