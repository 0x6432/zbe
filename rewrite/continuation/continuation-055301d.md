# Continuation from 055301d — draft, not accepted

Checkpoint: `055301dbcf79fe4b07bba15b1d6eb873f18fa4b7`, verified as the fetched tip of `draft/extern-got-foundation-3955fc2-20261109` on 2026-11-09 UTC. This is a continuation of an unaccepted draft, not a gate or release approval.

## Changes

- Report `unsupported_construct` for `extern` at the type-declaration name boundary. The regression checks its exact byte span, `:extern` remains a legal type name, ordinary invalid names retain their diagnostics, and newline/comment and lexing precedence are exercised.
- Add focused moving-allocation failure/retry tests for parse, planning, and emission. Both target forms are installed before folding and checked for identity afterward. Selected ABI layout fields and literal GOT-load/indirect-call sequences are checked. Same-emitter assembly equality is a retry consistency oracle, not an independent ABI oracle.
- Add a synthetic pathname-substitution investigation and report. This exposes a modelled risk in the repository path consumer, not an actual Valgrind or full-gate result. See `evidence-path-probe-report.md` for controls, limitations and hashes.

## Local evidence and limitations

- Pinned Zig `0.18.0-dev.35+5e754304d` archive and filename were verified using the upstream minisign key and the `mlugg/setup-zig` verifier. SHA-256: `cda25c1d2d8f10152b4c0ab797c41a5627a1395316083958870398fa136d766b`.
- The revised focused frontier test, placed in an otherwise isolated checkpoint tree, passed 7/7 in Debug, ReleaseSafe and ReleaseFast. Each mode exercised 96 planning/emission cases and 2,912 injected allocation-failure ordinals, plus 22 fresh-parse failure ordinals. Runs held `/data/zbe-coordination/full-verification.lock`, used at most two CPUs and a 4 GiB virtual-memory limit. These tests do not cover multi-function/multi-call cleanup, register-class record construction, a separately identified final-slice allocation, or in-place resize/remap paths.
- On the combined working tree, the type-declaration boundary regression passed in all three modes after review-driven additions. Existing extern diagnostic tests passed in all three modes before those additions; a focused Debug extern-filtered run passed 37/37 on an earlier combined snapshot. Formatting and `git diff --check` passed. These are focused author runs, not the full suite.
- The optional local exact-checkpoint Debug full unit suite was intentionally interrupted (exit 143) to avoid delaying required hosted CI. It is **not** a pass; ReleaseSafe and ReleaseFast full suites were not run. Public GitHub API inspection found no rewrite workflow run for the checkpoint at the time of inspection. Hosted exact-checkpoint CI requires a separate dispatch; do not treat earlier SHA evidence as this run.
- An independent static reviewer examined the changes and identified gaps; the folded-wrapper, exact-identity, probe assertion/control and test-cleanup findings were addressed. Remaining allocation/ABI coverage gaps above remain open. This was not the independent terminal audit.

## Gate status

**HELD.** The exact prior gate preparation and Valgrind were unavailable in this environment. Exclusive Valgrind core log authorship, protected case-bound handoff, full gate, independent terminal audit and required exact-commit CI remain outstanding. Do not advance canonical branches or infer acceptance from synthetic tests or earlier hosted runs. No force push or canonical-branch change was made during this continuation.
