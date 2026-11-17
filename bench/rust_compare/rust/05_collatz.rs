// Total stopping time of every start below 1,000,000.
// LIR twin: ../05_collatz.lir (prints 277182070 / 1723519 / 556).
const LIMIT: i64 = 1_000_000;

fn steps(n0: i64) -> i64 {
    let mut n = n0;
    let mut c: i64 = 0;
    while n != 1 && c < 10000 {
        if n % 2 == 0 {
            n /= 2;
        } else {
            n = 3 * n + 1;
        }
        c += 1;
    }
    c
}

fn main() {
    let mut total: i64 = 0;
    let mut best: i64 = 0;
    let mut best_n: i64 = 0;
    for i in 1..LIMIT {
        let s = steps(i);
        total += s;
        if s > best {
            best = s;
            best_n = i;
        }
    }
    println!("{}", total);
    println!("{}", best_n);
    println!("{}", best);
}
