// Fibonacci mod 2^31-1, 30,000,000 iterations.
// LIR twin: ../06_fib_mod.lir (prints 577847172).
const ITERS: i64 = 30_000_000;
const M: i64 = 2147483647;

fn main() {
    let mut a: i64 = 0;
    let mut b: i64 = 1;
    for _ in 0..ITERS {
        let t = a + b;
        if t >= M {
            a = b;
            b = t - M;
        } else {
            a = b;
            b = t;
        }
    }
    println!("{}", a);
}
