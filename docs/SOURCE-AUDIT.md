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
The follow-up audit source checkpoint 705f6b8 passed all nine verification
jobs in GitHub run 38778895988. Further changes below still require a fresh
source-specific run; historical green is not transferred to a new checkpoint.

## Findings and disposition

| Finding | Priority | Disposition |
| --- | --- | --- |
| Comparison decoding returns a bool and writes two output parameters, requiring undefined locals even when callers only need a predicate | Idiomatic API | Implemented optional Comparison values; numeric condition codes retained; SSA/copy/GCM and all three target selectors updated |
| GVN allocates its per-function hash table before fallible folding, but frees it only on success | Correctness / ownership | Implemented deferred release/reset; direct regression alternates failed floating-address folding, successful and zero-instruction functions |
| Shared driver emission callbacks exit the process on writer failure, despite the Zig library exposing WriteFailed | Correctness / embedding | Implemented separate callback error propagation and library output-unit cleanup; 162 recovery checks pass; CLI wording/exit preserved |
| Benchmark timing ignores subprocess failures in several paths, and successful-output checks ignore executable return codes | Verification reliability | Implemented checked builds/runs, finite timeouts and temporary cleanup; 10 fail-closed harness tests pass |
| Memcheck describes six targets but runs five, shares a fixed temporary path, and counts non-99 failures as success | Verification reliability | Fixed six-target coverage, temporary isolation and nonzero-exit classification; 4 stub tests pass; Valgrind itself unavailable locally |
| Benchmark divs.c relies on signed overflow, invalidating timing interpretation | Measurement reliability | Replaced accumulator and input construction with defined unsigned wrapping; six native benchmark fixtures checked with UBSan |
| Local full-suite entry point hides failures behind tail/sed pipelines | Verification reliability | Replaced with fail-fast core/corpus orchestration; four isolated failure/success tests |
| -O2 power-of-two multiplication becomes a shift that AMD64's address matcher does not recognize | Measured performance candidate | Matcher-only normalization of long shifts 1..3 to scales 2/4/8 at -O1/-O2; rejects word/nonconstant/out-of-range cases; measured and full corrected-source local v2 gate passed; fresh CI still required |
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
