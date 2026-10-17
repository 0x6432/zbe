# Opt-in bounded interpreter stack objects

Both evaluator entry points accept `interpreter.Options.stack_memory: ?StackOptions`
(default null) to enable evaluator-owned synthetic stack objects. It never converts
IL integers into host pointers, resizes the borrowed Image, or changes native
allocation lowering. Without it, reached allocations retain UnsupportedAllocation,
including zero size. With it, zero size returns address `0` (not dereferenceable).

StackOptions specifies a nonzero 16-aligned base (default 0x100000000), a byte
order (default little), and max_bytes (default 1 MiB). The complete synthetic
reservation must fit u64 and must not overlap a supplied nonempty Image. Invalid
configuration is rejected before execution, after normal validation/depth checks.

Each positive execution creates a separate owned byte slice plus initialization
tracking. All allocation forms are over-aligned to 16. Only the requested bytes
are accessible: rounding padding and a 16-byte synthetic guard are not objects.
The monotonic reservation charges roundUp(size,16)+16 against max_bytes across
the entire evaluation, not only live objects. Round-up overflow is
AllocationSizeOverflow; capacity exhaustion is StackLimitExceeded. Zero consumes
no reservation. This bounds object count and total payload/initialization bytes,
not total interpreter/analysis resources or allocator metadata.

Frames retain an object-count mark. Returning frees objects since that mark;
caller objects remain accessible by callees. Addresses are never reused during
an evaluation, so later sibling calls cannot revive a stale pointer. All objects
are freed on error or root return. Numeric results/image bytes can retain escaped
addresses, but they authorize no later access. A new evaluation resets its address
namespace: there is no cross-evaluation provenance guarantee. Forged numeric
addresses into a live object are accepted; this is not a capability model.

Loads require every byte initialized; otherwise UninitializedMemory. Stores
validate the whole object span/type before mutation and mark those bytes defined.
Blits resolve two complete spans (image or single live object), reject partial
overlap and undefined source bytes before mutation, and mark the destination
defined. Exact aliases still require initialized bytes; zero count touches
nothing. Accesses cannot span objects, padding, dead objects or image/stack
regions. Image reads retain their explicit zero initialization. Byte order is
per region; blits copy bytes without conversion.

Every allocation/load/store/blit consumes one normal instruction step, with
budget exhaustion winning before it executes. Byte counts are not step/time
budgets. Earlier Image writes survive later errors; temporary objects do not.
Default external/indirect-call refusals, depth limits, owned frames and folding
of ordered allocation effects remain unchanged. This is an opt-in diagnostic
model, not QBE invalid-program semantics or native memory safety/parity.

## Use and bounded regression coverage

For a parsed/validated function that allocates and initializes its own storage:

```zig
const result = try interpreter.evaluate(allocator, function, arguments,
    .{ .stack_memory = .{} });
```

Set `memory_image` alongside `stack_memory` to permit checked image/object byte
copies. The image must be kept alive and unmodified by the caller during the
evaluation. Stack configuration is immutable during execution. Internal lookup is
linear in live object count; this model makes no performance claim. Address
reservation includes padding/guards and is deliberately not reclaimed on return;
long-running programs can reach the cumulative cap with few live objects.

Tests reuse the unchanged independent 1,472-row Python memory oracle through
allocation and cross-region copying at eight offsets in both byte orders. They
also cover all allocation forms, loop freshness and recursive caller contents,
exact resource/step/depth boundaries, dead-address rejection, zero/overflow and
configuration boundaries, initialization and no-partial-mutation behavior,
retained Image writes, folding and exhaustive injected allocation cleanup.
Actual verification results are recorded in HANDOFF.md, not assumed here. The
existing native emitter, nine native harnesses and twelve generators are unchanged.

## Explicit module-global evaluation

Opt-in initialized globals use a separate owned synthetic model
(INTERPRETER-GLOBALS.md), including defined-data-only symbolic initializers
(INTERPRETER-DATA-RELOCATIONS.md). Defaults still refuse symbols; function/external
addresses remain unsupported. Image ownership and native linker/stack behavior
do not change.
