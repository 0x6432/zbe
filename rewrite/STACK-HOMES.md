# Optional stack-home reuse

`stack_homes.Layout.init(allocator, function, interference_options)` builds a validated scalar interference graph and greedily assigns eight-byte stack slots in value-ID order. Each value chooses the lowest slot not used by an already colored neighbor. Distinct `SlotId` and `ValueId` types avoid confusing a home number with a value. The result owns its value-to-slot slice and retains no IR, graph or analysis pointers; destroy with `deinit` and rebuild after mutation. `slot(value)` returns `null` for out-of-range value ordinals. IDs and layouts are function-scoped caller invariants, not owner-encoded capabilities.

This is deterministic proper coloring of the conservative scalar-home relation, **not optimal coloring or physical register allocation**. Slot IDs are contiguous from zero, `slot_count` never exceeds the value count, and an empty function needs no value homes. Slots may be reused across scalar widths/classes because every slot is eight bytes and every use reloads its own value width. No value's bits are read after its lifetime merely to preserve an obsolete SSA home.

The graph includes dead-result writes and simultaneous parameter/phi bundles, so still-emitted dead definitions cannot overwrite live homes. Dying operands can share a result's slot: the emitter loads all operands into scratch registers before writing the result. Phi edge copies still load **all** incoming values into separate scratch homes before committing any result. Scratch starts after the colored value-home area and is never colored with ordinary values. Incoming parameters keep distinct slots and are homed before ordinary scratch use. Fixed registers, physical aliases and ABI register choices are unchanged.

## Emitter and CLI

The existing `amd64.emit(allocator, module)` keeps the original unique-home behavior. `amd64.emitWithOptions(allocator, module, .{ .reuse_stack_homes = true })` enables coloring. Emission never modifies the IR and returns no partial assembly on failure. Analysis/layout storage is function-local and released after emission, including on allocation failure. The 64 KiB frame cap applies to **colored homes plus phi scratch**, still rounded to 16 bytes; it is not removed and large-frame probing remains unsupported.

```sh
./zig-out/bin/zbe-native --reuse-stack-homes input.ssa output.s
./zig-out/bin/zbe-native --fold-integers --reuse-stack-homes input.ssa output.s
python3 tools/native_check.py --reuse-stack-homes
python3 tools/native_float_check.py --fold-integers --reuse-stack-homes
```

Both flags precede the paths and may be given in either order. Folding runs before layout. Unknown or duplicate flags are usage errors and do not alter output. Default output/API behavior is unchanged; this does not introduce a legacy `-O` level.

## Limits

Coloring scans previously colored values, taking O(values²) neighbor queries, in addition to graph/liveness construction. The graph's 64 MiB default adjacency/scratch estimate and separate 64 MiB liveness matrix estimate remain in force. Layout additionally owns O(values) slot storage and one temporary color bitset. These are **not** total-process memory or time limits. Opt-in emission may return `InterferenceTooLarge` or `LivenessTooLarge`, even where unique-home emission did not need these analyses. No scalability or runtime-speed improvement is claimed.

## Verification

Tests check proper coloring on every interference edge, contiguous slots, repeatability, empty frames, snapshot lifetime, bounds, failure propagation and exhaustive allocation cleanup. They cover mixed-width/class dying chains, dead writes, parameter bundles, all 32 mixed programs and phi/floating fixtures. Emitter tests keep explicit default output identical, check phi scratch beyond colored homes, inject every allocation failure across multiple functions and compile an 8,193-value one-home chain that exceeds the uncolored frame cap.

The native integer harness adds five results covering a long chain, dead writes, dead phi results with a live-through input and unused incoming parameters. Its 301-value chain is checked to reserve 2,416 bytes by default and 16 bytes with reuse; both variants must return 301. All existing integer/float/bit-pattern/mixed-ABI/fault tests run in all four folding/reuse combinations. Flag-order and rejection/output-preservation tests remain explicit. Smaller measured frame size on this bounded case is not a performance benchmark or full backend acceptance.

The separate `--callee-saved-homes` option consumes the same coloring but maps its first five colors to explicitly preserved GP registers. It implies coloring, and specifying both home flags is redundant. See PRESERVED-HOMES.md for its narrower-than-full-allocation guarantees.
