# Zig-native backend rewrite

**Status: experimental scalar and bounded INTEGER/SSE/MEMORY-record Linux AMD64 compiler slice, plus scalar interpreter. Not a complete QBE backend.** This directory is a new implementation, not a wrapper around or a mechanical cleanup of the existing C-shaped port. Its parser accepts the documented scalar subset plus bounded nonempty record declarations with owned layout metadata; first-class aggregate values remain refused; bounded native MEMORY-record calls/returns ([AMD64-MEMORY-ABI.md](AMD64-MEMORY-ABI.md)) and integer-only size1..16 record calls/returns ([SMALL-INTEGER-ABI.md](SMALL-INTEGER-ABI.md)) are supported. The experimental driver emits Linux AMD64 integer and single/double scalar assembly. Most IL/ABI/target support, optimizations and full register allocation are still missing. An opt-in conservative integer constant folder is implemented, not a complete optimizer. Passing its tests does not establish QBE compatibility or replace the legacy backend.

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
- Bounded nonempty record declarations with owned checked layouts and earlier-record references; names live in a separate module-owned `record_names` pool, preserving scalar symbol IDs/assembly. The declaration layer does not itself classify target ABI uses ([RECORD-DECLARATIONS.md](RECORD-DECLARATIONS.md)).
- Independent modules owning separately allocated functions and numeric/zero-fill data objects; pointers survive module-table growth (DATA.md).
- Explicit scalar/record ABI descriptors retain nominal module type IDs and checked long pointer carriers in owned function/call metadata. The representation layer remains target-independent; bounded native INTEGER/SSE/MEMORY codegen is separate, while **all interpreter aggregate execution remains refused** ([AGGREGATE-ABI-REPRESENTATION.md](AGGREGATE-ABI-REPRESENTATION.md)).
- Function-owned typed value/block IDs and growable instruction storage.
- Explicit low-word operand projections normalize QBE long-to-word subtyping without changing source definitions or guessing reverse extension (LOW-WORD.md).
- Tagged scalar constants and operands, typed copy/phi, integer/floating arithmetic subset, integer bitwise/extension operations and negation, typed shifts, signed/unsigned integer comparisons and ordered/unordered floating comparisons, branch/jump/return and explicit program-termination (`hlt`) terminators.
- Source spans, typed diagnostics, allocation-free lexer and transactional scalar parser with forward block resolution.
- Typed long symbol-address operands with full-width executable AMD64 address materialization and explicit interpreter refusal (SYMBOL-ADDRESSES.md); bounded packed numeric/zero-fill data definitions are supported (DATA.md), with typed long symbolic initializers (DATA-RELOCATIONS.md) and owned b-group byte strings (DATA-STRINGS.md); exact all-zero objects use ELF BSS (DATA-BSS.md).
- Allocation-free scalar instruction-use iteration with copied fixed operands and explicitly borrowed call argument tails; production analyses share it while independent oracles remain separate (OPERANDS.md).
- Structural/type checks, owned CFG snapshots, dominators and explicit scalar SSA use/phi-edge validation.
- Owned block-boundary liveness snapshots with phi-edge uses, checked matrix limits and an independent path-search oracle.
- Owned, bounded scalar-home interference graphs, independently checked at program points; no machine-specific constraints in the graph.
- Bounded scalar interpreter with an explicit owned invocation stack for module-local direct calls, shared step/depth limits and independent integer/dominance oracle checks; no external function execution.
- Typed scalar loads and effect-only stores with long addresses, explicit access widths/extensions, native AMD64 lowering and opt-in owned simulated memory evaluation, with default refusal and no host dereferencing (see MEMORY.md and MEMORY-EVALUATION.md). Constant-length effect-only byte blits are implemented with compact native lowering and checked image copying (BLITS.md).
- Typed, per-signature Linux AMD64 scalar argument locations with independent GP/SSE banks and checked stack offsets; direct and typed indirect nonvariadic scalar/void-result calls, including known internal and caller-contract external targets (see CALLS.md).
- Typed native function-scoped `alloc4`/`alloc8`/`alloc16` with runtime page probing and moving outgoing-call reservations; opt-in bounded synthetic interpreter objects retain default allocation refusal (NATIVE-ALLOCATIONS.md and INTERPRETER-ALLOCATIONS.md).
- Bounded native fixed-frame reservation touches each page before descending farther, with protected-stack mutation controls (FRAME-PROBES.md).
- Experimental stack-homed Linux AMD64 base-scalar emitter and driver, tested by assembling/linking/executing from C; opt-in deterministic interference-colored stack-home reuse and a limited five-callee-saved-register home mode.
- Explicit signed word/long ↔ single/double numeric conversions with checked evaluator domains and native SSE lowering (SIGNED-CONVERSIONS.md); unsigned word/long conversions now extend the same typed path (UNSIGNED-CONVERSIONS.md); precision narrowing remains unsupported.
- Opt-in SSA-validated, source-order integer/bit-pattern constant folding with preserved arithmetic faults.
- Explicit errors for invalid builders; allocation-failure and ownership tests.
- Correct low-32-bit constant branch semantics, including long operands.

There are no compile-wide mutable globals, pointer-packed references, C-layout requirements, or calls into the existing backend in this core. This is a design direction, not a claim that all future compiler code can avoid low-level operations.

See [DATA-BSS.md](DATA-BSS.md) for exact zero-data lowering, [DATA-STRINGS.md](DATA-STRINGS.md) for owned byte strings, [DATA-RELOCATIONS.md](DATA-RELOCATIONS.md) for long symbolic pointer-table initializers, [DATA.md](DATA.md) for owned numeric/zero-fill globals, [SYMBOL-ADDRESSES.md](SYMBOL-ADDRESSES.md) for typed symbol-address operands, [INTERPRETER-ALLOCATIONS.md](INTERPRETER-ALLOCATIONS.md) for opt-in synthetic stack objects, [NATIVE-ALLOCATIONS.md](NATIVE-ALLOCATIONS.md) for native allocation and evaluator boundaries, [FRAME-PROBES.md](FRAME-PROBES.md) for bounded native fixed-frame probes, [LOW-WORD.md](LOW-WORD.md) for explicit scalar subtyping, [UNSIGNED-CONVERSIONS.md](UNSIGNED-CONVERSIONS.md) for unsigned numeric conversions and boundaries, [SIGNED-CONVERSIONS.md](SIGNED-CONVERSIONS.md) for defined signed numeric conversions, [BLITS.md](BLITS.md) for constant-length copies, [MEMORY-EVALUATION.md](MEMORY-EVALUATION.md) for bounded synthetic memory images, [MEMORY.md](MEMORY.md) for scalar memory/access safety boundaries, [INDIRECT-CALLS.md](INDIRECT-CALLS.md) for native callback/address contracts, [MODULE-EVALUATION.md](MODULE-EVALUATION.md) for bounded module-local interpretation, [CALLS.md](CALLS.md) for limited direct native calls and the interpreter boundary, [ABI-AMD64.md](ABI-AMD64.md) for scalar argument classification, [HALT.md](HALT.md) for explicit termination, [PRESERVED-HOMES.md](PRESERVED-HOMES.md) for limited register homes, [STACK-HOMES.md](STACK-HOMES.md) for optional layout reuse, [INTERFERENCE.md](INTERFERENCE.md) for conservative graph contracts, [LIVENESS.md](LIVENESS.md) for analysis boundaries and resource limits, [OPTIMIZE.md](OPTIMIZE.md) for the conservative opt-in pass, [NATIVE-AMD64.md](NATIVE-AMD64.md) for the native slice, [SCALAR-SEMANTICS.md](SCALAR-SEMANTICS.md) for analysis/evaluation contracts, [FRONTEND.md](FRONTEND.md) for the exact supported subset and limitations, [DESIGN.md](DESIGN.md) for ownership and implementation milestones and [HANDOFF.md](HANDOFF.md) for the current verification record.

Checked long scalar symbol+offset operands and their deliberately bounded
RIP-relative executable contract are described in SYMBOL-OFFSETS.md.

Opt-in interpreter-owned numeric/zero/string module globals are described in
INTERPRETER-GLOBALS.md. Defaults still refuse symbol resolution; the separate
synthetic model now accepts defined-data-only symbolic initializers
(INTERPRETER-DATA-RELOCATIONS.md), but not function/extern address lookup or host
calls.

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
(VARIADIC-FUNCTIONS.md); bounded opt-in synthetic consumers are separate (INTERPRETER-VAARG.md). Defaults still refuse vaarg/vastart; explicit root-only synthetic initialization
is separate (INTERPRETER-VASTART.md). Internal variadic calls remain refused by default; separate opt-in scalar
dispatch is described in INTERPRETER-VARIADIC-CALLS.md.

Native scalar variadic definitions and effect-only vastart now have a separate
frame-owned save region and checked named signatures (VARIADIC-FUNCTIONS.md).
Internal interpreter variadic calls remain explicit refusals by default
(INTERPRETER-VARIADIC-CALLS.md); root-only synthetic
vastart is separately opt-in (INTERPRETER-VASTART.md); opt-in manually prepared scalar descriptor consumers are separate (INTERPRETER-VAARG.md).

Nonvariadic scalar environment calls now have a distinct hidden long operand/
parameter and Linux AMD64 RAX mapping, without shifting ordinary ABI arguments
(ENVIRONMENT-CALLS.md). Root/module interpreter mapping remains synthetic and
bounded; environment+varargs remains unsupported. Native nonvariadic record ENV/indirect calls are supported separately (AGGREGATE-CALL-TARGETS.md); aggregate interpretation remains refused.

Bounded printable-ASCII quoted globals (excluding ELF `@` syntax) decode to owned canonical symbol names
across definitions/calls/scalar operands/data relocations (QUOTED-GLOBALS.md).
Native formatting escapes non-bare names while preserving existing bare output
and the private-label namespace; no host lookup or full identifier/target parity.

Bounded zero-fill `common data` tentative ELF definitions use explicit `.comm`
size/alignment and independent export flags (DATA-COMMON.md). Only z-groups
are accepted; same-module duplicates remain errors, while cross-object linker
coalescing/strong override is native ELF behavior, not interpreter host linking.

Checked target planning is available separately through `abi_amd64_plan`; see
[AMD64-ABI-PLANS.md](AMD64-ABI-PLANS.md). The emitter constructs fresh emission-scoped plans for bounded direct INTEGER/SSE/MEMORY-record
arguments/results ([AMD64-MEMORY-ABI.md](AMD64-MEMORY-ABI.md)); externally supplied
or stale plans are never emitter inputs. Aggregate interpretation remains refused.

Small SSE/mixed record calls and returns are bounded separately in [SMALL-SSE-ABI.md](SMALL-SSE-ABI.md), with offset-sensitive class merging and whole-argument rollback across both register banks.

Bounded regular align16 record calls/results omit padding-only NO_CLASS lanes
without shrinking declared storage ([ALIGN16-ABI.md](ALIGN16-ABI.md)). This follows
official SysV/C semantics, not pinned-QBE padding-lane oracle parity;
aggregate interpreter refusals remain unchanged; bounded native aggregate variadics are supported separately (AGGREGATE-VARIADIC.md). Native nonvariadic ENV/indirect record calls are now supported (AGGREGATE-CALL-TARGETS.md).

## Native record call targets

Nonvariadic indirect and scalar-long ENV aggregate definitions/calls/results
now use the existing typed Linux AMD64 SysV record plans, with late target
parking and ENV-last marshalling. Bounded native aggregate variadics are supported separately (AGGREGATE-VARIADIC.md); aggregate interpreter
execution remains refused. See [AGGREGATE-CALL-TARGETS.md](AGGREGATE-CALL-TARGETS.md)
for caller contracts, resource/output boundaries and independent oracles.

Native marked record calls and record-bearing variadic definitions/vastart use
checked raw stack ends and the176-byte save area (AGGREGATE-VARIADIC.md).
IL vaarg remains scalar-only; ENV+varargs and aggregate interpretation stay refused.
