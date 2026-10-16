# Exact zero-data ELF BSS lowering

The experimental Linux AMD64 emitter places provably all-zero data in writable
`.bss` (ELF NOBITS) rather than file-backed `.data` (PROGBITS). Classification is
by **raw bits**, never floating numeric equality or linker address guesses:

- Byte/half/word/long and single/double bit fields must be exactly zero.
- Every byte of an owned byte item must be zero.
- Zero-fill runs are zero, including count0; empty objects are vacuously zero.
- Every symbolic initializer is unknown/nonzero for this decision, even addend0.

Thus positive floating zero may use BSS, while negative floating zero retains its
sign bits in PROGBITS. Mixed content with any nonzero bit stays in PROGBITS. Self,
forward and external references are never assumed to resolve to address zero.

Module size/cache/ID/name/reference validation still runs first. `Data.isAllZero`
is allocation-free and does not validate ownership or resolve symbols; callers
using it directly must retain normal Data ownership invariants. Emission does not
modify/reorder IR, free byte items or change scalar analyses.

## Emission and runtime contract

Each object selects `.bss` or `.data` before its existing alignment/linkage/type
header. BSS payloads emit one `.zero` of the validated byte length; zero-length
objects emit none. Existing `.balign`, optional `.globl`, `.type @object` and exact
`.size` directives remain in force. Nonzero objects retain exact packed field
emission, including numeric-only string byte directives and long relocations.

The ELF loader provides initial zero bytes and writable storage. This is not
uninitialized stack memory, an implicit interpreter object, or a new `.comm`/TLS/
section-linkage feature. Interpreters retain `UnsupportedSymbolAddress` for reached
global references. No host pointer conversion or caller Image initialization/growth
occurs. Native validity/extent/lifetime/signature requirements remain caller contracts.

Objects may occupy different sections and addresses than before. There is no
cross-object adjacency, ordering, distance or empty-object uniqueness promise.
DATA.md's16MiB/object and64MiB/module **payload** caps remain unchanged and exclude
alignment gaps and compiler metadata. Fixed native stack-frame limits are separate.
No shared-library policy, complete BSS/data ABI or performance superiority is claimed.

## Independent bounded verification

Four unit tests check raw-bit classification, signed floating zeros, byte slices,
empty data, unknown symbolic references, exact section/directive selection,
validation precedence and exhaustive parser/emitter allocation cleanup. They also
verify emission preserves the original byte-slice pointer/contents and object table.

`native_bss_check.py` uses explicit independent byte patterns and C expectations,
not the classification helper's answer. Across each option combination it checks
**877 non-PIE +885 PIE** initial-byte/address/mutation results and **16** linked ELF
section-kind/size/binding/alignment records. Negative-zero and pointer objects must
be PROGBITS; all-zero cases must be NOBITS. PIE requires nonzero high address bits.

Two additional data-only executables each contain four16MiB BSS objects, exactly
the64MiB module payload cap. Every byte is checked zero initially; both ends of
every object are written and every byte is rechecked against the complete expected
contents. ELF sizes/sections are independently inspected and each linked file must
remain at most128KiB. This tests one bounded sparse-file behavior, not general speed,
memory use, compiler throughput or artifact-size superiority. All prior harnesses,
generators, fixtures/oracles and rejection expectations remain in force. Actual
full-matrix and exact-SHA CI results belong in HANDOFF.md.
