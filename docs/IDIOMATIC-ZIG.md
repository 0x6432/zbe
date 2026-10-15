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

## Instruction builders completed

- Active instruction slices replace pointer/count pairs in GCM scheduling,
  conditional conversion and load reconstruction. Block wrappers synchronize
  the intentionally stored IR pointer/count fields.
- Append helpers accept instruction values and bounded sources. Self-appends
  reacquire source elements after growth; nops and empty inputs preserve the
  existing semantics, including unowned empty block storage.
- Reused buffers retain capacity between blocks. Load reconstruction still
  retains nops for byte-identical compatibility debug dumps.

## Additional core boundaries

- CFG union-find returns block roots directly and compresses typed parent
  links; it no longer casts optional successor fields to nonoptional pointers.
- Temporary use-list readers share `Tmp.uses()`. Empty views do not inspect
  storage, while nonempty views require materialized uses. Count-only tracking
  and the stored layout remain unchanged.

## Function-table consumers completed

- Generic passes and all target ABI/isel/emitter modules index temporary,
  constant and memory tables through active Fn views. Views are reacquired
  at each use, not cached across table growth; zero counts guard unowned storage.
- Constant insertion takes a value, and AMD64 external/TLS lowering snapshots
  constants before allocation-sensitive rewrites. Stored fields are unchanged.

## Remaining audit

Current audit checks covered CFG/SSA use boundaries, allocator/vector
ownership, driver error propagation, and the target ABI/isel/emitter pointer
categories. Remaining raw pointers are predominantly stored core IR fields,
sentinel strings, vector allocation boundaries and the shared instruction
buffer. Direct indexed core-field consumers still merit a follow-up bounded-view
audit; do not declare every module fully idiomatic from this scan alone.

Continue checking mutating-loop bounds, optionality, ownership/error paths,
and raw core-field consumers. Avoid cosmetic churn, bulk textual renames, or
changing intentionally numeric ABI/class/comparison fields. The pooled vector
allocator is deliberate, not automatically a replacement candidate.

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
