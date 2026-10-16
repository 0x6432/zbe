# Owned scalar interference

`interference.Graph.init(allocator, function, options)` constructs a symmetric, self-edge-free graph over the function's scalar value IDs. It obtains validated liveness internally, then owns only packed adjacency masks. It retains no function, CFG or liveness pointers. Destroy with `deinit`; rebuild after mutation. The snapshot is immutable by convention. `interferes(a, b)` and `degree(value)` return `null` for out-of-range ordinals; function ownership of otherwise valid IDs remains the caller's responsibility.

## Definition and boundaries

This is a **target-independent, conservative scalar-home graph**, not a machine register allocator:

- Each ordinary result interferes with other values live immediately after its definition, even if that result is dead. A still-emitted dead definition must not clobber a live home.
- Parameters are a simultaneous entry-definition bundle. All distinct parameters interfere, including unused ones; each also interferes with values live after the bundle.
- Each block's phi results are another simultaneous bundle. All distinct results interfere, including dead ones, and each interferes with other values live after the bundle. All phi definitions are removed together before considering earlier definitions. Incoming phi operands belong to predecessor edges, not the destination's ordinary instruction sequence.
- Constants have no graph nodes. Values in different blocks can share a home when their lifetimes permit it. A result may share a dying source's home. No special copy-coalescing exclusion is applied to a source that remains live.
- All validated blocks, including unreachable ones, are considered. Actual CFG edges and the SSA verifier's unreachable-use policy are unchanged.
- Edges are class-independent, including between integer and floating values. A future target allocator may filter for disjoint register banks. This graph does not model physical register aliases, instruction early clobbers, two-address constraints, fixed registers, call clobbers, ABI placement or spill scratch.

The implementation walks each block backward from owned block live-out sets, adds terminator uses, connects each definition to the current live set, removes the definition and adds its operands. It handles phi and parameter bundles explicitly. No IR is rewritten and generated assembly is unchanged. The graph itself performs no coloring or emitter work. A separate opt-in stack-home layout consumes it (see STACK-HOMES.md); physical register assignment and spill insertion remain unimplemented.

## Resource accounting

Adjacency uses O(values² / machine-word-bits) packed mask storage. A checked estimate covers the adjacency allocation plus the one live-set scratch mask, its header and descriptor. `max_graph_bytes` defaults to 64 MiB and produces `InterferenceTooLarge` before construction if exceeded. The empty graph uses zero mask storage. `max_liveness_matrix_bytes` separately controls the liveness constructor's matrix estimate (also 64 MiB by default); exceeding it returns `LivenessTooLarge`.

These caps are not a combined memory limit: graph construction also needs liveness/SSA/CFG storage, and allocator overhead and execution time are not capped. All owned graph, bitset and temporary analysis storage is cleaned up on failure. The quadratic graph is a bounded prototype, not a scalability claim.

## Independent checks

The test oracle scans **forward** from each definition's program point for a given value's use before redefinition, following CFG edges and phi incoming operands. It does not use production liveness sets or the backward instruction walk. Explicit parameter/phi bundle constraints complete its expected relation. Every pair and degree is compared on representative scalar/phi/float/unreachable fixtures, the 32-function mixed corpus and 32 generated cyclic CFGs with dead definitions.

Direct tests cover live-through values, dead-result clobbers, dying-source reuse, edge-separated phi operands, dead parallel phi results, cross-class parameters, snapshot lifetime, bounds, empty functions, separate/exact storage limits, checked overflow, invalid SSA, exhaustive allocation-failure cleanup, packed word boundaries and zero padding/self edges. This checks the stated relation, not the correctness of a future machine allocator.
