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
