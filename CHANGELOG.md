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
- The 552 `O*` op aliases are gone: ops are written as enum literals
  (`i.op == .add`, `emit(.copy, ...)`) or `Opc.storew.offset(k)`; op ranges
  are `Opc.cmpw_first`/`Opc.cmpw_last` etc. `INS`, `INS0`, `emit` and the
  parser's `mkins` take a typed `Opc`, and op locals/tables in the ABI, isel
  and load code are `Opc` instead of `i32`.
- Class, jump and use-kind aliases (`Kw`, `Jjmp`, `UPhi`, ...; 191
  declarations) are gone too. Enum values are bare literals (`.w`, `.jmp`,
  `.phi`, `.add`) wherever the type is inferred, and qualified (`Cls.w`,
  `Opc.storew.offset(k)`) only where it is not.
- `Blk`, `Phi` and `Fn` have slice accessors (`b.insns()`, `b.preds()`,
  `b.frons()`, `p.args()`, `p.blks()`, `f.tmps()`, `f.cons()`, `f.mems()`,
  `f.blks()`); loops use them instead of `x.ins[0..x.nins]` or index
  counters. Simple counted `while` loops are `for (a..b) |i|`, and
  predecessor searches are `for ... else` expressions.
- Macro-style helpers use Zig names: `TMP`/`CON`/`SLOT`/`TYPE`/`CALL`/`MEM`/`INT`
  are `tmpRef`/`conRef`/`slotRef`/`typeRef`/`callRef`/`memRef`/`intRef`;
  `INS`/`INS0` are `mkIns`/`insOp`; `KBASE`/`KWIDE` are `clsBase`/`clsWide`;
  `BIT` is `bitAt`, `INRANGE` is `inRange`, `MASK` is `lowMask`, and
  `ALIGN_UP`/`ALIGN_DOWN` are `alignUp`/`alignDown`.
- `eallocSlice(T, n)` returns a `[]T`; it replaces `ealloc(T, n)[0..n]`.
- The constant folder switches on the `Opc` enum, so its 47 case labels are
  bare literals (`.add =>`) instead of `ops.num(.add) =>`.
- `Opc.within(first, last)` checks op ranges; `iscmp` takes an `Opc`, and the
  alloc-slot loops in the instruction selectors count with `Opc.diff`.
- `Oaddtbl` is `add_table`; the `UXXX` alias is gone (use `.xxx`). `assoccon`
  keeps its op as an `Opc`.
- The op predicates (`isstore`, `isload`, `isalloc`, `isext`, `ispar`, `isarg`,
  `isparbh`, `isargbh`, `isxsel`) take an `Opc`, and `isret`/`isretbh` take a `J`,
  instead of `anytype`. amd64 `fixarg` keeps its op as an `Opc`.
- Literal class numbers use `Cls.w.int()` instead of `knum(.w)` (91 sites), and
  class fields use `i.cls.int()` instead of `knum(i.cls)`.

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
