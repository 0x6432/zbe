# Unsigned numeric integer/floating conversions

The independent rewrite accepts `uwtof` (unsigned word → single/double), `ultof` (unsigned long → single/double), `stoui` (single → unsigned word/long) and `dtoui` (double → unsigned word/long). These are four explicit `ConvertOp` variants, not overloaded raw-bit casts or implicit width changes. Signed operations remain separate (SIGNED-CONVERSIONS.md). Precision narrowing `truncd` remains unsupported and its documentation/reference discrepancy is not resolved here.

## Typed semantics and evaluation

Unsigned integer sources use their complete u32/u64 bit patterns. Integer-to-floating conversion can round; e.g. u64 maximum rounds to 2^64 in the default nearest-even environment, so converting it back to unsigned long is invalid. Floating-to-unsigned truncates toward zero, not saturation or modulo masking.

Before any host integer cast, the evaluator rejects nonfinite inputs, computes the truncated value, then checks `0 <= truncated < 2^32` or `2^64`. Negative fractions between -1 and zero (including negative subnormal/zero) therefore produce valid zero. A double 4294967295.5 produces valid u32 maximum. Negative integers, NaN, infinities and the exclusive upper bound return `ConversionOutOfRange`. The error is an explicit evaluator boundary, not a portable QBE result or native checked-conversion convention. Earlier instruction-budget exhaustion wins; unused conversions remain executable and may fail.

The existing failure-atomic builder, exact parser classes, owned result definitions, shared single-use operand iterator, SSA and analysis checks apply unchanged. Conversion facts remain unknown to the integer folder; no rounding-/error-sensitive conversion is folded or deleted. No new pointer ownership, global state or allocation convention is introduced.

## Linux AMD64 algorithms

Lowering uses caller-saved RAX/R10 and XMM0/XMM1 scratch, never persistent homes. Quoted internal labels include function ordinal, result ValueId and a separate conversion namespace; multiple conversions and CFG labels cannot collide.

- **Unsigned word → float:** a word load clears RAX's upper bits. Signed **64-bit** SSE conversion then covers the entire u32 domain, including values above i32 maximum.
- **Unsigned long → float:** the lower half uses signed 64-bit SSE conversion directly. For the upper half, `(n >> 1) | (n & 1)` retains the low-bit sticky information before signed conversion; doubling the floating result restores scale exactly. This is justified/tested for nearest-even results, not a promise of every floating rounding mode or identical exception flags.
- **Float → unsigned word:** signed 64-bit truncation covers the defined u32 domain, followed by saving the low word.
- **Float → unsigned long:** compare against exactly representable 2^63. Below it, use signed 64-bit truncation. At/above it, subtract 2^63, truncate the nonnegative signed-range remainder, and restore bit 63. For defined upper-half inputs the subtraction is exact by Sterbenz's lemma. Single/double threshold bits are respectively `0x5f000000` and `0x43e0000000000000`.

No native NaN/range checks, saturation, typed error return or floating-environment emulation is added. Out-of-domain native results/exceptions are outside the defined-value contract. Tests set FE_TONEAREST; unmasked host/target exceptions, signaling-NaN arithmetic and exception-flag equivalence are not claimed. Native invalid conversions are not used as correctness-oracle rows. Existing homes, phi copies, outgoing calls and full preserved-register restoration are unchanged.

## Bounded verification design

`generate_unsigned_conversion_oracle.py` independently uses exact Python Fraction arithmetic and the existing rational IEEE nearest-even encoder, never production semantics or compiler output. It adds **1,024** cases, 128 for each of eight source/result combinations. These cover unsigned extrema, high-bit transitions, precision and halfway ties with either adjacent value, signed-boundary crossings, unsigned limits, subnormals, both zero signs and valid negative fractions. Separate evaluator tests reject NaN/infinity/negative integers/out-of-range values before host casting.

Six added unit tests cover the oracle, domain boundaries, failure-atomic typed builders/parser/structure checks, SSA/use-before-definition, unused conversion retention and step precedence, loop phis/folding, all home modes and exhaustive allocation cleanup. Independent liveness/interference corpora include the eight conversion functions and loop.

The existing sixth native harness now checks **1,554 defined results** per option combination: previous 521 signed results, 1,024 unsigned oracle results, five unsigned loop sums, mixed GP/SSE/stack pressure, an internal call, preserved-register restoration and high-bit literal/multiple-conversion label checks. It also checks **20** malformed/unsupported-input output-preservation outcomes. The matrix now includes eight native suites across eight option combinations and three build modes, with twelve independent generator checks; the projection extension is described in LOW-WORD.md. Actual verification outcomes belong in HANDOFF.md, not assumed from this test design.

These are bounded semantic/ABI regressions, not exhaustive IEEE/QBE conformance, a complete compiler, all-target parity, full register allocation or a claim of 100% idiomatic code.
