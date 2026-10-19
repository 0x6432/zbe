//! Owned, checked Linux AMD64 SysV plans. External snapshots are not emitter inputs.
//! ModulePlans constructs fresh, globally checked emission-scoped plans.
const std = @import("std");
const ir = @import("ir.zig");
const abi = @import("abi_amd64.zig");
const modules = @import("module.zig");
const records = @import("record_declaration.zig");
const validation = @import("module_validation.zig");
const homes = @import("stack_homes.zig");
pub const Error = validation.Error || homes.Error || error{ InvalidFunction, UnsupportedAggregatePlan, StackArgumentsTooLarge, FrameTooLarge };
pub const Options = struct { reuse_stack_homes: bool = false, callee_saved_homes: bool = false };
pub const Stack = struct { offset: u64, extent: u64, alignment: u8, incoming: i32 };
pub const Location = union(enum) { general: abi.General, vector: abi.Vector, stack: Stack };
pub const Argument = struct {
    descriptor: ir.AbiDescriptor,
    carrier: ir.ScalarType,
    /// Language payload, not carrier width or eightbyte spill extent.
    declared_bytes: u64,
    location: Location,
};
pub const MemoryResult = struct {
    record_id: records.Id,
    declared_bytes: u64,
    alignment: u8,
    hidden: abi.General = .rdi,
    returned: enum { rax } = .rax,
};
pub const Result = union(enum) { none, scalar: ir.AbiType, memory: MemoryResult };
pub const Signature = struct {
    allocator: std.mem.Allocator,
    result: Result,
    arguments: []Argument,
    general_used: u8,
    vector_used: u8,
    outgoing_bytes: u64,
    environment: bool,
    variadic: bool,
    variadic_start: ?usize,
    pub fn deinit(self: *Signature) void {
        self.allocator.free(self.arguments);
        self.* = undefined;
    }
};
pub const CallSite = struct {
    block: ir.BlockId,
    instruction: usize,
    target: ir.CallTarget,
    result_value: ?ir.ValueId,
    signature: Signature,
    pad_index: ?usize,
};
pub const Pad = struct {
    call_index: usize,
    record_id: records.Id,
    declared_bytes: u64,
    alignment: u8,
    /// Positive downward end: object is [RBP-end, RBP-end+declared_bytes).
    end: u64,
};
pub const Frame = struct {
    bytes: u64,
    scratch_base: u64,
    saved_base: u64,
    saved_count: usize,
    variadic_save_end: ?u64,
    hidden_return_end: ?u64,
    fixed_prefix_bytes: u64,
    /// Relative to CURRENT RSP, including after dynamic allocations.
    outgoing_bytes: u64,
};

/// Detached owned facts, not permission to consume edited IR. No owner pointer.
/// The public emitter rebuilds through ModulePlans, never accepting this as input.
pub const FunctionPlan = struct {
    allocator: std.mem.Allocator,
    function_id: modules.FunctionId,
    signature: Signature,
    calls: []CallSite,
    pads: []Pad,
    home_layout: ?homes.Layout,
    frame: Frame,

    pub fn init(allocator: std.mem.Allocator, module: *const modules.Module, id: modules.FunctionId, options: Options) Error!FunctionPlan {
        if (@backingInt(id) >= module.functions.items.len) return error.InvalidFunction;
        try validation.validate(allocator, module);
        const function = module.functions.items[@backingInt(id)];
        // COMPLETE allocation-free target scan before any home/plan allocation
        // or geometry check. Generic module validation above may itself allocate.
        try eligibleFunction(module, function);
        return build(allocator, module, id, options);
    }

    fn build(allocator: std.mem.Allocator, module: *const modules.Module, id: modules.FunctionId, options: Options) Error!FunctionPlan {
        const function = module.functions.items[@backingInt(id)];
        var signature = try planSignature(allocator, module, .{ .function = function });
        errdefer signature.deinit();
        var call_count: usize = 0;
        var pad_count: usize = 0;
        for (function.blocks.items) |block| for (block.instructions.items) |instruction| switch (instruction) {
            .call => |call| {
                call_count = std.math.add(usize, call_count, 1) catch return error.FrameTooLarge;
                if (try call.resultAbi(function)) |ty| if (ty == .record) {
                    pad_count = std.math.add(usize, pad_count, 1) catch return error.FrameTooLarge;
                };
            },
            else => {},
        };
        const calls = try allocator.alloc(CallSite, call_count);
        var initialized: usize = 0;
        errdefer {
            for (calls[0..initialized]) |*call| call.signature.deinit();
            allocator.free(calls);
        }
        const pads = try allocator.alloc(Pad, pad_count);
        errdefer allocator.free(pads);
        var pad_index: usize = 0;
        var outgoing: u64 = 0;
        for (function.blocks.items, 0..) |block, b| for (block.instructions.items, 0..) |instruction, i| switch (instruction) {
            .call => |call| {
                const planned = try planSignature(allocator, module, .{ .call = .{ .function = function, .call = call } });
                calls[initialized] = .{ .block = @fromBackingInt(@as(u32, @intCast(b))), .instruction = i, .target = call.callee, .result_value = call.result, .signature = planned, .pad_index = null };
                initialized += 1;
                outgoing = @max(outgoing, planned.outgoing_bytes);
                if (planned.result == .memory) {
                    const result = planned.result.memory;
                    calls[initialized - 1].pad_index = pad_index;
                    pads[pad_index] = .{ .call_index = initialized - 1, .record_id = result.record_id, .declared_bytes = result.declared_bytes, .alignment = @max(8, result.alignment), .end = 0 };
                    pad_index += 1;
                }
            },
            else => {},
        };
        var layout: ?homes.Layout = if (options.reuse_stack_homes or options.callee_saved_homes) try homes.Layout.init(allocator, function, .{}) else null;
        errdefer if (layout) |*owned| owned.deinit();
        const saved = if (options.callee_saved_homes) @min(@as(usize, 5), layout.?.slot_count) else 0;
        const slots = if (layout) |owned| owned.slot_count else function.values.items.len;
        var phis: usize = 0;
        for (function.blocks.items) |block| phis = @max(phis, block.phis.items.len);
        var frame = try baseFrame(slots - saved, phis, saved, function.parameters.items.len, function.variadic);
        var cursor = frame.fixed_prefix_bytes;
        if (signature.result == .memory) {
            cursor = try reserve(cursor, 8, 8);
            frame.hidden_return_end = cursor;
        }
        for (pads) |*pad| {
            cursor = try reserve(cursor, pad.declared_bytes, pad.alignment);
            pad.end = cursor;
        }
        frame.fixed_prefix_bytes = try frameAlign(cursor, 16);
        frame.outgoing_bytes = outgoing;
        frame.bytes = try finishFrame(frame.fixed_prefix_bytes, outgoing);
        return .{ .allocator = allocator, .function_id = id, .signature = signature, .calls = calls, .pads = pads, .home_layout = layout, .frame = frame };
    }
    pub fn deinit(self: *FunctionPlan) void {
        self.signature.deinit();
        for (self.calls) |*call| call.signature.deinit();
        self.allocator.free(self.calls);
        self.allocator.free(self.pads);
        if (self.home_layout) |*layout| layout.deinit();
        self.* = undefined;
    }
};

/// Fresh emission-scoped plans: ALL target eligibility precedes every plan
/// array/home/frame allocation. No stale plan is an input to the public emitter.
/// Scalar-only modules allocate no plan arrays/home layouts here.
pub const ModulePlans = struct {
    allocator: std.mem.Allocator,
    functions: []?FunctionPlan,

    pub fn init(allocator: std.mem.Allocator, module: *const modules.Module, options: Options) Error!ModulePlans {
        try validation.validate(allocator, module);
        var needed = false;
        for (module.functions.items) |function| {
            try eligibleFunction(module, function);
            if (recordRelevant(function)) needed = true;
        }
        if (!needed) return .{ .allocator = allocator, .functions = &.{} };
        const functions = try allocator.alloc(?FunctionPlan, module.functions.items.len);
        @memset(functions, null);
        errdefer {
            for (functions) |*entry| if (entry.*) |*plan| plan.deinit();
            allocator.free(functions);
        }
        for (module.functions.items, 0..) |function, i| if (recordRelevant(function)) {
            functions[i] = try FunctionPlan.build(allocator, module, @fromBackingInt(@as(u32, @intCast(i))), options);
        };
        return .{ .allocator = allocator, .functions = functions };
    }
    pub fn get(self: *const ModulePlans, ordinal: usize) ?*const FunctionPlan {
        if (ordinal >= self.functions.len) return null;
        return if (self.functions[ordinal]) |*plan| plan else null;
    }
    pub fn deinit(self: *ModulePlans) void {
        for (self.functions) |*entry| if (entry.*) |*plan| plan.deinit();
        self.allocator.free(self.functions);
        self.* = undefined;
    }
};
fn recordRelevant(function: *const ir.Function) bool {
    if (function.hasRecordSignature()) return true;
    for (function.blocks.items) |block| for (block.instructions.items) |instruction| switch (instruction) {
        .call => |call| if (call.hasRecordAbi()) return true,
        else => {},
    };
    return false;
}

fn eligibleDescriptor(module: *const modules.Module, ty: ir.AbiDescriptor) Error!void {
    if (ty == .record) {
        const record = module.getRecord(ty.record) orelse return error.InvalidAggregateType;
        if (record.size < 17 or record.size > 4096 or record.alignment > 16) return error.UnsupportedAggregatePlan;
    }
}
fn eligibleFunction(module: *const modules.Module, function: *const ir.Function) Error!void {
    if (function.hasRecordSignature() and (function.variadic or function.environment != null)) return error.UnsupportedAggregatePlan;
    if (try function.returnAbi()) |ty| try eligibleDescriptor(module, ty);
    for (function.ordinaryParameters()) |id| try eligibleDescriptor(module, try function.parameterAbi(id));
    for (function.blocks.items) |block| for (block.instructions.items) |instruction| switch (instruction) {
        .call => |call| {
            if (call.hasRecordAbi() and (call.environment != null or call.variadic_start != null or call.callee == .address)) return error.UnsupportedAggregatePlan;
            if (try call.resultAbi(function)) |ty| try eligibleDescriptor(module, ty);
            for (call.arguments) |argument| try eligibleDescriptor(module, try argument.abi());
        },
        else => {},
    };
}
const View = union(enum) {
    function: *const ir.Function,
    call: struct { function: *const ir.Function, call: ir.Call },
    fn count(self: View) usize {
        return switch (self) {
            .function => |f| f.ordinaryParameters().len,
            .call => |c| c.call.arguments.len,
        };
    }
    fn argument(self: View, i: usize) Error!ir.AbiDescriptor {
        return switch (self) {
            .function => |f| f.parameterAbi(f.ordinaryParameters()[i]),
            .call => |c| c.call.arguments[i].abi(),
        };
    }
    fn result(self: View) Error!?ir.AbiDescriptor {
        return switch (self) {
            .function => |f| f.returnAbi(),
            .call => |c| c.call.resultAbi(c.function),
        };
    }
};
const general_bank = [_]abi.General{ .rdi, .rsi, .rdx, .rcx, .r8, .r9 };
const vector_bank = [_]abi.Vector{ .xmm0, .xmm1, .xmm2, .xmm3, .xmm4, .xmm5, .xmm6, .xmm7 };
fn planSignature(allocator: std.mem.Allocator, module: *const modules.Module, view: View) Error!Signature {
    const result: Result = if (try view.result()) |ty| switch (ty) {
        .scalar => |scalar| .{ .scalar = scalar },
        .record => |id| result: {
            const record = module.getRecord(id) orelse return error.InvalidAggregateType;
            break :result .{ .memory = .{ .record_id = id, .declared_bytes = record.size, .alignment = record.alignment } };
        },
    } else .none;
    var gp: u8 = if (result == .memory) 1 else 0;
    var sse: u8 = 0;
    var cursor: u64 = 0;
    const arguments = try allocator.alloc(Argument, view.count());
    errdefer allocator.free(arguments);
    for (arguments, 0..) |*argument, i| {
        const ty = try view.argument(i);
        const payload = if (ty == .scalar) scalarBytes(ty.scalar) else module.getRecord(ty.record).?.size;
        const alignment: u8 = if (ty == .scalar) 8 else @max(8, module.getRecord(ty.record).?.alignment);
        const location: Location = location: {
            if (ty == .scalar) {
                if (ty.scalar.scalar().isInteger() and gp < general_bank.len) {
                    const reg = general_bank[gp];
                    gp += 1;
                    break :location .{ .general = reg };
                }
                if (!ty.scalar.scalar().isInteger() and sse < vector_bank.len) {
                    const reg = vector_bank[sse];
                    sse += 1;
                    break :location .{ .vector = reg };
                }
            }
            const offset = try stackAlign(cursor, alignment);
            const extent = if (ty == .scalar) 8 else try stackAlign(payload, 8);
            const incoming = try incomingOffset(offset, payload, ty == .record);
            cursor = std.math.add(u64, offset, extent) catch return error.StackArgumentsTooLarge;
            break :location .{ .stack = .{ .offset = offset, .extent = extent, .alignment = alignment, .incoming = incoming } };
        };
        argument.* = .{ .descriptor = ty, .carrier = ty.carrierType(), .declared_bytes = payload, .location = location };
    }
    return .{ .allocator = allocator, .result = result, .arguments = arguments, .general_used = gp, .vector_used = sse, .outgoing_bytes = try stackAlign(cursor, 16), .environment = switch (view) {
        .function => |f| f.environment != null,
        .call => |c| c.call.environment != null,
    }, .variadic = switch (view) {
        .function => |f| f.variadic,
        .call => |c| c.call.variadic_start != null,
    }, .variadic_start = switch (view) {
        .function => null,
        .call => |c| c.call.variadic_start,
    } };
}
fn scalarBytes(ty: ir.AbiType) u64 {
    return switch (ty) {
        .signed_byte, .unsigned_byte => 1,
        .signed_half, .unsigned_half => 2,
        .word, .single => 4,
        .long, .double => 8,
    };
}
fn stackAlign(value: u64, alignment: u8) error{StackArgumentsTooLarge}!u64 {
    const mask: u64 = alignment - 1;
    return (std.math.add(u64, value, mask) catch return error.StackArgumentsTooLarge) & ~mask;
}
fn incomingOffset(offset: u64, size: u64, record: bool) error{StackArgumentsTooLarge}!i32 {
    const start = std.math.add(u64, 16, offset) catch return error.StackArgumentsTooLarge;
    if (start > std.math.maxInt(i32)) return error.StackArgumentsTooLarge;
    if (record) {
        if (size == 0) return error.StackArgumentsTooLarge;
        const last = std.math.add(u64, start, size - 1) catch return error.StackArgumentsTooLarge;
        if (last > std.math.maxInt(i32)) return error.StackArgumentsTooLarge;
    }
    return @intCast(start);
}
fn frameAdd(a: u64, b: u64) error{FrameTooLarge}!u64 {
    return std.math.add(u64, a, b) catch return error.FrameTooLarge;
}
fn frameAlign(value: u64, alignment: u8) error{FrameTooLarge}!u64 {
    const mask: u64 = alignment - 1;
    return (try frameAdd(value, mask)) & ~mask;
}
fn reserve(cursor: u64, size: u64, alignment: u8) error{FrameTooLarge}!u64 {
    return frameAlign(try frameAdd(cursor, size), alignment);
}
fn finishFrame(prefix: u64, outgoing: u64) error{FrameTooLarge}!u64 {
    const bytes = try frameAlign(try frameAdd(prefix, outgoing), 16);
    if (bytes > 65536) return error.FrameTooLarge;
    return bytes;
}
fn baseFrame(values: usize, phis: usize, saved: usize, parameters: usize, variadic: bool) error{FrameTooLarge}!Frame {
    const count = try frameAdd(values, phis);
    const total = try frameAdd(count, saved);
    const raw = std.math.mul(u64, total, 8) catch return error.FrameTooLarge;
    var bytes = try frameAlign(raw, 16);
    if (parameters > 6 and parameters - 6 > (std.math.maxInt(i32) - 16) / 8) return error.FrameTooLarge;
    const scratch = std.math.mul(u64, values, 8) catch return error.FrameTooLarge;
    const saved_base = std.math.mul(u64, count, 8) catch return error.FrameTooLarge;
    const variadic_end: ?u64 = if (variadic) end: {
        bytes = try frameAdd(bytes, 176);
        break :end bytes;
    } else null;
    _ = try finishFrame(bytes, 0);
    return .{ .bytes = bytes, .scratch_base = scratch, .saved_base = saved_base, .saved_count = saved, .variadic_save_end = variadic_end, .hidden_return_end = null, .fixed_prefix_bytes = bytes, .outgoing_bytes = 0 };
}

test "aggregate_abi_planner checked byte geometry independent inclusive overflow and frame cap oracles" {
    const t = std.testing;
    try t.expectEqual(@as(i32, 2147483640), try incomingOffset(2147483624, 8, false));
    try t.expectError(error.StackArgumentsTooLarge, incomingOffset(2147483632, 8, false));
    try t.expectEqual(@as(i32, 2147483624), try incomingOffset(2147483608, 24, true));
    try t.expectError(error.StackArgumentsTooLarge, incomingOffset(2147483616, 24, true));
    try t.expectError(error.StackArgumentsTooLarge, incomingOffset(0, 0, true));
    try t.expectError(error.StackArgumentsTooLarge, incomingOffset(std.math.maxInt(u64), 1, true));
    try t.expectError(error.StackArgumentsTooLarge, incomingOffset(0, std.math.maxInt(u64), true));
    try t.expectError(error.StackArgumentsTooLarge, stackAlign(std.math.maxInt(u64), 16));
    try t.expectError(error.FrameTooLarge, reserve(std.math.maxInt(u64), 1, 8));
    try t.expectError(error.FrameTooLarge, reserve(std.math.maxInt(u64) - 1, 1, 16));
    try t.expectError(error.FrameTooLarge, baseFrame(std.math.maxInt(usize) / 8 + 1, 0, 0, 0, false));
    try t.expectEqual(@as(u64, 65536), (try baseFrame(8192, 0, 0, 0, false)).bytes);
    try t.expectError(error.FrameTooLarge, baseFrame(8193, 0, 0, 0, false));
    const pad = try reserve(65504, 17, 8);
    try t.expectEqual(@as(u64, 65528), pad);
    try t.expectEqual(@as(u64, 65536), try finishFrame(try frameAlign(pad, 16), 0));
    try t.expectError(error.FrameTooLarge, finishFrame(try frameAlign(pad, 16), 16));
    // Hand worked 32-prefix -> hidden slot40 -> pads64,96 -> outgoing80.
    const hidden = try reserve(32, 8, 8);
    const first = try reserve(hidden, 17, 8);
    const second = try reserve(first, 32, 16);
    try t.expectEqual(@as(u64, 40), hidden);
    try t.expectEqual(@as(u64, 64), first);
    try t.expectEqual(@as(u64, 96), second);
    try t.expectEqual(@as(u64, 176), try finishFrame(second, 80));
}
