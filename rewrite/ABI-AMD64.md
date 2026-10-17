# Typed base-scalar AMD64 argument classification

`abi_amd64.ArgumentCursor` is an allocation-free, per-signature classifier for the **implemented Linux SysV base-scalar subset**. Initialize with `.{};` then call `next(ScalarType)` in declaration order. It returns a typed `Location` union:

- `general: General` — RDI, RSI, RDX, RCX, R8, R9 for the first six word/long arguments;
- `vector: Vector` — XMM0 through XMM7 for the first eight single/double arguments;
- `stack: StackSlot` — a distinct typed ordinal for each overflow argument, from either bank, in declaration order.

Banks exhaust independently. Overflowing one bank does not consume an available register in the other. Word and long share the GP bank; single and double share the vector bank. GP register names take an integer width, while vector names do not silently encode a scalar width. The emitter still controls move widths and raw-bit homing.

`StackSlot.incomingOffset()` returns the positive frame-pointer displacement `16 + ordinal * 8`, after the return address and saved RBP. Offsets must fit a signed AMD64 displacement. Both cursor overflow and an explicitly forged out-of-range slot return `StackArgumentsTooLarge`. A failing `next` leaves the cursor unchanged. This arithmetic boundary is not a memory/stack-allocation guarantee: the emitter's separate aligned 64 KiB frame cap remains much tighter for actual function parameter homes.

Cursor state is caller-owned and mutable; use a new default cursor for each signature. Manually editing counters is a caller invariant, not a supported way to reclassify an arbitrary suffix. There are no shared mutable counters or allocations. Incoming parameter emission now uses these typed locations instead of maintaining its own parallel register/stack counters. Home placement and the existing default/colored/preserved modes are otherwise unchanged.

## Scope

This classifier does **not** itself implement aggregates, ABI annotations, varargs, return classification, indirect arguments or another platform's ABI. The separate sb/ub/sh/uh slice maps those typed annotations to the word class before classification (SUBWORD-ABI.md). Direct scalar call lowering now reuses it for outgoing arguments (see CALLS.md); the classifier alone does not implement call emission or signature validation. No C layout, pointer packing or numeric class tags are required by this internal interface.

## Verification

Four unit tests check all width-aware GP/vector names, cursor isolation, checked displacement limits/failure atomicity, and every one of **65,536 sixteen-argument integer-versus-floating class signatures**. The latter recounts each prefix independently, derives overflow position from saturated class counts, and checks the result tag before reading its payload. Scalar widths alternate within each class; this is exhaustive over those class patterns, not all four-type sequences or every possible signature length. Existing weighted mixed-ABI native cases cover distinct actual values and both overflow bank orders.

All eight compiler-option combinations retain the full integer, floating, raw-bit, phi, arithmetic-fault, termination and CLI regression suites in all three compiler build modes. No new supported language operation or full-ABI claim is implied by this extraction.

External/indirect variadic scalar call sites now have a checked named-argument
prefix marker and final AMD64 AL setup (VARIADIC-CALLS.md). Variadic function
bodies and vastart are supported separately (VARIADIC-FUNCTIONS.md); interpreter
host calls remain unsupported. C
default promotions are explicit caller responsibilities, not inserted conversions.

Caller-supplied native scalar vaarg consumers are a separate bounded slice
(VAARG-CONSUMERS.md); their caller-supplied descriptor model is reused by native definitions/vastart
(VARIADIC-FUNCTIONS.md); interpreter descriptor emulation is not implemented. Reached evaluation explicitly refuses the operation.

Native scalar variadic definitions and effect-only vastart now have a separate
frame-owned save region and checked named signatures (VARIADIC-FUNCTIONS.md).
Interpreter variadic calls/operations remain explicit refusals.

Nonvariadic scalar environment calls now have a distinct hidden long operand/
parameter and Linux AMD64 RAX mapping, without shifting ordinary ABI arguments
(ENVIRONMENT-CALLS.md). Root/module interpreter mapping remains synthetic and
bounded; environment+varargs and aggregates remain unsupported.
