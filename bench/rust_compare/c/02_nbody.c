/* 300 bodies x 60 steps of integer pairwise force accumulation.
 * Twin of rust/02_nbody.rs and ../02_nbody.lir (expects -199280). */
#include "common.h"

#define N 300
#define STEPS 60

static i64 px[N], py[N], vx[N], vy[N];

int main(void) {
    for (i64 i = 0; i < N; i++) {
        px[i] = ((i * 2654435761LL) % 20000) - 10000;
        py[i] = ((i * 40503) % 20000) - 10000;
    }

    for (int s = 0; s < STEPS; s++) {
        for (i64 a = 0; a < N; a++) {
            i64 axi = px[a], ayi = py[a];
            i64 fx = 0, fy = 0;
            for (i64 b = 0; b < N; b++) {
                if (a != b) {
                    i64 dx = px[b] - axi;
                    i64 dy = py[b] - ayi;
                    i64 d2 = (dx * dx + dy * dy) / 1000000 + 1;
                    i64 inv = 100000000 / d2;
                    fx += dx * inv;
                    fy += dy * inv;
                }
            }
            vx[a] = (vx[a] + fx / 1000) % 100000;
            vy[a] = (vy[a] + fy / 1000) % 100000;
        }
    }

    i64 acc = 0;
    for (i64 q = 0; q < N; q++) acc += vx[q] + vy[q];
    print_i64(acc % 1000000007);
    return 0;
}
