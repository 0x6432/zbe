# Direct base-scalar calls

This is a deliberately limited native Linux SysV AMD64 call slice, not full QBE call/ABI support. Accepted form:

```text
%result =w|l|s|d call $direct_symbol(w|l|s|d operand, ...)
```

The example's ellipsis describes repetition, **not** an accepted variadic marker. Empty argument lists are supported. Every call has a scalar result, including calls whose result is unused. Void-result calls, indirect calls, environment parameters, aggregates, ABI-extension types and variadic calls remain explicitly unsupported.

## Owned representation and validation

`Instruction.call` contains a result `ValueId`, module-pool callee symbol and a function-owned slice of typed arguments. `Function.defineCall` checks every argument against its declared base scalar type, reserves instruction capacity and duplicates the argument slice before publishing the result definition/instruction. Failed type checks or allocations leave a pending result retryable; capacity growth may remain. `Function.deinit` frees argument slices. Public IR mutation must preserve this ownership contract; never replace an owned argument slice with borrowed storage.

Scalar SSA validation checks each argument at the instruction's use site, including local ordering and cross-block dominance. Liveness and interference include every argument use. Calls remain effectful and unknown to integer folding, even with constant arguments or unused results; argument storage is never lost by folding a call into a copy.

Native emission first validates every module body before traversing any known callee's parameter IDs. Every call target must be a valid supported assembly symbol. A module-local target must match the result type, argument count and every argument's exact base scalar type; mismatch returns `CallSignatureMismatch`. Forward and recursive definitions are supported. Unknown external function signatures cannot be verified from this IR: their nonvariadic scalar SysV signature is a **caller contract**, not a linker/type-checking guarantee. Parsing alone does not perform module-level call-signature validation.

## Native argument and frame lowering

Incoming and outgoing arguments use the same typed `abi_amd64.ArgumentCursor`. GP and SSE banks exhaust independently (six/eight registers); overflow arguments share eight-byte stack slots in declaration order. Word/single moves use their low four bytes, with the slot's unused bytes unspecified. Integer results arrive in RAX and floating results in XMM0; result bits are saved to the assigned home.

All current persistent homes are stack locations or saved/restored RBX/R12–R15. They survive a conforming SysV call, so this slice needs no new caller-saved-home spill machinery. Argument marshalling loads raw bits through RAX, not through already populated argument registers. All arguments are marshalled before writing the result home; dead argument/result home reuse remains safe. Future volatile-register homes would require explicit call-clobber constraints, not reuse of this assumption.

The frame reserves the maximum outgoing stack area across calls once. It sits at the bottom of the aligned frame, below ordinary homes, parallel-phi scratch and saved original registers. RSP remains 16-byte aligned immediately before each call. Outgoing storage participates in the existing 64 KiB cap; overflow fails without returning partial assembly. This is not dynamic stack allocation, probing, tail calls, unwinding or a full frame-layout implementation.

Native recursion follows ordinary process stack limits. Only regression inputs/timeouts bound test recursion; emitted programs do not inherit an interpreter step/depth guard.

## Evaluator boundary

The standalone function evaluator has no module resolver and never invokes arbitrary host functions. A **reached** call consumes one instruction step and returns `UnsupportedCall`. An unreachable call does not prevent evaluation of a call-free path. Budget exhaustion before the call still wins; preceding arithmetic faults retain precedence. The separate `evaluateModule` entry point now interprets module-local calls using an explicit owned frame stack and shared step/depth limits; undefined externals return `UnsupportedExternalCall`. See MODULE-EVALUATION.md. Neither API delegates to native execution.

## Bounded verification

Unit tests cover owned argument copies, failed-allocation retry, type errors, local/SSA dominance errors, unsupported forms, invalid symbols, forward known-signature mismatches, malformed later definitions, effect/folding and evaluator budget boundaries, frame-cap accounting, disjoint frame regions, and exhaustive allocation-failure cleanup through parsing/analysis/folding/all three home strategies. Independent liveness and interference oracles include call-containing loop fixtures.

`python3 tools/native_call_check.py` assembles and executes **466 native call/ABI/effect checks** plus **six signature rejection/output-preservation checks** per compiler-option combination:

- 128 signatures × three distinct value sets, using both bank-overflow orders, empty/small/large signatures, all scalar classes/results and two successive external calls;
- internal factorial and mutually recursive forward definitions;
- raw floating payloads, signed zero, infinities and subnormals through argument/return moves;
- live values of all four scalar types across an assembly helper explicitly clobbering all SysV volatile GP/SSE registers;
- a full-width preserved-register adapter and a direct stack-alignment probe;
- loop phi scratch and outgoing mixed-bank stack slots in one frame;
- observable calls with discarded results, including under integer folding.

Expected arithmetic uses bounded exact integers, not generated assembly or production ABI classification. These are regressions for this subset, not exhaustive signature coverage, full ABI parity, QBE byte identity or permission to replace the legacy backend.
