//! Variadic call sites only: no variadic function bodies or host evaluation.
const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const Module = @import("module.zig").Module;
const interpreter = @import("interpreter.zig");
const fixture = @embedFile("fixtures/variadic-calls.ssa");
const emit_options = [_]@import("amd64.zig").Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } };
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "variadic-calls", .text = text }, &diagnostic);
}

test "variadic marker records one checked named prefix without operands or implicit promotions" {
    const lists = [_][]const u8{ "", "...", "..., w 7", "w 1, ...", "d d_1, ..., w 253", "..., sb 129, s s_1" };
    const prefixes = [_]?usize{ null, 0, 0, 1, 1, 0 };
    const lengths = [_]usize{ 0, 0, 1, 1, 2, 2 };
    for (lists, prefixes, lengths) |list, prefix, length| {
        const text = try std.fmt.allocPrint(testing.allocator, "function w $f() {{\n@e\n%x =sb call $external({s})\nret 0\n}}", .{list});
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        const call = module.functions.items[0].blocks.items[0].instructions.items[0].call;
        try testing.expectEqual(prefix, call.variadic_start);
        try testing.expectEqual(length, call.arguments.len);
        try testing.expectEqual(ir.SubwordType.signed_byte, call.result_subword.?);
        var operands = module.functions.items[0].blocks.items[0].instructions.items[0].operands();
        var count: usize = 0;
        while (operands.next() != null) count += 1;
        try testing.expectEqual(length, count);
        if (std.mem.indexOf(u8, list, "sb") != null) {
            try testing.expectEqual(ir.SubwordType.signed_byte, call.arguments[0].subword_type.?);
            try testing.expectEqual(@as(u32, 129), call.arguments[0].operand.constant.word);
            try testing.expectEqual(ir.ScalarType.single, call.arguments[1].scalar_type);
        }
        try @import("module_validation.zig").validate(testing.allocator, &module);
    }
}

test "common typed variadic builder owns arguments and rejects invalid options before allocation or publication" {
    for ([_]bool{ false, true }) |indirect| for ([_]bool{ false, true }) |scalar| for (0..2) |failure_offset| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
        var f = ir.Function.init(failing.allocator(), @fromBackingInt(@as(u32, 0)), null);
        defer f.deinit();
        const b = try f.addBlock(null);
        const result = if (scalar) try f.declareValue(.word) else null;
        const target: ir.CallTarget = if (indirect) .{ .address = .{ .constant = .{ .long = 0 } } } else .{ .symbol = f.name };
        var args = [_]ir.CallArgument{ ir.CallArgument.init(.word, .{ .constant = .{ .word = 253 } }), ir.CallArgument.init(.double, .{ .constant = .{ .double_bits = 0x3ff0000000000000 } }) };
        const before = failing.alloc_index;
        try testing.expectError(error.InvalidVariadicMarker, f.appendCall(b, result, target, &args, .{ .variadic_start = 3 }));
        try testing.expectEqual(before, failing.alloc_index);
        try testing.expectError(error.TypeMismatch, f.appendCall(b, result, target, &args, .{ .result_abi = .long, .variadic_start = 1 }));
        failing.fail_index = failing.alloc_index + failure_offset;
        const options: ir.CallOptions = .{ .result_abi = if (scalar) .signed_byte else null, .variadic_start = 1 };
        try testing.expectError(error.OutOfMemory, f.appendCall(b, result, target, &args, options));
        if (result) |id| try testing.expect(f.values.items[@backingInt(id)].definition == .pending);
        try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
        failing.fail_index = std.math.maxInt(usize);
        try f.appendCall(b, result, target, &args, options);
        args[0].operand = .{ .constant = .{ .word = 0 } };
        const call = &f.blocks.items[0].instructions.items[0].call;
        try testing.expectEqual(@as(?usize, 1), call.variadic_start);
        try testing.expectEqual(@as(u32, 253), call.arguments[0].operand.constant.word);
        try f.terminate(b, .{ .return_value = null });
        try f.validateStructure();
        call.variadic_start = std.math.maxInt(usize);
        try testing.expectError(error.InvalidVariadicMarker, f.validateStructure());
        call.variadic_start = 2; // Zero variable arguments is valid metadata.
        try f.validateStructure();
    };
}

test "malformed markers and variadic bodies reject while defined nonvariadic signatures cannot acquire a marker" {
    for ([_][]const u8{
        "function $f(...) {\n@e\nret\n}",
        "function w $f(w %p, ...) {\n@e\nret %p\n}",
        "function w $f() {\n@e\n%x =w call $g(..., ...)\nret %x\n}",
        "function w $f() {\n@e\n%x =w call $g(w 1, ..., w 2, ...)\nret %x\n}",
        "function w $f() {\n@e\n%x =w call $g(...,)\nret %x\n}",
        "function w $f() {\n@e\n%x =w call $g(... w 1)\nret %x\n}",
        "function w $f() {\n@e\n%x =w call $g(w 1 ...)\nret %x\n}",
        "function $f(l %p) {\n@e\nvastart %p\nret\n}",
        "function w $f(l %p) {\n@e\n%x =w vaarg %p\nret %x\n}",
    }) |text| try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
    for ([_][]const u8{
        "function w $f() {\n@e\n%x =w call $g(...)\nret %x\n}\nfunction w $g() {\n@e\nret 7\n}",
        "function $f() {\n@e\nret\n@unused\ncall $g(w 7, ...)\nret\n}\nfunction $g(w %p) {\n@e\nret\n}",
    }) |text| {
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        for (emit_options) |options| try testing.expectError(error.CallSignatureMismatch, @import("amd64.zig").emitWithOptions(testing.allocator, &module, options));
        try testing.expectError(error.CallSignatureMismatch, interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 0)), &.{}, .{ .max_steps = 0 }));
    }
}

test "AL setup is exact capped includes named SSE and occurs after last argument with no nonvariadic change" {
    for ([_]bool{ false, true }) |indirect| for (0..11) |floats| {
        var text: std.Io.Writer.Allocating = .init(testing.allocator);
        defer text.deinit();
        try text.writer.writeAll("function w $f() {\n@e\n");
        if (indirect) try text.writer.writeAll("%target =l copy $external\n");
        try text.writer.print("%r =w call {s}(", .{if (indirect) "%target" else "$external"});
        for (0..floats) |_| try text.writer.writeAll("d d_1, ");
        try text.writer.writeAll("w 253");
        const normal_list_end = text.written().len;
        try text.writer.writeAll(")\nret %r\n}");
        var normal = try parse(testing.allocator, text.written());
        defer normal.deinit();
        // Same source/IR except a final marker, so floats are ALL named.
        const marked = try std.mem.concat(testing.allocator, u8, &.{ text.written()[0..normal_list_end], ", ...", text.written()[normal_list_end..] });
        defer testing.allocator.free(marked);
        var variadic = try parse(testing.allocator, marked);
        defer variadic.deinit();
        for (emit_options) |options| {
            const before = try @import("amd64.zig").emitWithOptions(testing.allocator, &normal, options);
            defer testing.allocator.free(before);
            const after = try @import("amd64.zig").emitWithOptions(testing.allocator, &variadic, options);
            defer testing.allocator.free(after);
            const move = try std.fmt.allocPrint(testing.allocator, "\tmovb ${d}, %al\n", .{@min(floats, 8)});
            defer testing.allocator.free(move);
            try testing.expect(std.mem.indexOf(u8, before, move) == null);
            const adjacency = try std.mem.concat(testing.allocator, u8, &.{ move, if (indirect) "\tcall *%r11\n" else "\tcall external\n" });
            defer testing.allocator.free(adjacency);
            try testing.expect(std.mem.indexOf(u8, after, adjacency) != null);
            const removed = try std.mem.replaceOwned(u8, testing.allocator, after, move, "");
            defer testing.allocator.free(removed);
            try testing.expectEqualStrings(before, removed);
        }
    };
}

test "variadic call annotations preserve interpreter safe paths dispatch refusal effects and budget precedence" {
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    const first: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 0));
    const safe: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 5));
    try testing.expectEqual(@as(u32, 42), (try interpreter.evaluateModule(testing.allocator, &module, safe, &.{ .{ .word = 0 }, .{ .long = 0 } }, .{})).?.word);
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, first, &.{}, .{ .max_steps = 0 }));
    try testing.expectError(error.UnsupportedExternalCall, interpreter.evaluateModule(testing.allocator, &module, first, &.{}, .{}));
    try testing.expectError(error.UnsupportedCall, interpreter.evaluate(testing.allocator, module.functions.items[0], &.{}, .{}));
    try testing.expectError(error.UnsupportedIndirectCall, interpreter.evaluateModule(testing.allocator, &module, safe, &.{ .{ .word = 1 }, .{ .long = 0 } }, .{}));
    for (module.functions.items) |f| _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
    try testing.expectEqual(@as(?usize, 1), module.functions.items[2].blocks.items[0].instructions.items[0].call.variadic_start);
    try testing.expectEqual(@as(usize, 2), module.functions.items[2].blocks.items[0].instructions.items.len);
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, fixture);
    defer module.deinit();
    const id = try module.addFunction("checked_vararg_builder", null);
    const f = module.getFunction(id).?;
    const b = try f.addBlock(null);
    const result = try f.declareValue(.word);
    try f.appendCall(b, result, .{ .symbol = try module.symbols.intern("external_narrow_varargs") }, &.{ir.CallArgument.init(.word, .{ .constant = .{ .word = 7 } })}, .{ .result_abi = .signed_byte, .variadic_start = 0 });
    try f.terminate(b, .{ .return_value = null });
    const value = try interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 5)), &.{ .{ .word = 0 }, .{ .long = 0 } }, .{});
    try testing.expectEqual(@as(u32, 42), value.?.word);
    if (interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 0)), &.{}, .{})) |_| return error.ExpectedExternalRefusal else |err| {
        if (err != error.UnsupportedExternalCall) return err;
    }
    for (module.functions.items) |function| {
        var live = try @import("liveness.zig").Snapshot.init(allocator, function, .{});
        defer live.deinit();
        var graph = try @import("interference.zig").Graph.init(allocator, function, .{});
        defer graph.deinit();
        _ = try @import("optimize.zig").foldIntegerConstants(allocator, function);
    }
    for (emit_options) |options| {
        const assembly = try @import("amd64.zig").emitWithOptions(allocator, &module, options);
        defer allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "movb $1, %al\n\tcall vararg_accumulate") != null);
    }
}
test "every variadic call option parsing builder analysis frame refusal and emission allocation cleans up" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
