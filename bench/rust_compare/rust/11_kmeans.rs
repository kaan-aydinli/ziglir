// 1-D k-means, 100,000 points, k=8, 15 Lloyd iterations.
// LIR twin: ../11_kmeans.lir (prints 22672602).
const N: usize = 100_000;
const K: usize = 8;
const ITERS: usize = 15;

fn main() {
    let mut pts = vec![0i64; N];
    let mut cen = vec![0i64; K];

    for i in 0..N {
        let v = ((i as i64 + 1).wrapping_mul(2654435761)) % 1000000;
        pts[i] = v;
    }
    for c in 0..K {
        cen[c] = c as i64 * 125000;
    }

    for _ in 0..ITERS {
        let mut sum = vec![0i64; K];
        let mut cnt = vec![0i64; K];
        for p in 0..N {
            let v = pts[p];
            let mut best = 0usize;
            let mut best_d = i64::MAX;
            for ci in 0..K {
                let d = v - cen[ci];
                let ad = if d < 0 { -d } else { d };
                if ad < best_d {
                    best_d = ad;
                    best = ci;
                }
            }
            sum[best] += v;
            cnt[best] += 1;
        }
        for q in 0..K {
            if cnt[q] > 0 {
                cen[q] = sum[q] / cnt[q];
            }
        }
    }

    let mut acc: i64 = 0;
    for w in 0..K {
        acc += cen[w] * (w as i64 + 1);
    }
    println!("{}", acc % 1000000007);
}
