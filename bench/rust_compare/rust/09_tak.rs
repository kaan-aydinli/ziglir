// tak(24, 16, 8) - call overhead and deep recursion.
// LIR twin: ../09_tak.lir (prints 9).
fn tak(x: i64, y: i64, z: i64) -> i64 {
    if y >= x {
        return z;
    }
    tak(tak(x - 1, y, z), tak(y - 1, z, x), tak(z - 1, x, y))
}

fn main() {
    println!("{}", tak(24, 16, 8));
}
