#!/usr/bin/env python3
"""NOEMA v3 Phase 0 executable guard: manifest validation + split audit + SoA shard contract.

Fail-closed: any integrity violation returns non-zero.
No external dependencies.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import sys
from pathlib import Path
from typing import Any

HEX64 = set("0123456789abcdef")
NV3_DOCS_MAGIC = b"NV3D"
NV3_SCHEMA_VERSION = 3


def fnv1a64_bytes(data: bytes) -> int:
    h = 0xCBF29CE484222325
    for b in data:
        h = ((h ^ b) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def is_hex64(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(c in HEX64 for c in value.lower())


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def load_manifest(path: Path) -> list[dict[str, Any]]:
    text = path.read_text(encoding="utf-8")
    if path.suffix == ".jsonl":
        entries = []
        for i, line in enumerate(text.splitlines(), 1):
            if not line.strip():
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as e:
                raise ValueError(f"{path}:{i}: invalid JSON: {e}") from e
            if not isinstance(obj, dict):
                raise ValueError(f"{path}:{i}: manifest entry must be object")
            entries.append(obj)
        return entries
    obj = json.loads(text)
    if isinstance(obj, list):
        if not all(isinstance(x, dict) for x in obj):
            raise ValueError(f"{path}: manifest list must contain objects")
        return obj
    if isinstance(obj, dict) and isinstance(obj.get("entries"), list):
        entries = obj["entries"]
        if not all(isinstance(x, dict) for x in entries):
            raise ValueError(f"{path}: entries must contain objects")
        return entries
    raise ValueError(f"{path}: expected JSONL, JSON list, or object with entries")


REQUIRED_FIELDS = [
    "source_id", "source_family", "license", "language", "acquired_date",
    "content_sha256", "content_blake3", "near_duplicate_cluster_id", "byte_length", "split_eligibility",
]
SPLITS = {"train", "dev", "test", "excluded"}
PROVENANCE = {"SYSTEM_POLICY", "USER_INPUT", "UNTRUSTED_SOURCE", "VERIFIED_KHG", "HYPOTHESIS"}


def validate_entry(entry: dict[str, Any], idx: int) -> list[str]:
    errs: list[str] = []
    for f in REQUIRED_FIELDS:
        if f not in entry:
            errs.append(f"entry[{idx}]: missing required field {f}")
    if errs:
        return errs
    if not isinstance(entry["source_id"], str) or not entry["source_id"]:
        errs.append(f"entry[{idx}]: source_id must be non-empty string")
    if not isinstance(entry["source_family"], str) or not entry["source_family"]:
        errs.append(f"entry[{idx}]: source_family must be non-empty string")
    if not isinstance(entry["license"], str) or not entry["license"]:
        errs.append(f"entry[{idx}]: license must be non-empty string")
    if not isinstance(entry["language"], str) or not entry["language"]:
        errs.append(f"entry[{idx}]: language must be non-empty string")
    if not isinstance(entry["acquired_date"], str) or len(entry["acquired_date"]) != 10:
        errs.append(f"entry[{idx}]: acquired_date must be YYYY-MM-DD")
    if not is_hex64(entry.get("content_sha256")):
        errs.append(f"entry[{idx}]: content_sha256 must be 64 hex chars")
    if not is_hex64(entry.get("content_blake3")):
        errs.append(f"entry[{idx}]: content_blake3 must be 64 hex chars")
    if not isinstance(entry["near_duplicate_cluster_id"], str) or not entry["near_duplicate_cluster_id"]:
        errs.append(f"entry[{idx}]: near_duplicate_cluster_id must be non-empty string")
    if not isinstance(entry["byte_length"], int) or entry["byte_length"] < 0:
        errs.append(f"entry[{idx}]: byte_length must be non-negative integer")
    if entry.get("split_eligibility") not in SPLITS:
        errs.append(f"entry[{idx}]: split_eligibility must be one of {sorted(SPLITS)}")
    prov = entry.get("provenance")
    if prov is not None and prov not in PROVENANCE:
        errs.append(f"entry[{idx}]: provenance must be one of {sorted(PROVENANCE)}")
    return errs


def audit_splits(entries: list[dict[str, Any]]) -> list[str]:
    errs: list[str] = []
    family_split: dict[str, set[str]] = {}
    cluster_split: dict[str, set[str]] = {}
    for i, e in enumerate(entries):
        split = e.get("split_eligibility")
        if split == "excluded":
            continue
        fam = e.get("source_family")
        cl = e.get("near_duplicate_cluster_id")
        if isinstance(fam, str):
            family_split.setdefault(fam, set()).add(split)
        if isinstance(cl, str):
            cluster_split.setdefault(cl, set()).add(split)
    for fam, splits in sorted(family_split.items()):
        if len(splits) > 1:
            errs.append(f"split leak: source_family {fam!r} crosses splits {sorted(splits)}")
    for cl, splits in sorted(cluster_split.items()):
        if len(splits) > 1:
            errs.append(f"split leak: near_duplicate_cluster_id {cl!r} crosses splits {sorted(splits)}")
    return errs


SOA_REQUIRED = ["stream.bin", "prov.bin", "reset.bit", "weight.bin", "docs.idx", "shard_meta.json"]


def validate_soa_dir(path: Path) -> list[str]:
    errs: list[str] = []
    if not path.is_dir():
        return [f"SoA dir not found: {path}"]
    for name in SOA_REQUIRED:
        if not (path / name).exists():
            errs.append(f"SoA missing required file: {path / name}")
    meta_path = path / "shard_meta.json"
    if meta_path.exists():
        try:
            meta = load_json(meta_path)
        except Exception as e:
            errs.append(f"SoA shard_meta.json invalid: {e}")
            return errs
        for field in ["version", "shard_id", "files"]:
            if field not in meta:
                errs.append(f"SoA shard_meta.json missing field: {field}")
        files = meta.get("files", {})
        if isinstance(files, dict):
            for name, info in files.items():
                fpath = path / name
                if not fpath.exists():
                    errs.append(f"SoA meta references missing file: {name}")
                    continue
                if isinstance(info, dict):
                    size = info.get("byte_length")
                    if isinstance(size, int) and size != fpath.stat().st_size:
                        errs.append(f"SoA size mismatch for {name}: meta={size} actual={fpath.stat().st_size}")
                    sha = info.get("sha256")
                    if isinstance(sha, str):
                        actual = sha256_file(fpath)
                        if actual.lower() != sha.lower():
                            errs.append(f"SoA sha256 mismatch for {name}")
    if not errs:
        stream = (path / "stream.bin").read_bytes()
        prov = (path / "prov.bin").read_bytes()
        reset = (path / "reset.bit").read_bytes()
        weight = (path / "weight.bin").read_bytes()
        docs = (path / "docs.idx").read_bytes()
        n = len(stream)
        if n == 0:
            errs.append("SoA stream.bin must be non-empty")
        if len(prov) != n:
            errs.append(f"SoA prov.bin length {len(prov)} != stream.bin length {n}")
        if any(p > 4 for p in prov):
            errs.append("SoA prov.bin contains invalid provenance tag (> 4)")
        expected_reset = (n + 7) // 8
        if len(reset) != expected_reset:
            errs.append(f"SoA reset.bit length {len(reset)} != ceil(N/8)={expected_reset}")
        if len(weight) != n * 4:
            errs.append(f"SoA weight.bin length {len(weight)} != N*4={n * 4}")
        else:
            vals = struct.unpack(f"<{n}f", weight)
            if any((not math.isfinite(v)) or v < 0.0 for v in vals):
                errs.append("SoA weight.bin contains negative or non-finite float32 weight")
        if len(docs) < 48 or (len(docs) - 16) % 32 != 0:
            errs.append(f"SoA docs.idx invalid size {len(docs)}")
        else:
            magic, ver, d_cnt = struct.unpack("<4sIQ", docs[:16])
            if magic != NV3_DOCS_MAGIC or ver != NV3_SCHEMA_VERSION:
                errs.append(f"SoA docs.idx bad header magic={magic!r} ver={ver}")
            elif len(docs) != 16 + d_cnt * 32 or d_cnt == 0:
                errs.append(f"SoA docs.idx count mismatch d_cnt={d_cnt} size={len(docs)}")
            else:
                exp_off = 0
                for d in range(d_cnt):
                    off, ln, _mh, ck = struct.unpack("<QQQQ", docs[16 + d * 32 : 16 + (d + 1) * 32])
                    if off != exp_off or ln == 0 or off + ln > n:
                        errs.append(f"SoA docs.idx doc[{d}] invalid span ({off}, {ln}) vs {exp_off}..{n}")
                        break
                    rbit = (reset[off // 8] >> (7 - (off % 8))) & 1
                    if rbit != 1:
                        errs.append(f"SoA docs.idx doc[{d}] missing reset bit at offset {off}")
                    actual_ck = fnv1a64_bytes(stream[off : off + ln])
                    if actual_ck != ck:
                        errs.append(f"SoA docs.idx doc[{d}] FNV-1a64 mismatch")
                    exp_off = off + ln
                if exp_off != n:
                    errs.append(f"SoA docs.idx spans end at {exp_off} != {n}")
    return errs


def cmd_self_test() -> int:
    errs: list[str] = []
    good = [
        {
            "source_id": "s1", "source_family": "fam_a", "license": "MIT", "language": "en",
            "acquired_date": "2026-01-01", "content_sha256": "0" * 64, "content_blake3": "1" * 64,
            "near_duplicate_cluster_id": "c1", "byte_length": 10, "split_eligibility": "train",
        },
        {
            "source_id": "s2", "source_family": "fam_b", "license": "MIT", "language": "tr",
            "acquired_date": "2026-01-02", "content_sha256": "2" * 64, "content_blake3": "3" * 64,
            "near_duplicate_cluster_id": "c2", "byte_length": 20, "split_eligibility": "test",
        },
    ]
    for i, e in enumerate(good):
        errs.extend(validate_entry(e, i))
    errs.extend(audit_splits(good))
    if errs:
        print("FAIL self-test good-case:", errs)
        return 1

    bad_overlap = [dict(good[0]), dict(good[1], source_family="fam_a", split_eligibility="test", source_id="s3", near_duplicate_cluster_id="c3")]
    overlap_errs = audit_splits(bad_overlap)
    if not any("source_family" in e for e in overlap_errs):
        print("FAIL self-test: expected source_family overlap detection")
        return 1

    bad_cluster = [dict(good[0]), dict(good[1], near_duplicate_cluster_id="c1", split_eligibility="dev", source_id="s4")]
    cluster_errs = audit_splits(bad_cluster)
    if not any("near_duplicate_cluster_id" in e for e in cluster_errs):
        print("FAIL self-test: expected near_duplicate cluster overlap detection")
        return 1

    bad_entry = dict(good[0])
    bad_entry.pop("license")
    if not validate_entry(bad_entry, 0):
        print("FAIL self-test: expected missing field detection")
        return 1

    print("OK manifest_guard self-test")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", help="Manifest file (.jsonl/.json)")
    ap.add_argument("--audit-split", action="store_true", help="Audit split leakage")
    ap.add_argument("--soa-dir", help="Validate SoA shard directory contract")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return cmd_self_test()

    if not args.manifest and not args.soa_dir:
        ap.error("provide --manifest, --soa-dir, or --self-test")

    errs: list[str] = []
    if args.manifest:
        entries = load_manifest(Path(args.manifest))
        for i, e in enumerate(entries):
            errs.extend(validate_entry(e, i))
        if args.audit_split:
            errs.extend(audit_splits(entries))
        print(f"manifest entries: {len(entries)}")
    if args.soa_dir:
        errs.extend(validate_soa_dir(Path(args.soa_dir)))

    if errs:
        for e in errs:
            print(f"FAIL {e}")
        print(f"FAIL: {len(errs)} error(s)")
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
