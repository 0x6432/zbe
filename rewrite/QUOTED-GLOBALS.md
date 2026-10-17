# Bounded decoded quoted global names

The independent frontend accepts `$"name"` in all existing global-name positions:
function/data definitions, direct calls, long scalar symbol/offset operands and
long data relocations. The **decoded name** must be nonempty printable ASCII
(bytes32–126), exclude `@`, not be the single dot, and not start with the
compiler-private `.Lzbe@`. The explicit `@` exclusion prevents GNU relocation
suffixes and ELF symbol-version syntax from being interpreted despite quotes;
it is not an incomplete keyword blacklist. Escaped `@` is excluded after decoding
too. Pool keys themselves remain unrestricted.
Leading/trailing spaces and punctuation are retained, not trimmed/interpreted.
Unquoted names keep their existing lexical grammar and exact assembly spelling.
This is a bounded Linux ELF/executable slice, not Unicode/global identifier parity,
other assembler/object targets, arbitrary expressions or full QBE compatibility.

```text
export data $"two words" = { l 11 22 }
export function l $"read second"() {
@entry
    %value =l loadl $"two words"+8
    ret %value
}
```

## Decoding and ownership

Quoted names reuse DATA-STRINGS.md's independently owned byte decoder: escaped
quote/backslash, bounded hexadecimal(two digits)/octal(up to three digits) and the
listed short escapes. Decoded control bytes/NUL/DEL/non-ASCII are rejected even
when that escape is valid for data bytes. Empty, dot, `@`, private-prefix and malformed
escapes reject at the original quoted-token span. Bare literal syntax, temporary/
block/type names and strings as ordinary operands do not gain new forms.

The parser validates/counts/allocates decoded bytes, interns them into the module's
stable individually owned pool, then frees the temporary buffer. Definition/call/
initializer/operand consumers receive pool-owned stable text, never that freed
buffer or a borrowed pointer into an overwritten input. Failure frees all partial
parser/module/decoder ownership. Failed additions may retain interned pool strings,
as with existing builders, but never incomplete function/data records.

Quoted/escaped/bare spellings with the same decoded bytes share a SymbolId and
known signature identity; duplicate decoded function/data definitions are rejected.
Names remain case-sensitive. This is this rewrite's explicit logical-name model,
not a claim to preserve the bundled reference parser's raw quoted-lexeme identity
or every assembler escape extension. The Pool API itself still accepts arbitrary
string keys; module semantics remain target-independent, while native emission
validates every used name, including manually constructed/unreachable references.

## Checked native formatting

Private typed name/reference formatting covers .globl/.local, .type, labels, .size, direct
calls, RIP-relative symbol/offset operands and long data relocations. Existing
bare names are emitted byte-for-byte as before. Non-bare printable names are
surrounded by assembler quotes, with quote/backslash bytes escaped. No raw source
quoted lexeme is inserted as assembly syntax. The private `.Lzbe@` namespace stays
unavailable even through quoted or manually built names, preserving branch/phi/
vaarg helper-label isolation. Accepted literal punctuation is never a directive, relocation suffix, version or addend.

GNU x86's instruction operand scanner cannot directly consume a quoted symbol
ending in a backslash, even though the directive parser accepts its exact name.
For those instruction references only, emission declares a private SymbolId-based
.set alias and uses that alias in the call/RIP operand. Definitions/metadata/data
relocations retain the original quoted name, including undefined external symbols.
No names are trimmed, rejected solely for that suffix, or renamed in ELF. Alias
emission is local to actual references, never arbitrary unused Pool strings;
repeated declarations resolve the same immutable symbol without allocating maps.
The private alias namespace cannot collide with accepted user names or existing
function/block/allocation/conversion/vaarg helpers.

Scalar addends remain checked i32 and data addends checked i64, printed outside
the completed quoted name; negative minima are never negated. ELF binding/type/
size, BSS/data placement, executable PIE/nonPIE behavior and the small-code-model
relocation contract remain unchanged. This does not add TLS, GOT/shared-object
interposition policy, runtime symbol lookup, automatic C identifier aliases or
new address arithmetic. Native pointer extent/lifetime/signature contracts remain.

## Analyses and evaluation

The representation is still an owned module SymbolId, not a new SSA operand/tag.
SSA/liveness/interference and integer folding do not infer numeric address bits
from spelling. Existing synthetic globals resolve module-defined data identities
under the same explicit option, including bounded data-only relocations, byte
order, reset and cleanup rules. Default/undefined/function-address refusals remain
unchanged; no decoded name triggers host lookup, host-pointer conversion or
implicit Image resizing. Direct known signatures work across spelling aliases.
Environment and variadic call boundaries remain their separately documented slices.

## Independent checks

Unit tests cover canonical identity/input lifetime, duplicates, token diagnostics,
invalid public metadata, private labels, all emission contexts, exact assembly
identity for quoted-bare versus bare source, synthetic globals/both byte orders
and exhaustive decoder/parser/analyses/evaluator/formatter failure cleanup. The
fixture joins both independent use-oracle corpora without introducing a fake use.
Native tests compare decoded ELF64 symbol-table bytes/binding/type/size against
independent expected names, not production formatting, and link external assembly
oracles. They exercise punctuation/quote/backslash/directive-looking names,
function/data/BSS, direct/indirect and env/variadic calls, signed scalar/data
relocations including i64 boundaries, phi/loads/stores/sentinels, preserved homes,
PIE/high addresses/nonPIE and rejection/output preservation. Actual completed
results are recorded in HANDOFF.md; this document does not itself assert success.
