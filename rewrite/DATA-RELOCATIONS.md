# Typed long symbolic data initializers

A long data group may contain an unquoted `$symbol` optionally followed by `+`
and a **signed 64-bit decimal addend**. Numeric long items and symbolic items can
be mixed in the same group. Each symbolic initializer occupies exactly eight
packed bytes. Definitions, numeric groups, zero runs, alignment/linkage and size
limits retain DATA.md's contracts.

```text
export data $table = align 16 {
    l $buffer $buffer+8 $buffer+-8,
    l $callback $table 17,
}
```

`data.SymbolAddress` retains a module-pool `SymbolId` and `i64` addend, never a
host pointer. Symbols may name forward definitions, data, functions, self/cyclic
references or contracted native externals. The compiler does not require external
definitions or resolve them during parsing. Module validation checks every symbol
ID, including unused data; target emission also checks each referenced spelling
before returning any assembly. Owner scope remains a caller invariant.

Unlike ordinary integer data literals, addends are **range-checked**, not wrapped.
The full interval -9,223,372,036,854,775,808 through 9,223,372,036,854,775,807 is
accepted. Newlines/comments are permitted around the explicit plus and signed
integer. A bare minus is not an offset operator: `$symbol-8` tokenizes as two
long-group items (`$symbol` and numeric `-8`), exactly like `$symbol -8`.
Use `$symbol+-8` to request a negative addend. A separated lone `-` is invalid.
Ordinary scalar `$symbol+offset` operands remain unsupported; they still require
explicit runtime long arithmetic.

Byte/half/word/single/double/zero symbolic initializers, quoted names,
symbol differences, TLS/extern modifiers, GOT/section/common policy and relocation
expressions other than one checked addend remain unsupported. This is a narrow
pointer-table slice, not complete QBE data syntax or a portable pointer model.
Owned byte strings are supported separately in b-groups (DATA-STRINGS.md).

## Linux AMD64 executable behavior

The emitter uses full-width `.quad symbol`, `.quad symbol+N` or `.quad symbol-N`
in writable `.data`. It prints a negative signed addend directly, including the
minimum, without negating it. No linker references are inserted into code or
read-only sections by this feature. GNU assembler/linker/dynamic-loader behavior
supplies the actual executable address bits; numeric addition can wrap at64 bits.
There is no bounds, pointer provenance, lifetime, executable-target or permissions
check. Only valid object spans/function signatures may be dereferenced/called.
Native checks of extreme addends compare address **bits only**, never dereference
them or assert that they designate valid objects.

Both non-PIE and PIE executable linking are covered, including high-address
preconditions and absence of `DT_TEXTREL`. No arbitrary code model, preemptible
shared-object/interposition, dynamic symbol lookup or TLS policy is promised.
Object size/binding metadata and writable-table behavior remain explicit.

## Interpreter and verification boundaries

Definitions and symbolic initializers do not synthesize interpreter globals.
Reached ordinary symbol-address resolution is still `UnsupportedSymbolAddress`,
including stack/Image-enabled evaluation. Module validation still runs first, so
invalid unused initializer IDs reject even otherwise safe entry paths. There is
no host-pointer cast, native fallback or automatic Image resize/population.

Five unit tests cover raw symbol identities, signed range edges, mixed/packed
layout, forward/self/external references, grammar boundaries, unused malformed
IDs/names, failure-atomic retry/size caps, interpreter refusal and exhaustive
parser/folder/emitter/partial-parse allocation cleanup. The independent numeric
byte generator and its fixture bytes remain unchanged; the numeric test's new
union arm explicitly rejects a symbolic item in that corpus.

`native_relocation_check.py` accepts the existing three flags. Per combination it
checks **324 non-PIE +327 PIE** linked address/callback/mutation results, including
internal/external function tables, full-width signed addends, self/forward cycles,
unaligned pointer fields, C/compiled table replacement, compiled stores through
pointers and complete sentinel comparisons. It also checks **12** ELF object
metadata records, **2** no-text-relocation executables, **2** symbolic-data-only
links and **40** invalid-input/output-preservation cases. Only now-valid long-symbol
negatives in existing tests/harnesses are replaced by unsupported narrow forms;
counts and output-preservation oracles remain intact. Actual matrix/CI outcomes
are recorded separately in HANDOFF.md.
