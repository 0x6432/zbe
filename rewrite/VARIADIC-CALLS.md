# Variadic scalar call sites only

The Linux AMD64 slice accepts one literal `...` marker in a direct external or
long-address indirect scalar/void call argument list. It records the number of
named arguments before the marker. The marker is not an argument, SSA value or
implicit type conversion. Native variadic definitions/vastart are a separate slice
(VARIADIC-FUNCTIONS.md);
aggregates and environment calls remain unsupported.

```text
%count =w call $snprintf(l %buffer, l 64, l $format, ..., w 123, d d_1.5)
%result =l call %callback(w 3, ..., w 7, l 9, d d_2)
call $effect(w 1, ..., w 17, d d_2)
```

A sole marker (`...`), initial marker (`..., w 7`) or final marker (`w 7, ...`)
is accepted; a final marker means zero variable arguments. These are typed IL
contracts, not statements that every such list is a legal C prototype. Duplicate
markers, missing commas and a trailing comma remain invalid. Ordinary module-
defined functions remain nonvariadic unless explicitly declared
with a final header marker. Marked calls to ordinary definitions return
`CallSignatureMismatch`, including unreachable/unused calls; marked known variadic
calls require the exact named prefix (VARIADIC-FUNCTIONS.md). Passing a marker does
not turn an ordinary
function definition into a variadic function.

## Explicit types and C default promotions

The marker does not promote any argument. Existing scalar classes, subword ABI
annotations and explicit low-word projections retain their ordinary rules.
When calling C, the IL author must explicitly provide C default promotions:
fully defined word values for small integers and double values for floating
variable arguments, with the appropriate preceding extension or `exts` instruction.
A raw single or subword variable argument is not automatically made compatible
with C `va_arg(double)` or `va_arg(int)`. Signedness, pointer validity, external/
indirect identity and complete runtime signature validity remain caller contracts.
Supporting the syntax is not a native safety/type-checking guarantee.

## Typed owned construction and validation

`ir.CallOptions` contains an optional typed result annotation and optional
`variadic_start: usize` prefix count. `Function.appendCall` accepts an optional
pending result, typed `CallTarget`, argument slice and options for checked common
construction. Existing direct/indirect/scalar/void/subword builder APIs remain
wrappers with null marker defaults. `Instruction.call` owns its copied argument
slice and stores the prefix as value metadata, not an aliased slice into parser
storage. Existing result/argument annotation consistency checks remain in force.

A prefix larger than the argument count returns `InvalidVariadicMarker` before
allocation/publication. Publicly forged metadata is also rejected by structural
validation, including on void calls. Failed type/target/index checks or allocation
leave pending result/instruction publication unchanged; retained capacity growth
is permitted. The marker never enters operand iteration or data-flow analyses;
real target/argument operands retain independent SSA/liveness/interference checks.
Folding preserves calls and all marker/signature metadata as ordered effects.

## AMD64 lowering

Argument locations remain the independent six-GP/eight-SSE banks and declaration-
ordered8-byte overflow slots. The outgoing frame reservation, probing, dynamic
allocation offset, R11 indirect target and result homing are unchanged. After all
arguments have been marshalled, immediately before a marked direct/indirect call,
the emitter writes AL with the exact occupied SSE-register count from the existing
argument cursor. This includes named single/double arguments and caps at8; it is
not merely the count after the marker or the total including stack-passed floats.

AL must be set even when zero: an earlier integer load may have left arbitrary
low accumulator bits. Loading it before ordinary argument marshalling would be
incorrect. The target remains R11, not RAX, through this final setup. Nonvariadic
calls emit no new AL move; an independent emission comparison verifies that
removing the one marked-call move restores the otherwise identical assembly.
No caller-side variadic register-save area is invented; variadic callee prologues/
va_list initialization belong to the callee (VARIADIC-FUNCTIONS.md), not the caller.

## Interpreter and unsupported boundaries

The evaluator does not execute variadic calls through C, host pointers or native
fallback. Standalone reached calls remain `UnsupportedCall`; module evaluation
still returns `UnsupportedExternalCall`/`UnsupportedIndirectCall` for those targets,
with ordinary instruction-step/depth/dispatch precedence and owned cleanup.
Call-free paths stay evaluable. A known nonvariadic signature mismatch is eager
module validation, not a reached instruction fault. Synthetic global/stack/Image
ownership and earlier successful writes are unchanged.

This is not full variadic ABI support, variadic function interpretation, aggregate
classification, environment/varargs combination support, another platform/target,
C default-promotion inference or complete QBE/backend parity.

## Independent regression approach

Unit tests cover prefix grammar/identity, no fake operand/promotion, common typed
builder allocation retry/argument ownership, forged indices, defined-nonvariadic
mismatch, unchanged nonvariadic assembly versus exactly one final AL move,
0..8 saturation/named SSE counting, direct/indirect ordering, safe/refused interpreter
paths, effect/folding and exhaustive allocation failure. The fixture joins both
independent analysis-oracle corpora without modifying their use switches.

A dedicated native harness uses generated C stdarg helpers with explicitly promoted
variable types, independently weighted unsigned64 expectations and all scalar/
subword return observations. Mixed named/variable banks overflow in both orders.
Assembly AL probes include named-only/empty/no-SSE/>8-SSE lists and a final integer
load deliberately poisoning AL before correct setup. PIE/nonPIE tests also cover
indirect targets, snprintf into caller-owned memory, void/unused effects, phi
loops, a dynamic object smaller than its outgoing overflow reservation and full-
width preserved originals. All subprocesses have finite timeouts. Actual verified
counts/results and any corrections are recorded in HANDOFF.md.

A separate consumer-only slice now accepts scalar vaarg using a caller-supplied
native descriptor in ordinary functions (VAARG-CONSUMERS.md). Native headers/vastart now reuse this consumer in VARIADIC-FUNCTIONS.md;
interpreter descriptor emulation remains unsupported.
