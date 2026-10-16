//! Cross-pipeline regressions for the deliberately limited direct-call slice.
const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const frontend = @import("frontend.zig");
const source = @import("source.zig");
const amd64 = @import("amd64.zig");
const ssa = @import("ssa.zig");
const interpreter = @import("interpreter.zig");
const optimize = @import("optimize.zig");
const Module = @import("module.zig").Module;
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?source.Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "calls", .text = text }, &diagnostic);
}
const options = [_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true } };

test "call builder owns arguments and allocation failures leave pending results retryable" {
    for (0..2) |failure_offset| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
        var f = ir.Function.init(failing.allocator(), @fromBackingInt(@as(u32, 0)), .long);
        defer f.deinit();
        const b = try f.addBlock(null);
        const result = try f.declareValue(.long);
        var arguments = [_]ir.CallArgument{.{ .scalar_type = .word, .operand = .{ .constant = .{ .word = 7 } } }};
        const callee = f.name;
        failing.fail_index = failing.alloc_index + failure_offset;
        try testing.expectError(error.OutOfMemory, f.defineCall(b, result, callee, &arguments));
        try testing.expect(f.values.items[@backingInt(result)].definition == .pending);
        try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
        failing.fail_index = std.math.maxInt(usize);
        arguments[0].scalar_type = .double;
        try testing.expectError(error.TypeMismatch, f.defineCall(b, result, callee, &arguments));
        try testing.expect(f.values.items[@backingInt(result)].definition == .pending);
        arguments[0].scalar_type = .word;
        try f.defineCall(b, result, callee, &arguments);
        arguments[0].operand = .{ .constant = .{ .word = 99 } };
        try testing.expectEqual(@as(u32, 7), f.blocks.items[0].instructions.items[0].call.arguments[0].operand.constant.word);
        try f.terminate(b, .{ .return_value = .{ .value = result } });
        try f.validateStructure();
        try testing.expectError(error.BlockTerminated, f.defineCall(b, result, callee, &.{}));
        f.values.items[@backingInt(result)].definition.instruction.index = 99;
        try testing.expectError(error.InvalidDefinition, f.validateStructure());
    }
}

test "call operands obey local ordering dominance and exact base-scalar types" {
    const cases = [_][]const u8{
        "function w $f() {\n@e\n%r =w call $g(w %r)\nret %r\n}",
        "function w $f() {\n@e\n%r =w call $g(w %later)\n%later =w copy 1\nret %r\n}",
        "function w $f(w %p) {\n@e\njnz %p, @left, @right\n@left\n%x =w copy 1\njmp @right\n@right\n%r =w call $g(w %x)\nret %r\n}",
    };
    for (cases) |text| {
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        var issue: ?ssa.Issue = null;
        try testing.expectError(error.InvalidSSA, ssa.validate(testing.allocator, module.functions.items[0], &issue));
        try testing.expect(issue.?.site == .instruction);
    }
    const rejected = [_][]const u8{
        "function w $f(s %p) {\n@e\n%r =w call $g(w %p)\nret %r\n}",
        "function w $f(w %p) {\n@e\n%r =w call %p()\nret %r\n}",
        "function w $f() {\n@e\n%r =w call $g(w 1, ...)\nret %r\n}",
        "function w $f() {\n@e\n%r =w call $g(sb 1)\nret %r\n}",
        "function w $f() {\n@e\n%r =w call $g(env 1)\nret %r\n}",
        "function w $f() {\n@e\n%r =w call $g(w 1,)\nret %r\n}",
        "function w $f() {\n@e\n%r =w call $\"quoted\"()\nret %r\n}",
        "function $f(w %p) {\n@e\ncall %p()\nret\n}",
    };
    for (rejected) |text| try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
}

test "native emission checks known call signatures and every callee symbol" {
    const callers = [_][]const u8{
        "function w $f() {\n@e\n%r =w call $g()\nret %r\n}\n",
        "function l $f() {\n@e\n%r =l call $g(w 1)\nret %r\n}\n",
        "function l $f() {\n@e\n%r =l call $g()\nret %r\n}\n",
    };
    for (callers) |caller| {
        const text = try std.mem.concat(testing.allocator, u8, &.{ caller, "function l $g(l %p) {\n@e\nret %p\n}" });
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        for (options) |option| try testing.expectError(error.CallSignatureMismatch, amd64.emitWithOptions(testing.allocator, &module, option));
    }
    var module = try parse(testing.allocator, "function w $f() {\n@e\n%r =w call $external()\nret %r\n}");
    defer module.deinit();
    const call = &module.functions.items[0].blocks.items[0].instructions.items[0].call;
    call.callee = .{ .symbol = @fromBackingInt(std.math.maxInt(u32)) };
    try testing.expectError(error.InvalidSymbol, amd64.emit(testing.allocator, &module));
    call.callee = .{ .symbol = try module.symbols.intern("bad;symbol") };
    try testing.expectError(error.InvalidSymbol, amd64.emit(testing.allocator, &module));
}

test "call effects survive folding and evaluator reports reached calls with budget precedence" {
    var module = try parse(testing.allocator, "function w $f(w %p) {\n@e\njnz %p, @call, @done\n@call\n%unused =w call $effect()\nret 9\n@done\nret 7\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    try testing.expectEqual(@as(usize, 0), try optimize.foldIntegerConstants(testing.allocator, f));
    try testing.expect(f.blocks.items[1].instructions.items[0] == .call);
    try testing.expectEqual(@as(u32, 7), (try interpreter.evaluate(testing.allocator, f, &.{.{ .word = 0 }}, .{})).?.word);
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluate(testing.allocator, f, &.{.{ .word = 1 }}, .{ .max_steps = 1 }));
    try testing.expectError(error.UnsupportedCall, interpreter.evaluate(testing.allocator, f, &.{.{ .word = 1 }}, .{ .max_steps = 2 }));
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, @embedFile("fixtures/direct-calls.ssa"));
    defer module.deinit();
    for (module.functions.items) |f| {
        var live = try @import("liveness.zig").Snapshot.init(allocator, f, .{});
        defer live.deinit();
        var graph = try @import("interference.zig").Graph.init(allocator, f, .{});
        defer graph.deinit();
        _ = try optimize.foldIntegerConstants(allocator, f);
    }
    for (options) |option| {
        const assembly = try amd64.emitWithOptions(allocator, &module, option);
        defer allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "\tcall increment\n") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "\tcall external_identity\n") != null);
    }
}
test "owned call arguments and complete call pipelines clean every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

test "outgoing call stack participates in the frame cap even without value homes" {
    var module = Module.init(testing.allocator);
    defer module.deinit();
    const id = try module.addFunction("large_call", .word);
    const f = module.getFunction(id).?;
    const b = try f.addBlock(null);
    const result = try f.declareValue(.word);
    const callee = try module.symbols.intern("external");
    const arguments = try testing.allocator.alloc(ir.CallArgument, 8300);
    defer testing.allocator.free(arguments);
    @memset(arguments, .{ .scalar_type = .word, .operand = .{ .constant = .{ .word = 1 } } });
    try f.defineCall(b, result, callee, arguments);
    try f.terminate(b, .{ .return_value = .{ .value = result } });
    for (options) |option| try testing.expectError(error.FrameTooLarge, amd64.emitWithOptions(testing.allocator, &module, option));
}

test "all module bodies are validated before known call signature traversal" {
    var module = try parse(testing.allocator, "function w $f() {\n@e\n%r =w call $g(w 1)\nret %r\n}\nfunction w $g(w %p) {\n@e\nret %p\n}");
    defer module.deinit();
    module.functions.items[1].parameters.items[0] = @fromBackingInt(std.math.maxInt(u32));
    for (options) |option| try testing.expectError(error.InvalidValue, amd64.emitWithOptions(testing.allocator, &module, option));
}

test "outgoing stack area is aligned and disjoint from homes phi scratch and saved originals" {
    var module = try parse(testing.allocator, "function l $f(l %a) {\n@entry\njmp @join\n@join\n%x =l phi @entry %a\n%r =l call $external(l %x, l 2, l 3, l 4, l 5, l 6, l 7, l 8)\n%sum =l add %r, %x\nret %sum\n}");
    defer module.deinit();
    for (options) |option| {
        const assembly = try amd64.emitWithOptions(testing.allocator, &module, option);
        defer testing.allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "movq %rax, 0(%rsp)") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "movq %rax, 8(%rsp)") != null);
        // Frame upper region always has at least two simultaneous value homes
        // (or saved originals) and one phi scratch slot; lower region adds 16.
        try testing.expect(std.mem.indexOf(u8, assembly, if (option.callee_saved_homes or option.reuse_stack_homes) "subq $48, %rsp" else "subq $64, %rsp") != null);
        const phi_store: []const u8 = if (option.callee_saved_homes) "movq %rax, -8(%rbp)" else if (option.reuse_stack_homes) "movq %rax, -24(%rbp)" else "movq %rax, -40(%rbp)";
        try testing.expect(std.mem.indexOf(u8, assembly, phi_store) != null);
    }
}
