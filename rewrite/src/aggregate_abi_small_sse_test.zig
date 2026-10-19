const std = @import("std");
const t = std.testing;
const Module = @import("module.zig").Module;
const frontend = @import("frontend.zig");
const planner = @import("abi_amd64_plan.zig");
const amd64 = @import("amd64.zig");
const interpreter = @import("interpreter.zig");
const abi = @import("abi_amd64.zig");
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "aggregate_abi_small_sse", .text = text }, &diagnostic);
}
fn id(n: u32) @import("module.zig").FunctionId {
    return @fromBackingInt(n);
}
const Case = struct { fields: []const u8, size: u64, classes: []const u8 };
const cases = [_]Case{
    .{ .fields = "s", .size = 4, .classes = "S" },
    .{ .fields = "s 2", .size = 8, .classes = "S" },
    .{ .fields = "s 3", .size = 12, .classes = "SS" },
    .{ .fields = "d 2", .size = 16, .classes = "SS" },
    .{ .fields = "w,s", .size = 8, .classes = "I" },
    .{ .fields = "s,l", .size = 16, .classes = "SI" },
    .{ .fields = "l,s", .size = 16, .classes = "IS" },
    .{ .fields = "s,:QIS", .size = 12, .classes = "IS" },
    .{ .fields = "s,:QSI", .size = 12, .classes = "SI" },
    .{ .fields = ":Child 2", .size = 16, .classes = "SS" },
};
test "aggregate_abi_small_sse exact literal classes packed floats dominance and BOTH shifted child directions" {
    for (cases) |case| {
        const text = try std.fmt.allocPrint(t.allocator, "type :QIS={{w,s}}\ntype :QSI={{s,w}}\ntype :Child={{s 2}}\ntype :T={{{s}}}\nfunction :T $f(:T %p){{\n@e\nret %p\n}}", .{case.fields});
        defer t.allocator.free(text);
        var module = try parse(t.allocator, text);
        defer module.deinit();
        var plan = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
        defer plan.deinit();
        try t.expectEqual(case.size, module.types.items[3].size);
        try t.expect(plan.frame.hidden_return_end == null);
        if (std.mem.indexOfScalar(u8, case.classes, 'S') == null) {
            try t.expect(plan.signature.result == .integer_record);
            try t.expect(plan.signature.arguments[0].location == .integer_record);
            continue;
        }
        const result = plan.signature.result.register_record;
        const argument = plan.signature.arguments[0].location.register_record;
        try t.expectEqual(case.size, result.declared_bytes);
        try t.expectEqual(case.classes.len, @as(usize, result.lane_count));
        try t.expectEqual(case.classes.len, @as(usize, argument.lane_count));
        var gp: u8 = 0;
        var sse: u8 = 0;
        for (case.classes, 0..) |class, lane| {
            const returned = result.lanes[lane];
            const incoming = argument.lanes[lane];
            const width: u8 = @intCast(@min(8, case.size - lane * 8));
            try t.expectEqual(@as(u8, @intCast(lane * 8)), returned.offset);
            try t.expectEqual(width, returned.bytes);
            try t.expectEqual(width, incoming.bytes);
            if (class == 'I') {
                try t.expectEqual(planner.ResultGeneral.rax, returned.register.general); // mixed record's FIRST integer, even in lane1
                try t.expectEqual(abi.General.rdi, incoming.register.general);
                gp += 1;
            } else {
                try t.expectEqual(if (sse == 0) planner.ResultVector.xmm0 else .xmm1, returned.register.vector);
                try t.expectEqual(if (sse == 0) abi.Vector.xmm0 else .xmm1, incoming.register.vector);
                sse += 1;
            }
        }
        try t.expectEqual(gp, plan.signature.general_used);
        try t.expectEqual(sse, plan.signature.vector_used);
        const assembly = try amd64.emit(t.allocator, &module);
        defer t.allocator.free(assembly);
        try t.expect(std.mem.indexOf(u8, assembly, "cvt") == null);
        if (case.size == 4) try t.expect(std.mem.indexOf(u8, assembly, "movd 0(%r11), %xmm0") != null);
        if (case.size == 12 and case.classes[1] == 'S') try t.expect(std.mem.indexOf(u8, assembly, "movd 8(%r11), %xmm") != null);
    }
}
fn params(allocator: std.mem.Allocator, longs: usize, doubles: usize, tail: []const u8) ![]u8 {
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(allocator);
    for (0..longs) |n| {
        const line = try std.fmt.allocPrint(allocator, "l %l{d},", .{n});
        defer allocator.free(line);
        try text.appendSlice(allocator, line);
    }
    for (0..doubles) |n| {
        const line = try std.fmt.allocPrint(allocator, "d %d{d},", .{n});
        defer allocator.free(line);
        try text.appendSlice(allocator, line);
    }
    try text.appendSlice(allocator, tail);
    return text.toOwnedSlice(allocator);
}
test "aggregate_abi_small_sse literal BOTH bank rollback stack offsets result banks and hidden RDI" {
    for ([_]bool{ false, true }) |hidden| {
        for (0..3) |variant| {
            const longs: usize = (if (variant == 0) @as(usize, 6) else 5) - @intFromBool(hidden);
            const doubles: usize = if (variant == 1) 8 else 7;
            const tail = switch (variant) {
                0 => ":M %m,d %after,d %spill",
                1 => ":M %m,l %after,:B %b,d %spill",
                else => ":M %m,l %after,d %spill",
            };
            const arguments = try params(t.allocator, longs, doubles, tail);
            defer t.allocator.free(arguments);
            const text = try std.fmt.allocPrint(t.allocator, "type :M={{l,s}}\ntype :B={{b}}\ntype :Big={{b 17}}\nfunction {s} $f({s}){{\n@e\nret 0\n}}", .{ if (hidden) @as([]const u8, ":Big") else ":M", arguments });
            defer t.allocator.free(text);
            var module = try parse(t.allocator, text);
            defer module.deinit();
            var plan = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
            defer plan.deinit();
            const a = plan.signature.arguments;
            const mixed = longs + doubles;
            try t.expectEqual(@as(u64, if (variant == 2) 16 else 32), plan.signature.outgoing_bytes);
            if (hidden) try t.expect(plan.frame.hidden_return_end != null) else try t.expect(plan.signature.result == .register_record);
            if (variant == 0) {
                try t.expectEqual(@as(u64, 0), a[mixed].location.stack.offset);
                try t.expectEqual(abi.Vector.xmm7, a[mixed + 1].location.vector);
                try t.expectEqual(@as(u64, 16), a[mixed + 2].location.stack.offset);
            } else if (variant == 1) {
                try t.expectEqual(@as(u64, 0), a[mixed].location.stack.offset);
                try t.expectEqual(abi.General.r9, a[mixed + 1].location.general);
                try t.expectEqual(@as(u64, 16), a[mixed + 2].location.stack.offset);
                try t.expectEqual(@as(u64, 24), a[mixed + 3].location.stack.offset);
            } else {
                const tuple = a[mixed].location.register_record;
                try t.expectEqual(abi.General.r9, tuple.lanes[0].register.general);
                try t.expectEqual(abi.Vector.xmm7, tuple.lanes[1].register.vector);
                try t.expectEqual(@as(u64, 0), a[mixed + 1].location.stack.offset);
                try t.expectEqual(@as(u64, 8), a[mixed + 2].location.stack.offset);
            }
        }
    }
    const arguments = try params(t.allocator, 0, 7, ":SS %m,d %after");
    defer t.allocator.free(arguments);
    const text = try std.fmt.allocPrint(t.allocator, "type :SS={{s 3}}\nfunction :SS $f({s}){{\n@e\nret %m\n}}", .{arguments});
    defer t.allocator.free(text);
    var module = try parse(t.allocator, text);
    defer module.deinit();
    var plan = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
    defer plan.deinit();
    try t.expectEqual(@as(u64, 0), plan.signature.arguments[7].location.stack.offset);
    try t.expectEqual(abi.Vector.xmm7, plan.signature.arguments[8].location.vector);
}
const owned = "type :T={s 3}\ntype :B={s}\nfunction :T $f(:T %p,:B %b){\n@e\n%r =:T call $external(:T %p,:B %b)\nret %r\n}\nfunction w $gap(){\n@e\nret 7\n}\nfunction :B $g(:B %p){\n@e\n%r =:B call $outside(:B %p)\nret %r\n}";
test "aggregate_abi_small_sse owned private incoming objects pads and detached snapshots validate fresh data" {
    const text = try t.allocator.dupe(u8, owned);
    defer t.allocator.free(text);
    var module = try parse(t.allocator, text);
    @memset(text, 0xa5);
    var plans = planner.ModulePlans.init(t.allocator, &module, .{}) catch |err| {
        module.deinit();
        return err;
    };
    defer plans.deinit();
    const plan = plans.get(0).?;
    try t.expect(plans.get(1) == null);
    try t.expectEqual(@as(u64, 48), plan.parameter_objects[0].end);
    try t.expectEqual(@as(u64, 56), plan.parameter_objects[1].end);
    try t.expectEqual(@as(u64, 72), plan.pads[0].end);
    try t.expectEqual(@as(u64, 80), plan.frame.bytes);
    module.types.items[0].runs[0].stride += 1;
    try t.expectError(error.InvalidRecordLayout, amd64.emit(t.allocator, &module));
    module.deinit();
    try t.expectEqual(@as(u64, 12), plan.signature.result.register_record.declared_bytes);
    try t.expectEqual(planner.ResultVector.xmm1, plan.signature.result.register_record.lanes[1].register.vector);
    try t.expectEqual(@as(u64, 4), plans.get(2).?.pads[0].declared_bytes);
}
fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, owned);
    defer module.deinit();
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(allocator, &module, options);
        allocator.free(assembly);
    }
}
test "aggregate_abi_small_sse exhaustive multi-function parser plan objects home writer allocations clean every failure" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
test "aggregate_abi_small_sse every emission OOM permits same module retry and exact cleanup" {
    var module = try parse(t.allocator, owned);
    defer module.deinit();
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        var finished = false;
        for (0..2048) |failure| {
            var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = failure, .resize_fail_index = 0 });
            if (amd64.emitWithOptions(failing.allocator(), &module, options)) |output| {
                failing.allocator().free(output);
                finished = true;
            } else |err| {
                try t.expectEqual(error.OutOfMemory, err);
                failing.fail_index = std.math.maxInt(usize);
                const retry = try amd64.emitWithOptions(failing.allocator(), &module, options);
                failing.allocator().free(retry);
            }
            try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
            if (finished) break;
        }
        try t.expect(finished);
    }
}
test "aggregate_abi_small_sse retained interpreter guards and unsupported site refusals do not become execution" {
    var module = try parse(t.allocator, owned);
    defer module.deinit();
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluate(t.allocator, module.functions.items[0], &.{}, .{ .max_call_depth = 0 }));
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluateModule(t.allocator, &module, id(0), &.{}, .{ .max_call_depth = 0, .internal_variadic_calls = true }));
    for ([_][]const u8{ "type :T=align 16 {s}\nfunction :T $f(l %p){\n@e\nret %p\n}", "type :T={s}\nfunction :T $f(env %e,l %p){\n@e\nret %p\n}", "type :T={s}\nfunction :T $f(l %p,...){\n@e\nret %p\n}", "type :T={s}\nfunction $f(){\n@e\ncall 0(:T 0)\nret\n}" }) |text| {
        var rejected = try parse(t.allocator, text);
        defer rejected.deinit();
        try t.expectError(error.UnsupportedAggregateAbi, amd64.emit(t.allocator, &rejected));
    }
    var caller = try parse(t.allocator, "type :T={s}\nfunction $f(){\n@e\ncall $missing(:T $absent)\nret\n}");
    defer caller.deinit();
    try t.expectError(error.StepLimitExceeded, interpreter.evaluate(t.allocator, caller.functions.items[0], &.{}, .{ .max_steps = 0 }));
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluate(t.allocator, caller.functions.items[0], &.{}, .{ .max_steps = 1 }));
}

test "aggregate_abi_small_sse compact deep child masks and huge unused layouts do not expand or retain source" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(t.allocator);
    try text.appendSlice(t.allocator, "type :A={b 2147483647}\ntype :B={:A 2147483647}\ntype :Huge={:B 4,:A 8,b 3}\ntype :Q={w,s}\ntype :T0={s,:Q}\n");
    for (1..256) |n| {
        const line = try std.fmt.allocPrint(t.allocator, "type :T{d}={{:T{d}}}\n", .{ n, n - 1 });
        defer t.allocator.free(line);
        try text.appendSlice(t.allocator, line);
    }
    try text.appendSlice(t.allocator, "function :T255 $f(:T255 %p){\n@e\nret %p\n}");
    var module = try parse(t.allocator, text.items);
    defer module.deinit();
    try t.expectEqual(std.math.maxInt(u64), module.types.items[2].size);
    var plan = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
    defer plan.deinit();
    const result = plan.signature.result.register_record;
    try t.expectEqual(@as(u64, 12), result.declared_bytes);
    try t.expectEqual(planner.ResultGeneral.rax, result.lanes[0].register.general);
    try t.expectEqual(planner.ResultVector.xmm0, result.lanes[1].register.vector);
    try t.expectEqual(@as(u8, 4), result.lanes[1].bytes);
    const assembly = try amd64.emit(t.allocator, &module);
    defer t.allocator.free(assembly);
    try t.expect(std.mem.indexOf(u8, assembly, "movd 8(%r11), %xmm0") != null);
}
test "aggregate_abi_small_sse exact 64KiB includes incoming object and distinct SSE result pads" {
    for ([_]usize{ 4095, 4096 }) |count| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(t.allocator);
        try text.appendSlice(t.allocator, "type :T={s}\nfunction $f(:T %p){\n@e\n");
        for (0..count) |n| {
            const line = try std.fmt.allocPrint(t.allocator, "%r{d} =:T call $external()\n", .{n});
            defer t.allocator.free(line);
            try text.appendSlice(t.allocator, line);
        }
        try text.appendSlice(t.allocator, "ret\n}");
        var module = try parse(t.allocator, text.items);
        defer module.deinit();
        if (count == 4096) try t.expectError(error.FrameTooLarge, amd64.emit(t.allocator, &module)) else {
            var plan = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
            defer plan.deinit();
            // Literal default layout:4096 pointer homes32768 +one incoming
            // object8 +4095 noncoalescing result objects32760 =65536.
            try t.expectEqual(@as(u64, 32776), plan.parameter_objects[0].end);
            try t.expectEqual(@as(u64, 32784), plan.pads[0].end);
            try t.expectEqual(@as(u64, 65536), plan.pads[4094].end);
            try t.expectEqual(@as(u64, 65536), plan.frame.bytes);
            const assembly = try amd64.emit(t.allocator, &module);
            defer t.allocator.free(assembly);
            try t.expectEqual(@as(usize, 16), std.mem.count(u8, assembly, "testb $0, (%rsp)"));
            try t.expectEqual(count, std.mem.count(u8, assembly, "call external"));
        }
    }
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
test "aggregate_abi_small_sse mixed prefix suffix reference establishes exact symbol IDs and function ordinals" {
    for ([_]bool{ false, true }) |prefix| {
        const text = try movedSide(t.allocator, @embedFile("fixtures/aggregate_abi_small_sse_mixed.ssa"), prefix);
        defer t.allocator.free(text);
        const other = try movedSide(t.allocator, @embedFile("fixtures/aggregate_abi_small_sse_scalar_reference.ssa"), prefix);
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
