# Owned numeric and zero-fill data definitions

The independent module owns separately allocated `data.Data` objects through typed
module-scoped `DataId` handles. Data pointers and interned names survive table
growth; item slices do not. Owner identity is still a caller invariant. Every
owner takes an allocator and has a matching `deinit`. An append reserves storage
before publishing its item and checked payload length; failed additions may retain
capacity or an unused interned symbol, never a partially published object.

## Accepted frontend subset

```text
[export] data $name = [align N] {
    b integer integer, h integer, w integer, l integer,
    s s_literal, d d_literal, z nonnegative-count,
}
```

Groups are comma-separated; each numeric group contains one or more matching
values. Whitespace/newlines and comments are accepted between data tokens; a
trailing comma and an empty object are allowed. Fields are **packed**, with no
implicit per-field padding. Explicit `z` groups introduce zero bytes and contain
exactly one nonnegative decimal count; zero is allowed. Numeric integer literals
use the existing modulo-2^64 parsing and truncate to the field width. `s` and `d`
require matching-width floating literal tokens, retaining the existing signed-zero,
infinity, plain-NaN and numeric conversion rules. NaN-payload spellings are still
explicitly unsupported, not silently discarded. Integer-to-float field coercion
and mismatched-width floating literals are deliberately outside this subset.

Alignment defaults to **8**; explicit powers of two from **1 through 64** are
accepted. This bounded choice follows the unchanged bundled reference parser's
current defaults/range, not a new all-target alignment guarantee. Empty objects
have size zero and promise neither unique addresses nor accessible bytes.

Prototype limits are **16 MiB payload per object** and **64 MiB payload per
module**. Checked additions reject overflow/excess with `DataTooLarge`; cached
size mismatches are `InvalidDataSize`. Validation recomputes every size before
emission or module interpretation. Limits exclude alignment gaps, item metadata,
source/token allocations and output text; they are not complete compiler resource
budgets. Builders enforce the object limit; module aggregate validation also runs
as each parsed data definition completes and at consumer boundaries.

Function/data symbols share one definition namespace. Builders reject cross-kind
or data/data duplicates with `DuplicateSymbol`; duplicate function diagnostics
remain unchanged. Module validation catches duplicates/invalid IDs after edits.
A direct call to a defined data object is rejected with `CalledDataSymbol` rather
than treated as an unknown external function. Indirect address calls still carry
the existing native caller contract, not pointer provenance or executable checks.

Unsupported quoted-name bytes/escapes (QUOTED-GLOBALS.md), unsupported string classes/escapes, general symbolic relocation forms,
thread/TLS, extern/section linkages and aggregate/full-data syntax remain
unsupported. This is not complete QBE data-language compatibility.

Long symbolic initializers with one checked signed addend are now supported
separately (DATA-RELOCATIONS.md); other relocations remain unsupported.

Owned byte strings in b-groups are implemented separately (DATA-STRINGS.md),
with explicit decoding, copied ownership and no implicit terminators.

## Linux AMD64 emission

Data are writable ELF objects: exact all-zero content uses `.bss`, while other
content uses `.data` (DATA-BSS.md). Objects retain checked `.balign`, optional
`.globl` for exported linkage, ELF `.type @object` and exact `.size` metadata.
Numeric fields use `.byte`, `.short`, `.long` or `.quad` raw-bit directives;
positive zero runs use `.zero`; all-zero BSS objects use one compact zero run. No padding is inserted inside objects. Object
alignment may introduce gaps between definitions. Every name, including unused
data, passes target symbol-spelling checks before any assembly is returned.
Data-only modules are valid compilation units. Emission does not modify IR.

Ordinary long `$symbol` address operands use the existing full-width RIP-relative
executable lowering (SYMBOL-ADDRESSES.md). PIE and non-PIE executables are covered;
there is no GOT/preemptible shared-library policy, arbitrary code model, TLS,
general relocation-expression support, sandbox or full ABI/platform parity claim.

## Interpreter boundary and independent checks

Definitions do **not** create implicit interpreter globals. Reached symbol-address
resolution remains `UnsupportedSymbolAddress`, including Image/stack-enabled
execution; no host address lookup, synthetic global allocation or Image resizing
occurs. Unreached references remain harmless, ordinary step limits retain their
precedence, and earlier Image writes survive later refusal. Data definitions are
validated before module execution, even if unused.

`generate_data_oracle.py --check` independently reproduces ten packed objects and
1,896 little-endian expected bytes using Python integer/struct arithmetic, never
compiler-produced expectations. Unit tests compare exact parsed bits/bytes and
cover alignment/defaults, malformed syntax, object/module caps, tampered sizes/IDs,
duplicate definitions, direct data calls, stable ownership, retry atomicity and
exhaustive injected allocation cleanup for builders, parser and emitter.

`native_data_check.py` accepts the three existing compiler flags. Per combination,
non-PIE and PIE executables check **7,856** and **7,866** byte/address/mutation
results respectively (the extra ten are explicit PIE/high-address checks). All
object bytes, including zero runs and unaligned fields, are compared to independent
expectations before and after compiled/C writes; internal data are reached through
compiled accessors, calls preserve addresses, and global blits retain sentinels.
The harness also checks **20** linked ELF size/binding/alignment records, **2**
data-only executable links and **48** rejection/output-preservation cases. Existing
symbol rejection counts remain unchanged: only the now-valid numeric-data negative
was replaced by a still-unsupported symbolic-relocation initializer. Actual full
matrix/CI results are recorded in HANDOFF.md rather than assumed here.

## Explicit module-global evaluation

Opt-in initialized globals use a separate owned synthetic model
(INTERPRETER-GLOBALS.md), including defined-data-only symbolic initializers
(INTERPRETER-DATA-RELOCATIONS.md). Defaults still refuse symbols; function/external
addresses remain unsupported. Image ownership and native linker/stack behavior
do not change.

Bounded printable-ASCII quoted globals decode to owned canonical symbol names
across definitions/calls/scalar operands/data relocations (QUOTED-GLOBALS.md).
Native formatting escapes non-bare names while preserving existing bare output
and the private-label namespace; no host lookup or full identifier/target parity.

Zero-fill `common data` is a separate bounded ELF linkage slice (DATA-COMMON.md).
It accepts only z-groups or an empty object, not arbitrary zero-valued fields.
Common/export flags are independent; default explicit alignment remains8.
