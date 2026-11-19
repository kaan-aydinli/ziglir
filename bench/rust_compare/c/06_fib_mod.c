/* Fibonacci mod 2^31-1, 30,000,000 iterations.
 * Twin of rust/06_fib_mod.rs and ../06_fib_mod.lir (expects 577847172). */
#include "common.h"

#define ITERS 30000000
#define M 2147483647LL

int main(void) {
    i64 a = 0, b = 1;
    for (i64 i = 0; i < ITERS; i++) {
        i64 t = a + b;
        if (t >= M) { a = b; b = t - M; }
        else { a = b; b = t; }
    }
    print_i64(a);
    return 0;
}
