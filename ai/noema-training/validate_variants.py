#!/usr/bin/env python3
"""Structural and leakage audit for the JSONL task-variant corpus."""
from __future__ import annotations
import json
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parent
REQUIRED_VARIANTS = {
    "supervised_dialogue", "preference_pair", "tool_call_cycle", "clarification",
    "grounded_reasoning", "retrieval_grounded", "code_test_repair",
    "safety_refusal_or_confirm", "multimodal_alignment", "temporal_sequence",
    "structured_table_transform", "calibration_judgment",
}
SPLITS = {"train", "dev", "test"}
DECISIONS = {"answer", "ask", "abstain", "tool", "unsupported"}


def _need(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def validate(rows: Iterable[dict[str, Any]]) -> int:
    ids: set[str] = set()
    groups: dict[str, str] = {}
    variants: set[str] = set()
    count = 0
    for n, row in enumerate(rows, 1):
        where = f"record {n}"
        _need(isinstance(row, dict), f"{where}: expected object")
        _need(row.get("schema") == "noema.training_variant.v1", f"{where}: schema mismatch")
        for key in ("id", "group_key", "split", "variant"):
            _need(isinstance(row.get(key), str) and row[key], f"{where}: missing string {key}")
        _need(row["id"] not in ids, f"{where}: duplicate id {row['id']}")
        ids.add(row["id"])
        _need(row["split"] in SPLITS, f"{where}: invalid split")
        group, split = row["group_key"], row["split"]
        _need(group not in groups or groups[group] == split, f"{where}: group leakage for {group}")
        groups[group] = split
        variant = row["variant"]
        variants.add(variant)
        _need(isinstance(row.get("task"), dict) and row["task"].get("family") and row["task"].get("capability"), f"{where}: task metadata missing")
        _need(isinstance(row.get("messages"), list) and row["messages"], f"{where}: messages missing")
        for j, turn in enumerate(row["messages"]):
            _need(isinstance(turn, dict) and turn.get("role") in {"system", "developer", "user", "assistant", "tool"}, f"{where}: invalid message {j}")
            content = turn.get("content")
            _need(isinstance(content, str) or (turn["role"] == "tool" and isinstance(content, dict)), f"{where}: message content has invalid type")
        _need(isinstance(row.get("target"), dict), f"{where}: target missing")
        labels = row.get("labels")
        _need(isinstance(labels, dict) and labels.get("decision") in DECISIONS, f"{where}: invalid decision label")
        provenance = row.get("provenance")
        _need(isinstance(provenance, dict) and provenance.get("source") and provenance.get("license") and provenance.get("review"), f"{where}: provenance incomplete")
        if variant == "preference_pair":
            candidates = row.get("candidates", [])
            _need(len(candidates) >= 2, f"{where}: preference needs at least two candidates")
            _need(len({c.get("rank") for c in candidates}) == len(candidates), f"{where}: candidate ranks must be unique")
            _need(row["target"].get("chosen") != row["target"].get("rejected"), f"{where}: chosen/rejected collide")
        elif variant == "tool_call_cycle":
            _need(row.get("tool_trace", {}).get("verified") is True, f"{where}: tool result must be verified")
            _need(any(m["role"] == "tool" for m in row["messages"]), f"{where}: missing tool result turn")
        elif variant == "grounded_reasoning":
            facts = {f["id"] for f in row.get("context", {}).get("facts", [])}
            _need(bool(row.get("reasoning", {}).get("steps")), f"{where}: reasoning steps missing")
            _need(all(set(s.get("support", [])) <= facts for s in row["reasoning"]["steps"]), f"{where}: dangling evidence reference")
        elif variant == "retrieval_grounded":
            docs = {d["doc_id"] for d in row.get("retrieval", {}).get("documents", [])}
            _need(bool(row.get("citations")), f"{where}: citations missing")
            _need(all(c.get("doc_id") in docs for c in row["citations"]), f"{where}: dangling citation")
        elif variant == "code_test_repair":
            _need(row.get("code", {}).get("test_status") == "passed" and row["code"].get("tests"), f"{where}: code target lacks passing tests")
        elif variant == "safety_refusal_or_confirm":
            _need(row.get("policy", {}).get("action") in {"block_pending_authorization", "refuse", "confirm"}, f"{where}: safety action missing")
        elif variant == "multimodal_alignment":
            parts = row["messages"][0].get("parts", [])
            _need(any(p.get("kind") in {"image_ref", "audio_ref", "video_ref", "spatial_ref"} for p in parts), f"{where}: media part missing")
            _need(bool(row.get("alignment")), f"{where}: alignment annotation missing")
        elif variant == "temporal_sequence":
            seq = row.get("sequence", {})
            _need(len(seq.get("timestamps", [])) == len(seq.get("values", [])) == len(seq.get("missing_mask", [])), f"{where}: sequence lengths disagree")
            _need(seq.get("observed_until") and seq.get("horizon", 0) > 0, f"{where}: temporal boundary/horizon missing")
        elif variant == "structured_table_transform":
            table = row.get("table", {})
            _need(table.get("columns") and table.get("rows") and row.get("program", {}).get("operation"), f"{where}: typed table/program missing")
        elif variant == "calibration_judgment":
            _need(row.get("evaluation", {}).get("expected_behavior") and row["evaluation"].get("rubric"), f"{where}: evaluation rubric missing")
        elif variant in {"supervised_dialogue", "clarification"}:
            _need(isinstance(row["target"].get("text"), str) and row["target"]["text"], f"{where}: target text missing")
        else:
            raise ValueError(f"{where}: unsupported variant {variant!r}")
        count += 1
    _need(variants == REQUIRED_VARIANTS, f"variant coverage mismatch: {sorted(variants ^ REQUIRED_VARIANTS)}")
    return count


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows = []
    with path.open(encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            _need(line.endswith("\n"), f"line {n}: JSONL record must end in newline")
            _need(line.strip() != "", f"line {n}: blank JSONL rows are forbidden")
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise ValueError(f"line {n}: {exc}") from exc
    return rows


def validate_composites(rows: Iterable[dict[str, Any]], atomic: dict[str, dict[str, Any]]) -> int:
    ids: set[str] = set()
    covered: set[str] = set()
    count = 0
    for n, row in enumerate(rows, 1):
        where = f"composite {n}"
        _need(row.get("schema") == "noema.composite_example.v1", f"{where}: invalid schema")
        _need(row.get("id") not in ids, f"{where}: duplicate id")
        ids.add(row["id"])
        components = row.get("components", [])
        _need(len(components) >= 2, f"{where}: needs at least two components")
        combo = [c.get("variant") for c in components]
        _need(combo == row.get("variant_combo"), f"{where}: variant_combo does not match components")
        _need(len(set(combo)) == len(combo), f"{where}: duplicate component variant")
        for component in components:
            _need(component.get("id") in atomic and atomic[component["id"]] == component, f"{where}: component is not an exact atomic example")
            covered.add(component["variant"])
        _need(row.get("composition", {}).get("operator") == "parallel_subtasks", f"{where}: unknown composition operator")
        _need(len(row.get("target", {}).get("items", [])) == len(components), f"{where}: target/component count mismatch")
        count += 1
    _need(covered == REQUIRED_VARIANTS, f"composite coverage mismatch: {sorted(REQUIRED_VARIANTS - covered)}")
    return count


def main() -> None:
    path = ROOT / "turkish_variants.v1.jsonl"
    atomic_rows = read_jsonl(path)
    count = validate(atomic_rows)
    composite_path = ROOT / "turkish_composite_examples.v1.jsonl"
    composite_count = validate_composites(read_jsonl(composite_path), {r["id"]: r for r in atomic_rows})
    print(f"valid atomic JSONL variants={count}; composite examples={composite_count}; covered task families={len(REQUIRED_VARIANTS)}")


if __name__ == "__main__":
    main()
