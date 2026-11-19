// splitmix64-style mixing over 20,000,000 values plus popcount accumulation.
// LIR twin: ../08_bitmix.lir (prints 1335377554 / 639992236).
const ITERS: i64 = 20_000_000;

fn mix(z0: i64) -> i64 {
    let mut z = z0 as u64;
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58476D1CE4E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D049BB133111EB);
    (z ^ (z >> 31)) as i64
}

fn main() {
    let mut acc: i64 = 0;
    let mut bits: i64 = 0;
    for i in 0..ITERS {
        let z = mix(i);
        acc += z % 1000003;
        bits += z.count_ones() as i64;
    }
    println!("{}", acc);
    println!("{}", bits);
}
