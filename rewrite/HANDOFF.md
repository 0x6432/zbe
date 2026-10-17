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

### Interpreter stack allocation published CI

After the user explicitly authorized transient token authentication, code
checkpoint `f97b69a68afb0f687157d19cc3dcd35f2e838e1b` was pushed successfully to
`rewrite/zig-native`. The credential-free origin URL is unchanged; authentication
was confined to the command environment, not repository files, remote URLs,
patches or logs.

Exact-SHA workflow https://github.com/0x6432/zbe/actions/runs/38958864614 completed
**successfully**: **Debug, ReleaseSafe and ReleaseFast all completed successfully**,
including their independent test and native execution steps. Confirmed through
the completed workflow and all three jobs APIs, not inferred from the earlier
queued/running states. This verifies the new interpreter allocation checkpoint,
not just the earlier native-allocation milestone. The local full-matrix results
recorded above remain unchanged.

This follow-up is documentation-only and skips redundant CI. No source change,
main merge or release tag was made. The previous publication/authentication
blocker is resolved; no further feature milestone was started.

## Typed long symbol-address operands

Continued from clean remote `f17eba7` under the user's request to keep progressing
through bounded milestones. Added module-owned `Operand.symbol`, always long,
with frontend `$symbol` operands. Bare symbols are deliberately long-only in this
subset; a long temporary permits explicit low-word projection. No data definitions,
TLS/extern/GOT forms, quoted-symbol syntax or symbol-offset literals are added.
See SYMBOL-ADDRESSES.md for scope and executable-linking limitations.

Module validation checks symbol IDs in ordinary instructions, phi inputs and
terminators, including unreachable paths. The emitter checks each used spelling
before returning any assembly, then materializes full addresses using RIP-relative
`leaq`. Indirect calls retain their target-capture and caller-contract semantics;
known direct signatures are unchanged. This is executable PIE/non-PIE coverage,
not complete PIC/shared-object/interposition or linker relocation support.

Symbols do not invent function-local SSA values; production visitors and separate
independent liveness/interference oracles treat them accordingly. The new fixture
runs through both analysis oracles. Integer folding keeps symbol addresses unknown.
Reached interpreter resolution returns `UnsupportedSymbolAddress` rather than
looking up host pointers or fabricating synthetic addresses. Safe paths, ordinary
step precedence, call-dispatch precedence and earlier Image writes are preserved;
all frames and synthetic objects clean up on refusal.

Five new tests cover typing/ownership/copied iterator state, invalid ID and hostile
name checks in all scalar positions, emission across home strategies, folding,
interpreter refusal/budgets/safe paths and exhaustive parser/analysis/folder/emitter/
frame allocation cleanup. The adversarial verifier test explicitly casts its
allocator-owned const slices to corrupt inputs; an initial test-only const-assignment
compile error was corrected before the passing run. Debug freshly passed
**241/241 tests** and built the executable in `/data/check-symbol-addresses.log`.

The tenth native harness independently links C-owned data and function addresses.
Its eight-option Debug smoke passed **2,032 defined checks per link mode**
(**4,064 per option** across non-PIE and PIE), including the PIE/high-address
preconditions, plus **16 rejection/output-preservation checks** per option in
`/data/check-symbol-native.log`. Existing nine harnesses, fixtures/oracles and
all twelve independent generators are unchanged. Full verification follows via
`/data/verify-symbol-addresses.sh`; no full-matrix/CI success is assumed yet.
No main integration, release tag or next feature code was started.

### Symbol-address local verification

The authoritative serial `/data/verify-symbol-addresses.log` ended
`SYMBOL ADDRESS VERIFICATION PASSED` with exit status 0. Debug reused the unchanged
**241/241** smoke result (the runner explicitly reported cached execution);
ReleaseSafe and ReleaseFast freshly passed **241/241** each. All **24** native
combinations passed all **ten** native harnesses. The **26** existing result/fault/
rejection/control groups each completed exactly **24 times** unchanged. The new
**2,032 linked-symbol checks** completed **48 times** (two executable link modes
per combination), and the link-mode/high-address and 16 rejection/output-preservation
groups each completed **24 times**. All **29** distinct markers were mechanically
counted with those expectations. Formatting and all **twelve independent generator
checks** passed. Existing native fixtures/oracles/generators and legacy source/
build/tools/tests are unchanged. The changes remain isolated to rewrite/ and the
rewrite workflow; credential and whitespace scans passed.

Publication CI is checked separately after pushing the exact code checkpoint.
No main merge, release tag or next feature implementation is authorized by this
record. The sandbox-only `/data/zbe-data-followup-design.txt` is an unimplemented
proposal for the next bounded milestone, not evidence of data-definition support.

### Symbol-address exact-SHA CI and rerun record

Code checkpoint `bf78756dfd0f188389b1297777643e7d3a4c48da` was published to
`rewrite/zig-native`. Workflow https://github.com/0x6432/zbe/actions/runs/38964639722
is now **confirmed green** for Debug, ReleaseSafe and ReleaseFast at that exact SHA.
The first attempt passed Debug/ReleaseSafe and all ReleaseFast unit tests, but the
ReleaseFast native step ended with exit **143** after seven complete option sets
and the eighth integer harness. Its only failure annotation was process exit 143;
there was no assertion, Python traceback or timeout annotation. The job lasted
514 seconds, below its 20-minute job limit. This is an unexplained termination,
not evidence of a diagnosed compiler defect or a proven runner-infrastructure bug.

The affected ReleaseFast/all-three-flags floating harness was repeated locally:
all **3,560** checks passed in six seconds. The failed CI job was then rerun at the
**unchanged SHA**, with unchanged harnesses/timeouts/oracles, and passed. The run's
second attempt reports all three modes successful; the successful first-attempt
Debug/ReleaseSafe jobs were retained. Original and rerun evidence is saved locally
as `/data/symbol-address-ci-attempt1.json`, `/data/symbol-ci-full-fast.log`,
`/data/symbol-ci-annotations.json`, `/data/recheck-symbol-fast.log` and
`/data/symbol-address-ci-rerun-result.json`. No failed result was relabeled green.

Next bounded milestone: numeric/zero-fill owned data definitions, packed fields,
explicit bounded alignment/size, executable AMD64 emission and independent byte
expectations. Strings/relocation initializers/TLS/full data or ABI parity and a
persistent interpreter global-memory model remain outside that proposed scope.
No main merge or release tag was performed.

## Owned numeric/zero-fill data milestone (in progress)

Added module-owned stable Data pointers/typed DataId, packed numeric raw-bit items
and bounded zero runs, explicit alignment1..64/default8 and checked16MiB/object,
64MiB/module payload limits. The frontend supports exported/local definitions,
matching integer/float groups, multiline whitespace and trailing commas. It rejects
strings, quoted names, relocations/offsets, TLS/section/common and mismatched float
field syntax. Module validation rechecks size caches/limits, IDs and cross-kind
namespace duplicates, and rejects direct calls to known data objects. AMD64 emits
writable aligned ELF object definitions with exact size/binding directives; ordinary
symbol addresses retain existing full-width executable lowering. Data-only modules
are supported. No implicit interpreter globals, host pointer lookup, Image growth,
GOT/shared-object policy or full data/ABI parity is claimed (DATA.md).

Seven new tests passed with the existing suite: **248/248 Debug** in
`/data/check-data-debug.log`. Initial compilation found a shadowed Alignment helper
parameter and an incorrect test-only Image.init argument list; both were corrected
before the successful run. Tests include independent parsed bytes, atomic retry,
stable ownership, hostile edits/caps/names/IDs, direct data-call rejection, retained
Image writes and exhaustive allocation-failure cleanup for builders/parser/emitter.
A subsequent pre-full-run test strengthens exact accepted aggregate-limit emission.

The independent Python data-byte generator supplies ten objects and1,896 expected
bytes; its initial harness metadata sum was corrected from a hand-count to the
actual independently generated1,896 before execution. Eight-option Debug native
smoke passed in `/data/check-native-data.log`: **7,856 non-PIE +7,866 PIE** defined
checks per combination, **20 ELF size/binding/alignment**, **2 data-only links** and
**48 data rejection/output-preservation** checks. The unchanged symbol harness
expectations also passed all eight options. Only two obsolete numeric-data negative
inputs (frontend and symbol CLI) changed to still-unsupported symbolic initializers;
all prior count/output-preservation contracts and independent generators are kept.

CI now includes the thirteenth generator and eleventh native harness, with option
banners for precise termination diagnosis. Full three-mode/eight-option verification
and publication CI have not yet been claimed. Legacy work remains isolated; no main
merge or release tag was performed.

### Owned-data authoritative local verification

`/data/verify-owned-data.sh` was generated directly from the current rewrite CI
steps and ran serially without source changes or overlapping builds/harnesses.
`/data/verify-owned-data.log` ended **OWNED DATA VERIFICATION PASSED**, exit 0.
**248/248 unit tests** passed in each of Debug, ReleaseSafe and ReleaseFast.
All **24** mode/option combinations passed all **eleven** native harnesses.
Mechanically counted **34 distinct completion groups**: 33 occurred exactly 24
times each, while the 2,032 linked-symbol group occurred 48 times (two links per
combination). Existing arithmetic-fault, termination, memory-fault, guard-page,
overflow trap, negative-control and rejection expectations all remained intact.

Per combination, new data checks were 7,856 non-PIE plus 7,866 PIE results, 20 linked
ELF metadata records, 2 data-only links and 48 rejection/output-preservation checks.
Formatting and all **thirteen** independent generator checks passed. All twelve
pre-existing generators and every pre-existing fixture/oracle file are unchanged.
Only the two obsolete numeric-data negatives were replaced as documented above;
their counts and output-preservation assertions were retained. Scope, whitespace,
credential and legacy-isolation checks passed; origin remains credential-free.

Publication CI will be checked separately at the exact pushed SHA. The sandbox-only
`/data/zbe-relocation-followup-design.txt` is an unimplemented proposal, not data
relocation functionality. No source changes for that follow-up have begun.

### Owned-data exact-SHA CI confirmed green

Published code checkpoint `07e440fb054e8d6b74f6314c1b215ec8c32defab` passed all three
jobs (Debug, ReleaseSafe, ReleaseFast) in its first workflow attempt:
https://github.com/0x6432/zbe/actions/runs/38975218317 . Each independent test and
native-matrix step completed successfully. No rerun, relaxed test or timeout change
was needed. Exact-SHA evidence is saved in `/data/owned-data-ci-result.json` and
`/data/watch-owned-data-ci.log`. The local248-test/24-combination result remains
recorded above. Working tree was clean after the code push. This documentation-only
record skips redundant CI; it does not claim validation of future source changes.

Next bounded milestone is typed long symbolic data initializers (pointer tables),
with signed addends, module symbol validation and executable PIE/non-PIE checks.
Numeric oracle bytes remain independent and unchanged. Strings, narrow/TLS/GOT
relocations and interpreter global resolution stay outside that proposed scope.
No main merge, release tag or full QBE/data/ABI claim was made.

## Typed long symbolic data initializer milestone (in progress)

Data.Item now has a typed eight-byte SymbolAddress (module SymbolId +i64 addend).
Long data groups accept forward/self/data/function/external symbolic initializers
and checked signed addends. Every referenced ID/spelling is validated even for
unused definitions. AMD64 emits full-width writable `.quad` linker expressions,
printing signed-minimum addends directly without negation. Numeric payload limits,
object size/binding and existing scalar address lowering are unchanged. No global
interpreter resolver, host pointer conversion, Image growth, narrow/TLS/GOT/general
relocations or shared-object/ABI parity is added (DATA-RELOCATIONS.md).

Five new unit tests passed: **253/253 Debug** in
`/data/check-relocations-debug.log`, including exhaustive allocation cleanup.
A first new negative test wrongly treated `$target-8` as subtraction; the existing
group grammar correctly parses a symbol followed by a negative numeric item.
The test now verifies that legal two-item result and rejects a separated lone
minus instead. No parser rejection was weakened to hide this test-author mistake.
An additional pre-full-run assertion strengthens successful symbolic append retry
and exact eight-byte accounting after injected OOM.

Eight-option Debug smoke passed in `/data/check-native-relocations.log`: **324
non-PIE +327 PIE** address/callback/mutation checks per option, plus12 ELF metadata,
2 no-text-relocation checks,2 data-only links and40 rejection/output-preservation
checks. Its initial completion count was hand-added as424 instead of324; all
behavioral assertions had passed, and only that new harness's count arithmetic was
corrected, with an explicit count diagnostic retained. Existing data and symbol
harnesses also passed all eight options with all counts unchanged. Now-valid long
symbol negative inputs were replaced only by still-unsupported narrow forms.
Independent numeric oracle bytes and every existing generator remain unchanged.

Full three-mode/eight-option verification follows. CI includes the twelfth harness;
no full-matrix or publication-CI success is assumed by this in-progress record.

### Symbolic-data authoritative local verification

The current CI-derived serial `/data/verify-data-relocations.sh` completed with
**DATA RELOCATION VERIFICATION PASSED**, exit0, recorded in
`/data/verify-data-relocations.log` and `.exit`. No source changed during the run.
**253/253 tests** passed in Debug, ReleaseSafe and ReleaseFast. All **24** native
mode/option combinations passed all **twelve** harnesses. Mechanical completion
counts matched **40 distinct groups**:39 groups exactly24 times, and the existing
2,032 linked-symbol group48 times (PIE/non-PIE). All prior result/fault/overflow/
negative-control/rejection checks stayed intact. New per-combination results:
324 non-PIE +327 PIE symbolic-data results,12 ELF metadata,2 no-text-relocation,
2 data-only link and40 rejection/output-preservation checks.

Formatting and all **thirteen** independent generators passed; every pre-existing
generator and fixture/oracle file is unchanged. Existing numeric/data/symbol
rejection counts and output-preservation contracts were retained as documented.
Scope, whitespace, credential and legacy-isolation checks passed. Origin remains
credential-free. The byte-string follow-up in `/data/zbe-byte-string-followup-design.txt`
is proposal-only, not implemented or verified. No main merge or release tag occurred.
Publication CI is checked separately at the exact pushed code SHA.

### Symbolic-data exact-SHA CI confirmed green

Code checkpoint `5c87942ff440de5f6ac890d6d418b66c84f40035` passed Debug,
ReleaseSafe and ReleaseFast in the first workflow attempt:
https://github.com/0x6432/zbe/actions/runs/38978254422 . All three independent
unit-test and native-matrix steps completed successfully; no rerun or relaxation
was needed. Exact-SHA evidence is saved in `/data/data-relocations-ci-result.json`
and `/data/watch-data-relocations-ci.log`. This documentation-only record skips
redundant CI. Source was unchanged throughout the authoritative local and CI runs.
No main merge, tag, interpreter globals or full backend/ABI/data parity is claimed.

Next bounded proposal is owned byte strings in b-data groups with explicit safe
escape decoding, no implicit terminator and numeric-only assembly emission. It
must preserve failure-atomic byte ownership, payload bounds, independent byte
expectations and existing unsupported-class/output-preservation checks.

## Owned byte-string data milestone (in progress)

Byte data groups now support owned strings mixed with numeric bytes. A two-pass
bounded decoder validates/counts before allocation, accepts an explicit control/
quote/backslash/octal/exact-two-hex escape subset and rejects malformed escapes or
physical line breaks. Raw nonescape bytes/UTF-8 are retained, with no implicit NUL,
padding or normalization. Data.append copies byte slices and publishes only after
copy/table allocation succeeds; failed table growth frees its copy. Data.deinit
frees every owned byte item. Object/module payload caps include decoded bytes.

AMD64 emits only numeric `.byte` lines, never raw `.ascii` text. An independent
Python corpus supplies eight objects and358 bytes, including all256 byte values,
UTF-8, embedded zeros, empty strings, mixed fields and assembler-like payloads.
Six new tests passed with all existing tests: **259/259 Debug** in
`/data/check-strings-debug.log`. The first compile found only a test binding that
needed const (its pointed-to source bytes remain intentionally mutable); it was
corrected before the passing run. Tests include copied ownership/source mutation,
copy/table OOM atomic retry, decoder limits/diagnostics and exhaustive allocation
failure cleanup. String definitions do not initialize caller Image or resolve
interpreter globals (DATA-STRINGS.md).

Eight-option Debug smoke passed in `/data/check-native-strings.log`: **1,455
non-PIE +1,463 PIE** string/address/mutation/call results per combination,16 ELF
metadata records,2 linked injection exclusions,2 data-only links and48 rejection/
output-preservation checks. Existing data, relocation and symbol harnesses also
passed all eight options unchanged in their counts. Only now-valid b-string
negative inputs were changed to unsupported h-string forms. Existing generators
and fixture/oracle bytes are unchanged; CI adds a fourteenth generator and a
thirteenth native harness. Full matrix/publication CI verification follows and
is not assumed by this in-progress record. No main merge or release tag occurred.

### Byte-string authoritative local verification

The CI-derived serial `/data/verify-data-strings.sh` ended **DATA STRING
VERIFICATION PASSED**, exit0, in `/data/verify-data-strings.log`. Source was frozen
throughout the run. Debug explicitly reused the unchanged **259/259** smoke result
(cached test execution); ReleaseSafe and ReleaseFast freshly passed **259/259**.
All **24** mode/option combinations passed all **thirteen** native harnesses.
Mechanically counted **46 distinct completion groups**:45 groups exactly24 times,
plus the2,032 linked-symbol group48 times for its two executable links. Existing
result/fault/overflow/guard/negative-control/rejection groups stayed intact.

New per-combination checks were1,455 non-PIE +1,463 PIE string results,16 ELF
metadata,2 linked injection exclusions,2 data-only links and48 rejection/output-
preservation checks. Formatting and all **fourteen** independent generators
passed. Every pre-existing generator and fixture/oracle file remains unchanged;
only the documented obsolete b-string negative inputs changed to h-string forms,
retaining all assertion/count contracts. Scope, whitespace, credential and legacy
isolation checks passed. No main merge, tag or backend/ABI parity claim was made.
Publication CI will be checked independently for the exact pushed code SHA.

### Byte-string exact-SHA CI confirmed green

Code checkpoint `56895a347864ec1744964d1cc80ebd386ec00bcd` passed Debug,
ReleaseSafe and ReleaseFast on the first workflow attempt:
https://github.com/0x6432/zbe/actions/runs/38980600520 . All three unit-test and
native-matrix steps completed successfully, with no rerun or relaxed expectations.
Exact-SHA evidence is saved in `/data/data-strings-ci-result.json` and
`/data/watch-data-strings-ci.log`. This documentation-only record skips redundant
CI and does not validate future source changes. Source stayed frozen throughout
local full verification and publication CI; no main merge or release tag occurred.

Next bounded proposal: all-zero raw-bit data lowering to writable ELF BSS, with
negative-zero/symbolic items kept in PROGBITS, independent linked byte/section/
size/binding checks and cap-sized sparse-object regressions. No new interpreter
global model, cross-object layout promise or performance superiority is implied.

## Exact zero-data BSS milestone (in progress)

Added allocation-free raw-bit all-zero classification. Numeric/float bit fields
must be exactly0, byte slices every byte0, zero runs and empty data are zero;
symbolic initializers always stay unknown/nonzero. After ordinary module/target
validation, AMD64 chooses writable `.bss` for all-zero objects and emits one compact
zero run, while negative floating zeros, relocations and nonzero content remain
in `.data`. Alignment/export/type/size, packed payload bytes, owned IR and scalar
semantics are unchanged. No cross-object layout, interpreter globals, `.comm`/TLS
or performance superiority is promised (DATA-BSS.md).

Four new tests passed with the suite: **263/263 Debug** in
`/data/check-bss-debug.log`. The initial compile exposed a runtime selection passed
to the comptime formatting parameter; it was corrected to select between two
literal-format calls before the successful run. Tests cover bit classification,
negative zeros, byte ownership/read-only emission, metadata, validation precedence
and exhaustive parser/emitter allocation cleanup.

Eight-option Debug smoke passed in `/data/check-native-bss.log`: **877 non-PIE
+885 PIE** byte/address/mutation results and16 ELF section/size/binding checks per
combination. Two data-only executable regressions per combination each use exactly
64MiB payload (four16MiB objects), verify every initial byte and all bytes after end
mutations, require NOBITS extents/alignment and ELF file size at most128KiB. The new
ELF reader initially expected decimal sizes; readelf displays16MiB as0x1000000,
so it was corrected to accept the actual decimal/hex formats without changing the
size assertion. Existing numeric, relocation and string native harnesses also
passed all eight options. Every prior generator/fixture/oracle is unchanged; CI
adds the fourteenth native harness and retains all fourteen generators.

Full three-mode/eight-option verification follows. No full-matrix or exact-SHA CI
success is assumed yet, and no main merge or release tag occurred.

### BSS authoritative local verification

The CI-derived serial `/data/verify-data-bss.sh` completed **DATA BSS VERIFICATION
PASSED**, exit0, in `/data/verify-data-bss.log`. Source stayed frozen throughout.
Debug reused its unchanged **263/263** smoke result (explicit cached execution);
ReleaseSafe and ReleaseFast freshly passed **263/263** each. All **24** native
mode/option combinations passed all **fourteen** harnesses. Mechanical completion
counts matched **50 distinct groups**:49 exactly24 times, plus the existing2,032
linked-symbol group48 times for its two executable links. Earlier defined results,
arithmetic/termination/memory/overflow faults, guard tests, negative controls and
rejection/output-preservation groups all stayed intact.

Per combination, new checks were877 non-PIE +885 PIE BSS results,16 ELF section/
size/binding/alignment records and2 cap-sized sparse-file/runtime regressions.
The file-footprint bound is **at most128KiB**, matching the harness comparison;
it is not a general artifact-size/performance claim. All **fourteen** independent
generators and formatting passed. All pre-existing generators and fixture/oracle
files remain unchanged, with no rejection substitutions needed for this lowering.
Scope, whitespace, credential and legacy-isolation checks passed. Origin remains
credential-free. No main merge, release tag, new interpreter globals or complete
backend/data/ABI parity is implied. Publication CI follows at the exact code SHA.
The scalar-symbol-addend proposal in `/data/zbe-scalar-symbol-addend-followup-design.txt`
is unimplemented and unverified; no source for that follow-up has begun.

### BSS exact-SHA publication CI confirmed

Code `7b71f64a39a27b2f038c30c036547a60cc975a53` passed all three jobs on its
first attempt: Debug, ReleaseSafe and ReleaseFast, run
https://github.com/0x6432/zbe/actions/runs/38982929621 . The run's head SHA was
checked exactly; all jobs completed successfully. Evidence is saved in
`/data/data-bss-ci-result.json` and `/data/watch-data-bss-ci.log`. Source stayed
frozen during local full verification and publication CI. This documentation-only
record skips redundant CI; it does not validate later changes.

Next bounded slice: a distinct long `symbol_offset` operand with a checked i32
addend, compact RIP-relative lowering and ordinary scalar operand coverage.
Combined symbol/displacement reach remains an assembler/linker contract, not a
promise every admitted offset links at every placement. Existing i64 data
initializers stay unchanged. No interpreter symbol resolver, main merge or release
tag is authorized or implied.

## Checked scalar symbol-offset milestone (in progress)

Added a distinct `Operand.symbol_offset` with module-owned symbol identity and a
checked signed i32 addend. Bare symbol API and wider i64 data initializers remain
unchanged. Ordinary scalar parsing is line-local and long-only; negative addends
use `$symbol+-N`, direct `$callee+0(...)` remains unsupported, and an explicit long
temporary is required for low-word use/indirect expression calls. Full-width LEA
uses the existing scratch lifetime; combined symbol/displacement reach remains an
assembler/linker small-code-model contract, not universal extreme-offset linkage.
No interpreter symbol resolution, host-pointer conversion or Image resizing is
introduced. See SYMBOL-OFFSETS.md.

Module and emitter validation use an allocation-free symbol-reference accessor;
production SSA uses remain non-values, while independent liveness/interference
switches separately classify the new tag. Their existing oracle bundles now also
include the new fixture. Existing generators and fixture/oracle bytes are
unchanged. Only four now-valid ordinary-symbol-offset rejection cases (two unit,
two native) were replaced with overflowing i32 offsets, preserving rejection
counts/output protection. Data relocation i64 range/grammar is untouched.

Focused Debug smoke passed **269/269** tests and built the executable. An added
adversarial test initially used a nonexistent `.compare` tag; it was corrected to
`.compare_integer` and extended with a long shift-value context before the passing
run. Further exact diagnostic-span and valid manually built indirect-target
assertions were added after that smoke and await full verification. Six new tests
cover copied payloads, min/max boundaries, wrong classes/malformed input, hostile
IDs/spellings, unknown folding, budgets/refusal/earlier writes and exhaustive
allocation cleanup. Source was not frozen for these development smoke runs; only
the forthcoming authoritative full run will verify the final current source.

All eight-option native Debug smoke combinations passed the new harness and both
affected existing symbol/relocation harnesses in `/data/check-native-offset.log`.
New checks per combination: **1,456 results in each of non-PIE and high-address
PIE**, two executable no-TEXTREL checks and32 rejection/output-preservation checks.
The C expectations use valid array extents, a C-defined middle alias for negative
offsets, all128 positive/middle-relative element addresses, memory/store-address
survival, parallel phi/swap paths, GP/SSE/overflow arguments, captured indirect
targets, blits, low words and all five preserved GP registers. CI adds the fifteenth
native harness and retains fourteen independent generators. Full local matrix and
exact-SHA CI are not yet claimed.

### Scalar-offset authoritative local verification passed

The serial CI-derived `/data/verify-symbol-offsets.sh` ended **SCALAR SYMBOL OFFSET
VERIFICATION PASSED**, exit0 (`/data/verify-symbol-offsets.log/.exit`). Final source
stayed frozen throughout. All three modes freshly passed **269/269** tests,
including the final diagnostic-span and manually built indirect-target assertions.
All **24** mode/option combinations passed **fifteen** native harnesses. Mechanical
counts matched **53 distinct completion groups**:51 exactly24 times, plus the
existing2,032 linked-symbol and new1,456 scalar-offset groups48 times each for two
executable links. The new harness contributes2,912 linked defined results,
2 no-TEXTREL checks and32 rejection/output-preservation checks per combination.
All earlier result/fault/guard/negative-control/rejection groups remain intact.

Formatting and all **fourteen** independent generators passed. All55 existing
fixture/generator files were verified unchanged against `ce54115`; legacy isolation,
whitespace, changed-path scope and credential scans passed. No main merge, release
tag, interpreter global model or full backend/ABI/code-model parity is implied.
Publication and exact code-SHA CI follow; local success is not CI success.

### Scalar-offset exact-SHA publication CI confirmed

Code `f2b58a47125e2ae78a1de039fa05ec273cb9d711` passed Debug, ReleaseSafe and
ReleaseFast on the first attempt, run
https://github.com/0x6432/zbe/actions/runs/38985515529 . Exact head SHA and all three
completed successful jobs were checked. Evidence is saved in
`/data/symbol-offsets-ci-result.json` and `/data/watch-symbol-offsets-ci.log`.
Source stayed frozen throughout full local verification and publication CI.
This documentation-only record skips redundant CI and does not verify later work.

Next reviewed bounded proposal: opt-in interpreter-owned numeric/zero/string
module globals, separate from caller Image and invocation stack objects, with
checked disjoint synthetic reservations and eager explicit refusal of symbolic
data initializers. Default/standalone symbol refusal and all host/external/indirect
call boundaries remain. The proposal is in
`/data/zbe-interpreter-globals-followup-design.txt`; no implementation or result is
claimed yet. No main merge or release tag occurred.

## Opt-in initialized interpreter globals (in progress)

Added separate evaluation-owned numeric/raw-floating-bit, zero-fill and copied
string globals behind null-default `Options.global_memory`. Default symbol refusal
is unchanged; standalone evaluation explicitly rejects this module-only option.
The new global owner validates complete synthetic reservation disjointness from
Image and stack, preflights data sizes/layout/unsupported symbolic initializers
before allocation, packs bytes in the selected endian order, and reserves exact
object spans plus alignment gaps/16-byte guards. Guard charging includes empty
objects. It neither borrows module bytes for mutation nor resizes caller Image.
No host/linker function/external resolution or indirect execution is introduced.

Bare/i32-offset data operands resolve through explicit memory context, not global
state; checked u64 arithmetic is distinct from whole-object access validity.
Global lifetime spans every invocation and is independent of stack object marks;
root return/error frees it and each new evaluation resets from module data.
Image writes before later errors persist. Eager opted-in configuration/initializer
errors precede execution/steps, explicitly documented in INTERPRETER-GLOBALS.md;
module validation, depth/range, argument and call-dispatch ordering are specified.
Symbolic data initializers remain an explicit eager unsupported boundary.

Focused Debug smoke passed **277/277** tests and built the executable in
`/data/check-interpreter-globals-debug.log`. Initial new tests used transposed
unsigned load-kind names; they were corrected before the passing run. Failure-
injected evaluation error paths explicitly propagate allocation failures instead
of masking them behind expected-error assertions. Eight added tests reuse the
unchanged1,896-byte numeric and358-byte string Python oracles, explicit raw-bit
big/little-endian packed expectations, ownership/reset/guards/range/cap/overlap/
zero cases, cross-region blit atomicity, child-frame sharing and earlier writes.

After smoke, further phi/branch/call-argument, two-child visibility, folding,
empty-object distinctness, empty reservations and reached address-overflow/budget
assertions were added. The new fixture joins independent analysis-oracle bundles.
Those final assertions await authoritative full verification; smoke is not claimed
for source changed after it. Native lowering, existing generators/fixtures/oracles
and all fifteen native harnesses are unchanged. Full matrix and exact-SHA CI are
not yet claimed; no main merge, release tag or full global/relocation/ABI parity.

### Initialized interpreter globals authoritative local verification passed

The CI-derived serial `/data/verify-interpreter-globals.sh` completed **INTERPRETER
GLOBAL VERIFICATION PASSED**, exit0, in `/data/verify-interpreter-globals.log/.exit`.
Source stayed frozen throughout. Final source freshly passed **277/277** tests in
each of Debug, ReleaseSafe and ReleaseFast, including all post-smoke assertions.
All **24** mode/option combinations passed all **fifteen** native harnesses.
Mechanical counts matched **53 distinct completion groups**:51 exactly24 times,
with existing2,032 linked-symbol and1,456 scalar-offset groups48 times each for
two executable links. No old result/fault/guard/control/rejection group was removed.

Formatting/all **fourteen** independent generator checks passed. All56 prior
fixture/generator files, every native harness and the CI workflow were verified
unchanged against `8a0688b`. Legacy isolation, whitespace, scope and credential
scans passed. This is opt-in initialized numeric/zero/string simulation, not
symbolic relocation/function-pointer support, persistent module state, native
address safety, full ABI/backend parity or performance superiority. Publication
and exact code-SHA CI follow; local success is not assumed to imply CI success.

### Initialized globals exact-SHA CI confirmed after post-step retry

Code `d33666e901186668e36dea973dbeec3616accfdd` is confirmed green, run
https://github.com/0x6432/zbe/actions/runs/38987731463 , attempt2. Debug and
ReleaseSafe succeeded in attempt1. ReleaseFast's formatting, all generator/unit
and native execution steps also completed successfully in attempt1, but its
`Post Run mlugg/setup-zig@v2` remained in progress when the job reached its20-minute
limit. GitHub's annotation explicitly reports maximum execution time20m0s; the
job/run ended cancelled (including cancellation grace). Its completed job-log
endpoint returned HTTP404, so no detailed cache/log root cause is asserted.

Only that cancelled ReleaseFast job was rerun at the **unchanged code SHA**.
It completed successfully in attempt2. Overall run success and the latest result
for each of the three job names were checked; earlier Debug/ReleaseSafe successes
were retained, not silently relabelled as reruns. No source, generator, harness,
check or timeout changed to obtain green. Source stayed frozen throughout local
full verification and both publication attempts.

Evidence: `/data/interpreter-globals-ci-attempt1.json`,
`/data/interpreter-globals-ci-annotations.json`,
`/data/interpreter-globals-ci-rerun-result.json` and
`/data/watch-interpreter-globals-ci-rerun.log`. The first local watcher expired at
its20-minute polling bound before remote cancellation completed; no success was
claimed from that timeout. A separate finite retry watcher recorded actual green.
This documentation-only record skips redundant CI and does not verify future work.

Next bounded proposal: resolve existing symbolic data initializers only to defined
module Data objects in this opt-in synthetic model. Forward/self/mutual addresses
are not recursive initializer execution; function/external relocations remain
explicitly refused. Signed i64 arithmetic, complete layout/preflight, byte order,
ownership and error cleanup must remain checked. Proposal-only design is in
`/data/zbe-interpreter-data-relocations-followup-design.txt`. No main merge,
release tag, full interpreter relocation/ABI/backend parity or performance claim.

## Internal-data-only synthetic relocations (in progress)

Extended opt-in initialized globals to existing long symbolic initializers only
when their pool IDs name defined module Data objects. Forward/self/mutual
references use checked guarded-layout addresses, never recursive initializer
execution or host/linker lookup. Function/external initializers still return eager
UnsupportedGlobalInitializer; null-default/standalone symbol boundaries and
external/indirect call refusals stay unchanged. Full signed i64 addends are checked
against u64, widening minInt before negation. Stored integers do not prove object
extent/provenance. Native emission/parser/IR and i32 scalar offset rules are intact.

Preflight checks layout, target membership and address arithmetic before allocating
payloads. A separate materialize helper owns its buffer with errdefer until table
publication, so new fallible relocation writes cannot leak an unpublished payload
or double-free published objects. Lookup is an allocation-free linear layout scan,
not an optimized linker or performance claim. INTERPRETER-DATA-RELOCATIONS.md
specifies byte order, eager errors, ownership and unsupported cases.

Six focused tests and a new fixture add independently hand-computed guarded layout
and byte expectations for both endians, self/forward/mutual/empty/unaligned refs,
full signed extremes yielding zero/max integers, pre-allocation underflow/overflow,
function/external and invalid-ID/size refusal, pointer-table loads/calls/blits,
reset/folding, earlier Image writes, step ordering and exhaustive allocation
cleanup. The fixture joins both independent analysis-oracle bundles. Focused Debug
verification is running in `/data/check-interpreter-data-relocations-debug.log`;
no passing result/full matrix/exact-SHA CI is assumed yet. All prior fixtures,
generators/native harnesses and legacy files are intended to remain unchanged and
will be checked before publication. No main merge or release tag is authorized.

### Internal relocation focused Debug verification passed

Focused smoke passed **283/283** tests and built the executable in
`/data/check-interpreter-data-relocations-debug.log`. No implementation/test
correction was required after this smoke: final current source is unchanged.
Scope/credential/whitespace and legacy checks passed; all57 prior fixture/generator
files, native harnesses and workflow are unchanged against `12f8358`. The complete
serial three-mode/eight-option verification follows with source frozen. Debug may
reuse the unchanged smoke result; actual cached/fresh status will be recorded,
not inferred. No full-matrix or publication CI success is claimed yet.

### Internal-data relocation full local verification passed

`/data/verify-interpreter-data-relocations.sh` completed with exit0 and
`INTERPRETER DATA RELOCATION VERIFICATION PASSED`. Formatting and all14 independent
generator checks passed. Debug reused the unchanged283-test smoke result; Safe
and Fast each freshly passed283/283 tests. All24 build-mode/option combinations
passed all15 native harnesses. Mechanical completion counting found exactly53
groups:51 appeared24 times, linked-symbol2032 and scalar-offset1456 each appeared48
times for their separate PIE/non-PIE links. Existing fault, rejection, output-
preservation, guard-page and negative-control groups retained their counts.

Read-only review and scope/credential/whitespace/legacy checks passed. All57 prior
fixture/generator files, all native harnesses and workflow remain unchanged versus
`12f8358`; only the new interpreter fixture was added to independent analysis
corpora. Evidence: `/data/verify-interpreter-data-relocations.log`, its `.exit`
and `/data/interpreter-data-relocation-verification-counts.json`. A remote fetch
confirmed the prior documentation checkpoint still heads rewrite/zig-native.
Exact-SHA publication CI is next; no remote green result is claimed yet. No main
merge, release tag or full relocation/ABI/backend parity is implied.

### Internal-data relocation exact-SHA CI confirmed green

Published code checkpoint `5626c77a1a250c23ac309b4511adda0d9bdb83b4` passed
https://github.com/0x6432/zbe/actions/runs/39009654237 on its first attempt.
Debug, ReleaseSafe and ReleaseFast completed successfully, including their
post-job steps. No rerun, source correction, weakened assertion or timeout change
was needed. Source remained frozen through the complete local matrix and exact-
SHA CI. Evidence: `/data/interpreter-data-relocations-ci-result.json` and
`/data/watch-interpreter-data-relocations-ci.log`. This documentation-only update
skips redundant CI; it records actual results, not verification of future work.

Next bounded proposal: typed sb/ub/sh/uh annotations in scalar ABI positions on
Linux AMD64, retaining four SSA classes and explicit extension instructions.
Reference semantics leave upper bits unspecified; do not add implicit sign/zero
extension or claim full ABI support. Before implementation, review checked typed
annotations/ownership, exact internal signatures, parser predeclaration restrictions,
independent poisoned-upper-bit native expectations and allocation-failure cleanup.
Proposal-only review: `/data/zbe-subword-abi-followup-design.txt`. No main merge,
release tag, full backend parity or performance claim is authorized.

## Typed subword scalar ABI slice (in progress)

After first-attempt green internal-data relocation CI and its published result
record, implementing typed sb/ub/sh/uh annotations only in function/call ABI
positions. Four SSA classes remain unchanged; narrow values use word transport
with unspecified upper bits, not automatic sign/zero extension. This follows
bundled IL documentation and AMD64 elimsb, without changing the legacy reference.
Explicit extension instructions remain required to observe the complete word.

Closed AbiType/SubwordType annotations are separate from ScalarType. Existing
base builders keep their APIs/default null annotations. New typed constructors
retain failure-atomic parameter/call publication and copied argument ownership.
Structural validation checks publicly forged contradictory metadata, including
void/nonword results and nonparameter values; defined calls compare exact narrow
annotations as well as existing scalar/result/arity rules. External/indirect
signatures remain caller contracts and interpreter host invocation stays refused.

Parser header/call handling and predeclaration now admit narrow annotations only
on call-result SSA definitions; arithmetic/phi/copy contexts still reject them.
One old now-valid sb-call negative was replaced with unsupported b, preserving
its rejection count. New fixture adds explicit extension, recursion, long lowword
arguments and phi/call swaps to both unchanged independent analysis switches.
Seven focused tests plus a new independent native harness are being verified;
no passing full result is assumed. The native harness covers poisoned upper bits,
mixed bank overflow, narrow returns, direct/indirect/internal/external paths,
unused effects, preserved originals, PIE/nonPIE and output-preserving rejection.

Initial focused compilation exposed incorrect comma wiring of the new analysis
fixture; corrected to string concatenation without changing either oracle. The
focused runner was stopped for slow-test diagnosis and rerun with progress output;
the new OOM driver avoids repeated identical value-matrix validation while still
injecting every allocation in representative constructor/recursive/phi/analysis/
emission paths. Full value matrices remain separate tests. Neither stop indicates
a passing or failed assertion. No authoritative full matrix or exact-SHA CI has
started for this milestone. Existing tools/oracles/fixtures remain protected.

### Subword focused results before full verification

Diagnostic standalone execution completed all290 tests successfully. No assertion
failed. The earlier quiet runner was stopped to inspect progress, not because
OOM coverage or semantics were weakened. Review then made AbiType.scalar's switch
explicitly exhaustive, removed its now-obsolete private parser helper, and added
independent word-nonparameter/void-return metadata checks and a separate5x5
argument-annotation signature matrix. The full runner must freshly verify this
final source; no cached290 result is claimed for those last test additions.

`/data/check-subword-abi-native.sh` built Debug and passed the new harness in all
8 option combinations:1033 defined-bit checks per PIE/nonPIE link,2 no-TEXTREL and
40 rejection/output-preservation checks per combination. No native correction was
needed. Native oracle expectations observe only low bits/explicit extensions.
All prior native harnesses, generators and fixtures remain unchanged against
`291733e`; the single existing unit negative replacement preserves its count.
The full three-mode/eight-option matrix is next with source frozen, including all
16 native harnesses and all14 independent generator checks. Exact-SHA CI has not
started; no full ABI/parity/performance claim is implied.

### Subword ABI full local verification passed

`/data/verify-subword-abi.sh` completed exit0 with `SUBWORD ABI VERIFICATION PASSED`.
Final-source290/290 tests freshly passed in Debug (2m), ReleaseSafe (3s) and
ReleaseFast (2s). Formatting and all14 independent generator checks passed. All24
mode/option combinations passed all16 native harnesses. Mechanical counting found
56 completion groups:53 appeared24 times, while linked-symbol2032, scalar-offset
1456 and new subword1033 appeared48 times each for separate PIE/nonPIE links.
The new harness also retained2 no-TEXTREL and40 rejection/output-preservation
checks per combination. Existing fault/control/rejection totals stayed unchanged.

Source remained frozen throughout authoritative verification. Final review and
scope/credential/legacy/whitespace checks passed; all73 prior fixture/generator/
native-harness files are unchanged versus `291733e`. The only prior unit negative
replacement is now-supported sb argument -> unsupported b, count preserved. CI
only adds the new harness to its existing eight-option loop; original timeout,
generators and assertions remain intact. Evidence: `/data/verify-subword-abi.log`,
its `.exit` and `/data/subword-abi-verification-counts.json`. Documentation now
corrects the native harness count to16. Exact-SHA publication CI is next, not yet
confirmed green. No main merge, release tag or full ABI/backend parity is implied.

### Typed subword ABI exact-SHA CI confirmed green

Code checkpoint `2ad59cb554ed822101633a4e3a7e209cb33121aa` passed
https://github.com/0x6432/zbe/actions/runs/39011804238 on its first attempt.
Debug, ReleaseSafe and ReleaseFast all completed successfully, including post-job
steps. No rerun, source correction, timeout change or weakened assertion was
needed. Source stayed frozen through the full local matrix and complete exact-
SHA CI. Evidence: `/data/subword-abi-ci-result.json` and
`/data/watch-subword-abi-ci.log`. This documentation-only record skips redundant
CI and is not verification of future changes. The worktree was clean after code
publication, with origin remaining credential-free and legacy isolation intact.

Next reviewed bounded proposal: external/indirect variadic call sites only,
recording a checked named-argument prefix index and setting AL to the occupied
SSE argument-register count after marshalling. Keep variadic function definitions,
vastart/vaarg, aggregates, environment calls and host interpretation unsupported.
Explicit IL types remain caller contracts; never invent C default promotions.
Review AL0/named-SSE/>8-SSE ordering, R11 preservation, exact defined-nonvariadic
signature refusal, owned typed construction and independent C/assembly oracles
before implementation. Proposal: `/data/zbe-variadic-call-followup-design.txt`.
Environment-call ideas in `/data/zbe-environment-call-followup-design.txt` remain
unselected questions, not implemented functionality. No main merge, release tag,
full ABI/backend parity or performance claim is authorized.

## Variadic scalar call sites only (in progress)

Following first-attempt green typed-subword CI, added external/indirect marked
scalar/void call sites only. Call.variadic_start records a checked named-prefix
index, never an operand or implicit promotion. Function definitions remain
nonvariadic; any marked known direct call is CallSignatureMismatch, even unused/
unreachable. Variadic headers, vastart/vaarg, aggregates, environment calls and
interpreter host invocation remain unsupported. C default promotions remain the
IL caller's explicit extension/widening responsibility, not hidden conversions.

Typed CallOptions and common Function.appendCall preserve existing builder APIs
as wrappers and copied argument ownership. Result/target/argument/index checks
precede publication; out-of-range public metadata returns InvalidVariadicMarker.
Parser permits one marker with explicit commas, including initial/final/sole
markers. Native lowering writes AL from the existing saturated SSE cursor after
all argument loads, immediately before call, including named floats and AL0.
R11 targets, return homing, frame/probe/dynamic allocation and nonvariadic emission
remain unchanged. No new operand-use or scalar class is introduced.

Six focused tests passed296/296 in Debug and built the executable without source
or test corrections. They cover prefix grammar/no implicit promotion, common
builder ownership/failure retry, forged indices, unsupported bodies/known-call
mismatch, exact AL ordering/count/saturation and otherwise identical nonvariadic
assembly in four home options, evaluator refusal/safe/budget paths, effects and
exhaustive OOM cleanup. The new fixture joins both independent analysis corpora.
Evidence: `/data/check-variadic-calls-debug.log` and its exit0 record.

The new native harness passed all8 Debug option sets without corrections:561
checks per PIE/nonPIE link,2 no-TEXTREL and32 rejection/output-preservation cases
per combination. C stdarg expectations are independent promoted weighted values;
raw assembly probes assert AL separately, including poisoned final integer loads.
Coverage includes all base/subword returns, mixed named/variable bank overflow,
zero tails, indirect targets, snprintf, void/unused effects, phi loops, preserved
originals and a16-byte dynamic object below a48-byte outgoing reservation.
Evidence: `/data/check-variadic-calls-native.log` and its exit0 record.

Scope/credential/legacy/whitespace checks passed. All74 prior fixture/generator/
native-harness files except the separately checked newly valid subword negative
remain unchanged versus d8b4723. Exactly two old newly valid marked-call negatives
(one unit, one subword harness) became duplicate-marker negatives, preserving
both groups' assertion counts. No existing oracle was broadened/weakened. The
new17th harness is added to the existing CI loop; original timeout stays intact.
The authoritative full matrix follows frozen source. Debug may reuse unchanged
296 smoke; actual cache/fresh status will be recorded. No full-matrix/exact-SHA CI
result is assumed, nor full variadic ABI/backend parity or performance.

### Variadic call-site full local verification passed

The frozen authoritative runner completed exit0 with
VARIADIC CALL VERIFICATION PASSED. Debug reused the unchanged296-test smoke;
ReleaseSafe and ReleaseFast each freshly passed296/296. All24 combinations
(three modes times eight option sets) passed all17 native harnesses. Formatting
and all14 independent generator checks passed. All59 completion groups were
counted:55 appeared24 times; the linked-symbol, scalar-offset, subword ABI and
new variadic defined-result groups appeared48 times for their two links. The
new harness contributed561 defined results per PIE/nonPIE link,2 no-TEXTREL and
32 rejection/output-preservation checks per combination. No source correction,
assertion reduction, timeout change or generator/oracle replacement was needed.

Evidence: /data/verify-variadic-calls.sh, .log, .pid and .exit;
/data/variadic-calls-verification-counts.json. Final review confirmed credential-
free origin, legacy isolation, allowed-path scope and no credential patterns.
The two newly valid old syntax negatives are exactly the duplicate-marker
replacements described above; all other prior fixture/generator/native-harness
files remain unchanged. Exact pushed-SHA CI is still pending; local success does
not imply CI success or complete variadic ABI/backend parity. Source remains
frozen through exact-SHA CI, including post-job steps.
