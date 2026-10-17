# Native scalar variadic definitions and vastart

The Linux AMD64 scalar slice accepts one final `...` marker in a function header,
including a sole marker. `Function.variadic` defaults false; named parameters keep
their existing identities and base/subword ABI annotations. The marker is not an
SSA value, named parameter or implicit promotion. Missing commas, repeated/nonfinal
markers and trailing commas are rejected. Aggregates, combined environment/variadic calls, other
platforms and full ABI/backend parity remain outside this slice.

```text
function l $first(w %anchor, ...) {
@entry
    %list =l alloc16 24
    vastart %list
    %value =l vaarg %list
    ret %value
}
```

## Checked direct signatures

A known variadic definition requires a marked direct call with marker position
exactly equal to its named parameter count. All named types/subword annotations
and return presence/class/annotation match exactly. Variable tail count/types are
runtime consumer contracts, not inferred from the body or converted implicitly.
Ordinary functions still require an unmarked call with exact complete arity.
Validation is eager for all bodies, including unused/unreachable calls. External/
indirect identity and complete runtime types remain caller contracts. C variable
arguments require explicit default promotions, as in VARIADIC-CALLS.md.

## Owned fixed register-save area

Each variadic native invocation reserves a separate176-byte area: GP6×8 followed
by SSE8×16. The region starts16-aligned below the existing aligned homes, phi
scratch and saved-original region, and above the outgoing reservation. It counts
against the existing64KiB fixed-frame cap and uses the same page-wise probes.
Existing RBP-relative home/scratch/saved offsets do not change. Outgoing slots and
dynamic allocations stay disjoint, including when an object is smaller than the
outgoing reservation. Normal function return releases this invocation's area.

The prologue first reserves/probes the complete fixed frame and saves original
callee-preserved registers. It then saves all incoming GP and XMM bank bits before
parameter scratch homing. SSE saves are unconditional raw moves, not arithmetic
or an AL-sensitive conditional save. No uninitialized argument is interpreted as
a language value; unused hardware register bits may be stored but remain unused.
Nonvariadic functions add no region or register-save instructions. This does not
change caller-side AL setup or introduce a caller-owned save area.

## Effect-only initialization

`Instruction.va_start` stores a long list operand by value; `appendVaStart` checks
an open block, variadic function flag and long operand before publication. It has
no result or dummy SSA value. Structural validation also rejects forged use in a
nonvariadic function or a wrong list class. Allocation failure publishes nothing;
retained capacity is allowed. Operand iteration and independent analysis oracles
cover the list separately. Folding preserves initialization as an ordered write,
including unused/repeated initialization.

`vastart` initializes a caller-provided live24-byte descriptor (VAARG-CONSUMERS.md):
GP offset8×occupied named GP registers; SSE offset48+16×occupied named SSE registers;
overflow pointerRBP+16+8×named overflow slots in declaration order; register-save
pointer to this invocation's owned region. Reinitializing resets consumption.
Copies share the saved bytes but have independent cursors. The descriptor and its
saved-area pointer must not escape the invocation's lifetime. Native address/
width/alignment/argument-type validity remain caller contracts; initialization is
not bounds checked or promised fault-atomic for invalid addresses. There is no
implicit descriptor allocation, va_end runtime helper or host pointer sandbox.

## Explicit interpreter boundary

Root evaluation accepts only the existing exact named argument array. No-varop
paths can execute; extra root arguments remain ArgumentCountMismatch. A reached
vastart consumes its ordinary step then returns UnsupportedVariadicOperation,
without resolving/writing the descriptor, even with valid Image/stack/global
options. Existing setup/argument preflight and earlier budget exhaustion win;
earlier Image writes persist and owned frames clean up.

Module evaluation refuses a reached internal call to a variadic definition with
UnsupportedVariadicCall after lookup and instruction step, before depth checks,
argument resolution or child-frame construction. It never silently drops tails
or pretends a named-only frame can consume them. Standalone reached calls retain
UnsupportedCall, external/indirect dispatch refusals remain unchanged, and eager
signature errors still precede execution. This is not variadic interpretation,
construction of native/host va_list objects or arbitrary host invocation.
The separate opt-in manual synthetic consumer (INTERPRETER-VAARG.md) does not
change these vastart, root-arity or internal variadic-call refusals.

## Regression approach

Direct tests cover header state, exact named signatures, builder/public-metadata
failure atomicity, frame alignment/cap, save-before-homing, ordered effects,
refusal/safe paths/budget/write precedence and exhaustive allocating cleanup.
Native tests use independent C promoted values and explicit observations of narrow
fixed arguments, mixed named register/overflow banks, all scalar/subword returns,
compiled marked direct/indirect callers and C readers consuming compiled-created
va_list descriptors. Reset/copy/loop/recursive behavior, live descriptor/object
state across calls, outgoing reservation, preserved originals and protected-stack
probe negative controls are exercised in PIE/nonPIE and every option combination.
Actual completed results and corrections are recorded in HANDOFF.md, not assumed.
