# Experimental Linux AMD64 base-scalar slice

This is the first independent parse → SSA/phi verification → assembly → native-execution path. It is **not** full QBE, full AMD64 lowering, a complete register allocator, a complete optimizer, or release-ready code generation.

```sh
zig build
./zig-out/bin/zbe-native input.ssa output.s
cc driver.c output.s -o program
python3 tools/native_check.py
python3 tools/native_float_check.py
python3 tools/native_call_check.py
python3 tools/native_memory_check.py
python3 tools/native_blit_check.py
python3 tools/native_numeric_check.py
```

The driver takes two paths and optionally preceding `--fold-integers`, `--reuse-stack-homes` and/or `--callee-saved-homes` flags, in any order. It reads at most 16 MiB of IL, constructs owned IR, and returns an error for unsupported or invalid input. No output is created/truncated until parsing, SSA validation and assembly generation succeed. Identical input/output path strings are rejected; path aliases are not canonicalized. Filesystem write failures are not promised to be atomic. Diagnostics are new typed/frontend messages, not the legacy QBE CLI wording.

## Implemented boundary

- GNU assembler syntax for Linux ELF AMD64, System V base-scalar calling convention.
- Word/long/single/double or void functions. Integer and SSE argument banks are tracked independently (six GP and eight SSE registers), with overflow scalar stack slots in declaration order; integer/SSE/void returns. Incoming argument locations come from the typed allocation-free classifier described in ABI-AMD64.md.
- Direct and typed long-address indirect nonvariadic scalar/void-result calls with typed scalar arguments, including internal recursion/forward definitions and externally contracted SysV signatures. Call stack space is included in the aligned frame cap, disjoint from homes/phi scratch/saved originals (see CALLS.md).
- Typed scalar loads and effect-only stores through long addresses, with exact widths/extensions and raw floating bit transfers (see MEMORY.md).
- Floating copy/negation, scalar SSE add/sub/mul/div, and bit-preserving edge phi copies. Single/double homes retain raw bits; moves and negation do not pass through arithmetic conversion.
- Current integer copy/arithmetic/division/remainder/bitwise/negation/integer-extension/shift/integer-comparison instructions, jumps, low-word conditional branches, explicit `hlt` lowered to `ud2`, and edge-specific parallel phi copies.
- By default every SSA value has an eight-byte stack home; phi copies use additional, non-overlapping scratch homes. Default emission assigns unique homes. Opt-in `--reuse-stack-homes` greedily colors scalar interference into shared homes (see STACK-HOMES.md). Opt-in `--callee-saved-homes` additionally puts the first five colors in saved/restored GP registers, with remaining colors on the stack (see PRESERVED-HOMES.md). This is not a complete register allocator. A separate opt-in prepass performs conservative integer constant folding without deleting instructions.
- Frame pointer is preserved, stack space rounded to 16 bytes, and only caller-saved scratch registers are used for computation; optional callee-saved homes are separately saved/restored. A prototype frame-size cap of 64 KiB is explicit; fixed reservation now probes each page before descending farther (FRAME-PROBES.md).
- Export/local symbol linkage is retained. Symbols are validated, and quoted internal labels use a namespace unavailable to accepted user symbols. The assembly marks a non-executable GNU stack.

Aggregate types, precision narrowing, unsupported call forms, atomics, unsupported data/escape/general-relocation forms, aggregate ABI forms and combined environment/variadic calls, debug/unwind metadata, other instruction families, other platforms and other targets are unsupported. There is no fallback to the old port. Backend failures return no partial assembly from the library API. The module and IR are not modified by emission.

Native compiled loops have ordinary native-program behavior; the interpreter's execution budget is **not** inserted into emitted programs. The native test harness uses process timeouts. Debug/ReleaseSafe/ReleaseFast describe how the compiler tool is built, not IL optimization levels.

## Verification

The integer native harness consumes all 384 independent Python arithmetic/bitwise oracle cases 832 shift/comparison oracle cases and 384 negation/extension oracle cases and 1,228 division/remainder oracle cases, all four constant-jump regressions, loop-carried phi swaps, eight-argument word/long ABI cases, dynamic long-condition low-word checks, conditional phi edges and duplicate-target phi edges. It assembles/links through the host C compiler and calls the exported functions from C: 3,378 result checks plus a void-function call. The 512 additional mixed-program cases combine arithmetic, shifts, comparisons, extensions and division with diamonds and loop-carried phi values. These include a comparison-driven sum loop and a shift whose `%cl` scratch overlaps a former incoming argument register; all incoming arguments have independent homes before scratch use. Signed/unsigned division uses hardware quotient/remainder instructions, with all incoming arguments saved before `%rdx` scratch use; a mixed-argument regression checks this. Twenty-four separate subprocess checks require SIGFPE for dynamic and compile-time zero divisors and signed-minimum/minus-one pairs. These faults are not compiler diagnostics or evaluator error objects. Core dumps are disabled in the harness.

Four additional termination/ordering subprocess checks require SIGILL for direct/conditional halt and successful division followed by halt, but SIGFPE for zero division before halt. This is target-dependent abnormal termination, not a normal ABI return (see HALT.md).

It also checks fifteen CLI rejection/output-preservation/flag-order conditions and verifies the chain frame is 2,416 bytes by default versus 16 bytes with either colored home option.

These are bounded regressions for this subset, not byte identity with C QBE, full ABI conformance, target completeness, performance evidence, or permission to replace `main`.


The separate floating harness checks **3,560** native floating/bit-pattern/mixed-ABI results: 512 independent exact-rational arithmetic expectations, signed zero/infinity/NaN payload copies and negations, parallel floating swap phis, 384 same-width bitcast/exact-widening cases, 2,560 comparison cases, and interleaved/floats-first signatures exhausting both register banks with distinct weighted argument values. It sets round-to-nearest for these tests. Scalar SSE arithmetic follows the caller's floating environment; the compiler does not emulate rounding modes, normalize NaN payload results, or claim floating-environment parity with C QBE. The separate call harness adds 890 native call/ABI/effect checks and ten signature rejection/output-preservation checks in every option combination. Aggregates remain unsupported; native scalar variadic bodies are separate (VARIADIC-FUNCTIONS.md); sb/ub/sh/uh scalar ABI annotations now retain word transport with unspecified upper bits (SUBWORD-ABI.md). See CALLS.md for exact call coverage and the evaluator boundary.

The CLI unsupported-operation fixture now rejects precision narrowing (`truncd`): base floating types and comparisons are supported. All rejection/output-preservation expectations remain in force for unsupported or invalid input.


Same-width `cast` uses raw-bit moves across integer/SSE ABI classes. `exts` uses single-to-double precision widening; finite values are exact. Signaling-NaN arithmetic/payload widening is not specified by this subset. `truncd` is deliberately not implemented yet: local upstream IL documentation says toward-zero, but the unchanged C reference emits environment-sensitive `cvtsd2ss` and rounds a bounded probe to nearest under the default environment. No silent semantic choice is made for that discrepancy.


Floating predicates use explicit ordered/unordered SSE flag handling rather than treating floating flags as integer comparisons. Equality/less/less-equal exclude unordered results, inequality includes unordered results, and ordered/unordered test parity explicitly. Native tests cover both integer result widths, both floating operand widths, signed zeros, infinities and quiet/signaling NaN operands. Truth-value coverage does not establish floating exception-flag equivalence or behavior with unmasked exceptions.


All nineteen native harnesses accept `--fold-integers`, `--reuse-stack-homes` and `--callee-saved-homes`, forwarding them to the experimental compiler. CI executes each harness in all eight flag combinations in every compiler build mode, retaining all result, arithmetic-fault and output-preservation expectations. See OPTIMIZE.md for the folding pass's conservative scope and failure-atomic per-function contract and STACK-HOMES.md for layout ownership and analysis limits, and PRESERVED-HOMES.md for limited physical homes and the explicit full-width register-preservation adapter. No new IL optimization level or legacy compatibility behavior is implied.

## Scalar memory subset

Typed loads and effect-only stores now lower through full-width long addresses, with exact access widths, integer signed/unsigned extensions and raw floating bits. The memory harness adds 55,198 scalar-memory outcomes, two guard-page fault-retention checks and eight rejection/output-preservation checks per option combination. Native addresses are caller contracts, not a sandbox; interpreters require an explicitly supplied bounded synthetic image or opt-in stack model to execute memory, otherwise refusing it without host dereferencing (MEMORY-EVALUATION.md). Constant-length effect-only blits now have compact `rep movsb` lowering and a separate 3,041-result/two-fault/twelve-rejection harness (BLITS.md). Native dynamic stack allocation is now supported separately (NATIVE-ALLOCATIONS.md); numeric/zero-fill global data are implemented separately (DATA.md); atomic operations remain unsupported. See MEMORY.md.

## Signed numeric conversions

Signed word/long to single/double and single/double to signed word/long now use width-specific SSE conversions (SIGNED-CONVERSIONS.md). Float-to-signed truncates toward zero; the evaluator checks finite/range domains before host integer casts, but native invalid conversions retain ISA/environment-dependent behavior outside the defined-value claim. The numeric harness now combines signed and unsigned cases: 1,554 defined results and twenty rejection/output-preservation checks per option combination. Unsigned conversion uses explicit high-half algorithms (UNSIGNED-CONVERSIONS.md). The `truncd` discrepancy remains unresolved.


## Explicit low-word operand projections

Long temporaries used in word contexts load their low 32 bits from their original homes without changing the long source or creating a new definition. A seventh harness checks 2,114 outcomes, two retained arithmetic faults and eight rejection/output-preservation cases per option combination, including word call/stack arguments, indirect callbacks, phi edges, loops, raw casts, stores and original long uses after calls. Implicit reverse extension remains invalid. See LOW-WORD.md.


## Bounded fixed-frame reservation

Fixed frames now descend at most 4,096 bytes per step with an in-frame read probe before every next descent, including the remainder. Zero frames remain untouched; final layout, alignment and the 64 KiB cap are unchanged. The eighth harness checks ordinary results/preserved registers plus two protected-stack faults and two test-only unprobed negative controls per option combination. This is not dynamic allocation support or complete stack-clash hardening. See FRAME-PROBES.md.


## Dynamic native stack objects

`alloc4`/`alloc8`/`alloc16` use typed long byte sizes/results and runtime page-wise reservation, over-aligned to16. Every reached execution reserves a fresh positive extent until return. An aligned outgoing-area offset keeps stack arguments below live objects even when an allocation is smaller than the outgoing reservation. Size-rounding overflow traps instead of wrapping; zero-byte objects promise no dereference. The ninth harness covers initialized extents, loops, recursion, mixed/indirect calls, preserved registers and protected-stack mutation controls. Evaluators refuse allocation by default, even with an Image; opt-in synthetic interpreter objects are separate (INTERPRETER-ALLOCATIONS.md). See NATIVE-ALLOCATIONS.md for the exact native/interpreter boundary.


## Typed symbol addresses

Bare unquoted `$symbol` scalar operands have long address type and lower to
full-width RIP-relative `leaq`, never an implicit load or truncated immediate.
Module validation checks operand symbol IDs and the emitter checks spellings,
including phi/terminator/unreachable uses. Executable PIE/non-PIE linking is
covered separately; checked scalar i32 symbol offsets are described in
SYMBOL-OFFSETS.md. GOT/shared-object interposition, TLS, general relocation
expressions and full PIC/ABI support are not added. Numeric/zero-fill
data definitions are implemented separately (DATA.md). By default, interpreters explicitly
refuse reached symbol-address resolution; opt-in initialized synthetic data globals
are separate (INTERPRETER-GLOBALS.md). See SYMBOL-ADDRESSES.md. The tenth
native harness adds independent linked object/function address, initialized
memory, phi, mixed call and preservation checks in both executable link modes.


## Owned packed data

Numeric/zero-fill module data now emit writable ELF objects, checked alignment and
exact size/binding metadata. The eleventh harness compares independent bytes and
compiled/C mutations in PIE/non-PIE executables, plus data-only links and rejection
output preservation. This adds no interpreter global resolver or full data-language
parity. Typed long symbolic initializers are separately implemented
(DATA-RELOCATIONS.md). See DATA.md for exact syntax, limits, ownership and verification scope.


## Owned byte-string data

Byte data groups now decode an explicit bounded escape subset into owned bytes.
Numeric-only byte directives prevent source string contents from becoming assembly.
There is no implicit terminator, interpreter global resolver or all-GAS escape
compatibility claim. The thirteenth native harness independently compares all-byte
content, whole-object mutations, ELF extents and injection exclusions in PIE and
non-PIE executables (DATA-STRINGS.md).


## Exact all-zero data

Validated all-zero raw-bit objects now lower to writable ELF BSS; negative-zero
and symbolic objects stay in file-backed data. The fourteenth native harness
independently checks bytes, writes, ELF section kinds and cap-sized sparse objects
in PIE/non-PIE. No cross-object layout, interpreter-global or performance-parity
promise is introduced (DATA-BSS.md).

Checked i32 scalar symbol displacements use full-width RIP-relative LEA, under the
existing combined symbol/displacement linker reach contract (SYMBOL-OFFSETS.md).
No new scratch lifetime, interpreter resolver or broader PIC/code-model promise
is implied.

External/indirect variadic scalar call sites now have a checked named-argument
prefix marker and final AMD64 AL setup (VARIADIC-CALLS.md). Variadic function
bodies and vastart are supported separately (VARIADIC-FUNCTIONS.md); interpreter
host calls remain unsupported. C
default promotions are explicit caller responsibilities, not inserted conversions.

Caller-supplied native scalar vaarg consumers are a separate bounded slice
(VAARG-CONSUMERS.md); their caller-supplied descriptor model is reused by native definitions/vastart
(VARIADIC-FUNCTIONS.md); bounded opt-in synthetic consumers are separate (INTERPRETER-VAARG.md). Defaults still refuse vaarg/vastart; explicit root-only synthetic initialization
is separate (INTERPRETER-VASTART.md). Internal variadic calls remain unsupported.

Native scalar variadic definitions and effect-only vastart now have a separate
frame-owned save region and checked named signatures (VARIADIC-FUNCTIONS.md).
Internal interpreter variadic calls remain explicit refusals; root-only synthetic
vastart is separately opt-in (INTERPRETER-VASTART.md); opt-in manually prepared scalar descriptor consumers are separate (INTERPRETER-VAARG.md).

Nonvariadic scalar environment calls now have a distinct hidden long operand/
parameter and Linux AMD64 RAX mapping, without shifting ordinary ABI arguments
(ENVIRONMENT-CALLS.md). Root/module interpreter mapping remains synthetic and
bounded; environment+varargs and aggregates remain unsupported.

Bounded printable-ASCII quoted globals (excluding ELF `@` syntax) decode to owned canonical symbol names
across definitions/calls/scalar operands/data relocations (QUOTED-GLOBALS.md).
Native formatting escapes non-bare names while preserving existing bare output
and the private-label namespace; no host lookup or full identifier/target parity.

### Bounded integer literal instruction selection

Direct literal RHS word/long `add/sub/and/or/xor` use AMD64 immediate forms.
Word literals retain all32 bits; long literals qualify only when the full64-bit
pattern equals sign-extension of an i32. Other RHS forms/opcodes retain their
existing materialization; literal lhs is never commuted. This is read-only
instruction selection with no new flag, IR rewrite or performance claim. See
AMD64-IMMEDIATES.md for encoding boundaries, ownership and independent tests.
