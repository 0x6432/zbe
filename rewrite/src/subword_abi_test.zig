//! ABI annotations do not introduce arithmetic types or implicit extension.
const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const Module = @import("module.zig").Module;
const interpreter = @import("interpreter.zig");
const fixture = @embedFile("fixtures/subword-abi.ssa");
const narrow = [_]ir.AbiType{ .signed_byte, .unsigned_byte, .signed_half, .unsigned_half };
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "subword-abi", .text = text }, &diagnostic);
}
const emit_options = [_]@import("amd64.zig").Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } };

test "ABI types keep four scalar classes and narrow parameters have owned failure atomic identity" {
    for (narrow) |ty| {
        try testing.expectEqual(ir.ScalarType.word, ty.scalar());
        try testing.expect(ty.subword() != null);
        for (0..2) |failure_offset| {
            var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
            var f = ir.Function.initAbi(failing.allocator(), @fromBackingInt(@as(u32, 0)), ty);
            defer f.deinit();
            failing.fail_index = failing.alloc_index + failure_offset;
            try testing.expectError(error.OutOfMemory, f.addParameterAbi(ty));
            try testing.expectEqual(@as(usize, 0), f.values.items.len);
            try testing.expectEqual(@as(usize, 0), f.parameters.items.len);
            failing.fail_index = std.math.maxInt(usize);
            const p = try f.addParameterAbi(ty);
            const b = try f.addBlock(null);
            try f.terminate(b, .{ .return_value = .{ .value = p } });
            try f.validateStructure();
            try testing.expectEqual(ty.subword(), f.return_subword);
            try testing.expectEqual(ty.subword(), f.values.items[0].parameter_subword);
        }
    }
    for ([_]ir.ScalarType{ .word, .long, .single, .double }) |ty| {
        try testing.expectEqual(ty, ir.AbiType.fromScalar(ty).scalar());
        try testing.expect(ir.AbiType.fromScalar(ty).subword() == null);
    }
}

test "narrow direct and indirect call builders copy annotations and retry every unpublished allocation" {
    for (narrow) |ty| for ([_]bool{ false, true }) |indirect| for (0..2) |failure_offset| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
        var f = ir.Function.init(failing.allocator(), @fromBackingInt(@as(u32, 0)), .word);
        defer f.deinit();
        const b = try f.addBlock(null);
        const result = try f.declareValue(.word);
        var args = [_]ir.CallArgument{ir.CallArgument.init(ty, .{ .constant = .{ .word = 0xabcdef81 } })};
        const target: ir.Operand = .{ .constant = .{ .long = 0 } }; // Never executed.
        failing.fail_index = failing.alloc_index + failure_offset;
        const attempt = if (indirect) f.defineIndirectCallAbi(b, result, target, ty, &args) else f.defineCallAbi(b, result, f.name, ty, &args);
        try testing.expectError(error.OutOfMemory, attempt);
        try testing.expect(f.values.items[@backingInt(result)].definition == .pending);
        try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
        failing.fail_index = std.math.maxInt(usize);
        try testing.expectError(error.TypeMismatch, f.defineCallAbi(b, result, f.name, .long, &args));
        args[0].scalar_type = .long;
        args[0].operand = .{ .constant = .{ .long = 1 } };
        try testing.expectError(error.TypeMismatch, f.defineCallAbi(b, result, f.name, ty, &args));
        args[0] = ir.CallArgument.init(ty, .{ .constant = .{ .word = 0xabcdef81 } });
        if (indirect) try f.defineIndirectCallAbi(b, result, target, ty, &args) else try f.defineCallAbi(b, result, f.name, ty, &args);
        args[0].subword_type = null;
        args[0].operand = .{ .constant = .{ .word = 0 } };
        const call = f.blocks.items[0].instructions.items[0].call;
        try testing.expectEqual(ty.subword(), call.result_subword);
        try testing.expectEqual(ty.subword(), call.arguments[0].subword_type);
        try testing.expectEqual(@as(u32, 0xabcdef81), call.arguments[0].operand.constant.word);
        try f.terminate(b, .{ .return_value = .{ .value = result } });
        try f.validateStructure();
    };
}

test "forged ABI metadata cannot annotate nonword void or nonparameter values" {
    var module = try parse(testing.allocator, "function l $f(l %p) {\n@e\n%r =l call $g(l %p)\ncall $effect()\nret %r\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    f.return_subword = .signed_byte;
    try testing.expectError(error.TypeMismatch, f.validateStructure());
    f.return_subword = null;
    f.values.items[0].parameter_subword = .unsigned_byte;
    try testing.expectError(error.TypeMismatch, f.validateStructure());
    f.values.items[0].parameter_subword = null;
    f.values.items[1].parameter_subword = .signed_half;
    try testing.expectError(error.TypeMismatch, f.validateStructure());
    f.values.items[1].parameter_subword = null;
    const call = &f.blocks.items[0].instructions.items[0].call;
    call.result_subword = .unsigned_half;
    try testing.expectError(error.TypeMismatch, f.validateStructure());
    call.result_subword = null;
    const args = @constCast(call.arguments);
    args[0].subword_type = .signed_byte;
    try testing.expectError(error.TypeMismatch, f.validateStructure());
    args[0].subword_type = null;
    f.blocks.items[0].instructions.items[1].call.result_subword = .unsigned_byte;
    try testing.expectError(error.TypeMismatch, f.validateStructure());
    f.blocks.items[0].instructions.items[1].call.result_subword = null;
    try f.validateStructure();
    var words = try parse(testing.allocator, "function w $words(w %p) {\n@e\n%x =w copy %p\nret %x\n}\nfunction $void() {\n@e\nret\n}");
    defer words.deinit();
    const word_function = words.functions.items[0];
    word_function.values.items[1].parameter_subword = .signed_byte;
    try testing.expectError(error.TypeMismatch, word_function.validateStructure());
    word_function.values.items[1].parameter_subword = null;
    try word_function.validateStructure();
    const void_function = words.functions.items[1];
    void_function.return_subword = .signed_byte;
    try testing.expectError(error.TypeMismatch, void_function.validateStructure());
    void_function.return_subword = null;
    try void_function.validateStructure();
}

test "narrow ABI parser rejects noncall SSA annotations and preserves exact defined signatures" {
    const spellings = [_][]const u8{ "sb", "ub", "sh", "uh" };
    for (spellings) |spelling| {
        for ([_][]const u8{ "copy 1", "add 1, 2", "phi @e 1", "\ncall $g()" }) |operation| {
            const text = try std.fmt.allocPrint(testing.allocator, "function w $f() {{\n@e\n%x ={s} {s}\nret 0\n}}", .{ spelling, operation });
            defer testing.allocator.free(text);
            try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
        }
    }
    const types = [_][]const u8{ "w", "sb", "ub", "sh", "uh" };
    for (types) |caller| for (types) |callee| {
        const text = try std.fmt.allocPrint(testing.allocator, "function w $f() {{\n@e\n%x ={s} call $g({s} 129)\nret 0\n}}\nfunction {s} $g({s} %x) {{\n@e\nret %x\n}}", .{ caller, caller, callee, callee });
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        if (std.mem.eql(u8, caller, callee)) {
            try @import("module_validation.zig").validate(testing.allocator, &module);
        } else try testing.expectError(error.CallSignatureMismatch, @import("module_validation.zig").validate(testing.allocator, &module));
    };
    // Isolate every argument annotation comparison from return comparisons.
    for (types) |caller| for (types) |callee| {
        const text = try std.fmt.allocPrint(testing.allocator, "function w $f() {{\n@e\n%x =w call $g({s} 129)\nret 0\n}}\nfunction w $g({s} %x) {{\n@e\nret %x\n}}", .{ caller, callee });
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        if (std.mem.eql(u8, caller, callee)) {
            try @import("module_validation.zig").validate(testing.allocator, &module);
        } else try testing.expectError(error.CallSignatureMismatch, @import("module_validation.zig").validate(testing.allocator, &module));
    };
}

fn extendedSum(bits: u32) u32 {
    // Independent small integer arithmetic; never production extension helpers.
    const byte: i64 = @intCast(bits & 255);
    const half: i64 = @intCast(bits & 65535);
    const signed_byte = byte - (if (byte >= 128) @as(i64, 256) else 0);
    const signed_half = half - (if (half >= 32768) @as(i64, 65536) else 0);
    return @truncate(@as(u64, @bitCast(signed_byte + byte + signed_half + half)));
}
fn run(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, fixture);
    defer module.deinit();
    for (module.functions.items) |f| _ = try @import("optimize.zig").foldIntegerConstants(allocator, f);
    for ([_]u64{ 0, 0x7f, 0x80, 0xff, 0x7fff, 0x8000, 0xffff, 0xabcdef0180fffe81 }) |bits| {
        const result = try interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 0)), &.{.{ .long = bits }}, .{});
        try testing.expectEqual(extendedSum(@truncate(bits)), result.?.word);
    }
    const recursive = (try interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 5)), &.{ .{ .word = 5 }, .{ .word = 65534 } }, .{})).?.word;
    try testing.expectEqual(@as(u32, 3), recursive & 65535); // Only low16 return bits are defined.
    for (0..8) |count| {
        const result = (try interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 6)), &.{ .{ .word = @intCast(count) }, .{ .word = 0x12345681 }, .{ .word = 0xabcdef7f } }, .{})).?.word;
        const expected: i64 = if (count % 2 == 0) -127 + 257 * 127 else 127 - 257 * 127;
        try testing.expectEqual(@as(u32, @truncate(@as(u64, @bitCast(expected)))), result);
    }
}
test "explicit narrow observations agree across recursion lowword projection phi swaps and folding" {
    try run(testing.allocator);
}

test "narrow annotations do not enable interpreter external or indirect calls and budgets still win" {
    for ([_][]const u8{ "$external", "0" }, 0..) |target, i| {
        const text = try std.fmt.allocPrint(testing.allocator, "function w $f() {{\n@e\n%x =sb call {s}(uh 65535)\n%r =w extsb %x\nret %r\n}}", .{target});
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        const f = module.functions.items[0];
        try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 0)), &.{}, .{ .max_steps = 0 }));
        try testing.expectError(if (i == 0) error.UnsupportedExternalCall else error.UnsupportedIndirectCall, interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 0)), &.{}, .{}));
        try testing.expectError(error.UnsupportedCall, interpreter.evaluate(testing.allocator, f, &.{}, .{}));
    }
}

fn exercise(allocator: std.mem.Allocator) !void {
    // The full value matrix runs above. Inject OOM into one representative
    // invocation of each distinct path, not repeated identical validation work.
    var module = try parse(allocator, fixture);
    defer module.deinit();
    _ = try interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 0)), &.{.{ .long = 0xabcdef0180fffe81 }}, .{});
    _ = try interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 5)), &.{ .{ .word = 2 }, .{ .word = 65534 } }, .{});
    _ = try interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 6)), &.{ .{ .word = 2 }, .{ .word = 129 }, .{ .word = 127 } }, .{});
    for (module.functions.items) |function| _ = try @import("optimize.zig").foldIntegerConstants(allocator, function);
    _ = try module.addFunctionAbi("typed_builder", .unsigned_byte);
    const f = module.functions.items[module.functions.items.len - 1];
    const p = try f.addParameterAbi(.signed_byte);
    const b = try f.addBlock(null);
    const result = try f.declareValue(.word);
    try f.defineCallAbi(b, result, module.functions.items[1].name, .signed_byte, &.{ir.CallArgument.init(.signed_byte, .{ .value = p })});
    try f.terminate(b, .{ .return_value = .{ .value = result } });
    for (module.functions.items) |function| {
        var live = try @import("liveness.zig").Snapshot.init(allocator, function, .{});
        defer live.deinit();
        var graph = try @import("interference.zig").Graph.init(allocator, function, .{});
        defer graph.deinit();
    }
    for (emit_options) |options| {
        const assembly = try @import("amd64.zig").emitWithOptions(allocator, &module, options);
        defer allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "call subword_byte") != null);
    }
}
test "typed narrow parsing builders calls analyses folding and emission clean every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
