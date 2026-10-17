# Bounded simulated memory evaluation

`memory.Image` is a caller-owned, fixed-size byte image for scalar interpretation. IL long addresses are **synthetic integers**, not pointers into the Zig process. The evaluator never casts them to host pointers, invokes native memory code or falls back to the compiled program. This opt-in tool is not a complete QBE memory model, process sandbox or native memory checker.

```zig
var image = try memory.Image.init(allocator, 64, .{});
defer image.deinit();
const address = try image.addressAt(1); // deliberately unaligned
try image.write(.word, .{ .word = 42 }, address);
const result = try interpreter.evaluate(allocator, function,
    &.{.{ .long = address }}, .{ .memory_image = &image });
```

The example assumes a validated/parsible scalar function with one long parameter. Modules use the same option with `evaluateModule`. Import `memory` and `interpreter` from the independent `zbe_native` module; this API is separate from the CLI/native address contract.

## Ownership and range

`Image.init(allocator, byte_count, options)` owns one zero-initialized slice. `deinit` frees it. Do not copy ownership, replace the owned slice or alter the base/byte order during evaluation. `image.bytes` may be initialized or inspected directly through ordinary checked Zig slices. There is no resizing, region registration or host-pointer API. The caller keeps the image alive for the entire evaluator call, including internal invocations, and must not concurrently mutate it.

Options:

- `base: u64 = 0x10000`: synthetic address of byte zero. Zero is rejected so an IL null address cannot be valid. A nonempty image's last byte must be representable as u64; construction rejects overflowing extents before allocation. A valid final byte can be `maxInt(u64)`.
- `endian: std.builtin.Endian = .little`: explicit byte interpretation, independent of host byte order. Big-endian image tests are semantic coverage, **not** a big-endian native backend claim. For comparisons with the current AMD64 emitter choose little-endian.

An empty image is valid but has no valid access/address. `addressAt(offset)` returns only in-image byte addresses, not one-past pointers. `read(kind, result_type, address)` and `write(kind, value, address)` enforce the same typed access contracts as MEMORY.md. Misclassified types return `TypeMismatch` before checking the address. Addresses before the image, overflowing accesses, after-end accesses and accesses crossing the end return `MemoryOutOfBounds`. Unaligned in-range accesses are permitted.

Each read/write checks the **entire extent** before touching bytes. A failing write changes nothing; successful narrow stores truncate only the selected low bits. Signed loads extend according to their declared access width and result type; raw floating loads/stores preserve bits, including signaling/quiet NaN payloads, without floating arithmetic. Reads observe the explicit zero initialization or bytes written by the caller/program. This does **not** assert that QBE native `alloc` returns zeroed or initialized storage; native allocation is implemented separately, while evaluators retain default `UnsupportedAllocation`. Opt-in `Options.stack_memory` adds separate synthetic objects without resizing or allocating within the Image (INTERPRETER-ALLOCATIONS.md and NATIVE-ALLOCATIONS.md).

## Interpreter integration

`Options.memory_image: ?*memory.Image = null` is borrowed, never deinitialized or resized by the interpreter. Without an image, reached load/store instructions still consume their instruction step and return `UnsupportedMemory`; old default behavior remains intact. A memory-free path does not require an image.

With an image, every reached load/store consumes exactly one ordinary instruction step, resolves its long address and performs the checked access. No extra steps are charged for individual bytes. Step exhaustion before the instruction wins over memory errors and does not execute the access. The same image is shared by all frames of `evaluateModule`, so aliases and memory observations across internal calls are visible. Existing root-inclusive depth/shared step limits, argument checks, and refusal of host/external/indirect calls remain unchanged. Providing memory never authorizes an external call.

Completed stores **persist** after normal return or a later error, halt, depth/step exhaustion, arithmetic fault or unsupported external call. There is no transaction, rollback or implicit reset between invocations. Per-access no-partial-write behavior is distinct from invocation-wide state. Completed image blits follow the same persistence rule; each failing bounds/overlap-checked copy changes no bytes. Every evaluator-owned frame/argument/phi allocation is still freed on all exits; image ownership remains with the caller.

The image is a single readable/writable region with no permissions, initialization/poison tracking, pointer provenance, object lifetime model of its own, global relocations, atomics, concurrent memory model, external effects or aggregate support. Constant-length byte blits are now supported with whole-span checks, exact-alias/zero-count rules and explicit partial-overlap rejection (BLITS.md). The optional interpreter stack model adds separate initialization/lifetime-checked objects (INTERPRETER-ALLOCATIONS.md). Caller-selected image size and allocator failure bound image storage; the interpreter's execution limits do not constitute a total memory/time/analysis budget. Native compiled programs still use actual native addresses without these checks.

## Bounded verification

Six new tests cover construction/overflow/null/empty/last-u64 boundaries, class errors and no partial writes, both byte orders, raw floating bits, nested shared-image calls, loop phis, repeated/folded evaluation, retained writes after failures, budgets/depth and exhaustive allocation cleanup.

The new independently generated `src/fixtures/memory-oracle.tsv` has **1,472 Python byte-decoding/encoding cases**: 17 load opcode/result variants × 32 bit patterns × two byte orders (1,088), plus six store variants × 32 patterns × two orders (384). Every row runs at eight offsets through both the image API and parsed-IR standalone evaluation; store checks compare complete sentinel images. Expected results come from Python bytes/integer widths, not Zig's implementation or the native compiler. Cases include negative-zero, high-bit extension boundaries and quiet/signaling NaN payloads. `tools/generate_memory_oracle.py --check` verifies reproducibility and is included in CI alongside the eight existing generators.

The separate 55,198-case native memory harness remains unchanged and derives its own expectations. Neither corpus alone proves full QBE semantics, arbitrary memory safety or backend parity.

## Explicit module-global evaluation

Opt-in initialized globals use a separate owned synthetic model
(INTERPRETER-GLOBALS.md), including defined-data-only symbolic initializers
(INTERPRETER-DATA-RELOCATIONS.md). Defaults still refuse symbols; function/external
addresses remain unsupported. Image ownership and native linker/stack behavior
do not change.
