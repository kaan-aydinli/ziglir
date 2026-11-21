#!/usr/bin/env python3
"""Deterministic, dependency-free dataset integrity and leakage audit.

This is a release gate for objective checks, not a model-quality or licensing oracle.
It never emits record text in reports; identifiers and hashes only.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable


class AuditError(Exception):
    pass


def _records(path: Path) -> Iterable[tuple[int, dict[str, Any]]]:
    try:
        with path.open(encoding="utf-8") as stream:
            for line_no, raw in enumerate(stream, 1):
                if not raw.strip():
                    continue
                try:
                    value = json.loads(raw)
                except json.JSONDecodeError as exc:
                    raise AuditError(f"{path}:{line_no}: invalid JSON: {exc.msg}") from exc
                if not isinstance(value, dict):
                    raise AuditError(f"{path}:{line_no}: record must be an object")
                yield line_no, value
    except OSError as exc:
        raise AuditError(f"{path}: {exc}") from exc


def _norm(text: str) -> str:
    return re.sub(r"\s+", " ", unicodedata.normalize("NFKC", text).casefold()).strip()


def _texts(row: dict[str, Any]) -> list[str]:
    found: list[str] = []
    if isinstance(row.get("input"), str):
        found.append(row["input"])
    def walk(value: Any) -> None:
        if isinstance(value, dict):
            if value.get("kind") == "text" and isinstance(value.get("text"), str):
                found.append(value["text"])
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)
    walk(row.get("conversation", []))
    # A row can contain the same input through both top-level and conversation fields.
    return sorted({_norm(x) for x in found if len(_norm(x)) >= 24})


def audit(path: Path) -> dict[str, Any]:
    seen_ids: dict[str, int] = {}
    group_splits: dict[str, tuple[str, int]] = {}
    text_splits: dict[str, tuple[str, int, str]] = {}
    split_counts: Counter[str] = Counter()
    family_counts: Counter[str] = Counter()
    language_counts: Counter[str] = Counter()
    findings: list[dict[str, str]] = []
    records = 0

    for line_no, row in _records(path):
        records += 1
        loc = f"{path.name}:{line_no}"
        rid = row.get("id")
        split = row.get("split")
        if not isinstance(rid, str) or not rid.strip():
            findings.append({"severity": "error", "code": "missing_id", "record": loc})
        elif rid in seen_ids:
            findings.append({"severity": "error", "code": "duplicate_id", "record": loc, "first": f"{path.name}:{seen_ids[rid]}"})
        else:
            seen_ids[rid] = line_no
        if not isinstance(split, str) or not split.strip():
            findings.append({"severity": "error", "code": "missing_split", "record": loc})
            split = "<invalid>"
        split_counts[split] += 1

        group = row.get("group_key")
        if isinstance(group, str) and group.strip():
            previous = group_splits.get(group)
            if previous and previous[0] != split:
                findings.append({"severity": "error", "code": "group_split_leakage", "record": loc, "first": f"{path.name}:{previous[1]}"})
            else:
                group_splits[group] = (split, line_no)

        task = row.get("task")
        family = task.get("family") if isinstance(task, dict) else task
        if isinstance(family, str) and family:
            family_counts[family] += 1
        language = row.get("language")
        if isinstance(language, str) and language:
            language_counts[language] += 1

        for text in _texts(row):
            digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
            prior = text_splits.get(digest)
            if prior and prior[0] != split:
                findings.append({"severity": "error", "code": "exact_text_split_leakage", "record": loc, "first": f"{path.name}:{prior[1]}", "text_hash": digest})
            else:
                text_splits[digest] = (split, line_no, rid if isinstance(rid, str) else "")

        provenance = row.get("provenance")
        if not isinstance(provenance, dict):
            findings.append({"severity": "warning", "code": "provenance_not_structured", "record": loc})
        elif not all(isinstance(provenance.get(k), str) and provenance[k].strip() for k in ("source", "license")):
            findings.append({"severity": "error", "code": "missing_source_or_license", "record": loc})

        quality = row.get("quality")
        if isinstance(quality, dict) and quality.get("disagreement") not in (None, "", [], {}):
            findings.append({"severity": "warning", "code": "unresolved_label_disagreement", "record": loc})

    if records == 0:
        raise AuditError(f"{path}: no records")
    findings.sort(key=lambda item: (item["severity"], item["code"], item["record"], item.get("first", "")))
    return {
        "audit_schema": "noema.dataset_audit.v1",
        "dataset": path.name,
        "records": records,
        "split_counts": dict(sorted(split_counts.items())),
        "task_family_counts": dict(sorted(family_counts.items())),
        "language_counts": dict(sorted(language_counts.items())),
        "findings": findings,
        "release_gate": "fail" if any(f["severity"] == "error" for f in findings) else "review" if findings else "pass",
        "limitations": ["No fuzzy or semantic duplicate detection.", "No payload, license, consent authenticity, label truth, privacy, or model-quality verification.", "Warnings require human review; a clean audit is not a quality certification."],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", type=Path, help="JSONL dataset")
    parser.add_argument("--report", type=Path, help="write deterministic JSON report")
    args = parser.parse_args(argv)
    try:
        report = audit(args.dataset)
    except AuditError as exc:
        print(f"INVALID: {exc}", file=sys.stderr)
        return 2
    rendered = json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    if args.report:
        args.report.write_text(rendered, encoding="utf-8")
    print(f"{report['dataset']}: {report['records']} records; gate={report['release_gate']}; findings={len(report['findings'])}")
    for finding in report["findings"]:
        print(f"{finding['severity'].upper()} {finding['code']} {finding['record']}")
    return 1 if report["release_gate"] == "fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
