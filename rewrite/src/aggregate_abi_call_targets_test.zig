const std = @import("std");
const t = std.testing;
const Module = @import("module.zig").Module;
const frontend = @import("frontend.zig");
const planner = @import("abi_amd64_plan.zig");
const amd64 = @import("amd64.zig");
const interpreter = @import("interpreter.zig");
fn id(n: u32) @import("module.zig").FunctionId {
    return @fromBackingInt(n);
}
fn parse(a: std.mem.Allocator, text: []const u8) !Module {
    var d: ?@import("source.zig").Diagnostic = null;
    return frontend.parse(a, .{ .name = "aggregate_abi_call_targets", .text = text }, &d);
}
const owned = "type :S=align 16 {s}\ntype :M={b 23}\nfunction :M $f(env %e,l %fn,:S %s,:M %m){\n@e\n%a =:M call %fn(env %e,:S %s,:M %m)\nret %a\n}\nfunction w $gap(){\n@e\nret 1\n}\nfunction :S $g(env %e,:S %p){\n@e\n%a =:S call $outside(env %e,:S %p)\nret %a\n}";
test "aggregate_abi_call_targets typed nonvariadic env indirect metadata uses unchanged banks and full objects" {
    var m = try parse(t.allocator, owned);
    defer m.deinit();
    var plans = try planner.ModulePlans.init(t.allocator, &m, .{});
    defer plans.deinit();
    const p = plans.get(0).?;
    try t.expect(p.signature.environment and !p.signature.variadic);
    try t.expectEqual(@as(usize, 3), p.signature.arguments.len);
    try t.expect(p.signature.result == .memory);
    try t.expect(p.frame.hidden_return_end != null);
    try t.expectEqual(@as(u8, 2), p.signature.general_used);
    try t.expectEqual(@as(u8, 1), p.signature.vector_used);
    const site = p.calls[0];
    try t.expect(site.target == .address);
    try t.expect(site.signature.environment);
    try t.expect(site.signature.result == .memory);
    try t.expectEqual(@as(u8, 1), site.signature.general_used);
    try t.expectEqual(@as(u8, 1), site.signature.vector_used);
    try t.expectEqual(@as(u64, 32), site.signature.outgoing_bytes);
    try t.expectEqual(@as(u64, 23), p.pads[0].declared_bytes);
    try t.expectEqual(@as(u64, 16), p.parameter_objects[0].declared_bytes);
    try t.expect(plans.get(1) == null);
    const output = try amd64.emit(t.allocator, &m);
    defer t.allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "call *%r11") != null);
}
fn exercise(a: std.mem.Allocator) !void {
    var m = try parse(a, owned);
    defer m.deinit();
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |o| {
        const text = try amd64.emitWithOptions(a, &m, o);
        a.free(text);
    }
}
test "aggregate_abi_call_targets exhaustive multiple plan env home copy pad writer OOM cleans partial ownership" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
test "aggregate_abi_call_targets each emission failure allows same module retry and exact balance" {
    var m = try parse(t.allocator, owned);
    defer m.deinit();
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |o| {
        var finished = false;
        for (0..2048) |n| {
            var f = t.FailingAllocator.init(t.allocator, .{ .fail_index = n, .resize_fail_index = 0 });
            if (amd64.emitWithOptions(f.allocator(), &m, o)) |a| {
                f.allocator().free(a);
                finished = true;
            } else |err| {
                try t.expectEqual(error.OutOfMemory, err);
                f.fail_index = std.math.maxInt(usize);
                const retry = try amd64.emitWithOptions(f.allocator(), &m, o);
                f.allocator().free(retry);
            }
            try t.expectEqual(f.allocated_bytes, f.freed_bytes);
            if (finished) break;
        }
        try t.expect(finished);
    }
}
test "aggregate_abi_call_targets snapshots detached from source module and unused tamper cannot authorize emission" {
    const text = try t.allocator.dupe(u8, owned);
    defer t.allocator.free(text);
    var m = try parse(t.allocator, text);
    @memset(text, 0xa5);
    var p = planner.FunctionPlan.init(t.allocator, &m, id(0), .{ .callee_saved_homes = true }) catch |err| {
        m.deinit();
        return err;
    };
    defer p.deinit();
    m.types.items[0].runs[0].stride += 1;
    try t.expectError(error.InvalidRecordLayout, amd64.emit(t.allocator, &m));
    m.deinit();
    try t.expect(p.calls[0].target == .address and p.calls[0].signature.environment);
    try t.expectEqual(@as(u64, 23), p.signature.result.memory.declared_bytes);
}
test "aggregate_abi_call_targets unknown indirect IDs validation and known used environment errors stay eager" {
    var m = try parse(t.allocator, owned);
    defer m.deinit();
    const call = &m.functions.items[0].blocks.items[0].instructions.items[0].call;
    @constCast(call.arguments)[0].descriptor = .{ .record = @fromBackingInt(std.math.maxInt(u32)) };
    try t.expectError(error.InvalidAggregateType, amd64.emit(t.allocator, &m));
    var missing = try parse(t.allocator, "type :T={s}\nfunction :T $callee(env %e,:T %p){\n@e\n%use =l copy %e\nret %p\n}\nfunction :T $f(:T %p){\n@e\n%r =:T call $callee(:T %p)\nret %r\n}");
    defer missing.deinit();
    try t.expectError(error.CallSignatureMismatch, amd64.emit(t.allocator, &missing));
}
test "aggregate_abi_call_targets aggregate interpreter guards retain root and reached step priority" {
    var m = try parse(t.allocator, owned);
    defer m.deinit();
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluate(t.allocator, m.functions.items[0], &.{}, .{ .max_call_depth = 0, .environment = 7 }));
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluateModule(t.allocator, &m, id(0), &.{}, .{ .max_call_depth = 0, .environment = 7, .internal_variadic_calls = true }));
    var caller = try parse(t.allocator, "type :T={s}\nfunction $f(){\n@e\ncall 0(env $missing,:T $absent)\nret\n}");
    defer caller.deinit();
    try t.expectError(error.StepLimitExceeded, interpreter.evaluate(t.allocator, caller.functions.items[0], &.{}, .{ .max_steps = 0 }));
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluate(t.allocator, caller.functions.items[0], &.{}, .{ .max_steps = 1 }));
}

fn movedSide(allocator: std.mem.Allocator, text: []const u8, prefix: bool) ![]u8 {
    if (!prefix) return allocator.dupe(u8, text);
    const first = std.mem.indexOf(u8, text, "export function ").?;
    const side = std.mem.indexOf(u8, text, "\nfunction ").? + 1;
    return std.mem.concat(allocator, u8, &.{ text[0..first], text[side..], text[first..side] });
}
fn fragment(assembly: []const u8, name: []const u8) []const u8 {
    var h: [128]u8 = undefined;
    var q: [128]u8 = undefined;
    const head = std.fmt.bufPrint(&h, ".globl {s}\n.type {s}, @function\n", .{ name, name }) catch unreachable;
    const tail = std.fmt.bufPrint(&q, ".size {s}, .-{s}\n", .{ name, name }) catch unreachable;
    const start = std.mem.indexOf(u8, assembly, head).?;
    return assembly[start .. start + std.mem.indexOf(u8, assembly[start..], tail).? + tail.len];
}
test "aggregate_abi_call_targets mixed prefix suffix reference establishes exact symbol IDs and function ordinals" {
    for ([_]bool{ false, true }) |prefix| {
        const text = try movedSide(t.allocator, @embedFile("fixtures/aggregate_abi_call_targets_mixed.ssa"), prefix);
        defer t.allocator.free(text);
        const other = try movedSide(t.allocator, @embedFile("fixtures/aggregate_abi_call_targets_scalar_reference.ssa"), prefix);
        defer t.allocator.free(other);
        var module = try parse(t.allocator, text);
        defer module.deinit();
        var reference = try parse(t.allocator, other);
        defer reference.deinit();
        try t.expectEqual(reference.symbols.names.items.len, module.symbols.names.items.len);
        for (reference.symbols.names.items, module.symbols.names.items) |a, b| try t.expectEqualStrings(a, b);
        try t.expectEqual(reference.functions.items.len, module.functions.items.len);
        for (reference.functions.items, module.functions.items, 0..) |a, b, n| {
            try t.expectEqual(a.name, b.name);
            try t.expect(reference.getFunction(id(@intCast(n))).? == a and module.getFunction(id(@intCast(n))).? == b);
            if (n == (if (prefix) @as(usize, 0) else 4)) {
                try t.expect(!a.hasRecordSignature() and b.hasRecordSignature());
            } else try t.expect(!a.hasRecordSignature() and !b.hasRecordSignature());
        }
        for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
            const a = try amd64.emitWithOptions(t.allocator, &module, options);
            defer t.allocator.free(a);
            const b = try amd64.emitWithOptions(t.allocator, &reference, options);
            defer t.allocator.free(b);
            for ([_][]const u8{ "common_address", "ordinary_address", "external_address", "T" }) |symbol| try t.expectEqualSlices(u8, fragment(a, symbol), fragment(b, symbol));
        }
    }
}
