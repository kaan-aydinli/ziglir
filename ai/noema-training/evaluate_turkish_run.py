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
    with (ROOT / "turkish_synthetic.v2.jsonl").open(encoding="utf-8") as jf, (ROOT / "turkish_synthetic.tsv").open(encoding="utf-8") as tf:
        for n, (raw, line) in enumerate(zip(jf, tf), 1):
            row = json.loads(raw)
            cols = line.rstrip("\n").split("\t")
            assert len(cols) == 19, (n, len(cols))
            assert row["schema"] == cols[0] == "noema.example.v2"
            assert row["id"] == cols[1] and row["split"] == cols[2]
            assert row["group_key"] == cols[3]
            assert row["conversation"][0]["parts"][0]["text"] == cols[17]
            assert row["target"]["parts"][0]["text"] == cols[18]
            assert row["provenance"]["source"] == "synthetic"
            group = row["group_key"]
            assert group not in groups or groups[group] == row["split"]
            groups[group] = row["split"]
            label = row["target"]["decision"]
            records.append(row)
            split_counts[row["split"]] += 1
            labels[(row["split"], label)] += 1
        assert jf.readline() == "" and tf.readline() == ""
    assert len(records) == 99000 and split_counts == {"train": 79200, "dev": 9900, "test": 9900}
    assert len(groups) == 40

    classifier = (ROOT / "turkish_model.selcp").read_bytes()
    assert classifier[:8] == b"SELQ32V2"
    cm = struct.unpack("<11Q", classifier[8:96])
    assert cm[:10] == (2, 1 << 32, 128, 4, 128, 1, 1, 79200, 10, 1729)
    assert len(classifier) == 96 + (cm[3] * cm[4] * 4 + cm[3]) * 8
    assert checksum(classifier[96:]) == cm[10]

    decoder = (ROOT / "turkish_decoder.seltok").read_bytes()
    assert decoder[:8] == b"SELTOK07"
    dm = struct.unpack("<11Q", decoder[8:96])
    assert dm[:10] == (7, 4, 128, 32, 96, 258, 4 * 32 * 96 * 258, 3960, 1, 1729)
    assert len(decoder) == 96 + dm[6] * 8
    assert checksum(decoder[96:]) == dm[10]

    predictions = {}
    with (ROOT / "turkish_test_predictions.tsv").open(encoding="utf-8") as f:
        assert f.readline().rstrip("\n") == "row_index\tactual_class\tpredicted_class"
        for line in f:
            index, actual, predicted = map(int, line.rstrip("\n").split("\t"))
            assert 0 <= index < len(records) and records[index]["split"] == "test"
            assert actual == LABELS.index(records[index]["target"]["decision"])
            predictions[index] = (actual, predicted)
    assert len(predictions) == 9900

    generated = {}
    with (ROOT / "turkish_decoder_predictions.tsv").open(encoding="utf-8") as f:
        assert f.readline().rstrip("\n") == "row_index\tactual_class\tpredicted_class\tgenerated_text"
        for line in f:
            index_s, actual_s, predicted_s, text = line.rstrip("\n").split("\t", 3)
            index, actual, predicted = int(index_s), int(actual_s), int(predicted_s)
            assert index in predictions and predictions[index] == (actual, predicted)
            assert text and len(text.encode("utf-8")) <= 96
            generated[index] = text
    assert len(generated) == 40
    assert all(sum(predictions[i][0] == c for i in generated) == 10 for c in range(4))

    classifier_correct = sum(actual == predicted for actual, predicted in predictions.values())
    exact = sum(text == records[i]["target"]["parts"][0]["text"] for i, text in generated.items())
    print(f"synthetic rows={len(records)} grouped_families={len(groups)} split={split_counts['train']}/{split_counts['dev']}/{split_counts['test']}")
    print(f"classifier heldout accuracy={classifier_correct}/9900 ({classifier_correct/9900:.2%})")
    print(f"decoder sampled exact matches={exact}/40 ({exact/40:.2%}); class-balanced sample only")
    print("SELTOK07 payload and SELQ32V2 payload checksums/metadata valid")
    print("Warning: synthetic data and a class-conditioned position-wise byte head do not measure open-ended language quality.")


if __name__ == "__main__":
    main()
