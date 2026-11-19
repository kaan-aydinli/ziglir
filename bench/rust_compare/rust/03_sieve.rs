// Sieve of Eratosthenes to 2,000,000, five passes.
// LIR twin: ../03_sieve.lir (prints 744665).
const LIMIT: usize = 2_000_000;
const PASSES: usize = 5;

fn main() {
    let mut sieve = vec![0u8; LIMIT + 1];
    let mut total: i64 = 0;

    for _ in 0..PASSES {
        for i in 0..=LIMIT {
            sieve[i] = 1;
        }
        sieve[0] = 0;
        sieve[1] = 0;

        let mut p = 2usize;
        while p * p <= LIMIT {
            if sieve[p] == 1 {
                let mut m = p * p;
                while m <= LIMIT {
                    sieve[m] = 0;
                    m += p;
                }
            }
            p += 1;
        }

        let mut count: i64 = 0;
        for q in 0..=LIMIT {
            count += sieve[q] as i64;
        }
        total += count;
    }
    println!("{}", total);
}
