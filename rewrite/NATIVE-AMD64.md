# Experimental Linux AMD64 base-scalar slice

This is the first independent parse → SSA/phi verification → assembly → native-execution path. It is **not** full QBE, full AMD64 lowering, a complete register allocator, a complete optimizer, or release-ready code generation.

```sh
zig build
./zig-out/bin/zbe-native input.ssa output.s
cc driver.c output.s -o program
python3 tools/native_check.py
python3 tools/native_float_check.py
python3 tools/native_call_check.py
```

The driver takes two paths and optionally preceding `--fold-integers`, `--reuse-stack-homes` and/or `--callee-saved-homes` flags, in any order. It reads at most 16 MiB of IL, constructs owned IR, and returns an error for unsupported or invalid input. No output is created/truncated until parsing, SSA validation and assembly generation succeed. Identical input/output path strings are rejected; path aliases are not canonicalized. Filesystem write failures are not promised to be atomic. Diagnostics are new typed/frontend messages, not the legacy QBE CLI wording.

## Implemented boundary

- GNU assembler syntax for Linux ELF AMD64, System V base-scalar calling convention.
- Word/long/single/double or void functions. Integer and SSE argument banks are tracked independently (six GP and eight SSE registers), with overflow scalar stack slots in declaration order; integer/SSE/void returns. Incoming argument locations come from the typed allocation-free classifier described in ABI-AMD64.md.
- Direct nonvariadic scalar-result calls with typed scalar arguments, including internal recursion/forward definitions and externally contracted SysV signatures. Call stack space is included in the aligned frame cap, disjoint from homes/phi scratch/saved originals (see CALLS.md).
- Floating copy/negation, scalar SSE add/sub/mul/div, and bit-preserving edge phi copies. Single/double homes retain raw bits; moves and negation do not pass through arithmetic conversion.
- Current integer copy/arithmetic/division/remainder/bitwise/negation/integer-extension/shift/integer-comparison instructions, jumps, low-word conditional branches, explicit `hlt` lowered to `ud2`, and edge-specific parallel phi copies.
- By default every SSA value has an eight-byte stack home; phi copies use additional, non-overlapping scratch homes. Default emission assigns unique homes. Opt-in `--reuse-stack-homes` greedily colors scalar interference into shared homes (see STACK-HOMES.md). Opt-in `--callee-saved-homes` additionally puts the first five colors in saved/restored GP registers, with remaining colors on the stack (see PRESERVED-HOMES.md). This is not a complete register allocator. A separate opt-in prepass performs conservative integer constant folding without deleting instructions.
- Frame pointer is preserved, stack space rounded to 16 bytes, and only caller-saved scratch registers are used for computation; optional callee-saved homes are separately saved/restored. A prototype frame-size cap of 64 KiB is explicit; large-frame probing is not implemented.
- Export/local symbol linkage is retained. Symbols are validated, and quoted internal labels use a namespace unavailable to accepted user symbols. The assembly marks a non-executable GNU stack.

Aggregate/ABI-extension types, precision narrowing and numeric integer/float conversions, unsupported call forms, loads/stores, data/global definitions, varargs, debug/unwind metadata, other instruction families, other platforms and other targets are unsupported. There is no fallback to the old port. Backend failures return no partial assembly from the library API. The module and IR are not modified by emission.

Native compiled loops have ordinary native-program behavior; the interpreter's execution budget is **not** inserted into emitted programs. The native test harness uses process timeouts. Debug/ReleaseSafe/ReleaseFast describe how the compiler tool is built, not IL optimization levels.

## Verification

The integer native harness consumes all 384 independent Python arithmetic/bitwise oracle cases 832 shift/comparison oracle cases and 384 negation/extension oracle cases and 1,228 division/remainder oracle cases, all four constant-jump regressions, loop-carried phi swaps, eight-argument word/long ABI cases, dynamic long-condition low-word checks, conditional phi edges and duplicate-target phi edges. It assembles/links through the host C compiler and calls the exported functions from C: 3,378 result checks plus a void-function call. The 512 additional mixed-program cases combine arithmetic, shifts, comparisons, extensions and division with diamonds and loop-carried phi values. These include a comparison-driven sum loop and a shift whose `%cl` scratch overlaps a former incoming argument register; all incoming arguments have independent homes before scratch use. Signed/unsigned division uses hardware quotient/remainder instructions, with all incoming arguments saved before `%rdx` scratch use; a mixed-argument regression checks this. Twenty-four separate subprocess checks require SIGFPE for dynamic and compile-time zero divisors and signed-minimum/minus-one pairs. These faults are not compiler diagnostics or evaluator error objects. Core dumps are disabled in the harness.

Four additional termination/ordering subprocess checks require SIGILL for direct/conditional halt and successful division followed by halt, but SIGFPE for zero division before halt. This is target-dependent abnormal termination, not a normal ABI return (see HALT.md).

It also checks fifteen CLI rejection/output-preservation/flag-order conditions and verifies the chain frame is 2,416 bytes by default versus 16 bytes with either colored home option.

These are bounded regressions for this subset, not byte identity with C QBE, full ABI conformance, target completeness, performance evidence, or permission to replace `main`.


The separate floating harness checks **3,560** native floating/bit-pattern/mixed-ABI results: 512 independent exact-rational arithmetic expectations, signed zero/infinity/NaN payload copies and negations, parallel floating swap phis, 384 same-width bitcast/exact-widening cases, 2,560 comparison cases, and interleaved/floats-first signatures exhausting both register banks with distinct weighted argument values. It sets round-to-nearest for these tests. Scalar SSE arithmetic follows the caller's floating environment; the compiler does not emulate rounding modes, normalize NaN payload results, or claim floating-environment parity with C QBE. The separate call harness adds 466 native call/ABI/effect checks and six signature rejection/output-preservation checks in every option combination. Aggregates, varargs and extended ABI parameter/result classes remain unsupported. See CALLS.md for exact call coverage and the evaluator boundary.

The CLI unsupported-operation fixture now rejects precision narrowing (`truncd`): base floating types and comparisons are supported. All rejection/output-preservation expectations remain in force for unsupported or invalid input.


Same-width `cast` uses raw-bit moves across integer/SSE ABI classes. `exts` uses single-to-double precision widening; finite values are exact. Signaling-NaN arithmetic/payload widening is not specified by this subset. `truncd` is deliberately not implemented yet: local upstream IL documentation says toward-zero, but the unchanged C reference emits environment-sensitive `cvtsd2ss` and rounds a bounded probe to nearest under the default environment. No silent semantic choice is made for that discrepancy.


Floating predicates use explicit ordered/unordered SSE flag handling rather than treating floating flags as integer comparisons. Equality/less/less-equal exclude unordered results, inequality includes unordered results, and ordered/unordered test parity explicitly. Native tests cover both integer result widths, both floating operand widths, signed zeros, infinities and quiet/signaling NaN operands. Truth-value coverage does not establish floating exception-flag equivalence or behavior with unmasked exceptions.


Both native harnesses accept `--fold-integers`, `--reuse-stack-homes` and `--callee-saved-homes`, forwarding them to the experimental compiler. CI executes each harness in all eight flag combinations in every compiler build mode, retaining all result, arithmetic-fault and output-preservation expectations. See OPTIMIZE.md for the folding pass's conservative scope and failure-atomic per-function contract and STACK-HOMES.md for layout ownership and analysis limits, and PRESERVED-HOMES.md for limited physical homes and the explicit full-width register-preservation adapter. No new IL optimization level or legacy compatibility behavior is implied.
