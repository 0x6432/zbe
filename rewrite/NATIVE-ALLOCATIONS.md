# Native function-scoped stack allocation

The independent frontend/IR/Linux AMD64 path accepts `alloc4`, `alloc8` and `alloc16`: a **long** byte-size operand and **long** address result, with required minimum alignment 4, 8 or 16. The owned IR uses a typed `AllocationAlignment` and `Instruction.allocate`. The failure-atomic builder validates the pending result, open block and both classes before reserving/publishing. Source-size uses participate in SSA, the shared iterator and independent liveness/interference oracles.

Every reached execution reserves a fresh positive-size extent until that invocation returns, including constant allocations inside loops. No instruction is hoisted into a single reusable slot. Integer folding preserves allocations as unknown ordered effects even if their result is unused. The native implementation over-aligns all three forms to **16 bytes**, which satisfies each required alignment and preserves call alignment. Zero-size allocations touch no new extent; no distinctness or valid dereference of zero-size objects is promised. Native stack bytes are **not initialized**: tests write before reading, and no Image zero-initialization rule is borrowed.

## Dynamic RSP and outgoing arguments

Fixed RBP-relative homes, phi scratch and saved original registers stay unchanged. The fixed-frame limit is still **64 KiB**; it does not silently cap dynamic object sizes. `Frame` additionally records `S`, the maximum outgoing call-stack reservation rounded to 16 bytes. This rounding matters when only one 8-byte argument overflows: a raw `S = 8` would misalign `alloc16` addresses.

For size rounded to `N`, allocation decreases RSP by `N` and returns `RSP + S`. The new outgoing argument interval is `[newRSP, newRSP+S)`; the fresh object interval is `[newRSP+S, oldRSP+S)`. These remain disjoint even when `N < S`: old outgoing slots become object bytes while the outgoing reservation moves down. Earlier live allocations and all fixed frame regions remain above that interval. Calls still marshal stack arguments at the current RSP, with 16-byte alignment. Normal `leave`/RBP restoration releases all dynamic extents; saved originals remain in the fixed frame.

Runtime descent probes each new page before descending farther, using at most 4,096 bytes per step and probing any final nonzero remainder (FRAME-PROBES.md). Quoted labels use function/result identities and separate allocation namespaces. RAX is caller-saved size/address scratch, never a persistent home. No allocator helper/host function, global instruction buffer or C backend delegation is used.

## Invalid/extreme native sizes

Rounding checks `size + 15` for unsigned overflow before masking. Overflow deliberately traps with `ud2` rather than wrapping into a small allocation. This is an explicit invalid-size implementation boundary, **not** a claim that QBE assigns that signal to invalid allocation. Very large unavailable extents can fault at the host stack guard; there is no silent per-object success or saturation. The compiler does not emulate arbitrary host stack-limit policy, make native addresses safe, provide unwind metadata, or guarantee complete stack-clash hardening. Initialized valid-object operations are the result-conformance claim.

## Interpreter boundary remains explicit

By default a reached allocation consumes its ordinary instruction step and returns **`UnsupportedAllocation`**, even for zero bytes or with a supplied `memory.Image`. Opt-in `Options.stack_memory` now supplies a separate bounded synthetic object/lifetime/initialization model to both evaluators (INTERPRETER-ALLOCATIONS.md). Earlier step-budget exhaustion wins. No numeric IL address becomes a host pointer and the caller's Image is never resized. Earlier successful image writes persist after later errors; evaluator-owned frames and objects clean up. Unreached allocations do not fail safe paths. The opt-in diagnostic model does not make native addresses safe or specify QBE invalid-program behavior.

## Bounded regression design

Six new allocation tests cover failure-atomic builder retry/types/structure, all alignment variants, evaluator refusal/budget/image boundaries, malformed size SSA/types/arity, unused effects/safe branches and exhaustive parse/analysis/folder/evaluator/emitter allocation cleanup. A seventh AMD64 test checks 16-aligned outgoing reservation with a single overflow slot. Independent analysis fixtures include allocation-size uses, loops and mixed calls; the existing iterator's fixed-tag coverage gains allocation.

`tools/native_allocation_check.py` is the ninth native harness. It is designed for **580 defined-value checks** per option combination: three allocation opcodes × 23 runtime sizes × eight seeds, repeated constant-in-loop allocations with distinct positive extents and retained prior contents, recursive live caller objects, direct/indirect call mutation, mixed GP/SSE overflow arguments and `N < S` cases, preserved registers and ordinary page-sized guards. Exact expectations use independent Python integer byte sums, not emitted assembly or production semantics.

Two controlled-stack child cases require **SIGSEGV** from real dynamic page probes; two test-only unprobed negative controls must return successfully. Three checked round-up-overflow cases require **SIGILL** as an implementation boundary, not a valid-input numeric oracle. Twelve invalid-input/output-preservation checks retain no implicit word-to-long sizing and strict result classes/arity. Children have timeouts and disabled core dumps. No object is dereferenced after its invocation returns, and no uninitialized byte is used as an oracle.

All nine harnesses run in the three-build/eight-option matrix; the twelve existing independent generators remain unchanged. Actual verification results belong in HANDOFF.md after completion. This is still a scalar/native subset, not a complete compiler, full memory model, full ABI/target coverage or a claim of 100% idiomatic Zig.
