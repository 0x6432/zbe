# Explicit long-to-word projections

QBE permits long values in word contexts, using their low 32 bits. The independent rewrite now normalizes that subtype into `Operand.low_word: ValueId`. It does not change the source's declared type, invent a new SSA definition/home, or guess signedness for the opposite direction. **Implicit word-to-long extension remains invalid.** Explicit `extsw`/`extuw` still choose sign or zero extension.

## Typed representation

`Function.operandType` validates that a projection's source ID exists and has long type, then reports word. Ordinary IR builders keep exact type checking; library callers explicitly construct a projection when needed. Hand-built projections of word/floating values, out-of-range IDs and structurally mutated invalid operands are rejected. Owner-scoped IDs remain a caller invariant, not a cross-function capability.

The frontend creates this representation only for a long temporary where an opcode/return/phi/call argument expects word. Decimal constants are already parsed at the expected width. No projection changes a function ABI signature. Branches retain the existing rule that long conditions test low 32 bits without needing a projected operand. There is no implicit float widening, integer/float cast or reverse integer extension.

`Operand.referencedValue()` exposes the underlying source for ordinary values and projections; constants have none. Production SSA and liveness/interference use it. Phi-edge liveness follows the original source ID. The independent analysis oracles retain separate exhaustive operand switches instead of sharing the production accessor, and their corpora include projection operations and mixed contexts. `Instruction.operands()` copies a projected operand just like an ordinary value: it does not borrow temporary union storage or extend owner lifetime.

## Execution and optimization

The evaluator resolves the original long and returns a tagged word containing its low bits. AMD64 loads from the original home with `movl` and uses the existing word-width operation/ABI path; the long source home is unchanged and can be used later at full width. This applies to arithmetic, shift counts, word comparisons, byte/half/word stores, explicit extensions, word-source numeric conversions, raw word/single casts, phi inputs, word returns and word call arguments, including outgoing stack arguments and indirect calls.

Integer folding projects only a known long fact and produces a word fact. Unknown sources remain unknown. Existing source-order behavior and arithmetic faults/effects are preserved; low-word signed minimum divided by minus one still faults natively and returns `IntegerOverflow` in the evaluator. Nonzero high words do not hide a zero word divisor.

## Reference evidence and bounded tests

The local upstream Subtyping section's first paragraph and arithmetic/branch examples explicitly allow long-to-word use. A later sentence reverses the wording and conflicts with its own signedness rationale. Bounded probes against the unchanged C reference confirmed long-to-word arithmetic, long shift counts and word returns, and rejection of implicit word-to-long addition. This slice follows that behavior; it does not claim every IL subtype/ABI feature.

`generate_low_word_oracle.py` adds **1,024 exact Python integer cases** over sixteen word operations. Every runtime source has nonzero randomized high bits; expectations use only low words, explicit signed interpretation, masked shifts and integer quotient/remainder identities. Existing numeric and arithmetic oracle fixtures are unchanged. Former negative parser/numeric-harness cases using legal long-in-word contexts were replaced by genuinely invalid floating classes, retaining rejection/output-preservation counts and adding explicit acceptance tests.

Six new unit tests plus an iterator test cover the oracle with/without folding, projection source/type/bounds validation, unchanged original types and values, phi/call/store/cast/numeric/shift/return contexts, malformed SSA and phi-edge dominance, no implicit widening, raw NaN payloads, retained arithmetic errors and exhaustive parser/analysis/folder/module-evaluator/emitter allocation cleanup. A seventh native harness checks **2,114** defined outcomes, **two SIGFPE** fault-retention cases and **eight rejection/output-preservation** checks per option combination. The defined checks include the 1,024 oracle cases, 64 mixed-context patterns, original long uses after calls, overflowing word sums, direct/indirect calls, stack arguments, loop phis, raw casts, stores with guards and full preserved-register restoration. Child execution is bounded and core dumps disabled.

All eight harnesses and twelve generators are wired into the three-build/eight-option matrix. Actual results are recorded in HANDOFF.md only after completion. This is not complete compiler/ABI/target parity, a full allocator or a claim of 100% idiomatic Zig.
