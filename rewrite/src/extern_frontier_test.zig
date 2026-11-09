//! Narrow allocation-frontier witnesses for extern name refusal.
const std = @import("std");
const t = std.testing;
const ir = @import("ir.zig");
const frontend = @import("frontend.zig");
const validation = @import("module_validation.zig");
const planner = @import("abi_amd64_plan.zig");
const amd64 = @import("amd64.zig");
const Module = @import("module.zig").Module;
const Mode = enum { whole, detached, emit };

fn run(mode: Mode, allocator: std.mem.Allocator, module: *const Module) !void {
    switch (mode) {
        .whole => {
            var p = try planner.ModulePlans.init(allocator, module, .{});
            defer p.deinit();
        },
        .detached => {
            var p = try planner.FunctionPlan.init(allocator, module, @fromBackingInt(@as(u32, 0)), .{});
            defer p.deinit();
        },
        .emit => {
            const text = try amd64.emit(allocator, module);
            defer allocator.free(text);
        },
    }
}

test "extern_frontier refuses before post-validation allocations and retries same module" {
    const inputs = [_][]const u8{
        "function l $f() {\n@e\nret extern $.bad\n}",
        "type :R={l 2}\nfunction l $f(:R %p) {\n@e\nret extern $.bad\n}",
        "function l $f() {\n@e\nret 0\n@dead\nret extern $.bad\n}",
        "function l $f() {\n@e\n%r =l call extern $.bad()\nret %r\n}",
    };
    for (inputs, 0..) |text, case_index| {
        var diagnostic: ?@import("source.zig").Diagnostic = null;
        var module = try frontend.parse(t.allocator, .{ .name = "frontier", .text = text }, &diagnostic);
        defer module.deinit();
        const forms: usize = if (case_index == 3) 2 else 1;
        for (0..forms) |form| {
            if (form == 1) {
                const call = &module.functions.items[0].blocks.items[0].instructions.items[0].call;
                const symbol = call.callee.extern_symbol;
                call.callee = .{ .address = .{ .got_symbol = symbol } };
            }
            var measure = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
            try validation.validate(measure.allocator(), &module);
            const generic_allocs = measure.alloc_index;
            try t.expectEqual(measure.allocated_bytes, measure.freed_bytes);
            for ([_]Mode{ .whole, .detached, .emit }) |mode| {
                // Fail each generic validation allocation and the very next
                // allocation. The last must remain untouched on name refusal.
                for (0..generic_allocs + 1) |ordinal| {
                    var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = ordinal, .resize_fail_index = 0 });
                    if (ordinal < generic_allocs) {
                        try t.expectError(error.OutOfMemory, run(mode, failing.allocator(), &module));
                        try t.expect(failing.has_induced_failure);
                    } else {
                        try t.expectError(error.UnsupportedExternSymbol, run(mode, failing.allocator(), &module));
                        try t.expect(!failing.has_induced_failure);
                        try t.expectEqual(generic_allocs, failing.alloc_index);
                    }
                    try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
                    // Same surviving module must give the normal refusal after
                    // any injected failure, without leaking partial state.
                    failing.fail_index = std.math.maxInt(usize);
                    try t.expectError(error.UnsupportedExternSymbol, run(mode, failing.allocator(), &module));
                    try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
                }
            }
        }
    }
}

// These are focused witnesses, not the full O01–O10 ledger. Ordinals are
// zero-based allocation attempts within each measured transaction. In-place
// resize is disabled; successful reservations may remain after a failed attempt.
fn poolRetry(allocator: std.mem.Allocator, ordinal: ?usize) !usize {
    var failing = t.FailingAllocator.init(allocator, .{ .resize_fail_index = 0 });
    var module = Module.init(failing.allocator());
    defer module.deinit();
    const first = try module.symbols.intern("first");
    const stable = module.symbols.get(first).?;
    var buffer: [32]u8 = undefined;
    while (module.symbols.names.items.len < module.symbols.names.capacity) {
        const name = try std.fmt.bufPrint(&buffer, "filler{d}", .{module.symbols.names.items.len});
        _ = try module.symbols.intern(name);
    }
    const count = module.symbols.names.items.len;
    const start = failing.alloc_index;
    if (ordinal) |n| failing.fail_index = start + n;
    var spelling = "external_target".*;
    const id = if (ordinal != null) blk: {
        try t.expectError(error.OutOfMemory, module.symbols.intern(&spelling));
        try t.expect(failing.has_induced_failure);
        try t.expectEqual(count, module.symbols.names.items.len);
        try t.expect(module.symbols.index.get(&spelling) == null);
        try t.expect(module.symbols.get(@fromBackingInt(@as(u32, @intCast(count)))) == null);
        try t.expectEqualStrings("first", module.symbols.get(first).?);
        try t.expectEqual(@intFromPtr(stable.ptr), @intFromPtr(module.symbols.get(first).?.ptr));
        failing.fail_index = std.math.maxInt(usize);
        break :blk try module.symbols.intern(&spelling);
    } else try module.symbols.intern(&spelling);
    const attempts = failing.alloc_index - start;
    try t.expectEqual(count, @as(usize, @intCast(@backingInt(id))));
    @memset(&spelling, 'x');
    try t.expectEqualStrings("external_target", module.symbols.get(id).?);
    const before_alias = failing.alloc_index;
    try t.expectEqual(id, try module.symbols.intern("external_target"));
    try t.expectEqual(before_alias, failing.alloc_index);
    try t.expectEqual(@intFromPtr(stable.ptr), @intFromPtr(module.symbols.get(first).?.ptr));
    return attempts;
}

fn callRetry(allocator: std.mem.Allocator, ordinal: ?usize, wrapped: bool) !usize {
    var failing = t.FailingAllocator.init(allocator, .{ .resize_fail_index = 0 });
    var module = Module.init(failing.allocator());
    defer module.deinit();
    const target = try module.symbols.intern("external_target");
    const argument = try module.symbols.intern("external_argument");
    const environment = try module.symbols.intern("external_environment");
    const function_id = try module.addFunction("caller", .long);
    const f = module.getFunction(function_id).?;
    const block = try f.addBlock(null);
    const result = try f.declareValue(.long);
    const callee: ir.CallTarget = if (wrapped) .{ .address = .{ .got_symbol = target } } else .{ .extern_symbol = target };
    var args = [_]ir.CallArgument{.{ .scalar_type = .long, .operand = .{ .got_symbol = argument } }};
    const options: ir.CallOptions = .{ .environment = .{ .got_symbol = environment } };
    const start = failing.alloc_index;
    if (ordinal) |n| {
        failing.fail_index = start + n;
        try t.expectError(error.OutOfMemory, f.appendCall(block, result, callee, &args, options));
        try t.expect(failing.has_induced_failure);
        try t.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
        try t.expect(f.values.items[@backingInt(result)].definition == .pending);
        failing.fail_index = std.math.maxInt(usize);
    }
    try f.appendCall(block, result, callee, &args, options);
    const attempts = failing.alloc_index - start;
    args[0].operand = .{ .constant = .{ .long = 99 } };
    const call = f.blocks.items[0].instructions.items[0].call;
    try t.expectEqual(target, call.callee.symbolicIdentity().?);
    try t.expectEqual(argument, call.arguments[0].operand.got_symbol);
    try t.expectEqual(environment, call.environment.?.got_symbol);
    const backlink = f.values.items[@backingInt(result)].definition.instruction;
    try t.expectEqual(block, backlink.block);
    try t.expectEqual(@as(usize, 0), backlink.index);
    try f.terminate(block, .{ .return_value = .{ .value = result } });
    try validation.validate(allocator, &module);
    return attempts;
}

test "extern pool and both call builders retry the same owner after OOM" {
    var tracked = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    const pool_attempts = try poolRetry(tracked.allocator(), null);
    try t.expect(pool_attempts > 0);
    for (0..pool_attempts) |ordinal| _ = try poolRetry(tracked.allocator(), ordinal);
    for ([_]bool{ false, true }) |wrapped| {
        const call_attempts = try callRetry(tracked.allocator(), null, wrapped);
        try t.expect(call_attempts > 0);
        for (0..call_attempts) |ordinal| _ = try callRetry(tracked.allocator(), ordinal, wrapped);
    }
    try t.expectEqual(tracked.allocated_bytes, tracked.freed_bytes);
}

test "successful extern emission retries same module after every measured OOM" {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    var module = try frontend.parse(t.allocator, .{ .name = "emit-retry", .text = "function l $f() {\n@e\n%p =l copy extern $target\n%r =l call extern $callee(l %p)\nret %r\n}" }, &diagnostic);
    defer module.deinit();
    var measure = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    const baseline = try amd64.emit(measure.allocator(), &module);
    try t.expect(std.mem.indexOf(u8, baseline, "target@GOTPCREL") != null);
    try t.expect(std.mem.indexOf(u8, baseline, "callee@GOTPCREL") != null);
    defer measure.allocator().free(baseline);
    const attempts = measure.alloc_index;
    try t.expect(attempts > 0);
    for (0..attempts) |ordinal| {
        var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = ordinal, .resize_fail_index = 0 });
        try t.expectError(error.OutOfMemory, amd64.emit(failing.allocator(), &module));
        try t.expect(failing.has_induced_failure);
        try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        failing.fail_index = std.math.maxInt(usize);
        const text = try amd64.emit(failing.allocator(), &module);
        try t.expectEqualStrings(baseline, text);
        failing.allocator().free(text);
        try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
}
