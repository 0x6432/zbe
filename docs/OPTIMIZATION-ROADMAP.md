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
