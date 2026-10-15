# Optimization roadmap

These are the next candidate optimizations, in rough order of value/risk.
Each must ship with the same verification as the existing ones:
`tests/opttable.py` entries (op x constant x class vs a gcc C oracle,
including worst-case inputs), `tests/optfuzz.py` coverage, a new mutant in
`tools/mutate.py` that the tests kill, and `tools/optsweep.sh` on all targets
(plus native/qemu execution on arm64 and rv64 in CI).

Rule of the project: a rewrite is only added if it is provably correct for
every input; correctness beats the number of optimizations.

## 9. Unsigned 32-bit division by "33-bit magic" constants (e.g. /7) — DONE (1.4.1)

Implemented in simpl.zig (`udivmagic33`, `udivconst`): q = ((x*m' >> 32) + x) >> (s-32)
in 64-bit registers. tools/opt2.py: unsigned divs left at -O2 went 270 -> 26.


Status: `udivconst` (src/simpl.zig) only accepts a magic m < 2^32 with error
<= 2^(s-32). About 1 in 5 divisors (7, 14, 19, 21, 27, 28, 31, ...) need
m = 2^32 + m', which does not fit the one-multiply sequence, so the `div`
is kept today.

Plan: since x < 2^32 and m < 2^33, x*m < 2^65 overflows a 64-bit multiply,
but it can be computed exactly in 64 bits as `(x << 32) + x*m'`... which also
overflows. Instead use the standard add-and-shift form on 64-bit values:

    t = extuw x            # 64-bit
    p = mul t, m'          # m' = m - 2^32 < 2^32, so p < 2^64
    q = shr p, 32          # high word of x*m'
    r = sub t, q ; r = shr r, 1 ; r = add r, q ; r = shr r, s-33

or more simply, because t < 2^32, `(t*m') >> 32` plus `t` fits in 33 bits and
`(t + ((t*m') >> 32)) >> (s-32)` is exact. Verify with the worst-case dividend
proof used by `udivmagic` and exhaustive checks for small d.

Risk: low. Gain: removes the remaining ~270 32-bit `div` in opt2's -O2 output.

## 10. Signed division / remainder by non-power-of-two constants (e.g. x/10)

Status: only signed powers of two are rewritten (`sdivpow2`).

Plan (Granlund-Montgomery / Hacker's Delight 10-1), for w class:

    t = extsw x
    p = mul t, M           # signed magic M, 64-bit product
    q = sar p, 32 + s
    q = sub q, (t sar 63)  # +1 for negative x (round toward zero)
    (rem: x - q*d)

Negative divisors: negate the quotient. Exclude d = 0, +-1, and handle
INT_MIN carefully (C's INT_MIN / -1 is UB; QBE's behaviour follows the
hardware, so the rewrite must not be applied to -1).

Risk: medium (sign/rounding). Gain: common in real code (itoa, `% 10`, ...).

## 11. 64-bit division by constants

Needs the high half of a 64x64->128 multiply, which QBE IL does not have.
Requires a new target-specific instruction on every backend (amd64 `mul`/
`imul` one-operand forms writing rdx:rax, arm64 `umulh`/`smulh`, rv64
`mulhu`/`mulh`), register-allocator constraints for amd64's fixed
registers, and emitter changes in all 6 targets.

Risk: high (touches isel/rega/emit on every target). Gain: large for 64-bit
division-heavy code. Do 9 and 10 first.

## 12. Redundant extension elimination — INVESTIGATED, not needed

A pass turning extsb(loadsb), extuh(extub x), extub(and x, 0x7f) into copies
was written and measured (1.4.1 dev): 0 instructions saved on test/*.ssa
(89 movs/movz before and after) — the existing isel/copy passes already
remove these. Not merged.


Remove `extsw`/`extuw`/`extsb`/... when the operand is already known to be
extended the same way (e.g. result of a load with the same extension, or of
an earlier identical extension, or a constant). Also fold
`extuw (and x, mask)` when mask < 2^31.

Risk: low, but needs a small per-temp "known extension" lattice; must respect
that w-class values have undefined upper bits in QBE. Gain: small, mostly
fewer `mov`s on amd64 and `sxtw`/`uxtw` on arm64.

## 13. Larger optimizations (higher risk, beyond gcc -O1/-O2 "low hanging")

- Loop strength reduction / induction variable simplification (turn `i*k`
  in loops into an additive recurrence). Needs loop detection (QBE has loop
  info used by GCM) and careful overflow semantics.
- Function inlining of small leaf functions in the same file. QBE compiles
  function by function and streams output, so this needs buffering of
  functions and a cost model.
- Tail calls (`call` immediately followed by `ret` of its result) into
  jumps, per-target ABI constraints (stack arguments, struct returns).
- Better register allocation hints / coalescing.

These are deliberately left out of the -O2 set: they change control flow or
ABI-level behaviour and would need much larger test suites (including
hare/cproc bootstraps on every target) before being trusted.

## AMD64 shift-based address scales — measured candidate (unreleased)

Power-of-two multiplication is already lowered to shifts by the generic
optimizer. AMD64's matcher historically recognized only the multiplication
view, so `base + (index << k)` could require a separate shift and scale-1
memory operand even for k = 1, 2, 3.

At -O1/-O2, instruction selection normalizes only its private numbering view:
long `shl index, k` becomes the existing multiply-by-2/4/8 pattern. The IR is
not rewritten. For all 64-bit bit patterns, shifting left by these counts is
multiplication by 2^k modulo 2^64, exactly the arithmetic of the machine's
64-bit effective address. Word shifts are excluded because they wrap at 32
bits and their upper bits are not defined. Variable counts, non-bit constants
and counts outside 1..3 are excluded. A matched address with a displacement
outside signed 32-bit range falls back to the original register arithmetic:
64-bit wrapping arithmetic does not widen x86's encoded displacement field.
-O0/QBE_COMPAT behavior is unchanged.

This is target address selection, not a new scalar arithmetic rewrite, so
scalar-only opttable/optfuzz cannot detect its essential memory-access or
shape failures. `tools/address-scales.py` supplies a seeded memory oracle
(loads AND stores, wraparound/high-bit indexes, shared shift values, word
shifts, multiplication, scale and non-scale counts), optimized AMD64 assembly
checks and six-target compatibility comparisons. It runs alongside the
unchanged scalar suites, including cross-target execution in CI.
`tools/address-scales-mutate.py` requires that a wrong scale is killed by an
actual memory-oracle mismatch, not a build failure. The existing eleven
simpl.zig mutation patterns remain intact. Full core, all-target optsweep and
source-specific CI remain required before treating the candidate as verified.
