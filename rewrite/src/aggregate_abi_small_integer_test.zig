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
    return frontend.parse(allocator, .{ .name = "aggregate_abi_small_integer", .text = text }, &diagnostic);
}
fn id(n: u32) @import("module.zig").FunctionId {
    return @fromBackingInt(n);
}
const small = "type :A={b 9}\ntype :B={b}\nfunction :A $f(:A %a,:B %b){\n@e\n%r =:A call $external(:A %a,:B %b)\nret %r\n}\nfunction w $scalar(){\n@e\nret 7\n}\nfunction :B $g(:B %a){\n@e\n%r =:B call $outside(:B %a)\nret %r\n}";
fn tuple(arg: planner.Argument, first: abi.General, second: ?abi.General, bytes: [2]u8) !void {
    try t.expect(arg.descriptor == .record);
    try t.expect(arg.location == .integer_record);
    const value = arg.location.integer_record;
    try t.expectEqual(first, value.registers[0]);
    try t.expectEqual(@as(u8, if (second != null) 2 else 1), value.lane_count);
    if (second) |reg| try t.expectEqual(reg, value.registers[1]);
    try t.expectEqual(bytes, value.lane_bytes);
}
test "aggregate_abi_small_integer nominal tuple plans own distinct parameter and result objects" {
    var module = try parse(t.allocator, small);
    defer module.deinit();
    var plan = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
    defer plan.deinit();
    try t.expect(plan.signature.result == .integer_record);
    try t.expectEqual(@as(u64, 9), plan.signature.result.integer_record.declared_bytes);
    try tuple(plan.signature.arguments[0], .rdi, .rsi, .{ 8, 1 });
    try tuple(plan.signature.arguments[1], .rdx, null, .{ 1, 0 });
    try t.expect(plan.frame.hidden_return_end == null);
    try t.expectEqual(@as(usize, 2), plan.parameter_objects.len);
    // Literal independent home-prefix32 -> A9 end48 -> B1 end56 -> result end72.
    try t.expectEqual(@as(u64, 48), plan.parameter_objects[0].end);
    try t.expectEqual(@as(u64, 56), plan.parameter_objects[1].end);
    try t.expectEqual(@as(u64, 72), plan.pads[0].end);
    try t.expectEqual(@as(u64, 80), plan.frame.bytes);
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(t.allocator, &module, options);
        defer t.allocator.free(assembly);
        try t.expect(std.mem.indexOf(u8, assembly, "movzbl 8(%r11), %r10d") != null);
        try t.expect(std.mem.indexOf(u8, assembly, "movq %rax, %r11") != null);
        try t.expect(std.mem.indexOf(u8, assembly, "rep movsb") == null); // all tuples fit; no stack/MEMORY copies
    }
}
const args = "l %l0,l %l1,l %l2,l %l3,:A %a,l %after,:B %b,d %d0,d %d1,d %d2,d %d3,d %d4,d %d5,d %d6,d %d7,d %d8";
test "aggregate_abi_small_integer literal32byte hidden result rollback and independent SSE oracles" {
    for ([_][]const u8{ ":M", ":A" }, 0..) |result, variant| {
        const source = try std.fmt.allocPrint(t.allocator, "type :A={{b 9}}\ntype :B={{b}}\ntype :M={{b 17}}\nfunction {s} $f({s}){{\n@e\nret 0\n}}", .{ result, args });
        defer t.allocator.free(source);
        var module = try parse(t.allocator, source);
        defer module.deinit();
        var plan = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
        defer plan.deinit();
        const a = plan.signature.arguments;
        try t.expectEqual(@as(u64, 32), plan.signature.outgoing_bytes);
        if (variant == 0) {
            try t.expect(plan.signature.result == .memory);
            try t.expectEqual(abi.General.rsi, a[0].location.general);
            try t.expectEqual(@as(u64, 0), a[4].location.stack.offset);
            try t.expectEqual(@as(u64, 16), a[4].location.stack.extent);
            try t.expectEqual(abi.General.r9, a[5].location.general); // rollback preserves this register
            try t.expectEqual(@as(u64, 16), a[6].location.stack.offset);
            try t.expectEqual(@as(u64, 24), a[15].location.stack.offset);
        } else {
            try t.expect(plan.signature.result == .integer_record);
            try t.expectEqual(abi.General.rdi, a[0].location.general);
            try tuple(a[4], .r8, .r9, .{ 8, 1 });
            try t.expectEqual(@as(u64, 0), a[5].location.stack.offset);
            try t.expectEqual(@as(u64, 8), a[6].location.stack.offset);
            try t.expectEqual(@as(u64, 16), a[15].location.stack.offset);
        }
        for (0..8) |i| try t.expectEqual(@as(usize, i), @backingInt(a[7 + i].location.vector));
    }
    var module = try parse(t.allocator, "type :A={b 9}\ntype :B={b}\nfunction $f(l %a,l %b,l %c,l %d,l %e,:A %whole,:B %last){\n@e\nret\n}");
    defer module.deinit();
    var plan = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
    defer plan.deinit();
    try t.expect(plan.signature.arguments[5].location == .stack);
    try tuple(plan.signature.arguments[6], .r9, null, .{ 1, 0 });
}
test "aggregate_abi_small_integer old variants and generic metadata remain while SSE positives extend eligibility" {
    for ([_][]const u8{ "s", "d 2", "w,s", "align 16 {l 2}" }, 0..) |fields, index| {
        const declaration = if (index == 3) try std.fmt.allocPrint(t.allocator, "type :T={s}\n", .{fields}) else try std.fmt.allocPrint(t.allocator, "type :T={{{s}}}\n", .{fields});
        defer t.allocator.free(declaration);
        const text = try std.mem.concat(t.allocator, u8, &.{ declaration, "function $f(:T %p){\n@e\nret\n}" });
        defer t.allocator.free(text);
        var module = try parse(t.allocator, text);
        defer module.deinit();
        try @import("module_validation.zig").validate(t.allocator, &module);
        if (index == 3) {
            try t.expectError(error.UnsupportedAggregateAbi, amd64.emit(t.allocator, &module));
        } else {
            // s/d2/w+s are now explicitly positive, with independent runtime
            // and exact INTEGER-dominance oracles in the new SSE harness.
            const output = try amd64.emit(t.allocator, &module);
            defer t.allocator.free(output);
        }
    }
    var module = try parse(t.allocator, "type :Small={b}\ntype :Float={s}\ntype :Over=align 64 {l 2}\ntype :N={h,b}\ntype :Nested={:N 2,l}\nfunction :Nested $f(:Nested %p){\n@e\nret %p\n}");
    defer module.deinit();
    var plan = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
    defer plan.deinit();
    try t.expectEqual(@as(u64, 16), plan.signature.result.integer_record.declared_bytes);
    try tuple(plan.signature.arguments[0], .rdi, .rsi, .{ 8, 8 });
    for ([_][]const u8{ "function $f(env %e,:T %p){\n@e\nret\n}", "function $f(:T %p,...){\n@e\nret\n}", "function $f(){\n@e\ncall 0(:T 0)\nret\n}" }) |body| {
        const text = try std.mem.concat(t.allocator, u8, &.{ "type :T={b}\n", body });
        defer t.allocator.free(text);
        var rejected = try parse(t.allocator, text);
        defer rejected.deinit();
        try t.expectError(error.UnsupportedAggregateAbi, amd64.emit(t.allocator, &rejected));
    }
}
test "aggregate_abi_small_integer detached facts survive source and module lifetime and cannot authorize tampering" {
    const text = try t.allocator.dupe(u8, small);
    defer t.allocator.free(text);
    var module = try parse(t.allocator, text);
    @memset(text, 0xa5);
    var plans = planner.ModulePlans.init(t.allocator, &module, .{ .callee_saved_homes = true }) catch |err| {
        module.deinit();
        return err;
    };
    defer plans.deinit();
    try t.expect(plans.get(1) == null);
    module.types.items[0].size += 1;
    try t.expectError(error.InvalidRecordLayout, amd64.emit(t.allocator, &module));
    module.deinit();
    try t.expectEqual(@as(u64, 9), plans.get(0).?.signature.result.integer_record.declared_bytes);
    try t.expectEqual(@as(usize, 2), plans.get(0).?.parameter_objects.len);
    try t.expectEqual(@as(u64, 1), plans.get(2).?.pads[0].declared_bytes);
}
fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, small);
    defer module.deinit();
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        const output = try amd64.emitWithOptions(allocator, &module, options);
        allocator.free(output);
    }
}
test "aggregate_abi_small_integer all multi-function parser plan object home writer failures clean up" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
test "aggregate_abi_small_integer failed emission keeps module retryable with balanced partial object plans" {
    var module = try parse(t.allocator, small);
    defer module.deinit();
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        var finished = false;
        for (0..2048) |index| {
            var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = index, .resize_fail_index = 0 });
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
test "aggregate_abi_small_integer independent interpreter root and reached refusal precedence remain" {
    var module = try parse(t.allocator, small);
    defer module.deinit();
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluate(t.allocator, module.functions.items[0], &.{}, .{ .max_call_depth = 0 }));
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluateModule(t.allocator, &module, id(0), &.{}, .{ .max_call_depth = 0, .stack_memory = .{}, .global_memory = .{}, .internal_variadic_calls = true }));
    var caller = try parse(t.allocator, "type :T={b}\nfunction $f(){\n@e\ncall $missing(:T $absent)\nret\n}");
    defer caller.deinit();
    try t.expectError(error.StepLimitExceeded, interpreter.evaluate(t.allocator, caller.functions.items[0], &.{}, .{ .max_steps = 0 }));
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluate(t.allocator, caller.functions.items[0], &.{}, .{ .max_steps = 1 }));
}

test "aggregate_abi_small_integer compact earlier DAG shape handles deep and huge unused records without expansion" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(t.allocator);
    // Independent arithmetic: (2^31-1)^2 then 4*A*A+8*A+3 = UINT64_MAX.
    // These valid unused declarations must not expand into byte-sized buffers.
    try text.appendSlice(t.allocator, "type :A={b 2147483647}\ntype :B={:A 2147483647}\ntype :Huge={:B 4,:A 8,b 3}\ntype :T0={b}\n");
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
    try t.expectEqual(@as(u64, 1), plan.signature.result.integer_record.declared_bytes);
    try tuple(plan.signature.arguments[0], .rdi, null, .{ 1, 0 });
    const assembly = try amd64.emit(t.allocator, &module);
    defer t.allocator.free(assembly);
    try t.expect(std.mem.indexOf(u8, assembly, "movzbl 0(%r11), %r10d") != null);
}

test "aggregate_abi_small_integer exact 64KiB independent home plus private result-pad limit" {
    for ([_]usize{ 4096, 4097 }) |count| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(t.allocator);
        try text.appendSlice(t.allocator, "type :T={b}\nfunction $f(){\n@e\n");
        for (0..count) |n| {
            const line = try std.fmt.allocPrint(t.allocator, "%p{d} =:T call $external()\n", .{n});
            defer t.allocator.free(line);
            try text.appendSlice(t.allocator, line);
        }
        try text.appendSlice(t.allocator, "ret\n}");
        var module = try parse(t.allocator, text.items);
        defer module.deinit();
        if (count == 4097) {
            try t.expectError(error.FrameTooLarge, amd64.emit(t.allocator, &module));
        } else {
            // Literal independent geometry:4096 pointer homes*8 +4096 distinct
            // minimally8-aligned byte-object pads*8 =65536; no hidden/outgoing.
            var plan = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
            defer plan.deinit();
            try t.expectEqual(@as(u64, 65536), plan.frame.bytes);
            try t.expectEqual(@as(usize, 4096), plan.pads.len);
            try t.expectEqual(@as(u64, 32776), plan.pads[0].end);
            try t.expectEqual(@as(u64, 65536), plan.pads[4095].end);
            const assembly = try amd64.emit(t.allocator, &module);
            defer t.allocator.free(assembly);
            try t.expectEqual(@as(usize, 16), std.mem.count(u8, assembly, "testb $0, (%rsp)"));
            try t.expectEqual(count, std.mem.count(u8, assembly, "call external"));
        }
    }
}

fn moveMixedSide(allocator: std.mem.Allocator, source: []const u8, prefix: bool) ![]u8 {
    if (!prefix) return allocator.dupe(u8, source);
    const first = std.mem.indexOf(u8, source, "export function ").?;
    const side = std.mem.indexOf(u8, source, "\nfunction ").? + 1;
    return std.mem.concat(allocator, u8, &.{ source[0..first], source[side..], source[first..side] });
}
fn scalarFragment(assembly: []const u8, name: []const u8) []const u8 {
    var head_buffer: [128]u8 = undefined;
    var tail_buffer: [128]u8 = undefined;
    const head = std.fmt.bufPrint(&head_buffer, ".globl {s}\n.type {s}, @function\n", .{ name, name }) catch unreachable;
    const tail = std.fmt.bufPrint(&tail_buffer, ".size {s}, .-{s}\n", .{ name, name }) catch unreachable;
    const begin = std.mem.indexOf(u8, assembly, head).?;
    return assembly[begin .. begin + std.mem.indexOf(u8, assembly[begin..], tail).? + tail.len];
}
test "aggregate_abi_small_integer prefix suffix mixed scalar fragments establish exact symbol IDs and function ordinals" {
    for ([_]bool{ false, true }) |prefix| {
        const source = try moveMixedSide(t.allocator, @embedFile("fixtures/aggregate_abi_small_integer_mixed.ssa"), prefix);
        defer t.allocator.free(source);
        const reference_source = try moveMixedSide(t.allocator, @embedFile("fixtures/aggregate_abi_small_integer_scalar_reference.ssa"), prefix);
        defer t.allocator.free(reference_source);
        var module = try parse(t.allocator, source);
        defer module.deinit();
        var reference = try parse(t.allocator, reference_source);
        defer reference.deinit();
        try t.expectEqual(reference.symbols.names.items.len, module.symbols.names.items.len);
        for (reference.symbols.names.items, module.symbols.names.items) |a, b| try t.expectEqualStrings(a, b);
        try t.expectEqual(reference.functions.items.len, module.functions.items.len);
        for (reference.functions.items, module.functions.items, 0..) |a, b, n| {
            try t.expectEqual(a.name, b.name);
            const fid = id(@intCast(n));
            try t.expect(reference.getFunction(fid).? == a and module.getFunction(fid).? == b);
            if (n == (if (prefix) @as(usize, 0) else 4)) {
                try t.expect(!a.hasRecordSignature() and b.hasRecordSignature());
            } else try t.expect(!a.hasRecordSignature() and !b.hasRecordSignature());
        }
        for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
            const a = try amd64.emitWithOptions(t.allocator, &reference, options);
            defer t.allocator.free(a);
            const b = try amd64.emitWithOptions(t.allocator, &module, options);
            defer t.allocator.free(b);
            for ([_][]const u8{ "common_address", "ordinary_address", "external_address", "T" }) |symbol| try t.expectEqualSlices(u8, scalarFragment(a, symbol), scalarFragment(b, symbol));
        }
    }
}
