/* 1-D k-means, 100,000 points, k=8, 15 Lloyd iterations.
 * Twin of rust/11_kmeans.rs and ../11_kmeans.lir (expects 22216541). */
#include "common.h"

#define N 100000
#define K 8
#define ITERS 15

static i64 pts[N];
static i64 cen[K];
static i64 sum_[K], cnt_[K];

int main(void) {
    for (i64 i = 0; i < N; i++) {
        pts[i] = (i64)((u64)(i + 1) * 2654435761ULL) % 1000000;
    }
    for (i64 c = 0; c < K; c++) cen[c] = c * 125000;

    for (int it = 0; it < ITERS; it++) {
        for (int z = 0; z < K; z++) { sum_[z] = 0; cnt_[z] = 0; }
        for (i64 p = 0; p < N; p++) {
            i64 v = pts[p];
            i64 best = 0, best_d = INT64_MAX;
            for (i64 ci = 0; ci < K; ci++) {
                i64 d = v - cen[ci];
                i64 ad = d < 0 ? -d : d;
                if (ad < best_d) { best_d = ad; best = ci; }
            }
            sum_[best] += v;
            cnt_[best] += 1;
        }
        for (int q = 0; q < K; q++)
            if (cnt_[q] > 0) cen[q] = sum_[q] / cnt_[q];
    }

    i64 acc = 0;
    for (i64 w = 0; w < K; w++) acc += cen[w] * (w + 1);
    print_i64(acc % 1000000007);
    return 0;
}
