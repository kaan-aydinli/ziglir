/* tak(24, 16, 8) - call overhead and deep recursion.
 * Twin of rust/09_tak.rs and ../09_tak.lir (expects 9). */
#include "common.h"

static i64 tak(i64 x, i64 y, i64 z) {
    if (y >= x) return z;
    return tak(tak(x - 1, y, z), tak(y - 1, z, x), tak(z - 1, x, y));
}

int main(void) {
    print_i64(tak(24, 16, 8));
    return 0;
}
