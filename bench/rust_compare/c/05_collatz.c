/* Total stopping time of every start below 1,000,000.
 * Twin of rust/05_collatz.rs and ../05_collatz.lir (expects 131434272). */
#include "common.h"

#define LIMIT 1000000

static i64 steps(i64 n0) {
    i64 n = n0, c = 0;
    while (n != 1 && c < 10000) {
        if (n % 2 == 0) n /= 2;
        else n = 3 * n + 1;
        c++;
    }
    return c;
}

int main(void) {
    i64 total = 0, best = 0, best_n = 0;
    for (i64 i = 1; i < LIMIT; i++) {
        i64 s = steps(i);
        total += s;
        if (s > best) { best = s; best_n = i; }
    }
    print_i64(total);
    print_i64(best_n);
    print_i64(best);
    return 0;
}
