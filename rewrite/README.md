# Zig-native backend rewrite

**Status: experimental base-scalar Linux AMD64 compiler slice, plus scalar frontend/verifier/interpreter. Not a complete QBE backend.** This directory is a new implementation, not a wrapper around or a mechanical cleanup of the existing C-shaped port. Its parser accepts only the documented scalar subset. The experimental driver emits Linux AMD64 integer and single/double scalar assembly. Most IL/ABI/target support, optimizations and full register allocation are still missing. An opt-in conservative integer constant folder is implemented, not a complete optimizer. Passing its tests does not establish QBE compatibility or replace the legacy backend.

Work lives on `rewrite/zig-native`. The existing compiler, build and regression suite remain the reference implementation and are unchanged by this foundation.

## Build and test

Use Zig **0.18.0-dev.35+5e754304d**, matching the repository's pinned toolchain:

```sh
cd rewrite
zig build test
zig build test -Doptimize=ReleaseSafe
zig build test -Doptimize=ReleaseFast
zig fmt --check build.zig src
```

The independent build exports `zbe_native` without linking libc or importing the legacy implementation. `zig build` installs the experimental `zig-out/bin/zbe-native` compiler and compiles the test artifact; `zig build test` executes unit tests. See NATIVE-AMD64.md for driver/native-harness commands and strict coverage limits.

## Implemented

- Allocator-owned interned symbols, with stable string storage.
- Independent modules owning separately allocated functions; function pointers survive module-table growth.
- Function-owned typed value/block IDs and growable instruction storage.
- Explicit low-word operand projections normalize QBE long-to-word subtyping without changing source definitions or guessing reverse extension (LOW-WORD.md).
- Tagged scalar constants and operands, typed copy/phi, integer/floating arithmetic subset, integer bitwise/extension operations and negation, typed shifts, signed/unsigned integer comparisons and ordered/unordered floating comparisons, branch/jump/return and explicit program-termination (`hlt`) terminators.
- Source spans, typed diagnostics, allocation-free lexer and transactional scalar parser with forward block resolution.
- Allocation-free scalar instruction-use iteration with copied fixed operands and explicitly borrowed call argument tails; production analyses share it while independent oracles remain separate (OPERANDS.md).
- Structural/type checks, owned CFG snapshots, dominators and explicit scalar SSA use/phi-edge validation.
- Owned block-boundary liveness snapshots with phi-edge uses, checked matrix limits and an independent path-search oracle.
- Owned, bounded scalar-home interference graphs, independently checked at program points; no machine-specific constraints in the graph.
- Bounded scalar interpreter with an explicit owned invocation stack for module-local direct calls, shared step/depth limits and independent integer/dominance oracle checks; no external function execution.
- Typed scalar loads and effect-only stores with long addresses, explicit access widths/extensions, native AMD64 lowering and opt-in owned simulated memory evaluation, with default refusal and no host dereferencing (see MEMORY.md and MEMORY-EVALUATION.md). Constant-length effect-only byte blits are implemented with compact native lowering and checked image copying (BLITS.md).
- Typed, per-signature Linux AMD64 scalar argument locations with independent GP/SSE banks and checked stack offsets; direct and typed indirect nonvariadic scalar/void-result calls, including known internal and caller-contract external targets (see CALLS.md).
- Experimental stack-homed Linux AMD64 base-scalar emitter and driver, tested by assembling/linking/executing from C; opt-in deterministic interference-colored stack-home reuse and a limited five-callee-saved-register home mode.
- Explicit signed word/long ↔ single/double numeric conversions with checked evaluator domains and native SSE lowering (SIGNED-CONVERSIONS.md); unsigned word/long conversions now extend the same typed path (UNSIGNED-CONVERSIONS.md); precision narrowing remains unsupported.
- Opt-in SSA-validated, source-order integer/bit-pattern constant folding with preserved arithmetic faults.
- Explicit errors for invalid builders; allocation-failure and ownership tests.
- Correct low-32-bit constant branch semantics, including long operands.

There are no compile-wide mutable globals, pointer-packed references, C-layout requirements, or calls into the existing backend in this core. This is a design direction, not a claim that all future compiler code can avoid low-level operations.

See [LOW-WORD.md](LOW-WORD.md) for explicit scalar subtyping, [UNSIGNED-CONVERSIONS.md](UNSIGNED-CONVERSIONS.md) for unsigned numeric conversions and boundaries, [SIGNED-CONVERSIONS.md](SIGNED-CONVERSIONS.md) for defined signed numeric conversions, [BLITS.md](BLITS.md) for constant-length copies, [MEMORY-EVALUATION.md](MEMORY-EVALUATION.md) for bounded synthetic memory images, [MEMORY.md](MEMORY.md) for scalar memory/access safety boundaries, [INDIRECT-CALLS.md](INDIRECT-CALLS.md) for native callback/address contracts, [MODULE-EVALUATION.md](MODULE-EVALUATION.md) for bounded module-local interpretation, [CALLS.md](CALLS.md) for limited direct native calls and the interpreter boundary, [ABI-AMD64.md](ABI-AMD64.md) for scalar argument classification, [HALT.md](HALT.md) for explicit termination, [PRESERVED-HOMES.md](PRESERVED-HOMES.md) for limited register homes, [STACK-HOMES.md](STACK-HOMES.md) for optional layout reuse, [INTERFERENCE.md](INTERFERENCE.md) for conservative graph contracts, [LIVENESS.md](LIVENESS.md) for analysis boundaries and resource limits, [OPTIMIZE.md](OPTIMIZE.md) for the conservative opt-in pass, [NATIVE-AMD64.md](NATIVE-AMD64.md) for the native slice, [SCALAR-SEMANTICS.md](SCALAR-SEMANTICS.md) for analysis/evaluation contracts, [FRONTEND.md](FRONTEND.md) for the exact supported subset and limitations, [DESIGN.md](DESIGN.md) for ownership and implementation milestones and [HANDOFF.md](HANDOFF.md) for the current verification record.
