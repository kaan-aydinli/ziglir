import copy
import unittest

from validate_variants import ROOT, read_jsonl, validate, validate_composites


class VariantCorpusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = read_jsonl(ROOT / "turkish_variants.v1.jsonl")

    def test_all_task_variants_validate(self):
        self.assertEqual(validate(self.rows), 12)

    def test_duplicate_ids_rejected(self):
        rows = copy.deepcopy(self.rows)
        rows[1]["id"] = rows[0]["id"]
        with self.assertRaisesRegex(ValueError, "duplicate id"):
            validate(rows)

    def test_group_leakage_rejected(self):
        rows = copy.deepcopy(self.rows)
        rows[1]["group_key"] = rows[0]["group_key"]
        rows[1]["split"] = "test"
        with self.assertRaisesRegex(ValueError, "group leakage"):
            validate(rows)

    def test_dangling_citation_rejected(self):
        rows = copy.deepcopy(self.rows)
        row = next(r for r in rows if r["variant"] == "retrieval_grounded")
        row["citations"][0]["doc_id"] = "missing-doc"
        with self.assertRaisesRegex(ValueError, "dangling citation"):
            validate(rows)

    def test_tool_cycle_requires_verified_result(self):
        rows = copy.deepcopy(self.rows)
        row = next(r for r in rows if r["variant"] == "tool_call_cycle")
        row["tool_trace"]["verified"] = False
        with self.assertRaisesRegex(ValueError, "must be verified"):
            validate(rows)

    def test_composite_examples_cover_all_atoms(self):
        atomic = {row["id"]: row for row in self.rows}
        composites = read_jsonl(ROOT / "turkish_composite_examples.v1.jsonl")
        self.assertEqual(validate_composites(composites, atomic), 12)


if __name__ == "__main__":
    unittest.main()
