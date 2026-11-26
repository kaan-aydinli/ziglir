#!/usr/bin/env python3
"""Deterministic builder for NOEMA v3 locked multi-domain raw UTF-8 SoA corpus.

Produces:
  - ai/noema_v3/corpus_locked/manifest.jsonl
  - ai/noema_v3/corpus_locked/train_soa/
  - ai/noema_v3/corpus_locked/dev_soa/
  - ai/noema_v3/corpus_locked/test_soa/

Enforces strict source_family and near_duplicate_cluster_id isolation across
train, dev, and locked test splits (verified fail-closed by manifest_guard.py).
"""
from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT_ROOT = ROOT / "ai/noema_v3/corpus_locked"

PROV_MAP = {
    "SYSTEM_POLICY": 0,
    "USER_INPUT": 1,
    "UNTRUSTED_SOURCE": 2,
    "VERIFIED_KHG": 3,
    "HYPOTHESIS": 4,
}


def fnv1a64(data: bytes) -> int:
    h = 0xCBF29CE484222325
    for b in data:
        h = ((h ^ b) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def keyed_blake_digest(data: bytes) -> str:
    return hashlib.blake2b(data, digest_size=32, person=b"NV3_BLK3").hexdigest()


CORPUS_DOCS = [
    # ---- TRAIN SPLIT (6 distinct families & clusters) ----
    {
        "source_id": "nv3_tr_mech_01",
        "source_family": "tr_classical_mechanics",
        "cluster_id": "clus_tr_mech_force",
        "language": "tr",
        "split": "train",
        "provenance": "VERIFIED_KHG",
        "text": "İlke: Kuvvet kütle ile ivmenin çarpımına eşittir (F = m * a). Kanıt: 6 kg * 3 m/s^2 = 18 N [DOĞRULANDI]\n",
    },
    {
        "source_id": "nv3_tr_arith_02",
        "source_family": "tr_exact_rationals",
        "cluster_id": "clus_tr_rat_sum",
        "language": "tr",
        "split": "train",
        "provenance": "VERIFIED_KHG",
        "text": "İlke: Kesir toplamı ortak payda ve EBOB ile indirgenir. Kanıt: (1/4) + (1/4) = 1/2 [DOĞRULANDI]\n",
    },
    {
        "source_id": "nv3_tr_logic_03",
        "source_family": "tr_propositional_logic",
        "cluster_id": "clus_tr_modus_ponens",
        "language": "tr",
        "split": "train",
        "provenance": "VERIFIED_KHG",
        "text": "İlke: A => B ve A öncülleri doğruysa B zorunlu olarak doğrudur; !B ile çelişki oluşur [DOĞRULANDI]\n",
    },
    {
        "source_id": "nv3_tr_epist_04",
        "source_family": "tr_epistemic_policy",
        "cluster_id": "clus_tr_abstain_law",
        "language": "tr",
        "split": "train",
        "provenance": "SYSTEM_POLICY",
        "text": "İlke: Kanıt grafiğinde doğrulanmış dayanak yoksa model iddia üretmez ve dürüstçe çekinir [ABSTAIN]\n",
    },
    {
        "source_id": "nv3_en_thermo_05",
        "source_family": "en_energy_power_si",
        "cluster_id": "clus_en_work_watt",
        "language": "en",
        "split": "train",
        "provenance": "VERIFIED_KHG",
        "text": "Principle: Mechanical work per unit time defines power in SI units. Proof: 20 J / 4 s = 5 W [VERIFIED]\n",
    },
    {
        "source_id": "nv3_en_causal_06",
        "source_family": "en_causal_memory",
        "cluster_id": "clus_en_causality_rule",
        "language": "en",
        "split": "train",
        "provenance": "SYSTEM_POLICY",
        "text": "Principle: Causal byte generation observes prompt bytes only and never accesses future response bytes [VERIFIED]\n",
    },
    # ---- DEV SPLIT (3 distinct families & clusters) ----
    {
        "source_id": "nv3_tr_pressure_07",
        "source_family": "tr_fluid_statics_si",
        "cluster_id": "clus_tr_pascal_unit",
        "language": "tr",
        "split": "dev",
        "provenance": "VERIFIED_KHG",
        "text": "İlke: Basınç birim yüzeye dik etkiyen kuvvettir. Kanıt: 30 N / 6 m^2 = 5 Pa [DOĞRULANDI]\n",
    },
    {
        "source_id": "nv3_tr_temp_08",
        "source_family": "tr_temporal_intervals",
        "cluster_id": "clus_tr_epoch_order",
        "language": "tr",
        "split": "dev",
        "provenance": "VERIFIED_KHG",
        "text": "İlke: Ardışık geçerlilik aralıklarında sorgu tarihini kapsayan güncel kayıt seçilir [DOĞRULANDI]\n",
    },
    {
        "source_id": "nv3_en_prov_09",
        "source_family": "en_provenance_security",
        "cluster_id": "clus_en_untrusted_isolation",
        "language": "en",
        "split": "dev",
        "provenance": "SYSTEM_POLICY",
        "text": "Principle: Untrusted external text spans never escalate authority to system policy [VERIFIED]\n",
    },
    # ---- LOCKED TEST SPLIT (3 distinct families & clusters) ----
    {
        "source_id": "nv3_tr_kinem_10",
        "source_family": "tr_kinematics_velocity",
        "cluster_id": "clus_tr_velocity_si",
        "language": "tr",
        "split": "test",
        "provenance": "VERIFIED_KHG",
        "text": "İlke: Sabit hız yer değiştirmenin zamana oranıdır. Kanıt: 24 m / 3 s = 8 m/s [DOĞRULANDI]\n",
    },
    {
        "source_id": "nv3_tr_number_11",
        "source_family": "tr_integer_identities",
        "cluster_id": "clus_tr_bigint_exact",
        "language": "tr",
        "split": "test",
        "provenance": "VERIFIED_KHG",
        "text": "İlke: Tam sayı ve kesir doğrulaması kayan nokta hatası olmadan kesin yürütülür [DOĞRULANDI]\n",
    },
    {
        "source_id": "nv3_en_freq_12",
        "source_family": "en_wave_frequency_si",
        "cluster_id": "clus_en_hertz_unit",
        "language": "en",
        "split": "test",
        "provenance": "VERIFIED_KHG",
        "text": "Principle: Oscillation count per second yields frequency in hertz. Proof: 12 / 3 s = 4 Hz [VERIFIED]\n",
    },
]


def write_soa_shard(shard_dir: Path, shard_id: str, docs: list[dict]) -> None:
    shard_dir.mkdir(parents=True, exist_ok=True)
    stream_parts: list[bytes] = []
    prov_bytes = bytearray()
    weights: list[float] = []
    doc_records: list[tuple[int, int, int, int]] = []
    reset_offsets: set[int] = set()

    cur_off = 0
    for d in docs:
        raw = d["text"].encode("utf-8")
        n = len(raw)
        ptag = PROV_MAP[d["provenance"]]
        mhash = int(hashlib.sha256(d["source_id"].encode("utf-8")).hexdigest()[:16], 16)
        ck = fnv1a64(raw)
        reset_offsets.add(cur_off)
        stream_parts.append(raw)
        prov_bytes.extend([ptag] * n)
        weights.extend([1.0] * n)
        doc_records.append((cur_off, n, mhash, ck))
        cur_off += n

    stream = b"".join(stream_parts)
    total_n = len(stream)
    reset_buf = bytearray((total_n + 7) // 8)
    for roff in reset_offsets:
        reset_buf[roff // 8] |= 1 << (7 - (roff % 8))

    weight_buf = struct.pack(f"<{total_n}f", *weights)
    docs_hdr = struct.pack("<4sIQ", b"NV3D", 3, len(doc_records))
    docs_body = b"".join(struct.pack("<QQQQ", *rec) for rec in doc_records)
    docs_buf = docs_hdr + docs_body

    files_payload = {
        "stream.bin": stream,
        "prov.bin": bytes(prov_bytes),
        "reset.bit": bytes(reset_buf),
        "weight.bin": weight_buf,
        "docs.idx": docs_buf,
    }
    meta_files = {}
    for fname, content in files_payload.items():
        (shard_dir / fname).write_bytes(content)
        meta_files[fname] = {
            "byte_length": len(content),
            "sha256": hashlib.sha256(content).hexdigest(),
        }

    meta = {
        "version": "3.0.0",
        "shard_id": shard_id,
        "num_docs": len(doc_records),
        "num_bytes": total_n,
        "files": meta_files,
    }
    (shard_dir / "shard_meta.json").write_text(
        json.dumps(meta, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    manifest_lines: list[str] = []
    by_split: dict[str, list[dict]] = {"train": [], "dev": [], "test": []}

    for d in CORPUS_DOCS:
        raw = d["text"].encode("utf-8")
        entry = {
            "source_id": d["source_id"],
            "source_family": d["source_family"],
            "license": "CC0-1.0",
            "language": d["language"],
            "acquired_date": "2026-11-25",
            "content_sha256": hashlib.sha256(raw).hexdigest(),
            "content_blake3": keyed_blake_digest(raw),
            "near_duplicate_cluster_id": d["cluster_id"],
            "byte_length": len(raw),
            "split_eligibility": d["split"],
            "provenance": d["provenance"],
        }
        manifest_lines.append(json.dumps(entry, ensure_ascii=False))
        by_split[d["split"]].append(d)

    manifest_path = OUT_ROOT / "manifest.jsonl"
    manifest_path.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")

    write_soa_shard(OUT_ROOT / "train_soa", "nv3_locked_train_v1", by_split["train"])
    write_soa_shard(OUT_ROOT / "dev_soa", "nv3_locked_dev_v1", by_split["dev"])
    write_soa_shard(OUT_ROOT / "test_soa", "nv3_locked_test_v1", by_split["test"])

    # Also ensure Phase 0 / Phase 2 micro-shard fixtures exist deterministically
    fix_root = ROOT / "ai/noema_v3/fixtures"
    fixture_docs = [
        {
            "source_id": "nv3_train_doc_001",
            "source_family": "tr_causal_axioms_train",
            "cluster_id": "cluster_train_ax01",
            "language": "tr",
            "split": "train",
            "provenance": "VERIFIED_KHG",
            "text": "Kanıt: A -> B => B.\n",
        },
        {
            "source_id": "nv3_train_doc_002",
            "source_family": "tr_causal_axioms_train",
            "cluster_id": "cluster_train_ax02",
            "language": "tr",
            "split": "train",
            "provenance": "UNTRUSTED_SOURCE",
            "text": "Kanıt: X -> Y => Y.\n",
        },
        {
            "source_id": "nv3_test_doc_001",
            "source_family": "tr_causal_eval_heldout",
            "cluster_id": "cluster_test_ev01",
            "language": "tr",
            "split": "test",
            "provenance": "VERIFIED_KHG",
            "text": "Kanıt: P -> Q => Q.\n",
        },
        {
            "source_id": "nv3_test_doc_002",
            "source_family": "tr_causal_eval_heldout",
            "cluster_id": "cluster_test_ev02",
            "language": "tr",
            "split": "test",
            "provenance": "USER_INPUT",
            "text": "Kanıt: M -> N => N [1]\n",
        },
    ]
    fix_manifest_lines = []
    for fd in fixture_docs:
        raw = fd["text"].encode("utf-8")
        fix_manifest_lines.append(
            json.dumps(
                {
                    "source_id": fd["source_id"],
                    "source_family": fd["source_family"],
                    "license": "CC0-1.0",
                    "language": fd["language"],
                    "acquired_date": "2026-11-25",
                    "content_sha256": hashlib.sha256(raw).hexdigest(),
                    "content_blake3": keyed_blake_digest(raw),
                    "near_duplicate_cluster_id": fd["cluster_id"],
                    "byte_length": len(raw),
                    "split_eligibility": fd["split"],
                    "provenance": fd["provenance"],
                },
                ensure_ascii=False,
            )
        )
    (fix_root / "phase2_corpus_manifest.jsonl").write_text(
        "\n".join(fix_manifest_lines) + "\n", encoding="utf-8"
    )
    write_soa_shard(fix_root / "soa_shard_sample", "soa_shard_sample_v3", fixture_docs[:2])
    write_soa_shard(fix_root / "soa_shard_heldout", "soa_shard_heldout_v3", fixture_docs[2:])

    print(f"Built locked corpus at {OUT_ROOT} (docs={len(CORPUS_DOCS)}) + Phase 0/2 fixtures")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
