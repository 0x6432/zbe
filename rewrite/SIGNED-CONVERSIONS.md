# Signed numeric integer/floating conversions

The independent frontend/IR/evaluator/native Linux AMD64 slice accepts these numeric conversions, separately from raw-bit `cast`:

| Opcode | Source | Result |
| --- | --- | --- |
| `swtof` | word, interpreted as signed i32 | single or double |
| `sltof` | long, interpreted as signed i64 | single or double |
| `stosi` | single | word or long, signed result |
| `dtosi` | double | word or long, signed result |

Integer-to-floating conversions may round. Floating-to-signed conversions discard the fractional part **toward zero**. This is not sign/zero extension, bit reinterpretation, saturating arithmetic or a reversible roundtrip: for example, converting signed i64 maximum to double can round to 2^63, which cannot then be converted back to a valid signed i64.

Unsigned numeric conversions (`stoui`, `dtoui`, `uwtof`, `ultof`) now extend this path; see UNSIGNED-CONVERSIONS.md for their domain checks and native high-half algorithms. Double-to-single `truncd` remains unsupported. The existing narrowing documentation/reference discrepancy remains unresolved; adding these signed operations does not silently choose narrowing semantics. Implicit operand-width conversions and extended ABI classes are not added.

## Typed representation and ownership

`ConvertOp` describes four semantic source/sign directions and checks the permitted result class. `Instruction.convert` has one operand and one pending typed result; it is distinct from non-fallible bit-pattern unary instructions. `defineConvert` checks block openness, pending definition and source/result types before reserving instruction capacity and publishing its backlink. Allocation failure leaves the result pending and publishes no instruction. No extra owned/borrowed variable storage is introduced.

Structural validation checks types/backlinks, the shared use iterator supplies the operand to production SSA/liveness/interference, and the independent analysis oracles retain their own exhaustive conversion case. Integer constant folding deliberately leaves conversions unknown and executable, including unused results: folding/deleting them could change rounding, exceptions or evaluator error behavior. No floating-environment-sensitive constant propagation is introduced.

## Evaluator domain and limits

`semantics.convertedValue` uses explicit signed i32/i64 bit interpretation and strict f32/f64 conversion operations. For float-to-integer it checks finiteness, computes the truncated value and verifies that **that value** is within the signed result range before any host integer cast. The lower bound is inclusive and the positive 2^31/2^63 bound exclusive. In particular, a representable double -2147483648.5 truncates to valid i32 minimum; checking the untruncated source against minimum would reject it incorrectly.

NaN, infinities and out-of-range truncated values return **`ConversionOutOfRange`** without invoking an invalid host integer cast. This is an explicit evaluator boundary, not a portable value/error assigned by QBE to invalid conversions. The normal instruction-step budget applies; earlier budget exhaustion wins. An unused result still executes and can return that error. Raw same-width casts continue to preserve all floating bits without numeric interpretation.

The conformance fixture tests round-to-nearest, ties-to-even integer-to-float results under the default floating environment. There is no claim of complete host/target rounding-mode equivalence, floating exception flags, signaling-NaN arithmetic behavior or protection against unmasked host floating exceptions. Strict float mode is not a full floating-environment emulator.

## Linux AMD64 lowering

Signed integer-to-float uses width-appropriate `cvtsi2ss`/`cvtsi2sd`; float-to-signed uses `cvttss2si`/`cvttsd2si` with an explicit word/long result width. Raw bits transfer between RAX and XMM0 around the operation, then return to the existing homes. Existing incoming homing, outgoing calls, phi scratch and full callee-saved restoration remain unchanged. These scratch registers are never persistent homes.

Native integer-to-float instructions follow the caller's MXCSR rounding mode; the truncating float-to-integer instructions use toward-zero conversion. Native out-of-domain conversions are **not** rewritten into the interpreter's typed error or checked/saturating code. Their ISA/environment-dependent masked invalid result or unmasked exception lies outside the defined-value conformance claim. Such invalid values are not executed as native correctness-oracle cases.

## Bounded verification

Six added tests cover 512 independently generated exact Python Fraction expectations, typed builder failure retry/closed blocks/tampered structure, invalid result/source classes, malformed SSA, unused error-producing conversions, budget/error precedence, loop-carried phis with/without folding, all home strategies and exhaustive parser/analysis/evaluator/emitter allocation cleanup. Domain tests separately check positive/negative infinity, quiet/signaling NaNs, both signed bounds, the valid lower-bound fractional case, negative fractional truncation and signed zero.

`generate_signed_conversion_oracle.py --check` verifies **512 cases**, 64 per source/result direction: signed word/long to single/double, and single/double to signed word/long. Expected bits use Python exact Fraction decoding/nearest-even encoding and integer truncation, never host floating arithmetic or compiler output. Cases include signed extrema, integer precision/tie boundaries, subnormals, both zero signs, fractional truncation and nearby signed boundaries. The generator reuses the existing independent rational encoder, not production Zig semantics.

The sixth native harness, `tools/native_numeric_check.py`, sets FE_TONEAREST and checks **521 defined-value results** per option combination: the 512 oracle cases, five loop-sum cases, a mixed integer/SSE/stack-argument pressure case, an internal wrapper, full preserved-register checking and a safe path that never reaches an invalid conversion. Unsigned coverage now extends that same harness to **1,554** defined results and **20 rejection/output-preservation checks** for malformed types and retained unsupported narrowing. It links PIE, disables core dumps and bounds child execution time. CI runs it in all eight option combinations in Debug/ReleaseSafe/ReleaseFast, alongside the existing five native harnesses and eleven reproducible generators.

These are bounded regressions, not exhaustive IEEE/QBE/ABI acceptance, target parity, a performance claim or a completed optimizer.
