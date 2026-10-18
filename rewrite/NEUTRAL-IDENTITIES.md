# Proposed next independent milestone: operand-preserving integer identities

Approved bounded design, implemented by the existing opt-in integer pass. No common, alloc-alias, floating,
ABI, target or register-allocation overlap.

Actual gap: rewrite/OPTIMIZE.md and src/optimize.zig foldIntegerConstants/folded
require both binary operands known; dynamic x+0, x*1, x|0, x^0, x&allones and
masked-zero shifts remain arithmetic instructions. The verified semantics and
native scalar backend already define their integer widths and count masking.

Choose only operand-PRESERVING identities (word/long): x+0,0+x,x-0,x*1,1*x,
x|0,0|x,x^0,0^x,x&allones,allones&x; and x shifted by a known count whose existing
five/six-bit mask is zero. Rewrite the same result to copy of the ORIGINAL other
operand, preserving low_word/symbol forms and exact type. Try existing complete
constant fold first; source-order constant facts can prove the neutral operand.
Do not add identities that DISCARD unknown operands (x*0,x&0,x-x,x^x), div/rem,
float or comparisons. Besides avoiding arithmetic-fault mistakes, this preserves
UnsupportedSymbolAddress/bounds/refusal behavior of operand resolution itself.
No known function address or host call inference from symbolic long operands.

Invariants: current SSA validation + all scratch allocation before mutation;
no new allocation after rewrites begin. Keep instruction count, result IDs,
backlinks, CFG, phi inputs/terminators and shared interpreter step counts unchanged.
No DCE, parameter/phi facts, fixed point, branch simplification or moving effects.
No change to default emitter path: retain opt-in --fold-integers and document its
expanded conservative integer-simplification scope. No speed claim without data.

Acceptance: independent width-masked Python integer expectations over all rules,
constants supplied directly/through existing known facts, both operand orders,
bit-boundary+seeded values, long-to-word projections and count32/64 multiples.
Compare pre/post validated interpretation and native runtime across existing home
options; assert arithmetic-to-copy transformation/unchanged default rather than
assume runtime speedup. Nonmatching constants, float signed zeros/NaNs, division
faults, symbolic-address refusal, ordered calls/load/store/alloc/vaarg/vastart and
unused effect results must retain old behavior. Validate idempotence, unchanged
IDs/CFG/steps, exhaustive allocation failure/retry and independent mutants that
apply an incorrect identity or erase a symbolic-resolution fault. Preserve old
oracle fixtures/harnesses/CI; additive identity fixtures/harness only if justified.
Final frozen3mode/fmt/all generators/full24 native configs plus new coverage,
independent review, verified commit/push and actual exact-SHA CI before full green.

## Ownership and accounting

The existing invocation-owned facts array and SSA scratch are the only scratch
storage; all allocation/validation completes before the first rewrite. The helper
is pure and allocates nothing. Copies retain the original value ID/projection or
module-pool symbol ID/addend without borrowing new storage. The facts array is
freed on return and no cached state survives an invocation. Instruction and step
budgets do not change; a copy still resolves its operand at the original point.
There is no module transaction guarantee beyond the existing per-function API.

## Additive acceptance tooling

`tools/neutral_identity_generate.py --check` reproduces 476 independent seeded
width-boundary/near-miss cases. `neutral_identity_test.zig` checks those results,
exact rewrite selection, payloads, step/error precedence, Image writes, overflow,
ordered effects, and allocation-failure atomicity plus same-function recovery.
`tools/neutral_identity_native_check.py` exercises 479 runtime assertions in each
of PIE and non-PIE links plus four arithmetic-fault controls per configuration.
The generator and native harness are registered in the existing CI workflow.

`tools/neutral_identity_mutation_check.py --zig /path/to/pinned/zig --evidence DIR`
uses temporary copies only and requires semantic assertions to reject four
compiling mutants (wrong long shift mask, wrong long all-ones, multiply annihilator,
and dropped symbol addend). It does not accept a compile error as a killed mutant.
