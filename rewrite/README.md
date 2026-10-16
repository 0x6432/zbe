# Zig-native backend rewrite

**Status: ownership/IR foundation and scalar frontend subset, not a working compiler.** This directory is a new implementation, not a wrapper around or a mechanical cleanup of the existing C-shaped port. Its parser accepts only the documented scalar subset. It has no executable, machine-code/assembly emitter, ABI lowering, optimizer, or register allocator yet. Passing its tests does not establish QBE compatibility or replace the legacy backend.

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

The independent build exports the `zbe_native` module without linking libc or importing the legacy implementation. Plain `zig build` compiles the test artifact; `zig build test` also executes it.

## Implemented

- Allocator-owned interned symbols, with stable string storage.
- Independent modules owning separately allocated functions; function pointers survive module-table growth.
- Function-owned typed value/block IDs and growable instruction storage.
- Tagged scalar constants and operands, typed copy, integer/floating arithmetic subset, integer bitwise operations, branch/jump/return terminators.
- Source spans, typed diagnostics, allocation-free lexer and transactional scalar parser with forward block resolution.
- Structural/type checks and definition backlinks, not full SSA verification.
- Explicit errors for invalid builders; allocation-failure and ownership tests.
- Correct low-32-bit constant branch semantics, including long operands.

There are no compile-wide mutable globals, pointer-packed references, C-layout requirements, or calls into the existing backend in this core. This is a design direction, not a claim that all future compiler code can avoid low-level operations.

See [FRONTEND.md](FRONTEND.md) for the exact supported subset and limitations, [DESIGN.md](DESIGN.md) for ownership and implementation milestones and [HANDOFF.md](HANDOFF.md) for the current verification record.
