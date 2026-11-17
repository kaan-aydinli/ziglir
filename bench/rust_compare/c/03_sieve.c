/* Sieve of Eratosthenes to 2,000,000, five passes.
 * Twin of rust/03_sieve.rs and ../03_sieve.lir (expects 744665). */
#include "common.h"

#define LIMIT 2000000
#define PASSES 5

static unsigned char sieve[LIMIT + 1];

int main(void) {
    i64 total = 0;
    for (int pass = 0; pass < PASSES; pass++) {
        for (i64 i = 0; i <= LIMIT; i++) sieve[i] = 1;
        sieve[0] = 0;
        sieve[1] = 0;

        for (i64 p = 2; p * p <= LIMIT; p++) {
            if (sieve[p] == 1) {
                for (i64 m = p * p; m <= LIMIT; m += p) sieve[m] = 0;
            }
        }

        i64 count = 0;
        for (i64 q = 0; q <= LIMIT; q++) count += sieve[q];
        total += count;
    }
    print_i64(total);
    return 0;
}
