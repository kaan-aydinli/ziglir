"""Tests for deterministic dataset leakage/integrity auditing."""
import json
import tempfile
import unittest
from pathlib import Path

import dataset_audit


class DatasetAuditTests(unittest.TestCase):
    def make_dataset(self, rows):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        path = Path(temp.name) / "data.jsonl"
        path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")
        return path

    @staticmethod
    def row(rid, split, group, text):
        return {
            "id": rid, "split": split, "group_key": group,
            "task": {"family": "nlu"}, "language": "tr",
            "input": text,
            "provenance": {"source": "synthetic", "license": "internal"},
        }

    def test_repository_eval_and_universal_fixtures_pass(self):
        root = Path(__file__).parent
        for name in ("universal_examples.jsonl", "capability_eval.example.jsonl"):
            report = dataset_audit.audit(root / name)
            self.assertEqual(report["release_gate"], "pass")
            self.assertEqual(report["findings"], [])

    def test_same_group_across_splits_fails(self):
        path = self.make_dataset([
            self.row("a", "train", "same-rule", "Training example with sufficiently long prompt."),
            self.row("b", "test", "same-rule", "Different heldout example with sufficiently long prompt."),
        ])
        report = dataset_audit.audit(path)
        self.assertEqual(report["release_gate"], "fail")
        self.assertIn("group_split_leakage", {f["code"] for f in report["findings"]})

    def test_normalized_exact_prompt_across_splits_fails_without_echoing_text(self):
        prompt = "A sufficiently long prompt shared across these two data splits."
        path = self.make_dataset([
            self.row("a", "train", "g1", prompt),
            self.row("b", "test", "g2", "  " + prompt.upper() + "  "),
        ])
        report = dataset_audit.audit(path)
        findings = [f for f in report["findings"] if f["code"] == "exact_text_split_leakage"]
        self.assertEqual(len(findings), 1)
        self.assertNotIn(prompt, json.dumps(report))
        self.assertIn("text_hash", findings[0])

    def test_missing_license_is_a_hard_gate_failure(self):
        row = self.row("a", "train", "g1", "A sufficiently long synthetic prompt for audit.")
        row["provenance"].pop("license")
        self.assertEqual(dataset_audit.audit(self.make_dataset([row]))["release_gate"], "fail")

    def test_report_is_deterministic(self):
        report = dataset_audit.audit(Path(__file__).parent / "capability_eval.example.jsonl")
        encoded1 = json.dumps(report, ensure_ascii=False, sort_keys=True)
        encoded2 = json.dumps(dataset_audit.audit(Path(__file__).parent / "capability_eval.example.jsonl"), ensure_ascii=False, sort_keys=True)
        self.assertEqual(encoded1, encoded2)


if __name__ == "__main__":
    unittest.main()
