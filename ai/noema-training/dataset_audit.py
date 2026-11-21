#!/usr/bin/env python3
"""Deterministic, dependency-free dataset integrity and leakage audit.

Indexes and counts spill to a temporary SQLite database to keep Python heap use
bounded for large JSONL files. This is an objective integrity gate, not a model-
quality, license-authenticity, consent-authenticity, or semantic-duplicate oracle.
Reports never include record text.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
import sys
import tempfile
import unicodedata
from pathlib import Path
from typing import Any, Iterable

MAX_FINDINGS = 1000
TOP_CATEGORIES = 200
SQLITE_CACHE_KIB = 8192


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
    found: set[str] = set()
    if isinstance(row.get("input"), str):
        normalized = _norm(row["input"])
        if len(normalized) >= 24:
            found.add(normalized)

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            if value.get("kind") == "text" and isinstance(value.get("text"), str):
                normalized = _norm(value["text"])
                if len(normalized) >= 24:
                    found.add(normalized)
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(row.get("conversation", []))
    return sorted(found)


def _add_finding(
    db: sqlite3.Connection,
    details: list[dict[str, str]],
    *, severity: str,
    code: str,
    record: str,
    first: str | None = None,
    text_hash: str | None = None,
) -> None:
    db.execute(
        "INSERT INTO finding_counts(severity, code, count) VALUES (?, ?, 1) "
        "ON CONFLICT(severity, code) DO UPDATE SET count=count+1",
        (severity, code),
    )
    if len(details) < MAX_FINDINGS:
        item = {"severity": severity, "code": code, "record": record}
        if first is not None:
            item["first"] = first
        if text_hash is not None:
            item["text_hash"] = text_hash
        details.append(item)


def _count_value(db: sqlite3.Connection, kind: str, value: str) -> None:
    db.execute(
        "INSERT INTO counts(kind, value, count) VALUES (?, ?, 1) "
        "ON CONFLICT(kind, value) DO UPDATE SET count=count+1",
        (kind, value),
    )


def audit(path: Path) -> dict[str, Any]:
    details: list[dict[str, str]] = []
    records = 0
    with tempfile.TemporaryDirectory(prefix="noema-dataset-audit-") as temp_dir:
        db = sqlite3.connect(str(Path(temp_dir) / "audit.sqlite3"))
        try:
            db.execute(f"PRAGMA cache_size=-{SQLITE_CACHE_KIB}")
            db.execute("PRAGMA temp_store=FILE")
            db.execute("PRAGMA journal_mode=OFF")
            db.execute("PRAGMA synchronous=OFF")
            db.executescript("""
                CREATE TABLE ids (value TEXT PRIMARY KEY, line INTEGER NOT NULL);
                CREATE TABLE groups_seen (value TEXT PRIMARY KEY, split TEXT NOT NULL, line INTEGER NOT NULL);
                CREATE TABLE texts_seen (value TEXT PRIMARY KEY, split TEXT NOT NULL, line INTEGER NOT NULL);
                CREATE TABLE counts (kind TEXT NOT NULL, value TEXT NOT NULL, count INTEGER NOT NULL,
                                     PRIMARY KEY(kind, value));
                CREATE TABLE finding_counts (severity TEXT NOT NULL, code TEXT NOT NULL, count INTEGER NOT NULL,
                                             PRIMARY KEY(severity, code));
            """)
            for line_no, row in _records(path):
                records += 1
                loc = f"{path.name}:{line_no}"
                rid = row.get("id")
                if not isinstance(rid, str) or not rid.strip():
                    _add_finding(db, details, severity="error", code="missing_id", record=loc)
                else:
                    inserted = db.execute("INSERT OR IGNORE INTO ids(value, line) VALUES (?, ?)", (rid, line_no)).rowcount
                    if not inserted:
                        prior = db.execute("SELECT line FROM ids WHERE value=?", (rid,)).fetchone()
                        _add_finding(db, details, severity="error", code="duplicate_id", record=loc, first=f"{path.name}:{prior[0]}")

                split = row.get("split")
                if not isinstance(split, str) or not split.strip():
                    _add_finding(db, details, severity="error", code="missing_split", record=loc)
                    split = "<invalid>"
                _count_value(db, "split", split)

                group = row.get("group_key")
                if isinstance(group, str) and group.strip():
                    inserted = db.execute("INSERT OR IGNORE INTO groups_seen(value, split, line) VALUES (?, ?, ?)", (group, split, line_no)).rowcount
                    if not inserted:
                        prior = db.execute("SELECT split, line FROM groups_seen WHERE value=?", (group,)).fetchone()
                        if prior[0] != split:
                            _add_finding(db, details, severity="error", code="group_split_leakage", record=loc, first=f"{path.name}:{prior[1]}")

                task = row.get("task")
                family = task.get("family") if isinstance(task, dict) else task
                if isinstance(family, str) and family:
                    _count_value(db, "task_family", family)
                language = row.get("language")
                if isinstance(language, str) and language:
                    _count_value(db, "language", language)

                for text in _texts(row):
                    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
                    inserted = db.execute("INSERT OR IGNORE INTO texts_seen(value, split, line) VALUES (?, ?, ?)", (digest, split, line_no)).rowcount
                    if not inserted:
                        prior = db.execute("SELECT split, line FROM texts_seen WHERE value=?", (digest,)).fetchone()
                        if prior[0] != split:
                            _add_finding(db, details, severity="error", code="exact_text_split_leakage", record=loc, first=f"{path.name}:{prior[1]}", text_hash=digest)

                provenance = row.get("provenance")
                if not isinstance(provenance, dict):
                    _add_finding(db, details, severity="warning", code="provenance_not_structured", record=loc)
                elif not all(isinstance(provenance.get(k), str) and provenance[k].strip() for k in ("source", "license")):
                    _add_finding(db, details, severity="error", code="missing_source_or_license", record=loc)

                quality = row.get("quality")
                if isinstance(quality, dict) and quality.get("disagreement") not in (None, "", [], {}):
                    _add_finding(db, details, severity="warning", code="unresolved_label_disagreement", record=loc)

                if records % 5000 == 0:
                    db.commit()
            db.commit()
            if records == 0:
                raise AuditError(f"{path}: no records")

            def summary(kind: str) -> dict[str, int]:
                rows = db.execute(
                    "SELECT value, count FROM counts WHERE kind=? ORDER BY count DESC, value LIMIT ?",
                    (kind, TOP_CATEGORIES),
                ).fetchall()
                return {value: count for value, count in sorted(rows)}

            category_counts = {
                kind: db.execute("SELECT COUNT(*) FROM counts WHERE kind=?", (kind,)).fetchone()[0]
                for kind in ("split", "task_family", "language")
            }
            finding_counts = [
                {"severity": severity, "code": code, "count": count}
                for severity, code, count in db.execute(
                    "SELECT severity, code, count FROM finding_counts ORDER BY severity, code"
                )
            ]
            error_count = sum(item["count"] for item in finding_counts if item["severity"] == "error")
            total_findings = sum(item["count"] for item in finding_counts)
            details.sort(key=lambda item: (item["severity"], item["code"], item["record"], item.get("first", "")))
            return {
                "audit_schema": "noema.dataset_audit.v1",
                "dataset": path.name,
                "records": records,
                "split_counts": summary("split"),
                "task_family_counts": summary("task_family"),
                "language_counts": summary("language"),
                "omitted_category_counts": {kind: max(0, count - TOP_CATEGORIES) for kind, count in category_counts.items()},
                "finding_counts": finding_counts,
                "findings": details,
                "total_findings": total_findings,
                "findings_truncated": total_findings > len(details),
                "release_gate": "fail" if error_count else "review" if total_findings else "pass",
                "index_storage": "temporary-sqlite-disk-spill",
                "python_heap_detail_cap": MAX_FINDINGS,
                "limitations": ["No fuzzy or semantic duplicate detection.", "No payload, license, consent authenticity, label truth, privacy, or model-quality verification.", "Warnings require human review; a clean audit is not a quality certification."],
            }
        finally:
            db.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", type=Path, help="JSONL dataset")
    parser.add_argument("--report", type=Path, help="write deterministic JSON report")
    args = parser.parse_args(argv)
    try:
        report = audit(args.dataset)
    except (AuditError, sqlite3.Error) as exc:
        print(f"INVALID: {exc}", file=sys.stderr)
        return 2
    rendered = json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    if args.report:
        args.report.write_text(rendered, encoding="utf-8")
    print(f"{report['dataset']}: {report['records']} records; gate={report['release_gate']}; findings={report['total_findings']}")
    for finding in report["findings"]:
        print(f"{finding['severity'].upper()} {finding['code']} {finding['record']}")
    if report["findings_truncated"]:
        print(f"NOTE findings truncated to first {MAX_FINDINGS}; full counts are in the report")
    return 1 if report["release_gate"] == "fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
