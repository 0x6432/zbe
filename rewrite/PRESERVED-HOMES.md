# Optional callee-saved register homes

`amd64.emitWithOptions(..., .{ .callee_saved_homes = true })` and CLI `--callee-saved-homes` enable a deliberately limited physical home assignment for the Linux AMD64 scalar prototype. It uses the existing validated interference coloring, assigns the first five colors to **RBX, R12, R13, R14 and R15**, and leaves additional colors in shared eight-byte stack homes. The option implies coloring; also specifying `--reuse-stack-homes` is accepted and redundant. Default emission remains unique stack homes.

This is **not a complete QBE register allocator**. It uses no caller-saved homes or persistent SSE homes, has no register-class-aware preferences, live-range splitting, rematerialization, optimal spilling, copy coalescing or general machine-constraint solver. Floating values use their raw bits in GP homes; scalar floating computation still uses the existing SSE scratch path. Values beyond the five chosen colors stay on the stack rather than requiring new spill instructions in the IR.

## Safety boundaries

- Allocated home registers never alias the emitter's RAX/R10/RCX/RDX or XMM0/XMM1 scratch. Every operand is loaded into scratch before a result home is overwritten. This isolates the implemented division, shift, floating and comparison instruction constraints from home assignment.
- The graph remains class-independent and preserves dead writes and simultaneous parameter/phi bundles. All incoming parameters have distinct locations. Incoming GP/SSE/stack arguments are homed before ordinary scratch use.
- Before any home assignment, the prologue saves the **full 64-bit original contents** of each used callee-saved register. Every normal return restores them after preparing the integer/SSE return result. Registers not used for homes are not touched or saved. The existing frame-pointer save/restore is unchanged.
- Frame regions are disjoint: ordinary stack homes, then parallel phi scratch, then saved original registers. Incoming stack arguments remain at positive frame-pointer offsets. Space is rounded to 16 bytes and the existing 64 KiB cap includes all regions. No large-frame probing or unwind metadata is added.
- Every phi input is read to a separate scratch home before any phi result is committed, even when a source/destination uses a physical register or the same color. Register preservation is for normal returns; native arithmetic-fault behavior is unchanged.
- No calls exist in the supported IR subset. This option does not establish call lowering, aggregate/extended ABI support, varargs, exceptional unwinding or other targets.

Locations are a typed internal `Home` union of stack offset and a semantic preserved-register enum, not pointer tagging or numeric ABI fields. Per-function owned color storage is released after emission, including on error. The IR remains unmodified, and library errors return no partial assembly. Graph/liveness resource caps and quadratic-coloring limitations from STACK-HOMES.md still apply. Additional saved-register space means no runtime-speed or frame-size improvement is promised.

## Verification

Unit tests check width-aware word/long/raw-float home moves, saving only used registers, disjoint stack/scratch/save offsets, both branch returns, empty frames, frame overflow, redundant option identity and exhaustive allocation-failure cleanup across functions. A seven-phi rotation fixture forces all five preserved registers and additional stack homes even with integer folding.

The native harness calls that fixture both directly (expected sum 21) and through a separate GNU assembly SysV adapter. The adapter seeds all five preserved registers with distinct full-width patterns, calls generated code, checks all 64 bits and restores its own caller's registers. It aligns the stack for its call and disables executable-stack marking. The existing integer, floating, mixed-ABI, bit-pattern, parallel-phi, division-fault and CLI checks also run in all eight combinations of the three compiler flags, in every compiler build mode. All six flag permutations select identical assembly for a small fixture; duplicate flags are usage errors preserving output.

This establishes bounded native regressions for the implemented home scheme, not complete register allocation, full ABI conformance, performance or release readiness.

Before analysis or execution, every SSA-dependent consumer rejects CFG edges targeting the entry block with `EntryHasPredecessors`, as required by QBE. An invalid-entry regression checks all consumers and every CLI flag combination, including output creation/preservation. This prevents a once-invoked parameter home from being reused as if parameters were redefined on a loop backedge.
