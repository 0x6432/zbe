# Explicit program termination

The scalar IR has a payload-free `Terminator.halt`, spelled `hlt` in the frontend. It closes its block with no operands, no SSA uses and no outgoing CFG edges. It is valid in void or any scalar-result function because it does not return. Instructions or another terminator cannot follow it in the same block. Unlike a jump, it names no target; the invocation-entry restriction is unchanged.

QBE's IL documentation defines `hlt` as program termination with a target-dependent error. The evaluator returns typed `error.Halted` instead of terminating its host process. Reaching the terminator consumes one execution-budget step; budget exhaustion before that step still returns `StepLimitExceeded`. Ordinary instructions and their faults occur first. No fake return value or successor is invented.

The experimental Linux AMD64 emitter outputs `ud2`, matching the legacy AMD64 termination instruction. This is **not** the privileged hardware `hlt` instruction. Default native execution raises SIGILL. Arithmetic faults before the terminator remain arithmetic faults; the folder does not delete instructions or replace a preceding exceptional division with the later halt. No precise cross-target signal, signal-handler resumption or exception-unwinding behavior is promised.

A halting path is not a normal return, so callee-saved homes are not restored there; normal return paths still restore them as documented in PRESERVED-HOMES.md. The existing stack/home/phi/SSA rules otherwise apply. This adds no calls, memory, exception handlers or new target support.

## Verification

Tests cover all result classes, exact terminator arity/block closure, conditional return versus halt, step boundaries and arithmetic-fault ordering. Existing independent liveness/interference path-search checks include the halt fixture. Exhaustive allocation failure injection covers parsing, CFG, liveness, interference, home coloring, folding, evaluation and all three emitter home modes, including cleanup when evaluation returns `Halted`.

The native harness checks a normal conditional result of 42 and four separate subprocess cases: direct halt (SIGILL), conditional halt (SIGILL), zero division before halt (SIGFPE), and successful division followed by halt (SIGILL). Core dumps are disabled and subprocesses have finite timeouts. All eight flag combinations are checked in all three compiler build modes; floating/ABI/bit-pattern regressions and CLI output-preservation expectations remain unchanged. No legacy source or oracle is modified.
