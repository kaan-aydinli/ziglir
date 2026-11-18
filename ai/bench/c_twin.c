// SEL'in LLVM C ikizi — aynı iş, aynı Q32.32 aritmetiği, aynı kenar düzeni.
// Amac: LIR ile "elle yazılmış C" arasındaki farkı ölçmek.
// NOT: Bu bir Rust ölçümü DEĞİLDİR; Rust bu ortamda çalıştırılamıyor.
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

#define K 8
#define EDGE_STRIDE 4

static inline int64_t sat_add(int64_t a, int64_t b) {
    int64_t s = a + b;
    if ((a >= 0) == (b >= 0) && ((a >= 0) != (s >= 0)))
        return a >= 0 ? ((int64_t)1 << 62) - 1 : -((int64_t)1 << 62);
    return s;
}
static inline int64_t sel_mul(int64_t a, int64_t b) { return (a * b) >> 32; }
static inline int64_t lrelu(int64_t x) { return x < 0 ? (x >> 4) + 16777216 : x + 16777216; }

typedef struct { int64_t *edges; int64_t nout; int64_t k; } Layer;

static void forward(Layer *l, const int64_t *x, int64_t *out) {
    for (int64_t o = 0; o < l->nout; o++) {
        int64_t acc = 0;
        for (int64_t j = 0; j < l->k; j++) {
            int64_t *e = l->edges + (o * l->k + j) * EDGE_STRIDE;
            acc = sat_add(acc, sel_mul(e[1], x[e[0]]));
        }
        out[o] = lrelu(acc);
    }
}

int main(void) {
    const int64_t n1 = 64, n2 = 128, n3 = 8;
    int64_t *x = malloc(64 * 8), *h1 = malloc(n2 * 8), *h2 = malloc(n2 * 8), *y = malloc(n3 * 8);
    for (int64_t i = 0; i < 64; i++) x[i] = i % 7;

    Layer ls[3] = {
        {malloc(n2 * K * EDGE_STRIDE * 8), n2, K},
        {malloc(n2 * K * EDGE_STRIDE * 8), n2, K},
        {malloc(n3 * K * EDGE_STRIDE * 8), n3, K},
    };
    int64_t nins[3] = {n1, n2, n2};
    for (int l = 0; l < 3; l++)
        for (int64_t i = 0; i < ls[l].nout * K; i++) {
            int64_t *e = ls[l].edges + i * EDGE_STRIDE;
            e[0] = (i + (i / K) * 5 + 3) % nins[l];
            e[1] = (int64_t)(((i * 131) % 256) - 128) * (1LL << 24);
            e[2] = 0; e[3] = 0;
        }

    for (int64_t s = 0; s < 2000; s++) {
        forward(&ls[0], x, h1);
        forward(&ls[1], h1, h2);
        forward(&ls[2], h2, y);
    }
    int64_t sum = 0;
    for (int64_t i = 0; i < n3; i++) sum += y[i];
    printf("%lld\n", (long long)(sum >> 32));
    return 0;
}
