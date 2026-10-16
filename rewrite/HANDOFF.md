# Zig-native rewrite handoff

## Scope and base

- Branch: `rewrite/zig-native`, based on `ab50bae01ee280b836bd86f2a8d23866912f19bc`.
- This is an independent, from-scratch core under `rewrite/`, not a completed compiler rewrite.
- Legacy compiler sources, root build configuration, reference tools and regression tests are unchanged.
- `main` and `wip/idiomatic` remain at the base; publish only this rewrite branch. No release or tag is authorized.

## Initial foundation (historical)

Allocator-owned symbols, separately allocated module-owned functions, typed function-scoped block/value IDs, tagged scalar constants/operands, minimal binary instructions and terminators, structural/type validation with bidirectional definition checks. No legacy imports, mutable compiler globals or libc dependency in the new core.

Tests cover owned string input, deduplication, stable borrowed symbol strings/function pointers, independent modules, typed builders, invalid operands/targets/returns, corrupt definition links, growth, low-word branch conditions, and cleanup under every allocation failure in representative growth scenarios. Dedicated recovery tests inject failure at both linked builder allocations, then retry on the same function.

The validator is not a full SSA verifier; IDs do not encode their owner identity. No parser, complete IL vocabulary, CFG/dominance engine, optimizer, target lowering, register allocation, emitter or CLI is implemented yet. Do not claim backend or ABI compatibility from these foundation tests.

## Verification and publication

Use the pinned Zig version from README. Run `zig build test` in Debug, ReleaseSafe and ReleaseFast plus `zig fmt --check build.zig src`. The branch-only workflow `.github/workflows/rewrite.yml` tests those same three modes; it does not assert legacy compiler parity or publish releases.

Local verification results and remote run status are recorded below after completion.

## Next milestones

The scalar frontend update below starts the frontend stage. Expand to full typed IL, CFG/SSA verification, and target lowering as described in DESIGN.md. Do not delegate parsing or code generation to the legacy implementation and describe that as a rewrite.

### Local foundation verification

Pinned Zig `0.18.0-dev.35+5e754304d`: **13/13 tests passed in each of Debug, ReleaseSafe and ReleaseFast**. Formatting passed. The allocation-failure scenarios and same-function recovery checks are included in all three runs. Verification log in the working environment: `/data/verify-native-rewrite-foundation.log` (not a portable repository artifact).

`git diff origin/main -- src build.zig build.zig.zon tools tests` was empty. The old compiler suite was not rerun for this isolated foundation; its earlier CI result is not evidence of rewrite parity.

### Published foundation CI

Published source checkpoint: `fa8ec8fb54a3bca64d3fdcc1708b64cfcc8b7d98` on `rewrite/zig-native`.

GitHub run https://github.com/0x6432/zbe/actions/runs/38860532445 completed with **success**: Foundation (Debug), Foundation (ReleaseSafe), and Foundation (ReleaseFast) all passed. This is the independent foundation workflow, not the legacy nine-job compatibility suite.

Remote `main` and `wip/idiomatic` were confirmed at `ab50bae01ee280b836bd86f2a8d23866912f19bc` after the branch push. No tag or release was created. This result-recording follow-up is documentation-only; it does not change the tested source or workflow.


## Scalar frontend update

Implemented independent `source.zig`, `lexer.zig` and `frontend.zig`. The parser owns its token/name-map scratch storage, frees all partial IR on failure, and returns a module independent of the input's lifetime. It retains export linkage and resolves forward block targets without placeholder pointers. IR now supports typed `copy` instructions as well as the initial arithmetic subset.

Coverage includes all four functions in the unchanged constant-jump fixture, parameters, void functions, current binary operations, signed zero/hexadecimal floats, typed malformed-input diagnostics, duplicate/unknown names, every fixture truncation, 1,024 deterministic three-byte mutations and all 65,536 byte pairs through the lexer. Valid and malformed multi-function parses are exercised at every controlled allocation failure.

An optimized local run exposed `NondeterministicMemoryUsage` in the existing IR growth/OOM test. The standard injector assumes repeatable allocation counts; in-place resize/remap decisions can change those counts. A shared test helper now runs ordinary allocator growth first, then exhaustively injects failures with resize/remap disabled so growth must allocate deterministically. It still checks every allocation failure and freed byte count; OOM errors are not swallowed. This changes the test harness, not production allocator behavior.

This is a **scalar subset**, not the full frontend: no globals/data, aggregate/ABI types, memory operations, calls, phi, varargs, quoted global decoding, implicit mixed-width conversions or NaN payload conversion yet. Temporary uses must follow textual definitions, and dominance remains unchecked. See FRONTEND.md; passing parser tests is not evidence of emitted/executed code or backend parity. The old compiler and its diagnostics/oracles are unchanged.

### Scalar frontend local verification

Pinned Zig `0.18.0-dev.35+5e754304d`: **32/32 tests passed in Debug, ReleaseSafe and ReleaseFast**, and formatting passed. After the standard build runner reused cached results for repeat invocations, ten **uncached direct executions** of the newly built ReleaseFast test artifact were run separately; all 32 tests passed on every execution. Logs are `/data/verify-native-frontend-final.log` and `/data/repeat-native-frontend-fast-tests.log` in the current environment, not repository artifacts.

The copied constant-jump fixture is byte-identical to its legacy source. `git diff ab50bae -- src build.zig build.zig.zon tools tests` is empty; no legacy compiler behavior or oracle was changed. Remote CI for this source checkpoint is checked separately after publication.

### Scalar frontend published CI

Source checkpoint `add705d6e7929097dadc24d39a9c62d895b9cd4d` was pushed only to `rewrite/zig-native`. GitHub run https://github.com/0x6432/zbe/actions/runs/38862128437 completed **successfully**: Rewrite core (Debug), Rewrite core (ReleaseSafe), and Rewrite core (ReleaseFast) all passed. This is independent IR/frontend verification, not the old compiler's compatibility suite.

This documentation-only result update does not alter the tested code/workflow. Next: complete typed IL and its frontend coverage, then CFG/SSA verification before target lowering. No main-branch merge, release or tag was performed.

## Scalar CFG/SSA and interpreter milestone

Added owned read-only CFG snapshots with CSR predecessors, deduplicated successor edges, reachability and iterative reverse-postorder traversal. Dominators use iterative immediate-dominator intersection over RPO ranks. Graphs own their data rather than borrowing function storage; callers must rebuild after mutation. Tests include diamonds, reordered and irreducible loops, unreachable nodes, a 4,096-block chain, and independent vertex-removal/BFS checks on 512 generated graphs.

`ssa.validate` now checks scalar instruction/terminator uses for same-block ordering and cross-block dominance. Unreachable blocks accept parameters and ordered local uses, but conservatively reject cross-block uses; this is an explicit subset policy, not full QBE validation. The frontend still performs syntax/structure checks only. There are no phi nodes yet.

Added an invocation-owned bounded scalar interpreter that always validates SSA before execution. Instructions/terminators consume a finite step budget. Integer arithmetic wraps at word/long widths; branches use low-32-bit semantics; copies retain floating bits. All four constant-jump regressions are evaluated with expected results 0, 0, 0, 1. This is semantic interpretation, not compiled/native execution.

A committed fixture contains 384 Python arbitrary-precision integer oracle cases, checked through the new parser and evaluator. The reproducible generator is `rewrite/tools/generate_integer_oracle.py`; CI checks it with `--check`. The old Python oracle, compiler and reference suite are unchanged. Exhaustive controlled allocation-failure checks cover successful and rejected SSA paths, CFG/dominator ownership, and evaluator frames. See SCALAR-SEMANTICS.md for exact contracts and remaining limits.

### Scalar semantics local verification

Pinned Zig `0.18.0-dev.35+5e754304d`: **57/57 tests passed in Debug, ReleaseSafe and ReleaseFast**; formatting and Python oracle reproducibility passed. Current-environment log: `/data/verify-native-semantics.log`. No legacy source/build/tool/test changes; no native code-generation parity is claimed.


### Scalar semantics published CI

Source checkpoint `95dd0df445e1fb2b97966f7374344bd9c35a7dcc` passed GitHub run https://github.com/0x6432/zbe/actions/runs/38865302907: Debug, ReleaseSafe and ReleaseFast all succeeded, including integer-oracle reproducibility. This result belongs to the 57-test scalar-semantic checkpoint, before the following phi extension.

## Phi nodes and forward value declarations

Added owned typed phi-input slices and explicit pending value declarations. Define builders complete reserved values without creating untyped references; unfinished or multiply defined values fail validation. Define failures retain retryable pending state. Phi-input allocation is failure-atomic and independent of borrowed input arrays.

The frontend predeclares temporary types and block labels, then defines instructions/phis. It accepts loop backedges and layout-independent forward references, while SSA validation still rejects invalid use-before-definition/dominance. Phi nodes must precede ordinary instructions.

SSA validation checks each unique predecessor exactly once, forbids entry phis, and validates each incoming operand at the predecessor's end. Diagnostics now have a tagged use site rather than a nullable instruction index. The interpreter reads all incoming phi values into separate scratch before committing results, preserving simultaneous assignment and swaps. Each phi consumes one execution-budget step.

New tests cover phi edge coverage, incorrect-edge definitions, entry phis, copied input ownership, retry after both allocation failure points, unresolved declarations, forward layout, floating payload selection, diamond selection, and a counter loop with two mutually swapping phi values and exact execution budgets. The legacy compiler, oracle and compatibility behavior remain unchanged.

### Phi local verification

Pinned Zig: **68/68 tests passed in Debug, ReleaseSafe and ReleaseFast**, plus ten uncached direct executions of the ReleaseFast artifact (68/68 each). Formatting and independent Python oracle reproducibility passed. Logs: `/data/verify-native-phi.log` and `/data/repeat-native-phi-fast-tests.log` in this environment. No legacy source/build/tool/test changes. Remote CI is checked separately after this source checkpoint is pushed.


### Phi published CI

Source checkpoint `b5780af4f8a32087a016e15d41b886e3dc3d3868` passed GitHub run https://github.com/0x6432/zbe/actions/runs/38866093154: all three Debug/ReleaseSafe/ReleaseFast jobs succeeded. This is the 68-test phi checkpoint, before native emission below.

## Experimental Linux AMD64 integer vertical slice

Added an independent assembly emitter and `zbe-native input.ssa output.s` driver, without importing or delegating to the old backend. The emitted subset includes word/long/void functions, SysV GP register and stack arguments, current integer arithmetic/bitwise/copy instructions, low-word branches and parallel edge phi copies. Every SSA value is stack-homed; there is no allocator/optimizer parity. Prototype frames are capped at 64 KiB; unsupported floating/ABI/language/target features return explicit errors. Symbols are checked and internal labels occupy a disjoint quoted namespace.

The native harness assembles/links generated output with a C driver and checks 406 integer/oracle/branch/phi/ABI results plus a void call. It tests both sides of conditional phi edges and duplicate branch targets, all four constant-jump regressions, swap loops, and eight-argument word/long calls. Eight CLI tests cover typed rejection, no output creation, preservation of existing outputs, usage and identical input/output rejection. See NATIVE-AMD64.md; this is not complete QBE/ABI/target compatibility or release-ready code generation.

### Native integer slice local verification

Pinned Zig Debug, ReleaseSafe and ReleaseFast builds each passed **72/72 unit tests**, **406 assembled/linked/native result checks**, and **8 CLI rejection/output-preservation checks**. Formatting and Python oracle reproducibility passed. Current-environment log: `/data/verify-native-amd64-final.log`. These optimize modes describe the compiler build, not backend IL optimizations. CI is extended to build/run the native harness in each matrix job and is checked separately after publication. The legacy source/build/tools/tests remain unchanged.


### Native integer slice published CI

Source checkpoint `dbff646fbd5f2910e9ae8e5023041ed5e9c3153a` passed GitHub run https://github.com/0x6432/zbe/actions/runs/38867028347. All three Debug/ReleaseSafe/ReleaseFast jobs succeeded, including 72 unit tests, 406 assembled/linked/native result checks and eight CLI checks per mode. This result precedes the shift/comparison extension below.

## Typed integer shifts and comparisons

Added semantic shift/predicate enums, typed IR builders and validation, parsing, SSA operand checks, bounded evaluation and Linux AMD64 emission. Shift counts are word operands with low-five/low-six-bit masking. Integer comparison suffixes select word/long operands; results independently support either integer width and are always zero/one. Signed and unsigned predicates are distinct; no floating comparisons or division/remainder are implied.

An independent reproducible Python fixture adds 832 cases covering modulo decimal constants, signed boundaries, masked counts and comparison result widths. Tests consume it through parsing/evaluation and through assembled/linked/native execution. Additional regressions cover comparison-driven loop phis, non-dominating shift/comparison inputs, invalid types, allocation-failure cleanup and preservation of incoming arguments across `%cl` scratch use. The legacy compiler, test oracle, build and reference suite are unchanged.

### Shift/comparison local verification

Pinned Zig Debug, ReleaseSafe and ReleaseFast each passed **78/78 unit tests**, **1,245 assembled/linked/native result checks**, and **8 CLI rejection/output-preservation checks**. Formatting and both independent Python fixture reproducibility checks passed. Current-environment log: `/data/verify-native-scalar-full.log`. Legacy source/build/tools/tests are unchanged. Remote CI is checked separately after publication; no release tag or main-branch integration is authorized.


### Shift/comparison published CI

Source checkpoint `a546f093682470408d5a4efb4cfad75d3f198c11` passed GitHub run https://github.com/0x6432/zbe/actions/runs/38868062443: Debug, ReleaseSafe and ReleaseFast all succeeded, including 78 unit tests, 1,245 native checks and eight CLI checks per mode. This precedes the unary extension below.

## Typed negation and integer extensions

Added a semantic unary-operation enum whose operand-type contract is shared by parsing and IR validation. All four scalar types support same-width negation; integer negation wraps, floating negation changes only the sign bit. Native emission remains integer-only. Byte/half extensions read a word and return word or long; word extensions read a word and return long only. Signed and unsigned extensions are explicit. They do not implement extended ABI types.

An independent reproducible Python fixture supplies 384 modulo/boundary/random negation and extension expectations. The interpreter tests immediate parsing and evaluation, while native tests pass the corresponding bit patterns as runtime C arguments. Additional tests cover floating signed zero/infinities/NaN payloads, invalid operand/result types, SSA ordering/dominance, builder retry after allocation failure, structural revalidation after mutation and exhaustive allocation-failure cleanup in parsing/evaluation/emission. No legacy compiler/build/tool/test changes or new release tags.

### Unary local verification

Pinned Zig Debug, ReleaseSafe and ReleaseFast each passed **85/85 unit tests**, **1,629 assembled/linked/native result checks**, and **8 CLI rejection/output-preservation checks**. Formatting and all three independent Python fixtures' reproducibility passed. Current-environment log: `/data/verify-native-unary.log`. Native floating code generation is still unsupported; floating negation tests establish interpreter bit semantics only. Remote CI is checked separately after publication.


### Unary published CI

Source checkpoint `5889954db31146f4b4bc5d4fe05acd987ac419e5` passed GitHub run https://github.com/0x6432/zbe/actions/runs/38868745314: Debug, ReleaseSafe and ReleaseFast all succeeded, including 85 unit tests, 1,629 native result checks and eight CLI checks per mode. This precedes division/remainder support below.

## Signed/unsigned division and remainder

Added integer `div`, `udiv`, `rem` and `urem` throughout the typed binary path and Linux AMD64 emitter. Signed quotient truncates toward zero; remainder has the dividend's sign. Floating `div` is supported only by scalar parsing/evaluation; native floating remains unsupported. The evaluator checks zero divisors and signed-minimum/minus-one pairs before host arithmetic and returns typed errors, including for signed remainder overflow. Native AMD64 instead uses the hardware arithmetic-fault boundary. No portable QBE exceptional-result semantics are claimed.

A reproducible Python fixture adds 1,228 valid cases using integer quotient/remainder identities, all checked through evaluation and runtime C arguments to assembled/linked output. Exceptional pairs are not silently filtered out of verification: twelve native subprocess checks require SIGFPE, and evaluator tests require the corresponding errors. Core dumps are disabled. A mixed-argument regression checks that division scratch does not corrupt former `%rdx`/`%rcx` incoming values. Allocation-failure cleanup covers exceptional evaluation and emission.

### Division/remainder local verification

Pinned Zig Debug, ReleaseSafe and ReleaseFast each passed **91/91 unit tests**, **2,858 assembled/linked/native result checks**, **12 native arithmetic-fault checks**, and **8 CLI rejection/output-preservation checks**. Formatting and all four Python fixtures' reproducibility passed. Current-environment log: `/data/verify-native-division.log`. The initial integration smoke build caught two compile errors (duplicate local declaration and a removed standard-library integer-type helper); both were corrected before this successful full run. No test or oracle was weakened. Legacy source/build/tools/tests remain unchanged. Remote CI is checked separately after publication.


## Mixed-program differential coverage

Added a bounded deterministic program generator, not a new optimizer or full-language fuzzer. It creates 32 integer functions and 512 expected invocation results, mixing 20 operations per function with diamond control flow, edge phis, and a counted loop carrying multiple values. Expected results come from independent Python bit-pattern calculations, and both the Zig parser/verifier/evaluator and native emitted programs consume the same committed corpus. Reproducibility is checked by CI. Exceptional division pairs remain tested separately and are not assigned arbitrary values here.

### Mixed-program local verification

Pinned Zig Debug, ReleaseSafe and ReleaseFast each passed **92/92 unit tests**, **3,370 assembled/linked/native result checks**, **12 native arithmetic-fault checks**, and **8 CLI rejection/output-preservation checks**. Formatting and all five independent generators' reproducibility checks passed. Current-environment log: `/data/verify-native-mixed.log`. Legacy source/build/tools/tests remain unchanged. The preceding division checkpoint's CI was still running when this entry was written; no green result is inferred from local success. Remote results are recorded separately.


### Division and mixed-program published CI

Division source checkpoint `ebf104f196fdb7659e4100d85bdcd4dde18e8907` passed https://github.com/0x6432/zbe/actions/runs/38869391957: all three Debug/ReleaseSafe/ReleaseFast jobs succeeded. Mixed-program checkpoint `4d59d48aaff1f05df92714bc5952421faec37c45` passed https://github.com/0x6432/zbe/actions/runs/38869605109: all three jobs also succeeded. These results precede native floating emission below.

## Native base-scalar floating emission

Expanded Linux AMD64 emission to single/double scalar copies, sign-bit negation, SSE add/sub/mul/div and raw-bit parallel phi copies. GP and SSE incoming argument counters are independent; overflow scalar stack slots follow declaration order. Floating results return in XMM0. Scalar homes retain raw bits; floating parameter movement, copies, negation and phis do not use arithmetic conversion. This does not implement floating comparison/conversion, aggregates, extended ABI types, calls, varargs, memory, other targets or full ABI compatibility.

A new 512-case exact-rational Python oracle explicitly rounds finite arithmetic inputs to IEEE binary32/binary64 nearest-even, including signed zero and normal/subnormal/overflow boundaries. The same cases are checked by the interpreter and native SSE output. The separate native floating harness adds payload-preserving copy/negation/phi tests and weighted mixed signatures that exhaust GP and SSE banks in interleaved and floats-first order. No target-specific NaN arithmetic payload or non-default floating environment conformance is asserted. Core bit-constant tests and allocation-failure cleanup cover floating emission.

Because basic floating types are now supported, the CLI rejection fixture now rejects the still-unsupported floating comparison instead; output-creation/preservation expectations are unchanged. No legacy tests or oracle were weakened.

### Native floating local verification

Pinned Zig Debug, ReleaseSafe and ReleaseFast each passed **95/95 unit tests**, **3,370 integer/program native result checks**, **616 floating/bit-pattern/mixed-ABI native checks**, **12 native arithmetic-fault checks**, and **8 CLI rejection/output-preservation checks**. Formatting and all six independent generators' reproducibility passed. Current-environment log: `/data/verify-native-floats.log`. All float expectations are bounded to the documented environment/operation subset; this is not full floating/ABI/QBE conformance. Legacy source/build/tools/tests remain unchanged. Remote CI is checked separately after publication.


### Native floating published CI

Source checkpoint `ba6fadebeb479a51105ad10ef3c5ab47409ce3cb` passed GitHub run https://github.com/0x6432/zbe/actions/runs/38870276587. The complete run is confirmed successful, not merely locally verified.

## Bit-preserving casts and exact floating widening

Added same-width `cast` across integer/floating classes and `exts` single-to-double widening through the existing semantic unary path, with shared type contracts, structural validation, evaluation and native emission. A new reproducible 384-case fixture tests all four cast directions (including signed zero/infinity/NaN payloads) and finite/infinity widening boundaries. Additional tests cover bad classes/widths and allocation-failure cleanup across parsing/evaluation/emission.

Precision narrowing remains deliberately unsupported. Prior inspection found that upstream `doc/il.txt` describes `truncd` as toward-zero, while the unchanged AMD64 C reference emits `cvtsd2ss`. A separate bounded probe with input `0x1.0000018p0` under FE_TONEAREST returned `0x3f800001`, not toward-zero `0x3f800000`. No reference code, oracle or legacy behavior was changed, and no new narrowing semantics were silently selected.

### Recovery after sandbox rollback

The sandbox reverted to local checkpoint `1a95cea` after an interrupted publication attempt. GitHub still contained the complete published chain through `ba6fade`; the clean worktree was restored with a fast-forward, without recreating or duplicating those commits. The unpushed conversion source/tests were recovered from the active session record and are being freshly verified in this environment. Previous local verification/probe logs were not retained across the rollback; do not infer they exist at their historical paths. Main remains at `ab50bae01ee280b836bd86f2a8d23866912f19bc`; no release tag was created.

### Recovered cast/widening verification

Fresh verification after recovery passed in Debug, ReleaseSafe and ReleaseFast: **98/98 unit tests**, **3,370 integer/program native checks**, **1,000 floating/bit-pattern/mixed-ABI native checks**, **12 native arithmetic-fault checks**, and **8 CLI checks per mode**. Formatting and all seven generators' reproducibility passed. Current-environment log: `/data/verify-native-conversions-recovered.log`; runner and PID file share that prefix. Legacy source/build/tools/tests are unchanged. The floating checkpoint is confirmed green on GitHub; conversion CI is checked separately after this source checkpoint is pushed.


## Typed floating comparisons

Added semantic floating type/predicate enums, a typed compare instruction and failure-atomic builder, frontend opcode decoding, structure/SSA checks, strict evaluator truth semantics and NaN-aware SSE lowering. Both floating operand widths and both integer result widths are supported. Equality/less/less-equal explicitly mask unordered native flags; inequality includes unordered. Ordered/unordered predicates use the parity flag.

An independent reproducible 2,560-case oracle uses integer NaN/infinity classification and exact rational finite ordering. It checks both operands and signed zero/infinity/quiet/signaling NaN cases through evaluation and native execution. Additional tests check invalid classes/widths, dominance of each operand, builder retry/mutation validation and exhaustive allocation cleanup. Native exception-flag/unmasked-trap parity is not claimed. The unsupported CLI fixture now rejects still-unimplemented `truncd`; rejection/output preservation checks remain intact.

### Floating comparison local verification

Pinned Zig Debug, ReleaseSafe and ReleaseFast each passed **103/103 unit tests**, **3,370 integer/program native checks**, **3,560 floating/bit-pattern/mixed-ABI native checks**, **12 native arithmetic-fault checks**, and **8 CLI checks**. Formatting and all eight generators' reproducibility checks passed. Current-environment log: `/data/verify-native-float-comparisons.log`. Legacy source/build/tools/tests remain unchanged. Conversion CI is still monitored separately; no running run is inferred green. Comparison CI is checked after publication.


### Conversion and floating comparison published CI

Recovered conversion checkpoint `eff12e0c6c468c3149fcff66957f9ee1cff20c35` passed https://github.com/0x6432/zbe/actions/runs/38877374218: all three Debug/ReleaseSafe/ReleaseFast jobs succeeded. Floating comparison checkpoint `7b6b23d45eab28b7352f9b8ea840adb282dd6360` passed https://github.com/0x6432/zbe/actions/runs/38877658617: all three jobs also succeeded. These precede the optimizer below.

## Conservative integer constant folding

Extracted pure scalar bit-pattern operations into `semantics.zig`, shared by evaluation and a new opt-in source-order integer folding pass. The pass validates SSA and allocates all facts before mutating a function. It preserves IDs/backlinks, instruction counts, CFG, phi inputs and terminators. Parameters/phis remain unknown and layout order may conservatively prevent folding. Known copies, integer operations and bit-pattern-only transforms become constant copies; exceptional integer divisions/remainders remain executable. Floating arithmetic/comparisons/widening are not folded. No DCE, branch simplification, frame compaction, register allocation or full optimizer parity is implied.

The experimental CLI gains `--fold-integers`; legacy `-O0`/compatibility behavior is unchanged. Both native harnesses and CI check normal and folded paths. Twelve additional compile-time-operand arithmetic-fault cases complement the original twelve dynamic cases. Unit tests independently check 2,444 folded constants, chaining/low-word branches, unchanged floating operations, conservative layout and per-function fact ownership, validation-before-mutation and exhaustive failure cleanup. See OPTIMIZE.md.

An earlier integration smoke runner overlapped the first full runner, which could compete when installing compiler build modes. Both superseded process trees were stopped; only the fresh non-overlapping `/data/verify-native-folding-final.log` run is authoritative for this milestone's final mode-by-mode results.

### Integer folding local verification

Pinned Zig Debug, ReleaseSafe and ReleaseFast passed **110/110 unit tests**. Debug was additionally executed directly without run-step caching (`/data/verify-fold-debug-direct.log`, ending `All 110 tests passed`). The authoritative non-overlapping full log is `/data/verify-native-folding-final.log`: in each compiler build mode, **both normal and `--fold-integers` paths** passed **3,370 integer/program native checks**, **3,560 floating/bit-pattern/mixed-ABI native checks**, **24 arithmetic-fault checks**, and **8 CLI checks** per path. Formatting and all eight generators' reproducibility passed. Legacy source/build/tools/tests remain unchanged. CI for the optimizer is checked separately after publication; no release tag or main integration is authorized.


### Integer folding published CI

Optimizer checkpoint `625b18a8561f1dd8c0f854398fad78cc6f7cbb28` passed https://github.com/0x6432/zbe/actions/runs/38878495385: Debug, ReleaseSafe and ReleaseFast all succeeded, including both normal and constant-folded native harness paths. This result precedes liveness below.

## Owned block-boundary liveness

Added independently owned scalar liveness snapshots with standard-library dynamic bitsets, allocator cleanup, checked matrix-storage estimates and bounded queries. Entry parameters and phi results are entry definitions; phi operands are predecessor-edge uses. Both reachable and unreachable blocks are analyzed without inventing edges. Snapshots do not retain IR or CFG pointers and must be rebuilt after mutation. The 64 MiB default matrix cap does not bound separate SSA/CFG scratch or solver runtime. See LIVENESS.md for exact contracts. No register assignment, spill insertion or emitter integration is implemented.

Seven added tests compare every block/value query against a separate per-value use-before-definition path-search oracle on representative scalar/phi fixtures, 64 generated cyclic CFGs and the 32-function mixed corpus. Tests also cover edge-specific phi inputs, snapshot lifetime after module destruction, unreachable local uses, zero-value frames, limits/overflow, invalid SSA and exhaustive allocation-failure cleanup.

### Liveness local verification

Pinned Zig Debug, ReleaseSafe and ReleaseFast each passed **117/117 unit tests**. In each build mode, **both normal and `--fold-integers` paths** passed **3,370 integer/program native checks**, **3,560 floating/bit-pattern/mixed-ABI native checks**, **24 arithmetic-fault checks**, and **8 CLI checks** per path. Formatting and all eight independent generators' reproducibility checks passed. Authoritative non-overlapping log: `/data/verify-native-liveness.log`, ending `LIVENESS VERIFICATION PASSED`. Legacy source/build/tools/tests remain unchanged. Liveness CI is checked separately after publication; no main integration or release tag.


### Liveness published CI

Liveness checkpoint `de65bfddcf733739eff14365686b956edb86f41b` passed https://github.com/0x6432/zbe/actions/runs/38879251679: Debug, ReleaseSafe and ReleaseFast all succeeded. This result precedes interference below.

## Owned scalar-home interference

Added an independently owned, symmetric packed adjacency graph over scalar value IDs. Ordinary results conflict with values live after definition, including dead-result clobbers. Parameter and phi definitions are simultaneous bundles with pairwise conflicts, including unused results. Phi edge uses remain edge-specific; values of different scalar classes are deliberately not filtered. The graph is a conservative target-independent home relation, not a model of machine register aliases, fixed registers, early clobbers, ABI placement or calls. No emitter or IR mutation is performed. See INTERFERENCE.md.

Checked graph/scratch estimates and separate liveness matrix limits each default to 64 MiB. Neither limits combined process memory or execution time. Allocation failures free the graph and all analysis scratch. Liveness and interference use the pinned standard library's current `Dynamic` bitset name instead of its deprecated alias.

Nine added tests cover dead definitions, dying-source reuse, simultaneous phi results and live-through parameters, edge distinction, class-independent entry bundles, snapshot lifetime, empty frames, bounds, exact/separate limits, overflow, invalid SSA, every allocation failure, word-boundary packing, all 32 mixed programs and 32 generated cyclic CFGs. A separate forward use-before-redefinition path-search oracle checks every graph pair and degree without consuming production liveness sets or walking instructions backward.

### Interference local verification

Pinned Zig Debug, ReleaseSafe and ReleaseFast each passed **126/126 unit tests**. In each build mode, **both normal and `--fold-integers` paths** passed **3,370 integer/program native checks**, **3,560 floating/bit-pattern/mixed-ABI native checks**, **24 arithmetic-fault checks**, and **8 CLI checks** per path. Formatting and all eight independent generators' reproducibility checks passed. Authoritative log: `/data/verify-native-interference.log`, ending `INTERFERENCE VERIFICATION PASSED`. Legacy source/build/tools/tests remain unchanged. Interference CI is checked separately after publication; no main integration or release tag.

### Interference published CI

Interference checkpoint `6c2feeba0de0c553162ffe3382e8a8523b849711` passed https://github.com/0x6432/zbe/actions/runs/38879941871: Debug, ReleaseSafe and ReleaseFast all succeeded. This result precedes optional stack-home reuse below.

## Optional interference-colored stack homes

Added owned typed slot layouts using deterministic value-order greedy coloring. They preserve every conservative interference edge, including dead writes and simultaneous parameter/phi bundles, but do not promise minimum colors. All scalar slots remain eight bytes. This is stack storage reuse, not physical register assignment, spill insertion or a full allocator.

The existing `amd64.emit` keeps unique homes by default; `emitWithOptions` and CLI `--reuse-stack-homes` opt into coloring. Operands load before result stores; phi copies still read every input into separate scratch before any result write. Scratch starts after colored homes, and incoming parameters remain distinct. The existing aligned 64 KiB frame cap now applies to colored homes plus scratch in the opt-in path. IR is never mutated by emission, and temporary layouts are freed across functions and errors. Graph/liveness caps remain separate, not total memory/runtime limits. See STACK-HOMES.md.

Ten added unit tests cover proper/contiguous/deterministic coloring, mixed-width/class chains, dead writes, parameter bundles, lifetime/bounds, empty frames, limit/SSA failures, every allocation failure, all mixed programs and phi/float fixtures, default emission, scratch placement and an 8,193-value chain. The initial smoke compile caught a capture shadowing the public `slot` method; it was renamed before the successful 136-test Debug run. No oracle was weakened.

Five new native results cover dying chains, dead writes, a dead phi with a live-through input and a dead incoming parameter. The 301-value chain explicitly verifies default 2,416-byte versus reused 16-byte frames with identical return value. CLI checks increase to twelve, adding unknown/duplicate flag preservation and accepted flag-order identity. Both native harnesses and CI now cover all four combinations of folding and home reuse. No legacy source/build/tool/test changes or release tag.

### Stack-home reuse local verification

Pinned Zig Debug, ReleaseSafe and ReleaseFast each passed **136/136 unit tests** (fresh Debug smoke in `/data/check-stack-homes-debug-fixed.log`; the full runner reused that successful Debug test artifact). In each build mode, **all four folding/reuse flag combinations** passed **3,375 integer/program native checks**, **3,560 floating/bit-pattern/mixed-ABI native checks**, **24 arithmetic-fault checks**, and **12 CLI rejection/output-preservation/flag-order checks** per combination. Formatting and all eight independent generators' reproducibility checks passed. Authoritative full log: `/data/verify-native-stack-homes.log`, ending `STACK HOME REUSE VERIFICATION PASSED`. Legacy source/build/tools/tests remain unchanged. Remote CI is checked separately after publication; no main integration or release tag.

### Stack-home reuse published CI

Stack-home checkpoint `e88da7734bf435d864715735668cadb01cff465e` passed https://github.com/0x6432/zbe/actions/runs/38880861958: Debug, ReleaseSafe and ReleaseFast all succeeded, including all four folding/reuse combinations. This result precedes limited register homes below.

## Optional callee-saved physical homes

Added a typed internal home union and preserved-register enum. CLI/library option `--callee-saved-homes` uses the existing interference coloring, maps the first five colors to RBX/R12/R13/R14/R15 and retains remaining colors in shared stack homes. It implies coloring; explicitly combining both home flags is accepted and redundant. Default unique-stack behavior remains unchanged. All scalar classes use GP raw-bit homes; computation retains existing GP/SSE scratch. This is limited physical assignment, not a complete register allocator, SSE-home selection, live-range splitting or optimal spilling. No calls or new IL instructions are introduced. See PRESERVED-HOMES.md.

The prologue saves the full original contents of only the used preserved registers before parameter homing. Every normal integer/floating/void return restores them after preparing its result. Ordinary stack, phi scratch and saved-register regions are disjoint and included in the existing aligned 64 KiB frame cap. Parameter bundle and phi-edge invariants are unchanged; every phi source is saved to scratch before result commits. Analysis/color storage is freed across functions and allocation failures, and emission never mutates IR.

Five new unit tests cover width-aware raw-bit moves, used-only saves, redundant option identity, disjoint frame regions, simultaneous phi rotation, multiple return paths, empty functions, frame overflow, floating/void result restoration and exhaustive allocation failures across functions. A separate native assembly adapter seeds all five registers with distinct full-width patterns, calls generated code, checks all 64 bits and restores its own caller. The seven-phi fixture forces both physical and stack homes even under folding. Native expectations add direct sum 21 and preservation result zero; CLI checks add duplicate new-flag rejection and all six accepted flag permutations. Both native harnesses and CI cover all eight flag combinations in each compiler build mode.

### Entry-edge safety audit before publication

The first limited-register verification passed 141 unit tests and all eight native flag combinations in each build mode, but is **superseded** as the final publication record. Further audit found that QBE forbids every jump to a function's first block (`doc/il.txt`, Jumps), while the new scalar verifier had accepted such CFGs. The parameter-definition convention in liveness is unsound for those invocation-entry backedges. A bounded native probe (`/data/probe-entry-backedge.log`) confirmed the issue: for a fixed nonzero parameter, unique homes timed out as the IL loop dictates, but reused and preserved homes returned 7 after a dead definition overwrote the parameter. This also affects the previously published opt-in reuse checkpoint for that invalid-QBE input. It is not a change to valid QBE loop semantics.

Added `EntryHasPredecessors` before dominance/liveness/folding/execution/emission; even an unreachable predecessor is rejected. The low-level CFG/dominator APIs still analyze general graphs. A committed reproducer and new verifier/cross-pipeline tests protect every SSA-dependent API and all three emission modes. CLI checks increase from thirteen to fifteen by testing no-output creation and existing-output preservation for this error in every flag combination. Generated liveness/interference cycles now loop among non-entry blocks, retaining oracle comparisons and cycle coverage while satisfying QBE's entry contract. The valid infinite-execution budget fixture gains a separate invocation entry, and entry-phi rejection is checked independently of backedge rejection. No arithmetic oracle or legacy compiler was changed.

The boundary-fix smoke initially caught two existing fixtures expecting the former entry-backedge behavior; both were updated to test their original intended properties on valid-entry graphs. A fresh non-overlapping `/data/verify-native-preserved-homes-final.log` run is the authoritative final verification for this milestone.


### Limited register homes and entry-boundary final verification

The authoritative non-overlapping `/data/verify-native-preserved-homes-final.log` ended `PRESERVED HOME VERIFICATION PASSED`. Pinned Zig Debug, ReleaseSafe and ReleaseFast each passed **143/143 unit tests**. In every build mode, **all eight flag combinations** passed **3,377 integer/program native checks**, **3,560 floating/bit-pattern/mixed-ABI native checks**, **24 arithmetic-fault checks**, and **15 CLI rejection/output-preservation/flag-order checks** per combination. All 24 completions of each native suite were counted explicitly. Formatting and all eight independent generators' reproducibility checks passed. This supersedes the pre-audit 141-test run. Legacy source/build/tools/tests remain unchanged. CI is checked separately after publication; main integration and release tags remain unauthorized.

### Limited register homes published CI

Checkpoint `8f55f534dc74a1f62a0a56ea5d12ca6ff5e7c987` passed https://github.com/0x6432/zbe/actions/runs/38904948145: Debug, ReleaseSafe and ReleaseFast all succeeded, including 143 unit tests, all eight native flag combinations and entry-edge rejection/output-preservation coverage. This result precedes halt support below.

## Explicit halt termination

Added payload-free `Terminator.halt`, frontend `hlt`, operand-free structural/SSA handling, no CFG successors, no terminator liveness uses and no synthetic return value. It is valid for void or any scalar-result function. Interpretation consumes a terminator step and returns typed `Halted`, preserving budget exhaustion and preceding arithmetic-fault precedence. Linux AMD64 emits `ud2`, matching the legacy target's termination instruction, not privileged hardware `hlt`. Halting is abnormal program termination, not an ABI return or portable cross-target signal guarantee. No calls, memory or new targets are added. See HALT.md.

Four added tests cover every result class, block closure/arity, conditional return versus halt, exact budget boundaries, earlier division faults and exhaustive allocation cleanup through parsing/CFG/liveness/interference/coloring/folding/evaluation/all home modes. Existing independent analysis path-search oracle tests now include the halt fixture. The native harness adds conditional return 42 and four separate termination/ordering subprocesses: direct halt, conditional halt and successful division followed by halt require SIGILL; division by zero before halt requires SIGFPE. Core dumps remain disabled and timeouts finite. Existing arithmetic, floating, ABI, bit-pattern and CLI expectations remain intact.


### Halt local verification

Pinned Zig Debug, ReleaseSafe and ReleaseFast each passed **147/147 unit tests** (fresh Debug smoke in `/data/check-halt-debug.log`, reused by the full runner; fresh release-mode results in the full log). Authoritative `/data/verify-native-halt.log` ended `HALT VERIFICATION PASSED`. In every build mode, **all eight flag combinations** passed **3,378 integer/program native checks**, **3,560 floating/bit-pattern/mixed-ABI native checks**, **24 arithmetic-fault checks**, **4 termination/ordering checks**, and **15 CLI rejection/output-preservation/flag-order checks** per combination. All 24 completions of each suite were counted. Formatting and all eight independent generators' reproducibility passed. Legacy source/build/tools/tests remain unchanged. CI is checked separately after publication; no main integration or release tag.

### Halt published CI

Halt checkpoint `f69ccbb85b54523c0771d1f30b9ccc06d37c9210` passed https://github.com/0x6432/zbe/actions/runs/38906265283: Debug, ReleaseSafe and ReleaseFast all succeeded, including 147 unit tests and all eight native flag combinations with termination/ordering checks. This result precedes typed argument classification below.

## Typed base-scalar AMD64 argument locations

Extracted the existing incoming-argument ABI logic into allocation-free per-signature cursors with typed GP/vector/stack locations, semantic register names and checked positive stack displacements. Register banks still exhaust independently and share overflow slots in declaration order. The emitter no longer maintains its own parallel GP/SSE/stack counters. This adds no calls, aggregate/extended ABI classes, varargs or new targets. The separate 64 KiB frame cap and home strategies are unchanged. See ABI-AMD64.md.

Four new unit tests cover width-specific names, independent cursor instances, displacement boundaries, forged stack IDs and failure atomicity. An independent prefix-count oracle checks every one of 65,536 sixteen-argument integer-versus-floating class patterns, with scalar widths alternated within each class and explicit result-tag checks. This is exhaustive class-pattern coverage for that length, not all four-type sequences or arbitrary signature lengths. Existing weighted native mixed-ABI checks and all eight compiler pipelines remain intact.

### Typed argument classifier local verification

Authoritative `/data/verify-native-abi-classifier.log` ended `ABI CLASSIFIER VERIFICATION PASSED`. Pinned Zig Debug, ReleaseSafe and ReleaseFast each passed **151/151 unit tests**. Each mode passed all eight flag combinations: **3,378 integer/program**, **3,560 floating/bit-pattern/mixed-ABI**, **24 arithmetic-fault**, **4 termination/ordering**, and **15 CLI** checks per combination. All 24 completions of each suite were counted. Formatting and all eight independent generator reproducibility checks passed. Legacy source/build/tools/tests remain unchanged. Publication CI is checked separately; no main integration or release tag.

### Typed argument classifier published CI

Checkpoint `68a4588756ff280b478089117e32d0b064db7025` passed https://github.com/0x6432/zbe/actions/runs/38907759638: Debug, ReleaseSafe and ReleaseFast all succeeded, including 151 unit tests and all eight existing native option combinations. The public API poll initially hit its anonymous rate limit; an authenticated read verified the exact SHA and all three successful jobs. This result precedes direct-call support below.

## Direct nonvariadic scalar-result calls

Added owned typed `Instruction.call` arguments and failure-atomic pending-result construction; deinitialization frees each owned argument slice. Scalar validation/SSA/liveness/interference now check every call argument. Integer folding treats calls as effectful unknowns, retaining even calls with unused results. The standalone interpreter explicitly returns `UnsupportedCall` only on a reached call after consuming its step; it never invokes host code. Internal-call interpretation is not implemented. See CALLS.md for the precise subset and API/ownership contracts.

Linux SysV AMD64 lowering marshals typed GP/SSE/shared overflow arguments with the existing classifier and saves scalar results from RAX/XMM0. Persistent homes are exclusively stack or callee-saved registers; all survive a conforming call. A maximum outgoing stack area is reserved below homes/phi scratch/saved originals and included in the aligned 64 KiB cap. Known module-local signatures must match exact base-scalar result/argument types and count; all module bodies are validated before traversing known callee parameter IDs. External signatures remain a caller contract. Void-result/indirect/variadic/environment/aggregate/extended-ABI calls remain unsupported. Native recursion has ordinary process limits, not interpreter guards.

Added unit tests for ownership, allocation-failure retry/cleanup, SSA/unsupported forms, invalid symbols, known-signature mismatches, malformed later definitions, effect/budget behavior and outgoing-frame cap/separation. Independent liveness/interference oracles now include a call-containing loop fixture. Separate native harness covers 128 signatures with three value sets, two successive calls, both mixed-bank overflow orders, all scalar return classes, internal/mutual recursion, raw floating payloads, observable discarded-result calls, phi/outgoing frame coexistence, alignment, full-width preserved-register checks and live values across explicit destruction of all volatile GP/SSE registers. It reports 466 native checks plus six signature rejection/output-preservation checks. CI adds it to all eight option combinations in every build mode. Verification follows below when complete.

### Direct-call local verification

Pinned Zig Debug passed **159/159 unit tests** freshly in `/data/check-direct-calls-debug.log`, followed by all eight call-suite flag combinations. The authoritative non-overlapping `/data/verify-native-direct-calls.log` reused that unchanged Debug test result from Zig's cache and freshly passed **159/159** in ReleaseSafe and ReleaseFast; it ended `DIRECT CALL VERIFICATION PASSED`. In every build mode all eight option combinations passed **3,378 integer/program**, **3,560 floating/bit-pattern/mixed-ABI**, **466 direct-call/ABI/effect**, **24 arithmetic-fault**, **4 termination/ordering**, **15 existing CLI**, and **6 call-signature rejection/output-preservation** checks per combination. All 24 suite completions were counted. Formatting and all eight independent generator reproducibility checks passed. The first frame-separation assertion draft incorrectly expected a store into the first default value home; it was corrected to check each mode's actual distinct phi-scratch region before these final runs. No implementation failure was hidden by that assertion correction. Legacy source/build/tools/tests remain unchanged. Publication CI is checked separately; no main integration or release tag.

### Direct-call published CI

Checkpoint `acf47d2b809ad80c30d1bc7d3c586fc4e590b95d` passed https://github.com/0x6432/zbe/actions/runs/38910672675: Debug, ReleaseSafe and ReleaseFast all succeeded, including 159 unit tests and all eight native option combinations with the 466-check direct-call suite and signature output-preservation checks. This result precedes module-local interpretation below.

## Bounded module-local call interpretation

Added `interpreter.evaluateModule` with target-independent module SSA/call-signature validation and an explicit owned invocation-frame stack. Self/mutual/forward direct calls execute only module-owned scalar functions; reached undefined externals return `UnsupportedExternalCall`, never host invocation or native fallback. Standalone `evaluate` retains reached-call `UnsupportedCall`. Both APIs now share the same iterative scalar engine. Each invocation owns values and parallel-phi scratch; argument copies and completed/active frames are freed across every exit. No handle-array pointer survives array growth. IL recursion does not recurse through the host Zig stack. See MODULE-EVALUATION.md.

One 100,000-default step budget spans all invocations. New `max_call_depth` defaults to 64 active frames including the root; zero rejects execution and known internal pushes at the limit fail with `CallDepthLimitExceeded`. These are not total memory/analysis/native limits. Callee halt/arithmetic errors propagate, and root/step/type errors remain explicit. Shared `module_validation.validate` replaces the native emitter's duplicate body/signature traversal while leaving assembly-symbol spelling checks in the target emitter.

Seven new tests cover exact global budgets, root-inclusive depth, invalid entry/argument errors, 1,001-frame recursive sum and relocation, mutual forward recursion, all raw scalar classes/NaN payloads, nested/caller phi loops, undefined externals not executed, halt/arithmetic/void propagation, target-independent validation and exhaustive allocation failures through nested frames/argument copies/growth/phi scratch/early exits. Debug smoke passed 166/166 unit tests; full verification follows when complete.

### Module-local evaluation local verification

Debug freshly passed **166/166 unit tests** in `/data/check-module-eval-debug.log`; the authoritative non-overlapping `/data/verify-native-module-eval.log` reused that unchanged Debug result and freshly passed **166/166** in ReleaseSafe and ReleaseFast. It ended `MODULE EVALUATION VERIFICATION PASSED`. In each build mode all eight option combinations passed **3,378 integer/program**, **3,560 floating/bit-pattern/mixed-ABI**, **466 direct-call/ABI/effect**, **24 arithmetic-fault**, **4 termination/ordering**, **15 existing CLI**, and **6 call-signature rejection/output-preservation** checks. All 24 completions per suite were counted. Formatting and all eight independent generator checks passed. Legacy source/build/tools/tests remain unchanged. CI is checked separately after publication; no main integration or release tag.

### Module-local evaluation published CI

Checkpoint `b04aecb2c2ad351c0c2302b606f76e3074b7680f` passed https://github.com/0x6432/zbe/actions/runs/38912641015: Debug, ReleaseSafe and ReleaseFast all succeeded, including 166 unit tests and all eight native option combinations. This result precedes void-result calls below.

## Genuine void-result direct calls

Made call results optional and `Instruction.result()` return `?ValueId`. Added failure-atomic `appendVoidCall` with owned typed arguments; no SSA value, dummy constant or home is created. Factored argument parsing so result-bearing and void statement calls share the same strict direct/nonvariadic scalar-argument grammar. Known target result presence/type must match; omitting a known nonvoid result or binding a void target fails `CallSignatureMismatch`. Scalar reverse-definition checks reject orphaned old results if a pass improperly removes a call destination. See CALLS.md.

Liveness/interference always retain arguments as uses but add/kill definitions only when present; independent path/program-point oracles include new void fixtures. Integer folding skips resultless effects without removing them. AMD64 marshals the same arguments/outgoing stack but never reads/saves return registers for void calls. Module interpretation resumes void callers without fabricated result writes, using the same owned frame/depth/step machinery. Unsupported indirect/varargs/environment/aggregate/extended ABI forms stay rejected. Old nonvoid-only test fixtures now unwrap the optional accessor explicitly; the old rejected void statement was replaced with an actually unsupported indirect void call.

Six new tests cover zero-value frames/homes, observable effect retention, exact void budgets/depth, recursive void execution, argument-only liveness, malformed SSA/known signatures/orphaned definitions, statement block closure, builder retry/ownership, outgoing-only frame cap and exhaustive allocation cleanup. The native call harness adds genuine C void effects, nested/recursive internal calls, empty-SSA functions, mixed overflow arguments and live/preserved homes; totals become 474 native call/ABI/effect and ten signature rejection/output-preservation checks per option combination. Verification follows when complete.

### Void-result call local verification

Debug freshly passed **172/172 unit tests** in `/data/check-void-calls-debug.log` and all eight call-harness option combinations. The authoritative non-overlapping `/data/verify-native-void-calls.log` reused that unchanged Debug unit result and freshly passed **172/172** in ReleaseSafe and ReleaseFast; it ended `VOID CALL VERIFICATION PASSED`. Each build mode passed all eight combinations: **3,378 integer/program**, **3,560 floating/bit-pattern/mixed-ABI**, **474 direct-call/ABI/effect**, **24 arithmetic-fault**, **4 termination/ordering**, **15 existing CLI**, and **10 call-signature rejection/output-preservation** checks per combination. All 24 suite completions were counted. Formatting and all eight independent generator reproducibility checks passed. Legacy source/build/tools/tests remain unchanged. CI is checked separately after publication; no main integration or release tag.

### Void-result call published CI

Checkpoint `8fb54e45258ea655ae3d06abcb7c33c34585fa9f` passed https://github.com/0x6432/zbe/actions/runs/38914200760: Debug, ReleaseSafe and ReleaseFast all succeeded, including 172 unit tests and all eight native option combinations with void-effect and signature-preservation checks. This result precedes indirect calls below.

## Typed long-address indirect calls

Replaced the symbolic-only callee field with `CallTarget.symbol`/`.address` and retained optional scalar/void results plus owned argument slices. Existing direct builders retain their API; indirect counterparts share failure-atomic construction. Address targets must be long operands and participate in structure/SSA/liveness/interference like other uses, including target-only liveness. Known symbolic signatures remain checked; indirect address validity/signature is a native caller contract, not a linker or runtime safety proof. No environment/varargs/aggregate/extended ABI support is added. See INDIRECT-CALLS.md.

AMD64 captures the full address in R11 before marshalling arguments through RAX, then emits `call *%r11`. R11 is not a persistent home or argument register. Direct calls, outgoing frames, result homing and effect-only behavior are unchanged. Module interpretation returns `UnsupportedIndirectCall` for any reached address target without dereferencing or invoking it; standalone calls retain `UnsupportedCall`. Generated native programs are not sandboxed, and invalid addresses/signatures remain invalid native programs. Literal-null fixtures are compiled/validated but never executed natively.

Five added unit tests cover target types/representation/order/dominance, scalar/void builder retry and ownership, target-only liveness, target-before-argument emission, interpreter refusal and exhaustive cleanup. Independent analysis oracles include indirect fixtures. Native calls expand to 890 call/ABI/effect checks (existing 474 plus mixed signatures, callback recursion, target-as-argument, void callbacks, raw payloads and preserved registers), with ten symbolic-signature rejection checks. This harness now links PIE and explicitly checks high callback address bits to expose truncation; other integer/float harnesses retain non-PIE checks. C pointer/integer conversion is an explicit Linux AMD64 test convention, not portable-C or full PIC/ABI support. Verification follows when complete.

### Indirect-call local verification

Debug freshly passed **177/177 unit tests** and all eight call-harness option combinations in `/data/check-indirect-calls-debug.log`. The authoritative non-overlapping `/data/verify-native-indirect-calls.log` reused that unchanged Debug unit result and freshly passed **177/177** in ReleaseSafe and ReleaseFast; it ended `INDIRECT CALL VERIFICATION PASSED`. Each build mode passed all eight combinations: **3,378 integer/program**, **3,560 floating/bit-pattern/mixed-ABI**, **890 call/ABI/effect**, **24 arithmetic-fault**, **4 termination/ordering**, **15 existing CLI**, and **10 symbolic-signature rejection/output-preservation** checks per combination. All 24 suite completions were counted. The call harness's PIE/high-address precondition passed in every combination; other native suites retain their existing non-PIE linking. Formatting and all eight independent generator checks passed. Legacy source/build/tools/tests remain unchanged. CI is checked separately after publication; no main integration or release tag.

### Indirect-call published CI

Checkpoint `c46e03cc75a1bcd6d4d0275cd2357efacfdb0ede` passed https://github.com/0x6432/zbe/actions/runs/38915982770: Debug, ReleaseSafe and ReleaseFast all succeeded, including 177 unit tests and all eight native option combinations with 890 call/ABI/effect checks and ten symbolic-signature rejection checks. This result precedes scalar memory support below.

## Typed scalar loads and effect-only stores

Added semantic `LoadKind`/`StoreKind`, long-address load/store instructions, failure-atomic builders and strict parser forms. Small loads sign/zero-extend to word or long; `loadw` exactly aliases `loadsw` as confirmed in the unchanged C reference parser. Byte/half stores truncate word sources. Stores define no value. Structural/SSA checks and every production/independent liveness/interference operand visitor include memory uses. Integer folding treats all loads as unknown and retains both load faults and store effects without reordering. See MEMORY.md.

AMD64 captures full addresses in R10, moves raw bits through RAX and accesses exactly the declared byte width. Unsigned loads to long clear high bits with EAX writes. Scratch registers are never persistent homes. Both evaluators consume the access step then return `UnsupportedMemory`, never dereferencing supplied numeric addresses; a simulated address space is not implemented. Native valid extent/lifetime/permissions remain a caller contract, not sandboxing. Allocation/blits/globals/atomics/full memory semantics and target parity remain missing.

Six new unit tests cover all access classes, invalid parser forms, effect-only stores, builder allocation retry/closed blocks, malformed SSA/dominance, memory liveness, fold retention, evaluator refusal/budget and exhaustive pipeline allocation failures. The native memory harness independently checks 55,198 outcomes (narrow signed/unsigned loads, full-buffer sentinel stores, all offsets, page boundaries, raw floating bits, loops/calls/aliasing/high-pressure homes/literal stores/preserved registers), two guard-page SIGSEGV retention cases and eight CLI rejection/output-preservation cases per option combination. It requires high mapped address bits under PIE. An initial Zig capture-name shadowing error was corrected before tests; no semantic mismatch was hidden. Verification follows when complete.

### Scalar-memory local verification

Debug freshly passed **183/183 unit tests** in `/data/check-memory-debug.log`; the final eight-option Debug memory smoke in `/data/check-memory-native.log` passed after adding high-pressure homes/stack arguments. The authoritative non-overlapping `/data/verify-native-scalar-memory.log` reused the unchanged Debug unit result and freshly passed **183/183** in ReleaseSafe and ReleaseFast; it ended `SCALAR MEMORY VERIFICATION PASSED`. Each build mode passed all eight combinations: **3,378 integer/program**, **3,560 floating/bit-pattern/mixed-ABI**, **890 call/ABI/effect**, **55,198 scalar-memory**, **24 arithmetic-fault**, **4 termination/ordering**, **2 memory fault-retention**, **15 existing CLI**, **10 symbolic-signature rejection/output-preservation** and **8 memory rejection/output-preservation** checks per combination. All 24 suite completions were counted. Memory page-boundary and PIE/high-address prerequisites passed in every combination. Formatting and all eight independent generator reproducibility checks passed. Legacy source/build/tools/tests remain unchanged. Publication CI is checked separately; no main integration or release tag.

### Scalar-memory published CI

Checkpoint `d634ca706c69c00927f9607a2beeafae172de754` passed https://github.com/0x6432/zbe/actions/runs/38918777380: Debug, ReleaseSafe and ReleaseFast all succeeded, including 183 unit tests and all eight native option combinations with 55,198 scalar-memory checks, two memory fault-retention checks and eight memory rejection/output-preservation checks. This result precedes optional memory-image interpretation below.

## Optional owned simulated memory for interpretation

Added allocator-owned, fixed-size, zero-initialized `memory.Image` with nonzero synthetic base, explicit little/big byte order, checked extents/address arithmetic and no host-address casts. Typed read/write APIs implement raw bits and signed/unsigned extensions; entire access validation precedes writes. Empty images and an image ending at the last u64 address are handled explicitly. Zero initialization is an API choice, not a claim about future native allocation IL. See MEMORY-EVALUATION.md.

Both evaluator APIs borrow optional `Options.memory_image`; all module-local frames share it and each memory instruction consumes one ordinary step. Without an image the published `UnsupportedMemory` boundary is unchanged. Memory errors do not dereference host addresses. Completed stores persist across later failure/return/repeated invocation; only a failing individual write is mutation-free, not an invocation transaction. Host/external/indirect calls remain refused. No allocation/globals/blits/permissions/provenance/concurrency model or native checking is added.

Six new tests cover owned range/null/overflow/empty/last-u64 handling, class and no-partial-write errors, 1,472 independent Python load/store byte-order cases at eight offsets through image and parsed interpreter APIs, nested shared-image calls and loop phis, repeated/folded evaluation, retained writes across bounds/arithmetic/halt/step/external errors, depth limits and exhaustive allocation cleanup. The ninth generator verifies its fixture independently; existing native harnesses/oracles remain unchanged. Debug freshly passed 189/189 unit tests. Full verification follows when complete.

### Memory-image local verification

Debug freshly passed **189/189 unit tests** in `/data/check-memory-image-debug.log`; the authoritative non-overlapping `/data/verify-native-memory-image.log` reused that unchanged Debug result and freshly passed **189/189** in ReleaseSafe and ReleaseFast. It ended `MEMORY IMAGE VERIFICATION PASSED`. Every build mode passed all eight flag combinations with the unchanged **3,378 integer/program**, **3,560 floating/bit-pattern/mixed-ABI**, **890 call/ABI/effect**, **55,198 scalar-memory**, **24 arithmetic-fault**, **4 termination/ordering**, **2 memory fault-retention**, **15 existing CLI**, **10 symbolic-signature rejection/output-preservation** and **8 memory rejection/output-preservation** checks per combination. All 24 native suite completions were counted. Formatting and all **nine** independent generator reproducibility checks passed, including 1,472 memory-image cases exercised at eight offsets in unit tests. Legacy source/build/tools/tests remain unchanged. CI is checked separately after publication; no main integration or release tag.

### Memory-image published CI

Checkpoint `75710b91a18505a78c8da9ce9e9d2f12f149555d` passed https://github.com/0x6432/zbe/actions/runs/38920912217: Debug, ReleaseSafe and ReleaseFast all succeeded, including 189 unit tests, all nine independent generators and all eight native option combinations. This result precedes blit support below.

## Constant-length effect-only byte blits

Added typed blit source/destination operands and an explicit `u31` nonnegative signed-word byte count, failure-atomic builder and strict decimal count parsing without modulo wrapping. Both addresses participate in structural/SSA/liveness/interference checks, including zero-count uses and independent analysis oracles. Blits have no result/home and remain ordered effects under integer folding. This intentionally does not reproduce the unchanged C reference parser's smaller packed 29-bit-reference count limit. See BLITS.md for the precise boundary.

AMD64 emits compact `rep movsb` with RSI/RDI/RCX caller-saved scratch, relying on SysV's clear-DF contract and leaving persistent homes intact. Zero counts emit no accesses; native invalid extents/partial overlap remain invalid programs without bounds/overlap checks or fault rollback. The optional simulated image checks both whole spans and rejects partial overlap before mutation; identical valid spans and zero-count invalid addresses are no-ops. No-image evaluation still refuses reached blits, including zero, after consuming the instruction step. One step is not a per-byte/time budget.

Six new unit tests cover builders, parser types/counts/overflow/arity, maximum-count constant-size assembly, whole-span/no-partial-write/alias/zero semantics, SSA/liveness/effect retention, nested image calls and exact budgets/default refusal, plus exhaustive pipeline allocation cleanup. Debug passed 195/195 tests. The fifth native harness passes 3,041 byte-copy/offset/boundary/preserved-register/stack-pointer-pressure results, two protected-memory SIGSEGV cases and twelve rejection/output-preservation checks in each of eight Debug option combinations. Partial overlaps are not executed natively. An initial reserved-word test identifier was corrected before passing verification. Full verification follows when complete.

### Blit local verification

Debug freshly passed **195/195 unit tests** in `/data/check-blit-debug.log`, and `/data/check-blit-native.log` passed all eight new native-harness flag combinations. The authoritative non-overlapping `/data/verify-native-blit.log` reused that unchanged Debug unit result and freshly passed **195/195** in ReleaseSafe and ReleaseFast; it ended `BLIT VERIFICATION PASSED`. Every build mode passed all eight combinations: **3,378 integer/program**, **3,560 floating/bit-pattern/mixed-ABI**, **890 call/ABI/effect**, **55,198 scalar-memory**, **3,041 blit**, **24 arithmetic-fault**, **4 termination/ordering**, **2 memory fault-retention**, **2 blit memory-fault**, **15 existing CLI**, **10 symbolic-signature rejection/output-preservation**, **8 memory rejection/output-preservation** and **12 blit rejection/output-preservation** checks per combination. All 24 native suite completions were counted. Formatting and all nine independent generator checks passed. Legacy source/build/tools/tests remain unchanged. Publication CI is checked separately; no main integration or release tag.

### Blit published CI

Checkpoint `6bb27b5e32733193f93f082f86dd5f074c70c563` passed https://github.com/0x6432/zbe/actions/runs/38922644173: Debug, ReleaseSafe and ReleaseFast all succeeded, including 195 unit tests, all nine independent generators and all eight option combinations of all five native harnesses. This result precedes shared production operand iteration below.

## Allocation-free scalar instruction-use iterator

Added `Instruction.operands()` returning copied fixed operands plus a borrowed function-owned call-argument tail. It yields only scalar uses, with indirect target before arguments and stable operand order; repeated exhaustion returns null. There are no temporary-payload pointers/slices, allocations, numeric packing or owner-lifetime extension. Production SSA/liveness/interference use this shared accessor; phi/terminator and definition handling are unchanged. Independent path/program-point oracles deliberately keep separate exhaustive use switches. See OPERANDS.md.

Three tests cover every fixed tag and explicit tag-count coverage, result exclusion/order/repeated exhaustion, scalar/void and direct/indirect calls at all zero-through-four argument counts/classes, target-only calls, and copied operands surviving overwritten/temporary instruction values. A test reflection spelling was updated for the pinned Zig API before verification. This cleanup is not a performance or full-compiler/100%-idiomatic claim. Verification follows when complete.

### Operand-iteration local verification

Debug freshly passed **198/198 unit tests** in `/data/check-operands-debug.log`. The authoritative non-overlapping `/data/verify-native-operands.log` reused that unchanged Debug result and freshly passed **198/198** in ReleaseSafe and ReleaseFast; it ended `OPERAND ITERATION VERIFICATION PASSED`. Each build mode passed all eight flag combinations with unchanged **3,378 integer/program**, **3,560 floating/bit-pattern/mixed-ABI**, **890 call/ABI/effect**, **55,198 scalar-memory**, **3,041 blit**, **24 arithmetic-fault**, **4 termination/ordering**, **2 memory fault-retention**, **2 blit memory-fault**, **15 existing CLI**, **10 symbolic-signature rejection/output-preservation**, **8 memory rejection/output-preservation** and **12 blit rejection/output-preservation** checks per combination. All 24 native suite completions were counted. Formatting and all nine independent generator reproducibility checks passed. The independent analysis use switches remain unchanged by this refactor. Legacy source/build/tools/tests remain unchanged. Publication CI is checked separately; no main integration or release tag.

### Operand-iteration published CI

Checkpoint `754a537ddaf63c247eb0916f9dc1b5d7151ad7c3` passed https://github.com/0x6432/zbe/actions/runs/38924830652: Debug, ReleaseSafe and ReleaseFast all succeeded, including 198 unit tests, all nine independent generators and all eight option combinations of all five native harnesses. This result precedes signed numeric conversions below.

## Explicit signed numeric integer/floating conversions

Added semantic `ConvertOp` and typed `Instruction.convert` for `swtof`, `sltof`, `stosi`, `dtosi`, separate from non-fallible raw-bit unary operations. Failure-atomic builders, strict parser classes, structure/SSA/shared-use iteration and independent analysis use switches cover the operand/result. Integer folding preserves conversions as unknown executable instructions, including unused error-producing results. Unsigned conversion and the existing `truncd` discrepancy remain unsupported/unresolved. See SIGNED-CONVERSIONS.md.

Pure signed conversion semantics retain strict f32/f64 widths. Float-to-signed checks finite truncated values against exact signed bounds before any host integer cast, returning `ConversionOutOfRange` for invalid domains. Checking after truncation deliberately accepts double -2147483648.5 -> i32 MIN. Native AMD64 uses width-specific cvtsi2ss/sd and cvttss/sd2si with raw RAX/XMM0 transfers; no native checked/saturating error convention is invented. Only defined-value nearest-even tests are claimed; out-of-domain native invalid results/exceptions and full floating-environment parity remain outside the contract.

Six tests cover independent exact expectations, invalid domains, builder/class/structure/SSA checks, unused conversion and budget precedence, loop phis/folding, all home strategies and exhaustive allocation cleanup. A tenth generator adds 512 exact Fraction-derived cases; existing oracles are unchanged. The sixth native harness checks 521 defined outcomes (512 oracle plus loops/ABI pressure/internal call/preserved registers/safe branch) and twelve rejection/output-preservation cases per option combination. Full verification follows when complete.

### Signed-conversion local verification

Debug freshly passed **204/204 unit tests** and all eight numeric-harness flag combinations in `/data/check-signed-conversions-debug.log`. The authoritative non-overlapping `/data/verify-native-signed-conversions.log` reused that unchanged Debug unit result and freshly passed **204/204** in ReleaseSafe and ReleaseFast; it ended `SIGNED NUMERIC CONVERSION VERIFICATION PASSED`. Every build mode passed all eight combinations: **3,378 integer/program**, **3,560 floating/bit-pattern/mixed-ABI**, **890 call/ABI/effect**, **55,198 scalar-memory**, **3,041 blit**, **521 signed numeric-conversion**, **24 arithmetic-fault**, **4 termination/ordering**, **2 memory fault-retention**, **2 blit memory-fault**, **15 existing CLI**, **10 symbolic-signature rejection/output-preservation**, **8 memory rejection/output-preservation**, **12 blit rejection/output-preservation** and **12 numeric rejection/output-preservation** checks per combination. All 24 native suite completions were counted. Formatting and all **ten** independent generator checks passed. The preliminary numeric smoke before the loop fixture had 516 results; the complete final runs use 521. Legacy source/build/tools/tests remain unchanged. CI is checked separately after publication; no main integration or release tag.


### Signed-conversion published CI

Checkpoint `e7bcab2b2b2630b7ee25ce431d565b891660ec8a` passed https://github.com/0x6432/zbe/actions/runs/38927185213: Debug, ReleaseSafe and ReleaseFast all succeeded, including 204 unit tests, all ten independent generators and all eight option combinations of all six native harnesses. This result precedes unsigned numeric conversions below.


## Explicit unsigned numeric integer/floating conversions

Added `uwtof`, `ultof`, `stoui`, `dtoui` as typed semantic conversion variants, reusing the failure-atomic builder, operand iterator and owned scalar IR. Unsigned float-to-integer evaluation rejects nonfinite/out-of-range truncated values before host casts, including an exclusive 2^32/2^64 upper bound; negative fractions truncating to zero are accepted. Unused conversions remain executable. Precision narrowing is still unsupported. See UNSIGNED-CONVERSIONS.md.

Native AMD64 zero-extends words before signed-64 SSE conversion; unsigned long uses lower-half direct conversion or high-half sticky-halving/doubling. Float-to-word uses signed-64 truncation; float-to-long uses an exact 2^63 split/subtraction/high-bit restoration. Scratch remains caller-saved, conversion labels use function/result identities, and defined-value nearest-even results are the claim—not invalid-input/error/exception-flag or all-rounding-mode parity. Existing signed lowering was moved into the same typed emission helper without changing its algorithm.

Six tests add 1,024 independent exact Fraction expectations, unsigned domain/class/builder/SSA/budget/unused-effect checks, loop phis/folding and exhaustive allocation cleanup. The independent analysis corpora include the new fixtures. Debug freshly passed **210/210 unit tests** in `/data/check-unsigned-conversions-debug.log`. All eight Debug native numeric flag combinations passed **1,554 defined results** and **20 rejection/output-preservation checks** each in `/data/check-unsigned-conversions-native.log`. A copied fixture filename typo was corrected before these successful runs. The existing signed fixture/oracle is unchanged. Full three-build verification follows when complete; no main merge or tag.


### Unsigned-conversion local verification

Debug freshly passed **210/210 unit tests** in `/data/check-unsigned-conversions-debug.log`, plus all eight numeric native combinations in `/data/check-unsigned-conversions-native.log`. The authoritative non-overlapping `/data/verify-native-unsigned-conversions.log` reused that unchanged Debug result and freshly passed **210/210** in ReleaseSafe and ReleaseFast; it ended `UNSIGNED NUMERIC CONVERSION VERIFICATION PASSED`. Every build mode passed all eight combinations: **3,378 integer/program**, **3,560 floating/bit-pattern/mixed-ABI**, **890 call/ABI/effect**, **55,198 scalar-memory**, **3,041 blit**, **1,554 signed/unsigned numeric-conversion**, **24 arithmetic-fault**, **4 termination/ordering**, **2 memory fault-retention**, **2 blit memory-fault**, **15 existing CLI**, **10 symbolic-signature rejection/output-preservation**, **8 memory rejection/output-preservation**, **12 blit rejection/output-preservation** and **20 numeric rejection/output-preservation** checks per combination. All 24 completions of every native suite were counted. Formatting and all **eleven** independent generator checks passed. Previous signed oracle/generator files and all legacy source/build/tools/tests remain unchanged. Publication CI is checked separately; no main integration or release tag.


### Unsigned-conversion published CI

Checkpoint `385aa0ccdcf404f80e1a4be296822aa57129bc7c` passed https://github.com/0x6432/zbe/actions/runs/38929060288: Debug, ReleaseSafe and ReleaseFast all succeeded, including 210 unit tests, all eleven independent generators and all eight option combinations of all six native harnesses. This result precedes explicit low-word operand projections below.

## Explicit long-to-word scalar operand projections

Added `Operand.low_word: ValueId`, with checked long-source/word-result type and a shared source-reference accessor. Frontend long-in-word subtyping now creates this explicit projection without changing source definitions, allocating hidden values or permitting reverse implicit widening. SSA, phi-edge liveness, interference, interpreter, known integer facts and AMD64 home loads retain the original source dependency; independent analysis oracles keep separate operand switches. See LOW-WORD.md.

The upstream Subtyping paragraph contradicts itself in one sentence; unchanged C reference probes confirm long-to-word arithmetic, shift counts and returns, plus rejection of word-to-long addition. This implementation follows those probes and the explicit IL examples, not guessed extension semantics. Existing signed/unsigned numeric and arithmetic oracle fixtures are unchanged. Former parser/numeric/memory/call rejection fixtures that are now legal long-in-word contexts were replaced with genuinely invalid floating classes, retaining their negative checks. Initial smoke caught two additional obsolete negative fixtures and one expected mixed-call sum typo; these were corrected before successful verification is claimed.

Seven new unit/iterator tests and a twelfth generator cover 1,024 exact Python operation cases, source/type/bounds/builder/SSA checks, normal/phi-edge uses, mixed calls/returns/stores/numeric/casts, loop phis, source preservation, folding/fault behavior and exhaustive allocation cleanup. The seventh native suite is designed for 2,114 outcomes, two SIGFPE cases and eight rejection/output-preservation checks per option combination. Verification follows when complete; no main merge or tag.


### Low-word projection smoke verification

After correcting obsolete rejection fixtures and a handwritten mixed-call expected sum, Debug freshly passed **217/217 unit tests** without leaks in `/data/check-low-word-debug.log`. The earlier expected-error helper leaks came from unexpectedly successful now-valid parser fixtures; final failure-injection tests and the full final unit run are clean. `/data/check-low-word-native.log` passed all eight Debug flag combinations with **2,114 defined projection results**, **two SIGFPE fault-retention cases** and **eight rejection/output-preservation checks** each. Full three-build verification is running; no publication-CI outcome for this uncommitted milestone is assumed.


### Low-word projection local verification

Debug freshly passed **217/217 unit tests** without leaks in `/data/check-low-word-debug.log` and all eight projection native combinations in `/data/check-low-word-native.log`. The authoritative non-overlapping `/data/verify-native-low-word.log` reused that unchanged Debug result and freshly passed **217/217** in ReleaseSafe and ReleaseFast; it ended `LOW WORD PROJECTION VERIFICATION PASSED`. Each build mode passed all eight combinations: **3,378 integer/program**, **3,560 floating/bit-pattern/mixed-ABI**, **890 call/ABI/effect**, **55,198 scalar-memory**, **3,041 blit**, **1,554 signed/unsigned numeric-conversion**, **2,114 low-word projection**, **24 existing arithmetic-fault**, **two projected arithmetic-fault**, **4 termination/ordering**, **2 memory fault-retention**, **2 blit memory-fault**, **15 existing CLI**, **10 symbolic-signature rejection/output-preservation**, **8 memory rejection/output-preservation**, **12 blit rejection/output-preservation**, **20 numeric rejection/output-preservation** and **eight projection rejection/output-preservation** checks per combination. All 24 completions of each of the seven native suites were counted. Formatting and all **twelve** independent generator checks passed. Existing signed/unsigned generator/oracle files and all legacy source/build/tools/tests remain unchanged. Publication CI is checked separately; no main integration or release tag.


### Low-word projection published CI

Checkpoint `7f7414433a33def9a0d0793d473beebbcc8ba4a2` passed https://github.com/0x6432/zbe/actions/runs/38931516272: Debug, ReleaseSafe and ReleaseFast all succeeded, including 217 unit tests, all twelve independent generators and all eight option combinations of all seven native harnesses. This result precedes fixed-frame probes below.


## Bounded page-wise native fixed-frame reservation

Added a private typed frame-reservation helper: descend by at most 4,096 bytes, read-touch the new RSP before another descent, and include the final remainder. Zero frames do nothing. No argument/general/SSE registers or frame bytes are changed by the touch; prologue flags are dead. Final RSP/alignment, all existing frame regions and the 64 KiB cap remain unchanged. This is a prerequisite for later allocation work, not dynamic allocation support or a claim of complete stack-clash hardening. See FRAME-PROBES.md.

Two tests cover exact reservation/touch sequences at seven boundary sizes through the maximum and exhaustive maximum-output allocation failures. Debug freshly passed **219/219 unit tests** in `/data/check-frame-probes-debug.log`. A new eighth native harness uses unreachable unknown-call pressure to retain large frames across every folding/home option, an alternate-stack adapter with a guarded mapping, and test-only removal of touches as negative controls. Its planned per-option checks are six ordinary result/preserved outcomes, two guard-page SIGSEGV cases and two successful unprobed controls. Verification follows when complete; all twelve generators and legacy implementation remain unchanged.


The guard harness's unprobed negative control initially caught an insufficient stack-top margin in the test mapping: some preserved-original slots straddled the guard even after touches were removed. A 128-byte aligned top margin puts those slots wholly in accessible lower memory while the first real probe still hits the guard. Expectations were not weakened: both real probes must SIGSEGV and both unprobed controls must succeed in every option combination. This was a test-placement correction, not a production allocator/home-layout change.


### Fixed-frame native smoke verification

After the guard-placement correction, `/data/check-frame-probes-native.log` passed all eight Debug flag combinations: **six result/preserved checks**, **two guard-page SIGSEGV cases** and **two unprobed negative controls** per combination. Each test-only unprobed mutation successfully crosses the controlled guard, while real probes fault at it. The prior **219/219** Debug unit smoke passed; only a stale source comment was subsequently corrected. The authoritative full runner rebuilds/checks that final source and all existing suites. No CI outcome for the uncommitted frame milestone is assumed.


### Fixed-frame probing local verification

The authoritative non-overlapping `/data/verify-native-frame-probes.log` freshly passed **219/219 unit tests** in **all three** build modes and ended `FRAME PROBING VERIFICATION PASSED`. Every build mode passed all eight combinations: **3,378 integer/program**, **3,560 floating/bit-pattern/mixed-ABI**, **890 call/ABI/effect**, **55,198 scalar-memory**, **3,041 blit**, **1,554 signed/unsigned numeric-conversion**, **2,114 low-word projection**, **six fixed-frame result/preserved**, **24 existing arithmetic-fault**, **two projected arithmetic-fault**, **4 termination/ordering**, **2 memory fault-retention**, **2 blit memory-fault**, **two fixed-frame guard-page SIGSEGV**, **two unprobed negative controls**, **15 existing CLI**, **10 symbolic-signature rejection/output-preservation**, **8 memory rejection/output-preservation**, **12 blit rejection/output-preservation**, **20 numeric rejection/output-preservation** and **eight projection rejection/output-preservation** checks per combination. All 24 completions of each of the eight native suites and both new guard/control groups were counted. Formatting and all **twelve** independent generator checks passed. Legacy source/build/tools/tests and existing oracle/generator files remain unchanged. Publication CI is checked separately; no main integration or release tag.

### Fixed-frame probing published CI

Checkpoint `34d5ea29ffb4a4d6c9e3300533dbd44b098b7e15` passed https://github.com/0x6432/zbe/actions/runs/38934557201: Debug, ReleaseSafe and ReleaseFast all succeeded. This precedes native dynamic allocation below.

## Native function-scoped dynamic allocation

Added typed `alloc4`/`alloc8`/`alloc16` with long size/result, failure-atomic construction, SSA/operand/independent analysis coverage and retained ordered effects. Each reached positive-size execution reserves fresh function-lifetime stack storage, including constants inside loops. Native lowering over-aligns to 16, probes page-wise, and checks round-up overflow before masking. Aligned outgoing reservations remain below live dynamic objects even when an object is smaller than the outgoing area. RBP-relative fixed homes, phi scratch and saved originals remain unchanged; normal return releases the dynamic extents. The 64 KiB cap still applies only to the fixed frame. See NATIVE-ALLOCATIONS.md for interval proof and invalid-size boundaries.

The interpreter explicitly returns `UnsupportedAllocation` on a reached allocation, including zero-size and Image-backed evaluation; no host-pointer fabrication or implicit Image resizing. Earlier writes persist, budgets still apply and owned frames clean up. This is native subset support, not a complete compiler or interpreter stack model.

Debug smoke passed **226/226 unit tests** without leaks and built successfully (`/data/check-native-allocations-debug.log`). All eight native allocation option combinations passed **580 defined results**, **two dynamic guard SIGSEGV cases**, **three checked round-up overflow SIGILL boundary cases**, **two unprobed negative controls** and **twelve invalid-input/output-preservation checks** each (`/data/check-native-allocations-native.log`). The exhaustive allocation-failure helper propagates OutOfMemory rather than wrapping it in an expected-error assertion. Full three-build verification follows; publication CI is checked separately.

At the user's request, finish verification/publication of this milestone and then stop. Do not begin interpreter allocation or another feature milestone. No main integration or release tag is authorized.


### Native dynamic allocation local verification

The authoritative non-overlapping `/data/verify-native-allocations.log` ended `NATIVE DYNAMIC ALLOCATION VERIFICATION PASSED`. Debug reused the unchanged **226/226** smoke result; ReleaseSafe and ReleaseFast freshly passed **226/226** each. All **24 combinations** (three builds × eight option sets) passed each of the **nine native harnesses**: 3,378 integer/program, 3,560 floating/bit-pattern/mixed-ABI, 890 call/ABI/effect, 55,198 scalar-memory, 3,041 blit, 1,554 signed/unsigned numeric-conversion, 2,114 low-word projection, six fixed-frame result/preserved and **580 dynamic-allocation defined results** per combination. All existing fault, termination, rejection and output-preservation groups passed unchanged. Each combination also passed two dynamic guard SIGSEGV checks, three round-up overflow SIGILL boundary checks, two unprobed dynamic controls and twelve allocation rejection/output-preservation checks. All 26 check/control completion markers were counted 24 times. Formatting and all **twelve independent generator checks** passed. Legacy source/build/tools/tests and existing oracle/generator files remain unchanged. Publication CI is checked separately. Stop after this milestone, as requested.

### Native dynamic allocation published CI and requested stop

Code checkpoint `35026f9e8bd62db4b5b18402d9f835535a771a6c` passed https://github.com/0x6432/zbe/actions/runs/38937920348: **Debug, ReleaseSafe and ReleaseFast all completed successfully**, including 226 unit tests, twelve generator checks and all eight option combinations of all nine native harnesses. Verified through the GitHub run and jobs APIs after completion, not inferred from a running workflow. This final documentation-only record does not alter the verified code; its commit skips redundant CI. Work stops here at the user's request. No next milestone was started, no main integration performed and no release tag created.

## Opt-in bounded synthetic interpreter stack objects

Continued at the user's explicit authorization from clean remote `0c1aa78`; the
prior requested stop is superseded for this milestone. Added optional
`Options.stack_memory`, separately owned synthetic objects and initialization
tracking without host-pointer casts or Image resizing. Both evaluators retain
allocation refusal by default. Enabled allocations are 16-aligned, requested-span
bounded, cumulatively capped and function-scoped. Returning frees only that
frame's objects; monotonic addresses prevent sibling calls reviving dead objects
within one evaluation. New evaluations intentionally reset the numeric namespace,
not a cross-evaluation provenance guarantee. See INTERPRETER-ALLOCATIONS.md for
zero-size, round-up/cap errors, configuration/region checks and diagnostic limits.

Reads and blit sources require initialized bytes. Whole-span validation precedes
writes/copies; cross Image/object copies work without conversion. Earlier Image
writes survive all later errors. Each operation consumes its ordinary instruction
step, including unused allocations; existing shared depth/step limits and
external/indirect refusals remain intact. Native allocation/emission, independent
oracle/generator files and legacy implementation are unchanged.

Ten new tests cover full reservation/disjoint boundaries, padding/guards/dead
objects, initialization and failure atomicity, all allocation forms, loop
freshness, recursive caller contents through 1,001 frames, exact budgets,
retained Image writes, folding and exhaustive injected cleanup/retry (including
recursive handle growth and child-call errors). The unchanged independent
1,472-row Python memory oracle additionally runs through allocations and
cross-region blits at eight offsets in both byte orders.

Initial Debug smoke passed **236/236 tests** in
`/data/check-interpreter-allocations.log`. Two Zig local/declaration name-shadowing
compile errors were corrected before the passing run. Child-error coverage was
then strengthened before starting fresh full verification. The serial,
CI-equivalent `/data/verify-interpreter-allocations.sh` performs all three builds,
eight option sets, nine native harnesses, twelve generator checks and formatting.
No full-matrix or publication-CI result is assumed until observed. No main merge
or release tag is authorized or performed.

### Interpreter stack allocation local verification and publication boundary

The authoritative serial `/data/verify-interpreter-allocations.log` ended
`INTERPRETER STACK ALLOCATION VERIFICATION PASSED` with exit status 0. All three
modes (Debug, ReleaseSafe and ReleaseFast) freshly passed **236/236 unit tests**
after strengthening child-error coverage. All **24 native combinations** passed
all **nine unchanged native harnesses**. All **26** result/fault/rejection/control
completion markers were mechanically counted exactly **24 times**. Per-combination
defined results remain 3,378 integer/program, 3,560 floating/bit-pattern/mixed-ABI,
890 call/ABI/effect, 55,198 scalar-memory, 3,041 blit, 1,554 numeric conversion,
2,114 projection, six fixed-frame and 580 dynamic-allocation results. All existing
fault, guard, overflow, output-preservation and unprobed negative controls passed.
Formatting and all **twelve independent generator checks** passed. Legacy
source/build/tools/tests, native emitter and existing fixtures/oracles/generators
are unchanged. Scope/credential scans and diff whitespace checks passed.

GitHub device sign-in expired without approval. No exposed credential was used;
no authentication token was written into the repository, Git remote, handoff or
patch. Temporary authentication configuration was removed. The remote remained
`0c1aa78` when freshly fetched after verification. Work is committed locally on
`rewrite/zig-native`, but **not pushed**: this checkpoint has **no GitHub Actions
run**, and no publication CI success is claimed. The earlier green native
allocation CI is only evidence for its earlier code checkpoint, not this change.

Resume by authenticating with a fresh secure GitHub/device connection, inspecting
the remote with fetch and the ancestor check, pushing only rewrite/zig-native,
then checking Actions for that exact pushed SHA and recording actual results.
Do not merge main or create a release tag. A credential-free format-patch of the
local checkpoint is also retained outside the repository for handoff. No further
feature milestone was started.
