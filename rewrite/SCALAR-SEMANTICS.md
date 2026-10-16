# Scalar CFG, SSA and evaluation

This layer verifies and interprets **only the current scalar IR vocabulary**. It is not a completed compiler, full QBE verifier or optimizer. The separate experimental integer-only Linux AMD64 emitter is described in NATIVE-AMD64.md.

## Owned CFG snapshots

`cfg.Graph.init(allocator, &function)` first validates structure and types, then creates owned successor lists, CSR predecessor storage, entry reachability and reverse postorder. Entry is block zero. Both arms of a branch are CFG edges regardless of constant conditions; equal targets are deduplicated. An explicit DFS stack avoids recursion on deep graphs. Storage is linear in blocks plus edges.

Snapshots do not borrow function storage, and their exposed slices are read-only. They do not carry mutation epochs or enforce owner identity: rebuild after any relevant function change, and never mix IDs from different functions. `cfg.Dominators` computes immediate dominators iteratively using reverse-postorder ranks, not numeric block IDs. Entry and unreachable blocks have no public immediate dominator; unreachable blocks return false for all dominance queries, including self-dominance.

## Explicit scalar SSA verification

`ssa.validate(allocator, &function, &issue)` checks structure/types and every instruction/terminator operand:

- Parameters are available throughout the function.
- An instruction definition in the same block must precede its use strictly; self-use and forward use are rejected.
- A cross-block definition must dominate its reachable use. Phi results are available at block entry.
- Phi inputs cover every unique CFG predecessor exactly once; their definitions are checked at the end of that predecessor, not at the destination block. Entry-block phis are rejected because invocation has no incoming CFG edge.
- Unreachable blocks allow ordered local uses and parameters, but cross-block uses in unreachable blocks are conservatively rejected with `unreachable_cross_block_use`. This is an explicit subset policy, not a claim about all legal QBE dead-code cases.

`InvalidSSA` returns an issue containing the value, use block and a tagged site: instruction, terminator, phi or individual phi input. Structural and allocation errors remain distinct. Validation owns/frees scratch storage and never changes the function.

The frontend's `parse` API still checks syntax/structure, not dominance. Call scalar SSA validation before using its result in a pass that requires verified SSA. Current scalar phi nodes and edge-specific uses are checked; complete IL validation remains future work.

## Bounded reference evaluator

`interpreter.evaluate(allocator, &function, arguments, options)` always invokes scalar SSA validation, checks argument count/types, then executes into a separate invocation-owned frame. Each phi, ordinary instruction and terminator consumes one step; the default budget is 100,000 steps. Budget zero performs no execution. Exhaustion returns `StepLimitExceeded`, including for endless CFG loops. The execution budget does not bound parsing or analysis time.

Phi inputs are read from the chosen predecessor and committed simultaneously, with a separate invocation-owned scratch slice, so loop-carried swaps/cycles preserve old values.

Word/long arithmetic wraps at 32/64 bits. Shifts use a word count masked to five/six bits and distinguish logical from signed arithmetic right shift. Integer comparisons have explicit signed/unsigned predicates and operand widths, producing a word or long zero/one independently of operand width. Integer negation wraps, and byte/half/word extensions sign- or zero-extend explicitly selected low bits. Floating negation flips the sign bit without arithmetic conversion, preserving payload bits and signed zero. Copy preserves bit patterns; branch decisions test the low 32 bits of integer operands. Floating add/sub/mul use explicit f32/f64 width and strict host arithmetic, not target code generation. No target-specific NaN arithmetic, floating-environment, ABI or native-code parity is claimed. Copying an existing NaN payload preserves its bits; parsing payload spellings is still unsupported.

There are no memory operations, calls, recursion, globals or side-effect emulation in this evaluator. It is a semantic test tool for the implemented subset, not a replacement CLI or a path that delegates execution to the old compiler.

## Independent checks

Dominance tests compare with a separate vertex-removal/reachability oracle on 512 generated small graphs, plus explicit diamonds, loops, unreachable nodes and a deep chain. Integer differential tests use a committed fixture generated with Python arbitrary-precision arithmetic; `python3 tools/generate_integer_oracle.py --check` checks reproducibility. The separate `generate_scalar_oracle.py --check` fixture adds 832 masked-shift and signed/unsigned comparison cases, including both comparison result widths and decimal modulo/truncation boundaries. A third `generate_unary_oracle.py --check` fixture supplies 384 negation/extension cases; native tests call these operations with runtime integer arguments. Zig tests do not need Python to consume these fixtures. Allocation-failure injection covers analysis and execution ownership.
