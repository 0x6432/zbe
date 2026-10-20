# Nonvariadic scalar environment calls

The bounded scalar slice accepts `env %e` as the first function parameter and
`env long-operand` as the first call argument. This is an optional hidden long
value, not an extra C ABI argument, implicit pointer conversion or aggregate.
The Linux AMD64 register is RAX; ordinary GP/SSE banks and overflow slots remain
unchanged. Environment plus a variadic definition/call marker is rejected.
Other targets, full ABI support and arbitrary interpreter host calls are absent.

```text
function l $add(env %e, l %value) {
@entry
    %answer =l add %e, %value
    ret %answer
}
function l $caller() {
@entry
    %answer =l call $add(env 4294967297, l 22)
    ret %answer
}
```

## Owned representation and validation

`Function.environment` optionally names its first owned SSA parameter. It is long,
unannotated, and retains an ordinary parameter definition, so SSA entry uses,
parameter cliques, liveness, interference and home layout include it. The checked
first-only `addEnvironmentParameter` publishes the flag only after successful
parameter construction. `ordinaryParameters()` supplies the remaining borrowed
slice without allocating; consumers validate public metadata before using it.
Forged identity, wrong class, nonfirst parameter and variadic combinations are
rejected. Parameters remain function-owned, not pointers into caller storage.

`CallOptions.environment`/`Call.environment` hold a distinct optional copied long
operand. Existing call builders retain their signatures/default behavior; the
common checked builder validates before publication/copying ordinary arguments.
Indirect target, environment and ordinary arguments are scalar uses in that
order. Production operand iteration and independent analysis oracles cover them
separately. The optional operand does not consume an ordinary typed argument,
variadic-prefix position or result identity. Calls remain ordered effects.

Known signatures compare ordinary parameters and return presence/class/subword
annotations exactly. Supplied environments to non-environment callees are allowed.
An environment may be omitted only if `usesEnvironment()` finds no reference in
any instruction operand, phi input or terminator, including unreachable blocks
and explicit low-word projections. This is a conservative all-body scan, not DCE,
reachability inference or proof that some uses are semantically harmless. Missing
used environments are eager `CallSignatureMismatch` errors even in dead calls.
External/indirect runtime signatures and address validity remain caller contracts.

## Native ordering

Probes reserve/touch the unchanged bounded fixed frame without clobbering RAX.
Original callee-preserved registers are saved before the hidden parameter is
homed from RAX, then ordinary parameters are homed using their unchanged banks.
No parameter scratch can destroy the incoming environment before its save.
For scalar-only calls, outgoing indirect targets move to R11 first; ordinary argument marshalling uses
RAX scratch as before; the environment is loaded into RAX last immediately before
the call. No environment shares RAX with variadic AL setup. The ordinary return
may overwrite RAX. Homes survive calls in the existing stack/preserved modes.
A C caller may use the ordinary prototype when the environment is unused; no
particular hidden value is then assumed. This is not a C closure ABI wrapper.

## Explicit interpreter mapping

`Options.environment: ?u64` supplies only the root's raw long value, separate from
its exact ordinary scalar argument array. Child values come from each call's
explicit operand, not inherited root options. Frames map all ordinary arguments
and then any supplied hidden value into owned storage. Truly unused omitted
environments remain uninitialized, not fabricated zero. A used root environment
omission returns `MissingEnvironment` after ordinary count/type preflight and
before frame allocation. Existing validation, depth-zero and memory configuration
setup precedence is unchanged; setup errors precede execution budget checks.

Reached module-local nonvariadic calls preserve instruction-step, target lookup
and depth precedence. Ordinary arguments resolve first, then any explicit hidden
operand resolves even if the target has no environment parameter. Thus discarding
an ABI value does not suppress an existing symbolic-address refusal. External,
indirect and variadic-call refusals still precede child argument resolution. No
numeric address becomes a host pointer; Image/stack/global synthetic memory rules,
earlier successful writes and owned frame/object cleanup remain unchanged.
Standalone calls remain `UnsupportedCall`.

## Verification scope

Direct tests cover checked metadata/builders, operand order/lifetime, omission
uses, root/child mapping, budgets/refusals, earlier Image writes and exhaustive
allocation failures. Existing independent analysis corpora include the fixture.
The native harness uses assembly thunks that modify only hidden RAX before
entering compiled functions, and independent assembly/C readers that capture RAX
before reading unchanged C arguments. It covers mixed banks/overflow, fixed
single and narrow arguments, all scalar/subword returns, raw long bits, direct/
indirect calls, symbolic environments/target aliases, large probed incoming frames,
recursion/phi, live values across calls, void stores and preserved originals,
PIE/nonPIE, plus rejection/output preservation. Results must be recorded only
after execution in HANDOFF.md; this document does not assert completed parity.

## Aggregate native extension

Nonvariadic record signatures/sites now support this same hidden long ENV
convention and typed indirect targets (AGGREGATE-CALL-TARGETS.md). Record calls
park targets in R11 only AFTER all record packing/ordinary marshalling and hidden
RDI setup, then load ENV into RAX last. Incoming ENV is homed before record
unpacking. Aggregate variadics and aggregate interpretation remain refused.
