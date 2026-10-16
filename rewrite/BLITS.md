# Constant-length byte blits

The independent scalar frontend accepts this effect-only instruction:

```text
blit long-source-address, long-destination-address, nonnegative-decimal-byte-count
```

Both addresses must be long operands. The byte count must be an exact decimal constant in **0..2,147,483,647**, represented as `u31` in the typed IR. Temporary/floating counts, negative spellings (including `-0`), overflow and wrong address classes are rejected. Unlike ordinary modulo-2^64 data literals, counts never wrap. There is no result, dummy value, borrowed byte storage or allocation associated with the instruction.

This follows the documented nonnegative word-count contract, but does **not** reproduce the unchanged C reference parser's smaller packed 29-bit signed-reference limit of 268,435,455. The rewrite deliberately uses an explicit nonnegative signed-word count, not the reference's packed internal encoding. Counts just above that old limit and the new maximum compile to bounded-size assembly in tests. This is not a byte-identity or diagnostic-compatibility claim.

## Ownership, validation and effects

`Function.appendBlit(block, source, destination, byte_count)` validates block/type state before appending. Allocation failure publishes no instruction. Structural validation checks both addresses; SSA checks ordering/dominance even for zero-length blits. Both addresses participate in liveness/interference, including in the independent path/program-point oracles. Blits define/kill no SSA result. Integer folding never deletes or reorders them.

Source and destination spans must be **non-overlapping or identical**; partial overlap is not a valid program. This is not a `memmove` operation. No alias analysis, copy forwarding, dead-copy elimination, allocation, global data or aggregate ABI is added.

## Linux AMD64 lowering

A nonzero blit loads full addresses into RSI/RDI, puts the constant count in ECX (zero-extending RCX), and emits `rep movsb`. Assembly size is independent of the count; no helper call, per-byte instruction expansion or extra frame area is needed. All persistent homes are stack or callee-saved GP registers, never RSI/RDI/RCX. Incoming argument values already have homes, including when more than six GP arguments arrive on the stack. Future volatile homes must revisit these clobber constraints.

SysV AMD64 requires the direction flag clear on function entry and return. This lowering relies on that ABI contract and does not change the flag. It makes no performance claim about `rep movsb` versus unrolling or library copies.

Zero-count blits emit no machine access, including for invalid address integers. Nonzero native extents, read/write permissions and overlap policy remain the program/caller's responsibility: there are **no** runtime overlap/bounds/null checks. Native faults can happen after partial progress and do not provide rollback. Generated code is not sandboxed.

## Bounded synthetic-image interpretation

With `Options.memory_image`, both evaluators resolve addresses inside the explicitly supplied image, never as host pointers. `Image.copy(source, destination, byte_count)` checks both complete nonzero spans before mutation; an invalid span returns `MemoryOutOfBounds`. Valid identical spans are a no-op. Partially overlapping valid spans return `PartialMemoryOverlap` without changing bytes. Adjacent non-overlapping spans work in either direction. The operation is byte-oriented, so the image's endian setting is irrelevant to the copy itself.

A zero-length copy touches no address and accepts even integers outside the image. It still consumes one ordinary interpreter instruction step. Without an image or opt-in stack model, even a reached zero-count blit retains the explicit `UnsupportedMemory` feature boundary. Step exhaustion before the instruction wins. Copying does not charge one step per byte: execution budgets are not total byte-work/time guarantees; the caller-selected image extent bounds a successful copy. Completed blits persist after later interpreter errors, just like successful stores. See MEMORY-EVALUATION.md for ownership and shared-frame rules. Opt-in synthetic stack objects additionally support checked cross-region blits and reject undefined source bytes (INTERPRETER-ALLOCATIONS.md).

The image API is stricter about invalid partial overlaps than native emitted code; no semantics are promised for executing such invalid native programs. Per-operation mutation-free failure in the image is not native fault atomicity or invocation-wide rollback.

## Bounded verification

Six added unit tests cover failure-atomic builders/closed blocks, exact count/type/arity/range rules, constant-size maximum-count assembly, whole-span and overlap rejection before mutation, zero/identical/adjacent copy rules, SSA ordering/dominance/liveness, fold retention, shared-image nested calls and exact step/default-refusal behavior, plus exhaustive parser/analysis/evaluator/emitter allocation cleanup.

The new `tools/native_blit_check.py` accepts the existing three flags. Each combination checks **3,041 native blit results**:

- 22 counts from zero through 4,096; 64 source/destination offset pairs, complete destination sentinels and unchanged source buffers; eight identical-alias offsets; exact source and destination page-boundary copies (3,036 checks).
- Full-width preserved-register verification, live GP values and incoming stack pointers across a blit, and an explicit high mapped-address prerequisite (five checks). Zero-count copying through protected addresses executes without an access.

Two separate subprocesses require SIGSEGV for a protected source or destination. Twelve malformed-input cases preserve absent/existing CLI output. Partial overlaps are deliberately **not** executed natively. The harness links PIE, requires Linux AMD64 pages of at least 4,096 bytes, disables core dumps and bounds child execution time. C byte-array copying supplies independent expectations; no result is derived from the image API or generated compiler. CI runs it in all eight flag combinations alongside the existing four harnesses in Debug/ReleaseSafe/ReleaseFast. This is bounded regression coverage, not full QBE/memory/ABI acceptance or a performance test.
