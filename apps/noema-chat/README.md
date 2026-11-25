# NOEMA Chat (LIR-backed field inference prototype)

A Turkish chat-style UI for the repository's LIR-implemented NOEMA-Φ path.
The Node server is only an HTTP/static-file bridge; model loading, prompt
conditioning, and field evolution run in LIR. A bounded in-checkpoint exemplar
index provides corpus-derived text retrieval; the prototype is not a free-form
language generator.

## Run locally

From the repository root, build the LIR executable using the repository's Zig
toolchain. To generate the ignored trained checkpoint from the included
plain-text corpus, run the trainer once, then start the web app:

```sh
zig build -Doptimize=ReleaseFast
node apps/noema-chat/train-included-corpus.mjs
node apps/noema-chat/server.mjs
```

Open `http://localhost:4173`. Set `PORT` or `LIR_BIN` to override the defaults.
The server binds to `0.0.0.0` for Arena preview support. The included trainer
publishes an increasing `pretrain_large_vNNN.nps` checkpoint and atomically
updates `pretrain_large_latest.nps` (both ignored by Git). The UI shows the
current version's filename/date; if no included checkpoint exists, it disables
that model option and leaves the fresh baseline available.

## Train from your own TXT file

Open the separate **Pretraining** page from the top navigation. Select or drop a
UTF-8 `.txt` corpus; there is no configured total-byte or physical-line ceiling.
Upload size is ultimately bounded by available disk/RAM and the platform's
transport. There is no default training time limit; operators may set
`TRAIN_TIMEOUT_MS` as a deployment policy. A standalone `---` line separates
topics; the delimiter is framing only and is omitted. All other topic bytes
(including whitespace) are preserved and packed into roughly 1 MiB LIR records.
The page displays upload progress, then polls the LIR trainer's actual record
counter and reports percent, processed/source bytes, elapsed time, and estimated
remaining time. Input is streamed to disk and training records are split at
roughly 1 MiB boundaries; the split size is a chunking strategy, not a corpus
size limit.
The first successful run creates `ai/noema-training/user_pretrain_v001.nps`;
subsequent runs load that latest state and continue training into `v002`, `v003`,
and so on. Previous versions are never overwritten; Chat loads the newest
successful version via a latest-version alias. The model picker shows the actual
version filename/date.

## Models and output

Use the model picker to choose `trained` (the latest corpus checkpoint, when
present), `uploaded` (the newest user-trained version), or
`fresh` (new untrained field state). Each request loads/creates
the selected state and scores the checkpoint's dataset-sized exemplar index
against the prompt using normalized raw-byte 5-gram resonance. Its entry count
scales to the planned training records, subject to available memory. Each stored
retrieval anchor is currently limited to one eligible source line of at most 256
bytes per training record. An exact byte-substring match wins; otherwise a candidate needs similarity
at least 0.22 and one case-insensitive whole-token overlap. Passing those
heuristic retrieval checks returns the stored line as UTF-8 and lossless hex;
otherwise the model abstains rather than using a canned fallback. This gives corpus-grounded, non-hardcoded output, but it is
retrieval of learned examples—not free-form language generation, and its quality
depends on the training data. No conversational state is carried across requests.

`POST /api/chat` accepts `{ "message": "...", "modelId": "trained" }`;
`modelId` may be `trained`, `uploaded`, or `fresh`. `GET /api/health` reports
whether each selected checkpoint exists and its actual file size. Results include model ID,
training records/bytes/perturbations, stored exemplar count/capacity, spectral
stage, input/output byte counts, retrieval similarity, free energy and surprise
gate measured during that run. The prompt has no configured UTF-8 byte ceiling;
the LIR adapter grows its input buffer as needed, subject to available memory,
address space and the host's integer representation. The chat backend retains a
15-second per-request execution timeout as an operational safeguard.

The trainer reads `ai/noema-training/pretrain_corpus_large.tr.txt`: plain
UTF-8 topic text with a standalone `---` line between topics. On this checkout,
three end-to-end native runs each reported 70 records and 566,714 payload bytes
(566,990 source bytes including the 276 bytes of delimiter lines); measured wall
times after the current parser, checkpoint, arena-scratch and spectral recurrence
changes were 0.846 s, 0.741 s, and 0.756 s (0.756 s median), including `lir run`
startup. All remained at spectral stage 0; this is a local technical corpus, not
a quality benchmark.
`train-included-corpus.mjs` publishes a new checkpoint after each successful run. `ai/noema-training/pretrain_corpus.tr.txt`
is the smaller original authoring corpus.

A separate HTTP upload stress run used a synthetic repeated-byte TXT body of
66,000,066 bytes (66 decimal MB, 62.94 MiB), grouped into 63 LIR records. Across
three runs, accept/preparation times were 0.232, 0.237, and 0.330 s (median
0.237 s); training waits were 0.814, 0.815, and 0.815 s (median 0.815 s);
end-to-end times were 1.046, 1.052, and 1.145 s (median 1.052 s). This validates upload/training throughput and progress
completion on synthetic data only; it is not an intelligence or language-quality
benchmark. Test checkpoints were removed after the run.

## Retrieval behavior test

`ai/tests/56_noema_pretrain_learned_excerpt.lir` trains on two lines, then asks
an unseen paraphrase (`River sediment reaches the coast.`) and checks that the
selected answer is the exact relevant training line, not a prompt-copy or a
hardcoded response. The held-out query scored **0.582** in the current 512-
feature configuration; a separate unrelated query is required to fall below the
0.22 threshold plus lexical-overlap gate. The test also saves/reloads the checkpoint and runs
on native, VM, and C backends. This is a tiny functional example, not an
accuracy estimate: it does not establish broad semantic generalization or
natural-language quality. The latest generated-data run and actual prompt/output
checks are documented in [`PRETRAINING-RUN.md`](../../ai/noema-training/PRETRAINING-RUN.md).
