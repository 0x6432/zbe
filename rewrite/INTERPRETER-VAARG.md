# Opt-in bounded synthetic vaarg descriptor consumers

`interpreter.Options.consume_vaargs` defaults to false. When enabled, reached
scalar `vaarg` reads/advances a manually prepared synthetic descriptor through
existing Image, live stack-object or owned-global accesses. No integer becomes a
host pointer. This does not materialize native register-save storage, initialize
`vastart`, accept root argument tails, execute variadic internal calls, authorize
external/indirect host calls or claim complete variadic interpretation/ABI parity.
The frontend, IR, analyses, folding and native emitter remain unchanged.

## Explicit layout, raw values and byte order

The descriptor uses the existing scalar layout:

| Offset | Width | Meaning |
| --- | --- | --- |
| 0 | unsigned32 | GP save-area byte offset |
| 4 | unsigned32 | SSE save-area byte offset |
| 8 | unsigned64 synthetic address | next overflow slot |
| 16 | unsigned64 synthetic address | register-save area |

Word/long select GP offset<48, advancing by8. Single/double select SSE offset<176,
advancing by16. Otherwise the selected offset is left unchanged and the shared
next-overflow pointer advances by8. Word/single load exactly4 bytes; long/double
load exactly8. Values retain raw integer/floating bits, including signed zero and
NaN payloads, with no arithmetic, promotions or inferred runtime argument types.
Only selected fields are read/written; unused fields need not be initialized.
No implicit alignment or stride normalization is added.

Each field/source access must fit one checked live region/object, as ordinary
memory operations do. There is no additional fictitious whole24-byte access or
structure-provenance check. Every read/write uses its region's configured byte
order, even when the descriptor and source have different byte orders. The
layout offsets/widths follow the existing scalar consumer; synthetic big-endian
use is NOT a native System V descriptor/target claim. Byte blits still copy bytes
without conversion; caller-prepared pointers must be synthetic addresses.

## Error, write and execution order

The existing validation, depth, configuration, global-setup and root-argument
preflight order is unchanged. Each reached vaarg consumes one ordinary instruction
step. Exhausted budget wins before access. With the default option, refusal is
UnsupportedVariadicOperation before resolving even a symbolic/undefined list.
With the option enabled, resolve the long list, require an enabled memory model,
read the selected u32 field and needed pointer, and calculate the source/next
cursor with checked u64 arithmetic. Address/next-pointer calculation overflow
returns MemoryOutOfBounds before updating the cursor. This explicit invalid-domain
boundary does not emulate native wrapping addresses or promise native fault parity.

The successful selected cursor write occurs BEFORE the source load. A later
source bounds/extent-overflow/uninitialized-byte fault retains that write, as do
later errors/halts/budget exhaustion. A source alias into the cursor observes its
advanced bytes, not a pre-update snapshot. No invocation transaction or rollback
is introduced; ordinary per-access complete-span write checks remain unchanged.
No hidden byte/slot loop or extra instruction steps are charged.

A supplied empty region is still bounded; no region is implicitly resized or
allocated. Reached consume with no memory model returns UnsupportedMemory after
list resolution. Existing symbolic resolution errors, initialization/guard/dead-
object checks and owned cleanup remain. A caller-provided Image is never freed,
replaced, resized or reset by evaluation; completed writes persist. Owned globals
reset per evaluation and stack addresses are not revived within an evaluation.

## What stays unsupported

Reached `vastart` always retains UnsupportedVariadicOperation, including with this
option and valid memory. Reached internal calls to variadic definitions retain
UnsupportedVariadicCall before depth/argument resolution. Root calls still accept
only their exact named parameter array, not a tail; no descriptor is inferred
from that array. A function's variadic flag itself does not construct or prohibit
a manually supplied descriptor. Existing default/safe-path behavior is unchanged.
There is no va_end/va_copy helper, host stdarg access, aggregate, external function
resolver or arbitrary native pointer capability in this model. A bounded blit can
copy descriptor bytes under existing overlap/initialization rules; independent
copied cursors still share the addressed source bytes.

## Verification design

Tests compare raw results and complete sentinel images against explicit independent
cursor/source expectations, across all four classes, both byte orders, GP/SSE
thresholds/high unsigned offsets and standalone/module entry points. Other checks
cover exact4-byte final-u64 reads, arithmetic-vs-source-fault write ordering,
source/cursor aliases, default/refusal/setup/budgets, ordinary child sharing and copied cursor independence,
unused folded consumption, partially initialized stack descriptors, uninitialized
source writes, global reset/mixed region byte orders and stale returned objects.
Injected allocation failures cover Image/module/frame/global/stack ownership and
later source errors. Existing default-refusal tests/native harnesses/generators
remain unchanged. Actual completed results belong in HANDOFF.md, not this design.
