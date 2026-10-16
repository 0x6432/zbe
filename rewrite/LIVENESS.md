# Owned scalar liveness

`liveness.Snapshot.init(allocator, function, options)` validates scalar SSA and returns an independently owned block-boundary analysis. Destroy it with `deinit`; it can outlive the input function/module. It is immutable by convention, not a frozen IR view. Rebuild after any IR mutation. Value/block IDs remain function-scoped caller invariants; queries return `null` for out-of-range ordinals, but cannot detect an in-range ID from another function.

## Boundary conventions

- SSA validation rejects every CFG edge targeting entry, including unreachable predecessors. Parameters are therefore defined once, not recreated on a loop backedge.
- `live_in` is before block-entry definitions. Parameters are definitions at the entry block; phi results are definitions at their own block entry. Neither is live-in to its defining block merely because it is used later there.
- Ordinary instruction operands and branch/return operands are uses. Each instruction result is a definition. Constants do not require a value bit.
- Phi operands are uses on the corresponding predecessor edge, not ordinary uses at the successor entry. A predecessor's `live_out` includes only its own phi inputs, plus the successor's `live_in` values. Parallel phis are not sequential assignments.
- `live_out` is the union across actual successor edges, not a separate per-edge result. Dead instruction operands still count: this analysis does not eliminate instructions.
- Unreachable blocks are analyzed on their actual edges too; no artificial entry edges are added. The existing SSA validator's conservative unreachable-use policy still applies.

The solver starts with empty sets and iterates backward to a fixed point, visiting reachable blocks in reverse reverse-postorder and unreachable blocks in reverse numeric order. Its equations are `out[b] = union(in[s] + phi_inputs[b -> s])` and `in[b] = uses[b] + (out[b] - defs[b])`.

## Ownership and resource limits

Each row uses an allocator-owned standard-library dynamic bitset. Construction cleans up partial rows and analysis scratch on every error. Only live-in/out rows survive construction; no IR/CFG pointers are retained.

The representation uses O(blocks × values / machine-word-bits) mask storage, not a linear-space liveness algorithm. The default `max_matrix_bytes` is 64 MiB. A checked conservative estimate covers four row matrices, two scratch bitsets, row descriptors and mask headers, and returns `LivenessTooLarge` before constructing them if the cap is exceeded. This is **not** a cap on allocator overhead, separate SSA/CFG scratch, total process memory or solver execution time. The snapshot itself exposes block boundaries, not instruction-level queries. A separate scalar-home interference analysis consumes it (see INTERFERENCE.md); the snapshot does not assign locations or insert spills. Optional stack/register-home consumers are described in STACK-HOMES.md and PRESERVED-HOMES.md.

## Verification

Direct tests check diamond edge precision, loop-carried phi swaps, typed scalar operations, unreachable blocks, empty value sets, bounds, memory limits, snapshot lifetime and exhaustive allocation-failure cleanup. A separate per-value path-search oracle asks whether a use is reachable before a definition, checking phi operands on edges without using the production bitset equations. All block/value queries are compared on representative fixtures, 64 generated cyclic CFGs and the 32-function mixed-program corpus. The normal and constant-folded native regression suites remain unchanged.
