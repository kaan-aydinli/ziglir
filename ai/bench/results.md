# SEL — ölçüm sonuçları

Üretim: `python3 ai/bench/run.py --write` · 2026-11-18 12:49

| iş | süre (ms) | açıklama |
|---|---:|---|
| fixed ops | 10.50 | mul + div + sat_add, 1M yineleme |
| forward | 53.78 | 24 kenarlık SEL ileri geçişi, 100k çağrı |
| forward+learn | 180.09 | 24 kenarlık ileri + eikonal güncelleme, 100k |
| xor train | 44.98 | XOR, 3000 epoch x 4 desen = 12000 güncelleme |
| 3-layer net | 124.73 | 128 nöron x 3 katman, K=8, 2000 adım |
| search | 11.87 | 1M gönderilik ters indeks, 1 sorgu |
| matmul 96 | 17.31 | 96x96 Q32.32 matris çarpımı |
