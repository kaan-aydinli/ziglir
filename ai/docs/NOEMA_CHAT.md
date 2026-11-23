# NOEMA local chat prototype

This implementation is a small, local, LIR-only retrieval prototype. It is **not** a GPT/Gemini/Claude/DeepSeek-scale generative model: it does not synthesize open-ended text from learned language-model weights. It indexes prompt/answer pairs in a bounded, matrix-free sparse memory and returns a stored answer when its token-signature similarity clears a threshold; otherwise it abstains. It cannot be represented as equivalent in capability to frontier models.

## Build a demonstration memory

From the repository root, first create the corpus and then index only its training split:

```sh
./zig-out/bin/lir run ai/generate_110k_corpus.lir --backend=native
./zig-out/bin/lir run ai/train_noema_chat_memory.lir --backend=native
```

The generated 110k corpus is synthetic/template-based demonstration data. The memory trainer reports the total rows, accepted training pairs, rejected pairs, and saves `ai/noema-training/turkish_chat_memory.nsm`. It excludes non-`train` rows from retrieval. The checkpoint is local; no external model or hosted inference is called.

## Chat

The production-facing interface is `ai/chat.lir`, which implements a three-tier decision pipeline:
1. **Deterministic symbolic & natural-language arithmetic:** Solves addition, subtraction, multiplication, and division directly, preventing nearest-neighbor arithmetic hallucinations.
2. **Matrix-free sparse episodic memory:** Retrieves stored contextual knowledge (insufficient information detection, causal distinctions, code/tool delegation) from the 88k training split via Jaccard token signatures.
3. **Safe abstention:** When confidence is below threshold, cleanly abstains and requests clarification instead of fabricating answers.

```sh
printf 'Sepette 12 elma ve 8 armut var. Toplam meyve sayısı kaçtır?\n' \
  | ./zig-out/bin/lir run ai/chat.lir --backend=native
```

For pure retrieval testing without the arithmetic tool routing, `ai/chat_noema_memory.lir` remains available.

## Observed smoke-test outputs (`ai/chat.lir`)

After indexing 110,000 JSONL rows (88,000 train pairs learned, 0 rejected):

- `İki sayının toplamı kaçtır? Birinci sayı 2, ikinci sayı 1.` → `Toplam 3.`
- `Sepette 12 elma ve 8 armut var. Toplam meyve sayısı kaçtır?` → `Toplam 20.`
- `17 + 25` → `= 42`
- `100 - 37` → `= 63`
- `Bir rafta 15 kitap vardı; 6'sı alındı. Kaç kitap kaldı?` → `Kalan 9.`
- `Dikdörtgenin alanı 48 santimetrekare. Bir kenarının uzunluğu nedir?` → `Tek bir yanıt için ek ölçü veya ikinci koşul gerekir.`
- `Şemsiye satışı 25 iken ıslak kaldırım sayısı 14 oldu. Bu ilişki nedenselliği kanıtlar mı?` → `Bu gözlem tek başına nedenselliği göstermez; ortak neden veya müdahale verisi gerekir.`
- `Müzik teorisi nedir?` → abstention prompt.


These are synthetic-corpus retrieval smoke tests, not a held-out language-quality benchmark or evidence of general reasoning.
