# HANDOFF – QBE → Zig translation

Updated: 20261009-104444 UTC (backup 48)

## Goal
Translate QBE (C, cloned at /data/qbe-c, HEAD e786f06) to latest Zig master.
Phase 1: 1:1 translation (src/*.zig, C pointers, libc). Phase 2: test with QBE
tests, Hare, cproc, own tests. Phase 3: canonical/idiomatic Zig rewrite.
Backups every 10–15 min: ALWAYS update HANDOFF.md first, then run
/data/backup.sh, which commits and pushes to github.com/0x6432/zbe (see
"Backups" at the end). Tarballs are no longer used.

## Restore after sandbox reset
1. git clone https://github.com/0x6432/zbe /data/qbe-zig; cp tools/backup.sh /data/.
2. Install Zig master into /data/tools/zig (0.18.0-dev.35+5e754304d was used).
3. git clone git://c9x.me/qbe.git (https fails) /data/qbe-c && make (reference binary).

## Zig master gotchas
- `**` array repeat removed -> `@splat`; `usingnamespace` removed.
- C varargs: `fn f(fmt: [*c]const u8, ...) callconv(.c)`, pass `ap` to vfprintf.
- No tabs in comments; while-body `if` w/o braces followed by assignment fails
  to parse -> use braces.
- signed `/` and `%` need @divTrunc/@rem; float<->int compare needs float casts.

## Conventions (1:1)
- src/libc.zig: hand-written externs (`const C = @import("libc.zig")`).
- src/all.zig: all.h types (extern structs, [*c] ptrs), re-exports all module
  fns; `pub var` globals used as `all.T`, `all.curi`, `all.insb`,
  `all.insbEnd()` (= &insb[NIns]), `all.debug`, `all.optab`, `all.typ`, `all.con01`.
- tools/preamble.py <files>: regenerates import block between
  `// -- imports --` and `// -- end imports --`.
- tools/gen_ops.py: generates src/ops.zig from ops.h.
- Bool-ish C ints returning predicates -> Zig bool. Fn.ntmp is i32 (cast).
- Compile check: cd src && zig test -lc check_tmp.zig --test-no-exec
  (check_tmp.zig refAllDecls each translated module; add new ones).

## Status
**1:1 translation COMPLETE.** All C files translated: ops, libc, all, util,
parse, cfg, abi, mem, alias, load, ssa, copy, fold, gvn, gcm, ifopt, simpl,
live, spill, rega, emit, amd64/*, arm64/*, rv64/*, main.zig, build.zig.
- tools/test.sh all (bin=$PWD/zig-out/bin/qbe): all tests execute OK (x86_64).
- tools/cmp.sh TARGET: byte-identical asm vs C qbe (/data/qbe-c/qbe) on all
  76 tests for amd64_sysv, amd64_apple, amd64_win, arm64, arm64_apple, rv64.
x86_64 va_list: pass by pointer (libc.VaListArg).

External testing (done, all passing with zig qbe):
- cproc (/data/cproc): `make bootstrap` with zig qbe as `qbe` in PATH
  (/data/zbin/qbe symlink): stage2 == stage3; `make check-stage2` 196/196.
- harec (/data/harec): `make check` 39/39 with zig qbe.
- tools/corpus.sh over /data/corpus (cproc test .qbe, IL of cproc + qbe C
  sources, harec .ssa): 0 diffs vs C qbe across all 6 targets.
- tools/mkcorpus.sh regenerates all of this after a sandbox reset.

- hare stdlib (/data/hare): `.bin/hare` built through zig qbe;
  `make check`: 626 passed, 0 failed, 11 skipped. (harec symlinked to
  /data/zbin/harec; scdoc missing so build `make .bin/hare` not `make`.)
- Own tests: tests/abifuzz.py (ABI fuzzer: C<->QBE calls, structs, sub-word,
  varargs; executes + compares asm on 6 targets with QBEREF=/data/qbe-c/qbe),
  tests/irfuzz.py (random IR programs vs Python evaluator; exercises opt
  passes). Both 100% ok (abifuzz 100 iters, irfuzz 150 iters).
- BUGS.md: 2 upstream QBE amd64 bugs found (shift flags, shift imm range).

## Canonical rewrite (in progress)
Git tag `v1-literal` = verified 1:1 version. Stages (each must keep
tools/cmp.sh x6, tools/dbgcmp.sh x6, tools/corpus.sh, tests/*fuzz.py identical):
1. **DONE (commit "canonical stage 1")**: all output via `*std.Io.Writer`
   (`Writer.Error!void` propagated with try). util.zig helpers: `cs()` (C
   string -> slice), `dprint()` (debug to `all.dbg` = buffered stderr),
   `bufPrintZ`, `die(fmt,args)` (flush dbg, abort), `cfloat()` (exact C
   `%f` formatter, big-int based), `cint(x,w)` (C `% Nd`). parse.err flushes
   dbg + `all.outw` then exit(1) like C. main.zig uses std.process.Init,
   File.writerStreaming for stdout/-o file; writeFailed() on I/O errors.
   tools/dbgcmp.sh compares all -d dumps vs C (0 diffs on 6 targets).
   Note: std.fmt prints '+' for signed ints with a width -> use cint().
2. Input/CLI. DONE (2a): whole input read into memory (Dir.readFileAlloc /
   stdin allocRemaining, arena); lexer uses getc()/ungetc() over a slice;
   floats via scanflt() (scanf "_%f"-like prefix scan + std.fmt.parseFloat,
   sign handled manually so -nan keeps its sign). corpus.sh: when both
   binaries fail, compares stderr (C "file.c: dying:" prefix normalized,
   C assert vs zig panic treated equal). DONE (2b): own getopt-compatible
   (GNU permuting) arg parser in main.zig, matches C qbe on -h/-x/-t?/
   missing arg/unknown target/-o/stdin; inpath is a slice.
3. Memory/libc. DONE (3a/3b): **libc dropped entirely** (src/libc.zig
   removed, build.zig no link_libc; static binary). util.zig: `gpa` =
   std.heap.smp_allocator; emalloc/efree via 16-byte size header; PFn pool
   = std.heap.ArenaAllocator reset by freeall(); typed palloc(T, n) /
   ealloc(T, n); vgrow uses @memcpy; strf(pl, comptime fmt, args) uses
   std.fmt; streq() replaces strcmp; util.sort(T, ptr, n, order) =
   std.sort.block (stable = same tie order as glibc merge-sort qsort) with
   typed `fn (T, T) std.math.Order` comparators; mem* -> @memcpy/@memset/
   copyForwards/Backwards (guard n==0: null [*c] can't be sliced).
   tools/all.sh runs every check (FUZZ=1 adds fuzzers).
   TODO (3c): vectors (vnew/vgrow) -> typed growable arrays.
4. Pointers. DONE (4a): 116 `[*c]Fn` params -> `*Fn` (tools/ptrparams.py
   T1,T2 files: converts params w/o arithmetic/null/copy use; fn types
   `fn ([*c]Fn` -> `fn (*Fn`). DONE (4b): 21 pointer-walking loops ->
   `for (b.ins[0..b.nins]) |*i|` (tools/forloops.py).
   DONE (4c): 41 linked-list walks -> `var b_it: ?*Blk = f.start;
   while (b_it) |b| : (b_it = b.link)` (tools/listloops.py); ptrparams
   fixed (var-copy check was too strict) -> 162 *Fn params total.
   Audit note: for-over-slice evaluates bounds once (C re-reads nins/nuse
   each iteration); converted loop bodies were checked not to grow the
   iterated array. Index loops `while (n < f.ntmp)` are kept as while
   loops on purpose (bodies may call newtmp and grow the bound).
   Progress metric: `[*c]` 740 -> 694, `.*.` 3538 -> 3052.
   DONE (4d): ptrparams for Blk, Phi, Tmp, Con, Typ, Lnk, Dat, Use, Alias;
   Fn.tmp/con/mem and all.typ are `[*]T` (so `&f.tmp[i]` is `*Tmp`).
   Metric now `[*c]` 560, `.*.` 2594. Failed/skipped: BSet params (C
   `[1]BSet` array-of-one idiom must become plain BSet first), Num (null
   arg in amd64 isel sel()).
   DONE (4e): `[1]BSet` idiom -> plain `BSet` fields/locals, all BSet params
   `*BSet` (spill limit()/fst use `?*BSet`).
   DONE (4f): linked-list fields are optionals: Blk.s1/s2/link/idom/dom/dlink,
   Blk.phi, Phi.link, Fn.start, Asmbits/RAlloc/ExtraAlloc/Insl.link,
   cfg.zig jump struct s1/s2 -> `?*T`. Sed rewrote `.FIELD.*.` -> `.FIELD.?.`;
   locals inferred from these got explicit `[*c]T` via tools/fixderef.py
   (pipe zig errors into it); tools/listloops2.py converts variables reused
   for several list walks in one function. NOTE Use.u.phi is still [*c]Phi
   (don't apply `.phi.?` there).
   DONE (4g/4h): listloops.py/forloops.py made scope-aware (used-after check
   stops at end of enclosing block; `&x.*.f` no longer blocks) -> 11 more
   list walks, 8 more pointer walks converted.
   DONE (4i): tools/derefdots.py: rewrites every `p.*.f` -> `p.f`, then runs
   `zig build` repeatedly and restores `.*.` per base expression per function
   where zig says "[*c]T does not support field access" (C pointers need .*).
   Run from src/ (`--resume` skips the global rewrite). all.sh now runs
   `zig build` first and aborts on failure (check_tmp.zig misses main.zig!).
   Metric: `[*c]` 547, `.*.` 2088 (remaining `.*.` are on C pointers; they
   disappear as C pointers are converted -- rerun derefdots after each step).
   DONE (4j-4l): Blk.pred/fron, Fn.rpo, Phi.blk -> `[*]*Blk`; Phi.arg,
   BSet.t, Typ.fields, Blk.ins -> `[*]T`; vnewT returns `[*]T`; Use.u.ins/phi
   -> `*T`; Tmp.def, Alias.slot -> `?*T`. Tmp.use stays `[*c]Use` (null =
   not yet allocated, see ssa.zig). Locals doing Ins pointer arithmetic got
   explicit `[*c]Ins` (tools/fixinsptr.py, fed with `zig build` errors);
   pointer order comparisons between *T use @intFromPtr.
   DONE (4m-4o): tools/backloops.py (backward `i = b.ins + b.nins; while
   (i != b.ins) { i -= 1; ...}` -> index loop with `const i = &b.ins[i_n]`),
   forloops.py accepts `!=`; tools/optionalize.py T1,T2 (from src/): turns
   `[*c]T` params/typed locals into `?*T` (`x.*.` -> `x.?.`), builds, and
   restores every function that fails to compile. palloc/ealloc return
   `[*]T` (palloc(T,0) returns a dangling non-null ptr; C returned NULL but
   never dereferenced it), new pnew(T)/enew(T) return `*T` (zeroed).
   STAGE 5 (hand rewrites, file by file, after the mechanical tools):
   DONE 5a: cfg.zig fully idiomatic (sdom/dom take *Blk, inter/lca return
   ?*Blk, ifgraph(ifb, **Blk x3), simplcfg uses slices `ealloc(T,n)[0..n]`,
   std.mem.swap, for-over-pred). Per-file C-ism ranking command:
   `for f in src/*.zig src/*/*.zig; do printf '%s %s\n' "$(grep -o '\[\*c\]\|\.\*\.' $f | wc -l)" $f; done | sort -rn`
   DONE 5b-5d: ptrparams for Ins and all other struct types (beware: it
   converts array params that are only passed down -- Num `tn` and mem Slot
   `sl` were reverted by hand); idup/icpy take `[*]const Ins`; optionalize
   now skips indexed/arithmetic names and reverts callees named in
   "parameter type declared here" notes. Metric: `[*c]` 389, `.*.` 1434.
   CAUTION: don't `git stash` with uncommitted tool edits (lost them once).
   DONE 5e/5f: live.zig idiomatic; spill dopm index-based; util.igroup(b, n)
   returns index range `.{lo, hi}`, util.insidx(b, i) (asserting) maps an
   *Ins back to its index; gcm schedins/schedblk index-based.
   DONE 5g-5i: alias.zig fillalias, ssa.zig (phiins work stack, Name
   stack, renblk), copy.zig, gvn.zig (gvntbl `[]?*Ins`) idiomatic.
   DONE 5j-5l: rega.zig (dopm index-based like spill), load.zig (def takes
   an ins index ?uint), mem.zig (coalesce slices; Store.i/bl are `[*]Ins`
   so blit pairs use i[1]). NOTE: when building structs with `undefined`
   fields, remember the C code relied on zeroed memory (Debug fills 0xaa).
   DONE 5m/5n: all.curi is now `[*]Ins` (init &insb); use all.insbTail()
   (= insbEnd()-curi) / all.insbHead() (= curi-&insb); `&all.curi[0]` for a
   single *Ins. parse.zig globals typed (curf *Fn, curb ?*Blk, plink
   *?*Phi, blink *?*Blk, tmph [*]i32 guarded by tmphcap), ttoa ?[]const u8.
   Strings remain C strings (`[*c]u8` interned + cs()) -- deliberate for now.
   DONE 5o/5p: arm64/abi.zig, rv64/abi.zig: selcall(f, args: []Ins,
   call: *Ins, ilp: *?*Insl), selpar(f, pars: []Ins), argsclass takes
   slices, gp/fp register cursors are indices into gpreg/fpreg,
   Class.t/type is ?*Typ; T.retregs/argregs take `?*[2]i32`.
   tools/abislices.py has the loop/deref regexes used for these.
   DONE 5q/5r: amd64/sysv.zig and winabi.zig same treatment (all ABI files
   now free of `[*c]`/`.*.`).
   DONE 5s: amd64/isel.zig (fixarg(r: *Ref, k, i: ?*Ins, f), selsel/flagi
   index/slice based, tn is [*]Num), util.runmatch(code: []const uchar,
   tn, ref, vars: []Ref) index-based.
   NEXT FILES: arm64/isel, rv64/isel, emit files, util, simpl; emit files, ABI, isel.
   NEXT: rewrite remaining `[*c]Ins` pointer walks to index loops / slices
   (ABI selpar/selcall take [i0,i1) ranges -> should take `[]Ins`), manual
   idiomatic rewrites of functions optionalize couldn't handle (e.g.
   cfg.zig filldom/fillrpo/inter).
   TODO: rest of `[*c]` -> `*T`/`?*T`/slices (the `[*c]T` locals added by
   fixderef are candidates), enums for ops/classes/jumps.
   Notes: Zig forbids `<` on `[*]T` (only `[*c]`) and `&cptr[i]` is
   `*allowzero T` (won't coerce to *T) -> rewrite pointer loops to
   slices/indices before converting struct fields to `[*]T`.

## Next steps (current as of stage 6n, all checks green)
DONE 5t (redone after sandbox reset): arm64/isel.zig (fixarg(pr: *Ref),
selcmp(arg: *[2]Ref), seljmp backward index search with ?*Ins, list walks)
and rv64/isel.zig (memarg/immarg/fixarg take *Ref/?*Ins). All isel files
are now free of `[*c]`/`.*.`. Pattern for new con in fixarg: keep the index
`ci` and use CON(ci) instead of ptrdiff(c, f.con) (ptrdiff needs same types).
Restore notes: ziglang.org/builds still serves 0.18.0-dev.35+5e754304d
(master moved to dev.120); a full mkcorpus.sh run takes a few minutes and now
gives corpus "1608 runs, 0 differ, 104 both-failed" (bigger than before).
1. (done) arm64/isel.zig, rv64/isel.zig.
DONE 5u (start of emit files): amd64/emit.zig + arm64/emit.zig: E.fn is
`*Fn`, `*_emitfn(f: *Fn, ...)` (were ?*Fn), `e.@"fn".*.` -> `e.@"fn".`.
DONE 5v: arm64/emit.zig: fixarg(pr: *Ref), emitins(i: *Ins), rclob walks are
`for (arm64_rclob) |r| { if (r < 0) break; ... }`. Left in arm64/emit: only C
strings (fmt/rname/loadaddr/ctoa; deliberate).
DONE 5w: rv64/emit.zig: emitf/emitins take *Ins, fixmem(pr: *Ref), rclob
for-loops, `cs(@as([*c]const u8, if .. "a" else "b"))` print args -> plain
literals. Left: only C strings (fmt, ctoa table, loadaddr rn) -- deliberate.
DONE 5x: amd64/emit.zig: sysv/winabi rclob/rsave are slices
(`amd64_sysv_rclob[0..NCLR_SYSV]`), push loops `for (rclob) |r|`, pop loops
reverse index loops. Left: only C strings (fmt, ctoa/regtoa/clstoa tables).
All three target emit files are done.
DONE 5y: emit.zig: stash is a `?*Asmbits` list (stashbits walks `*?*Asmbits`),
Dat.lnk is `?*Lnk`. Left in emit.zig: C strings + `file` u32 vector.
DONE 5z: util.zig: Vec header via `[*]Vec` (v[0].f), phicls/dumpts take
`[*]Tmp`, sort takes `[*]T`.
DONE 6a: simpl.zig ins() takes a block index instead of walking [*c]Ins.
DONE 6b: spill.zig `tmp: [*]Tmp`, `limit_tarr: ?[*]i32` (`orelse return`:
null only when nt == 0 with k < 0 -- an earlier `.?` crashed hare corpus),
Target.rsave `[*]i32`.
DONE 6c: Tmp.use is `?[*]Use` (vector, null until filluse); users do `.use.?[..]`.
DONE 6d: emit.zig `file: ?[*]u32`.
Remaining `[*c]` are C strings (names, fmt tables, sec names, kwmap) kept
deliberately; cfg.zig `pb.*.id` is a legit `**Blk` deref.
DONE 6e/6f: target emit files: string tables/params are `[*:0]const u8`
(`?[*:0]const u8` where a table has holes, e.g. ctoa/rname, omap.fmt ends
with null -> callers use `.fmt.?`); fmt walkers use `s[0]` instead of `s.*`;
`&all.T.assym` / bufPrintZ buffers passed via `@ptrCast`.
Fuzzers rerun at 6d: abifuzz 60/60, irfuzz 100/100.
DONE 6g-6j: STRINGS FINISHED - zero `[*c]` left in src (except a comment in
amd64/targ.zig and check_tmp.zig). emit.zig tables/params `[*:0]const u8`;
all.zig name/sec/secf/str fields `?[*:0]u8` (nullable because structs are
zero-initialised; call sites use `.name.?` where C assumed non-null);
util: hash/intern take `[*:0]const u8`, str()/strf() return `[*:0]u8`,
newtmp prefix `?[*:0]const u8`, intern Bucket.str `[*][*:0]u8`;
parse kwmap `[Ntok]?[*:0]const u8`, tokval.str `[*:0]u8` buffer;
dbgfile fn type `fn ([*:0]const u8) void`. NUL-terminated stack buffers
(bufPrintZ) are passed with `@ptrCast(&buf)`.
Tool: /data/fixopt.py rebuilds and auto-inserts `.?` / `@ptrCast` for the
common optional/sentinel errors (falls over when the caret points at a
`.field`; fix those by hand).
DONE 6k: typed vector API in util.zig: Vec header {mag,pool,cap};
`vnewT(T,len,pool) [*]T`, `vgrow(&v,len)` / `vfree(v)` / `vcap(v)` are generic
over the element type (accept [*]T, [*:0]T, ?[*]T); no anyopaque, no esz,
typed @memcpy; call sites no longer @ptrCast for vfree.
DONE 6l: TESTS + 3 real bugs found by them:
  * `zig build test` -> src/unit_tests.zig (14 tests: vectors incl. growth/
    optional/sentinel/pools, hash, intern dedup/collisions/empty, strf, cs,
    streq, bitsets across word boundaries + algebra, sort, ptrdiff).
  * tools/edge.sh: 291 C-vs-Zig cases (CLI options/errors, stdin, -o, every
    -d flag, multiple files, lexer/parser errors, huge/float constants,
    long/quoted idents, data/sections/thread, empty/nested/union/opaque types,
    unreachable blocks, phis, register pressure, varargs, many args, blit,
    dbgloc) x 6 targets; compares stdout, exit code, stderr, -o file.
  * all.sh now also prints `unit: ok` and `edge: N passed, 0 failed`.
  * bugs fixed: empty aggregate type `type :e = { }` panicked (C does
    `1 << -1`; we now mask the shift like x86) in parse.zig parsefields and
    amd64/sysv.zig typclass; fatal errors (e.g. missing 2nd input file) lost
    already-emitted stdout - main.fail() now flushes stdout like C exit().
DONE 6m: jump kinds are `pub const J = enum(i16)` in all.zig (fields xxx,
retw..hlt); (the old `Jjmp`, `Jretw`, ... aliases were later removed; use `.jmp`);
Blk.jmp.type and cfg.zig Jmp.type are `J`. Arithmetic uses `J.add(n)`
(C: `Jjf + c`) and `.int()`; inRange/isret/isretbh accept enums or ints.
SANDBOX NOTE: long foreground commands (all.sh ~2 min) have killed the sandbox
twice and rolled /data back to an older snapshot. Always run all.sh in the
background (`(sh tools/all.sh > /tmp/all.log 2>&1; echo EXIT $? >> /tmp/all.log) &`)
and poll with `sleep 100; tail -12 /tmp/all.log`. Commit WIP before verifying.
DONE 6n: tools/s6n_casts.py removed 111 redundant @intCast/@truncate/@ptrCast
(a cast builtin never passes its result type to its operand, so a removal that
still compiles is an identity or lossless widening). ~470 casts remain; they
are real narrowing/sign/pointer conversions inherited from C int/uint mixing.
REMAINING (optional, not started): ops/classes (Kw..Kd, O*) as enums - ops are
used as table indices and in range arithmetic everywhere, so convert like 6m
(enum + aliases + .int()/add()); Ins.op/cls are u32 while Tmp.cls is i16 -
unifying these types would remove many of the remaining casts.
TAG v2-idiomatic (= backup 40, 51b20dc): end of Phase 3, byte-identical to
upstream C QBE e786f06.
STAGE 7 DONE, TAG v3-bugfix (all.sh pieces green: 0/76 x6 targets asm+debug, corpus 1608/0 differ, edge 291/0, bugs 89/0, unit 16/16, abifuzz 20/20, irfuzz 30/30 + 30/30 --upstream-bugs):
  The 3 BUGS.md issues are fixed in Zig (tools/s7_bugfix.py) AND in a patched
  C reference /data/qbe-cfix/qbe built from tools/qbe-cfix.patch
  (`cp -r /data/qbe-c /data/qbe-cfix; cd /data/qbe-cfix; patch -p1 <
  /data/qbe-zig/tools/qbe-cfix.patch; make`). All compare tools now default
  to ${QBEREF:-/data/qbe-cfix/qbe}, so "byte-identical" now means identical to
  the FIXED C. 1: ops.zig sar/shr/shl X(1,0,0) (no zero-flag reuse);
  2: amd64/isel.zig masks constant shift counts to 31/63; 3: util.zig igroup
  steps back onto the sel0. Tests: tools/bugs.sh (89 property checks; fails
  55/89 on unfixed C, 0 on fixed) + unit tests "igroup: ..." (16 unit tests).
  all.sh now also prints `bugs: N passed, 0 failed`.
STAGE 8 (optimizations, IN PROGRESS). QBE_COMPAT=1 in the environment turns
  every new optimization off (all.compat) so the byte-comparison tools still
  match the fixed C reference; all.sh exports it for those steps and runs
  test.sh + irfuzz WITHOUT it ("opt:" lines) to check program behaviour.
  8a DONE: simpl.zig algebra(): x*0, x&0 -> 0; x*1, x/1, x+0, x-0,
  x|0, x^0, x<<0 (count mod width), x&-1 -> copy; x*2^n -> shl; x*-1 -> neg (8b).
  Tests: tools/opt.sh (46 cases: each identity for w and l, compiled, linked
  with a C driver and RUN on 12 boundary inputs; asm-shape and compat checks).
  8c DONE: -O0/-O1/-O2 (gcc style; -O = -O1, -O3/-Os = -O2; default 2;
  QBE_COMPAT forces 0 and keeps upstream help text). O1: algebra() plus
  x-x, x^x -> 0 and x&x, x|x -> x. O2: signed div/rem by 2^n via
  sar/shr/add (sdivpow2), unsigned w div/rem by constant via one 64-bit
  multiply (udivmagic: only magic numbers < 2^32 with a proven error bound;
  others, e.g. 7, keep div). Test: tools/opt2.py (1348 division functions x
  3 levels, ~12k inputs each, run natively).
  TAG v4-opt pushed, BUT it crashes on arm64/arm64_apple at -O1/-O2: the
  abi passes emit arithmetic on machine registers (`%abi =l add R32, 0`)
  and algebra() turned it into a register copy -> rega assert. FIXED in
  878a8ad (virt()/allvirt(): rewrites only touch virtual temps). Use tag
  v4.1-opt. Guard: tools/optsweep.sh (every target x -O1/-O2 must succeed
  wherever C qbe does; test suite 910/0, corpus 3008/0). Lesson: amd64-only
  behaviour tests are not enough; there is no qemu in the sandbox.
STAGE 10 DONE (tests + BUGS #4): BUGS #4 was a FUZZER bug: jnz tests only
  the low 32 bits of a long (doc/il.txt); irfuzz now models that; seeds
  9000..9039 40/40. New tests (all in all.sh): tools/jnz.sh (21),
  tests/opttable.py (5898 op x const x class funcs x 3 levels vs gcc C oracle,
  worst-case dividends), tests/optfuzz.py (random op chains vs C oracle),
  tools/mutate.py (11 injected optimizer bugs, all killed; run it after any
  simpl.zig change). NOTE: sandbox rolled back again at start of stage 10;
  restored from GitHub.
STAGE 9 DONE (QoL), TAG v5-qol: src/lib.zig (Zig module "qbe": compile(),
  targets(); C ABI qbe_compile/qbe_free/qbe_target/qbe_version), include/qbe.h,
  libqbe.a via zig build; main.zig items made pub for it. CLI: --help,
  --version (1.4.0-zig), --list-targets, -O levels; QBE_COMPAT keeps upstream
  CLI. Tests: tools/lib.sh (1418/0: library output == CLI for 76 files x 6
  targets x 3 levels, == C ref at -O0, API edge cases, 200 repeated calls),
  tools/cli.sh (21/0). README.md documents everything.
  Known pre-existing failure: BUGS.md #4 (irfuzz seed 9029; C qbe fails too).
NEXT after v3-bugfix: new optimization passes (user request), each verified
  with unit/edge/bugs/fuzz; output may then differ from C by design, so
  compare program BEHAVIOUR (abifuzz/irfuzz run the code) not bytes.
PLAN (user approved, in order): (1) strings DONE; (2) vectors DONE; (2b) tests DONE; (3) jump enum DONE, cast reduction pass DONE, then vectors (vnew/vgrow) -> typed growable arrays;
(3) enums for ops/classes/jumps; (4) cut casts.
NOTE: the sandbox can stop mid-session (files in /data survived once, but the
last edits before the stop were partly lost) -> commit + back up often.
2. Emit files (arm64/emit ~70 `.*.`, rv64/emit ~57, amd64/emit ~35,
   emit.zig ~34): E.fn `*Fn`, `*_emitfn(f: *Fn, ...)`, fixarg(pr: *Ref),
   emitins(i: *Ins), rv64 emitf(i: *Ins), `e.@"fn".*.` -> `e.@"fn".`,
   rclob loops `for (arm64_rclob) |r| { if (r < 0) break; ... }`.
   Asm format strings stay C-style strings (deliberate).
3. util.zig (vectors, hash), simpl.zig, all.zig, leftovers in
   parse/spill/main/cfg/amd64/targ. Count: `grep -c '\[\*c\]' src/*.zig src/*/*.zig`.
4. Consider enums for ops/classes/jumps (or document as deliberate), nicer
   Vec API; optionally fix BUGS.md items (separate commits, intentional diffs).
Cautions: never `git stash` with uncommitted tool edits; C relied on zeroed
memory (Debug fills `undefined` with 0xaa); `[*]T` has no `<`/`>` (use
indices/slices); pointer subtraction on `[*]T` works; tmph needs
`tmphcap != 0` guard.

## CI (current)

- ci.yml: jobs call `sh tools/ci.sh <suite>` (core, native, cross <target>,
  corpus, cproc, hare, win). The C reference qbe is built by tools/ci-ref.sh
  from tools/qbe-ref.tar.gz (pristine e786f06) + tools/qbe-cfix.patch and
  cached under ~/qbe-cfix. Zig pinned via env ZIG_VERSION. Comparison against C
  is skipped on Darwin (libc qsort ordering differs). lib.sh treats rc >= 128
  as a crash unless stderr has qbe's intentional "dying:".
- nightly.yml: fuzz, zig-master (continue-on-error), memcheck (valgrind),
  programs (Lua via cproc+zbe; SQLite gated by SQLITE=1: cproc lacks
  long double), freebsd (vmactions).
- Release: push a `v*` tag with a matching CHANGELOG.md section.
- One-off scripts referenced below now live in tools/archive/.

## Prompt for the next agent
> You are continuing a QBE (C compiler backend) -> Zig master translation.
> Restore: `git clone https://github.com/0x6432/zbe /data/qbe-zig` and
> `cp /data/qbe-zig/tools/backup.sh /data/` (put a GitHub token in
> /data/.gh_token); install Zig master to /data/tools/zig and
> `export PATH=/data/tools/zig:$PATH` in every shell; clone
> git://c9x.me/qbe.git to /data/qbe-c and `make` (reference binary
> /data/qbe-c/qbe); build corpus with `sh tools/mkcorpus.sh` (Hare/cproc IR,
> see Status section). Read HANDOFF.md fully first.
> State: 1:1 translation done and verified (git tag `v1-literal`). Canonical
> rewrite in progress, stages 1-6n done + stage 7 bugfixes (see "Canonical rewrite").
> Verify after EVERY change: `sh tools/all.sh > /tmp/all.log 2>&1; head -1
> /tmp/all.log; tail -8 /tmp/all.log` (FUZZ=1 also runs abifuzz/irfuzz).
> Expected: "All is fine!", 0/76 differ on 6 targets + debug dumps, corpus
> 1608 runs 0 differ 104 both-failed, abifuzz 60/60, irfuzz 100/100.
> Commit each stage ("stage 5x: ..."). Every 10-15 min: update HANDOFF.md
> (required), run `sh /data/backup.sh` (pushes to GitHub).
> Continue with "Next steps" above. Output must stay byte-identical to C QBE.

## Backups (since backup 34): GitHub, not tarballs
`sh /data/backup.sh` refuses if HANDOFF.md is >20 min old, stamps the
Updated line, commits "wip: periodic backup N", and pushes HEAD to
github.com/0x6432/zbe (main). The token lives in /data/.gh_token (chmod 600,
never committed). A copy of backup.sh is kept in tools/backup.sh.
Restore: `git clone https://github.com/0x6432/zbe qbe-zig`.

## Decision: NUL-terminated strings (item 9)
- Names, symbol and section strings, and emitted text use `[*:0]const u8` (or `[*:0]u8` buffers), not slices. Reason: the emitter hands these straight to assembler/format output and the C reference is string-based, so byte-identical output is easiest to verify with NUL terminators.
- Optional fields (`?[*:0]u8`) stay nullable because IR structs are zero-initialised; call sites use `.?` where the C code assumed non-null.
- Stack buffers that must be passed as strings use `bufPrintZ` and `@ptrCast`.
- Revisit only if output is no longer compared byte-for-byte against the C reference.

## Decisions: idiomatic rewrite (items 5-8)
- Item 5 (enums): use kinds (`U`), alias results (`AliasRes`) and alias kinds
  (`AKind`) are enums, following the jump enum `J`; call sites use enum
  literals (`.phi`, `.top`, ...). Kept as integers on purpose:
  symbol kinds (`SGlo/SThr/SExt` are bit flags, combined as `SExtThr`),
  widths (`W*`, used as array indices, `bitAt()` positions and offsets that must
  match the Oload/Oext order), comparison kinds (`Ci*`/`Cf*`, offsets added to
  op numbers).
- Item 6: `Ins.cls`, `Tmp.cls` and `Phi.cls` share one type, now `Cls` (below).
- Item 7: done in 6k (typed `vnewT`/`vgrow`/`vfree`); nothing left.
- Item 8: `fillrpo`/`inter`/`filldom` were already idiomatic; only `filldom`
  now uses a `changed` flag.
- Local note: in some sandboxes the locally built C reference emits
  `shlq $0` for wide shifts and `tools/edge.sh` shows 20 mismatches; CI is
  authoritative (291/0).

## Decisions: ops and classes enums
- `Ins.op` is `ops.Opc` (`enum(u32)`, generated by `tools/gen_ops.py`); ops
  are written as enum literals (`.add`, `.storew`), there are no `O*` aliases.
  C-style op arithmetic is written `Opc.storew.offset(k)` (Ostorew + k) and
  `i.op.diff(.extsb)` (i.op - Oextsb);
  `i.op.int()` indexes `optab` and range checks compare `.int()`. Where ported
  code still keeps an op in an `i32` (isel/abi helpers, `opfold`, `iscmp`),
  `ops.num(x)` / `ops.of(x)` convert. `.xxx` (0) is the omap sentinel.
- `Ins.cls`, `Tmp.cls`, `Phi.cls` are `all.Cls` (`enum(i16)`: `x = -1`, `w`,
  `l`, `s`, `d`; written `.w`, `.l`, ..., no `Kx..Kd` aliases). `.int()`, `.idx()` (table index, never
  `x`) and `.offset(n)`; `all.knum`/`all.kof` convert at integer boundaries;
  `clsBase`/`clsWide` accept both. `clsmerge` takes `*Cls`.
- Emitter omap tables use a per-file `KPat` enum (`a = -2`, `i = -1`, `w`, `l`,
  `s`, `d`) because the `Ki`/`Ka` wildcards are not real classes.
- Kept as integers: the parser's extended modes (`Ksb..Kuh = 4..7`, `Kc`,
  `K0`, `Ke = -2`, `Km`) since they never reach `Ins.cls`; `optab` `argcls`
  entries (`[2][4]i16`, include `Ke`/`Km`/`Kx`); ABI helper class fields in
  amd64/winabi and arm64 HFA (`i32`/`i8`).
- AMD64 isel `opn` and SysV `argsclass` take `Opc` rather than `i32`;
  address-pattern switches use enum literals and argument/parameter opcode
  normalization uses `Opc.arg.offset(i.op.diff(op))`. No `ops.num` calls
  remain in the isel/ABI files. A unit regression exercises every pair of
  address-pattern states for add/mul and the default opcode path.
- Remaining numeric parameters such as amd64 `cmpswap` and rv64 `selcmp`
  are comparison-kind offsets, not opcodes; they stay numeric intentionally.
  ABI helper numeric fields and class boundaries described above stay as-is.

## Decisions: errors and state (Phase 5)
- Input errors are `all.Error` (`error{InvalidInput}`), returned by `fail()`
  (parse.zig; re-exported as `all.fail`) and propagated with `try` through the
  parser, the pass pipeline and the target `abi0`/`abi1`/`isel` hooks. `main`
  prints `qbe:<file>:<line>: <msg>` and exits 1 exactly like C qbe; `lib.compile`
  returns `error.InvalidInput` (`qbe_compile` -> 3). The exiting `err()` is gone.
- `die()` stays for internal invariant failures: tools/lib.sh treats rc>=128
  without `dying:` as a crash and tools/corpus.sh compares `dying:` lines with C.
- Ten input-driven `die` sites now return `all.failInput()` (InvalidInput):
  unsupported extern/thread on arm64/rv64/amd64_win, rv64 extern offsets,
  amd64/rv64 alloc overflow and invalid constants, winabi env with varargs,
  and initialized common data. Unlike parser `fail`, `failInput` preserves
  the exact `qbe: dying:` diagnostic, without aborting. CLI exits 1; the C
  library returns 3. The emitter vtable and helper chains propagate the
  error as `(Writer.Error || all.Error)`, and the driver distinguishes it
  from WriteFailed. Internal invariant and resource-exhaustion aborts stay.
- `tools/input-errors.py` compares the input diagnostics against C, verifies
  CLI exit 1 at every optimization level, and checks repeated bad->good
  compilations in one library process. Two unit tests cover invalid constants
  at the private helper boundary. The CI core/native suites run the script.
  `tools/cmp.sh` and `tools/corpus.sh` permit C abort versus zbe exit 1 only
  for the enumerated input diagnostics through `tools/input-error-compat.sh`;
  their normalized stderr must still match exactly.
- Per-pass mutable state lives in one documented `const State = struct {...}`
  per file with an instance `var st: State = .{}` (spill, rega, load, emit,
  ssa, gvn, parse, arm64/abi, the three emitters, util, lib). It is not reset
  per function, so cached buffers (spill `limit_tarr`) behave as before.
- Kept as module-level globals on purpose: the program-wide compile context in
  all.zig (`T`, `debug`, `typ`, `insb`/`curi`, `dbg`, `outw`, `compat`,
  `optlevel`, `con01` shared by gvn and copy), the per-target `Target` values
  and main.zig's I/O writers. Threading these through every pass would touch
  ~380 uses in 28 files for no behaviour change.
- Read-only tables are `const`: `optab`, amd64/arm64/rv64 rsave/rclob, arm64/rv64
  argument registers; `Target.rsave` is `[*]const i32`.
- Lesson: identifier renames by script must skip string literals and comments
  and handle `..name` ranges; c03cb09 rewrote `in` -> `st.in` inside 13 error
  messages (fixed in 3d3dfbc, caught only by tools/edge.sh). Run edge.sh and
  compare its FAIL list with the local baseline (20 sandbox-only mismatches).

### Input-error conversion verification (2026-10-13)
- Zig 0.18.0-dev.35+5e754304d: build OK; unit suite 19/19.
- tools/input-errors.py: 51/51 cases (all optimization levels), including
  repeated library error->success recovery; C diagnostic text unchanged.
- Compat assembly and debug dumps: 0/76 differ on each of all six targets.
- Corpus over bundled test/*.ssa: 456 runs, 0 differ, 1 both-failed.
- bugs: 110/0; lib: 1442/0.
- edge: 271/20; the complete FAIL list is identical to the pre-change baseline.
- Comparison exception helper: positive match and five negative checks passed
  (wrong statuses, invariant failure, extra stderr, extra trailing newline).


### CI follow-up: dash abort trailer (2026-10-13)
- CI at 5fc472a passed 7/9 jobs. Core and cproc comparisons failed because
  Ubuntu's /bin/sh (dash) appends `Aborted` or `Aborted (core dumped)` to the
  redirected C-reference stderr, unlike this sandbox's Bash /bin/sh.
- Reproduced locally with dash 0.5.12: amd64_win tls was 1/76 different.
- The input-error exception now requires exactly C rc=134 and zbe rc=1,
  an approved input diagnostic, and otherwise byte-identical normalized
  stderr. It removes only ONE final shell-generated C abort trailer.
  The corpus comparator accepts the helper's already-verified match directly.
- tools/input-error-compat-test.py covers all approved messages with both
  trailer variants and checks that wrong statuses, invariant diagnostics,
  extra output/newlines and unexpected/duplicate abort lines remain rejected.
  Core/native CI run it through their native /bin/sh; TEST_SHELL allows a
  dash or Bash override locally. No compiler diagnostic text was changed.
- Comparison scripts now use per-invocation temporary directories. Running
  bundled and cproc corpora concurrently exposed their previously shared
  /tmp/corp.* outputs; those raced and produced false differences. The asm,
  debug and corpus comparators all isolate and clean up their scratch files.


### CI checkpoint (2026-10-13)
- ac95e80: all nine CI jobs passed, including core and cproc; the dash
  comparison follow-up is confirmed green before the next opcode cleanup.

### Typed opcode helper verification (2026-10-13)
- Build OK; unit suite 20/20, including the exhaustive address-pattern test.
- Assembly and debug dumps: 0/76 differ on each of all six targets.
- Input-error cases 51/0; strict comparison regression cases 42/0.
- bugs 110/0; lib 1442/0; cproc corpus 1212 runs, 0 differ, 52 both-failed.
- edge 271/20; its full FAIL list matches the pre-change sandbox baseline.


### Bounded instruction helper slices (2026-10-13)
- Previous checkpoint 2c3e001 passed all nine CI jobs before this change.
- util.idup takes []const Ins; util.icpy takes []Ins and []const Ins and
  returns the unused destination tail. The copy retains forward/backward
  overlap handling, checks destination capacity, and handles empty slices.
- util.sort takes []T, preserving stable ordering. All affected call sites
  in the parser, passes, selectors and ABI lowering supply bounded slices.
- all.insbHeadSlice()/insbTailSlice() expose active shared-buffer ranges;
  the intentional global cursor and fixed buffer design are unchanged.
- idup sources remain independent of their destination block vectors;
  growth may relocate b.ins, so aliasing that vector is not supported.
- Added regressions for chained/overlapping/empty/self instruction copies,
  block copy growth/shrinkage and independence, equal-key stable ordering,
  and active head/tail buffer ranges. All 11 optimizer mutation patterns
  were checked unchanged; compiler diagnostic strings were not edited.

### Bounded slice helper verification (2026-10-13)
- Build OK; unit suite 27/27, including seven new slice regressions.
- Assembly and debug dumps: 0/76 differ on each of all six targets.
- Input-error cases 51/0; strict comparison cases 42/0; bugs 110/0.
- lib 1442/0; cproc corpus 1212 runs, 0 differ, 52 both-failed.
- Native behavior suite: All is fine; ABI fuzz: 20/20 iterations OK.
- edge 271/20; complete FAIL list is identical to the sandbox baseline.


### Temporary-array slices (2026-10-13)
- 3c6c6df passed all nine CI jobs before this follow-up.
- phicls takes []Tmp; dumpts takes []const Tmp; liveness bset takes
  []const Tmp. filluse/filllive capture f.tmps() while those arrays are stable.
- Spill and register-allocation State.tmp are []Tmp. The spiller's separate
  ntmp field is removed; bitsets and traversal use the slice length.
- Audited that filluse/filllive/spill/rega do not grow the temporary vector
  while these slices are in use. SSA-renaming functions that call newtmp are
  separate and continue to fetch the current vector when required.
- Register counts, ABI class fields, matcher-number arrays and the shared
  compile context are intentionally untouched. State buffers remain cached.
- Added tests for phi-chain compression in a subslice with neighbor guards,
  const/empty temporary debug dumps, and liveness deduplication/class counts.

### Temporary-array slice verification (2026-10-13)
- Build OK; unit suite 31/31, including four new temporary-array tests.
- Assembly and debug dumps: 0/76 differ on each of all six targets.
- Input-error cases 51/0; strict comparison cases 42/0; bugs 110/0.
- lib 1442/0; cproc corpus 1212 runs, 0 differ, 52 both-failed.
- Native behavior suite: All is fine; ABI fuzz: 20/20 iterations OK.
- edge 271/20; complete FAIL list is unchanged from the sandbox baseline.
- Compiler diagnostics and all 11 optimizer mutation patterns remain intact.


### Address-matcher slices (2026-10-13)
- cdb5751 passed all nine CI jobs before this follow-up.
- util.runmatch takes []const Num. AMD64 selector helpers pass []Num or
  ?[]Num, preserving null for recursive selection paths without matching.
- The number table uses eallocSlice and retains its allocation-time length;
  instruction selection can grow f.tmp, but original matchable temps keep
  their initial indices. Each block clears only that independent table.
- refn/anumber take []const Con. Address helpers fetch f.cons() at each
  call rather than retaining a stale view across constant-vector growth.
- No matcher bytecode, address-pattern tables, diagnostic strings, or
  compile-wide globals were changed. Numeric comparison offsets stay intact.
- Added tests for ordered/raw child traversal, dispatch/default/jump/stop,
  constant/cache classification, and instruction numbering in a guarded
  number-table subslice. Register-allocator memory state is untouched.

### Address-matcher slice verification (2026-10-14)
- Final checkpoint builds successfully; unit suite 37/37, including six new
  matcher/classification tests. Fixtures use nonzero temporary references:
  tmpRef(0) is the sentinel R and is not a valid matcher root.
- Assembly and debug dumps: 0/76 differ on each of all six targets.
- Input-error cases 51/0; strict comparison cases 42/0; bugs 110/0.
- lib 1442/0; cproc corpus 1212 runs, 0 differ, 52 both-failed.
- Native behavior suite: All is fine; ABI fuzz: 20/20 iterations OK.
- edge 271/20; the complete FAIL list remains identical to the sandbox baseline.
- Compiler diagnostic strings and all 11 optimizer mutation patterns are intact.


### Bounded pass storage (2026-10-15)
- Based on 049c656. Its CI status could not be rechecked: GitHub DNS failed
  from the sandbox, and the public run page was unavailable through web tools.
- Register-allocation State.mem uses f.mems(); beg/end register-map arrays
  retain the block count at allocation. New edge-copy blocks are appended
  later and are not indexed through those original-block maps.
- Spill-limit scratch is a reusable []i32; its length replaces limit_maxt.
  Each call uses only the active prefix. The buffer still persists across
  functions and grows only when needed; no production reset was introduced.
- Empty unowned storage is never passed to efree. Empty/negative limits,
  stable cost ties, membership preferences, reuse, shrinking, and growth
  are covered by three new direct spiller tests.
- Compiler diagnostic strings, matcher tables, register/class numbering,
  intentional compile-wide globals, and extern-layout structs are unchanged.
- Network access must be restored before fetching/pushing or confirming CI;
  main and wip/idiomatic remain at the last pushed checkpoint for now.

### Pass-storage verification and offline checkpoint (2026-10-15)
- Build OK; unit suite 40/40, including three new spill-cache regressions.
- Assembly and debug dumps: 0/76 differ on each of all six targets.
- Input-error cases 51/0; strict comparison cases 42/0; bugs 110/0.
- lib 1442/0; cproc corpus 1212 runs, 0 differ, 52 both-failed.
- Native behavior suite: All is fine; ABI fuzz: 20/20 iterations OK.
- edge 271/20; complete FAIL list matches the sandbox baseline.
- Additional IR fuzz: 149/150 iterations OK, seeds 1000..1149, 20 functions
  per iteration. Seed 1130 reports f14 mismatch against the Python oracle.
- Reproduced seed 1130 with this build, the previous 049c656 binary, and
  /data/qbe-cfix/qbe: all three return the same native f14 mismatch. Their
  assembly is byte-identical on all six targets. This is not introduced by
  the pass-storage cleanup; the underlying compiler/oracle cause is unresolved.
- Reproducer source, comparison log, patch and bundle are preserved in the
  downloadable offline checkpoint. No compiler diagnostic strings changed;
  all 11 optimizer mutation patterns remain intact.
- New work is committed only on wip/pass-storage. Local main/wip/idiomatic
  remain at 049c656; no release tag was created. Restore network access,
  fetch and inspect remote state, then fast-forward/push and check CI.


### Constant jnz investigation/fix (2026-10-15)
- Continues from the unpushed pass-storage checkpoint fdc5d1f. GitHub DNS
  is still unavailable; local main/wip/idiomatic remain at 049c656.
- Resolved the seed 1130 mystery: the Python oracle is correct. Upstream
  gvn.c and port gvn.zig dedupjmp test all 64 constant bits, but jnz has
  word semantics. The minimized fixture also fails at prior -O1/-O2.
- Mask folded conditions at -O1/-O2, retaining original -O0 behavior for
  C-compatible byte output. No oracle weakening or C-reference changes.
- Added a direct branch-folding unit test and extended tools/jnz.sh with
  direct, product, negative-high-only, and nonzero-low-word constant cases.
- The original compat-mode IR-fuzz seed remains a known upstream failure;
  optimized fuzzing is the correctness check for this fix. See BUGS.md #8.

### Constant jnz verification (2026-10-15)
- Build OK; unit suite 41/41, including direct constant branch-folding checks
  at -O0/-O1/-O2 for zero, signed/high-only, and nonzero low-word values.
- Extended jnz harness: 21 passed, 0 failed (native semantics, six-target
  reference comparison, and optimized compilation across all targets).
- IR fuzz at both -O1 and -O2: 150/150 iterations OK, seeds 1000..1149,
  20 functions per iteration. Original seed 1130 now passes in both modes.
- -O0 still reproduces upstream's seed 1130 failure by design. Oracle and
  C-reference source remain untouched; compatibility is not presented as
  a semantic pass for that seed.
- Six-target assembly/debug comparisons: 0/76 differ on each target.
- Input errors 51/0; comparator cases 42/0; bugs 110/0; library 1442/0.
- cproc corpus: 1212 runs, 0 differ, 52 both-failed; behavior OK;
  ABI fuzz 20/20. Edge 271/20, with the full failure list unchanged.
- Diagnostic strings and all 11 optimizer mutation patterns remain intact.
- This branch includes the previous unpushed pass-storage cleanup. Network
  remains unavailable, so it is an offline checkpoint only; main and
  wip/idiomatic still point to 049c656. No release tag was created.

### Imported checkpoint review and online verification (2026-10-15)
- Imported zbe-jnz-fix.bundle after successful prerequisite verification.
  The original four-commit chain through c9da5b6 is preserved; no cumulative
  patch was applied and no completed code change was recreated.
- Fresh GitHub clone and subsequent fetch both found main and wip/idiomatic
  at 049c6562318c0c6fc50937fb1951fad6cfc76d01, permitting fast-forward.
- Confirmed prior run https://github.com/0x6432/zbe/actions/runs/38454908393
  completed successfully: all nine verification jobs passed (release skipped).
- Reviewed bounded register maps/memory views, scratch ownership and reuse,
  active-prefix sorting, and the optimized low-word branch test. No change
  to the oracle, C-reference patch, diagnostics, or CI workflow was needed.
- Rebuilt with Zig 0.18.0-dev.35+5e754304d and the vendored patched C reference.
  Direct unit tests: 41/41. Full tools/ci.sh core: zero failed checks.
  Six-target compatibility assembly/debug: 0/76 differ per target; jnz 21/0;
  bugs 110/0; library 1442/0; input errors 51/0; strict comparator 42/0;
  CLI 21/0; optsweep 910/0; opt 46/0; opt2 and opttable passed;
  native optimized/compat behavior passed; package consumer passed.
  Core optfuzz 40/40, optimized IR fuzz 60/60 (9000..9059), compatibility
  IR fuzz 60/60 (5000..5059), and ABI fuzz 60/60 (1000..1059) passed.
  Mutation suite killed all 11 mutants; source was restored afterward.
- Targeted optimized IR fuzz: 150/150 at EACH of -O1 and -O2, 20 functions
  per iteration, seeds 1000..1149. This includes the original seed 1130.
- QBE_COMPAT=1 seed 1130 still fails with f14 mismatch, as deliberately
  retained upstream behavior. Its assembly matches the C reference on all
  six targets. This is not reported as a semantic compatibility-mode fix.
- Fresh-sandbox edge suite: 291/291 passed for both c9da5b6 and the original
  049c656 baseline. The previous sandbox's 20 failures did not reproduce.
- The prior generated cproc corpus was not present in this sandbox; its
  archived verification is preserved, not represented as freshly rerun.
- Local main and wip/idiomatic are fast-forwarded to this reviewed handoff
  checkpoint. Publishing remains blocked pending fresh GitHub device
  authorization; no configured authenticated GitHub connection was available.
  Remote branches remain at 049c656 and no new CI run has been triggered.
  Re-fetch before publishing, push both branches without force, then check CI
  and append the actual published checkpoint/run result here.
- No release tag was created. Exposed credentials were not reused or copied
  into repository content, remotes, archives, or verification logs.
- Review logs are /data/recheck-*.log, /data/recheck-summary.log,
  /data/recheck-unit-direct.log and /data/baseline-edge.log.

### Online publication and CI status (2026-10-15)
- Published the preserved offline chain plus reviewed handoff checkpoint
  2df99381c68bdc2885e023ca3680783e37e86fd9 to BOTH main and wip/idiomatic
  using an atomic, non-force fast-forward push. Remote tips were checked
  immediately before and after publication; no user changes were discarded.
- Publication CI: https://github.com/0x6432/zbe/actions/runs/38737049989
- Status checked at 2026-10-15T12:58:18+00:00: in_progress;
  successful jobs: native (ubuntu-24.04-arm), hare (ubuntu-24.04), native (macos-15), cross (amd64_win), cross (arm64), hare (ubuntu-24.04-arm), cproc, cross (rv64).
  Still running: core. Overall green is NOT yet confirmed.
- This follow-up changes HANDOFF.md only; compiler sources remain exactly
  those verified at c9da5b6. Pushing this documentation checkpoint triggers
  its own CI run; inspect the newest run separately before claiming green.
- Repository remote remains https://github.com/0x6432/zbe.git. The user
  explicitly authorized token authentication; no credential was committed
  to the repository or stored in its remote URL. No release tag was created.

### Confirmed online CI completion (2026-10-15)
- Publication checkpoint 2df99381c68bdc2885e023ca3680783e37e86fd9:
  https://github.com/0x6432/zbe/actions/runs/38737049989 — completed SUCCESS.
- Published handoff checkpoint d07d4a4850adac1a16c63ed00ebce1f72c9cc9e3:
  https://github.com/0x6432/zbe/actions/runs/38738796441 — completed SUCCESS.
- BOTH runs passed all nine verification jobs: core; native Linux arm64 and
  macOS; cross arm64, rv64 and amd64_win; cproc; Hare Linux x86_64 and arm64.
  The release job was skipped normally because no release tag was pushed.
- This final HANDOFF-only record uses [skip ci] to avoid launching a third
  identical suite. Compiler/test/workflow content is unchanged from the
  confirmed-green checkpoints. Both branches receive the same final record.
- The original offline commits remain intact. No force push, release tag,
  oracle weakening, reference-patch change, or credential commit occurred.

### Idiomatic rewrite resumed: parser/emitter caches (2026-10-15)
- Continues from confirmed-green 8e4311b. The user prioritized completing
  idiomatic Zig work before considering additional optimizations.
- Parser temporary-name hash storage is []i32; its length carries capacity.
  The table still starts at 16384 slots, grows at half full, preserves probe
  and rehash order, and is cleared/reused between functions rather than freed.
- Emitter debug-file storage is an active []u32 backed by the existing vector
  allocation. Its length replaces nfile; file numbering, duplicate selection,
  vector growth, and process-wide lifetime are unchanged.
- Four new direct unit tests cover initial allocation/deduplication/reuse,
  wraparound collisions/rehashing, debug-file numbering/location output, and
  active-name preservation across vector growth. Unit suite: 45/45 passed.
- tools/parser-caches.py generates large/small/large functions crossing the
  real 8192-name growth threshold plus nine debug files and duplicate names.
  Its six-target assembly and parser-dump comparisons with C passed 12/12.
  Core/native CI and tools/all.sh now include this regression.
- Full local core verification and targeted -O1/-O2 fuzzing are running in
  the background; see /data/idiomatic-verify-summary.log and related logs.
  Do not claim final verification or new CI green until those complete.
- Further private pointer/count audit targets: util intern buckets, load
  insertion-log rollback/sentinel traversal, and mem slot store histories.
  Keep ABI/extern layouts, numeric ABI fields, sentinel strings, compile-wide
  globals, shared instruction buffers, and cached pass capacities deliberate.

### Intern bucket slices (2026-10-15)
- String-intern buckets now store an active slice of sentinel string pointers
  instead of an unbounded vector pointer and duplicate count. The numeric ID
  encoding, hash/probe order, power-of-two growth policy, overflow diagnostic,
  owned string copies, and process-wide reuse are unchanged.
- Added a forced single-bucket collision test spanning four capacity growths,
  preserving exact IDs, contents, pointer ownership, and duplicate reuse.
  Direct unit suite: 46/46; parser/debug-file growth comparisons: 12/12.
- The first full core run picked up the earlier unit-test helper typo while
  it was being corrected; all other checks passed, including mutation 11/0.
  The corrected direct unit run is green. A complete fresh aggregate run is
  still required before publishing; no failed run is being called green.

### Private load/store buffer slices (2026-10-15)
- Load insertion entries use an active []Insert. Rollback truncates the
  CURRENT allocation after possible growth; it never restores a stale slice.
  Consumption uses checked indices and no longer requires an out-of-band
  sentinel. Per-function allocation/free and insertion ordering are preserved.
- Memory-coalescing store histories use []Store; retained instruction tails
  and blit references use []Ins. Use-list instruction removal recovers its
  owning block/index before taking a bounded tail. No IR/extern layout changed.
- Five direct tests cover log growth/rollback (including empty rollback),
  stable phi/instruction ordering, empty-log consumption, store-history growth,
  and blit-pair/singleton removal with guarded neighboring instructions.
- Aggregate direct unit suite: 51/51 passed. Full aggregate compatibility,
  behavior, mutation and optimized-fuzz verification is required next.

### Rewrite scope and current audit (2026-10-15)
- docs/IDIOMATIC-ZIG.md is the current ordered work tracker. The rewrite is
  still in progress; this storage milestone is not a claim of full completion.
- The next interface batch is typed SSA/GVN use-registration payloads, followed
  by bounded bitset views, local instruction-vector builders, parser states,
  and a final module-by-module audit. Preserve the deliberate designs listed
  in the tracker rather than changing extern layouts or compile-wide globals.
- Regenerated cproc at pinned d1c53dd: bootstrap and make check succeeded.
  Its 202-file real-world corpus compared over all six targets: 1212 runs,
  zero differ, 52 both-failed. The corpus used an immutable compiler snapshot
  so the concurrent optimizer mutation test could not contaminate the result.

### Storage milestone verification (2026-10-15)
- Fresh aggregate core run passed with zero failed checks, including unit
  51/51, edge 291/0, jnz 21/0, parser-cache stress 12/0, library 1442/0,
  bugs 110/0, input errors 51/0, strict comparator 42/0, all six assembly
  and debug comparisons 0/76 differ, and mutation 11 killed/0 survived.
- Optimized IR fuzz: 150/150 at EACH -O1 and -O2, 20 functions/iteration,
  seeds 1000..1149. Cproc bootstrap/check and 1212-run corpus also passed.

### Typed use payloads, bitset views, and parser states (2026-10-15)
- SSA adduse accepts a tagged Phi/Ins/jump payload; all SSA/GVN callers pass
  actual pointer types without anyopaque/align casts. Stored Use layout and
  numeric kinds remain unchanged; disabled tracking still leaves counts alone.
- BSet adds mutable/read-only word views without changing its fields/layout.
  Empty views do not inspect an unowned pointer. Bitset helpers and direct
  register-mask consumers use bounded views; readers accept const BSet values.
- Parser control flow uses an enum; opcode-derived token numbering is untouched.
- Five new direct tests cover typed payloads/counts/growth, disabled tracking,
  guarded/empty/const bitset views, overlapping forward copies, and parser
  state rejection/closing transitions with the exact existing diagnostic.
  Current direct unit result: 56/56 passed. Full aggregate rerun is next.
- Remaining rewrite work is tracked in docs/IDIOMATIC-ZIG.md; do not treat this
  milestone as a blanket claim that all local builder interfaces are finished.

### Bounded instruction builders (2026-10-15)
- Replaced addins/addbins pointer/count interfaces with active-slice append
  helpers and block wrappers that synchronize the unchanged stored IR fields.
- GCM scheduling, conditional conversion and load reconstruction use bounded
  active slices; reset lengths retain vector allocations and capacity.
- Self-appending sources reacquire elements after growth. Appending by value
  avoids retaining a pointer into a destination that may move. Load rebuilding
  deliberately retains nops for unchanged compatibility debug dumps.
- Three direct tests cover order/nop filtering/reuse, heap-alias growth, block
  extent synchronization and empty unowned storage. Direct unit result: 59/59.
- Full aggregate verification of the typed-interface and builder batches is
  still pending; earlier storage-only results are not sufficient for publishing.

### Typed CFG roots and bounded use-list readers (2026-10-15)
- CFG union-find returns typed block roots and compresses parent links, avoiding
  casts from optional successor fields to nonoptional pointer-to-pointer types.
- Temporary use readers use a shared bounded view, including an empty-storage
  guard that does not inspect an undefined/null pointer at zero active uses.
  Count-only tracking and all stored fields remain unchanged.
- Added root/path-compression and guarded-use-view regressions. Debug direct
  units: 61/61. ReleaseSafe and complete aggregate verification are pending.
- The module audit retains intentional ABI layouts, numeric target fields,
  allocator/vector boundaries and sentinel strings. Direct indexed core-field
  consumers remain a follow-up; the rewrite is not declared complete.

### Combined idiomatic cleanup verification and publication gate (2026-10-15)
- Verified source checkpoint 957a4d4 includes parser/emitter caches, intern
  buckets, load/store histories, typed use registration, bounded bitsets,
  enum parser states, alias-safe instruction builders, typed CFG roots and
  bounded temporary use readers. No new optimizer feature was added.
- Pinned Zig build passed. Direct tests: 61/61 in Debug AND ReleaseSafe.
  Parser/debug-file growth stress: 12/12, including real 8300-temp functions.
- Fresh full core suite: zero failed checks. All six targets: 0/76 assembly
  differences and 0/76 debug differences each. Native optimized/compat behavior
  passed. Edge 291/0, bugs 110/0, library 1442/0, input errors 51/0, strict
  comparator 42/0, CLI 21/0, jnz 21/0, opt 46/0, optsweep 910/0.
- Division matrix: 1348 functions x3 levels; opttable: 5898 functions x3 levels.
  Core optfuzz 40/40; optimized IR fuzz 60/60 seeds 9000..9059;
  compatibility IR fuzz 60/60 seeds 5000..5059; ABI fuzz 60/60 seeds 1000..1059.
  All 11 optimizer mutants killed; zero survived. Package consumer passed.
- Additional optimized IR fuzz: 150/150 at EACH -O1 and -O2, seeds
  1000..1149, 20 functions per seed (includes original constant-jnz seed 1130).
- Final immutable compiler snapshot: cproc d1c53dd bootstrap and make check
  passed. The 202-file real-world corpus: 1212 runs, zero differ, 52
  both-failed (matched reference errors, not successful compilations).
- Stored IR/ABI fields, compiler input diagnostic literals, C reference patch,
  Python oracle and optimizer rewrites remain unchanged. Mutation source was
  restored and the generated ci-out directory moved outside the repository.
- Remote main and wip/idiomatic were fetched and both still pointed at
  8e4311b. Their previous CI runs 38737049989 and 38738796441 are confirmed
  successful. Fast-forward publication and NEW GitHub CI confirmation follow;
  local green is not a claim that the newly triggered GitHub run is green.
- The rewrite remains in progress: docs/IDIOMATIC-ZIG.md tracks the remaining
  direct indexed core-field consumer audit and intentional representations.
  No release tag was created or authorized.

### Published cleanup CI confirmed (2026-10-15)
- Both main and wip/idiomatic were fast-forwarded and atomically pushed to
  dfa83458ec5268768e67aa4286093a4842675ef2.
- GitHub run https://github.com/0x6432/zbe/actions/runs/38751793899 completed
  SUCCESS. All nine verification jobs passed: core, cproc, hare on x86_64 and
  arm64 Linux, native arm64 Linux and macOS, and arm64/rv64/Windows cross jobs.
  Release was skipped normally; no tag or release was created.
- This final handoff-only commit uses [skip ci]; the source and tests verified
  by that green run are unchanged. Both branches receive the same handoff.
- Continue the remaining direct-indexed core-field consumer audit recorded in
  docs/IDIOMATIC-ZIG.md before claiming the entire idiomatic rewrite complete.
  Preserve all deliberate representation and compatibility boundaries.

### Active function-table consumers (2026-10-15)
- Temporary, constant and memory consumers across generic passes and all target
  ABI/isel/emitter modules index bounded Fn views, reacquired at each access.
  Register allocator/spiller cached slices remain bounded and intentionally cached.
- Fn table views return empty slices without inspecting unowned pointers when
  their active count is zero. Stored fields and vector allocation APIs are unchanged.
- Constant insertion takes a Con value, avoiding a borrowed input across growth.
  AMD64 external/TLS lowering snapshots its constant before getcon/newcon can
  relocate the constant vector; no erased pointer/out-parameter is needed.
- Three regressions cover guarded empty/active extents, repeated constant growth
  and deduplication, and external/TLS snapshots from constant and memory tables.
  Fixtures now explicitly publish their constant counts. Direct tests: 64/64.
- A first test build caught an unqualified vnewT helper in the new fixture; the
  qualification was corrected and the complete direct rerun passed. All 11
  optimizer mutation anchors remain intact. Full aggregate verification is pending.

### Block/phi views and capacity-aware instruction prefixes (2026-10-15)
- Active instruction, predecessor, frontier, phi and materialized RPO indexing
  now uses bounded accessors across passes and targets. Zero-count views do not
  inspect unowned storage. RPO views remain invalid during CFG growth until rebuilt.
- A shared prefix replacement helper distinguishes vector capacity from active
  length, moves overlapping tails safely, and publishes pointer/count together.
  AMD64 SysV, arm64 and rv64 parameter lowering and rega copy prefixes use it.
  Prefixes retain nops and vector capacity; stored IR fields/layout are unchanged.
- Append helpers explicitly retain owned empty vector pointers at the allocator
  boundary. A direct test caught accidental use of an unowned empty view there;
  the boundary was restored, and the complete direct rerun passed 67/67.
- New regressions cover expanding/shrinking/equal/prepend/full replacement,
  retained capacity after clearing, nop preservation and all guarded core views.
- Remaining representation audit: aggregate type-table/union-field storage and
  the final intentional allocator, sentinel, ABI and shared-buffer exceptions.
  Full aggregate verification remains required before publication.

### Aggregate types and parser-owned cleanup (2026-10-15)
- The compile-wide type table is an active slice, removing its separate parser
  count without changing global compilation context or numeric type references.
  Extern Typ fields retain their representation and expose bounded field-set views.
- Type/union construction publishes owned storage before fallible parsing.
  Deferred cleanup releases partial type names/fields and lexer storage on both
  success and error; cached temporary-hash capacity is retained and cleared.
  Failed parses clear block-name references and reset the function pool.
- Lexer cache initialization now lives beside its cached table in parser State.
  New isolated-state tests caught the old split flag/table fixture inconsistency;
  moving the flag preserves production initialization and restores test isolation.
- Added type-table growth, nested types, nine union alternatives, dark types,
  guarded empty fields and malformed-then-valid parse tests. Direct units: 70/70.
- Library API regression alternates 24 malformed parses with 24 valid compiles
  in one process, including a function that fails after inserting temp/block names.
  Full library comparisons including recovery: 1442/0. An initial callback-name
  shadowing error in the new tests was corrected before the successful rerun.
- All planned active IR/type indexing categories are now bounded. Remaining raw
  operations are deliberate allocator/vector publication boundaries, core layout
  fields, sentinel strings/register lists and the shared instruction buffer.
  The final Debug/ReleaseSafe, full core/corpus/fuzz and online CI gate is pending.
