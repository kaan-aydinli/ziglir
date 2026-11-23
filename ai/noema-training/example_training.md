# Encoded example-set training run

`example_training.csv` is a small, manually feature-coded classification view of the records in `example.jsonl`, kept in the same order. It is not a parsed or lossless conversion of the JSONL text.

CSV columns are: split (`0=train`, `1=dev`, `2=test`), four cue features, four one-hot decision targets. Feature and target order is `answer, ask, tool, abstain` and all feature vectors are one-hot:

| Source IDs | Split | Cue/target class |
|---|---|---|
| arith-001, arith-002 | train | answer |
| plan-001 | train | answer |
| abstain-001 | train | ask |
| code-001 | train | tool |
| language-001 | train | ask |
| perception-001 | train | answer |
| arith-003, plan-002 | dev | answer |
| causal-001 | dev | abstain |
| safety-001 | test | ask |

The input representation deliberately exposes the decision class as a feature cue, so this is a plumbing/smoke dataset, not a meaningful natural-language generalization benchmark. The test set has one example; reported accuracy is descriptive only and cannot support a performance claim.

Run from repository root:

```sh
./zig-out/bin/lir run ai/train_example.lir --backend=native
```

The program reads the CSV through LIR file I/O, decodes it into Q32.32 arrays, trains 200 fixed epochs, and reports split counts, raw Q32.32 losses, accuracy, and confusion matrices. Raw Q32.32 values are divided by 4,294,967,296 to obtain their real-valued metric.
