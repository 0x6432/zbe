# Continuation from dea7f2c — draft, not accepted

Base `dea7f2c2e6b6e9d1a5e1104d8c32a60e48be85b9` is the previous continuation draft, not an accepted baseline. The integration gate remains **HELD**. No full gate, independent terminal audit or hosted rewrite CI was run.

## Focused allocation coverage

`extern_frontier_test.zig` adds a moving-allocation sweep for a fixture with multiple functions and calls, mixed INTEGER/SSE register-class records and memory-class records. It checks selected target identities, plan/ABI layout, fold behavior and GOT/indirect-call instruction sequences. Each failed allocation must be induced, clean up, and permit retry on the same module. The assembly comparison to output from the same emitter is a retry-consistency check, not independent ABI validation.

On an isolated `dea7f2c` worktree with this test change, the pinned Zig version ran 162/162 tests in each of Debug, ReleaseSafe and ReleaseFast. Each mode exercised 32 cases and 2,312 induced failure ordinals. Runs used `/data/zbe-coordination/full-verification.lock`, at most two CPUs and a 4 GiB virtual-memory limit. A workspace restart deleted an earlier uncommitted worktree; the test was recovered from session edit history, strengthened and rerun before these results. An independent static reviewer reviewed the final changes; this was not a terminal audit.

These are focused O06–O08 witnesses, not complete O01–O10 acceptance: successful in-place resize/remap and a separately identified final-slice failure remain open. Allocation ordinals are not attributed to individual cleanup phases. Assembly checks search whole output rather than proving function-local placement/order, and some block/frame geometry checks remain incomplete. Runtime ABI, defect controls, full ledgers and integrated-tree CI remain outstanding.

## Validation-order policy conflict — not implemented

An experimental, unmerged change moved validation of ordinary direct-call symbol IDs earlier. A focused regression demonstrated on the base that an early mismatched extern call followed by an invalid ordinary direct-call ID returns `CallSignatureMismatch`; the experimental change returned `InvalidSymbol`. An independent static review found that the same change also alters ordinary-only error ordering: a mismatched ordinary call before a later invalid direct-call ID would change from `CallSignatureMismatch` to `InvalidSymbol`. It would likewise move a direct-call ID error ahead of an invalid aggregate descriptor. These ordinary-only counterexamples were established by code inspection, not execution.

The proposal's P1 says old ordinary error ordering remains unchanged, while P3 requires all IDs and descriptors before signature comparisons. These cannot both apply unconditionally to the ordinary-only counterexample. Moving the ID pass after descriptor resolution would avoid the descriptor-order change, but not the mismatch-order conflict. Choose and explicitly approve the intended scope before revising implementation: either preserve old-only ordering and narrow P3, or apply complete-ID precedence universally and amend P1 with corresponding old-only regression tests. The experimental source patch was **not merged**.

## External evidence

Public workflow API queries found no exact-commit rewrite run for the original `055301d` checkpoint or `dea7f2c` when checked. Browser sign-in for dispatch could not be completed because the secure input feature reported the page unavailable; no private values were submitted. The original checkpoint and the current tip still need their own exact-commit hosted CI. A prior M01 investigation did not produce a recoverable linked runtime witness; ordinary-LEA link rejection is not an M01 pass.

The Valgrind evidence-authorship problem and protected handoff remain unresolved. Do not advance canonical branches or interpret synthetic probes, local focused tests or static review as gate acceptance.
