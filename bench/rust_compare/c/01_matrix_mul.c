/* 60x60 integer matrix multiply, accumulated three times.
 * Twin of rust/01_matrix_mul.rs and ../01_matrix_mul.lir (expects 403973). */
#include "common.h"

#define N 60
#define CELLS (N * N)

int main(void) {
    i64 *a = calloc(CELLS, sizeof(i64));
    i64 *b = calloc(CELLS, sizeof(i64));
    i64 *c = calloc(CELLS, sizeof(i64));

    for (i64 i = 0; i < N; i++) {
        for (i64 j = 0; j < N; j++) {
            a[i * N + j] = (i64)((i * 37 + j * 11) % 97);
            b[i * N + j] = (i64)((i * 13 + j * 29) % 89);
        }
    }

    for (int rep = 0; rep < 3; rep++) {
        for (i64 r = 0; r < N; r++) {
            for (i64 k = 0; k < N; k++) {
                i64 av = a[r * N + k];
                for (i64 col = 0; col < N; col++) {
                    i64 bv = b[k * N + col];
                    c[r * N + col] = (c[r * N + col] + av * bv) % 1000003;
                }
            }
        }
    }

    i64 sum = 0;
    for (i64 p = 0; p < CELLS; p++) sum = (sum + c[p]) % 1000003;
    print_i64(sum);
    free(a); free(b); free(c);
    return 0;
}
