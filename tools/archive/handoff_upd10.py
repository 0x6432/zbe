p='/data/qbe-zig/HANDOFF.md'
s=open(p).read()
old='PLAN (user approved, in order): (1) strings DONE; (2)'
new='''DONE 6k: typed vector API in util.zig: Vec header {mag,pool,cap};
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
PLAN (user approved, in order): (1) strings DONE; (2) vectors DONE; (2b) tests DONE; (3)'''
assert old in s
s=s.replace(old,new)
s=s.replace('stages 1-6j done','stages 1-6l done').replace('current as of stage 6j,','current as of stage 6l,')
open(p,'w').write(s)
