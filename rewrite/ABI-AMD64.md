# Typed base-scalar AMD64 argument classification

`abi_amd64.ArgumentCursor` is an allocation-free, per-signature classifier for the **implemented Linux SysV base-scalar subset**. Initialize with `.{};` then call `next(ScalarType)` in declaration order. It returns a typed `Location` union:

- `general: General` — RDI, RSI, RDX, RCX, R8, R9 for the first six word/long arguments;
- `vector: Vector` — XMM0 through XMM7 for the first eight single/double arguments;
- `stack: StackSlot` — a distinct typed ordinal for each overflow argument, from either bank, in declaration order.

Banks exhaust independently. Overflowing one bank does not consume an available register in the other. Word and long share the GP bank; single and double share the vector bank. GP register names take an integer width, while vector names do not silently encode a scalar width. The emitter still controls move widths and raw-bit homing.

`StackSlot.incomingOffset()` returns the positive frame-pointer displacement `16 + ordinal * 8`, after the return address and saved RBP. Offsets must fit a signed AMD64 displacement. Both cursor overflow and an explicitly forged out-of-range slot return `StackArgumentsTooLarge`. A failing `next` leaves the cursor unchanged. This arithmetic boundary is not a memory/stack-allocation guarantee: the emitter's separate aligned 64 KiB frame cap remains much tighter for actual function parameter homes.

Cursor state is caller-owned and mutable; use a new default cursor for each signature. Manually editing counters is a caller invariant, not a supported way to reclassify an arbitrary suffix. There are no shared mutable counters or allocations. Incoming parameter emission now uses these typed locations instead of maintaining its own parallel register/stack counters. Home placement and the existing default/colored/preserved modes are otherwise unchanged.

## Scope

This classifier does **not** implement aggregates, ABI-extension types, varargs, return classification, indirect arguments or another platform's ABI. Direct scalar call lowering now reuses it for outgoing arguments (see CALLS.md); the classifier alone does not implement call emission or signature validation. No C layout, pointer packing or numeric class tags are required by this internal interface.

## Verification

Four unit tests check all width-aware GP/vector names, cursor isolation, checked displacement limits/failure atomicity, and every one of **65,536 sixteen-argument integer-versus-floating class signatures**. The latter recounts each prefix independently, derives overflow position from saturated class counts, and checks the result tag before reading its payload. Scalar widths alternate within each class; this is exhaustive over those class patterns, not all four-type sequences or every possible signature length. Existing weighted mixed-ABI native cases cover distinct actual values and both overflow bank orders.

All eight compiler-option combinations retain the full integer, floating, raw-bit, phi, arithmetic-fault, termination and CLI regression suites in all three compiler build modes. No new supported language operation or full-ABI claim is implied by this extraction.
