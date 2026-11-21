# Text example set for LIR training

`example_text.tsv` contains the 11 natural-language prompts and textual decision labels corresponding to records in `example.jsonl`, in source order. Format is `split<TAB>label<TAB>prompt`; allowed labels are `answer`, `ask`, `tool`, `abstain`. The source split is preserved.

This is a tiny demonstration corpus, not a representative or quality-reviewed NLP benchmark. It contains 7 train, 3 dev, and 1 test prompt; several examples are synthetic and the held-out test has only one record. Do not interpret accuracy as evidence of generalization.

The LIR loader uses ASCII alphanumeric token boundaries, ASCII lowercase, and deterministic hashed bag-of-words with 64 bins. UTF-8 non-ASCII bytes are delimiters rather than Unicode characters; there is no stemming, subword encoding, sequence model, contextual representation, or learned tokenizer. The training labels and prompts are textual; the model's internal feature/count buffers and one-hot class targets are numeric, as expected by this numerical learner.

Run `./zig-out/bin/lir run ai/train_text_example.lir --backend=native` from the repository root. The report uses Q32.32 raw loss (`raw / 4294967296` gives the real value) and confusion matrices in `answer, ask, tool, abstain` order.
