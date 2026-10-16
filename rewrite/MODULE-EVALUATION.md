# Bounded module-local call evaluation

`interpreter.evaluateModule(allocator, module, entry: FunctionId, arguments, options)` interprets the implemented scalar vocabulary and **module-local direct calls**. It is not native execution, arbitrary host invocation, full IL emulation or an external-function resolver. Entry IDs belong to the supplied module. An out-of-range entry returns `InvalidFunction`.

## Validation and ownership

The exported `module_validation.validate` checks every function's symbol ID, duplicate function identity, scalar structure/SSA and then every known direct-call signature. It validates all bodies before traversing known callee parameter IDs. External target IDs must exist in the module symbol pool, but an external target need not have a definition. Known calls require exact scalar result type, argument count and argument types, even when unreachable. The validator does not impose AMD64 assembly-symbol spelling; the AMD64 emitter adds its own spelling checks after shared validation. This removes duplicate signature-verifier logic without making scalar semantics target-specific.

Module evaluation validates the module once before executing, not repeatedly on each recursive invocation. The standalone `evaluate(function, ...)` still validates its function and returns `UnsupportedCall` for a reached call, because it has no module resolver. Both entry points use the same scalar execution engine. Neither mutates IR, module symbols or input arguments. The caller must keep the module/functions alive and must not mutate them concurrently with execution.

Each active invocation owns separate optional scalar-value storage and parallel-phi scratch. A growable owned frame-handle array stores its current block, predecessor, next instruction and caller return destination. Frame-array relocation does not move the separately allocated value/phi storage; the runtime never retains a handle-array pointer across growth. Arguments are copied into the callee's value frame before temporary argument storage is freed. A return commits only its scalar result into the suspended caller's destination, then frees the completed invocation. All active frames are freed on success or any typed/allocation error.

Invocation dispatch, return and recursive control flow are **iterative**. IL recursion does not recurse through the host Zig stack. Direct/self/mutual calls and forward definitions use module symbol IDs, not host addresses. No external lookup falls back to libc, the old compiler, a process or the network.

## Explicit limits and errors

`Options.max_steps` defaults to **100,000**, shared by the complete evaluation across every frame. Each phi, ordinary instruction (including call) and terminator consumes one step. Frame creation/argument copying/validation do not consume additional IL steps. Returning from a callee does not reset the budget. A reached call consumes its step before target lookup or depth checks, so an exhausted budget wins at that point. Preceding arithmetic faults retain their ordinary precedence.

`Options.max_call_depth` defaults to **64**, counting the entry invocation. Zero returns `CallDepthLimitExceeded` before any execution frame is allocated; one permits a call-free entry but not a nested invocation. Pushing a known internal callee at the cap returns `CallDepthLimitExceeded`. This is a bound on simultaneous invocation count, not total allocated bytes, parsing/validation time or native recursion. Each frame's memory depends on its function's value/phi count, and callers choosing larger limits accept that cost. The explicit heap stack needs no unsafe host-recursion workaround or fixed arbitrary hard cap.

A reached undefined external target returns `UnsupportedExternalCall`; a valid call-free path through a function containing external calls still evaluates. External resolution precedes the internal-depth check; there is no frame to push for an undefined target. A reached `hlt` in any invocation returns `Halted` for the entire evaluation. Integer callee faults return `DivisionByZero`/`IntegerOverflow`. Root argument errors remain `ArgumentCountMismatch`/`ArgumentTypeMismatch`; a void root returns `null`. Void-result call instructions remain unsupported by the frontend/IR call slice.

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
