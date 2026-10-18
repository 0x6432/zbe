const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const Module = @import("module.zig").Module;
const interpreter = @import("interpreter.zig");
const Image = @import("memory.zig").Image;
const base: u64 = 0x100000000;
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "internal-variadic", .text = text }, &diagnostic);
}
fn id(index: usize) @import("module.zig").FunctionId {
    return @fromBackingInt(@as(u32, @intCast(index)));
}
fn descriptor(bytes: []u8, endian: std.builtin.Endian, gp: u32, fp: u32, overflow: u64, save: u64) void {
    std.mem.writeInt(u32, bytes[0..4], gp, endian);
    std.mem.writeInt(u32, bytes[4..8], fp, endian);
    std.mem.writeInt(u64, bytes[8..16], overflow, endian);
    std.mem.writeInt(u64, bytes[16..24], save, endian);
}
const simple = "function l $entry() {\n@e\n%r =l call $child(..., l 42)\nret %r\n}\n" ++
    "function l $child(...) {\n@e\nvastart 65536\n%r =l vaarg 65536\nret %r\n}\n";

test "internal variadic dispatch is independent opt-in and preserves default refusal and step depth order" {
    var module = try parse(testing.allocator, simple);
    defer module.deinit();
    var image = try Image.init(testing.allocator, 32, .{});
    defer image.deinit();
    try testing.expectError(error.UnsupportedVariadicCall, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .memory_image = &image, .stack_memory = .{}, .consume_vaargs = true, .max_call_depth = 1 }));
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .internal_variadic_calls = true, .max_steps = 0, .max_call_depth = 1 }));
    try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .internal_variadic_calls = true, .max_steps = 1, .max_call_depth = 1 }));
    try testing.expectError(error.UnsupportedCall, interpreter.evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .internal_variadic_calls = true }));
    try testing.expectError(error.UnsupportedVariadicOperation, interpreter.evaluateModule(testing.allocator, &module, id(1), &.{}, .{ .internal_variadic_calls = true, .memory_image = &image, .stack_memory = .{} }));
    try testing.expectError(error.UnsupportedMemory, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .internal_variadic_calls = true }));
    try testing.expectError(error.UnsupportedAllocation, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .internal_variadic_calls = true, .memory_image = &image }));
    @memset(image.bytes, 0xa5);
    try testing.expectError(error.UnsupportedVariadicOperation, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .internal_variadic_calls = true, .memory_image = &image, .stack_memory = .{} }));
    var expected: [32]u8 = @splat(0xa5);
    descriptor(&expected, .little, 0, 48, base + 176, base);
    try testing.expectEqualSlices(u8, &expected, image.bytes);
    try testing.expectEqual(@as(u64, 42), (try interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .internal_variadic_calls = true, .consume_vaargs = true, .memory_image = &image, .stack_memory = .{}, .max_steps = 5, .max_call_depth = 2 })).?.long);
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .internal_variadic_calls = true, .consume_vaargs = true, .memory_image = &image, .stack_memory = .{}, .max_steps = 4 }));
    try testing.expectEqual(@as(u64, 8), (try image.read(.unsigned_word, .long, image.base)).long);
}

test "internal no-varop and explicit empty tails remain lazy and preserve named subword transport" {
    var module = try parse(testing.allocator, "function w $entry() {\n@e\n%r =sb call $child(sb 255, ..., l 9, d d_1)\nret %r\n}\n" ++
        "function sb $child(sb %named, ...) {\n@e\nret %named\n}\n" ++
        "function $empty() {\n@e\ncall $init(...)\nret\n}\n" ++
        "function $init(...) {\n@e\nvastart 65536\nret\n}\n");
    defer module.deinit();
    try testing.expectEqual(@as(u32, 255), (try interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .internal_variadic_calls = true, .stack_memory = .{ .max_bytes = 0 } })).?.word);
    var image = try Image.init(testing.allocator, 24, .{});
    defer image.deinit();
    try testing.expectError(error.StackLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(2), &.{}, .{ .internal_variadic_calls = true, .memory_image = &image, .stack_memory = .{ .max_bytes = 191 } }));
    try testing.expectEqual(@as(?ir.Constant, null), try interpreter.evaluateModule(testing.allocator, &module, id(2), &.{}, .{ .internal_variadic_calls = true, .memory_image = &image, .stack_memory = .{ .max_bytes = 192 } }));
    var expected: [24]u8 = undefined;
    descriptor(&expected, .little, 0, 48, base + 176, base);
    try testing.expectEqualSlices(u8, &expected, image.bytes);
}

test "internal raw classes use named banks and shared ordered overflow with mixed endian descriptors" {
    const source = "function d $entry(w %w, l %l, s %s, d %d) {\n@e\n%r =d call $child(l 1, l 2, l 3, l 4, l 5, l 6, l 7, d d_1, d d_2, d d_3, d d_4, d d_5, d d_6, d d_7, d d_8, d d_9, ..., w %w, l %l, s %s, d %d)\nret %r\n}\n" ++
        "function d $child(l %a, l %b, l %c, l %d, l %e, l %f, l %g, d %h, d %i, d %j, d %k, d %m, d %n, d %o, d %p, d %q, ...) {\n@e\nvastart 65536\n%w =w vaarg 65536\n%l =l vaarg 65536\n%s =s vaarg 65536\n%r =d vaarg 65536\nstorew %w, 65568\nstorel %l, 65576\nstores %s, 65584\nret %r\n}\n";
    var module = try parse(testing.allocator, source);
    defer module.deinit();
    for ([_]std.builtin.Endian{ .little, .big }) |image_endian| for ([_]std.builtin.Endian{ .little, .big }) |stack_endian| for ([_]u64{ 0, 0x8000000080000000, 0x7ff000007f800001, 0xffffffffffffffff }) |raw| {
        var image = try Image.init(testing.allocator, 64, .{ .endian = image_endian });
        defer image.deinit();
        @memset(image.bytes, 0xa5);
        const args = [_]ir.Constant{ .{ .word = @truncate(raw) }, .{ .long = raw }, .{ .single_bits = @truncate(raw) }, .{ .double_bits = raw } };
        try testing.expectEqual(raw, (try interpreter.evaluateModule(testing.allocator, &module, id(0), &args, .{ .internal_variadic_calls = true, .consume_vaargs = true, .memory_image = &image, .stack_memory = .{ .max_bytes = 240, .endian = stack_endian } })).?.double_bits);
        var expected: [64]u8 = @splat(0xa5);
        descriptor(&expected, image_endian, 48, 176, base + 224, base);
        std.mem.writeInt(u32, expected[32..36], @truncate(raw), image_endian);
        std.mem.writeInt(u64, expected[40..48], raw, image_endian);
        std.mem.writeInt(u32, expected[48..52], @truncate(raw), image_endian);
        try testing.expectEqualSlices(u8, &expected, image.bytes);
    };
}

const recursive = "function l $entry(w %count) {\n@e\n%tail =l extuw %count\n%r =l call $recur(w %count, ..., l %tail)\nret %r\n}\n" ++
    "function l $recur(w %count, ...) {\n@e\n%list =l alloc16 24\nvastart %list\njnz %count, @next, @done\n@next\n%n =w sub %count, 1\n%tail =l extuw %n\n%r =l call $recur(w %n, ..., l %tail)\njmp @done\n@done\n%below =l phi @e 0, @next %r\n%v =l vaarg %list\n%sum =l add %v, %below\nret %sum\n}\n";
test "recursive variadic frames keep distinct sources through handle growth and descendant returns" {
    var module = try parse(testing.allocator, recursive);
    defer module.deinit();
    const args = [_]ir.Constant{.{ .word = 80 }};
    try testing.expectEqual(@as(u64, 3240), (try interpreter.evaluateModule(testing.allocator, &module, id(0), &args, .{ .internal_variadic_calls = true, .consume_vaargs = true, .stack_memory = .{ .max_bytes = 81 * 240 }, .max_call_depth = 82 })).?.long);
    try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &args, .{ .internal_variadic_calls = true, .consume_vaargs = true, .stack_memory = .{}, .max_call_depth = 81 }));
    try testing.expectError(error.StackLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &args, .{ .internal_variadic_calls = true, .consume_vaargs = true, .stack_memory = .{ .max_bytes = 81 * 240 - 1 }, .max_call_depth = 82 }));
}

test "root tail never leaks into child and child source survives ordinary descendant consumption" {
    var module = try parse(testing.allocator, "function l $entry(...) {\n@e\nvastart 65536\n%r =l call $child(..., l 22)\n%x =l vaarg 65536\n%sum =l add %r, %x\nret %sum\n}\n" ++
        "function l $child(...) {\n@e\n%list =l alloc16 24\nvastart %list\n%r =l call $reader(l %list)\nret %r\n}\n" ++
        "function l $reader(l %list) {\n@e\n%local =l alloc8 8\nstorel 999, %local\n%r =l vaarg %list\nret %r\n}\n");
    defer module.deinit();
    var image = try Image.init(testing.allocator, 24, .{});
    defer image.deinit();
    try testing.expectEqual(@as(u64, 33), (try interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .root_variadic_arguments = &.{.{ .long = 11 }}, .internal_variadic_calls = true, .consume_vaargs = true, .memory_image = &image, .stack_memory = .{ .max_bytes = 464 } })).?.long);
    var expected: [24]u8 = undefined;
    descriptor(&expected, .little, 8, 48, base + 176, base);
    try testing.expectEqualSlices(u8, &expected, image.bytes);
}

test "repeated child vastart resets copied cursors but never restores source mutation or allocates again" {
    var module = try parse(testing.allocator, "function l $entry() {\n@e\n%r =l call $child(..., l 11, l 22)\nret %r\n}\n" ++
        "function l $child(...) {\n@e\nvastart 65536\nblit 65536, 65560, 24\n%x =l vaarg 65536\n%y =l vaarg 65560\n%save =l loadl 65552\nstorel 99, %save\nvastart 65536\n%z =l vaarg 65536\n%a =l add %x, %y\n%r =l add %a, %z\nret %r\n}\n");
    defer module.deinit();
    var image = try Image.init(testing.allocator, 48, .{});
    defer image.deinit();
    try testing.expectEqual(@as(u64, 121), (try interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .internal_variadic_calls = true, .consume_vaargs = true, .memory_image = &image, .stack_memory = .{ .max_bytes = 192 } })).?.long);
    var expected: [48]u8 = undefined;
    descriptor(expected[0..24], .little, 8, 48, base + 176, base);
    descriptor(expected[24..48], .little, 8, 48, base + 176, base);
    try testing.expectEqualSlices(u8, &expected, image.bytes);
}

test "returned child source is dead even after sibling allocation and reservations remain cumulative" {
    var module = try parse(testing.allocator, "function l $entry() {\n@e\n%old =l call $child(..., l 11)\n%new =l call $child(..., l 22)\n%r =l loadl %old\nret %r\n}\n" ++
        "function l $child(...) {\n@e\nvastart 65536\n%save =l loadl 65552\nret %save\n}\n");
    defer module.deinit();
    var image = try Image.init(testing.allocator, 24, .{});
    defer image.deinit();
    try testing.expectError(error.MemoryOutOfBounds, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .internal_variadic_calls = true, .memory_image = &image, .stack_memory = .{ .max_bytes = 384 } }));
    try testing.expectEqual(base + 192, (try image.read(.long, .long, 65552)).long);
    try testing.expectError(error.StackLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .internal_variadic_calls = true, .memory_image = &image, .stack_memory = .{ .max_bytes = 383 } }));
    try testing.expectEqual(base, (try image.read(.long, .long, 65552)).long);
}

test "bad child descriptor fails before source reservation or mutation and tail faults preserve cursor writes" {
    var invalid = try parse(testing.allocator, "function $entry() {\n@e\nstorew 7, 65536\ncall $child(...)\nret\n}\nfunction $child(...) {\n@e\nvastart 65544\nret\n}\n");
    defer invalid.deinit();
    var image = try Image.init(testing.allocator, 24, .{});
    defer image.deinit();
    @memset(image.bytes, 0xa5);
    try testing.expectError(error.MemoryOutOfBounds, interpreter.evaluateModule(testing.allocator, &invalid, id(0), &.{}, .{ .internal_variadic_calls = true, .memory_image = &image, .stack_memory = .{ .max_bytes = 0 } }));
    var expected: [24]u8 = @splat(0xa5);
    std.mem.writeInt(u32, expected[0..4], 7, .little);
    try testing.expectEqualSlices(u8, &expected, image.bytes);
    var narrow = try parse(testing.allocator, "function l $entry() {\n@e\n%r =l call $child(..., w 42)\nret %r\n}\nfunction l $child(...) {\n@e\nvastart 65536\n%r =l vaarg 65536\nret %r\n}\n");
    defer narrow.deinit();
    try testing.expectError(error.UninitializedMemory, interpreter.evaluateModule(testing.allocator, &narrow, id(0), &.{}, .{ .internal_variadic_calls = true, .consume_vaargs = true, .memory_image = &image, .stack_memory = .{} }));
    descriptor(&expected, .little, 8, 48, base + 176, base);
    try testing.expectEqualSlices(u8, &expected, image.bytes);
}

test "new dispatch capability never authorizes external indirect symbolic tails or invalid named contracts" {
    var module = try parse(testing.allocator, "function $external() {\n@e\ncall $missing(...)\nret\n}\n" ++
        "function $indirect(l %address) {\n@e\ncall %address(...)\nret\n}\n" ++
        "function $symbol() {\n@e\ncall $child(..., l $missing)\nret\n}\nfunction $child(...) {\n@e\nret\n}\n");
    defer module.deinit();
    try testing.expectError(error.UnsupportedExternalCall, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .internal_variadic_calls = true, .max_call_depth = 1 }));
    try testing.expectError(error.UnsupportedIndirectCall, interpreter.evaluateModule(testing.allocator, &module, id(1), &.{.{ .long = 0 }}, .{ .internal_variadic_calls = true, .max_call_depth = 1 }));
    try testing.expectError(error.UnsupportedVariadicCall, interpreter.evaluateModule(testing.allocator, &module, id(2), &.{}, .{}));
    try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(2), &.{}, .{ .internal_variadic_calls = true, .max_call_depth = 1 }));
    try testing.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(testing.allocator, &module, id(2), &.{}, .{ .internal_variadic_calls = true }));
    for ([_][]const u8{ "l 7, ...", "sb 7, ...", "..., w 7", "w 7" }) |list| {
        const text = try std.fmt.allocPrint(testing.allocator, "function $entry() {{\n@e\ncall $child({s})\nret\n}}\nfunction $child(w %named, ...) {{\n@e\nret\n}}\n", .{list});
        defer testing.allocator.free(text);
        var invalid = try parse(testing.allocator, text);
        defer invalid.deinit();
        try testing.expectError(error.CallSignatureMismatch, interpreter.evaluateModule(testing.allocator, &invalid, id(0), &.{}, .{ .internal_variadic_calls = true }));
    }
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, recursive ++ "data $list = { z 24 }\nfunction l $global() {\n@e\n%r =l call $child(..., l 42)\nret %r\n}\nfunction l $child(...) {\n@e\nvastart $list\n%r =l vaarg $list\nret %r\n}\n" ++
        "function $fault() {\n@e\ncall $bad(..., w 42)\nret\n}\nfunction $bad(...) {\n@e\nvastart 65536\n%x =l vaarg 65536\nret\n}\n");
    defer module.deinit();
    var image = try Image.init(allocator, 24, .{});
    defer image.deinit();
    const options: interpreter.Options = .{ .internal_variadic_calls = true, .consume_vaargs = true, .stack_memory = .{}, .memory_image = &image, .global_memory = .{} };
    if ((try interpreter.evaluateModule(allocator, &module, id(0), &.{.{ .word = 9 }}, options)).?.long != 45) return error.WrongRecursiveResult;
    if ((try interpreter.evaluateModule(allocator, &module, id(2), &.{}, options)).?.long != 42) return error.WrongGlobalResult;
    if (interpreter.evaluateModule(allocator, &module, id(4), &.{}, options)) |_| return error.ExpectedSourceFault else |err| {
        if (err != error.UninitializedMemory) return err;
    }
    if (std.mem.readInt(u32, image.bytes[0..4], .little) != 8) return error.ExpectedRetainedWrite;
    // Recovery in the same owned module and borrowed Image after a later fault.
    if ((try interpreter.evaluateModule(allocator, &module, id(2), &.{}, options)).?.long != 42) return error.WrongRecoveryResult;
}
test "internal variadic snapshots frames source objects globals and later errors clean every allocation failure and recover" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

test "register tails preserve raw words singles doubles low-word projection and forwarded child snapshots" {
    var module = try parse(testing.allocator, "function d $entry(l %wide, s %single, d %double) {\n@e\n%r =d call $forward(l %wide, s %single, d %double)\nret %r\n}\n" ++
        "function d $forward(l %wide, s %single, d %double) {\n@e\n%r =d call $child(sb 255, d d_1, ..., w %wide, l %wide, s %single, d %double)\nret %r\n}\n" ++
        "function d $child(sb %named, d %fp, ...) {\n@e\nvastart 65536\n%w =w vaarg 65536\n%l =l vaarg 65536\n%s =s vaarg 65536\n%d =d vaarg 65536\nstorew %w, 65568\nstorel %l, 65576\nstores %s, 65584\nstorew %named, 65592\nret %d\n}\n");
    defer module.deinit();
    for ([_]std.builtin.Endian{ .little, .big }) |image_endian| for ([_]std.builtin.Endian{ .little, .big }) |stack_endian| for ([_]u64{ 0, 0x8000000000000000, 0x7ff0000000000001, 0x7ff800000000cafe, 0xffffffffffffffff }) |raw| {
        var image = try Image.init(testing.allocator, 64, .{ .endian = image_endian });
        defer image.deinit();
        @memset(image.bytes, 0xa5);
        const arguments = [_]ir.Constant{ .{ .long = 0x12345678abcdef01 }, .{ .single_bits = 0x7f800001 }, .{ .double_bits = raw } };
        const result = (try interpreter.evaluateModule(testing.allocator, &module, id(0), &arguments, .{ .internal_variadic_calls = true, .consume_vaargs = true, .memory_image = &image, .stack_memory = .{ .endian = stack_endian, .max_bytes = 192 } })).?;
        try testing.expectEqual(raw, result.double_bits);
        var expected: [64]u8 = @splat(0xa5);
        descriptor(&expected, image_endian, 24, 96, base + 176, base);
        std.mem.writeInt(u32, expected[32..36], 0xabcdef01, image_endian);
        std.mem.writeInt(u64, expected[40..48], 0x12345678abcdef01, image_endian);
        std.mem.writeInt(u32, expected[48..52], 0x7f800001, image_endian);
        std.mem.writeInt(u32, expected[56..60], 255, image_endian);
        try testing.expectEqualSlices(u8, &expected, image.bytes);
        try testing.expectEqual(@as(u64, 0x12345678abcdef01), arguments[0].long);
        try testing.expectEqual(@as(u32, 0x7f800001), arguments[1].single_bits);
    };
}

test "unused internal vaarg keeps ordered consumption after folding and callee halts retain earlier Image writes" {
    const source = "function l $entry() {\n@e\n%r =l call $child(..., l 11, l 22)\nret %r\n}\n" ++
        "function l $child(...) {\n@e\nvastart 65536\n%unused =l vaarg 65536\n%r =l vaarg 65536\nret %r\n}\n" ++
        "function $stop() {\n@e\ncall $halt(...)\nret\n}\nfunction $halt(...) {\n@e\nstorel 99, 65536\nhlt\n}\n";
    var module = try parse(testing.allocator, source);
    defer module.deinit();
    var image = try Image.init(testing.allocator, 24, .{});
    defer image.deinit();
    for ([_]bool{ false, true }) |fold| {
        if (fold) for (module.functions.items) |function| {
            _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, function);
        };
        try testing.expectEqual(@as(u64, 22), (try interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .internal_variadic_calls = true, .consume_vaargs = true, .memory_image = &image, .stack_memory = .{} })).?.long);
        try testing.expectEqual(@as(u32, 16), (try image.read(.unsigned_word, .word, 65536)).word);
        try testing.expectError(error.Halted, interpreter.evaluateModule(testing.allocator, &module, id(2), &.{}, .{ .internal_variadic_calls = true, .memory_image = &image }));
        try testing.expectEqual(@as(u64, 99), (try image.read(.long, .long, 65536)).long);
    }
}

test "each runtime allocation failure permits retry on the same module and Image without leaks or stale state" {
    var module = try parse(testing.allocator, recursive ++ "data $list = { z 24 }\n");
    defer module.deinit();
    var image = try Image.init(testing.allocator, 24, .{});
    defer image.deinit();
    const options: interpreter.Options = .{ .internal_variadic_calls = true, .consume_vaargs = true, .stack_memory = .{}, .memory_image = &image, .global_memory = .{} };
    const arguments = [_]ir.Constant{.{ .word = 9 }};
    var count = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.expectEqual(@as(u64, 45), (try interpreter.evaluateModule(count.allocator(), &module, id(0), &arguments, options)).?.long);
    try testing.expectEqual(count.allocated_bytes, count.freed_bytes);
    for (0..count.alloc_index) |fail_at| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = fail_at, .resize_fail_index = 0 });
        try testing.expectError(error.OutOfMemory, interpreter.evaluateModule(failing.allocator(), &module, id(0), &arguments, options));
        try testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        failing.fail_index = std.math.maxInt(usize);
        try testing.expectEqual(@as(u64, 45), (try interpreter.evaluateModule(failing.allocator(), &module, id(0), &arguments, options)).?.long);
        try testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        try testing.expectEqual(@as(u32, 9), arguments[0].word);
        try testing.expectEqual(@as(u64, 24), module.data.items[0].items.items[0].zero);
    }
}
