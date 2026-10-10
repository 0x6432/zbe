# Changelog

## 1.4.1 (unreleased)

### Optimizations
- -O2: unsigned 32-bit division/remainder by constants that need a 33-bit
  magic number (e.g. /7, /19, 0xffffffff) now uses multiply + add + shift
  instead of `div`.

### Fixes
- rv64: shift-by-immediate counts are masked to the operand width (fixed in
  the C reference patch too).
- rv64: float-flattened struct arguments are no longer passed on the stack
  when general-purpose registers run out (BUGS.md #6, also in the C patch).
- arm64: `va_start` after an aggregate that did not fit in registers no longer
  leaves stale va register counts (BUGS.md #7, also in the C patch).

### Code quality
- Use kinds, alias results and alias kinds are Zig enums (old names kept as
  aliases); switches over them are now checked for missing cases.
- Instruction, temp and phi classes share one type (`i16`); 22 redundant
  casts removed.
- Instruction opcodes are a Zig enum (`Opc`); `Oadd` etc. remain as
  aliases and `tools/gen_ops.py` generates the enum. Op arithmetic goes through
  `offset`/`diff`/`int` helpers.
- Value classes are a Zig enum (`Cls`: `x`, `w`, `l`, `s`, `d`); `Kw` etc.
  remain as aliases. The emitters' `Ki`/`Ka` wildcards use a separate
  pattern enum. Output is byte-identical to before.

### CI / tooling
- CI compiles and passes again on all jobs (lib.sh crash detection, cproc limit
  macros, wine setup, host-independent cli tests, rv64 fix).
- Zig version pinned; PR runs cancel in progress; C reference vendored
  (`tools/qbe-ref.tar.gz`) and cached; releases only on `v*` tags.
- Fuzzers (irfuzz -O2, abifuzz) also run on arm64/rv64 cross jobs.
- abifuzz sign/zero-extends sub-word parameters in the callee and uses
  `long long` so it is correct on LLP64 Windows; `tools/bugs.sh` checks wide
  shift immediates on arm64 and rv64 too.
- New nightly workflow: long fuzz, Zig master (allow-fail), valgrind +
  ReleaseSafe, Lua 5.4.7 test suite built with cproc+zbe, FreeBSD.
- One-off rewrite scripts moved to `tools/archive/`; `__pycache__` removed.

## 1.4.0

- Complete Zig translation of QBE (e786f06) with byte-identical output at
  -O0 / `QBE_COMPAT=1`; the three upstream bugs in BUGS.md fixed; -O1/-O2
  algebraic and division-by-constant rewrites; library mode (libqbe.a, qbe.h).
