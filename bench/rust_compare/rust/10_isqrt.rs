// isqrt over 2,000,000 values plus icbrt over 300,000.
// LIR twin: ../10_isqrt.lir (prints 7451059694 / 74497521).
fn isqrt(n: i64) -> i64 {
    if n < 2 { return n; }
    let mut x = n;
    let mut y = (x + 1) / 2;
    while y < x {
        x = y;
        y = (x + n / x) / 2;
    }
    x
}

fn icbrt(n: i64) -> i64 {
    if n < 8 { return n; }
    let mut x = n / 3 + 1;
    loop {
        let y = (2 * x + n / (x * x)) / 3;
        if y >= x { return x; }
        x = y;
    }
}

fn main() {
    let mut sum: i64 = 0;
    for i in 0..2_000_000i64 {
        sum += isqrt(i);
    }
    let mut cube_sum: i64 = 0;
    for j in 0..300_000i64 {
        cube_sum += icbrt(j);
    }
    println!("{}", sum);
    println!("{}", cube_sum);
}
