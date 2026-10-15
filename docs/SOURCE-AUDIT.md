# Follow-up source audit

## Verdict and scope

The planned representation/interface pass is complete, but **“100% idiomatic
Zig” is not a defensible certification**. Idiomaticness is a design judgment,
not a property proved by compiling or counting pointers. Further useful work
exists. Preserve deliberate low-level representations rather than translating
all C-shaped code mechanically.

This follow-up reviews the current IR/util interfaces, parser and allocator
ownership, pass scratch lifetimes, target instruction selection, CLI/library
error propagation, and the reliability of verification/benchmark tools.
It is not a formal proof or an exhaustive search for compiler defects.
The previous nine-job CI result covers ac2e336, not the changes below.

## Findings and disposition

| Finding | Priority | Disposition |
| --- | --- | --- |
| Comparison decoding returns a bool and writes two output parameters, requiring undefined locals even when callers only need a predicate | Idiomatic API | Replace with an optional Comparison value; retain numeric condition codes and update SSA/copy/GCM and all three target selectors |
| GVN allocates its per-function hash table before fallible folding, but frees it only on success | Correctness / ownership | Defer release and reset immediately after allocation; regress failed floating-address folding followed by successful and zero-instruction functions |
| Shared driver emission callbacks exit the process on writer failure, despite the Zig library exposing WriteFailed | Correctness / embedding | Propagate callback writer errors to the CLI/library boundary; keep the CLI diagnostic and exit behavior |
| Benchmark timing ignores subprocess failures in several paths, and successful-output checks ignore executable return codes | Verification reliability | Harden before trusting performance results; reject failed/crashed/timed-out commands |
| Memcheck describes six targets but runs five, shares a fixed temporary path, and counts non-99 failures as success | Verification reliability | Require explicit handling before claiming memory-check coverage |
| Repository-wide zig fmt --check reports pre-existing differences | Style / lower priority | Do not conceal this or reformat unrelated compiler code in a semantic patch |

## Boundaries to keep

- Extern IR layouts, C interface, numeric class/ABI/comparison fields.
- Sentinel strings and raw allocator/header operations at ownership boundaries.
- Compile-wide state, pooled allocation and the shared instruction buffer.
- Cached spill/parser/pass capacities across functions; GVN's table is instead
  allocated and released per call, so deferred cleanup does not discard a cache.
- Exact diagnostic wording and reference output at -O0 / QBE_COMPAT=1,
  including the documented upstream constant-jnz bug. Optimized semantics must
  pass the unchanged oracle separately.

## Ordered continuation

1. Finish the focused idiomatic API/ownership regressions, then harden library
   error recovery and the relevant verification tools.
2. Establish reproducible ReleaseFast performance measurements only after the
   benchmark rejects failures; optimize only where evidence supports it.
3. Prepare release notes, package checks and a verification checklist. Do not
   change the version or create a tag/release without explicit authorization.

## Publication gate

New source changes require pinned Debug and ReleaseSafe tests, full core,
six-target assembly/debug identity, diagnostics, native behavior and optimized
fuzz, followed by a fresh GitHub CI result. Record exact results in HANDOFF.md;
do not carry a prior source checkpoint's green status onto new code.
