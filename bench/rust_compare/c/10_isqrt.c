/* isqrt over 2,000,000 values plus icbrt over 300,000.
 * Twin of rust/10_isqrt.rs and ../10_isqrt.lir (expects 1884618085). */
#include "common.h"

static i64 isqrt_(i64 n) {
    if (n < 2) return n;
    i64 x = n, y = (x + 1) / 2;
    while (y < x) {
        x = y;
        y = (x + n / x) / 2;
    }
    return x;
}

static i64 icbrt(i64 n) {
    if (n < 8) return n;
    i64 x = n / 3 + 1;
    for (;;) {
        i64 y = (2 * x + n / (x * x)) / 3;
        if (y >= x) return x;
        x = y;
    }
}

int main(void) {
    i64 sum = 0;
    for (i64 i = 0; i < 2000000; i++) sum += isqrt_(i);
    i64 cube_sum = 0;
    for (i64 j = 0; j < 300000; j++) cube_sum += icbrt(j);
    print_i64(sum);
    print_i64(cube_sum);
    return 0;
}
