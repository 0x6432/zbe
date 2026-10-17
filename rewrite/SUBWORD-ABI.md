# Typed subword scalar ABI annotations

The Linux AMD64 scalar slice accepts `sb`, `ub`, `sh` and `uh` in function result/
parameter declarations and call result/argument annotations. They mean signed or
unsigned byte/halfword ABI values, **not new SSA arithmetic classes**. Such values
have base class `word`; ordinary instructions, copies and phis still use only
`w`, `l`, `s` or `d`. A narrow SSA annotation is accepted only on a `call` result.
Void calls remain effect-only; annotating a known nonvoid call as void is invalid.
Long operands in narrow word argument contexts use the existing explicit low-word
projection. Implicit word-to-long promotion remains invalid.

```text
function sb $identity(sb %x) {
@entry
    ret %x
}
function w $observe(l %bits) {
@entry
    %raw =sb call $identity(sb %bits)
    %defined =w extsb %raw
    ret %defined
}
```

## Unspecified upper bits are not implicit extension

Only the low8/16 bits of a subword parameter or returned value are specified.
Neither arguments nor returns must be sign/zero extended according to the ABI
annotation. This matches the bundled QBE IL description and its AMD64 `elimsb`
normalization, not an assumption that signed arguments arrive as complete signed
words. Use `extsb`, `extub`, `extsh` or `extuh` before observing the entire word
as that small integer. The compiler does not insert an extension/mask at calls,
function entry or return. Retaining current word transport is one permitted
choice for upper bits, not a cross-compiler upper-bit compatibility promise.

Incoming/outgoing classification therefore still uses the word GP bank, six GP
registers independently of eight SSE registers, then declaration-ordered8-byte
stack slots. Return transport remains the low word of RAX. Outgoing reservations,
R11 indirect targets, fixed/dynamic frames, phi scratch and preserved homes are
unchanged. This does not itself add aggregates, varargs, environment arguments, complete
C ABI validation, another target/platform or native address safety.

## Explicit metadata and checked ownership

`ir.AbiType` has eight typed cases and maps to the four `ScalarType` classes and an
optional closed `SubwordType`. Existing base-scalar APIs retain their signatures
and null annotations. `Function.initAbi`, `Module.addFunctionAbi` and
`Function.addParameterAbi` construct typed function signatures.
`CallArgument.init(AbiType, Operand)` builds an argument annotation;
`defineCallAbi`/`defineIndirectCallAbi` additionally require the declared call
result class to match its pending SSA value before publishing storage.

The function stores a return annotation; parameter values store only their own
parameter annotation, with no second allocated parallel parameter table. Calls
store a result annotation and copy every argument's annotation together with its
owned operand. A failed type check/allocation leaves the pending definition and
instruction list logically unchanged; retained grown capacity remains allowed.
Function destruction still owns and frees call argument slices.

Because storage is publicly mutable, validation rejects narrow metadata on
non-word returns/arguments/results, void call results and non-parameter SSA
values. Known direct calls compare exact subword annotations as well as scalar
classes, result presence and arity, including forward/recursive/unreachable calls.
A word signature is not silently treated as the same declared signature as sb,
nor are sb and ub conflated. This exact internal policy is deliberately stronger
than merely agreeing on an AMD64 register location. External/indirect signatures
remain caller contracts; no annotation proves target identity/executability.

## Interpretation and effects

The interpreter retains its existing word storage for narrow values. Tests only
observe defined low bits or explicit extensions, not arbitrary upper bits. Internal
calls remain explicit owned frames with shared step/depth limits; narrow metadata
does not enable external/indirect host invocation. Default `UnsupportedCall`,
`UnsupportedExternalCall` and `UnsupportedIndirectCall` boundaries and budget
precedence remain intact. Calls remain effects even when their narrow result is
unused; integer folding neither invents an extension nor removes the call.

## Independent verification

Focused tests cover typed mappings, parameter/call allocation-failure retry,
argument-copy ownership, forged inconsistent metadata, parser predeclaration and
non-call rejection, exact-signature combinations, explicit extension across
recursive calls, low-word projection, phi swaps and folding, evaluator refusal/
budgets and exhaustive allocation cleanup through construction/analysis/emission.
Both independent analysis-oracle corpora include the new fixture without changing
their operand-use switches.

A separate native harness uses independent small-integer expectations, mixed-bank
signatures and narrow C prototypes. Handwritten assembly poisons upper argument/
return bits, including GP and stack arguments. All four explicit extensions,
direct/internal/external/indirect paths, recursion, phi swaps, unused effects and
full-width preserved originals are checked in PIE and non-PIE links. Existing
harnesses/generators remain independent and unchanged. Actual results and any
corrections are recorded in HANDOFF.md, not presumed by this design description.

The native harness checks1033 defined-bit results per link (PIE and non-PIE),
2 executable no-TEXTREL conditions and40 rejection/output-preservation cases per
option combination. The complete matrix and exact-SHA CI results are recorded in
HANDOFF.md; these bounded results do not establish full ABI compatibility.

External/indirect variadic scalar call sites now have a checked named-argument
prefix marker and final AMD64 AL setup (VARIADIC-CALLS.md). Variadic function
bodies, vastart and interpreter host calls remain unsupported; C
default promotions are explicit caller responsibilities, not inserted conversions.

Caller-supplied native scalar vaarg consumers are a separate bounded slice
(VAARG-CONSUMERS.md); they do not implement variadic bodies, vastart or interpreter
descriptor emulation. Reached evaluation explicitly refuses the operation.
