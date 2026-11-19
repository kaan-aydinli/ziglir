/* 800x800 16.16 fixed-point Mandelbrot escape-time count, 400 max iterations.
 * Twin of rust/04_mandelbrot.rs and ../04_mandelbrot.lir (expects 18388003). */
#include "common.h"

#define W 800
#define H 800
#define MAX_ITER 400
#define ONE 65536

int main(void) {
    i64 total = 0;
    for (i64 y = 0; y < H; y++) {
        i64 ci = (y * 262144) / H - 131072;
        for (i64 x = 0; x < W; x++) {
            i64 cr = (x * 393216) / W - 262144;
            i64 zr = 0, zi = 0, it = 0;
            int alive = 1;
            while (it < MAX_ITER && alive == 1) {
                i64 zr2 = (zr * zr) / ONE;
                i64 zi2 = (zi * zi) / ONE;
                if (zr2 + zi2 > 4 * ONE) {
                    alive = 0;
                } else {
                    zi = 2 * ((zr * zi) / ONE) + ci;
                    zr = zr2 - zi2 + cr;
                }
                it++;
            }
            total += it;
        }
    }
    print_i64(total % 1000000007);
    return 0;
}
