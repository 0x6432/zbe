# Bounded zero-fill common data (Linux AMD64 ELF)

`[export] common data` and `common [export] data` accept independent common/export
flags, each at most once, including intervening newlines. Common applies only to
data. Empty `{}` and any sequence of `z` groups (including `z 0`) are accepted.
All typed initializers are refused, including numeric/float positive zero, empty
strings and symbol references. This follows the pinned QBE parser/emitter source
(e786f06032fefa2e3790d6b1c9e31ed138f475a6), not a documented portable IL extension.
The pinned public linkage documentation does not describe common.

Common is a separate boolean from ordinary visibility; optional export is retained
but ELF common symbols are global either way. Default explicit alignment remains8,
allowed powers of two1..64, and existing16MiB/object,64MiB/module caps remain.
Append rejects a non-z item before allocation/publication. Public validation also
rejects mutated invalid common IR and checks cached lengths; no all-zero byte
classifier substitutes for z-only validation. Same-module canonical duplicate
symbols remain errors, including common/strong/function collisions in either
order. Cross-object linker coalescing is not same-module redeclaration support.

Native emission is exactly `.comm name,size,alignment`, with existing safe quoted
symbol formatting. No ordinary label/BSS/.size is emitted for that object. GNU as
ELF third operand is a BYTE alignment, not log2. In unlinked objects SHN_COMMON
and st_size identify tentative storage; st_value is alignment, not an address.
The tested default assembler policy yields GLOBAL/OBJECT/DEFAULT/COM, including
size0. Empty common objects confer no dereferenceable bytes or distinct address.

GNU ld coalesces cross-object commons at largest size/alignment. A strong ordinary
initialized or BSS definition overrides common in either link order; it need not
inherit common size/alignment. Tests must never access beyond the winning strong
object. This is Linux ELF behavior, not all-target/shared-library/linker parity.
Official contracts: GNU as manual Comm, GNU ld --warn-common, ELF gABI Symbol Table.

Opt-in synthetic interpreter globals retain per-module fresh zero objects with
existing guards/caps and default refusal. They do not simulate cross-object
coalescing, overrides, host linking or native addresses; the empty object has no
accessible bytes. No new memory capability is enabled by a linkage flag.

Acceptance: independent object metadata/assembler probes, cross-object aliasing,
coalescing and strong/BSS override in both link orders, runtime zero/mutation and
PIE/non-PIE execution; invalid initializers/linkages, zero/caps/quoted names,
manual IR edits and every allocation-failure/retry. Preserve old fixtures,
generators/harnesses and unrelated refusals. Add a common-specific native harness
and CI invocation; run fresh3 unit modes, fmt, all existing generators, full24
native configs plus the new harness. Only actual logs establish verification;
exact-SHA CI remains required before a full-green claim. No tag/release.

Contract sources read during design:
- https://sourceware.org/binutils/docs/as/Comm.html
- https://sourceware.org/binutils/docs/ld/Options.html (warn-common)
- https://gabi.xinuos.com/v42/elf/05-symtab.html

### Quoted COMMON reference boundary

Independent review caught that GAS rejects the existing trailing-backslash `.set`
workaround when its target is SHN_COMMON. For **defined common objects only**
whose canonical names end in backslash, emit one private SymbolId-based full-width
pointer cell in fixed `.data.rel.ro.local`, using the already-supported `.quad`
directive spelling. Scalar address operands load that cell, then apply the checked
i32 addend with LEA. Original ELF identity and ordinary data relocation spelling
are unchanged; ordinary/undefined noncommon `.set` aliases stay as before.
Cells are emitted once per such common definition, even if unused, never for
arbitrary unused symbol-pool strings. This introduces bounded internal relocation
storage, not user section syntax, constructors, executable-text relocation, host
lookup or extra IL steps. GNU executable PIE/non-PIE and strong override must
resolve the same identity through both scalar and initializer paths. No shared-
library interposition/GOT policy or performance claim is added.
