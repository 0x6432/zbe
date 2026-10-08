# Upstream QBE issues found while testing the port

Found with tests/irfuzz.py against the C reference (qbe e786f06). The Zig
1:1 port reproduces them faithfully (byte-identical output). Candidates for
reporting upstream / fixing in the canonical Zig version.

## 1. amd64: jnz/select on a shift result reuses stale flags
ops.h marks sar/shr/shl as SetsZeroFlag (`X(1,1,0)`), so amd64 isel elides
the `cmp` before `jnz` (and ifopt selects -> cmov). But x86 shifts whose
(masked) count is 0 leave the flags unchanged.
Reproducer: tests/upstream-bug-shift-flags.ssa
```
%n =w add %b, 32
%x =w shr %a, %n
jnz %x, @nz, @z      # t(0,0) returns 1, expected 0
```
Fix idea: zflag = 0 for sar/shr/shl in ops.h (X(1,0,0)).

## 2. amd64: shift counts that are/fold to constants >= width
Immediate shift counts are emitted verbatim, e.g. `shrq $1048576, %rdi` or
`shrq $4294967267, %rdx` (after folding `%c =w sub 3, 32`) -> assembler
error "operand type mismatch". Fix idea: mask immediate counts with
(width-1) in amd64 isel/emit (and check fold).

tests/irfuzz.py avoids both unless run with --upstream-bugs.

## 3. util.c igroup(): Osel1 case asserts the wrong instruction (latent)
```c
case Osel1:
	for (; i>ib && (i-1)->op == Osel1; i--)
		;
	assert(i->op == Osel0);   /* i is the first Osel1 here, not the Osel0 */
```
After the loop `i` points at the first `sel1` of the run, so the assert can
only hold if the run is empty; the intended code is presumably
`for (; (i-1)->op == Osel1; i--); i--;` (or asserting `(i-1)->op == Osel0`).
Not reachable today: gcm's schedblk always enters a sel group at its `sel0`.
The Zig port keeps the upstream behavior (util.zig igroup).
