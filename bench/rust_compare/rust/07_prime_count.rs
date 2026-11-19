// pi(2,000,000) by trial division.
// LIR twin: ../07_prime_count.lir (prints 148933).
const LIMIT: i64 = 2_000_000;

fn is_prime(n: i64) -> i64 {
    if n < 2 { return 0; }
    if n < 4 { return 1; }
    if n % 2 == 0 { return 0; }
    let mut d: i64 = 3;
    while d * d <= n {
        if n % d == 0 { return 0; }
        d += 2;
    }
    1
}

fn main() {
    let mut count: i64 = 0;
    let mut n: i64 = 2;
    while n < LIMIT {
        count += is_prime(n);
        n += 1;
    }
    println!("{}", count);
}
