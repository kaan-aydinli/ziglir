"""Unit tests for the dependency-free NOEMA example validator."""
import json
import tempfile
import unittest
from pathlib import Path

import validate_examples as validator


class ValidatorTests(unittest.TestCase):
    def test_repository_examples_validate(self):
        messages = validator.validate_all(Path(__file__).parent)
        self.assertEqual(len(messages), 6)

    def test_duplicate_example_ids_are_rejected(self):
        row = {
            "id": "same", "split": "train", "seed": 1, "task": "reasoning",
            "input": "x", "context": {}, "target_graph": {}, "target": "x",
            "evidence": {}, "decision": "answer", "validator": {}, "provenance": "synthetic",
        }
        with self.assertRaisesRegex(validator.ValidationError, "duplicate id"):
            validator.validate_example_rows([row, dict(row)])

    def test_unknown_split_is_rejected(self):
        row = {
            "id": "x", "split": "production", "seed": 1, "task": "reasoning",
            "input": "x", "context": {}, "target_graph": {}, "target": "x",
            "evidence": {}, "decision": "answer", "validator": {}, "provenance": "synthetic",
        }
        with self.assertRaisesRegex(validator.ValidationError, "unsupported value"):
            validator.validate_example_rows([row])

    def test_wrong_type_enum_is_reported_not_crash(self):
        row = {
            "id": "x", "split": [], "seed": 1, "task": "reasoning",
            "input": "x", "context": {}, "target_graph": {}, "target": "x",
            "evidence": {}, "decision": "answer", "validator": {}, "provenance": "synthetic",
        }
        with self.assertRaisesRegex(validator.ValidationError, "unsupported value"):
            validator.validate_example_rows([row])

    def test_unsupported_output_cannot_claim_artifact(self):
        row = {
            "schema": "noema.output_example.v1", "id": "x", "task": "audio",
            "split": "test", "request_ref": "r", "decision": "unsupported",
            "obligations": [], "artifacts": [{"artifact_id": "a"}], "validation": {}, "provenance": "synthetic",
        }
        with self.assertRaisesRegex(validator.ValidationError, "must not claim artifacts"):
            validator.validate_output_rows([row])

    def test_eval_examples_require_grouped_split(self):
        row = {
            "schema": "noema.capability_eval.v1", "id": "e1", "split": "dev",
            "group_key": "", "task": {"family": "nlu"}, "language": "tr",
            "input": "x", "context": {}, "reference": {}, "criterion": {},
            "checker": {}, "risk": "low", "provenance": {},
        }
        with self.assertRaisesRegex(validator.ValidationError, "group_key"):
            validator.validate_eval_rows([row])

    def test_output_artifact_must_reference_declared_obligation(self):
        row = {
            "schema": "noema.output_example.v1", "id": "x", "task": "text",
            "split": "test", "request_ref": "r", "decision": "answer",
            "obligations": [], "artifacts": [{
                "artifact_id": "a", "kind": "text", "media_type": "text/plain",
                "payload_ref": "demo", "payload_hash": "demo", "source_obligations": ["missing"],
                "source_evidence": [], "evidence_level": "hypothesis", "generator_version": "demo",
                "safety_labels": [], "user_rights": "demo",
            }], "validation": {}, "provenance": "synthetic",
        }
        with self.assertRaisesRegex(validator.ValidationError, "unknown obligation refs"):
            validator.validate_output_rows([row])

    def test_output_artifact_evidence_must_match_obligation(self):
        row = {
            "schema": "noema.output_example.v1", "id": "x", "task": "text",
            "split": "test", "request_ref": "r", "decision": "answer",
            "obligations": [{"obligation_id": "o1", "evidence_id": "e1"}],
            "artifacts": [{
                "artifact_id": "a", "kind": "text", "media_type": "text/plain",
                "payload_ref": "demo", "payload_hash": "demo", "source_obligations": ["o1"],
                "source_evidence": ["e2"], "evidence_level": "hypothesis",
                "generator_version": "demo", "safety_labels": [], "user_rights": "demo",
            }], "validation": {}, "provenance": "synthetic",
        }
        with self.assertRaisesRegex(validator.ValidationError, "evidence refs do not match"):
            validator.validate_output_rows([row])

    def test_deletion_tombstone_must_not_retain_content(self):
        row = {
            "event_id": "del-1", "event_type": "deletion", "schema_version": 1,
            "run_id": "r", "timestamp": "t", "provenance_id": "p",
            "subject_ref": "s", "scope": [], "completion": "done",
            "tombstone": {"content_included": True},
        }
        with self.assertRaisesRegex(validator.ValidationError, "must not include deleted content"):
            validator.validate_event_rows([row])

    def test_invalid_jsonl_reports_line_number(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bad.jsonl"
            path.write_text("{}\nnot-json\n", encoding="utf-8")
            with self.assertRaisesRegex(validator.ValidationError, r":2: invalid JSON"):
                validator._load_jsonl(path)


if __name__ == "__main__":
    unittest.main()
