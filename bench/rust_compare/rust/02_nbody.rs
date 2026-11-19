// 300 bodies x 60 steps of integer pairwise force accumulation.
// LIR twin: ../02_nbody.lir (prints -2702000).
const N: usize = 300;
const STEPS: usize = 60;

fn main() {
    let mut px = vec![0i64; N];
    let mut py = vec![0i64; N];
    let mut vx = vec![0i64; N];
    let mut vy = vec![0i64; N];

    for i in 0..N {
        let i64i = i as i64;
        px[i] = ((i64i * 2654435761) % 20000) - 10000;
        py[i] = ((i64i * 40503) % 20000) - 10000;
    }

    for _ in 0..STEPS {
        for a in 0..N {
            let axi = px[a];
            let ayi = py[a];
            let mut fx: i64 = 0;
            let mut fy: i64 = 0;
            for b in 0..N {
                if a != b {
                    let dx = px[b] - axi;
                    let dy = py[b] - ayi;
                    let d2 = (dx * dx + dy * dy) / 1000000 + 1;
                    let inv = 100000000 / d2;
                    fx += dx * inv;
                    fy += dy * inv;
                }
            }
            vx[a] = (vx[a] + fx / 1000) % 100000;
            vy[a] = (vy[a] + fy / 1000) % 100000;
        }
    }

    let mut acc: i64 = 0;
    for q in 0..N {
        acc += vx[q] + vy[q];
    }
    println!("{}", acc % 1000000007);
}
