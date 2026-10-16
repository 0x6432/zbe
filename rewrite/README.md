# Zig-native backend rewrite

**Status: experimental base-scalar Linux AMD64 compiler slice, plus scalar frontend/verifier/interpreter. Not a complete QBE backend.** This directory is a new implementation, not a wrapper around or a mechanical cleanup of the existing C-shaped port. Its parser accepts only the documented scalar subset. The experimental driver emits Linux AMD64 integer and single/double scalar assembly. Most IL/ABI/target support, optimization and register allocation are still missing. Passing its tests does not establish QBE compatibility or replace the legacy backend.

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
- Tagged scalar constants and operands, typed copy/phi, integer/floating arithmetic subset, integer bitwise/extension operations and negation, typed shifts and signed/unsigned comparisons, branch/jump/return terminators.
- Source spans, typed diagnostics, allocation-free lexer and transactional scalar parser with forward block resolution.
- Structural/type checks, owned CFG snapshots, dominators and explicit scalar SSA use/phi-edge validation.
- Bounded scalar interpreter and independent integer/dominance oracle checks.
- Experimental stack-homed Linux AMD64 base-scalar emitter and driver, tested by assembling/linking/executing from C.
- Explicit errors for invalid builders; allocation-failure and ownership tests.
- Correct low-32-bit constant branch semantics, including long operands.

There are no compile-wide mutable globals, pointer-packed references, C-layout requirements, or calls into the existing backend in this core. This is a design direction, not a claim that all future compiler code can avoid low-level operations.

See [NATIVE-AMD64.md](NATIVE-AMD64.md) for the native slice, [SCALAR-SEMANTICS.md](SCALAR-SEMANTICS.md) for analysis/evaluation contracts, [FRONTEND.md](FRONTEND.md) for the exact supported subset and limitations, [DESIGN.md](DESIGN.md) for ownership and implementation milestones and [HANDOFF.md](HANDOFF.md) for the current verification record.
