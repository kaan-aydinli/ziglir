/* pi(2,000,000) by trial division.
 * Twin of rust/07_prime_count.rs and ../07_prime_count.lir (expects 148933). */
#include "common.h"

#define LIMIT 2000000

static int is_prime(i64 n) {
    if (n < 2) return 0;
    if (n < 4) return 1;
    if (n % 2 == 0) return 0;
    for (i64 d = 3; d * d <= n; d += 2)
        if (n % d == 0) return 0;
    return 1;
}

int main(void) {
    i64 count = 0;
    for (i64 n = 2; n < LIMIT; n++) count += is_prime(n);
    print_i64(count);
    return 0;
}
