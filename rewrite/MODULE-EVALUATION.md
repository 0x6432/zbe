# Bounded module-local call evaluation

`interpreter.evaluateModule(allocator, module, entry: FunctionId, arguments, options)` interprets the implemented scalar vocabulary and **module-local direct calls**. It is not native execution, arbitrary host invocation, full IL emulation or an external-function resolver. Entry IDs belong to the supplied module. An out-of-range entry returns `InvalidFunction`.

## Validation and ownership

The exported `module_validation.validate` checks every function's symbol ID, duplicate function identity, scalar structure/SSA and then every known direct-call signature. It validates all bodies before traversing known callee parameter IDs. External target IDs must exist in the module symbol pool, but an external target need not have a definition. Known calls require exact scalar result type, argument count and argument types, even when unreachable. The validator does not impose AMD64 assembly-symbol spelling; the AMD64 emitter adds its own spelling checks after shared validation. This removes duplicate signature-verifier logic without making scalar semantics target-specific.

Module evaluation validates the module once before executing, not repeatedly on each recursive invocation. The standalone `evaluate(function, ...)` still validates its function and returns `UnsupportedCall` for a reached call, because it has no module resolver. Both entry points use the same scalar execution engine. Neither mutates IR, module symbols or input arguments. The caller must keep the module/functions alive and must not mutate them concurrently with execution.

Each active invocation owns separate optional scalar-value storage and parallel-phi scratch. A growable owned frame-handle array stores its current block, predecessor, next instruction and caller return destination. Frame-array relocation does not move the separately allocated value/phi storage; the runtime never retains a handle-array pointer across growth. Arguments are copied into the callee's value frame before temporary argument storage is freed. A scalar return commits its result into the suspended caller's destination; a void return resumes the caller without any value write. Completed invocations are freed in either case. All active frames are freed on success or any typed/allocation error.

Invocation dispatch, return and recursive control flow are **iterative**. IL recursion does not recurse through the host Zig stack. Direct/self/mutual calls and forward definitions use module symbol IDs, not host addresses. Indirect address targets are verified as long SSA uses but refused at execution (see INDIRECT-CALLS.md). No external lookup falls back to libc, the old compiler, a process or the network.

## Explicit limits and errors

`Options.max_steps` defaults to **100,000**, shared by the complete evaluation across every frame. Each phi, ordinary instruction (including call) and terminator consumes one step. Frame creation/argument copying/validation do not consume additional IL steps. Returning from a callee does not reset the budget. A reached call consumes its step before target lookup or depth checks, so an exhausted budget wins at that point. Preceding arithmetic faults retain their ordinary precedence.

`Options.max_call_depth` defaults to **64**, counting the entry invocation. Zero returns `CallDepthLimitExceeded` before any execution frame is allocated; one permits a call-free entry but not a nested invocation. Pushing a known internal callee at the cap returns `CallDepthLimitExceeded`. This is a bound on simultaneous invocation count, not total allocated bytes, parsing/validation time or native recursion. Each frame's memory depends on its function's value/phi count, and callers choosing larger limits accept that cost. The explicit heap stack needs no unsafe host-recursion workaround or fixed arbitrary hard cap.

A reached address target returns `UnsupportedIndirectCall` without dereferencing or invoking it. A reached undefined symbolic external target returns `UnsupportedExternalCall`; a valid call-free path through a function containing external calls still evaluates. External resolution precedes the internal-depth check; there is no frame to push for an undefined target. A reached `hlt` in any invocation returns `Halted` for the entire evaluation. Integer callee faults return `DivisionByZero`/`IntegerOverflow`. Root argument errors remain `ArgumentCountMismatch`/`ArgumentTypeMismatch`; a void root returns `null`. Void-result calls now use the same bounded invocation dispatch without fabricated result values; known result presence is checked by module validation (see CALLS.md).

The standalone evaluator also honors the entry-frame limit, but cannot dispatch calls. Native programs do **not** inherit either evaluator limit: their stack, arithmetic faults and halt instructions retain the native behavior documented in CALLS.md and NATIVE-AMD64.md.

## Bounded verification

Seven added tests cover:

- exact shared step budgets over two calls, root-inclusive depth limits, root argument errors and invalid entry IDs;
- depth 64 boundary and a 1,001-frame recursive sum with repeated handle-array growth, independently expected as 500,500;
- mutual/forward recursion with independent parity expectations;
- all four raw scalar classes, NaN payloads, nested invocation phi storage and distinct parallel swaps in a suspended caller loop;
- external calls not executed, call-free paths, callee halt/arithmetic faults and void-root returns;
- target-independent symbol spelling, duplicate/invalid symbol IDs, invalid later bodies and known-signature mismatch rejection;
- exhaustive allocation-failure cleanup through parsing, nested frames, argument copies, handle growth, phi scratch and early depth/step exits.

The existing standalone scalar/interpreter/oracle tests and complete native regression matrix remain in force. Deep bounded recursion and these fixtures are not proof of complete QBE semantics, total-process resource limits or external ABI execution in the interpreter.

## Memory boundary

The IR/native compiler now supports scalar loads/stores (MEMORY.md). An optional caller-owned `Options.memory_image` now supplies a bounded synthetic byte image shared by every internal frame (MEMORY-EVALUATION.md). Without it, a reached memory instruction consumes its step then returns `UnsupportedMemory`, propagating through internal calls and freeing all active frames. Neither mode dereferences a numeric host address. Step exhaustion before the instruction wins; memory-free paths remain evaluable. Completed writes persist after later errors; only individual failing stores are mutation-free.


Reached `alloc4`/`alloc8`/`alloc16` consume the ordinary step then return `UnsupportedAllocation` by default, including in child calls and with a supplied Image. Opt-in `Options.stack_memory` enables separate evaluator-owned synthetic objects, scoped to each invocation and shared across internal calls (INTERPRETER-ALLOCATIONS.md). Returning releases only that frame's objects; all remaining objects clean up on error. Earlier Image writes persist. No host-pointer fallback or implicit Image resizing is introduced (NATIVE-ALLOCATIONS.md).


Scalar symbol-address operands are now accepted by the IR/frontend/native slice,
but by default resolving one in the interpreter returns `UnsupportedSymbolAddress` without
lookup, host-pointer conversion or synthetic address invention. Safe paths and
ordinary step/error precedence remain intact; Image writes before a later symbol
refusal persist and owned frames/objects clean up (SYMBOL-ADDRESSES.md).

## Explicit module-global evaluation

Opt-in initialized globals use a separate owned synthetic model
(INTERPRETER-GLOBALS.md), including defined-data-only symbolic initializers
(INTERPRETER-DATA-RELOCATIONS.md). Defaults still refuse symbols; function/external
addresses remain unsupported. Image ownership and native linker/stack behavior
do not change.

Typed sb/ub/sh/uh scalar ABI annotations retain word SSA classes and unspecified
upper bits, with explicit extension instructions and exact internal signature
checks (SUBWORD-ABI.md). This does not add aggregates, varargs or host invocation.

External/indirect variadic scalar call sites now have a checked named-argument
prefix marker and final AMD64 AL setup (VARIADIC-CALLS.md). Variadic function
bodies and vastart are supported separately (VARIADIC-FUNCTIONS.md); interpreter
host calls remain unsupported. C
default promotions are explicit caller responsibilities, not inserted conversions.

Caller-supplied native scalar vaarg consumers are a separate bounded slice
(VAARG-CONSUMERS.md); their caller-supplied descriptor model is reused by native definitions/vastart
(VARIADIC-FUNCTIONS.md); interpreter descriptor emulation is not implemented. Reached evaluation explicitly refuses the operation.

Native scalar variadic definitions and effect-only vastart now have a separate
frame-owned save region and checked named signatures (VARIADIC-FUNCTIONS.md).
Interpreter variadic calls/operations remain explicit refusals.
