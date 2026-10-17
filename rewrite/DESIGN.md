# Design and implementation plan

## Ownership and invariants

`Module` owns a symbol pool and separately allocated `Function` and numeric/zero-fill `Data` objects (DATA.md); Data owns copied byte-string items (DATA-STRINGS.md). Each function owns its parameters, values, blocks and each block's instruction array. Every owner accepts an allocator and has a matching `deinit`. Errors propagate to callers rather than exiting the process.

Long-to-word subtyping is normalized as an explicit `Operand.low_word` projection retaining the original source ID/type; it does not allocate a value or permit implicit word-to-long extension (LOW-WORD.md).

Symbol strings and module-owned function pointers remain stable until owner destruction. Array views and pointers into function storage can be invalidated by growth; retain IDs instead. `ValueId` and `BlockId` are distinct types, but **owner scope is a caller invariant**: IDs from two functions can have identical ordinals. Symbol IDs belong to their pool and function IDs to their module. These types do not encode owner identity at compile time.

Builders validate before publishing and reserve all necessary capacity before appending linked records. Failed allocation can retain enlarged capacity. A failed function addition can retain a newly interned symbol, but never publishes an incomplete function; the module still owns that symbol. This is logical-record atomicity, not byte-for-byte rollback of allocator state.

Scalar instruction uses have a shared allocation-free value iterator (OPERANDS.md); production SSA/liveness/interference share it while independent test oracles retain separate tagged-union switches. Fixed operands are copied; call argument tails borrow their owner.

Structural validation checks reference bounds, bidirectional definition links, operand/result types, branch targets, returns, and terminator presence. `cfg` separately supplies reachability/dominators and `ssa.validate` checks scalar use ordering/dominance and exact phi-edge coverage. This is not a complete QBE IL/SSA verifier. Public IR storage can be edited by future passes; those passes must maintain invariants and rebuild analyses/run validation at their boundaries.

## Semantic and compatibility boundaries

The clean core uses tagged unions, explicit types and mathematical bit-pattern semantics. In particular, long branch conditions test their low 32 bits. It does not intentionally reproduce the known upstream constant-jump bug.

The legacy compiler's `-O0`/`QBE_COMPAT` behavior, C diagnostics, reference patches and Python oracle remain unchanged. A future compatibility frontend/CLI must explicitly define which historical quirks it preserves; do not silently weaken an oracle to hide a mismatch. External C ABI adapters, when implemented, may legitimately use extern layouts and numeric encodings. Those representations must not dictate the entire internal IR.

This rewrite intentionally does not carry forward the old port's internal-global/shared-instruction-buffer/extern-layout preservation constraints. Those constraints still apply to changes to the old implementation.

## Milestones

1. **Foundation (implemented):** ownership, symbols, minimal typed IR/builders, structural validation and allocation-failure tests.
2. **Frontend (in progress):** source spans, typed diagnostics and independent lexer/scalar parser are implemented. Expand to complete IL representation, including the remaining data language, complete memory operations and calls. Bounded packed numeric/zero-fill globals are implemented (DATA.md). Scalar loads/stores, constant-length blits and base-scalar calls are implemented. Typed phi nodes and forward references are implemented. Test malformed and valid input without delegating to the old parser. See FRONTEND.md for current boundaries.
3. **Verified semantics (scalar subset implemented):** owned CFG/dominator analysis, scalar SSA use validation and a bounded interpreter with independent integer/dominance oracle checks and module-local direct calls via an explicit owned invocation stack (see MODULE-EVALUATION.md). Phi/edge validation and simultaneous phi interpretation are implemented; opt-in owned bounded byte images now support scalar memory evaluation without host pointers (see MEMORY-EVALUATION.md); extend to complete language semantics. Preserve float bits and machine integer widths explicitly.
4. **First vertical slice (base-scalar prototype implemented):** independent Linux AMD64 end-to-end compile/assemble/execute path with independently classified GP/SSE register/stack arguments, floating arithmetic and parallel phi copies and bounded regressions. Conservative opt-in integer folding and stack-home reuse and limited callee-saved register homes; direct and typed long-address indirect nonvariadic scalar/void-result calls implemented (see CALLS.md), plus native scalar loads/stores (see MEMORY.md) and constant-length blits (BLITS.md); fixed-frame reservation is page-wise probed (FRAME-PROBES.md); native dynamic stack allocation is implemented (NATIVE-ALLOCATIONS.md), with opt-in bounded synthetic interpreter objects (INTERPRETER-ALLOCATIONS.md) and default refusal; no complete register allocator, full call ABI, remaining data language, remaining floating operations, full ABI or target parity; see NATIVE-AMD64.md.
5. **Backend completeness (in progress; conservative integer folding, owned block liveness, scalar interference and opt-in stack-home coloring and limited callee-saved homes implemented):** analyses, optimizations, instruction selection, liveness, register allocation, spills and full AMD64 instruction support, with pass-level invariants.
6. **Targets and interfaces:** AArch64/RV64, platform/object/ABI variants, command line/library entry points and optional C boundary.
7. **Acceptance:** existing compatibility/behavior corpus, all-target assembly/debug comparisons where promised, diagnostics, fuzzing, mutation tests, bootstrap and performance checks. Audit remaining unsafe operations and document justified low-level boundaries.

Do not replace the current backend or publish a release merely because the foundation tests pass. Each stage needs its own tested implementation and honest coverage record.

Long scalar addresses have distinct bare-symbol and checked i32 symbol-offset
operands, neither an SSA value nor a resolved numeric constant. Module ownership
and bounded executable relocation semantics are specified in SYMBOL-OFFSETS.md.

Opt-in interpreter-owned numeric/zero/string module globals are described in
INTERPRETER-GLOBALS.md. Defaults still refuse symbol resolution; the separate
synthetic model now accepts defined-data-only symbolic initializers
(INTERPRETER-DATA-RELOCATIONS.md), but not function/extern address lookup or host
calls.
