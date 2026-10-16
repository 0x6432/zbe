const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const frontend = @import("frontend.zig");
const source = @import("source.zig");
const interpreter = @import("interpreter.zig");
const amd64 = @import("amd64.zig");
const entry: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 0));
const options = [_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true } };
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?source.Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "memory", .text = text }, &diagnostic);
}

test "memory access kinds validate exact scalar classes and store effects have no definitions" {
    for (std.enums.values(ir.LoadKind)) |kind| for (std.enums.values(ir.ScalarType)) |ty| {
        var f = ir.Function.init(testing.allocator, @fromBackingInt(@as(u32, 0)), null);
        defer f.deinit();
        const b = try f.addBlock(null);
        const result = try f.declareValue(ty);
        const address: ir.Operand = .{ .constant = .{ .long = 0 } };
        if (kind.accepts(ty)) {
            try f.defineLoad(b, result, kind, address);
            try f.terminate(b, .{ .return_value = null });
            try f.validateStructure();
            f.blocks.items[0].instructions.items[0].load.address = .{ .constant = .{ .word = 0 } };
            try testing.expectError(error.TypeMismatch, f.validateStructure());
        } else {
            try testing.expectError(error.TypeMismatch, f.defineLoad(b, result, kind, address));
            try testing.expect(f.values.items[0].definition == .pending);
            try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
        }
    };
    for (std.enums.values(ir.StoreKind)) |kind| for ([_]ir.Constant{ .{ .word = 1 }, .{ .long = 1 }, .{ .single_bits = 1 }, .{ .double_bits = 1 } }) |value| {
        var f = ir.Function.init(testing.allocator, @fromBackingInt(@as(u32, 0)), null);
        defer f.deinit();
        const b = try f.addBlock(null);
        const address: ir.Operand = .{ .constant = .{ .long = 0 } };
        if (kind.valueType() == value.scalarType()) {
            try f.appendStore(b, kind, .{ .constant = value }, address);
            try testing.expectEqual(@as(?ir.ValueId, null), f.blocks.items[0].instructions.items[0].result());
            try testing.expectEqual(@as(usize, 0), f.values.items.len);
            try f.terminate(b, .{ .return_value = null });
            try f.validateStructure();
            f.blocks.items[0].instructions.items[0].store.address = .{ .constant = .{ .word = 0 } };
            try testing.expectError(error.TypeMismatch, f.validateStructure());
        } else try testing.expectError(error.TypeMismatch, f.appendStore(b, kind, .{ .constant = value }, address));
    };
}

test "load store builders retain pending state across allocation failure and reject closed blocks" {
    for ([_]bool{ false, true }) |load| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
        var f = ir.Function.init(failing.allocator(), @fromBackingInt(@as(u32, 0)), null);
        defer f.deinit();
        const b = try f.addBlock(null);
        const result = if (load) try f.declareValue(.word) else null;
        const address: ir.Operand = .{ .constant = .{ .long = 0 } };
        const value: ir.Operand = .{ .constant = .{ .word = 42 } };
        failing.fail_index = failing.alloc_index;
        if (result) |r| {
            try testing.expectError(error.OutOfMemory, f.defineLoad(b, r, .signed_byte, address));
            try testing.expect(f.values.items[0].definition == .pending);
        } else try testing.expectError(error.OutOfMemory, f.appendStore(b, .byte, value, address));
        try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
        failing.fail_index = std.math.maxInt(usize);
        if (result) |r| {
            try testing.expectError(error.TypeMismatch, f.defineLoad(b, r, .long, address));
            try f.defineLoad(b, r, .signed_byte, address);
        } else try f.appendStore(b, .byte, value, address);
        try f.terminate(b, .{ .return_value = null });
        if (result) |r| {
            try testing.expectError(error.BlockTerminated, f.defineLoad(b, r, .signed_byte, address));
        } else try testing.expectError(error.BlockTerminated, f.appendStore(b, .byte, value, address));
        try f.validateStructure();
    }
}

test "frontend accepts all memory spellings and rejects invalid classes and arity" {
    for ([_][]const u8{ "loadsb", "loadub", "loadsh", "loaduh", "loadsw", "loaduw", "loadw" }) |op| for ([_][]const u8{ "w", "l" }) |ty| {
        const text = try std.fmt.allocPrint(testing.allocator, "function {s} $f(l %p) {{\n@e\n%x ={s} {s} %p\nret %x\n}}", .{ ty, ty, op });
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        try @import("module_validation.zig").validate(testing.allocator, &module);
    };
    const text = "function $f(l %p) {\n@e\n%l =l loadl %p\n%s =s loads %p\n%d =d loadd %p\nstoreb 1, %p\nstoreh 2, %p\nstorew 3, %p\nstorel %l, %p\nstores %s, %p\nstored %d, %p\nret\n}";
    var module = try parse(testing.allocator, text);
    defer module.deinit();
    try @import("module_validation.zig").validate(testing.allocator, &module);
    for ([_][]const u8{
        "function w $f(w %p) {\n@e\n%x =w loadw %p\nret %x\n}",
        "function s $f() {\n@e\n%x =s loadsb 0\nret %x\n}",
        "function w $f() {\n@e\n%x =w loadl 0\nret %x\n}",
        "function $f(s %v) {\n@e\nstoreb %v, 0\nret\n}",
        "function $f(w %p) {\n@e\nstorew 1, %p\nret\n}",
        "function $f() {\n@e\nstorew 1\nret\n}",
        "function w $f() {\n@e\n%x =w loadw 0, 1\nret %x\n}",
        "function $f() {\n@e\nret\nstoreb 1, 0\n}",
    }) |invalid| try testing.expectError(error.InvalidInput, parse(testing.allocator, invalid));
}

test "memory uses obey SSA ordering and dominance and remain live across edges" {
    for ([_][]const u8{
        "function w $f() {\n@e\n%x =w loadw %p\n%p =l copy 0\nret %x\n}",
        "function $f() {\n@e\nstorel %p, %p\n%p =l copy 0\nret\n}",
        "function $f(w %c) {\n@e\njnz %c, @a, @b\n@a\n%p =l copy 0\njmp @b\n@b\nstoreb 1, %p\nret\n}",
        "function $f() {\n@e\nstorew %v, 0\n%v =w copy 1\nret\n}",
    }) |text| {
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        var issue: ?@import("ssa.zig").Issue = null;
        try testing.expectError(error.InvalidSSA, @import("ssa.zig").validate(testing.allocator, module.functions.items[0], &issue));
        try testing.expect(issue.?.site == .instruction);
    }
    var module = try parse(testing.allocator, @embedFile("fixtures/scalar-memory.ssa"));
    defer module.deinit();
    const f = module.functions.items[0];
    var live = try @import("liveness.zig").Snapshot.init(testing.allocator, f, .{});
    defer live.deinit();
    for (f.parameters.items) |parameter| try testing.expect(live.isLiveOut(@fromBackingInt(@as(u32, 0)), parameter).?);
    _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
    try testing.expect(f.blocks.items[1].instructions.items[0] == .store);
    try testing.expect(f.blocks.items[1].instructions.items[1] == .load);
}

test "evaluators refuse reached memory after its step without dereferencing numeric addresses" {
    var module = try parse(testing.allocator, @embedFile("fixtures/scalar-memory.ssa"));
    defer module.deinit();
    const path: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 1));
    try testing.expectEqual(@as(u32, 42), (try interpreter.evaluateModule(testing.allocator, &module, path, &.{ .{ .word = 0 }, .{ .long = 0 } }, .{})).?.word);
    try testing.expectError(error.UnsupportedMemory, interpreter.evaluateModule(testing.allocator, &module, path, &.{ .{ .word = 1 }, .{ .long = 0 } }, .{}));
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, path, &.{ .{ .word = 1 }, .{ .long = 0 } }, .{ .max_steps = 1 }));
    for ([_][]const u8{ "function w $f() {\n@e\n%x =w loadw 0\nret %x\n}", "function $f() {\n@e\nstorel 0, 0\nret\n}" }) |text| {
        var literal = try parse(testing.allocator, text);
        defer literal.deinit();
        try testing.expectError(error.UnsupportedMemory, interpreter.evaluate(testing.allocator, literal.functions.items[0], &.{}, .{}));
        try testing.expectError(error.UnsupportedMemory, interpreter.evaluateModule(testing.allocator, &literal, entry, &.{}, .{}));
        try testing.expectError(error.StepLimitExceeded, interpreter.evaluate(testing.allocator, literal.functions.items[0], &.{}, .{ .max_steps = 0 }));
    }
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, @embedFile("fixtures/scalar-memory.ssa"));
    defer module.deinit();
    for (module.functions.items) |f| {
        var graph = try @import("interference.zig").Graph.init(allocator, f, .{});
        defer graph.deinit();
        _ = try @import("optimize.zig").foldIntegerConstants(allocator, f);
    }
    for (options) |option| {
        const assembly = try amd64.emitWithOptions(allocator, &module, option);
        defer allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "movb %al, (%r10)") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "movsbq (%r10), %rax") != null);
    }
    if (interpreter.evaluateModule(allocator, &module, entry, &.{ .{ .long = 0 }, .{ .word = 1 }, .{ .word = 7 } }, .{})) |_| return error.ExpectedMemoryRejection else |err| {
        if (err != error.UnsupportedMemory) return err;
    }
}
test "memory parsing analyses folding emission and evaluator refusal clean up all allocation failures" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
