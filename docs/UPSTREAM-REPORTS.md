# Draft reports for upstream QBE (~mpu/qbe-dev@lists.sr.ht)

Drafts only, not sent. Against qbe e786f06. Details/repros in BUGS.md.

---
Subject: [BUG] amd64: jnz/sel after shift uses stale flags when count is 0

ops.h marks shl/shr/sar as setting the zero flag, so amd64 isel drops the
`cmp` before `jnz` (and ifopt turns sel into cmov on the same flags). x86
shifts with a masked count of 0 leave the flags unchanged, so the branch tests
an earlier result. Repro: tests/upstream-bug-shift-flags.ssa (`%n =w add %b,
32; %x =w shr %a, %n; jnz %x` returns 1 for a=0,b=0). Suggested fix: X(1,0,0)
for the three shifts in ops.h.

---
Subject: [BUG] amd64/rv64: immediate shift counts >= width reach the assembler

Constant shift counts are emitted verbatim (`shrq $1048576, %rdi`, or after
folding `sub 3, 32`: `$4294967267`), and gas rejects them; rv64 emits e.g.
`sll t0, a0, 64` ("improper shift amount"). IL semantics take the count modulo
the width, so isel should mask immediates with (width-1). Patch: see the
amd64/rv64 isel hunks in zbe tools/qbe-cfix.patch.

---
Subject: [BUG] util.c igroup(): Osel1 case asserts on the wrong instruction

After `for (; i>ib && (i-1)->op == Osel1; i--);` `i` is the first sel1, not
the sel0, so `assert(i->op == Osel0)` fires on any sel group (latent: only
reached by callers that start at a sel1). Fix: `assert((i-1)->op == Osel0);
i--;` (or adjust the loop).
