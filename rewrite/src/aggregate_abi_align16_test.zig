const std = @import("std");
const t = std.testing;
const frontend = @import("frontend.zig");
const Module = @import("module.zig").Module;
const planner = @import("abi_amd64_plan.zig");
const amd64 = @import("amd64.zig");
const interpreter = @import("interpreter.zig");
const abi = @import("abi_amd64.zig");
fn parse(a: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return frontend.parse(a, .{ .name = "aggregate_abi_align16", .text = text }, &diagnostic);
}
fn id(n: u32) @import("module.zig").FunctionId {
    return @fromBackingInt(n);
}
test "aggregate_abi_align16 literal classes active offsets and complete declared storage" {
    const fields = [_][]const u8{ "b", "w,s", "l", "s", "d", "s 2", "s 3", "d 2", "s,l", "l,s", "l 2", ":Child" };
    const classes = [_][]const u8{ "I", "I", "I", "S", "S", "S", "SS", "SS", "SI", "IS", "II", "S" };
    for (fields, classes) |field, expected| {
        const text = try std.fmt.allocPrint(t.allocator, "type :Child=align 16 {{s}}\ntype :T=align 16 {{{s}}}\nfunction :T $f(:T %p){{\n@e\nret %p\n}}", .{field});
        defer t.allocator.free(text);
        var m = try parse(t.allocator, text);
        defer m.deinit();
        var p = try planner.FunctionPlan.init(t.allocator, &m, id(0), .{});
        defer p.deinit();
        const r = p.signature.result.register_record;
        try t.expectEqual(@as(u64, 16), r.declared_bytes);
        try t.expectEqual(@as(u8, 16), r.alignment);
        try t.expectEqual(expected.len, r.lane_count);
        try t.expectEqual(@as(u64, 16), p.parameter_objects[0].declared_bytes);
        try t.expectEqual(@as(u8, 16), p.parameter_objects[0].alignment);
        try t.expectEqual(@as(u64, 0), p.parameter_objects[0].end % 16);
        var gp: usize = 0;
        var fp: usize = 0;
        for (expected, 0..) |c, n| {
            try t.expectEqual(@as(u8, @intCast(n * 8)), r.lanes[n].offset);
            try t.expectEqual(@as(u8, 8), r.lanes[n].bytes);
            const arg = p.signature.arguments[0].location.register_record.lanes[n];
            if (c == 'I') {
                try t.expectEqual(if (gp == 0) planner.ResultGeneral.rax else .rdx, r.lanes[n].register.general);
                try t.expectEqual(if (gp == 0) abi.General.rdi else .rsi, arg.register.general);
                gp += 1;
            } else {
                try t.expectEqual(if (fp == 0) planner.ResultVector.xmm0 else .xmm1, r.lanes[n].register.vector);
                try t.expectEqual(if (fp == 0) abi.Vector.xmm0 else .xmm1, arg.register.vector);
                fp += 1;
            }
        }
        try t.expectEqual(@as(u8, @intCast(gp)), p.signature.general_used);
        try t.expectEqual(@as(u8, @intCast(fp)), p.signature.vector_used);
        const assembly = try amd64.emit(t.allocator, &m);
        defer t.allocator.free(assembly);
        if (expected.len == 1) try t.expect(std.mem.indexOf(u8, assembly, "8(%r11)") == null);
    }
}
const owned = "type :A=align 16 {s}\ntype :B=align 16 {l,s}\nfunction :A $f(:A %a,:B %b){\n@e\n%x =:A call $one(:A %a,:B %b)\n%y =:B call $two(:B %b)\nret %x\n}\nfunction w $gap(){\n@e\nret 1\n}\nfunction :B $g(:B %b){\n@e\n%x =:B call $other(:B %b)\nret %x\n}";
fn exercise(a: std.mem.Allocator) !void {
    var m = try parse(a, owned);
    defer m.deinit();
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |o| {
        const text = try amd64.emitWithOptions(a, &m, o);
        a.free(text);
    }
}
test "aggregate_abi_align16 exhaustive parse module plans incoming objects pads writer failure cleanup" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
test "aggregate_abi_align16 same module every writer allocation OOM permits exact balanced retry" {
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
test "aggregate_abi_align16 exact stack alignment 48 outgoing with untouched SSE bank" {
    var m = try parse(t.allocator, "type :T=align 16 {w}\nfunction :T $f(l %a,l %b,l %c,l %d,l %e,l %f,l %spill,:T %t,l %after,d %fp){\n@e\nret %t\n}");
    defer m.deinit();
    var p = try planner.FunctionPlan.init(t.allocator, &m, id(0), .{});
    defer p.deinit();
    try t.expectEqual(@as(u64, 0), p.signature.arguments[6].location.stack.offset);
    const s = p.signature.arguments[7].location.stack;
    try t.expectEqual(@as(u64, 16), s.offset);
    try t.expectEqual(@as(u64, 16), s.extent);
    try t.expectEqual(@as(u8, 16), s.alignment);
    try t.expectEqual(@as(i32, 32), s.incoming);
    try t.expectEqual(@as(u64, 32), p.signature.arguments[8].location.stack.offset);
    try t.expectEqual(abi.Vector.xmm0, p.signature.arguments[9].location.vector);
    try t.expectEqual(@as(u64, 48), p.signature.outgoing_bytes);
}
test "aggregate_abi_align16 NO_CLASS neither bank consumed following scalars and whole tuple rollback" {
    for ([_][]const u8{ "type :T=align 16 {b}\nfunction :T $f(l %a,l %b,l %c,l %d,l %e,:T %t,l %after,d %fp){\n@e\nret %t\n}", "type :T=align 16 {s}\nfunction :T $f(d %a,d %b,d %c,d %d,d %e,d %f,d %g,:T %t,d %after,l %gp){\n@e\nret %t\n}" }, 0..) |text, i| {
        var m = try parse(t.allocator, text);
        defer m.deinit();
        var p = try planner.FunctionPlan.init(t.allocator, &m, id(0), .{});
        defer p.deinit();
        if (i == 0) {
            try t.expectEqual(abi.General.r9, p.signature.arguments[5].location.register_record.lanes[0].register.general);
            try t.expectEqual(@as(u64, 0), p.signature.arguments[6].location.stack.offset);
            try t.expectEqual(abi.Vector.xmm0, p.signature.arguments[7].location.vector);
        } else {
            try t.expectEqual(abi.Vector.xmm7, p.signature.arguments[7].location.register_record.lanes[0].register.vector);
            try t.expectEqual(@as(u64, 0), p.signature.arguments[8].location.stack.offset);
            try t.expectEqual(abi.General.rdi, p.signature.arguments[9].location.general);
        }
    }
}
test "aggregate_abi_align16 detached owned facts no stale unused layout permission and interpreter refusal" {
    const text = try t.allocator.dupe(u8, owned);
    defer t.allocator.free(text);
    var m = try parse(t.allocator, text);
    @memset(text, 0xa5);
    var plans = try planner.ModulePlans.init(t.allocator, &m, .{});
    defer plans.deinit();
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluateModule(t.allocator, &m, id(0), &.{}, .{ .max_call_depth = 0 }));
    m.types.items[0].alignment = 8;
    try t.expectError(error.InvalidRecordLayout, amd64.emit(t.allocator, &m));
    m.deinit();
    const p = plans.get(0).?;
    try t.expectEqual(@as(u64, 16), p.pads[0].declared_bytes);
    try t.expectEqual(@as(u8, 16), p.pads[0].alignment);
    try t.expectEqual(@as(u8, 1), p.signature.result.register_record.lane_count);
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
test "aggregate_abi_align16 mixed prefix suffix reference establishes exact symbol IDs and function ordinals" {
    for ([_]bool{ false, true }) |prefix| {
        const text = try movedSide(t.allocator, @embedFile("fixtures/aggregate_abi_align16_mixed.ssa"), prefix);
        defer t.allocator.free(text);
        const other = try movedSide(t.allocator, @embedFile("fixtures/aggregate_abi_align16_scalar_reference.ssa"), prefix);
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
test "aggregate_abi_align16 literal65536 frame includes full16 incoming object and2729 pads" {
    for ([_]usize{ 2729, 2730 }) |count| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(t.allocator);
        try text.appendSlice(t.allocator, "type :T=align 16 {s}\nfunction $f(:T %p,l %a,l %b){\n@e\n");
        for (0..count) |n| {
            const line = try std.fmt.allocPrint(t.allocator, "%r{d} =:T call $external()\n", .{n});
            defer t.allocator.free(line);
            try text.appendSlice(t.allocator, line);
        }
        try text.appendSlice(t.allocator, "ret\n}");
        var m = try parse(t.allocator, text.items);
        defer m.deinit();
        if (count == 2730) try t.expectError(error.FrameTooLarge, amd64.emit(t.allocator, &m)) else {
            var p = try planner.FunctionPlan.init(t.allocator, &m, id(0), .{});
            defer p.deinit();
            // 2732 homes *8=21856 +incoming16 +2729 pads*16=65536.
            try t.expectEqual(@as(u64, 21872), p.parameter_objects[0].end);
            try t.expectEqual(@as(u64, 21888), p.pads[0].end);
            try t.expectEqual(@as(u64, 65536), p.pads[2728].end);
            try t.expectEqual(@as(u64, 65536), p.frame.bytes);
            const a = try amd64.emit(t.allocator, &m);
            defer t.allocator.free(a);
            try t.expectEqual(@as(usize, 16), std.mem.count(u8, a, "testb $0, (%rsp)"));
        }
    }
}
test "aggregate_abi_align16 max4096 compact DAG and UINT64MAX unused metadata remain bounded owned facts" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(t.allocator);
    try text.appendSlice(t.allocator, "type :A={b 2147483647}\ntype :B={:A 2147483647}\ntype :Huge={:B 4,:A 8,b 3}\ntype :T0=align 16 {s}\n");
    for (1..4093) |n| {
        const line = try std.fmt.allocPrint(t.allocator, "type :T{d}={{:T{d}}}\n", .{ n, n - 1 });
        defer t.allocator.free(line);
        try text.appendSlice(t.allocator, line);
    }
    try text.appendSlice(t.allocator, "function :T4092 $f(:T4092 %p){\n@e\nret %p\n}");
    var m = try parse(t.allocator, text.items);
    var p = planner.FunctionPlan.init(t.allocator, &m, id(0), .{}) catch |err| {
        m.deinit();
        return err;
    };
    defer p.deinit();
    try t.expectEqual(@as(usize, 4096), m.types.items.len);
    try t.expectEqual(std.math.maxInt(u64), m.types.items[2].size);
    @memset(text.items, 0xa5);
    const output = try amd64.emit(t.allocator, &m);
    defer t.allocator.free(output);
    m.deinit();
    try t.expectEqual(@as(u8, 1), p.signature.result.register_record.lane_count);
    try t.expectEqual(@as(u8, 16), p.signature.result.register_record.alignment);
    try t.expectEqual(@as(u64, 16), p.parameter_objects[0].declared_bytes);
}
test "aggregate_abi_align16 independent32prefix 16object two16pads outgoing48 frame128" {
    var m = try parse(t.allocator, "type :T=align 16 {w}\nfunction :T $f(:T %p){\n@e\n%a =:T call $external(l 1,l 2,l 3,l 4,l 5,l 6,l 7,:T %p,l 99,d d_0)\n%b =:T call $other()\nret %b\n}");
    defer m.deinit();
    var p = try planner.FunctionPlan.init(t.allocator, &m, id(0), .{});
    defer p.deinit();
    try t.expectEqual(@as(u64, 48), p.parameter_objects[0].end);
    try t.expectEqual(@as(u64, 64), p.pads[0].end);
    try t.expectEqual(@as(u64, 80), p.pads[1].end);
    try t.expectEqual(@as(u64, 48), p.frame.outgoing_bytes);
    try t.expectEqual(@as(u64, 128), p.frame.bytes);
}
