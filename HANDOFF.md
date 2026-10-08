# HANDOFF – QBE → Zig translation

Updated: 20261008-220121 UTC (backup 35)

## Goal
Translate QBE (C, cloned at /data/qbe-c, HEAD e786f06) to latest Zig master.
Phase 1: 1:1 translation (src/*.zig, C pointers, libc). Phase 2: test with QBE
tests, Hare, cproc, own tests. Phase 3: canonical/idiomatic Zig rewrite.
Backups every 10–15 min: ALWAYS update HANDOFF.md first (backup.sh refuses
if it is unchanged since the last backup), then run /data/backup.sh and
download /data/backups/qbe-zig-backup-N.tar.gz (N = backup number, counted
from "wip: periodic backup" commits). The tarball holds qbe-zig/ (with
HANDOFF.md), backup.sh and a top-level copy of HANDOFF.md.

## Restore after sandbox reset
1. Extract tarball into /data (gives /data/qbe-zig and /data/backup.sh).
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

## Next steps (current as of stage 6d, all checks green)
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
NEXT (optional polish): enums for ops/classes/jumps; slices for strings.
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

## Prompt for the next agent
> You are continuing a QBE (C compiler backend) -> Zig master translation.
> Restore: extract qbe-zig-backup.tar.gz into /data (gives /data/qbe-zig git
> repo + /data/backup.sh); install Zig master to /data/tools/zig and
> `export PATH=/data/tools/zig:$PATH` in every shell; clone
> git://c9x.me/qbe.git to /data/qbe-c and `make` (reference binary
> /data/qbe-c/qbe); build corpus with `sh tools/mkcorpus.sh` (Hare/cproc IR,
> see Status section). Read HANDOFF.md fully first.
> State: 1:1 translation done and verified (git tag `v1-literal`). Canonical
> rewrite in progress, stages 1-6d done (see "Canonical rewrite").
> Verify after EVERY change: `sh tools/all.sh > /tmp/all.log 2>&1; head -1
> /tmp/all.log; tail -8 /tmp/all.log` (FUZZ=1 also runs abifuzz/irfuzz).
> Expected: "All is fine!", 0/76 differ on 6 targets + debug dumps, corpus
> 1608 runs 0 differ 104 both-failed, abifuzz 60/60, irfuzz 100/100.
> Commit each stage ("stage 5x: ..."). Every 10-15 min: update HANDOFF.md
> (required), run `sh /data/backup.sh`, download qbe-zig-backup-N.tar.gz.
> Continue with "Next steps" above. Output must stay byte-identical to C QBE.

## Backups (since backup 34): GitHub, not tarballs
`sh /data/backup.sh` refuses if HANDOFF.md is >20 min old, stamps the
Updated line, commits "wip: periodic backup N", and pushes HEAD to
github.com/0x6432/zbe (main). The token lives in /data/.gh_token (chmod 600,
never committed). A copy of backup.sh is kept in tools/backup.sh.
Restore: `git clone https://github.com/0x6432/zbe qbe-zig`.
