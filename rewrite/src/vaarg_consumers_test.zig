//! Caller-contracted native descriptors; no interpreter host memory.
const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const Module = @import("module.zig").Module;
const interpreter = @import("interpreter.zig");
const fixture = @embedFile("fixtures/vaarg-consumers.ssa");
const emit_options = [_]@import("amd64.zig").Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } };
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "vaarg-consumers", .text = text }, &diagnostic);
}

test "vaarg builder validates before allocation and leaves failed results retryable for four classes" {
    for ([_]ir.ScalarType{ .word, .long, .single, .double }) |ty| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
        var f = ir.Function.init(failing.allocator(), @fromBackingInt(@as(u32, 0)), null);
        defer f.deinit();
        const b = try f.addBlock(null);
        const result = try f.declareValue(ty);
        const before = failing.alloc_index;
        try testing.expectError(error.TypeMismatch, f.defineVaArg(b, result, .{ .constant = .{ .word = 0 } }));
        try testing.expectEqual(before, failing.alloc_index);
        failing.fail_index = failing.alloc_index;
        try testing.expectError(error.OutOfMemory, f.defineVaArg(b, result, .{ .constant = .{ .long = 0 } }));
        try testing.expect(f.values.items[@backingInt(result)].definition == .pending);
        try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
        failing.fail_index = std.math.maxInt(usize);
        try f.defineVaArg(b, result, .{ .constant = .{ .long = 0 } });
        try testing.expectError(error.InvalidDefinition, f.defineVaArg(b, result, .{ .constant = .{ .long = 0 } }));
        try f.terminate(b, .{ .return_value = null });
        try f.validateStructure();
        f.blocks.items[0].instructions.items[0].va_argument.list = .{ .constant = .{ .word = 0 } };
        try testing.expectError(error.TypeMismatch, f.validateStructure());
        try testing.expectError(error.BlockTerminated, f.defineVaArg(b, result, .{ .constant = .{ .long = 0 } }));
    }
}

test "vaarg grammar and SSA reject invalid list classes arity annotations and unsupported initialization" {
    for ([_][]const u8{
        "function w $f(w %p) {\n@e\n%x =w vaarg %p\nret %x\n}",
        "function w $f(s %p) {\n@e\n%x =w vaarg %p\nret %x\n}",
        "function w $f(d %p) {\n@e\n%x =w vaarg %p\nret %x\n}",
        "function w $f(l %p) {\n@e\n%x =w vaarg\nret %x\n}",
        "function w $f(l %p) {\n@e\n%x =w vaarg %p, %p\nret %x\n}",
        "function w $f(l %p) {\n@e\n%x =sb vaarg %p\nret %x\n}",
        "function $f(l %p) {\n@e\nvaarg %p\nret\n}",
        "function $f(l %p) {\n@e\nvastart %p\nret\n}",
        "function $f(...) {\n@e\nret\n}",
    }) |text| try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
    var invalid = try parse(testing.allocator, "function w $f() {\n@e\n%x =w vaarg %p\n%p =l copy 0\nret %x\n}");
    defer invalid.deinit();
    try testing.expectError(error.InvalidSSA, @import("module_validation.zig").validate(testing.allocator, &invalid));
    var symbols = try parse(testing.allocator, "function w $f() {\n@e\n%x =w vaarg $descriptor\nret %x\n}");
    defer symbols.deinit();
    var uses = symbols.functions.items[0].blocks.items[0].instructions.items[0].operands();
    try testing.expect(uses.next().? == .symbol);
    try testing.expect(uses.next() == null);
}

test "reached vaarg refuses before pointer resolution under all memory options and budget preserves prior writes" {
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    const first: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 0));
    const safe: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 6));
    var image = try @import("memory.zig").Image.init(testing.allocator, 24, .{});
    defer image.deinit();
    for (0..8) |bits| {
        const options: interpreter.Options = .{ .memory_image = if (bits & 1 != 0) &image else null, .stack_memory = if (bits & 2 != 0) .{} else null, .global_memory = if (bits & 4 != 0) .{} else null };
        for (0..4) |index| {
            try testing.expectError(error.UnsupportedVariadicOperation, interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, @intCast(index))), &.{.{ .long = 0 }}, options));
            if (options.global_memory != null) {
                // Existing configuration preflight wins before any instruction.
                try testing.expectError(error.GlobalsRequireModule, interpreter.evaluate(testing.allocator, module.functions.items[index], &.{.{ .long = 0 }}, options));
            } else try testing.expectError(error.UnsupportedVariadicOperation, interpreter.evaluate(testing.allocator, module.functions.items[index], &.{.{ .long = 0 }}, options));
        }
        try testing.expectEqual(@as(u32, 42), (try interpreter.evaluateModule(testing.allocator, &module, safe, &.{ .{ .long = 0 }, .{ .word = 0 } }, options)).?.word);
    }
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, first, &.{.{ .long = 0 }}, .{ .max_steps = 0 }));
    var effects = try parse(testing.allocator, "function w $f(l %p) {\n@e\nstorew 123, %p\n%x =w vaarg $external_descriptor\nret %x\n}");
    defer effects.deinit();
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &effects, first, &.{.{ .long = image.base }}, .{ .memory_image = &image, .max_steps = 1 }));
    try testing.expectEqual(@as(u8, 123), image.bytes[0]);
    try testing.expectError(error.UnsupportedVariadicOperation, interpreter.evaluateModule(testing.allocator, &effects, first, &.{.{ .long = image.base }}, .{ .memory_image = &image, .max_steps = 2 }));
    try testing.expectEqual(@as(u8, 123), image.bytes[0]);
    try testing.expectEqual(@as(usize, 24), image.bytes.len);
    for (image.bytes[1..]) |byte| try testing.expectEqual(@as(u8, 0), byte);
    const nested: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 7));
    try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, nested, &.{.{ .long = 0 }}, .{ .max_call_depth = 1 }));
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, nested, &.{.{ .long = 0 }}, .{ .max_steps = 1 }));
    try testing.expectError(error.UnsupportedVariadicOperation, interpreter.evaluateModule(testing.allocator, &module, nested, &.{.{ .long = 0 }}, .{}));
}

test "vaarg remains an ordered effect with independent banks and unique internal labels in all home options" {
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    for (module.functions.items) |f| _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
    try testing.expect(module.functions.items[4].blocks.items[0].instructions.items[0] == .va_argument);
    try testing.expectEqual(@as(usize, 2), module.functions.items[4].blocks.items[0].instructions.items.len);
    for (emit_options) |options| {
        const assembly = try @import("amd64.zig").emitWithOptions(testing.allocator, &module, options);
        defer testing.allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "movl 0(%r10), %eax\n\tcmpl $48, %eax") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "movl 4(%r10), %eax\n\tcmpl $176, %eax") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "addl $8, 0(%r10)") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "addl $16, 4(%r10)") != null);
    }
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, fixture);
    defer module.deinit();
    const f = module.functions.items[0];
    const id: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 0));
    if (interpreter.evaluateModule(allocator, &module, id, &.{.{ .long = 0 }}, .{})) |_| return error.ExpectedRefusal else |err| {
        if (err != error.UnsupportedVariadicOperation) return err;
    }
    if (interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 7)), &.{.{ .long = 0 }}, .{})) |_| return error.ExpectedRefusal else |err| {
        if (err != error.UnsupportedVariadicOperation) return err;
    }
    for (module.functions.items) |function| {
        var live = try @import("liveness.zig").Snapshot.init(allocator, function, .{});
        defer live.deinit();
        var graph = try @import("interference.zig").Graph.init(allocator, function, .{});
        defer graph.deinit();
        _ = try @import("optimize.zig").foldIntegerConstants(allocator, function);
    }
    const new = try f.addBlock(null);
    const result = try f.declareValue(.word);
    try f.defineVaArg(new, result, .{ .constant = .{ .long = 0 } });
    try f.terminate(new, .{ .return_value = .{ .value = result } });
    for (emit_options) |options| {
        const assembly = try @import("amd64.zig").emitWithOptions(allocator, &module, options);
        defer allocator.free(assembly);
    }
}
test "every vaarg parse builder analysis fold refusal and emitter allocation cleans up" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
