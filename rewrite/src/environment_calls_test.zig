const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const interpreter = @import("interpreter.zig");
const Module = @import("module.zig").Module;
const fixture = @embedFile("fixtures/environment-calls.ssa");
const emit_options = [_]@import("amd64.zig").Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } };
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "environment-calls", .text = text }, &diagnostic);
}
fn id(index: u32) @import("module.zig").FunctionId {
    return @fromBackingInt(index);
}

test "environment headers are first-only long owned parameters and forged metadata is rejected" {
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    try @import("module_validation.zig").validate(testing.allocator, &module);
    const f = module.functions.items[1];
    try testing.expectEqual(f.parameters.items[0], f.environment.?);
    try testing.expectEqual(@as(usize, 1), f.ordinaryParameters().len);
    try testing.expectEqual(ir.ScalarType.long, f.values.items[@backingInt(f.environment.?)].scalar_type);
    const old = f.environment;
    f.environment = f.parameters.items[1];
    try testing.expectError(error.InvalidEnvironment, f.validateStructure());
    f.environment = @fromBackingInt(@as(u32, 0xffffffff));
    try testing.expectError(error.InvalidEnvironment, f.validateStructure());
    f.environment = old;
    f.variadic = true;
    try testing.expectError(error.InvalidEnvironment, f.validateStructure());
    f.variadic = false;
    f.values.items[0].scalar_type = .word;
    try testing.expectError(error.InvalidEnvironment, f.validateStructure());
    for ([_][]const u8{
        "function $f(w %p, env %e) {\n@e\nret\n}",
        "function $f(env %p, env %q) {\n@e\nret\n}",
        "function $f(env %p, ...) {\n@e\nret\n}",
        "function $f(env %p,) {\n@e\nret\n}",
        "function $f(env l %p) {\n@e\nret\n}",
        "function $f() {\n@e\ncall $g(w 1, env 2)\nret\n}",
        "function $f() {\n@e\ncall $g(env 1, env 2)\nret\n}",
        "function $f() {\n@e\ncall $g(env 1, ...)\nret\n}",
        "function $f(w %p) {\n@e\ncall $g(env %p)\nret\n}",
    }) |text| try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
}

test "environment parameter and call builders publish atomically and retain pending results" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    var f = ir.Function.init(failing.allocator(), @fromBackingInt(@as(u32, 0)), .long);
    defer f.deinit();
    failing.fail_index = failing.alloc_index;
    try testing.expectError(error.OutOfMemory, f.addEnvironmentParameter());
    try testing.expectEqual(@as(?ir.ValueId, null), f.environment);
    try testing.expectEqual(@as(usize, 0), f.parameters.items.len);
    try testing.expectEqual(@as(usize, 0), f.values.items.len);
    failing.fail_index = std.math.maxInt(usize);
    const environment = try f.addEnvironmentParameter();
    try testing.expectError(error.InvalidEnvironment, f.addEnvironmentParameter());
    const block = try f.addBlock(null);
    const result = try f.declareValue(.long);
    const target: ir.CallTarget = .{ .address = .{ .value = environment } };
    try testing.expectError(error.TypeMismatch, f.appendCall(block, result, target, &.{}, .{ .environment = .{ .constant = .{ .word = 7 } } }));
    try testing.expectError(error.InvalidEnvironment, f.appendCall(block, result, target, &.{}, .{ .environment = .{ .value = environment }, .variadic_start = 0 }));
    failing.fail_index = failing.alloc_index;
    try testing.expectError(error.OutOfMemory, f.appendCall(block, result, target, &.{.{ .scalar_type = .long, .operand = .{ .value = environment } }}, .{ .environment = .{ .value = environment } }));
    try testing.expect(f.values.items[@backingInt(result)].definition == .pending);
    try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
    failing.fail_index = std.math.maxInt(usize);
    try f.appendCall(block, result, target, &.{}, .{ .environment = .{ .value = environment } });
    try f.terminate(block, .{ .return_value = .{ .value = result } });
    try f.validateStructure();
    f.blocks.items[0].instructions.items[0].call.environment = .{ .constant = .{ .word = 1 } };
    try testing.expectError(error.TypeMismatch, f.validateStructure());
    f.blocks.items[0].instructions.items[0].call.environment = .{ .value = environment };
    f.blocks.items[0].instructions.items[0].call.variadic_start = 0;
    try testing.expectError(error.InvalidEnvironment, f.validateStructure());
}

test "environment use iteration copies target and hidden operand before borrowed arguments" {
    const a: ir.Operand = .{ .value = @fromBackingInt(@as(u32, 7)) };
    const b: ir.Operand = .{ .value = @fromBackingInt(@as(u32, 8)) };
    const c: ir.Operand = .{ .constant = .{ .long = 9 } };
    const argument: ir.CallArgument = .{ .scalar_type = .long, .operand = c };
    for ([_]ir.CallTarget{ .{ .symbol = @fromBackingInt(@as(u32, 0)) }, .{ .address = a } }) |target| {
        for ([_][]const ir.CallArgument{ &.{}, &.{argument} }) |arguments| {
            var instruction: ir.Instruction = .{ .call = .{ .result = null, .callee = target, .environment = b, .arguments = arguments } };
            var iterator = instruction.operands();
            instruction = .{ .copy = .{ .result = @fromBackingInt(@as(u32, 2)), .operand = c } };
            if (target == .address) try testing.expectEqualDeep(a, iterator.next().?);
            try testing.expectEqualDeep(b, iterator.next().?);
            if (arguments.len != 0) try testing.expectEqualDeep(c, iterator.next().?);
            try testing.expect(iterator.next() == null and iterator.next() == null);
        }
    }
}

test "missing environment detection covers unreachable phi terminator projection and call operands" {
    for ([_][]const u8{
        "function l $f(env %e) {\n@e\nret %e\n}",
        "function w $f(env %e) {\n@e\nret %e\n}",
        "function w $f(env %e) {\n@e\nret 42\n@dead\n%x =w copy %e\nret %x\n}",
        "function l $f(env %e) {\n@e\njmp @next\n@next\n%x =l phi @e %e\nret %x\n}",
        "function w $f(env %e) {\n@e\njnz %e, @yes, @no\n@yes\nret 1\n@no\nret 0\n}",
        "function $f(env %e) {\n@e\nret\n@dead\ncall $external(env %e)\nret\n}",
    }) |text| {
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        try testing.expect(module.functions.items[0].usesEnvironment());
        try testing.expectError(error.MissingEnvironment, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{}));
    }
    for ([_][]const u8{ "", "env 9" }) |args| {
        const text = try std.fmt.allocPrint(testing.allocator, "function l $caller() {{\n@e\n%x =l call $f({s})\nret %x\n}}\nfunction l $f(env %e) {{\n@e\nret %e\n}}", .{args});
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        if (args.len == 0) try testing.expectError(error.CallSignatureMismatch, @import("module_validation.zig").validate(testing.allocator, &module)) else try @import("module_validation.zig").validate(testing.allocator, &module);
    }
    var module = try parse(testing.allocator, "function w $caller() {\n@e\n%x =w call $f(w 7)\nret %x\n}\nfunction w $f(env %e, w %p) {\n@e\nret %p\n}");
    defer module.deinit();
    try testing.expectEqual(@as(u32, 7), (try interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{})).?.word);
}

test "environment root and child mappings preserve ordinary argument budgets and refusal precedence" {
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    try testing.expectEqual(@as(u64, 0xffff000000000001), (try interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .environment = 0xffff000000000001 })).?.long);
    try testing.expectEqual(@as(u64, 12), (try interpreter.evaluate(testing.allocator, module.functions.items[1], &.{.{ .long = 5 }}, .{ .environment = 7 })).?.long);
    try testing.expectError(error.ArgumentCountMismatch, interpreter.evaluateModule(testing.allocator, &module, id(1), &.{}, .{}));
    try testing.expectError(error.ArgumentTypeMismatch, interpreter.evaluateModule(testing.allocator, &module, id(1), &.{.{ .word = 5 }}, .{}));
    try testing.expectError(error.MissingEnvironment, interpreter.evaluateModule(testing.allocator, &module, id(1), &.{.{ .long = 5 }}, .{ .max_steps = 0 }));
    try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .max_call_depth = 0 }));
    try testing.expectEqual(@as(u32, 9), (try interpreter.evaluateModule(testing.allocator, &module, id(2), &.{.{ .word = 9 }}, .{})).?.word);
    try testing.expectEqual(@as(u64, 4294967319), (try interpreter.evaluateModule(testing.allocator, &module, id(3), &.{}, .{})).?.long);
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(3), &.{}, .{ .max_steps = 0 }));
    try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(3), &.{}, .{ .max_call_depth = 1 }));
    try testing.expectEqual(@as(u64, 406), (try interpreter.evaluateModule(testing.allocator, &module, id(4), &.{.{ .word = 3 }}, .{ .environment = 100 })).?.long);
    try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(4), &.{.{ .word = 3 }}, .{ .environment = 100, .max_call_depth = 3 }));
    try testing.expectEqual(@as(u32, 0x87654321), (try interpreter.evaluateModule(testing.allocator, &module, id(8), &.{}, .{ .environment = 0x1234567887654321 })).?.word);
    const external = "function $f() {\n@e\ncall $external(env $unknown)\nret\n}";
    var out = try parse(testing.allocator, external);
    defer out.deinit();
    try testing.expectError(error.UnsupportedExternalCall, interpreter.evaluateModule(testing.allocator, &out, id(0), &.{}, .{ .max_call_depth = 1 }));
    try testing.expectError(error.UnsupportedCall, interpreter.evaluate(testing.allocator, out.functions.items[0], &.{}, .{}));
    var address = try parse(testing.allocator, "function $f() {\n@e\ncall 0(env $unknown)\nret\n}");
    defer address.deinit();
    try testing.expectError(error.UnsupportedIndirectCall, interpreter.evaluateModule(testing.allocator, &address, id(0), &.{}, .{}));
}

test "environment memory is synthetic and supplied ignored operands still resolve after earlier writes" {
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    var image = try @import("memory.zig").Image.init(testing.allocator, 32, .{});
    defer image.deinit();
    try testing.expectEqual(@as(?ir.Constant, null), try interpreter.evaluateModule(testing.allocator, &module, id(5), &.{.{ .long = 0x123456789abcdef0 }}, .{ .environment = 65544, .memory_image = &image }));
    try testing.expectEqual(@as(u64, 0x123456789abcdef0), (try image.read(.long, .long, 65544)).long);
    var ignored = try parse(testing.allocator, "function $caller() {\n@e\nstorew 37, 65536\ncall $callee(env $unknown)\nret\n}\nfunction $callee() {\n@e\nret\n}");
    defer ignored.deinit();
    try testing.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(testing.allocator, &ignored, id(0), &.{}, .{ .memory_image = &image }));
    try testing.expectEqual(@as(u32, 37), (try image.read(.unsigned_word, .word, 65536)).word);
    try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &ignored, id(0), &.{}, .{ .memory_image = &image, .max_call_depth = 1 }));
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, fixture);
    defer module.deinit();
    for (module.functions.items) |f| {
        var live = try @import("liveness.zig").Snapshot.init(allocator, f, .{});
        defer live.deinit();
        var graph = try @import("interference.zig").Graph.init(allocator, f, .{});
        defer graph.deinit();
        _ = try @import("optimize.zig").foldIntegerConstants(allocator, f);
    }
    _ = try interpreter.evaluateModule(allocator, &module, id(3), &.{}, .{});
    _ = try interpreter.evaluateModule(allocator, &module, id(4), &.{.{ .word = 3 }}, .{ .environment = 100 });
    var image = try @import("memory.zig").Image.init(allocator, 32, .{});
    defer image.deinit();
    _ = try interpreter.evaluateModule(allocator, &module, id(5), &.{.{ .long = 99 }}, .{ .environment = 65544, .memory_image = &image });
    var refused = try parse(allocator, "function $caller() {\n@e\n%object =l alloc16 16\nstorew 37, 65536\ncall $callee(env $unknown)\nret\n}\nfunction $callee() {\n@e\nret\n}");
    defer refused.deinit();
    if (interpreter.evaluateModule(allocator, &refused, id(0), &.{}, .{ .memory_image = &image, .stack_memory = .{} })) |_| return error.TestExpectedError else |err| switch (err) {
        error.UnsupportedSymbolAddress => {},
        else => return err,
    }
    if (interpreter.evaluateModule(allocator, &module, id(4), &.{.{ .word = 3 }}, .{ .environment = 100, .max_call_depth = 2 })) |_| return error.TestExpectedError else |err| switch (err) {
        error.CallDepthLimitExceeded => {},
        else => return err,
    }
    if (parse(allocator, "function $bad(env %e, env %q) {\n@e\nret\n}")) |parsed| {
        var unexpected = parsed;
        unexpected.deinit();
        return error.TestExpectedError;
    } else |err| switch (err) {
        error.InvalidInput => {},
        else => return err,
    }
    for (emit_options) |option| {
        const assembly = try @import("amd64.zig").emitWithOptions(allocator, &module, option);
        defer allocator.free(assembly);
    }
}
test "all environment parser builder analysis nested interpreter and emitter allocation failures clean up" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
