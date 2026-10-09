# zbe: QBE in Zig

A complete Zig translation of the [QBE](https://c9x.me/compile/) compiler
backend, with the upstream bugs fixed, extra optimizations, and a library mode.

## Build

    zig build            # zig-out/bin/qbe, zig-out/lib/libqbe.a, zig-out/include/qbe.h
    zig build test       # unit tests
    sh tools/all.sh      # full regression suite

## Command line

    qbe [OPTIONS] {file.ssa, -}
      -o file          output file
      -t <target>      amd64_sysv (default), amd64_apple, amd64_win, arm64, arm64_apple, rv64
      -d <flags>       debug dumps (P M N C G K A I L S R)
      -O<level>        0 = output identical to upstream qbe; 1 = algebraic identities;
                       2 = also division by constants (default). -O = -O1, -O3/-Os = -O2
      --list-targets   list targets
      --version        print the version
      --help, -h       help

If `QBE_COMPAT=1` is set in the environment, qbe behaves exactly like upstream
qbe: `-O0`, the upstream help text, and long options rejected.

## Optimizations beyond upstream (only on integer values in virtual registers)

| level | rewrite |
|---|---|
| -O1 | `x*0`, `x&0` → 0; `x*1`, `x/1`, `x+0`, `x-0`, `x\|0`, `x^0`, shifts by 0 (count mod width), `x&-1` → x |
| -O1 | `x*2^n` → `x<<n`; `x*-1` → `neg x`; `x-x`, `x^x` → 0; `x&x`, `x\|x` → x |
| -O2 | signed `x/2^n`, `x%2^n` → shift sequence (no idiv) |
| -O2 | unsigned 32-bit `x/d`, `x%d` → one 64-bit multiply + shift (magic < 2^32), or multiply + shift + add for divisors needing a 33-bit magic (e.g. d = 7) |

Upstream qbe already performs SSA construction, copy elimination, constant
folding, GVN, GCM (loop-invariant hoisting), load forwarding, dead code
removal, CFG simplification and if-conversion.

## Library mode

Zig (`b.dependency("zbe", .{}).module("qbe")`):

```zig
const qbe = @import("qbe");
var aw: std.Io.Writer.Allocating = .init(gpa);
try qbe.compile(il_text, .{ .target = "arm64", .opt = 2 }, &aw.writer);
```

C (`#include "qbe.h"`, link `libqbe.a` and libc):

```c
char *as; size_t n;
if (qbe_compile(text, len, "rv64", 2, &as, &n) == 0) { fwrite(as, 1, n, stdout); qbe_free(as); }
```

The library has the same limitations as qbe itself: it is not thread-safe, and
malformed IL is fatal (the error goes to stderr and the process exits with 1).

## Tests

`tools/all.sh` runs these checks:

- byte-for-byte comparison with the bug-fixed C reference on all 6 targets,
  including debug dumps
- the corpus, edge cases (291), the upstream-bug checks (89) and unit tests
- the optimization tests: `opt.sh` (46), `opt2.py` (1348 division functions
  × 3 levels, run natively), and `optsweep.sh` (every target × level must
  succeed wherever C qbe does)
- the library tests (`lib.sh`, 1400+ comparisons with the CLI), `cli.sh`, and
  native-execution fuzzers

## Testing and CI

- `.github/workflows/ci.yml` (push, PR, tags `v*`): unit tests, the test
  suite and byte-for-byte comparison against the C reference qbe on
  amd64/arm64/rv64/Windows/macOS, cross runs under qemu, cproc and hare
  bootstraps, fuzzers. Zig is pinned (`ZIG_VERSION`); the C reference is built
  from the vendored `tools/qbe-ref.tar.gz` + `tools/qbe-cfix.patch` and cached.
- `.github/workflows/nightly.yml` (daily + manual): long fuzz runs, Zig master
  (allowed to fail), valgrind (`tools/memcheck.sh`) and a ReleaseSafe test run,
  real programs (`tools/programs.sh`: Lua 5.4.7 built with cproc+zbe running
  Lua's own test suite), and a FreeBSD VM job.
- Releases are created only from `v*` tags; notes come from `CHANGELOG.md`.

Locally: `sh tools/all.sh` (full suite), `sh tools/ci.sh <suite>` (what CI runs).
