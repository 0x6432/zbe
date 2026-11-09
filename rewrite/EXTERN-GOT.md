# Experimental extern/GOT operands

**Draft implementation; not yet accepted as a complete compatibility endpoint.**
The syntax below is specific to the experimental Linux AMD64 rewrite. It does
not enable TLS, global declarations, data initializers, new linkage forms,
aggregate interpretation, or a general PIC guarantee.

## Syntax and meaning

`extern` is contextual, not a reserved identifier. It precedes a global token
on the same logical line and denotes the resolved **address**, not the value
stored at that address and not the address of the GOT slot:

```text
function l $address() {
@entry
ret extern $external_data
}
function l $invoke(l %x) {
@entry
%r =l call extern $external_function(l %x)
ret %r
}
```

The operand is a long value; for word uses, materialize it as long and use the
existing explicit low-word rules. Whitespace between `extern` and the global
is allowed, but a newline or comment newline is not. An addend after an extern
symbol, including `+0`, and stacked linkage modifiers are rejected. Existing
ordinary symbol and symbol-plus-offset syntax is separate and unchanged.

Native extern names are decoded and interned once in the owning module. The
supported native subset starts with an ASCII letter or underscore and continues
with ASCII letters, digits, underscore, dot or dollar sign, subject also to the
existing portable-name and reserved-namespace checks. For example, `name`,
`_name`, `a.b` and `a$b` are in that subset; leading dots and spaces are not.
A valid source name outside the subset is retained in IR but native extern
emission refuses it with `UnsupportedExternSymbol`. Ordinary symbol uses do not
acquire this new restriction.

## Calls and evaluation

On Linux AMD64, the native emitter loads the pointer through `@GOTPCREL` and
uses an indirect call for an extern target. Existing scalar/record argument,
result, ENV and variadic boundaries still apply. Declared, known functions and
data retain the existing nominal signature and called-data checks; a symbol
with no module-local definition remains a linker/caller contract. This does not
export local definitions or guarantee that a function pointer is the ultimate
machine-code entry address rather than the ELF-canonical address.

The interpreter does not access a host loader or host pointers. A reached GOT
operand refuses with `UnsupportedSymbolAddress`; a reached module-owned extern
call refuses with `UnsupportedIndirectCall`, while standalone evaluation without
a module refuses a reached call with `UnsupportedCall`. Unreached operands are
not evaluated, though generic validation still checks the whole module.

## Verification boundary

Focused parser, ownership, allocation-frontier, interpreter, native ABI and
loader tests exist in this draft. They do **not** yet establish the complete
ABI/loader/mutation ledger, predecessor byte identity, or full acceptance.
The separate integration gate and exact-tree reviews remain outstanding. See
[EXTERN-GOT-WIP.md](EXTERN-GOT-WIP.md) for the current evidence and gaps.
