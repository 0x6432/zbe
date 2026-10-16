# Experimental Linux AMD64 integer slice

This is the first independent parse → SSA/phi verification → assembly → native-execution path. It is **not** full QBE, full AMD64 lowering, a register allocator, an optimizer, or release-ready code generation.

```sh
zig build
./zig-out/bin/zbe-native input.ssa output.s
cc driver.c output.s -o program
python3 tools/native_check.py
```

The driver takes exactly two paths. It reads at most 16 MiB of IL, constructs owned IR, and returns an error for unsupported or invalid input. No output is created/truncated until parsing, SSA validation and assembly generation succeed. Identical input/output path strings are rejected; path aliases are not canonicalized. Filesystem write failures are not promised to be atomic. Diagnostics are new typed/frontend messages, not the legacy QBE CLI wording.

## Implemented boundary

- GNU assembler syntax for Linux ELF AMD64, System V integer calling convention.
- Word/long or void functions; integer register arguments and stack arguments beyond the first six; integer/void returns.
- Current integer copy/arithmetic/division/remainder/bitwise/negation/integer-extension/shift/integer-comparison instructions, jumps, low-word conditional branches, and edge-specific parallel phi copies.
- Every SSA value has an eight-byte stack home; phi copies use additional, non-overlapping scratch homes. This deliberately simple strategy has **no register allocation or optimization**.
- Frame pointer is preserved, stack space rounded to 16 bytes, and only caller-saved scratch registers are used. A prototype frame-size cap of 64 KiB is explicit; large-frame probing is not implemented.
- Export/local symbol linkage is retained. Symbols are validated, and quoted internal labels use a namespace unavailable to accepted user symbols. The assembly marks a non-executable GNU stack.

Floating/aggregate/ABI-extension types, calls, loads/stores, data/global definitions, varargs, debug/unwind metadata, other instruction families, other platforms and other targets are unsupported. There is no fallback to the old port. Backend failures return no partial assembly from the library API. The module and IR are not modified by emission.

Native compiled loops have ordinary native-program behavior; the interpreter's execution budget is **not** inserted into emitted programs. The native test harness uses process timeouts. Debug/ReleaseSafe/ReleaseFast describe how the compiler tool is built, not IL optimization levels.

## Verification

The native harness consumes all 384 independent Python arithmetic/bitwise oracle cases 832 shift/comparison oracle cases and 384 negation/extension oracle cases and 1,228 division/remainder oracle cases, all four constant-jump regressions, loop-carried phi swaps, eight-argument word/long ABI cases, dynamic long-condition low-word checks, conditional phi edges and duplicate-target phi edges. It assembles/links through the host C compiler and calls the exported functions from C: 3,370 result checks plus a void-function call. The 512 additional mixed-program cases combine arithmetic, shifts, comparisons, extensions and division with diamonds and loop-carried phi values. These include a comparison-driven sum loop and a shift whose `%cl` scratch overlaps a former incoming argument register; all incoming arguments have independent homes before scratch use. Signed/unsigned division uses hardware quotient/remainder instructions, with all incoming arguments saved before `%rdx` scratch use; a mixed-argument regression checks this. Twelve separate subprocess checks require SIGFPE for zero divisors and signed-minimum/minus-one pairs. These faults are not compiler diagnostics or evaluator error objects. Core dumps are disabled in the harness.

It also checks eight CLI rejection/output-preservation conditions.

These are bounded regressions for this subset, not byte identity with C QBE, full ABI conformance, target completeness, performance evidence, or permission to replace `main`.
