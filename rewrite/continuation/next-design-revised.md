# Revised next-endpoint proposal — DESIGN ONLY, NOT RATIFIED

## 1. Disposition and authority

**Conditional recommendation: a complete bounded non-TLS `extern $symbol`
GOT-address/value/call endpoint, after actual opaque publication and a new explicit
user go-ahead. Every policy and ledger below is a proposed default, NOT a decision
ratified by the user, implementation permission, or execution evidence.**

This is a NEW document. It preserves `next-design-only.md`, its evidence directory,
and both `next-design-primary-review.md` and `next-design-boundary-review.md`.
It incorporates their concrete blockers, correcting the original scalar scheduling
claim and symbolic-wrapper/early-return omissions. The review reconciliation is
explicit below; neither review was unconditional implementation approval.

Inspected source identity remains frozen tree
`6861cde5cb9c28e58747c9d22803bc4847f2014b`, manifest530, public union base
`c09b74646b04e0ade3d84aebdcdda59fef56819e`, base tree
`2b68fd71e05b74d116e8a65bb02d7c6e4d345222`. It is **not** substituted for the
future published predecessor. Per the latest user report, the current opaque gate
is running: Debug all8 and ReleaseSafe526 have passed. Those are incremental
reports, **NOT terminal full-gate acceptance, CI success or publication**. This
planning must not delay or duplicate the parent's gate or terminal audit.

Activity for this revision: text reads, read-only hashes, and new coordination
artifacts only. No source/test changes, compiler/assembler/linker/native execution,
lock acquisition, Git index/ref operations, auth/tokens/private handoffs, or new
worktree. No new milestone implementation or calibration execution is authorized.

### Source authority and unchanged gap ranking

The original E1–E9 evidence ledger remains authoritative as pinned text, not runtime
proof. Saved QBE IL `174–195,226–237` defines function-body dynamic extern values;
QBE AMD64 emitter `549–580` loads the resolved pointer FROM GOTPCREL, with a zero
addend. The saved official psABI chapter `1499–1526` defines GOTPCREL's entry
coordinate and small-model addressing. Neither an ordinary-symbol LEA nor a
GOT-slot LEA is generally equivalent to that pointer load.

Pins: QBE revision `e786f06032fefa2e3790d6b1c9e31ed138f475a6`, archive SHA256
`ba0271b4722688e0fee53f59b0d05c1d5ad98ed35185bef5eea7e91ffe474f4e`;
psABI revision `e1ce098331da5dbd66e1ffc74162380bcc213236`, chapter SHA256
`2d42f2ab76b99a3b8456e6bc07e18314e85991119f72db90ca1175328e27b705`.
`next-design-evidence/hashes.json` pins31 copies; its SHA256 is
`22e4976eabb0271c4206fa49b6cba708f056766219f011700222e889b28b89e8`.

Recommendation order is unchanged: (1) explicit non-TLS extern/GOT; (2) complete
TLS storage plus local-exec/initial-exec transport, a separate larger endpoint;
(3) bounded section linkage with flags/storage/linker policy; (4) owned debug
file/location metadata with independent line-table verification. `truncd` remains
**ineligible on the rounding-policy hold**, not a fifth authorized endpoint.
This is not an exhaustive compatibility inventory. Internal QBE ops do not imply
public vector/X87/atomic support; deliberate ABI/interpreter refusals are not gaps
that this milestone may silently widen.

## 2. Proposed fixed policy set P1–P8

### P1. Scope, canonical names and precise native errors

Use the **primary review's more conservative initial name set**, as proposed by
the user for this revision:

`^[A-Za-z_][A-Za-z0-9_.$]*$` over decoded canonical ASCII bytes,
**intersected with existing portable-name and reserved-namespace checks**.

Thus `_x`, `alpha`, `a.b` and `a$b` are eligible; leading-dot names (including `.Lx`),
spaces, quotes, backslashes, punctuation outside the set and digit-leading decoded
names are not eligible for NEW native extern references. This does not claim the
GNU tools cannot support them. Quoted/escaped aliases decoding to one allowed name
share its existing SymbolId, never a decorated GOT spelling or second pool key.

- Source/global decoding validity stays exactly as today. Canonical portable but
  nonnative names remain legal source/IR for the new operand/target. They cause
  **`UnsupportedExternSymbol` for native extern use anywhere in emission's whole
  module**, including unreachable blocks/unused functions/phi alternatives. Do
  not remove them by optimization before checking eligibility.
- Only actual extern references are scanned, not arbitrary pool keys or ordinary
  uses/definitions of the same name. Ordinary quoted/trailing-backslash/common/
  offset/data support, accepted names, error ordering and assembly bytes remain
  unchanged. No new restriction on old symbol forms.
- Bad/out-of-range SymbolId: existing generic `InvalidSymbol` before target
  eligibility. A hand-interned name violating existing portable-name validity:
  native `InvalidSymbol` in the new extern scan. Portable but outside P1:
  `UnsupportedExternSymbol`. Invalid decoded source globals retain existing
  frontend diagnostics. Do not conflate those cases with OOM or aggregate errors.
- New scan order is stable module/function/block/operand order (phi inputs,
  instructions and their existing operand order, terminator; symbolic target
  identity checked consistently). First invalid new name in that traversal wins
  within the extern phase. Call target operands precede ENV then arguments, as in
  the existing use iterator; dedicated extern and direct GOT wrapper must appear
  at that same first position, not as a delayed second identity-only pass. No
  extra symbol-length/count cap or relocation array.
  The whole aggregate phase must already have completed before this phase.
- Unknown definitions/normal OBJECT or FUNC-compatible linking are caller/linker
  contracts. No host symbol lookup. Existing non-exported `.local` definitions
  stay local; extern does not export them or promise preemption. Exported,
  default-visible definitions are the controlled interposition case.

This resolves the reviews' naming disagreement **as a recommendation only**.
Full bare-name/leading-dot support is deferred, not conditionally enabled by
whatever assembles on one machine.

### P2. Exact grammar, carrier rules, diagnostic codes and spans

Proposed grammar is contextual, with no global keyword-table change:

`ExternValue := identifier("extern") INLINE_GLOBAL`

`INLINE_GLOBAL` means the immediately following lexer token is a global on the
same logical line; normal lexer-skipped spaces/tabs are allowed. No skipLines,
newline joining, comment-line skipping, or new lexer whitespace rules. Existing
tokenization still applies (e.g. a merged identifier is not two tokens). Exactly
one modifier, no source suffix/addend, **including `+0` / `+ 0`**. Runtime long
arithmetic after materialization remains available; old `$x + i32` stays exact.

Recognize this value at every existing compatible long operand site, and recognize
an extern symbolic call target. The value is long, never a polymorphic immediate
or direct word/float operand. For word use materialize long SSA then use today's
explicit low_word projection rules; no new numeric/precision conversion. A word/
float load may still use a long extern ADDRESS. No TLS, extern-thread, declaration,
linkage, data initializer, first-class aggregate value, or ENV+variadic widening.

Spans below are byte half-open `[token.start, token.end)`, not decoded-name offsets;
EOF is its existing `[len,len)`. This table applies to recognized NEW extern
syntax. Existing whole-input lexing errors still precede parser diagnostics, and
legitimate allocation failures can precede a later syntax/type diagnostic.

| ID | New-syntax case | Proposed code and exact span |
|---|---|---|
| D01 | `extern` then EOF | `unexpected_token`, EOF empty span |
| D02 | then temporary, integer, punctuation or unrelated identifier | `unexpected_token`, entire offending next token |
| D03 | then LF / CRLF / comment-generated newline | `unexpected_token`, the lexer's entire newline token span (comment includes its existing scanned bytes); do not consume following line |
| D04 | `extern extern $x` | `unsupported_construct`, second `extern` token |
| D05 | `extern thread $x` or recognized stacked linkage modifier (`export`, `common`, `section`) | `unsupported_construct`, that first stacked modifier token |
| D06 | `extern $x + ...`, including `+0`, overflow or absent integer after plus | `unsupported_construct`, plus token only, before reading/folding/parsing an addend |
| D07 | syntactically complete extern value in incompatible expected word/single/double context | `type_mismatch`, initial `extern` token |
| D08 | extern in data initializer or declaration/linkage position | `unsupported_construct`, `extern` token at that context boundary |
| D09 | malformed global quotes/escapes/decoded source name | exact existing lexer/globalName code and original global-token/error span, not a remapped new code |
| D10 | source/IR-valid name outside P1 | parse/type succeeds in a long context; native `UnsupportedExternSymbol`, not a fabricated frontend diagnostic |

For overlaps, new parser sequence is context gate → demand next global (recognize
D04/D05 first) → existing global decode/intern → forbid following plus → check
expected type. Thus plus wins over expected-type mismatch only after a valid
global; bad quotes retain earlier lexical/decode precedence. Other trailing tokens
retain existing delimiter/lineEnd diagnostics; no silent instruction swallowing.
Before an accepted extern prefix, standalone/reversed `thread extern ...`, old
unknown identifiers and ordinary malformed tokens retain their old context's
code/span. In particular this endpoint does not retroactively change every old
`thread` refusal to D05. Existing `$extern` and `:extern` identifiers stay legal in
their existing namespaces. D08 recognizes extern at top-level/linkage/data operand
boundaries only; it does not reserve arbitrary spelling inside names or strings.

### P3. Owned representation and symbolic target identity, including wrappers

Propose `Operand.got_symbol: SymbolId` and `CallTarget.extern_symbol: SymbolId`.
Names remain stable owned bytes in the module symbol pool; type names remain in
their separate pool. Function owns/copies call arguments/phi inputs exactly as
before. No source slices, owner pointers, host pointers, per-use allocation,
address cache, assembly-suffixed names or persistent extern registry.

A **single semantic symbolic-target identity accessor** must yield:

| Target form | Identity for validation | addressOperand view |
|---|---|---|
| old `.symbol(id)` | ordinary symbolic id, unchanged | null, unchanged |
| new `.extern_symbol(id)` | extern symbolic id | `.got_symbol(id)` |
| `.address(.got_symbol(id))` | **same extern symbolic id** | original GOT operand |
| old `.address(.symbol/.symbol_offset/.value/.constant/...)` | no new symbolic identity; old behavior | unchanged original address operand |

The direct GOT wrapper is equivalent, not an escape hatch: parser, generic
appendCall/defineIndirectCall builders, public-edited IR, module validation and
native lowering must agree without trusting builder canonicalization. Validate
all IDs/descriptors before known-signature comparisons, then for BOTH new symbolic
forms enforce called-data rejection and exact current nominal return/parameter,
subword, ENV and named variadic-prefix checks. Unknown external signatures remain
caller contracts. A copy/phi into an SSA value is the existing computed-pointer
boundary; no new provenance inference through SSA, nor optimizer-created erasure
of a dedicated symbolic identity. Preserve old address(.symbol) behavior.

`referencedSymbol` exposes GOT id; `referencedValue` is null. Address views expose
GOT targets to iteration while identity checks cannot be lost through that view.
Audit production and independently handwritten operand/target switches: builders,
type/SSA, validation, optimizer, liveness/interference and independent oracles,
plans/homes, emitter, interpreter, formatting. Treat GOT values as dynamic unknown;
never fold them into ordinary symbols, local synthetic addresses or numeric facts.
Every unused/unreachable reference is structurally validated. Numeric in-range
cross-module ID provenance remains the caller ownership invariant; no claim that
a u32 can detect the wrong owner when its numeric value happens to be valid.

### P4. Allocation/error ordering, public API scopes and scalar-only bypass

**Detached FunctionPlan:** existing invalid FunctionId check FIRST → generic
whole-module validation → existing selected-function aggregate eligibility → new
selected-function extern eligibility → build selected plan/homes/frame. Unselected
functions still undergo generic ID/descriptor/signature validation, but their
valid unsupported target features/names do not become detached target refusals.

**ModulePlans / public emission:** generic whole-module validation → determine
record relevance without allocation → existing aggregate eligibility for ALL
functions if record relevant → new extern eligibility for ALL functions ALWAYS
→ only then scalar-only empty return OR plan arrays and per-function builds.

The new extern scan **must precede ModulePlans' scalar-only empty-plan early
return**, but scalar-only modules still allocate no plan arrays/home layouts in
ModulePlans. This closes the real bypass without adding dummy aggregate plans.
If aggregate relevance is absent, its existing eligibility phase is empty, not a
reason to skip the new scan. Whole-module aggregate and extern scans are separate
phases: a bad extern in an early function must not overtake a later old aggregate
refusal. Do not interleave them per function. Invalid later generic metadata and
known nominal mismatches still precede both target phases.

The new extern scan allocates nothing and inspects only new extern references.
Generic record/SSA/descriptor validation may legitimately allocate/OOM earlier.
Old ordinary native symbol checks remain in their old post-plan location/error
order. No unchecked 'already validated' flag, cached caller plans or stale-module
shortcut; private builders only follow successful same-invocation checks. Public
Error unions must propagate `UnsupportedExternSymbol` unchanged, not map it to
aggregate unsupported. No plan/signature/pad/home/frame geometry/writer/final-slice
allocation may happen after a new eligibility refusal; output opening remains
after successful emission. Prove the frontier with categorized allocation
observers, not the first allocation number or a claim of allocation-free parsing.

### P5. Native materialization and **new-target-only** scalar schedule

GOT materialization loads the resolved pointer, 64 bits, into the requested
scratch64 register. It does not load symbol contents or return a GOT slot address.
No helper call, new home/save/outgoing slot or new prologue is required by default.
Do not reuse old COMMON-cell/trailing-backslash workarounds for excluded names.

**Corrected source fact:** saved `amd64.zig:426` captures old scalar indirect
targets into R11 BEFORE marshalling scalar arguments. `recordCall:676` captures
indirect targets AFTER copies/packs/scalars/hidden RDI because R11 was scratch.
The original proposal's uniform 'existing late target' description was wrong.

| Case | Proposed target preparation |
|---|---|
| Every old scalar direct/indirect target, including computed SSA obtained from a GOT value | Keep existing schedule and bytes: old indirect early capture; arguments; ENV or final AL; call |
| NEW scalar `.extern_symbol` or `.address(.got_symbol)` only | Marshal arguments; load GOT target through RAX into R11; establish ENV in RAX or final variadic AL; indirect call |
| Existing or new record indirect/extern targets | Keep record late capture AFTER all copies/packs/scalars/hidden RDI; then ENV or final AL; call |
| Old direct record symbolic target | Keep old direct call schedule/bytes |

Use the P3 accessor to distinguish new symbolic wrappers consistently. New operand
loads must respect selected scratch and preserve parked R11, marshalled args,
ENV/RAX/AL ordering. Do not reorder old scalar calls for stylistic uniformity.
Preserve exact ABI N versus occupied extent, hidden RDI/original RAX, source/pad
nonalias and variadic named raw end; no ABI policy changes ride with address
transport. An ELF canonical function pointer can legitimately be a canonical PLT
address. Required equality is to the independent loader/ABI-canonical pointer,
**not an unsupported guarantee that every pointer equals the ultimate code-entry
PC**. Forbid an incorrectly substituted PLT/GOT/ordinary address, not valid ELF
canonicalization or correct local-binding relaxation.

### P6. Interpreter ordering, no native-name pass in evaluation

Preserve the actual dispatch ladder, not a new blanket preflight:

1. Standalone evaluate: existing SSA validation then root aggregate-signature
   refusal. evaluateModule: existing entry-ID check, whole generic validation,
   then root aggregate refusal. Existing failures/OOM retain precedence.
2. Execute: max_call_depth==0 check, owned Space/frame/root argument/ENV checks in
   current order. Do not imply a reached-call refusal precedes root setup/OOM.
3. Each reached instruction/selected phi/terminator consumes its current step.
   A zero/exhausted instruction budget refuses before target/operand resolution.
4. At a reached call: record-ABI guard → missing owner yields `UnsupportedCall`
   → new extern target (dedicated or GOT wrapper) yields `UnsupportedIndirectCall`
   at today's indirect dispatch point. No callee lookup, call-depth-at-dispatch
   check, argument/environment resolution/allocation or child-frame creation after
   that refusal. Module-owned and standalone results are deliberately different.
5. Reached GOT operand evaluation yields `UnsupportedSymbolAddress` in current
   operand evaluation order, even with same-named local data and global-memory
   opt-in. No host or synthetic fallback. Valid unchosen phi inputs/unreached
   instructions are structurally checked but not evaluated.

Native P1 eligibility is not an interpreter gate. A nonnative but canonical extern
name can be unexecuted on a successful scalar path, or refuse when reached as
above. Step/depth/memory limits, aggregate refusal, root variadic/global/stack
opt-ins and cleanup remain unchanged. No host pointers/calls, aggregate evaluation
or aggregate-vaarg widening, and no synthetic thread/process loader state.

### P7. Invariants, resources and identity

All existing source limits, builder contracts, errors, suites, fixtures/goldens,
negative sentinels and prior semantics remain. CLI input16MiB is not a universal
builder bound; object/module data16/64MiB, u32 handles and all existing record,
type/run/argument/SSA/frame/synthetic-memory caps stay fixed, not enlarged or
silently lowered. No undocumented extern-count/name-length cap.

`truncd` stays held. No TLS/storage/sections/debug additions, new ABI class,
small opaque-containing register classification, first-class aggregate values,
aggregate vaarg/interpreter, new float environment policy or broad PIC promise.
Actual N/occupied extent/guards/return-pointer contracts stay exact.

The eventual published opaque executable is the old-output oracle; pin actual
public commit/tree/manifest/build/binary and toolchain before new work. All old
modules retain full assembly byte identity in all8 options, including ordinary
quoted/trailing-backslash/common/offset/data, scalar, INTEGER/SSE/mixed/union/
MEMORY/opaque, ENV, indirect and variadic paths. No new extern syntax in old parity
inputs; fresh extern positives use independent semantics, QBE secondarily. Do not
substitute union-only historical hashes or unpublished candidate self-comparison.

### P8. Ownership and bounded endpoint completion

A later authorized author owns production + units + one bounded feature harness +
docs + normal CI registration, complete through native execution/refusal/OOM, not
just parsed metadata. Independent reviewers inspect the SAME frozen tree;
parent alone owns durable backup, one full gate, commits/push/CI/publication. All
original calibration/probe/mutation/raw-failure inputs remain outside source.
No auth/private handoffs/unrelated changes. Future compiler/assembler/linker/native
commands ALL take the shared lock, use -j1 where supported and obey2CPU/4GiB;
focused author runs only, no duplicate full matrices. No commands start now.

## 3. Mandatory calibration prerequisite BEFORE production implementation

**A new explicitly authorized calibration phase is prerequisite, not an execution
request in this document.** Actual opaque publication and explicit user go-ahead
must come first. Calibration writes outside source; no production changes until
its evidence/ledger is reviewed and accepted. If any necessary witness cannot be
made distinguishing on the chosen tools, STOP for policy/fixture revision; never
silently waive a row, guess a flag, substitute a local link, or broaden support.

Proposed target is one Linux x86_64 ELF LP64 / GNU as / GNU ld.bfd / glibc startup
loader toolchain, with one independent C compiler (prefer current GCC if actually
present). This is NOT a claim about installed versions, flags or support for lld,
gold, musl, non-ELF or other code models. No new 'linker mode' is implemented by
the compiler; these are independent acceptance link configurations.

| Calibration ID | Required actual future evidence / pass criterion |
|---|---|
| K01 | Pin paths, versions, resolved executable/file hashes, target triples and effective driver commands for Zig, published opaque compiler, C compiler, as, ld.bfd, ELF inspection tools, libc/loader; capture only allowlisted relevant nonsecret environment values (never dump the environment). Record actual linker selected by C driver. Reuse verified parent/reference builds; no duplicate old compiler build. |
| K02 | Independent C/ASM minimal GOT getter/load fixture only. Discover and prove an actual supported no-relax mechanism and a separately ordinary relaxed link; capture command/diagnostic/disassembly/relocations for each. A flag that is ignored, unsupported, or does not preserve the required witness does NOT satisfy this row. Named accepted relocation families for objects and final dynamic relocations must be frozen from actual output, not numeric guesses. |
| K03 | PIE and non-PIE clients plus isolated PIC getter/candidate-surrogate DSO and provider DSO. Pin actual compile/link flags, DT_NEEDED/load order, default visibility/binding and absence of hidden/protected/-Bsymbolic in preemption positives. Provider-only fixture establishes loader-resolved data/function baseline. |
| K04 | Second startup override DSO via controlled DT_NEEDED ordering, plus bounded subprocess LD_PRELOAD variant. Unique initialized data and function results differ from provider. Independent PIC C/ASM accessor proves actual override selection for BOTH data and function; merely declaring a competing symbol is insufficient. No constructors/process hooks/dlopen. |
| K05 | Inspect all oracle/accessor/client/DSO objects and final binaries with pinned tools; rule out unintended COPY and TEXTREL, especially non-PIE data. Freeze named accepted relocation/symbol-binding ledger, exact flags and semantic checks. If avoiding COPY changes fixture structure, approve that structure before production rather than masking the issue. |
| K06 | Prove independent ELF-canonical function pointer equality/invocation in each binding case (may be canonical PLT), and data pointer versus contents versus GOT-slot distinction. Expected pointer comes from independent PIC C/ASM loader-resolved accessors, not compiler under test or assumed underlying entry PC. Capture pointer/binding witnesses without hardcoded ASLR addresses. |
| K07 | Calibrate real wrong-ordinary-LEA and GOT-slot-LEA controls: show a **distinguishing preemption-positive** witness where each assembles/links and fails the intended identity/result/guard assertion. A failed shared link is a useful negative but not a runtime control substitute. Local nonpreempted no-relax case must demonstrate 64-bit GOT load; separately prove correct local relaxation may eliminate an entry without becoming a test failure. |
| K08 | Freeze actual fixtures/tool pins/flags/named relocation acceptance, raw exits/stdout/stderr, source/binary hashes, no-relax/relax proof and canonical-pointer expectations into a calibration manifest; reviewers/parent approve. Revalidate integration sites against actual published opaque source. Only then can production implementation begin under explicit authorization. |

No K row has been executed for this design. All actual tool/flag/relocation/pointer
proof slots remain **PENDING**, openly, until authorized calibration. Pinned QBE
and psABI source evidence does not fill them. The proposed coverage structure
below is fixed; tool-dependent spellings may be filled only by K08 review, never
invented here or decided opportunistically during implementation.

## 4. Proposed fixed covering ledger (approval required)

This is a bounded covering design, not a Cartesian product and not future gate
count certification. Preserve EVERY old suite unchanged. Rows identify required
witness families; deterministic allocation-failure ordinals are exhaustively
measured, not a guessed numeric cap. Any added/deleted row, changed case domain,
option/link/binding schedule or dropped mutation requires explicit ledger revision
and approval. Unexpected raw failures are retained; do not silently shrink suites.

### U01–U16: fixed unit/structural/interpreter witness families

| ID | Fixed witnesses / acceptance |
|---|---|
| U01 | Native-name positives `a`, `_a`, `a.b`, `a$b`, `A0` and decoded quoted aliases; exact old/new SymbolId deduplication; source destroyed and pool/function growth leaves owned pointers/names stable. |
| U02 | Source/IR-valid native negatives `.a`, `.Lx`, `0a`, `a b`, embedded quote, trailing backslash; native UnsupportedExternSymbol only on extern use. Add old ordinary-only controls and unused pool-key controls. Hand-interned portable-invalid empty/control/@/reserved names retain InvalidSymbol; invalid ID remains generic InvalidSymbol. |
| U03 | D01–D10, with LF/CRLF/comment-newline/EOF variants, plus `+0`, `+ 0`, missing integer and out-of-i32 suffix. Combined type+plus, decode+plus and whole-input lexical-error controls prove precedence. Exact literal byte offsets frozen in future fixtures, not merely contains-token checks. |
| U04 | Existing namespace/ordinary syntax negatives/positives unchanged, reversed thread context unchanged, no unconditional keyword reservation, old symbol+offset i32 boundaries; load result word/float with long address succeeds; direct word/single/double extern values reject; long SSA-to-low_word path succeeds. |
| U05 | Every compatible site: copy, phi edge, binary LHS/RHS, comparison LHS/RHS, branch, return, load address, store address/value, blit source/destination, allocation size, scalar/record call argument, ENV and scalar vaarg/vastart descriptor address where existing typing permits. GOT-backed descriptor contents remain scalar-only. |
| U06 | All4 P3 target categories; both new forms through parser/builders/public edits. Same known-symbol checks for dedicated and direct wrapper: regular/union/opaque nominal mismatch, scalar/subword result/arg mismatch, called-data, missing ENV and variadic named-prefix. Old address(.symbol) and SSA pointer behavior unchanged. |
| U07 | Corrupt IDs/type/backlinks in each new operand/target position, later unused function/block/phi/argument/env/terminator; all descriptor IDs resolved before known mismatch; no cross-module-owner detection claim for a numerically valid handle. |
| U08 | Whole module: scalar-only extern negatives before empty-plan return; valid scalar-only returns no plan arrays; all aggregate eligibility before all extern names even when bad extern appears earlier; invalid generic metadata/signature wins. Detached: invalid FunctionId first, global generic metadata checked, selected target-only eligibility, unsupported unselected feature ignored after generic validity. |
| U09 | Allocation-frontier observer for scalar-only/record-relevant/late-unreachable name refusals and both new target forms; zero post-generic plan/home/frame/writer attempts. Old ordinary name failure order unchanged. No unchecked prepared/cache token path. |
| U10 | Shared-use iterator plus independent SSA/liveness/interference oracle on new symbols at phi/instructions/targets/env/terminators. GOT has symbol reference and no SSA reference. New/new-wrapper identity not erased; fold on/off treats GOT unknown; old folded assembly stays identical. |
| U11 | Reached operand -> UnsupportedSymbolAddress with global-memory disabled/enabled and same-named local object; structurally valid nonnative name unexecuted succeeds, reached refuses without native-name scan. Unchosen phi/unreachable operands not resolved; invalid IDs still checked by module validation. |
| U12 | Interpreter ordering ladder: invalid entry; root aggregate; maxdepth0; root argument/ENV errors; zero/exhausted step before instruction; reached aggregate call before owner; standalone scalar extern call -> UnsupportedCall; module-owned both new target forms -> UnsupportedIndirectCall before valid-but-poisonous GOT arg/ENV resolution, per-call depth check or child allocation. Preserve earlier setup/OOM. |
| U13 | No new aggregate-vaarg/interpreter, ENV+variadic, TLS/data-initializer/section or truncd acceptance. Native boundary errors do not remap old errors. Default and opt-in synthetic features retain exact existing policies. |
| U14 | Existing exact caps and ownership regression witnesses reused, not weakened or multiplied: checked IDs, source/data/type/run/args/SSA/frame/memory; highest existing ABI/frame/extent boundaries stay valid, one-past negatives unchanged; no invented builder CLI bound. |
| U15 | All O01–O10 exhaustive allocation-failure sweeps below; same-surviving-object retry and normal success without induced failure; zero-attempt operations stay zero. |
| U16 | CLI absent-output and preexisting byte sentinel on syntax/type/generic-ID/nominal/aggregate/extern-name/OOM failures; successful exact output; old ordinary quoted/common/offset paths and all8 predecessor byte identities registered without replacing prior fixtures. |

For U05 use one site table (one structurally valid/emittable witness per listed
alternative), not an all-sites × all-name × all-ABI product. Mark allocation-size
use compile-only/unexecuted in runtime witnesses: a loader pointer is not a bounded
allocation length. Scalar vaarg/vastart addresses may run only against a real
independently prepared valid scalar descriptor, with existing limits/guards; no
forged or aggregate-vaarg descriptor. Runtime-safe alternatives are checked by N11. U06/U07 negatives are static rejection
oracles; never execute mismatched ABI programs. The opaque/record descriptors are
nominal throughout; type declarations themselves do not force ABI use.

### O01–O10: exhaustive deterministic OOM frontiers

| ID | Transaction and retry contract |
|---|---|
| O01 | Whole parse including canonical decode/intern: fresh complete success or full destruction on each failure. NO partial-module parse resume promise. |
| O02 | Surviving symbol pool growth/intern + alias, same-pool retry; stable previous IDs/name pointers, no half-published ID, capacity retention reported honestly. |
| O03 | Owned function appendCall/indirect builder, dedicated and direct-GOT wrapper targets, copied args/env metadata; same-module/function retry and result/backlink publication atomicity. |
| O04 | Owned phi/operand instruction construction/growth; borrowed inputs destroyed, same surviving function retry; no half-published definition. |
| O05 | Generic record/data/module/SSA validation on all valid new-reference shapes, including unused metadata and known target comparison; same-module revalidation after each failure. |
| O06 | Detached FunctionPlan init on selected scalar/record function, all four reuse/callee-save home option combinations; deinit failed/successful plans and retry same immutable module. |
| O07 | ModulePlans on scalar-only and record-relevant modules, same four home combinations. Scalar-only plan arrays remain absent; supported new names must reach ordinary success. |
| O08 | Native emitter all8 fold/reuse/callee-save options with mixed scalar/record paths; sweep signature/call/pad/home/frame support allocations and all writer growth/final owned slice. Check no leak/partial successful output, retry same module, final result ownership. |
| O09 | Interpreter existing root/Space/frame setup with new reached/unreached values and target-order controls; no new arg/frame allocations after target refusal. Preserve existing setup failure precedence and cleanup. |
| O10 | Eligibility/accessors/enum payload/use iteration themselves allocation-free; observer distinguishes generic-validation allocations from forbidden post-generic plan/output allocations. Final no-induced-failure success detects swallowed finalwriter OOM. |

For each allocating transaction enumerate every allocation ordinal of the measured
complete no-failure trace, require OutOfMemory when that allocation is actually
failed, then the normal baseline outcome with no injected failure; record exact
measured attempts and the harness's ordinal convention. Positive construction/emit
baselines MUST succeed, including final owned-slice extraction. Intentional
interpreter/refusal witnesses instead require their pinned baseline refusal, not
an invented successful evaluation.
Where allocation paths depend on retry state, sweep a freshly reset witness per
ordinal AND perform the documented surviving-object retry, recording capacity
retention. Do not treat an induced failure not reached as an OOM pass. No arbitrary
retry-count cutoff, leaked enum payload, allocator-specific untested final slice,
or cleanup-only success. Raw failures and minimal reproductions are retained
alongside, never substituted for the original complete failing input.

### N01–N16: one common native bundle, all8 × PIE/non-PIE

Option index is the existing three booleans (fold, reuse homes, callee-saved homes),
explicit bit mapping to be copied from published CLI/tool registration at K08,
not guessed here. The bundle executes all16 witness families per invocation.
This is **16 scheduled successful bundle invocations**, not16 total assertions
or compiler stages. Independent C/ASM providers define expected results/addresses.

| ID | Fixed native witness |
|---|---|
| N01 | Data resolved pointer equals independent accessor, not initialized contents/slot; read/write-through-pointer with source/destination guards/canaries. |
| N02 | Function ELF-canonical pointer equality plus callback result via dedicated extern, direct GOT wrapper and extern-to-SSA target. |
| N03 | Scalar/void/subword calls: all sb/ub/sh/uh checked descriptors with explicit extension expectations; no unspecified-upper-bit oracle. |
| N04 | GP pressure at6/7 long args and SSE pressure at8/9 args, independently and one mixed overflow continuation; final named stack order/alignment. |
| N05 | Supported INTEGER record sizes1,8,9,16, including result; exact bytes and source preservation, use valid C only where representable. |
| N06 | SSE and mixed INTEGER/SSE two-lane argument/result plus small union; independent return-register/pack/unpack oracle. |
| N07 | MEMORY regular and large union; hidden RDI/original RAX, exact copy versus occupied extent and source/result disjointness. |
| N08 | Opaque exact sizes1,9,17,4096 with supported alignments selected1/8/16 (not product), plus large containing regular/union; unsupported small opaque-containing register form stays a static negative. Exceptional layouts ASM, valid packed C only where real. |
| N09 | Nonvariadic ENV scalar and record/opaque separately, env/target/source live across clobbering call; ENV final RAX preserved. |
| N10 | Variadic scalar and record/opaque named prefix separately; 0/8 occupied SSE registers plus overflow continuation, final AL and named raw end; scalar consumers only. |
| N11 | Runtime-safe U05 sites materialize independently checked data/function addresses or numeric bits; quote aliases/allowed punctuation names agree. Allocation-size GOT use is a structural/emission-only witness on an unexecuted path, NEVER a pointer-sized allocation or resource-exhaustion experiment. |
| N12 | Scalar target schedule witness: old computed target still safe early, new dedicated/wrapper target loaded late; argument GOT loads preserve R11 and selected scratch; final ENV/AL not poisoned. |
| N13 | Record copy/pack scratch pressure + late target after hidden RDI, result-pad alias/source overlap control at valid existing contracts; poisoned pads. |
| N14 | Loop/phi computed target selection and recursion with target/env/source live, same live-list continuation after pressure; no symbolic inference through SSA. |
| N15 | Dynamic alloc moving outgoing reservations and stack alignment across GOT target calls; reuse existing page-probe/max-frame regression witnesses without new limits. |
| N16 | Local non-exported ordinary/function and permitted extern references retain binding; old ordinary quoted/common/offset/data smoke and direct/indirect schedules unchanged. New extern does not silently export local definitions. |

Exact guard placement must distinguish logical N from rounded occupied extent;
no read-only source overread or destination overwrite hidden by mapped padding.
Do not claim C supports arbitrary opaque alignment/shape; assembly is primary for
those layouts. One bounded fixture bundle covers the rows, not a product of each
record size/bank pressure/name/option. QBE secondary positive comparison reuses
same supported input bundle in default option only, PIE and non-PIE (2 successful
runs), using verified pinned QBE; it is not the expected assembly oracle.

### L01–L04: isolated loader/preemption bundle

All4 assertions run per invocation: L01 data address/read-write/guards, L02
function canonical pointer/invocation, L03 selected binding/provider identity,
L04 object/final relocation+visibility checks and no COPY/TEXTREL.

Fixed scheduling axes are **options default/full only (2) × client PIE/non-PIE(2)
× independently calibrated no-relax/ordinary-relax(2) × binding provider-only /
DT_NEEDED override / bounded LD_PRELOAD override(3) = 24 successful invocations**.
Each uses an isolated candidate-function DSO and independently PIC C/ASM accessors;
provider and override data/function signatures are compatible and observably
different. Do not use hidden/protected/-Bsymbolic/local binding in preemption
positives. Case N16 is the separate local-binding control.

Actual pins/flags/named relocation expectations come from K01–K08 before production;
the fixed axes are not an assertion that required tools/flags presently work.
Preemption must be proved rather than assumed from link order. A correct local
relaxation can remove the GOT entry; non-relaxed distinguishable fixture and
canonical-pointer equality remain the acceptance criteria. Reuse built providers
across cases where hashes/flags identical; serialize every compiler/native step.

### M01–M12: real defect controls, isolated approved witnesses

| ID | Mutant and required intended detection (not unrelated refusal) |
|---|---|
| M01 | GOT pointer load -> ordinary-symbol LEA: K07-calibrated runtime preemption identity/result assertion fails. |
| M02 | GOT pointer load -> GOT-slot LEA: assembles/links, independent pointer/read/guard assertion fails. |
| M03 | GOT load writes wrong selected scratch or corrupts parked R11: N11/N12 checked result/target assertion fails. |
| M04 | New record target captured before copy/pack scratch: N13 independent target/result check fails. Moving NEW scalar target early alone is NOT presumed unsafe and is not a fake defect control. |
| M05 | ENV target load placed after ENV setup, or AL before last target/argument RAX load: separate N09 and N10 assertions fail (2 submutants). |
| M06 | Identity accessor ignores `.address(.got_symbol)`: U06 wrong nominal/called-data input is wrongly accepted; both dedicated form and wrapper static controls retained. |
| M07 | Fold GOT into ordinary or same-named local synthetic symbol: U10/U11 boundary assertion fails; optimizer identity erasure also detected. |
| M08 | New scan behind scalar-only empty return: U08/U09 scalar-only unsupported name incorrectly succeeds/crosses forbidden frontier. |
| M09 | New scan after plan/home allocation: U09 observer detects allocation frontier violation, not merely eventual UnsupportedExternSymbol. |
| M10 | Aggregate/extern scans interleaved: U08 bad-early-extern/later-old-aggregate priority assertion fails. |
| M11 | Interpreter synthetic fallback or call args resolved before target refusal: U11/U12 expected error/order fails (2 submutants); poisonous arguments are structurally valid. |
| M12 | Finalwriter/final-slice OOM swallowed or owned argument/phi/name cleanup omitted: O08/O03/O04/O02 exhaustive sweep/leak/normal-success assertion fails (2 representative submutants required: final-slice and owned cleanup). |

This ledger requires15 concrete submutants (M05/M11/M12 each2; others1), plus the
actual K07 calibration controls. Static/OOM mutants must compile successfully
before their intended assertion; runtime mutants must additionally assemble/link.
Record exact witness, source/assembly hash, command, exit, assertion signature,
stdout/stderr and binary/object identity. A link failure in M01 does NOT replace
its required runtime failure; an unsupported-name parser failure does not count
as a target/loader mutant witness. No undefined ABI execution or malicious host
pointer dereference as a passing test. Mutation artifacts stay outside source and
are not part of routine CI/full-gate product matrices unless separately approved.

### R01–R04: preservation and accounting

- R01: ALL existing registered unit/native/fixture/negative suites and caps remain;
  zero replacements, no dropped malformed cases/goldens, no stealth coverage cut.
- R02: complete old-module assembly parity all8 against actual published opaque
  compiler, including quoted/backslash/common/offset/data and all previous ABI
  transports. Reuse all predecessor oracle modules, not a convenient sample;
  derive exact module count from published registration, not a guessed number.
- R03: one bounded feature harness integrating U/O/N/L and docs/CI; parser and
  mutation originals/probes/calibration kept outside source as appropriate.
  Native success schedule is16 common +24 loader +2 secondary QBE =42 invocations;
  unit cases/OOM ordinals/build stages/mutation runs are separately counted, NOT
  inferred from42 or from opaque526/901/864. No current gate counts are changed.
- R04: before freeze, derive exact future Debug/ReleaseSafe/etc units/stages/
  harnesses from actual authorized registration. Freeze row-to-test/fixture/
  mode/option mapping and all expected counts, same tree for both independent
  reviews, parent-approved single full gate only. Focused author runs cover ledger
  cuts; no duplicate full matrices. Preserve raw unexpected failures, no suite
  shrinking. CI/publication are separate subsequent parent evidence.

## 5. Readiness blockers, disposition and approval checklist

| Blocker from reviews | Revised disposition / still required |
|---|---|
| Naming disagreement | P1 adopts conservative primary regex, portable/reserved intersection; boundary full-bare default deferred. **User ratification still required.** |
| Grammar/diagnostic/error precedence unfrozen | P1/P2 fix proposed codes, token spans, same-line/+0 rules, contextual/lexical precedence and name-error split. Exact fixture offsets require later author tests; policy approval now pending. |
| Direct GOT wrapper bypass | P3 fixes identity accessor equivalence for `.address(.got_symbol)`, preserves old address forms, U06/U07/M06. No source implementation exists. |
| Scalar-only ModulePlans bypass / detached scope | P4 specifies scan before empty return, separate aggregate-before-extern phases, selected detached versus global public scope, invalid FunctionId first; U08/U09/M08–M10. Approval and implementation proof pending. |
| Incorrect uniform late-call schedule | P5 corrects actual source behavior and fixes NEW-target-only scalar schedule, old scalar/record bytes unchanged; U16/N12/N13/M03–M05. |
| Interpreter owner/aggregate/step ambiguity | P6 pins actual root/setup/step/call order and refusal codes, wrapper equivalence, no interpreter native-name scan; U11/U12/M11. |
| Toolchain/loader proof absent | K01–K08 mandatory authorized calibration BEFORE production; actual pins/flags/relocations/COPY avoidance/canonical-pointer/preemption controls remain PENDING. Cannot be closed with this text. |
| Coverage and gate accounting open | U01–U16/O01–O10/N01–N16/L01–L04/M01–M12/R01–R04 bound witness domains/options/control schedule. Approve structure now; K08 fills tool-specific proofs; actual registration derives gate counts before freeze. No reduction of old suites. |
| No actual published predecessor or new authority | Absolute blockers remain. Parent's running opaque gate and review recommendations grant no new execution/implementation rights. |

**Requested future approval package (not a request to start now):**
1. Actual opaque publication identity and verification of predecessor source/binary.
2. Explicit user approval of P1–P8 and fixed ledger, including conservative names,
   diagnostic/order/identity/scopes/schedules/interpreter boundary and semantic holds.
3. Explicit authorization for outside-source K01–K08 calibration; reviewer/parent
   acceptance of its real evidence, pin/flag/relocation and canonical-pointer ledger.
4. Explicit implementation go-ahead against that actual predecessor, with the
   stated complete endpoint, ownership/OOM/resource/refusal contracts and ledger.
5. Later exact-tree reviews, durable backups and one parent full gate/publication.

If calibration needs a different provider/no-relax/relocation model or a policy
cannot meet the fixed witnesses, return for design/ledger approval BEFORE source
work. Nothing here assumes opaque terminal acceptance or authorizes another
milestone, calibration execution, lock use, or production mutation today.
