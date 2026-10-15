# Changelog

## 1.4.1 (unreleased)

### Optimizations
- -O1/-O2 AMD64: recognize long constant shifts by 1..3 as scaled memory
  indexes, including multiplication lowered to shifts. Word shifts are not
  widened; -O0 and compatibility-mode instruction selection are unchanged.
- -O2: unsigned 32-bit division/remainder by constants that need a 33-bit
  magic number (e.g. /7, /19, 0xffffffff) now uses multiply + add + shift
  instead of `div`.

### Fixes
- Zig library output failures now return `WriteFailed` instead of terminating
  the embedding process. Output-unit floating constants and debug-file state
  are discarded after failed or successful library compilations.
- GVN releases its per-function hash table on failed constant folding as well
  as success; repeated failure/recovery and empty functions are covered.
- -O1/-O2: folded constant `jnz` conditions now test only their low 32 bits,
  as required by the IL specification. -O0 retains upstream output (BUGS #8).
- Input-driven backend failures (unsupported extern/thread, extern offsets,
  allocation overflow, invalid constants, env with varargs, and initialized
  common data) now return `InvalidInput` instead of aborting. Diagnostics
  retain the C-compatible text; the CLI exits 1 and `qbe_compile` returns 3.

- rv64: shift-by-immediate counts are masked to the operand width (fixed in
  the C reference patch too).
- rv64: float-flattened struct arguments are no longer passed on the stack
  when general-purpose registers run out (BUGS.md #6, also in the C patch).
- arm64: `va_start` after an aggregate that did not fit in registers no longer
  leaves stale va register counts (BUGS.md #7, also in the C patch).

### Code quality
- Comparison decoding returns an optional class/condition value instead of a
  boolean plus output parameters; all target selectors use the typed result.
- Native benchmark fixtures use defined wrapping arithmetic and undergo UBSan
  checks; the full-suite entry point propagates build and suite failures.
- Release package builds select baseline CPUs rather than the build host CPU.
- Benchmark and memory-check harnesses reject failed executions rather than
  timing/counting them as successes, with dedicated harness regressions.
- Parser operand validation checks the reference kind before indexing temporary
  storage; high type/constant IDs are covered by six-target comparison tests.
- Active Fn/Blk/Phi/type-table consumers across passes and targets use bounded
  views. Capacity-aware instruction-prefix replacement centralizes overlap-safe
  ABI/register-allocation edits without changing stored IR layouts.
- Constant insertion/lowering snapshots values across possible vector growth.
  Parser-owned types/lexer buffers are cleaned up on success and invalid input;
  failed parses no longer retain stale block/temp lookup entries between calls.
- Instruction builders use active slices and growth-safe self-appends, with
  block wrappers preserving the stored IR fields. CFG union-find returns typed
  block roots instead of casting optional pointers; temporary use-list readers
  share a bounded view with an empty-storage guard.
- Parser name caches, debug-file lists, intern buckets, load insertion logs,
  and memory-coalescing histories use bounded slices while retaining their
  established ownership, reuse, ordering and numeric IDs.
- SSA/GVN use registration accepts typed payloads instead of erased pointers;
  bitset helpers expose bounded word views, and parser control states are an
  enum. Stored extern/ABI layouts and compatibility-mode output are unchanged.
- Register-allocation memory views and per-block register-map arrays use
  bounded slices. Spill-limit scratch storage carries its cached capacity
  in a slice, retaining reuse while sorting only the current active prefix.
- AMD64 address-matcher number tables and constant views are bounded slices,
  including the matcher bytecode interpreter. The number table retains its
  original allocation length even when instruction selection creates temps.
- SSA phi-class lookup, temporary debug dumps, liveness inputs, and spill/
  register-allocation temporary state use bounded slices. The spiller uses
  the slice length instead of a duplicate cached temporary count.
- Instruction duplication/copying and stable sorting take bounded slices
  instead of pointer/count pairs. Instruction copies preserve overlapping
  ranges and return the unused destination slice for safe chaining.
- AMD64 address-pattern numbering and SysV argument classification take
  typed `Opc` parameters instead of integer opcodes; their switches use enum
  literals and ABI opcode normalization uses `offset`/`diff`.
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
- `emit`, `newtmp` and `mkIns` take a `Cls` instead of `anytype`. Literal `0`
  classes are `.w`; callers that still hold integer classes convert with `kof`.
- amd64 `fixarg`, `selcmp` and `sel` keep classes as `Cls`. `Cls` gains `e = -2`
  (C: `Ke`), the erroneous class the op table uses for invalid operand classes,
  so converting an `argcls` result can no longer panic.
- `iscmp` reports the comparison class as a `Cls`. The arm64 and rv64 `fixarg`,
  `selcmp`, `imm` and `fixcmp` helpers take a `Cls`, like amd64.
- The ABI class arrays (sysv, winabi, arm64, rv64) hold `Cls` values, as do their
  register helpers (`rarg`, `register_for_arg`, `sttmps`, `ldregs`, `isfloatv`)
  and the arm64 HFA base class.
- `argcls` returns a `Cls`. Return-value classes in the ABIs, the rega parallel-move
  list, load's slice and helper classes, gvn's `cmpeqz`/`zeroval`/`usecls`/`propjnz0`
  and amd64 `emitcopy` all use `Cls`. Only the parser and `mem` (which compares raw
  op-table entries) still convert integer classes with `kof`.
- Input errors are a Zig error (`all.Error`, `error.InvalidInput`) instead of
  exiting the process. The parser and the backend checks (ABI alignment limits,
  invalid alloc sizes, unused stack slots, SSA checks, invalid data strings) return
  it via `fail()`, and it propagates with `try` through the pass pipeline and the
  target `abi0`/`abi1`/`isel` hooks. The `qbe` binary prints the same message and
  exits 1; the library `compile()` returns `error.InvalidInput` and `qbe_compile`
  returns 3 rather than killing the host. The exiting `err()` is removed; `die()`
  remains for internal invariant failures and still prints `dying:` like C qbe.
- The spiller, register allocator and load optimizer keep their per-function state
  in a documented `State` struct (`st`) instead of 21 loose file-level globals.
- The same applies to the data/debug emitter, SSA construction, GVN and the arm64
  vararg counters. Register tables that are never written (amd64 rsave/rclob,
  arm64/rv64 argument registers) are `const`, and `Target.rsave` is `[*]const i32`.
- The parser keeps its 16 lexer/parser variables in a `State` struct; the arm64
  and rv64 rsave/rclob tables are `const` too.
- The amd64/arm64/rv64 emitters and `util` keep their label counters, scratch
  buffers and fresh-temp counter in per-file `State` structs.
- `all.optab` is `const` (it was never written), and the library target-name
  cache in `lib.zig` is a `State` struct. The remaining `all.zig` globals (target,
  debug flags, instruction buffer, type table, output writers) stay module-level
  as the program-wide compile context, matching C qbe.

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
