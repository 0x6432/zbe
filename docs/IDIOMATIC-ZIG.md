# Idiomatic Zig rewrite tracker

Status: **in progress**. Finish the representation/interface cleanup before
adding optimizer features. Historical HANDOFF sections describe earlier stages;
this file tracks the remaining work, not a claim that every module is finished.

## Current bounded-storage milestone

- Parser temporary-name hash: slice capacity, deterministic collision probing,
  checked indexing, and allocation reuse across functions.
- Emitter debug-file list: active slice, stable numbering and deduplication.
- Intern buckets: active string slices, unchanged numeric IDs and owned strings.
- Load insertion log: active slice, growth-safe rollback, bounded consumption
  instead of an out-of-band sentinel.
- Memory coalescing: bounded store histories and instruction/blit tails, including
  recovery of the owning block for use-list instruction removal.

The field audit now finds unbounded many-pointer storage fields in `all.zig`'s
intentional core representations, rather than private pass/parser state. This
is a useful milestone, **not** the end of the rewrite: local vector builders,
legacy interfaces, and raw core-field consumers remain.

## Typed interfaces completed in the current batch

- SSA/GVN use registration uses a tagged payload rather than a separately
  supplied kind and erased pointer. The stored `Use` representation is unchanged.
- Bitsets expose mutable/read-only word slices. Helpers and register-mask users
  use bounded views, including zero-word sets without owned storage. Forward-copy
  semantics for overlapping word ranges are covered explicitly.
- Parser control states are an enum. Opcode-derived token numbers and grammar
  diagnostics are deliberately unchanged.

## Next batches, in order

1. **Instruction-vector builder interfaces.** Audit `addins`/`addbins` and local
   pointer/count builders (including the load pass's reused instruction buffer).
   Make ownership and active extents explicit without invalidating aliases or
   losing retained capacity. The pooled vector allocator is not automatically
   a candidate for replacement merely because it is custom.
2. **Module-by-module final audit.** Check mutating-loop bounds, optionality,
   ownership/error paths, and helper naming. Avoid cosmetic churn, bulk textual
   renames, or changing intentionally numeric ABI/class/comparison fields.

## Deliberate representations

These are not unfinished work merely because they resemble the C reference:

- Extern-layout IR/ABI structs retain their fields and binary representation.
  Expose bounded views at helper boundaries instead of replacing stored fields
  wholesale. The exported C library interface stays unchanged.
- NUL-terminated names, symbol/section strings, and format tables stay sentinel
  pointers where required by the established representation.
- Compile-wide globals, the shared instruction buffer, and non-thread-safe
  library behavior are intentional. Preserve cached pass storage across calls.
- Target register lists, instruction classes, ABI classifications and comparison
  offsets may be numeric by design; preserve their meaning and layout.
- `-O0`/`QBE_COMPAT=1` retains C-reference byte identity, including documented
  upstream behavior. Optimized correctness is checked independently; do not
  weaken fuzz oracles or silently patch the reference to hide a mismatch.

## Verification gate

For every meaningful batch: direct regressions, pinned-Zig build/unit tests,
six-target assembly/debug identity, input-error and strict-diagnostic checks,
edge/bug/library/jump suites, optimized behavior/fuzzing, and relevant real-world
corpus tests. Run mutation checks after optimizer changes and as part of the
aggregate core gate. Verify the actual GitHub CI result before calling it green.

Builds and long tests run in the background with logs and PIDs. Checkpoint each
batch and append current verification facts to HANDOFF.md. Never force-push
unexamined divergence or create a release tag without explicit authorization.
