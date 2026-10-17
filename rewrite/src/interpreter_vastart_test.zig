const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const Module = @import("module.zig").Module;
const interpreter = @import("interpreter.zig");
const synthetic = @import("evaluation_memory.zig");
const Image = @import("memory.zig").Image;
const base: u64 = 0x100000000;
const types = [_]ir.ScalarType{ .word, .long, .single, .double };
const readers =
    "function w $w(...) {\n@e\nvastart 65536\n%r =w vaarg 65536\nret %r\n}\n" ++
    "function l $l(...) {\n@e\nvastart 65536\n%r =l vaarg 65536\nret %r\n}\n" ++
    "function s $s(...) {\n@e\nvastart 65536\n%r =s vaarg 65536\nret %r\n}\n" ++
    "function d $d(...) {\n@e\nvastart 65536\n%r =d vaarg 65536\nret %r\n}\n";
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "interpreter-vastart", .text = text }, &diagnostic);
}
fn id(index: usize) @import("module.zig").FunctionId {
    return @fromBackingInt(@as(u32, @intCast(index)));
}
fn constant(ty: ir.ScalarType, raw: u64) ir.Constant {
    return switch (ty) {
        .word => .{ .word = @truncate(raw) },
        .long => .{ .long = raw },
        .single => .{ .single_bits = @truncate(raw) },
        .double => .{ .double_bits = raw },
    };
}
fn bits(value: ir.Constant) u64 {
    return switch (value) {
        .word => |v| v,
        .long => |v| v,
        .single_bits => |v| v,
        .double_bits => |v| v,
    };
}
fn width(ty: ir.ScalarType) usize {
    return if (ty == .word or ty == .single) 4 else 8;
}
fn loadKind(ty: ir.ScalarType) ir.LoadKind {
    return switch (ty) {
        .word => .unsigned_word,
        .long => .long,
        .single => .single,
        .double => .double,
    };
}
fn expectedDescriptor(bytes: []u8, endian: std.builtin.Endian, gp: u32, fp: u32, overflow: u64, save: u64) void {
    std.mem.writeInt(u32, bytes[0..4], gp, endian);
    std.mem.writeInt(u32, bytes[4..8], fp, endian);
    std.mem.writeInt(u64, bytes[8..16], overflow, endian);
    std.mem.writeInt(u64, bytes[16..24], save, endian);
}

test "root-only explicit tails preserve all four raw classes across entry APIs and independently mixed endians" {
    var module = try parse(testing.allocator, readers);
    defer module.deinit();
    for ([_]std.builtin.Endian{ .little, .big }) |image_endian| for ([_]std.builtin.Endian{ .little, .big }) |stack_endian| {
        var image = try Image.init(testing.allocator, 32, .{ .endian = image_endian });
        defer image.deinit();
        for (types, 0..) |ty, index| for ([_]u64{ 0, 0x80000000, 0x7f800001, 0x8000000000000000, 0x7ff0000000000001, 0xffffffffffffffff }) |raw| for ([_]bool{ false, true }) |as_module| {
            @memset(image.bytes, 0xa5);
            const tail = [_]ir.Constant{constant(ty, raw)};
            const options: interpreter.Options = .{ .root_variadic_arguments = &tail, .consume_vaargs = true, .stack_memory = .{ .endian = stack_endian }, .memory_image = &image };
            const value = if (as_module) (try interpreter.evaluateModule(testing.allocator, &module, id(index), &.{}, options)).? else (try interpreter.evaluate(testing.allocator, module.functions.items[index], &.{}, options)).?;
            try testing.expectEqual(ty, value.scalarType());
            try testing.expectEqual(bits(tail[0]), bits(value));
            var expected: [32]u8 = @splat(0xa5);
            expectedDescriptor(&expected, image_endian, if (ty.isInteger()) 8 else 0, if (ty.isInteger()) 48 else 64, base + 176, base);
            try testing.expectEqualSlices(u8, &expected, image.bytes);
        };
    };
}

test "synthetic save layout matches independent bank slots named overflow prefix and poisoned padding" {
    for ([_]std.builtin.Endian{ .little, .big }) |endian| for (0..8) |gp_count| for (0..10) |fp_count| {
        var image = try Image.init(testing.allocator, 32, .{ .endian = endian });
        defer image.deinit();
        @memset(image.bytes, 0xa5);
        var space = try synthetic.Space.init(testing.allocator, &image, .{ .endian = endian });
        defer space.deinit();
        var named: [16]ir.Constant = undefined;
        for (named[0..gp_count], 0..) |*value, i| value.* = .{ .word = @intCast(i + 100) };
        for (named[gp_count..][0..fp_count], 0..) |*value, i| value.* = .{ .double_bits = 0x7ff0000000000001 + i };
        var tail: [20]ir.Constant = undefined;
        for (&tail, 0..) |*value, i| value.* = constant(types[i % 4], 0x8000000080000000 + i);
        var state: ?synthetic.VariadicState = null;
        try space.startVaArgs(&state, image.base, named[0 .. gp_count + fp_count], &tail);
        const named_overflow: usize = (gp_count - @min(gp_count, @as(usize, 6))) + (fp_count - @min(fp_count, @as(usize, 8)));
        var expected: [32]u8 = @splat(0xa5);
        expectedDescriptor(&expected, endian, @as(u32, @intCast(@min(gp_count, 6))) * 8, 48 + @as(u32, @intCast(@min(fp_count, 8))) * 16, base + 176 + named_overflow * 8, base);
        try testing.expectEqualSlices(u8, &expected, image.bytes);
        var gp: usize = 0;
        var fp: usize = 0;
        var overflow: usize = 0;
        for ([_][]const ir.Constant{ named[0 .. gp_count + fp_count], &tail }) |arguments| for (arguments) |value| {
            const ty = value.scalarType();
            const offset: usize = if (ty.isInteger() and gp < 6) offset: {
                defer gp += 1;
                break :offset gp * 8;
            } else if (!ty.isInteger() and fp < 8) offset: {
                defer fp += 1;
                break :offset 48 + fp * 16;
            } else offset: {
                defer overflow += 1;
                break :offset 176 + overflow * 8;
            };
            try testing.expectEqual(bits(value), bits(try space.read(loadKind(ty), ty, base + offset)));
            if (width(ty) == 4 or (offset >= 48 and offset < 176)) try testing.expectError(error.UninitializedMemory, space.read(.unsigned_byte, .word, base + offset + width(ty)));
        };
        try testing.expectEqual(@as(usize, 1), space.mark());
        try testing.expectEqual(@as(usize, ((176 + overflow * 8 + 15) & ~@as(usize, 15)) + 16), space.used);
    };
}

test "root vastart capability exact named arity budgets and configuration preserve default refusals" {
    var module = try parse(testing.allocator, readers ++ "function w $safe(w %p, ...) {\n@e\nret %p\n}\nfunction w $normal(w %p) {\n@e\nret %p\n}\nfunction $symbol(...) {\n@e\nvastart $unknown\nret\n}\n");
    defer module.deinit();
    var image = try Image.init(testing.allocator, 24, .{});
    defer image.deinit();
    const empty: []const ir.Constant = &.{};
    try testing.expectError(error.UnsupportedVariadicOperation, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .memory_image = &image, .stack_memory = .{}, .consume_vaargs = true }));
    try testing.expectError(error.UnsupportedVariadicOperation, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .memory_image = &image, .stack_memory = .{}, .root_variadic_arguments = empty }));
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .max_steps = 0, .root_variadic_arguments = empty }));
    try testing.expectError(error.UnsupportedMemory, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .root_variadic_arguments = empty }));
    try testing.expectError(error.UnsupportedAllocation, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .root_variadic_arguments = empty, .memory_image = &image }));
    try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .max_call_depth = 0, .root_variadic_arguments = empty }));
    try testing.expectEqual(@as(u32, 42), (try interpreter.evaluateModule(testing.allocator, &module, id(4), &.{.{ .word = 42 }}, .{ .root_variadic_arguments = &.{.{ .long = 99 }} })).?.word);
    try testing.expectError(error.ArgumentCountMismatch, interpreter.evaluateModule(testing.allocator, &module, id(4), &.{ .{ .word = 42 }, .{ .long = 99 } }, .{ .root_variadic_arguments = empty }));
    try testing.expectError(error.ArgumentTypeMismatch, interpreter.evaluateModule(testing.allocator, &module, id(5), &.{.{ .long = 42 }}, .{ .root_variadic_arguments = empty }));
    try testing.expectError(error.UnexpectedVariadicArguments, interpreter.evaluateModule(testing.allocator, &module, id(5), &.{.{ .word = 42 }}, .{ .root_variadic_arguments = empty, .max_steps = 0 }));
    try testing.expectError(error.UnsupportedVariadicOperation, interpreter.evaluateModule(testing.allocator, &module, id(6), &.{}, .{ .consume_vaargs = true }));
    try testing.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(testing.allocator, &module, id(6), &.{}, .{ .root_variadic_arguments = empty }));
}

test "vastart reset and copied descriptors share root source across child frame growth without rematerializing" {
    var module = try parse(testing.allocator, "function l $read(l %list, w %depth) {\n@e\njnz %depth, @again, @done\n@again\n%n =w sub %depth, 1\n%r =l call $read(l %list, w %n)\nret %r\n@done\n%v =l vaarg %list\nret %v\n}\n" ++
        "function l $root(...) {\n@e\nvastart 65536\nblit 65536, 65568, 24\n%a =l call $read(l 65536, w 70)\n%b =l vaarg 65568\n%save =l loadl 65552\nstorel 99, %save\nvastart 65536\n%c =l vaarg 65536\n%sum =l add %a, %b\n%r =l add %sum, %c\nret %r\n}\n");
    defer module.deinit();
    for (module.functions.items) |f| _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
    for ([_]std.builtin.Endian{ .little, .big }) |endian| {
        var image = try Image.init(testing.allocator, 64, .{ .endian = endian });
        defer image.deinit();
        try testing.expectEqual(@as(u64, 121), (try interpreter.evaluateModule(testing.allocator, &module, id(1), &.{}, .{ .root_variadic_arguments = &.{.{ .long = 11 }}, .consume_vaargs = true, .stack_memory = .{ .max_bytes = 192, .endian = endian }, .memory_image = &image, .max_call_depth = 80 })).?.long);
        try testing.expectEqual(@as(u32, 8), std.mem.readInt(u32, image.bytes[0..4], endian));
        try testing.expectEqual(@as(u32, 8), std.mem.readInt(u32, image.bytes[32..36], endian));
        try testing.expectEqual(@as(u64, base), std.mem.readInt(u64, image.bytes[48..56], endian));
        try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(1), &.{}, .{ .root_variadic_arguments = &.{.{ .long = 11 }}, .consume_vaargs = true, .stack_memory = .{}, .memory_image = &image, .max_call_depth = 1 }));
    }
}

test "root descriptor complete-span atomicity guards capacity and source holes keep earlier Image writes" {
    var module = try parse(testing.allocator, "function $f(l %p, ...) {\n@e\nstorew 77, 65536\nvastart %p\nret\n}\n" ++ readers);
    defer module.deinit();
    var image = try Image.init(testing.allocator, 32, .{});
    defer image.deinit();
    for ([_]u64{ image.base + 9, std.math.maxInt(u64) - 7, 0 }) |address| {
        @memset(image.bytes, 0xa5);
        try testing.expectError(error.MemoryOutOfBounds, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{.{ .long = address }}, .{ .root_variadic_arguments = &.{}, .memory_image = &image }));
        var expected: [32]u8 = @splat(0xa5);
        std.mem.writeInt(u32, expected[0..4], 77, .little);
        try testing.expectEqualSlices(u8, &expected, image.bytes);
    }
    @memset(image.bytes, 0xa5);
    try testing.expectError(error.StackLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{.{ .long = image.base + 8 }}, .{ .root_variadic_arguments = &.{}, .memory_image = &image, .stack_memory = .{ .max_bytes = 191 } }));
    try testing.expectEqual(@as(u8, 0xa5), image.bytes[8]);
    try testing.expectError(error.UninitializedMemory, interpreter.evaluateModule(testing.allocator, &module, id(2), &.{}, .{ .root_variadic_arguments = &.{}, .memory_image = &image, .stack_memory = .{}, .consume_vaargs = true }));
    try testing.expectEqual(@as(u32, 8), std.mem.readInt(u32, image.bytes[0..4], .little));
    var space = try synthetic.Space.init(testing.allocator, null, .{});
    defer space.deinit();
    const first = try space.allocate(16);
    _ = try space.allocate(16);
    var state: ?synthetic.VariadicState = null;
    const before = space.used;
    try testing.expectError(error.MemoryOutOfBounds, space.startVaArgs(&state, first, &.{}, &.{}));
    try testing.expectEqual(before, space.used);
    try testing.expect(state == null);
    try testing.expectError(error.UninitializedMemory, space.read(.long, .long, first));
}

test "root named narrow metadata and interleaved exhausted banks consume exact overflow sequence" {
    var module = try parse(testing.allocator, "function l $f(sb %a, ub %b, sh %c, uh %d, w %e, l %f, w %g, d %x0, d %x1, d %x2, d %x3, d %x4, d %x5, d %x6, d %x7, s %x8, ...) {\n@e\nvastart 65536\n%a0 =l vaarg 65536\n%a1 =d vaarg 65536\n%a2 =w vaarg 65536\n%a3 =s vaarg 65536\nstorel %a0, 65568\nstored %a1, 65576\nstorew %a2, 65584\nstores %a3, 65592\n%small =w extsb %a\n%r =l extsw %small\nret %r\n}\n");
    defer module.deinit();
    var named: [16]ir.Constant = undefined;
    for (named[0..5]) |*v| v.* = .{ .word = 0xa5a5a580 };
    named[5] = .{ .long = 123 };
    named[6] = .{ .word = 456 };
    for (named[7..15]) |*v| v.* = .{ .double_bits = 0 };
    named[15] = .{ .single_bits = 0x7f800001 };
    const tail = [_]ir.Constant{ .{ .long = 0xffffffffffffffff }, .{ .double_bits = 0x7ff0000000000001 }, .{ .word = 0x80000000 }, .{ .single_bits = 0x80000000 } };
    for ([_]std.builtin.Endian{ .little, .big }) |endian| {
        var image = try Image.init(testing.allocator, 64, .{ .endian = endian });
        defer image.deinit();
        @memset(image.bytes, 0xa5);
        try testing.expectEqual(@as(u64, @bitCast(@as(i64, -128))), (try interpreter.evaluateModule(testing.allocator, &module, id(0), &named, .{ .root_variadic_arguments = &tail, .consume_vaargs = true, .memory_image = &image, .stack_memory = .{ .endian = endian, .max_bytes = 240 } })).?.long);
        var expected: [64]u8 = @splat(0xa5);
        expectedDescriptor(&expected, endian, 48, 176, base + 224, base);
        std.mem.writeInt(u64, expected[32..40], 0xffffffffffffffff, endian);
        std.mem.writeInt(u64, expected[40..48], 0x7ff0000000000001, endian);
        std.mem.writeInt(u32, expected[48..52], 0x80000000, endian);
        std.mem.writeInt(u32, expected[56..60], 0x80000000, endian);
        try testing.expectEqualSlices(u8, &expected, image.bytes);
    }
}

test "root globals descriptors reset and do not authorize internal variadic or host calls" {
    var module = try parse(testing.allocator, "data $list = { z 24 }\nfunction l $global(...) {\n@e\nvastart $list\n%r =l vaarg $list\nret %r\n}\n" ++
        "function $callee(...) {\n@e\nret\n}\nfunction $caller(...) {\n@e\ncall $callee(..., l $missing)\nret\n}\nfunction $external(...) {\n@e\ncall $missing(...)\nret\n}\n");
    defer module.deinit();
    for ([_]std.builtin.Endian{ .little, .big }) |endian| for (0..2) |_| {
        try testing.expectEqual(@as(u64, 42), (try interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .root_variadic_arguments = &.{.{ .long = 42 }}, .consume_vaargs = true, .stack_memory = .{}, .global_memory = .{ .endian = endian } })).?.long);
    };
    try testing.expectEqual(@as(u64, 24), module.data.items[0].items.items[0].zero);
    try testing.expectError(error.UnsupportedVariadicCall, interpreter.evaluateModule(testing.allocator, &module, id(2), &.{}, .{ .root_variadic_arguments = &.{}, .max_call_depth = 1 }));
    try testing.expectError(error.UnsupportedExternalCall, interpreter.evaluateModule(testing.allocator, &module, id(3), &.{}, .{ .root_variadic_arguments = &.{} }));
    try testing.expectError(error.UnsupportedCall, interpreter.evaluate(testing.allocator, module.functions.items[2], &.{}, .{ .root_variadic_arguments = &.{} }));
}

test "root overflow extent raw-width mismatches and step limits retain initialized descriptor effects" {
    var module = try parse(testing.allocator, "function $f(l %a, l %b, l %c, l %d, l %e, l %f, ...) {\n@e\nvastart 65536\n%x =l vaarg 65536\n%y =l vaarg 65536\nret\n}\nfunction l $stack(...) {\n@e\n%list =l alloc16 24\nvastart %list\n%r =l vaarg %list\nret %r\n}\n");
    defer module.deinit();
    var image = try Image.init(testing.allocator, 32, .{});
    defer image.deinit();
    const named: [6]ir.Constant = @splat(.{ .long = 0 });
    @memset(image.bytes, 0xa5);
    try testing.expectError(error.MemoryOutOfBounds, interpreter.evaluateModule(testing.allocator, &module, id(0), &named, .{ .root_variadic_arguments = &.{.{ .long = 42 }}, .consume_vaargs = true, .memory_image = &image, .stack_memory = .{ .max_bytes = 208 } }));
    var expected: [32]u8 = @splat(0xa5);
    expectedDescriptor(&expected, .little, 48, 48, base + 192, base);
    try testing.expectEqualSlices(u8, &expected, image.bytes);
    @memset(image.bytes, 0xa5);
    try testing.expectError(error.UninitializedMemory, interpreter.evaluateModule(testing.allocator, &module, id(0), &named, .{ .root_variadic_arguments = &.{.{ .word = 42 }}, .consume_vaargs = true, .memory_image = &image, .stack_memory = .{} }));
    expectedDescriptor(&expected, .little, 48, 48, base + 184, base);
    try testing.expectEqualSlices(u8, &expected, image.bytes);
    @memset(image.bytes, 0xa5);
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &named, .{ .root_variadic_arguments = &.{.{ .long = 42 }}, .consume_vaargs = true, .memory_image = &image, .stack_memory = .{}, .max_steps = 1 }));
    expectedDescriptor(&expected, .little, 48, 48, base + 176, base);
    try testing.expectEqualSlices(u8, &expected, image.bytes);
    try testing.expectError(error.MemoryOutOfBounds, interpreter.evaluateModule(testing.allocator, &module, id(0), &named, .{ .root_variadic_arguments = &.{}, .consume_vaargs = true, .memory_image = &image, .stack_memory = .{ .max_bytes = 192 } }));
    try testing.expectEqual(@as(u64, base + 184), std.mem.readInt(u64, image.bytes[8..16], .little));
    for ([_]std.builtin.Endian{ .little, .big }) |endian| {
        try testing.expectEqual(@as(u64, 42), (try interpreter.evaluateModule(testing.allocator, &module, id(1), &.{}, .{ .root_variadic_arguments = &.{.{ .long = 42 }}, .consume_vaargs = true, .stack_memory = .{ .endian = endian, .max_bytes = 240 } })).?.long);
    }
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, readers ++ "data $list = { z 24 }\nfunction l $global(...) {\n@e\n%local =l alloc8 8\nstorel 7, %local\nvastart $list\n%r =l call $child(l $list)\nret %r\n}\nfunction $fault(...) {\n@e\nvastart 65536\n%x =l vaarg 65536\n%y =l vaarg 65536\nret\n}\nfunction l $child(l %list) {\n@e\n%local =l alloc8 8\nstorel 9, %local\n%r =l vaarg %list\nret %r\n}\n");
    defer module.deinit();
    var image = try Image.init(allocator, 24, .{});
    defer image.deinit();
    _ = try interpreter.evaluateModule(allocator, &module, id(1), &.{}, .{ .root_variadic_arguments = &.{.{ .long = 42 }}, .consume_vaargs = true, .stack_memory = .{}, .memory_image = &image });
    _ = try interpreter.evaluateModule(allocator, &module, id(4), &.{}, .{ .root_variadic_arguments = &.{.{ .long = 42 }}, .consume_vaargs = true, .stack_memory = .{}, .global_memory = .{} });
    if (interpreter.evaluateModule(allocator, &module, id(5), &.{}, .{ .root_variadic_arguments = &.{.{ .long = 42 }}, .consume_vaargs = true, .stack_memory = .{}, .global_memory = .{}, .memory_image = &image })) |_| return error.ExpectedUninitialized else |err| {
        if (err != error.UninitializedMemory) return err;
    }
    if (std.mem.readInt(u32, image.bytes[0..4], .little) != 16) return error.ExpectedCursorWrite;
}
test "root variadic backing objects frames globals and retained later-error writes clean up every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
