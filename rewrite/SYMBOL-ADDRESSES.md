# Typed long symbol-address operands

The scalar frontend accepts an unquoted `$symbol` in a **long** operand context:
copy, return, long arithmetic/comparison, long phi input, long call argument,
allocation size, memory address or long store value. This is an address expression,
not a scalar load, numeric constant or ordinary SSA definition. Symbol IDs belong
to the module's owned symbol pool. Function-only structural checks know its long
type; module validation additionally checks every ID, including unreachable blocks,
phi inputs, call operands and terminators. Owner scope remains a caller invariant.

Bare symbols are deliberately long-only in this subset. To project low bits, first
copy the symbol to a long temporary and use that temporary in a word context.
Direct `$symbol` callees keep their existing meaning and known-signature checks;
a long temporary containing a function address can be an indirect target. No
symbol-plus-offset literal, quoted-symbol support or relocation
initializer, implicit floating bit pattern, linker resolver or full ABI is added.
Existing long arithmetic can form runtime byte offsets after taking an address.

Instruction operand iteration returns the copied symbolic operand, but
referencedValue returns null: a linker symbol is not a function-local live value.
The integer folder treats symbol addresses as unknown, preserving reached address
materialization and never assuming numeric layout, identity or equality.
Independent liveness/interference oracles retain separate operand switches.

## Linux AMD64 executable lowering

Each materialization emits `leaq symbol(%rip), scratch64`. This takes the complete
address; it does not read the object's contents or emit a truncated immediate.
Existing value homes, phi scratch, indirect-target capture and argument banks are
unchanged. Every used scalar symbol spelling passes the same emitter validation
as function/direct-call names before any assembly is returned. Invalid IDs/names
cannot be inserted into assembler text through operands, even on unreachable paths.

The linker supplies external data/functions. This implementation supports the
existing Linux AMD64 executable slice (PIE and non-PIE). It does **not** implement
GOT/preemptible shared-object policy, arbitrary code models, dynamic loader symbol
lookup, symbol visibility/TLS or full PIC support. Numeric/zero-fill data definitions are
now implemented separately (DATA.md), without relocation initializers. Address reach
and relocation validity remain assembler/linker contracts; native dereferences
still require valid extent/lifetime/permissions and are not sandboxed.

## Interpreter boundary

Resolving a reached symbol address returns `UnsupportedSymbolAddress`, including
with Image or stack_memory enabled. No host lookup, host-pointer cast, fabricated
synthetic address or Image resizing occurs. Unreached symbol operands do not fail
otherwise evaluable paths. Every instruction/phi/terminator first consumes its
ordinary step, so earlier exhaustion wins. Calls keep existing dispatch precedence:
standalone UnsupportedCall or module external/indirect/depth rejection can precede
argument resolution. Earlier Image writes persist and all owned frames/objects
clean up. This is an explicit unsupported boundary, not QBE invalid-program semantics.

Actual verification results are recorded in HANDOFF.md. Native regressions compare
addresses against independently linked C objects/functions under PIE/high-address
and non-PIE conditions, plus initialized byte/ABI/phi checks. Existing generators
and correctness fixtures remain unchanged.
