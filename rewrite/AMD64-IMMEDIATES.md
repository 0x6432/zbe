# Design-only follow-up: literal RHS AMD64 integer immediates

Approved isolated implementation scope; the separate frozen expansion gate is
running and must remain untouched. Word literals are printed as signed32 decimal
with identical low32 bits; the assembler may select an equivalent shorter imm8.

## Actual source gap and bounded scope

Current amd64.zig `.binary` always loads lhs into accumulator and rhs into temporary,
then emits register/register arithmetic. Select immediate forms only for direct
literal RHS of word/long add/sub/and/or/xor. Keep all lhs materialization (including
low_word, COMMON pointer-cell and quoted-symbol paths), save/result/home behavior,
and every surrounding effect in the exact existing order. No commutation of
constant lhs, SSA fact lookup, IR rewrite, new language support or new option.

Word literals use the full32-bit encoding; long literals qualify ONLY when their
64-bit pattern equals sign-extension of their low32 bits. Emit unambiguous signed
32-bit decimal for qword immediate values. Long 0x0000000080000000 and
0x00000000ffffffff MUST fall back to the current register path, while
0xffffffff80000000 and0xffffffffffffffff qualify. Float/div/rem/mul/shifts,
nonliteral RHS and all other forms retain the old path. Do not suppress even an
add-zero instruction: this is instruction selection, not a new elimination pass.

## Invariants, ownership and refusal boundaries

Existing module/SSA validation stays first. The emitter remains read-only on IR,
invocation-owned and allocation-fallible through its existing output buffer; no
new scratch owner, retained view, cap, CFG/ID/home layout or interpreter behavior.
Existing library all-or-error output and driver output-preservation guarantees
remain unchanged. No new host address resolution, relocation form or aliases.
Unknown/symbolic RHS still uses old materialization. Accumulator and save mapping
are unchanged; removing an unused temporary-register materialization must not
alter argument or callee-saved preservation. No performance claim without data.

## Acceptance before publication

- Independently compute masked word/long expected add/sub/bitwise results over
  signed32 boundaries, just-outside patterns, high-bit-only values and seeded
  dynamic lhs; verify exact qualifying/nonqualifying assembly operands.
- Native PIE/nonPIE execution, all existing home/folding options, live values
  around calls/phi/loops, low_word lhs and ordinary/quoted/common symbol lhs.
- Assert no immediate selection for literals outside encoding range, constants
  carried through SSA without --fold-integers, float, division or nonliteral RHS.
- Independent assembler/object disassembly confirms qword sign-extension and
  unchanged symbol relocations. Mutation test forces zero-extension acceptance
  and must fail on 0x0000000080000000/ffffffff (not incidental compile errors).
- Exhaustive emission allocation failures plus same-module retries; old source
  immutable; three modes/fmt/generators/full native matrix and exact-SHA CI.

This adds a modest real AMD64 instruction-selection capability, not a full target,
register allocator, optimizer level, source-language parity or speedup milestone.

## Additive validation

500 independent width/encoding boundary cases are reproduced by
`tools/immediate_selection_generate.py --check`; focused unit tests inspect exact
eligible/fallback assembly, immutable IR and all emission allocation failures
with same-module retry for all home options. The native harness independently
inspects100 object encodings without folding and runs510 assertions in each PIE
and non-PIE executable, including quoted symbols, projections, subtraction
asymmetry, phi/loop/call pressure and preserved registers. Generator and native
harness are registered in CI. A temporary-only compiling truncation mutant must
fail a native value assertion, not merely assembly or shape checks.

The emitter's only writer is its existing allocator-owned assembly buffer;
print/save failures propagate through `try` with no catch-to-fallback. No writer
interface or file-write behavior changes. Driver filesystem write atomicity
remains outside the existing guarantee; pre-emission failures do not truncate
output. No benchmark or speedup claim is made.
