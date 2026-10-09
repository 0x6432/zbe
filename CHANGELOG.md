# Changelog

## 1.4.1 (unreleased)

### Optimizations
- -O2: unsigned 32-bit division/remainder by constants that need a 33-bit
  magic number (e.g. /7, /19, 0xffffffff) now uses multiply + add + shift
  instead of `div`.

### Fixes
- rv64: shift-by-immediate counts are masked to the operand width (fixed in
  the C reference patch too).

### CI / tooling
- CI compiles and passes again on all jobs (lib.sh crash detection, cproc limit
  macros, wine setup, host-independent cli tests, rv64 fix).
- Zig version pinned; PR runs cancel in progress; C reference vendored
  (`tools/qbe-ref.tar.gz`) and cached; releases only on `v*` tags.
- Fuzzers (irfuzz -O2, abifuzz) also run on arm64/rv64 cross jobs.
- New nightly workflow: long fuzz, Zig master (allow-fail), valgrind +
  ReleaseSafe, Lua 5.4.7 test suite built with cproc+zbe, FreeBSD.
- One-off rewrite scripts moved to `tools/archive/`; `__pycache__` removed.

## 1.4.0

- Complete Zig translation of QBE (e786f06) with byte-identical output at
  -O0 / `QBE_COMPAT=1`; the three upstream bugs in BUGS.md fixed; -O1/-O2
  algebraic and division-by-constant rewrites; library mode (libqbe.a, qbe.h).
