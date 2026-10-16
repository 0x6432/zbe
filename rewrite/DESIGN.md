# Design and implementation plan

## Ownership and invariants

`Module` owns a symbol pool and separately allocated `Function` objects. Each function owns its parameters, values, blocks and each block's instruction array. Every owner accepts an allocator and has a matching `deinit`. Errors propagate to callers rather than exiting the process.

Symbol strings and module-owned function pointers remain stable until owner destruction. Array views and pointers into function storage can be invalidated by growth; retain IDs instead. `ValueId` and `BlockId` are distinct types, but **owner scope is a caller invariant**: IDs from two functions can have identical ordinals. Symbol IDs belong to their pool and function IDs to their module. These types do not encode owner identity at compile time.

Builders validate before publishing and reserve all necessary capacity before appending linked records. Failed allocation can retain enlarged capacity. A failed function addition can retain a newly interned symbol, but never publishes an incomplete function; the module still owns that symbol. This is logical-record atomicity, not byte-for-byte rollback of allocator state.

Structural validation checks reference bounds, bidirectional definition links, operand/result types, branch targets, returns, and terminator presence. It is **not** dominance analysis, use-before-definition checking, phi-edge validation, reachability analysis or a complete SSA verifier. Public storage can be edited by future passes; those passes must maintain invariants and run validation at their boundaries.

## Semantic and compatibility boundaries

The clean core uses tagged unions, explicit types and mathematical bit-pattern semantics. In particular, long branch conditions test their low 32 bits. It does not intentionally reproduce the known upstream constant-jump bug.

The legacy compiler's `-O0`/`QBE_COMPAT` behavior, C diagnostics, reference patches and Python oracle remain unchanged. A future compatibility frontend/CLI must explicitly define which historical quirks it preserves; do not silently weaken an oracle to hide a mismatch. External C ABI adapters, when implemented, may legitimately use extern layouts and numeric encodings. Those representations must not dictate the entire internal IR.

This rewrite intentionally does not carry forward the old port's internal-global/shared-instruction-buffer/extern-layout preservation constraints. Those constraints still apply to changes to the old implementation.

## Milestones

1. **Foundation (current):** ownership, symbols, minimal typed IR/builders, structural validation and allocation-failure tests.
2. **Frontend:** source spans, typed diagnostics, lexer/parser and complete IL representation, including globals, memory, calls and phi nodes. Test malformed and valid input without delegating to the old parser.
3. **Verified semantics:** CFG/SSA construction and dominance/phi validation; a bounded semantic interpreter and differential tests. Preserve float bits and machine integer widths explicitly.
4. **First vertical slice:** simple native AMD64 end-to-end compile, assemble and execute path, ABI handling and behavioral regressions. No parity claim from a small subset.
5. **Backend completeness:** analyses, optimizations, instruction selection, liveness, register allocation, spills and full AMD64 instruction support, with pass-level invariants.
6. **Targets and interfaces:** AArch64/RV64, platform/object/ABI variants, command line/library entry points and optional C boundary.
7. **Acceptance:** existing compatibility/behavior corpus, all-target assembly/debug comparisons where promised, diagnostics, fuzzing, mutation tests, bootstrap and performance checks. Audit remaining unsafe operations and document justified low-level boundaries.

Do not replace the current backend or publish a release merely because the foundation tests pass. Each stage needs its own tested implementation and honest coverage record.
