const std = @import("std");
const t = std.testing;
const Module = @import("module.zig").Module;
const frontend = @import("frontend.zig");
const amd64 = @import("amd64.zig");
const planner = @import("abi_amd64_plan.zig");
const interpreter = @import("interpreter.zig");
const ir = @import("ir.zig");
const fixture = @embedFile("fixtures/aggregate_abi_native.ssa");
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "aggregate_abi_native", .text = text }, &diagnostic);
}
fn small(allocator: std.mem.Allocator) !Module {
    return parse(allocator, "type :A={b 17}\nfunction :A $f(:A %a){\n@e\n%r =:A call $external(:A %a)\nret %r\n}");
}
test "aggregate_abi_native fresh module bridge owns all plans and exact byte instructions" {
    var module = try small(t.allocator);
    defer module.deinit();
    var plans = try planner.ModulePlans.init(t.allocator, &module, .{});
    defer plans.deinit();
    try t.expectEqual(@as(usize, 1), plans.functions.len);
    const plan = plans.get(0).?;
    try t.expectEqual(@as(u64, 32), plan.frame.outgoing_bytes);
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(t.allocator, &module, options);
        defer t.allocator.free(assembly);
        try t.expectEqual(@as(usize, 2), std.mem.count(u8, assembly, "rep movsb"));
        try t.expectEqual(@as(usize, 2), std.mem.count(u8, assembly, "movl $17, %ecx"));
        try t.expect(std.mem.indexOf(u8, assembly, "leaq 16(%rbp), %rax") != null);
        try t.expect(std.mem.indexOf(u8, assembly, "movq %rdi, -") != null);
    }
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluateModule(t.allocator, &module, @fromBackingInt(@as(u32, 0)), &.{}, .{}));
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluate(t.allocator, module.functions.items[0], &.{}, .{ .max_call_depth = 0 }));
    module.types.items[0].size += 1;
    try t.expectError(error.InvalidRecordLayout, amd64.emit(t.allocator, &module));
    try t.expectEqual(@as(u64, 17), plan.signature.result.memory.declared_bytes);
}

test "aggregate_abi_native global eligibility precedes every legacy frame and plan allocation" {
    var module = Module.init(t.allocator);
    defer module.deinit();
    const big = try module.addFunction("too_large", null);
    const f = module.getFunction(big).?;
    for (0..8193) |_| _ = try f.addParameter(.long);
    const b = try f.addBlock(null);
    try f.terminate(b, .{ .return_value = null });
    const tiny = try module.addRecord("OveralignedFloat", 16, &.{.{ .element = .{ .scalar = .single } }});
    const next = try module.addFunctionDescriptor("unsupported", .{ .record = tiny });
    const later = module.getFunction(next).?;
    const block = try later.addBlock(null);
    try later.terminate(block, .{ .return_value = .{ .constant = .{ .long = 0 } } });
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true } }) |options| try t.expectError(error.UnsupportedAggregateAbi, amd64.emitWithOptions(t.allocator, &module, options));
    // Change ONLY unsupported type to a valid eligible type: frame resource error
    // now propagates, not converted to an aggregate-unsupported catch-all.
    const valid = try module.addRecord("Valid", null, &.{.{ .element = .{ .scalar = .byte }, .count = 17 }});
    later.return_descriptor = .{ .record = valid };
    try t.expectError(error.FrameTooLarge, amd64.emit(t.allocator, &module));
}

test "aggregate_abi_native pure scalar path allocates no plans and mixed reference identities are exact" {
    var scalar = try parse(t.allocator, @embedFile("fixtures/record_declaration_symbol_identity.ssa"));
    defer scalar.deinit();
    var plans = try planner.ModulePlans.init(t.allocator, &scalar, .{});
    defer plans.deinit();
    try t.expectEqual(@as(usize, 0), plans.functions.len);
    var mixed = try parse(t.allocator, @embedFile("fixtures/aggregate_abi_native_mixed.ssa"));
    defer mixed.deinit();
    var reference = try parse(t.allocator, @embedFile("fixtures/aggregate_abi_native_scalar_reference.ssa"));
    defer reference.deinit();
    try t.expectEqual(reference.symbols.names.items.len, mixed.symbols.names.items.len);
    for (reference.symbols.names.items, mixed.symbols.names.items) |a, b| try t.expectEqualStrings(a, b);
    try t.expectEqual(reference.functions.items.len, mixed.functions.items.len);
    for (reference.functions.items, mixed.functions.items, 0..) |a, b, i| {
        try t.expectEqual(a.name, b.name);
        const fid: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, @intCast(i)));
        try t.expect(reference.getFunction(fid).? == a and mixed.getFunction(fid).? == b);
        if (i < 4) {
            try t.expect(!a.hasRecordSignature());
            try t.expect(!b.hasRecordSignature());
        }
    }
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        const a = try amd64.emitWithOptions(t.allocator, &reference, options);
        defer t.allocator.free(a);
        const b = try amd64.emitWithOptions(t.allocator, &mixed, options);
        defer t.allocator.free(b);
        // Compare ONLY unaffected function prefix. Both symbol tables/function
        // ordinals checked above; independent old45ec fragment hashes in harness.
        const boundary = ".local aggregate_abi_native_side";
        const a_end = std.mem.indexOf(u8, a, boundary).?;
        const b_end = std.mem.indexOf(u8, b, boundary).?;
        try t.expectEqualSlices(u8, a[0..a_end], b[0..b_end]);
    }
}
fn exercise(allocator: std.mem.Allocator) !void {
    var module = try small(allocator);
    defer module.deinit();
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(allocator, &module, options);
        allocator.free(assembly);
    }
}
test "aggregate_abi_native every parser validator plan home writer extraction allocation failure cleans up" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
test "aggregate_abi_native every emission failure permits same module retry and balanced allocation" {
    var module = try small(t.allocator);
    defer module.deinit();
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        var finished = false;
        for (0..1024) |failure| {
            var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = failure, .resize_fail_index = 0 });
            if (amd64.emitWithOptions(failing.allocator(), &module, options)) |assembly| {
                failing.allocator().free(assembly);
                finished = true;
            } else |err| {
                try t.expectEqual(error.OutOfMemory, err);
                failing.fail_index = std.math.maxInt(usize);
                const retry = try amd64.emitWithOptions(failing.allocator(), &module, options);
                failing.allocator().free(retry);
            }
            try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
            try t.expectEqual(@as(u64, 17), module.types.items[0].size);
            if (finished) break;
        }
        try t.expect(finished);
    }
}
test "aggregate_abi_native fixture validates every site and interpreter guards stay independent" {
    var module = try parse(t.allocator, fixture);
    defer module.deinit();
    var plans = try planner.ModulePlans.init(t.allocator, &module, .{});
    defer plans.deinit();
    try t.expectEqual(module.functions.items.len, plans.functions.len);
    // Source hashes and C/assembly runtime expectations are checked separately.
    for (module.functions.items, 0..) |function, i| {
        if (function.hasRecordSignature()) try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluateModule(t.allocator, &module, @fromBackingInt(@as(u32, @intCast(i))), &.{}, .{}));
    }
}

test "aggregate_abi_native actual frame reserves and probes bounded private pads and rejects excess" {
    for ([_]usize{ 15, 16 }) |count| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(t.allocator);
        try text.appendSlice(t.allocator, "type :Big={b 4096}\nfunction $pads(){\n@e\n");
        for (0..count) |i| {
            const line = try std.fmt.allocPrint(t.allocator, "%r{d} =:Big call $external()\n", .{i});
            defer t.allocator.free(line);
            try text.appendSlice(t.allocator, line);
        }
        try text.appendSlice(t.allocator, "ret\n}");
        var module = try parse(t.allocator, text.items);
        defer module.deinit();
        for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
            if (count == 16) {
                try t.expectError(error.FrameTooLarge, amd64.emitWithOptions(t.allocator, &module, options));
            } else {
                const assembly = try amd64.emitWithOptions(t.allocator, &module, options);
                defer t.allocator.free(assembly);
                // Fifteen distinct 4096-byte return pads need at least 61440
                // bytes plus homes. Actual emitter must probe sixteen pages,
                // including its final partial reservation, not merely plan it.
                try t.expectEqual(@as(usize, 16), std.mem.count(u8, assembly, "testb $0, (%rsp)"));
                try t.expectEqual(count, std.mem.count(u8, assembly, "call external"));
            }
        }
    }
}
