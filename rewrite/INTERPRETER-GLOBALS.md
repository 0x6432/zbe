# Opt-in initialized synthetic module globals

`interpreter.Options.global_memory: ?GlobalOptions` defaults to null. With it,
`evaluateModule` deep-copies numeric/raw-floating-bit, zero-fill and owned-string
module data into a separate evaluation-owned synthetic address space. It never
resolves host/linker pointers, resizes the caller's Image, borrows writable module
bytes or changes native lowering. Without it, reached scalar symbols retain
`UnsupportedSymbolAddress`, including with Image/stack memory enabled. The
standalone `evaluate` has no module context: supplying global_memory explicitly
returns `GlobalsRequireModule`, rather than silently ignoring that configuration.

## Configuration and initialized ownership

GlobalOptions has `base: u64 = 0x200000000`, `max_bytes: usize = 1 MiB` and
`endian: std.builtin.Endian = .little`. Base must be nonzero and64-aligned. The
whole configured reservation must fit u64 and be disjoint from any nonempty
borrowed Image and the whole configured nonempty stack reservation. Empty
reservations contain no addresses for overlap purposes, but base constraints
still apply. Range errors are `InvalidGlobalRange`.

Objects follow module declaration order for this model, with their declared
alignment, exact packed payload and16 inaccessible guard bytes after each object.
Alignment gaps, payload and guards all count against max_bytes. A zero-length
object still charges alignment/guard, obtains a distinct synthetic address, and
has no dereferenceable bytes. This is an explicit model layout, not a native linker
cross-object layout promise. Exceeding the reservation is `GlobalLimitExceeded`.
The cap also bounds object count via guards, not parsing/analysis/whole-process
resources or allocator metadata. Existing module/object payload caps still apply.

Initialization is eager: all data lengths, layout and supported initializer forms
are checked before table/payload allocation. Symbolic initializers may refer only
to defined module Data objects, with checked signed i64 address arithmetic
(INTERPRETER-DATA-RELOCATIONS.md). Function/external initializers, even in an unused
object, cause `UnsupportedGlobalInitializer`; there is no function-pointer or
host/linker resolver in this slice. Every ordinary scalar field
is packed in the selected byte order, without implicit field padding; zero runs,
raw floating bits and copied string bytes retain their exact payload. All bytes
are initialized. The module's Data items, byte slices and IR remain unchanged.

Module/SSA validation and the existing zero-depth check precede memory setup.
Existing stack/Image range checks precede global setup; global setup precedes root
argument-frame creation and instruction execution. Consequently opted-in
configuration/initialization errors can precede argument or zero-step errors.
Setup/validation/byte counts do not consume IL instruction steps. This eager
boundary is explicit; it is not a change to the default reached-symbol contract
or a claim about QBE invalid-program error ordering.

## Resolution, access and lifetime

Bare and checked-i32-offset scalar operands resolve only **defined data** symbol
IDs to synthetic integers. Function/external symbols still return reached
`UnsupportedSymbolAddress`. Offset arithmetic is checked against u64, with
`GlobalAddressOverflow` on overflow/underflow; minInt(i32) is widened before taking
its magnitude. Resolution does not prove dereferenceability: zero/one-past/outside
object addresses are merely integers until an access checks the complete extent.
Numeric forgery into a valid region remains allowed, as in Image/stack memory;
this is not a capability/provenance system.

Loads/stores require a single complete object span. Gaps, guards and multi-object
spans are inaccessible. Scalar accesses retain their exact type/width rules and
unaligned access support. Blits between globals, Image and live stack objects
resolve both full spans and reject partial overlap or uninitialized stack source
before mutation; zero-count and exact-alias rules remain unchanged. Bytes copy
without endian conversion; subsequent scalar reads use the destination region's
byte order. Failing accesses change no destination bytes.

One global owner is shared across all invocation frames and is separate from
stack object marks. Child returns release their stack objects, never globals.
Global writes remain visible to later instructions/callees in the same evaluation.
Every global allocation is freed on root return or any error. A new evaluation
starts from fresh module data: no persistent global mutation or cross-evaluation
address provenance is promised, and the configured namespace may repeat. Escaped
numeric addresses confer no later authority. Earlier successful caller Image
writes survive later global/access/step/call errors, as before.

Every reached phi/instruction/terminator consumes its ordinary step before symbol
resolution. Call dispatch still rejects external/indirect calls or depth overflow
before argument resolution; configuring globals does not authorize host calls.
Integer folding remains unaware of address layout or mutable global bytes. Native
addresses, stack allocation, ELF data/relocations and caller ABI remain unchanged.

## Regression design

Tests reuse unchanged independent numeric/string byte-oracle files, plus explicit
hand-written big/little-endian packed expectations including raw signaling-NaN
bits. They cover deep ownership, alignment/guard/cap/empty/u64/overlap boundaries,
signed address arithmetic, scalar and cross-region blit atomicity, initialized
versus undefined bytes, nested calls and stack release, reset/IR isolation,
configuration/default/refusal and step/error precedence, earlier Image writes and
exhaustive allocation-failure cleanup. The full existing native and generator
matrix remains required. HANDOFF.md records actual outcomes; this is not full QBE
global/relocation/interpreter semantics, persistence, ABI/target parity or native
memory safety/performance proof.
