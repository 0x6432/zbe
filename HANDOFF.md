# HANDOFF – QBE → Zig translation

Updated: 20261007-203302 UTC

## Goal
Translate QBE (C, cloned at /data/qbe-c, HEAD e786f06) to latest Zig master.
Phase 1: 1:1 translation (src/*.zig, C pointers, libc). Phase 2: test with QBE
tests, Hare, cproc, own tests. Phase 3: canonical/idiomatic Zig rewrite.
Backups every 10–15 min: run /data/backup.sh (needs HANDOFF.md updated),
then download /data/backups/qbe-zig-backup.tar.gz.

## Restore after sandbox reset
1. Extract tarball into /data (gives /data/qbe-zig and /data/backup.sh).
2. Install Zig master into /data/tools/zig (0.18.0-dev.35+5e754304d was used).
3. git clone https://c9x.me/git/qbe.git /data/qbe-c && make (reference binary).

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
Done + compiling: ops, libc, all, util, parse, cfg, abi, mem, alias, load, ssa,
copy, fold, gvn, gcm, ifopt, simpl, live, spill, rega, emit.
Written, not yet compiled: amd64/all.zig (target header; preamble.py imports
its names as `tgt.X`), amd64/targ.zig (Targets built at runtime by
`targ.init()` – main must call it), amd64/sysv.zig.
Stubs remaining: main, amd64/{isel,emit,winabi}, arm64/*, rv64/*.

## Next steps
1. Translate amd64/{isel,emit,winabi},
   arm64/{all.h,targ,abi,isel,emit}, rv64/{all.h,targ,abi,isel,emit}, main.c.
2. build.zig (exe qbe, link libc); run ./test.sh with Zig binary; diff asm
   output against C qbe for all tests in test/.
3. Hare / cproc test suites, abifuzz, own tests.
4. Canonical Zig rewrite.
