/* splitmix64-style mixing over 20,000,000 values plus popcount accumulation.
 * Twin of rust/08_bitmix.rs and ../08_bitmix.lir (expects 1335377554). */
#include "common.h"

#define ITERS 20000000

static i64 mix(i64 z0) {
    u64 z = (u64)z0;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return (i64)(z ^ (z >> 31));
}

int main(void) {
    i64 acc = 0, bits = 0;
    for (i64 i = 0; i < ITERS; i++) {
        i64 z = mix(i);
        acc += z % 1000003;
        bits += __builtin_popcountll((u64)z);
    }
    print_i64(acc);
    print_i64(bits);
    return 0;
}
