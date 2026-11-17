/* Shared helpers for the C twins of the Rust workloads.
 *
 * The Rust twins print with println!("{}", v), which formats and writes to
 * stdout. print_i64 does the same by hand so the C side pays the same output
 * cost and does not drag in printf's floating-point machinery. */
#ifndef RC_COMMON_H
#define RC_COMMON_H

#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>

typedef int64_t i64;
typedef uint64_t u64;

static void print_i64(i64 v) {
    char buf[32];
    char *p = buf + sizeof buf;
    int neg = v < 0;
    u64 u = neg ? (u64)(-(v + 1)) + 1 : (u64)v;
    *--p = '\n';
    do {
        *--p = (char)('0' + (u % 10));
        u /= 10;
    } while (u != 0);
    if (neg) *--p = '-';
    size_t len = (size_t)(buf + sizeof buf - p);
    ssize_t written = 0;
    while ((size_t)written < len) {
        ssize_t n = write(1, p + written, len - (size_t)written);
        if (n <= 0) break;
        written += n;
    }
}

#endif
