# SEL — ölçüm sonuçları

Üretim: `python3 ai/bench/run.py --write` · 2026-11-24 11:27

| iş | süre (ms) | açıklama |
|---|---:|---|
| fixed ops | 5.36 | mul + div + sat_add, 1M yineleme |
| forward | 16.88 | 24 kenarlık SEL ileri geçişi, 100k çağrı |
| forward+learn | 39.09 | 24 kenarlık ileri + eikonal güncelleme, 100k |
| xor train | 15.50 | XOR, 3000 epoch x 4 desen = 12000 güncelleme |
| 3-layer net | 35.43 | 128 nöron x 3 katman, K=8, 2000 adım |
| search | 9.43 | 1M gönderilik ters indeks, 1 sorgu |
| matmul 96 | 4.04 | 96x96 Q32.32 matris çarpımı |
