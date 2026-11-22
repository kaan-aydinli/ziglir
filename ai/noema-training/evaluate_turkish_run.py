#!/usr/bin/env python3
"""Audit persisted Turkish classifier/decoder weights and held-out inference exports.

This reports synthetic, template-isolated measurements only; it is not a human
quality, real-world language, or open-ended generation benchmark.
"""
from __future__ import annotations
import collections, json, struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LABELS = ["answer", "ask", "tool", "abstain"]


def checksum(payload: bytes) -> int:
    value = 2166136261
    for byte in payload:
        value = (value * 16777619 + byte) % 2147483647
    return value


def main() -> None:
    records = []
    groups: dict[str, str] = {}
    split_counts = collections.Counter()
    labels = collections.Counter()
    with (ROOT / "turkish_synthetic.v2.jsonl").open(encoding="utf-8") as jf:
        for n, raw in enumerate(jf, 1):
            row = json.loads(raw)
            assert row["schema"] == "noema.example.v2"
            assert row["id"] and row["group_key"] and row["split"] in {"train", "dev", "test"}
            assert row["conversation"][0]["parts"][0]["text"]
            assert row["target"]["parts"][0]["text"]
            assert row["provenance"]["source"] == "synthetic"
            group = row["group_key"]
            assert group not in groups or groups[group] == row["split"]
            groups[group] = row["split"]
            label = row["target"]["decision"]
            records.append(row)
            split_counts[row["split"]] += 1
            labels[(row["split"], label)] += 1
    assert len(records) > 0 and len(groups) > 0
    assert split_counts.get("train", 0) > 0 and split_counts.get("dev", 0) > 0 and split_counts.get("test", 0) > 0
    assert sum(split_counts.values()) == len(records)
    test_count = split_counts["test"]
    train_count = split_counts["train"]

    classifier = (ROOT / "turkish_model.selcp").read_bytes()
    assert classifier[:8] == b"SELQ32V2"
    cm = struct.unpack("<11Q", classifier[8:96])
    assert cm[:4] == (2, 1 << 32, 128, 4)
    assert 1 <= cm[4] <= 128 and cm[5:7] == (1, 1)
    assert cm[7] == train_count and cm[8] > 0 and cm[9] > 0
    assert len(classifier) == 96 + (cm[3] * cm[4] * 4 + cm[3]) * 8
    assert checksum(classifier[96:]) == cm[10]

    decoder = (ROOT / "turkish_decoder.seltok").read_bytes()
    assert decoder[:8] == b"SELTOK07"
    dm = struct.unpack("<11Q", decoder[8:96])
    assert dm[:7] == (7, 4, 128, 32, 96, 258, 4 * 32 * 96 * 258)
    assert dm[7] > 0 and dm[8] > 0 and dm[9] > 0
    assert len(decoder) == 96 + dm[6] * 8
    assert checksum(decoder[96:]) == dm[10]

    predictions = {}
    with (ROOT / "turkish_test_predictions.v1.jsonl").open(encoding="utf-8") as f:
        for raw in f:
            row = json.loads(raw)
            index, actual, predicted = row["row_index"], row["actual_class"], row["predicted_class"]
            assert 0 <= index < len(records) and records[index]["split"] == "test"
            assert actual == LABELS.index(records[index]["target"]["decision"])
            predictions[index] = (actual, predicted)
    assert len(predictions) == test_count

    generated = {}
    with (ROOT / "turkish_decoder_predictions.v1.jsonl").open(encoding="utf-8") as f:
        for raw in f:
            row = json.loads(raw)
            index, actual, predicted = row["row_index"], row["actual_class"], row["predicted_class"]
            text = row["generated_text"]
            assert index in predictions and predictions[index] == (actual, predicted)
            assert text and len(text.encode("utf-8")) <= 96
            generated[index] = text
    assert 0 < len(generated) <= len(predictions)
    generated_class_counts = collections.Counter(predictions[i][0] for i in generated)
    assert set(generated_class_counts) == set(range(4))
    assert max(generated_class_counts.values()) - min(generated_class_counts.values()) <= 1

    classifier_correct = sum(actual == predicted for actual, predicted in predictions.values())
    exact = sum(text == records[i]["target"]["parts"][0]["text"] for i, text in generated.items())
    print(f"synthetic rows={len(records)} grouped_families={len(groups)} split={split_counts['train']}/{split_counts['dev']}/{split_counts['test']}")
    print(f"classifier heldout accuracy={classifier_correct}/{test_count} ({classifier_correct/test_count:.2%})")
    print(f"decoder sampled exact matches={exact}/{len(generated)} ({exact/len(generated):.2%}); class-balanced sample only")
    print("SELTOK07 payload and SELQ32V2 payload checksums/metadata valid")
    print("Warning: synthetic data and a class-conditioned position-wise byte head do not measure open-ended language quality.")


if __name__ == "__main__":
    main()
