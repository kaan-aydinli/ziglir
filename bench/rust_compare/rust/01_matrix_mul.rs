// 60x60 integer matrix multiply, accumulated three times.
// LIR twin: ../01_matrix_mul.lir (prints 403973).
const N: usize = 60;
const CELLS: usize = N * N;

fn main() {
    let mut a = vec![0i64; CELLS];
    let mut b = vec![0i64; CELLS];
    let mut c = vec![0i64; CELLS];

    for i in 0..N {
        for j in 0..N {
            let ia = ((i * 37 + j * 11) % 97) as i64;
            let ib = ((i * 13 + j * 29) % 89) as i64;
            a[i * N + j] = ia;
            b[i * N + j] = ib;
        }
    }

    for _ in 0..3 {
        for r in 0..N {
            for k in 0..N {
                let av = a[r * N + k];
                for col in 0..N {
                    let bv = b[k * N + col];
                    let cv = c[r * N + col];
                    c[r * N + col] = (cv + av * bv) % 1000003;
                }
            }
        }
    }

    let mut sum: i64 = 0;
    for p in 0..CELLS {
        sum = (sum + c[p]) % 1000003;
    }
    println!("{}", sum);
}
