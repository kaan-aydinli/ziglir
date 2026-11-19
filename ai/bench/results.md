# SEL — ölçüm sonuçları

Üretim: `python3 ai/bench/run.py --write` · 2026-11-18 13:00

> **Not:** Bu tablo sınır-kontrolü hoisting'i (commit `44574bf`),
> memory-pure hoisting (`90a0eb7`) ve leaf-closure inlining (`b1f07b9`)
> **öncesine** aittir. Güncel rakamlar için `ai/README.md` ve
> `ai/docs/DESIGN.md` §5.5'e bakın.

| iş | süre (ms) | açıklama |
|---|---:|---|
| fixed ops | 8.35 | mul + div + sat_add, 1M yineleme |
| forward | 53.96 | 24 kenarlık SEL ileri geçişi, 100k çağrı |
| forward+learn | 191.16 | 24 kenarlık ileri + eikonal güncelleme, 100k |
| xor train | 45.71 | XOR, 3000 epoch x 4 desen = 12000 güncelleme |
| 3-layer net | 121.40 | 128 nöron x 3 katman, K=8, 2000 adım |
| search | 10.68 | 1M gönderilik ters indeks, 1 sorgu |
| matmul 96 | 17.01 | 96x96 Q32.32 matris çarpımı |
