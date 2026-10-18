# Opt-in root-only synthetic variadic initialization

`Options.root_variadic_arguments: ?[]const ir.Constant` defaults to null. A
non-null slice (including an empty one) explicitly enables synthetic `vastart`
for the root invocation only. The ordinary evaluator `arguments` array still
contains exactly the named arguments; it never silently accepts or drops a tail.
`Options.consume_vaargs` independently enables consumers (INTERPRETER-VAARG.md).
Neither option authorizes internal variadic calls, host/external/indirect calls,
implicit C promotions, environment+varargs, aggregates or full ABI interpretation.
The supplied slice is borrowed only for synchronous evaluation, never mutated or
freed; its values are copied into owned synthetic bytes if initialization occurs.

## Preflight and lazy storage

Existing validation, zero-depth, memory configuration/global setup and exact
named-argument frame checks keep their order. A non-null explicit tail on a
nonvariadic root then returns `UnexpectedVariadicArguments`, before executing an
instruction. With null, defaults are unchanged. A variadic no-varop path needs
no stack memory and creates no save area, even with a nonempty explicit tail.

A reached `vastart` consumes one ordinary instruction step. Exhaustion wins before
operation capability/access. A null tail returns `UnsupportedVariadicOperation`
before list resolution, including with manually enabled consumers. With an
explicit root tail, resolve the long list and check a complete24-byte destination
in one existing live Image/global/stack object. No memory model returns
`UnsupportedMemory`; invalid/overflowing/split/guard spans return
`MemoryOutOfBounds`. A bad destination is rejected before source allocation or
destination mutation. Initialization is complete-span/failure-atomic, an explicit
diagnostic-model policy, NOT native sequential invalid-address fault parity.

First valid reached initialization lazily materializes one root-owned source
object through the existing **explicit** `stack_memory` option. It does not enable
stack memory, resize the Image or invent a native pointer. With a valid Image
but no stack option it returns `UnsupportedAllocation`. Even an empty tail needs
the176-byte register region if initialization occurs. Source storage is charged
by ordinary stack round-up/16-byte guards against the cumulative reservation;
layout-size/cap failures return `StackLimitExceeded`; the existing allocator
round-up overflow remains `AllocationSizeOverflow`.
An allocator failure cannot publish a partial descriptor. Earlier completed
Image writes remain, on any later error; ownership always cleans up.

## Raw argument layout and initialization

The single requested object contains176 register bytes, followed by8-byte
shared overflow slots in declaration order for **all named and tail placements**.
Integer word/long values use six independent8-byte GP slots; single/double values
use eight independent16-byte SSE slots starting at48. After a bank exhausts,
arguments of that bank use the next shared overflow slot. Named parameters are
placed first, then the explicit tail, without resetting either bank. Narrow ABI
annotations retain ordinary word transport; no extension/promotion is inferred.

Only the actual4/8 raw bytes of each supplied value are initialized. Unused slots
and narrow/SSE padding remain uninitialized, not fabricated zero hardware values.
Negative zero and signaling/quiet NaN payloads are preserved without floating
arithmetic. Reading beyond supplied bytes or with a wider consumer retains
existing uninitialized/bounds errors and cursor-before-source ordering. Consumer
types remain caller contracts; there is no implicit argument-count/type metadata
check or native garbage-value emulation.

The initialized24-byte descriptor contains:
- GP offset8 times occupied named GP registers;
- SSE offset48 plus16 times occupied named SSE registers;
- overflow pointer after the named overflow slots;
- save pointer at this invocation's owned register region.

Each descriptor field uses its **destination region's** configured byte order;
saved values use the stack region's byte order. Mixed-endian descriptors/sources
are deliberate synthetic coverage, not a native big-endian System V ABI claim.
Access uses existing bounded scalar/byte operations, never host dereferencing.

## Reinitialization, copying and lifetime

Per-root state retains only the initial offsets/pointers, not a second hidden
owner or cached argument copy. Repeated `vastart` reuses the same source object
and writes initial descriptor cursors again; it does **not** restore mutated
saved values or consume another stack reservation. A bounded descriptor blit
creates independent cursors sharing source bytes. A forged numeric address into
a live source object is accepted under the existing synthetic memory model;
this is not a capability/provenance system.

Ordinary child frames may consume the root descriptor when consumers are enabled.
Their object marks preserve root source lifetime; returning frees only child
objects. Root return/error releases the source with all other root objects.
Escaped numbers confer no later authority, and new evaluations reset state. The
borrowed Image keeps its size, ownership and completed writes. Globals remain
owned/reset per evaluation. No stack address is rewound/reused within evaluation.

By default, reached internal variadic calls still return `UnsupportedVariadicCall` before
depth/argument resolution. Standalone calls still return `UnsupportedCall`; other
host-call refusals remain unchanged. An explicit root tail is not inherited by
children, nor a dispatch capability. Separate explicit internal dispatch and child-owned
initialization are described in INTERPRETER-VARIADIC-CALLS.md.
There is no va_end runtime helper, implicit
va_copy, native va_list import or complete variadic interpreter.

## Verification design

Independent expected descriptor bytes/raw values cover all four classes, both
entry APIs, raw special values, mixed byte orders, named GP/SSE exhaustion and
declaration-ordered overflow, padding initialization, exact capacities, copied
cursors/reset without source rematerialization, deep ordinary child growth and
root source lifetime. Further checks cover defaults/preflight/budgets/arity,
invalid whole spans/guards, source holes, globals reset, retained earlier writes,
unsupported calls and injected allocation-failure cleanup. Native code, frontend,
IR, analyses and prior independent fixtures/harnesses/generators are unchanged.
Actual completed results belong in HANDOFF.md; this design alone claims none.
