# alloc1 / alloc2 compatibility aliases

Pinned official QBE commit `e786f06032fefa2e3790d6b1c9e31ed138f475a6`
(`tools/qbe-ref.tar.gz`) defines `Oalloc = Oalloc4` in `all.h:183` and maps both
`Talloc1` and `Talloc2` to `Oalloc` in `parse.c:730–731`. `ops.h:126` requires a
long result and long size. These spellings are **normalized aliases of alloc4**,
not new one-/two-byte alignment classes or allocation behavior.

The rewrite frontend now maps both to existing `.four`. No new IR enum,
allocation owner, evaluator option or native lowering is introduced. Long SSA
size/result types, modulo-u64 integer literal parsing, failure-atomic building,
SSA/step validation, effect ordering and integer-folder non-deletion all remain
unchanged. Invalid types, extra/missing arguments and unrelated opcodes remain
rejected; no implicit word-to-long size conversion.

Native lowering remains over-aligned16 with checked `size+15` round-up, moving
outgoing argument reservations and the existing page probes. Zero size reserves
no new extent and promises neither distinctness nor dereferenceability. Huge
native extents can fault; round-up overflow traps with the existing `ud2` policy,
not newly specified QBE invalid-program behavior.

Reached interpreter allocation still defaults to `UnsupportedAllocation`, even
at size0 or with an Image; earlier step exhaustion wins. Explicit `stack_memory`
retains synthetic long addresses, zero→0, accessible requested bytes only,
16-alignment, `(roundUp(size,16)+16)` cumulative charge, checked overflow/caps,
uninitialized bytes and owner/frame cleanup. No host pointers, new object
lifetimes, implicit memory enabling or ABI changes. Existing allocation contracts
are in NATIVE-ALLOCATIONS.md and INTERPRETER-ALLOCATIONS.md.

Added focused alias tests compare normalized IR and byte-identical native
assembly against alloc4 in all folding/home combinations, but independently check
actual checksum values, synthetic address/cap boundaries and malformed/SSA/OOM
behavior. Native execution uses independent integer checksum expectations,
external mutation across outgoing stack/SSE arguments, preserved homes, zero and
page boundaries, and separately labeled invalid round-up trap checks. Full final
combined matrix remains required before publication; targeted passes alone are
not a new full-gate claim.
