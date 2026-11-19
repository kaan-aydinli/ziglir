// 800x800 16.16 fixed-point Mandelbrot escape-time count, 400 max iterations.
// LIR twin: ../04_mandelbrot.lir (prints 18388003).
const W: i64 = 800;
const H: i64 = 800;
const MAX_ITER: i64 = 400;
const ONE: i64 = 65536;

fn main() {
    let mut total: i64 = 0;
    for y in 0..H {
        let ci = (y * 262144) / H - 131072;
        for x in 0..W {
            let cr = (x * 393216) / W - 262144;
            let mut zr: i64 = 0;
            let mut zi: i64 = 0;
            let mut it: i64 = 0;
            let mut alive: i64 = 1;
            while it < MAX_ITER && alive == 1 {
                let zr2 = (zr * zr) / ONE;
                let zi2 = (zi * zi) / ONE;
                if zr2 + zi2 > 4 * ONE {
                    alive = 0;
                } else {
                    zi = 2 * ((zr * zi) / ONE) + ci;
                    zr = zr2 - zi2 + cr;
                }
                it += 1;
            }
            total += it;
        }
    }
    println!("{}", total % 1000000007);
}
