# NOEMA v2 text training set

## Source of truth and JSONL training

- `example_text.v2.jsonl` is the canonical and direct LIR input: one `noema.example.v2` task episode per line, with group key, seed, task/capability/risk, user text, context/unknowns, target decision/text and graph, evidence/validator, safety, quality-review state, and provenance.
- The schema-specific LIR decoder validates schema/version, ID/group/split/decision/risk/provenance/review fields, training consent, duplicate IDs and group leakage before vectorizing text. No paired TSV is required by this training example.
- Text is UTF-8 input, tokenized by ASCII alphanumeric boundaries and ASCII lowercase, then mapped to 64 deterministic hashed bag-of-words bins. Non-ASCII bytes currently delimit tokens; there is no Unicode-aware tokenization, sequence model, stemming, or contextual embedding.
- Text is UTF-8 input, tokenized by ASCII alphanumeric boundaries and ASCII lowercase, then mapped to 64 deterministic hashed bag-of-words bins. Non-ASCII bytes currently delimit tokens; there is no Unicode-aware tokenization, sequence model, stemming, or contextual embedding.

## Quality and split policy

There are 11 synthetic examples: train 9, dev 1, test 1. Arithmetic and planning rule families are kept entirely in train; causal is dev-only; destructive-action safety is test-only. Seeds and group keys are recorded. Every item is explicitly synthetic, internal-demo licensed, training-consented, and synthetically reviewed. Evidence kind and validator are item-specific. `plan-002` was corrected in both the legacy tutorial and v2 set: 8 is reachable from 2 by adding 3 twice (`2 → 5 → 8`); the earlier unreachable label/validator was mathematically incorrect. The related capability-eval group key was likewise renamed to indicate reachability.

This is still a pedagogical smoke corpus, not a representative, independently reviewed benchmark. A one-record test split cannot estimate model performance. The synthetic set intentionally covers a few behaviors and has no real-world source diversity, human review, robust paraphrase families, or statistical power. No quality/performance claim should be based on it.

Run from repository root:

```sh
./zig-out/bin/lir run ai/train_text_example.lir --backend=native
```

The program reads canonical JSONL using LIR file I/O and the schema-specific JSONL decoder, validates and vectorizes it, trains 200 epochs, then reports train/dev/test counts, Q32.32 losses, accuracy and confusion matrices. Raw Q32.32 values are divided by 4,294,967,296 for real-valued losses.
