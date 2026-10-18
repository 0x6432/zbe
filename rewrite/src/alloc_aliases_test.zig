const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const interpreter = @import("interpreter.zig");
const amd64 = @import("amd64.zig");
const optimize = @import("optimize.zig");
const program = @embedFile("fixtures/alloc_aliases_program.ssa");
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "alloc_aliases", .text = text }, &diagnostic);
}
fn allocation(allocator: std.mem.Allocator, opcode: []const u8) !@import("module.zig").Module {
    const text = try std.fmt.allocPrint(allocator, "function l $f(l %n) {{\n@e\n%p =l {s} %n\nret %p\n}}", .{opcode});
    defer allocator.free(text);
    return parse(allocator, text);
}

test "alloc_aliases normalize to alignment four and canonical assembly under all eight options" {
    var canonical = try allocation(testing.allocator, "alloc4");
    defer canonical.deinit();
    for ([_][]const u8{ "alloc1", "alloc2" }) |opcode| {
        var module = try allocation(testing.allocator, opcode);
        defer module.deinit();
        const f = module.functions.items[0];
        const instruction = f.blocks.items[0].instructions.items[0].allocate;
        try testing.expectEqual(ir.AllocationAlignment.four, instruction.alignment);
        try testing.expectEqual(ir.ScalarType.long, try f.operandType(instruction.size));
        try testing.expectEqual(ir.ScalarType.long, f.values.items[@backingInt(instruction.result)].scalar_type);
        for (0..8) |mask| {
            if (mask & 1 != 0) _ = try optimize.foldIntegerConstants(testing.allocator, f);
            try testing.expect(f.blocks.items[0].instructions.items[0] == .allocate);
            const options: amd64.Options = .{ .reuse_stack_homes = mask & 2 != 0, .callee_saved_homes = mask & 4 != 0 };
            const actual = try amd64.emitWithOptions(testing.allocator, &module, options);
            defer testing.allocator.free(actual);
            const expected = try amd64.emitWithOptions(testing.allocator, &canonical, options);
            defer testing.allocator.free(expected);
            try testing.expectEqualStrings(expected, actual);
            try testing.expect(std.mem.indexOf(u8, actual, "testb $0, (%rsp)") != null);
            try testing.expect(std.mem.indexOf(u8, actual, "addq $15, %rax") != null);
        }
    }
}

test "alloc_aliases default refusal and synthetic exact capacity zero overflow boundaries" {
    for ([_][]const u8{ "alloc1", "alloc2", "alloc4" }) |opcode| {
        var module = try allocation(testing.allocator, opcode);
        defer module.deinit();
        const f = module.functions.items[0];
        for ([_]u64{ 0, 1, 2, 3, 4, 15, 16, 17, 31, 32, 33, 4095, 4096, 4097 }) |size| {
            const args = &[_]ir.Constant{.{ .long = size }};
            try testing.expectError(error.UnsupportedAllocation, interpreter.evaluate(testing.allocator, f, args, .{}));
            try testing.expectError(error.StepLimitExceeded, interpreter.evaluate(testing.allocator, f, args, .{ .max_steps = 0, .stack_memory = .{} }));
            const charge: usize = if (size == 0) 0 else @intCast(((size + 15) / 16) * 16 + 16);
            const result = (try interpreter.evaluate(testing.allocator, f, args, .{ .max_steps = 2, .stack_memory = .{ .max_bytes = charge } })).?;
            try testing.expectEqual(if (size == 0) @as(u64, 0) else 0x100000000, result.long);
            if (charge != 0) try testing.expectError(error.StackLimitExceeded, interpreter.evaluate(testing.allocator, f, args, .{ .stack_memory = .{ .max_bytes = charge - 1 } }));
        }
        for ([_]u64{ std.math.maxInt(u64), std.math.maxInt(u64) - 1, std.math.maxInt(u64) - 14 }) |size| {
            try testing.expectError(error.UnsupportedAllocation, interpreter.evaluate(testing.allocator, f, &.{.{ .long = size }}, .{}));
            try testing.expectError(error.AllocationSizeOverflow, interpreter.evaluate(testing.allocator, f, &.{.{ .long = size }}, .{ .stack_memory = .{} }));
        }
        try testing.expectError(error.StackLimitExceeded, interpreter.evaluate(testing.allocator, f, &.{.{ .long = std.math.maxInt(u64) - 15 }}, .{ .stack_memory = .{} }));
        var image = try @import("memory.zig").Image.init(testing.allocator, 16, .{});
        defer image.deinit();
        try testing.expectError(error.UnsupportedAllocation, interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 0)), &.{.{ .long = 8 }}, .{ .memory_image = &image }));
    }
}

test "alloc_aliases preserve long-only typing arity and SSA rejection" {
    for ([_][]const u8{ "alloc1", "alloc2" }) |opcode| {
        inline for ([_][]const u8{
            "function w $f() {{\n@e\n%p =w {s} 1\nret %p\n}}",
            "function d $f() {{\n@e\n%p =d {s} 1\nret %p\n}}",
            "function l $f(w %n) {{\n@e\n%p =l {s} %n\nret %p\n}}",
            "function l $f() {{\n@e\n%p =l {s} s_1\nret %p\n}}",
            "function l $f() {{\n@e\n%p =l {s}\nret %p\n}}",
            "function l $f() {{\n@e\n%p =l {s} 1, 2\nret %p\n}}",
        }) |format| {
            const text = try std.fmt.allocPrint(testing.allocator, format, .{opcode});
            defer testing.allocator.free(text);
            try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
        }
        const text = try std.fmt.allocPrint(testing.allocator, "function l $f() {{\n@e\n%p =l {s} %n\n%n =l copy 1\nret %p\n}}", .{opcode});
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        var issue: ?@import("ssa.zig").Issue = null;
        try testing.expectError(error.InvalidSSA, @import("ssa.zig").validate(testing.allocator, module.functions.items[0], &issue));
        try testing.expectEqual(@import("ssa.zig").Code.use_before_definition, issue.?.code);
    }
    for ([_][]const u8{ "alloc0", "alloc3", "alloc32" }) |opcode| {
        try testing.expectError(error.InvalidInput, allocation(testing.allocator, opcode));
    }
}

test "alloc_aliases exact independent byte checksums and repeated positive allocation freshness" {
    var module = try parse(testing.allocator, program);
    defer module.deinit();
    for ([_]bool{ false, true }) |fold| {
        for (module.functions.items[0..3]) |f| {
            if (fold) _ = try optimize.foldIntegerConstants(testing.allocator, f);
            for ([_]u64{ 0, 1, 2, 3, 4, 15, 16, 17, 31, 32, 33, 255, 256, 4095, 4096, 4097 }) |size| {
                for ([_]u64{ 0, 127, 255, std.math.maxInt(u64) }) |seed| {
                    var expected: u64 = 0;
                    for (0..@intCast(size)) |i| expected += (seed +% i) & 255;
                    const result = (try interpreter.evaluate(testing.allocator, f, &.{ .{ .long = size }, .{ .long = seed } }, .{ .max_steps = 500_000, .stack_memory = .{} })).?;
                    try testing.expectEqual(expected, result.long);
                }
            }
        }
        const f = module.functions.items[5];
        if (fold) _ = try optimize.foldIntegerConstants(testing.allocator, f);
        for ([_]u64{ 0, 1, 2, 10, 31 }) |n| {
            try testing.expectEqual(n * 78, (try interpreter.evaluate(testing.allocator, f, &.{.{ .long = n }}, .{ .stack_memory = .{} })).?.long);
        }
    }
}

test "alloc_aliases unexecuted paths stay safe and failure preserves earlier Image writes" {
    for ([_][]const u8{ "alloc1", "alloc2" }) |opcode| {
        const text = try std.fmt.allocPrint(testing.allocator, "function l $f(w %take,l %image) {{\n@e\njnz %take, @bad, @safe\n@bad\nstoreb 42, %image\n%unused =l {s} 18446744073709551615\nret 7\n@safe\nret 99\n}}", .{opcode});
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        const f = module.functions.items[0];
        _ = try optimize.foldIntegerConstants(testing.allocator, f);
        try testing.expect(f.blocks.items[1].instructions.items[1] == .allocate);
        var image = try @import("memory.zig").Image.init(testing.allocator, 8, .{});
        defer image.deinit();
        try testing.expectEqual(@as(u64, 99), (try interpreter.evaluate(testing.allocator, f, &.{ .{ .word = 0 }, .{ .long = image.base } }, .{})).?.long);
        try testing.expectError(error.UnsupportedAllocation, interpreter.evaluate(testing.allocator, f, &.{ .{ .word = 1 }, .{ .long = image.base } }, .{ .memory_image = &image }));
        try testing.expectEqual(@as(u8, 42), image.bytes[0]);
        image.bytes[0] = 0;
        try testing.expectError(error.AllocationSizeOverflow, interpreter.evaluate(testing.allocator, f, &.{ .{ .word = 1 }, .{ .long = image.base } }, .{ .memory_image = &image, .stack_memory = .{} }));
        try testing.expectEqual(@as(u8, 42), image.bytes[0]);
    }
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, "function l $f() {\n@e\n%a =l alloc1 8\n%b =l alloc2 1\nstorel 7, %a\nstoreb 42, %b\n%x =l loadl %a\n%y =l loadub %b\n%r =l xor %x, %y\nret %r\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    var graph = try @import("interference.zig").Graph.init(allocator, f, .{});
    defer graph.deinit();
    _ = try optimize.foldIntegerConstants(allocator, f);
    try testing.expectEqual(@as(u64, 45), (try interpreter.evaluate(allocator, f, &.{}, .{ .stack_memory = .{} })).?.long);
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(allocator, &module, options);
        defer allocator.free(assembly);
        try testing.expectEqual(@as(usize, 2), std.mem.count(u8, assembly, "addq $15, %rax"));
    }
}

test "alloc_aliases parser analyses synthetic objects and emitter clean every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
