# Native scalar vaarg descriptor consumers

Ordinary functions may read/advance a caller-supplied Linux AMD64 SysV scalar
va_list descriptor using `%value =w/l/s/d vaarg %list`. The list operand is long;
results retain the four existing base scalar classes. This is a consumer-only
slice: native variadic headers/vastart now reuse it in VARIADIC-FUNCTIONS.md;
aggregates, environment calls and other platforms/targets remain unsupported. No native descriptor allocator or
callee register-save prologue is inferred. See VARIADIC-CALLS.md for the separate
caller-side marker/AL support.

## Typed ownership and effects

`Instruction.va_argument` owns a result identity and list operand by value.
`Function.defineVaArg` checks the open block, pending result and long list before
reserving/publishing. Failed validation/allocation leaves publication unchanged
and the result retryable; retained capacity is permitted. Publicly forged list
classes are rejected by structural validation. Narrow ABI annotations remain
call-only, never new vaarg scalar classes or implicit C promotions.

The list participates in shared production operand iteration and independently
written liveness/interference use switches. Reads and descriptor advancement
remain ordered effects, including when the result is unused; folding neither
replaces nor hoists them. Descriptor aliasing and shared consumption are visible.

## Native layout and advancement

The caller supplies a valid live descriptor with four fields:

| Offset | Representation | Meaning |
| --- | --- | --- |
| 0 | unsigned32 | GP byte offset into register-save area |
| 4 | unsigned32 | SSE byte offset into register-save area |
| 8 | native64 pointer | next overflow stack argument |
| 16 | native64 pointer | register-save area |

Word/long consume the GP bank while offset<48, advancing its field by8. Single/
double consume the SSE bank while offset<176, advancing its field by16. Otherwise
both use the shared overflow pointer, advancing it by8. Only the selected bank
field changes on the register path; only the overflow pointer changes on the
stack path. Word/single load exactly4 bytes; long/double exactly8, with raw moves
preserving floating bits. Upper bytes are not silently observed or normalized.

RAX/R10 are transient scratch; persistent homes, frame size, outgoing reservation,
probes and incoming argument handling are unchanged. Unique quoted labels use
function/result identities. No helper call, host library or legacy lowering is
used. C variadic values must already have appropriate default promotions: raw
single access is an explicit IL/native contract, not compatible C va_arg(float).

Descriptor alignment/validity, available matching argument types and lifetime are
caller contracts. Native pointers are not sandboxed. Forged/out-of-range fields
can fault or address arbitrary native memory; descriptor advancement can precede
a bad source load. No invalid-input fault atomicity, bounds checking, automatic
va_end, complete SysV ABI or full QBE/backend parity is promised.

## Explicit evaluator refusal

A reached vaarg consumes its ordinary instruction step then returns
`UnsupportedVariadicOperation`, without resolving even a symbolic list, reading
memory or advancing synthetic descriptors. This applies to standalone/module
evaluation and valid Image/stack/global options. Existing configuration/argument
preflight still wins before execution (including GlobalsRequireModule for
standalone evaluation configured with globals). Earlier budget exhaustion wins;
earlier successful writes survive; owned frames clean up. Unreached paths remain
evaluable. No numeric address becomes a host pointer, no fake va_list is created,
and caller-owned Image size is unchanged.

## Independent verification design

Unit coverage includes all four classes, failure-atomic builder retry, malformed
lists/arity/annotations, SSA ordering, refusal/budgets/safe paths and earlier Image
writes, effect retention, both analysis corpora and exhaustive allocating failure
cleanup. Independent native coverage uses promoted C stdarg callers passing live
va_list descriptors into compiled ordinary helpers; host va_copy consumption is
an independent advancement reference while Python supplies numeric expectations.
Hand-laid raw descriptors cover both bank thresholds and high unsigned offsets,
all four widths, signed zero/NaN bit patterns, copies/shared consumption and source
immutability. Page-boundary successful reads detect accidental overreads. Loops,
nested/recursive calls, unused consumption and full-width preserved originals
are exercised in PIE/nonPIE and all home/folding combinations. Verification
results belong in HANDOFF.md only after completion.
