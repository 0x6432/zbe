# Typed indirect base-scalar calls

The native Linux AMD64 slice accepts scalar-result and void calls through a **long** temporary or integer-address literal:

```text
%result =w|l|s|d call %long_target(w|l|s|d argument, ...)
call %long_target(w|l|s|d argument, ...)
```

The ellipsis describes repetition; actual marked variadic call sites are supported separately in VARIADIC-CALLS.md. Direct `$symbol` calls remain supported. A word or floating target is a type error. The indirect-call extension itself did not add function-address/global operands elsewhere in the language (these are now supported separately as long symbol-address operands; SYMBOL-ADDRESSES.md), memory operations (the later scalar memory slice is documented in MEMORY.md), aggregates, environment arguments, variadic ABI support, shared-library machinery or another target.

## Representation, ownership and validation

`CallTarget` is a tagged union of `symbol: SymbolId` and `address: Operand`, not a packed numeric reference. Symbol IDs belong to the module pool; address value IDs belong to the owning function. `Call` retains an optional result and function-owned typed argument slice. The existing direct builders keep their API; `defineIndirectCall` and `appendVoidIndirectCall` share the same private failure-atomic construction. Target and argument types are checked before reserving/duplicating storage and publishing any definition/effect. Arguments are freed by the function owner.

Indirect targets are ordinary SSA uses: structural validation requires long, SSA checks ordering/dominance, and liveness/interference include the target even if it appears nowhere in the argument list. Independent use-search oracles include target-only fixtures. Integer folding retains calls as effects and does not reinterpret a numeric address as a symbol or execute it.

Module validation checks known symbolic signatures as before, but cannot prove the identity, executability or signature of an indirect address. The caller must supply a valid function address with the declared scalar SysV argument/result contract, including any variadic call marker. Omitting a result asserts a void contract. **Generated native programs are not sandboxed**: an invalid address or incompatible function signature may fault or cause arbitrary invalid native behavior. Accepting an address literal for compilation is not a runtime validity guarantee. Null-address fixtures are never executed natively.

## AMD64 lowering

The emitter loads the full long address into RAX, then copies it to the dedicated caller-saved target scratch R11 **before** marshalling arguments. R11 is neither an argument register nor a persistent home. Argument loads use RAX and leave R11 intact, then `call *%r11` invokes the target. Scalar return homing, void-result suppression, aligned outgoing stack space, saved originals and phi scratch use the existing call rules. A target can also be an argument, remain live across calls or die into the call result's reused home.

This is a limited call-clobber design: persistent homes remain stack or callee-saved GP registers. Future volatile homes need explicit call-clobber constraints; R11 must not become a persistent home or argument-marshalling scratch without revisiting this lowering.

## Interpreter safety boundary

The standalone evaluator still returns `UnsupportedCall` for any reached call. Module evaluation executes only module-symbolic definitions; a reached address target consumes its instruction step and returns **`UnsupportedIndirectCall`** without resolving or invoking that address. A call-free path through such a function can still evaluate. Step exhaustion before the call wins. This is not a function-pointer capability model, native fallback, host pointer cast or external callback bridge in the interpreter.

## Bounded verification

Five unit tests cover target representation/type, scalar and void builder failure retry/argument ownership, malformed target ordering/dominance, target-only liveness, load-before-arguments ordering, module-evaluator refusal and exhaustive allocation failures. Independent liveness/interference oracles include indirect fixtures.

The native call harness now executes **890 call/ABI/effect checks**, plus the unchanged **ten known-symbol signature rejection/output-preservation checks**, in each option combination:

- Existing 474 direct/void call checks remain, plus 128 indirect signatures with three value sets (384 callback checks), all scalar return classes and both register-bank overflow orders.
- Additional callbacks cover passing the target as its own argument, repeated void effects, full-width preserved-register checking, direct-returned callback addresses, indirect recursion and raw floating payloads.
- The harness links this bounded slice with `-fPIE -pie` and explicitly requires a callback address with nonzero high 32 bits, so accidental address truncation cannot hide behind a low non-PIE code address. It asserts that precondition rather than silently claiming high-bit coverage on an unsuitable mapping. Other integer/floating harnesses retain their non-PIE checks.

Converting C function pointers through `uintptr_t` is explicitly a native Linux AMD64 test convention, not portable C or a complete PIC/shared-library ABI claim. These fixtures are not exhaustive callback/ABI conformance, valid-address checking or full backend acceptance.

Typed sb/ub/sh/uh scalar ABI annotations retain word SSA classes and unspecified
upper bits, with explicit extension instructions and exact internal signature
checks (SUBWORD-ABI.md). This does not add aggregates, varargs or host invocation.
