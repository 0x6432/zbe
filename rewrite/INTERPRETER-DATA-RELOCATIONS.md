# Internal-data-only synthetic initializers

The opt-in `Options.global_memory` model (INTERPRETER-GLOBALS.md) accepts existing
long symbolic data initializers **only when their symbol names a defined Data
object in the same module**. No new parser expression or IR variant is introduced.
An existing `data.SymbolAddress` retains its module-pool ID and checked signed i64
addend; it is never rewritten to a host pointer or numeric constant in module IR.

Forward, self and mutual data references use the guarded synthetic layout's object
addresses. Initializing a reference does not read/evaluate the target initializer
or recursively follow a pointer chain. Every initializer still occupies exactly
eight packed bytes, including in an unaligned mixed record. Numeric/raw-floating,
string and zero items retain their existing bytes and widths. All initializer
addresses are encoded using GlobalOptions.endian. Export linkage has no host or
linker lookup meaning in this model.

Function or undefined/external targets remain eager
`UnsupportedGlobalInitializer`, including in unused data or on a safe program path.
A function symbol is not reclassified as data, nor is an external symbol assigned
a fabricated address. Scalar function/external addresses still return reached
`UnsupportedSymbolAddress`, indirect calls remain `UnsupportedIndirectCall`, and
known direct calls to data remain a module-validation error. With global_memory
null, existing default symbol refusal and safe paths stay unchanged.

## Arithmetic, preflight and owned transfer

Before table/payload allocation, setup validates data lengths, the full aligned/
guarded reservation, every target's defined-data membership and every signed i64
address addition against u64. The minimum i64 addend is widened before negation.
Invalid arithmetic returns eager `GlobalAddressOverflow`, not wrapping, saturating,
host-pointer conversion or a promise about native linker overflow behavior.
A valid result may be zero, one-past, max-u64 or outside its original object's
extent; it is an integer, not proof of dereferenceability. Any subsequent memory
operation still checks a complete live object span. Numeric forgery into another
valid synthetic object remains permitted, not a capability/provenance system.

Lookup is an allocation-free linear guarded-layout scan per reference, not a
recursive solver, symbol loader, optimized indexed linker or performance claim.
Module payload/guard reservation limits bound the stored data/object count; IL
step limits do not bound setup/lookup/analysis time. All opted-in eager setup
errors retain the ordering documented in INTERPRETER-GLOBALS.md and occur before
instruction steps or caller Image mutation. Normal reached load/call/fault/budget
ordering is unchanged after successful initialization.

Payload materialization has its own `errdefer` owner. A buffer transfers to the
outer object table only after complete initialization succeeds; the outer
initialized count frees only transferred objects on later failure. No new fallible
initializer action leaks a just-allocated unpublished payload or double-frees a
published one. Module Data items/bytes remain unchanged; global objects stay
separate from invocation stack marks, are freed on every root exit, and reset
from fresh module data on a new evaluation. Stored synthetic integers have no
cross-evaluation provenance guarantee, even when namespaces repeat.

## Independent regression approach

A new fixture has a hand-computed packed/guarded layout with forward, self,
mutual, byte-offset and empty-object references. Expected addresses/byte extraction
are independent of the production lookup/serializer. Tests cover both byte orders,
exact mixed-record extents, full signed i64 extremes producing zero/max integers,
underflow/overflow before allocation, function/external refusal, invalid-ID/size
validation precedence and Image preservation before eager failure. Interpreted
pointer loads, child calls, finite cyclic address chains, folding, stack/Image
blits, evaluation reset, empty-object access faults and step precedence retain
independent scalar/address expectations and earlier successful Image writes.
Exhaustive allocation failure spans parse, preflight/materialization, frames,
blits, errors and emission. Both independent analysis-oracle corpora include the
fixture without changing their operand-use switches.

Existing native data relocations and all prior generators, correctness fixtures
and native harnesses remain unchanged. Native addresses are not compared with
synthetic layout constants. Actual verification belongs in HANDOFF.md. This is
not function-pointer interpretation, external/linker resolution, persistent globals,
complete relocation/QBE semantics, platform/ABI parity or native memory safety.
