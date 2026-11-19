# The embedded standard library

LIR ships a zero-wrapper standard library: the modules are plain LIR source
embedded in the compiler executable (`src/bootstrap/stdlib.zig`) and inlined at
compile time. There is nothing to install, no runtime to link, and no version
skew between compiler and library.

```lir
import algo
import collections
import fmt
import str

fn main() -> i64 {
    println(str_trim("  lir  "))       // "lir"  — modules are not namespaced
    let ring = rb_new(8)                // ring buffer from `collections`
    rb_push(ring, 1)
    printInt(gcd_i64(12, 18))           // 6    — from `algo`
    println("")
    println(hex_encode("hi"))           // 6869 — from `fmt`
    rb_free(ring)                       // explicit, no GC
    return 0
}
```

**Rules that follow from that design:**

* `import <name>` must be the first statement of the file, one module per line.
* Members are **not** namespaced: `import str` gives you `str_trim`, not
  `str.trim`. Name collisions with your own functions are reported by `sema`.
* Every function is ordinary LIR — you can read the source with
  `lir ast`/`--emit-ir`, and step it in `--backend=vm`.
* Allocating helpers return raw pointers and require explicit `@free`/
  `@*_free`. Nothing is garbage collected.
* A module must be imported to be available; importing an unknown name fails at
  compile time with `LIR-E4001` and a suggestion.

The compiler rejects an unknown module at compile time rather than silently
emitting a stub — see `lir explain errors`.

## Modules

| Module | Purpose |
|---|---|
| `core` | min/max/clamp/abs, saturating arithmetic, `itoa`/`utoa`, raw syscalls, terminal size, raw mode, key reading |
| `io` | stderr printing, file read/append/exists/size |
| `os` | `argc`/`argv`, `getenv`, `sleep_ms`, `now_ns` |
| `sys` | pid/ppid/uid, unlink, mkdir |
| `net` | byte order, IPv4 packing, TCP socket/bind/accept/connect, send/recv |
| `crypto` | CSPRNG (`random_u64`, `random_bytes`, tokens), constant-time compare, secure zero |
| `json` | quoting and key/value emission helpers |
| `math` | π/τ/e constants, float abs/sqrt/trig/exp/log/pow helpers |
| `testing` | `assert`, `assertEq`, `assertEqStr`, `assertEqFloat`, timestamps for `#[test]` |
| `str` | prefix/suffix/index/contains/trim/case/split/join/replace |
| `algo` | gcd/lcm/pow, heap sort, binary search, primes, levenshtein, glob match |
| `collections` | ring buffer, bit set, min-heap/priority queue, deque, stack, vector |
| `hash` | FNV-1a, CRC32/CRC32C, Adler32, Murmur3 |
| `fmt` | hex encode/decode, base64 encode/decode, URL encode |
| `time` | now/diff/sleep in ns/µs/ms/s, formatting helpers |
| `http` | status text, response builder, method/path parsing |

## Function index


### `core` (18 functions)

`min_i64`, `max_i64`, `clamp_i64`, `abs_i64`, `checked_add`, `checked_sub`, `checked_mul`, `saturating_add`, `saturating_sub`, `signum`, `itoa`, `utoa`, `syscall_write`, `syscall_read`, `syscall_exit`, `term_size`, `set_raw_mode`, `read_key`

### `io` (7 functions)

`eprint`, `eprintln`, `append_file`, `file_exists`, `file_size`, `read_file`, `write_file`

### `os` (5 functions)

`argc`, `argv`, `getenv`, `sleep_ms`, `now_ns`

### `sys` (5 functions)

`getpid`, `getppid`, `getuid`, `unlink_file`, `mkdir_dir`

### `net` (9 functions)

`htons`, `ipv4`, `tcp_socket`, `tcp_bind_listen`, `tcp_accept`, `tcp_connect`, `sock_send`, `sock_recv`, `sock_close`

### `crypto` (9 functions)

`random_u64`, `random_range`, `random_bytes`, `random_token_hex`, `secure_zero`, `const_time_eq`, `const_time_str_eq`, `constant_time_select`, `fnv1a_64`

### `json` (3 functions)

`json_quote`, `json_kv_str`, `json_kv_int`

### `math` (31 functions)

`pi`, `tau`, `e_const`, `abs_f`, `sqrt_f`, `sin_f`, `cos_f`, `floor_f`, `ceil_f`, `round_f`, `clamp_f`, `lerp`, `deg_to_rad`, `rad_to_deg`, `tan_f`, `hypot`, `smoothstep`, `vec2_dot`, `vec2_len_sq`, `vec2_dist_sq`, `is_prime_i64`, `next_prime_i64`, `log2_i64`, `log10_i64`, `factorial_i64`, `fibonacci_i64`, `pow_f`, `exp_f`, `ln_f`, `atan_f`, `atan2_f`

### `testing` (12 functions)

`now`, `timestampDiff`, `assert`, `assertEq`, `assertEqStr`, `assertEqFloat`, `assertRange`, `assert_true`, `assert_false`, `assert_eq_i64`, `assert_ne_i64`, `assert_eq_str`

### `str` (22 functions)

`str_starts_with`, `str_ends_with`, `str_index_of`, `str_contains`, `str_trim`, `str_to_upper`, `str_to_lower`, `str_repeat`, `str_count`, `str_replace`, `str_reverse`, `str_pad_left`, `str_pad_right`, `str_is_numeric`, `str_is_alpha`, `str_is_alphanumeric`, `str_levenshtein`, `str_glob_match`, `str_trim_left`, `str_trim_right`, `str_capitalize`, `str_join`

### `algo` (21 functions)

`gcd_i64`, `lcm_i64`, `pow_i64`, `sort_array_i64`, `sort_i64`, `bsearch_array_i64`, `binary_search_i64`, `reverse_array_i64`, `sum_array_i64`, `quick_sort_range`, `quick_sort_i64`, `lower_bound_i64`, `upper_bound_i64`, `min_element_i64`, `max_element_i64`, `shuffle_array_i64`, `dedup_sorted_i64`, `is_sorted_i64`, `count_occurrences_i64`, `find_index_i64`, `fill_array_i64`

### `collections` (54 functions)

`rb_new`, `rb_cap`, `rb_len`, `rb_is_empty`, `rb_is_full`, `rb_push`, `rb_pop`, `rb_peek`, `rb_free`, `bitset_new`, `bitset_set`, `bitset_clear`, `bitset_test`, `bitset_toggle`, `bitset_count`, `bitset_any`, `bitset_none`, `bitset_all`, `bitset_union`, `bitset_intersect`, `bitset_free`, `heap_new`, `heap_len`, `heap_push`, `heap_pop`, `heap_peek`, `heap_free`, `deque_new`, `deque_len`, `deque_push_back`, `deque_push_front`, `deque_pop_front`, `deque_pop_back`, `deque_peek_front`, `deque_peek_back`, `deque_free`, `stack_new`, `stack_len`, `stack_cap`, `stack_is_empty`, `stack_is_full`, `stack_push`, `stack_pop`, `stack_peek`, `stack_free`, `queue_new`, `queue_cap`, `queue_len`, `queue_is_empty`, `queue_is_full`, `queue_push`, `queue_pop`, `queue_peek`, `queue_free`

### `hash` (7 functions)

`fnv1a_64`, `fnv1a_buf`, `crc32`, `crc32_buf`, `crc32c`, `adler32`, `murmur3_32`

### `fmt` (10 functions)

`hex_encode`, `hex_nibble`, `hex_decode`, `base64_encode`, `b64_char_val`, `base64_decode`, `int_to_hex`, `hex_to_int`, `int_to_bin`, `format_bytes`

### `time` (9 functions)

`time_now_ns`, `time_now_ms`, `time_now_sec`, `time_diff_ms`, `time_diff_us`, `time_sleep_ms`, `is_leap_year`, `days_in_month`, `format_duration_ms`

### `http` (4 functions)

`http_status_text`, `http_build_response`, `http_parse_method`, `http_parse_path`

## Conventions

* Names carry their type when overloading is needed: `min_i64`, `sqrt_f`.
* Every allocating constructor has a matching `*_free` (`rb_free`, `heap_free`,
  `dq_free`, `stack_free`, `vec_free`, `map_free`).
* Functions that can fail return a sentinel (`-1`, `0`, null pointer) rather than
  raising; check the return value. `Option`/`Result` are the idiomatic wrapper
  when you want `?`/`??` handling.
* Bounds are checked at runtime where the compiler can prove a length: index past
  a heap array traps (exit 132) instead of reading adjacent memory.

## Writing new library code

Library code follows the same rules as user code: no `extern`, no `unsafe`, no
`asm`. It is compiled by `zig build test` through the catalogue conformance
tests, so a module that stops compiling breaks CI. Add new modules to
`src/bootstrap/stdlib.zig` and `langref.zig`'s `import` note, then regenerate
`docs/LANGUAGE_REFERENCE.md`.
