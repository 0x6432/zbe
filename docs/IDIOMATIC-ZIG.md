# Idiomatic Zig rewrite tracker

Status: **planned codebase-wide representation/interface pass implemented;
local verification passed; GitHub CI confirmation pending**. No new optimizer features are part of this
stage. Historical HANDOFF sections record intermediate, not current, completion.

## Implemented scope

- Typed opcodes, value/jump/use/alias kinds and SSA use payloads; errors propagate
  as Zig errors with the established input diagnostics and C return codes.
- Bounded parser caches, debug-file lists, intern buckets, load insertion logs,
  memory histories, pass maps, spill scratch and instruction builders. Capacity,
  stable ordering, IDs and cross-function allocation reuse remain deliberate.
- Generic passes and all target ABI/isel/emitter modules access active temporary,
  constant, memory, instruction, predecessor/frontier, phi, materialized RPO and
  aggregate-field storage through bounded views. Views are reacquired after growth.
- Empty core views never inspect unowned pointers. Vector mutators retain owned
  empty pointers at explicit allocator boundaries, rather than mistaking an empty
  read view for an allocation they can grow or free.
- Instruction prefix replacement handles capacity writes, overlap-safe tail
  movement and publication of the new extent. Constants are values/snapshots
  across allocation-sensitive operations instead of borrowed table pointers.
- The compile-wide type table carries its active length. Parser State owns its
  lexer-cache initialization flag. Deferred cleanup handles partial type/lexer
  allocations and failed-parse lookup state without discarding cached pass buffers.

## Audit coverage

| Area | Reviewed boundaries |
| --- | --- |
| Core IR and util | Active extents, enum payloads, word views, growth/alias ownership, instruction copying |
| Parser, data/debug emitter, driver, library | Cached tables, type ownership, parser states, diagnostics/error propagation, C interface |
| CFG, SSA, alias/copy/fold, GVN/GCM, if-conversion | Graph/use payloads, bounded core reads/writes, mutating-loop extents |
| Load/memory, liveness, spilling, register allocation | Histories, retained buffers, original-block map limits, prefix reconstruction |
| AMD64 SysV/Windows, arm64, rv64 | Type/argument classification, instruction selection/emission, table-growth boundaries |

This is completion of the planned representation/interface pass, not a promise
that every possible style improvement has been exhausted or that the compiler
has no bugs. Full regression and CI results must be recorded before publishing.

## Deliberate low-level representations

These are not unfinished work merely because they resemble the C reference:

- Extern-layout IR/ABI fields remain unchanged; bounded views are helper methods.
  The exported C interface and intentionally numeric ABI/class/comparison fields
  are preserved, as are fixed register arrays and sentinel-terminated save lists.
- NUL-terminated symbol/section/name strings remain sentinel pointers where
  required. The vector allocator retains header/pointer operations at allocation,
  growth, free and extent-publication boundaries. The pooled allocator is deliberate.
- Compile-wide globals, the shared reverse-emission instruction buffer, cached
  capacities and non-thread-safe library behavior remain intentional.
- RPO views describe a materialized table; after linking new CFG blocks, rebuild
  the CFG before using that view. Original-block rega maps never index new edge blocks.
- `-O0`/`QBE_COMPAT=1` retains C-reference output, including documented upstream
  behavior. Optimized correctness is tested independently. Never weaken the
  Python oracle or patch the reference to conceal a mismatch.

## Verification/publication gate

Run direct Debug and ReleaseSafe regressions, pinned-Zig build, parser/cache
stress, six-target assembly/debug identity, input-error and strict-diagnostic
checks, edge/bug/library/jump suites, native behavior, optimized fuzz, all 11
optimizer mutation checks, package consumer and the real-world cproc corpus.
Check actual GitHub CI, distinguishing running from confirmed green.

Builds and long tests run in the background with logs and PIDs. Append current
results to HANDOFF.md. Fetch and reconcile remote state before fast-forwarding
both main and wip/idiomatic. Never force-push unexamined divergence, commit
credentials, add optimizer features during this stage, or create a release tag
without explicit authorization.
