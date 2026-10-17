const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const Module = @import("module.zig").Module;
const FunctionId = @import("module.zig").FunctionId;
const interpreter = @import("interpreter.zig");
const Image = @import("memory.zig").Image;
const types = [_]ir.ScalarType{ .word, .long, .single, .double };
const readers =
    "function w $word(l %p) {\n@e\n%r =w vaarg %p\nret %r\n}\n" ++
    "function l $long(l %p) {\n@e\n%r =l vaarg %p\nret %r\n}\n" ++
    "function s $single(l %p) {\n@e\n%r =s vaarg %p\nret %r\n}\n" ++
    "function d $double(l %p) {\n@e\n%r =d vaarg %p\nret %r\n}\n";
const stack_reader = "function l $stack() {\n@e\n%list =l alloc16 24\n%save =l alloc8 8\nstorew 0, %list\n%field =l add %list, 16\nstorel %save, %field\nstorel 37, %save\n%r =l vaarg %list\nret %r\n}\n";
const global_reader = "data $save = { l 11 22 }\ndata $list = { w 0 48, l 0 $save }\nfunction l $global() {\n@e\n%a =l vaarg $list\n%b =l vaarg $list\n%r =l add %a, %b\nret %r\n}\n";
const undefined_reader = "function l $undefined(l %list) {\n@e\n%save =l alloc8 8\n%field =l add %list, 16\nstorel %save, %field\n%r =l vaarg %list\nret %r\n}\n";
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "interpreter-vaarg", .text = text }, &diagnostic);
}
fn id(index: usize) FunctionId {
    return @fromBackingInt(@as(u32, @intCast(index)));
}
fn bits(value: ir.Constant) u64 {
    return switch (value) {
        .word => |v| v,
        .long => |v| v,
        .single_bits => |v| v,
        .double_bits => |v| v,
    };
}
fn narrow(ty: ir.ScalarType) bool {
    return ty == .word or ty == .single;
}
fn put32(image: *Image, at: usize, value: u32) void {
    std.mem.writeInt(u32, image.bytes[at..][0..4], value, image.endian);
}
fn put64(image: *Image, at: usize, value: u64) void {
    std.mem.writeInt(u64, image.bytes[at..][0..8], value, image.endian);
}
fn get32(image: *const Image, at: usize) u32 {
    return std.mem.readInt(u32, image.bytes[at..][0..4], image.endian);
}
fn get64(image: *const Image, at: usize) u64 {
    return std.mem.readInt(u64, image.bytes[at..][0..8], image.endian);
}
fn descriptor(image: *Image, gp: u32, fp: u32, overflow: u64, save: u64) void {
    put32(image, 0, gp);
    put32(image, 4, fp);
    put64(image, 8, overflow);
    put64(image, 16, save);
}
fn run(module: *const Module, index: usize, list: u64, image: *Image, as_module: bool) !ir.Constant {
    const options: interpreter.Options = .{ .consume_vaargs = true, .memory_image = image };
    const value = if (as_module)
        try interpreter.evaluateModule(testing.allocator, module, id(index), &.{.{ .long = list }}, options)
    else
        try interpreter.evaluate(testing.allocator, module.functions.items[index], &.{.{ .long = list }}, options);
    return value.?;
}

test "opt-in vaarg raw four classes thresholds banks and full byte effects match independent expectations" {
    var module = try parse(testing.allocator, readers);
    defer module.deinit();
    const patterns = [_]u64{ 0, 0x80000000, 0x7f800001, 0x8000000000000000, 0x7ff0000000000001, 0xffffffffffffffff };
    for ([_]std.builtin.Endian{ .little, .big }) |endian| {
        var image = try Image.init(testing.allocator, 512, .{ .endian = endian });
        defer image.deinit();
        for (types, 0..) |ty, index| for (0..6) |position| for (patterns) |pattern| for ([_]bool{ false, true }) |as_module| {
            @memset(image.bytes, 0xa5);
            const offsets = if (ty.isInteger()) [_]u32{ 0, 40, 47, 48, 49, std.math.maxInt(u32) } else [_]u32{ 48, 160, 175, 176, 177, std.math.maxInt(u32) };
            const offset = offsets[position];
            const limit: u32 = if (ty.isInteger()) 48 else 176;
            const field: usize = if (ty.isInteger()) 0 else 4;
            const stride: u32 = if (ty.isInteger()) 8 else 16;
            descriptor(&image, if (ty.isInteger()) offset else 24, if (ty.isInteger()) 80 else offset, image.base + 400, if (offset < limit) image.base + 128 else 0);
            const source: usize = if (offset < limit) 128 + offset else 400;
            if (narrow(ty)) put32(&image, source, @truncate(pattern)) else put64(&image, source, pattern);
            var expected: [512]u8 = undefined;
            @memcpy(&expected, image.bytes);
            if (offset < limit) std.mem.writeInt(u32, expected[field..][0..4], offset + stride, endian) else std.mem.writeInt(u64, expected[8..16], image.base + 408, endian);
            const value = try run(&module, index, image.base, &image, as_module);
            try testing.expectEqual(ty, value.scalarType());
            try testing.expectEqual(if (narrow(ty)) @as(u64, @as(u32, @truncate(pattern))) else pattern, bits(value));
            try testing.expectEqualSlices(u8, &expected, image.bytes);
        };
    }
}

test "vaarg exact four-byte last-u64 loads and checked arithmetic have explicit mutation boundaries" {
    var module = try parse(testing.allocator, readers);
    defer module.deinit();
    const top: u64 = std.math.maxInt(u64);
    for ([_]std.builtin.Endian{ .little, .big }) |endian| {
        var image = try Image.init(testing.allocator, 256, .{ .base = top - 255, .endian = endian });
        defer image.deinit();
        for (types, 0..) |ty, index| {
            descriptor(&image, 0, 48, 0, top - 3 - (if (ty.isInteger()) @as(u64, 0) else 48));
            put32(&image, 252, 0x80000001);
            if (narrow(ty)) {
                try testing.expectEqual(@as(u64, 0x80000001), bits(try run(&module, index, image.base, &image, true)));
            } else try testing.expectError(error.MemoryOutOfBounds, run(&module, index, image.base, &image, true));
            try testing.expectEqual(@as(u32, if (ty.isInteger()) 8 else 64), get32(&image, if (ty.isInteger()) 0 else 4));
        }
        descriptor(&image, 8, 48, 0, top - 1);
        try testing.expectError(error.MemoryOutOfBounds, run(&module, 0, image.base, &image, true));
        try testing.expectEqual(@as(u32, 8), get32(&image, 0));
        descriptor(&image, 48, 176, top - 3, 0);
        try testing.expectError(error.MemoryOutOfBounds, run(&module, 0, image.base, &image, true));
        try testing.expectEqual(top - 3, get64(&image, 8));
        put32(&image, 252, 0);
        try testing.expectError(error.MemoryOutOfBounds, run(&module, 0, top - 3, &image, true));
        try testing.expectEqual(@as(u32, 0), get32(&image, 252));
        try testing.expectError(error.MemoryOutOfBounds, run(&module, 2, top - 1, &image, true));
    }
}

test "vaarg cursor writes precede aliased source loads and survive later source faults" {
    var module = try parse(testing.allocator, readers);
    defer module.deinit();
    for ([_]std.builtin.Endian{ .little, .big }) |endian| {
        var image = try Image.init(testing.allocator, 64, .{ .endian = endian });
        defer image.deinit();
        descriptor(&image, 0, 48, 0, image.base);
        try testing.expectEqual(@as(u64, 8), bits(try run(&module, 0, image.base, &image, false)));
        descriptor(&image, 48, 176, image.base + 8, 0);
        try testing.expectEqual(image.base + 16, bits(try run(&module, 1, image.base, &image, true)));
        descriptor(&image, 0, 48, 0, 0);
        try testing.expectError(error.MemoryOutOfBounds, run(&module, 1, image.base, &image, true));
        try testing.expectEqual(@as(u32, 8), get32(&image, 0));
        descriptor(&image, 48, 176, 1, 0);
        try testing.expectError(error.MemoryOutOfBounds, run(&module, 3, image.base, &image, true));
        try testing.expectEqual(@as(u64, 9), get64(&image, 8));
    }
}

test "consumer opt-in preserves default refusals budgets and unsupported initialization or variadic calls" {
    var module = try parse(testing.allocator, readers ++ "function $var(...) {\n@e\nvastart $unknown\nret\n}\nfunction $caller() {\n@e\ncall $var(...)\nret\n}\n");
    defer module.deinit();
    var image = try Image.init(testing.allocator, 64, .{});
    defer image.deinit();
    descriptor(&image, 0, 48, 0, image.base + 32);
    put64(&image, 32, 42);
    try testing.expectError(error.UnsupportedVariadicOperation, interpreter.evaluateModule(testing.allocator, &module, id(1), &.{.{ .long = image.base }}, .{ .memory_image = &image }));
    try testing.expectEqual(@as(u32, 0), get32(&image, 0));
    try testing.expectError(error.UnsupportedMemory, interpreter.evaluateModule(testing.allocator, &module, id(1), &.{.{ .long = 0 }}, .{ .consume_vaargs = true }));
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(1), &.{.{ .long = image.base }}, .{ .memory_image = &image, .consume_vaargs = true, .max_steps = 0 }));
    try testing.expectEqual(@as(u32, 0), get32(&image, 0));
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(1), &.{.{ .long = image.base }}, .{ .memory_image = &image, .consume_vaargs = true, .max_steps = 1 }));
    try testing.expectEqual(@as(u32, 8), get32(&image, 0));
    try testing.expectError(error.UnsupportedVariadicOperation, interpreter.evaluateModule(testing.allocator, &module, id(4), &.{}, .{ .memory_image = &image, .consume_vaargs = true }));
    try testing.expectError(error.UnsupportedVariadicCall, interpreter.evaluateModule(testing.allocator, &module, id(5), &.{}, .{ .consume_vaargs = true, .max_call_depth = 1 }));
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(5), &.{}, .{ .consume_vaargs = true, .max_steps = 0 }));
    var effects = try parse(testing.allocator, "function w $f(l %p) {\n@e\nstorew 123, %p\n%r =w vaarg $external\nret %r\n}");
    defer effects.deinit();
    try testing.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(testing.allocator, &effects, id(0), &.{.{ .long = image.base + 32 }}, .{ .memory_image = &image, .consume_vaargs = true }));
    try testing.expectEqual(@as(u8, 123), image.bytes[32]);
}

test "ordinary child consumers share cursors and unused folded consumption remains an effect" {
    var module = try parse(testing.allocator, readers ++ "function l $caller(l %p) {\n@e\n%a =l call $long(l %p)\n%b =l call $long(l %p)\n%r =l add %a, %b\nret %r\n}\nfunction w $unused(l %p) {\n@e\n%a =l vaarg %p\n%b =l vaarg %p\nret 42\n}\n");
    defer module.deinit();
    var image = try Image.init(testing.allocator, 128, .{});
    defer image.deinit();
    descriptor(&image, 0, 48, 0, image.base + 32);
    put64(&image, 32, 11);
    put64(&image, 40, 22);
    try image.copy(image.base, image.base + 64, 24);
    try testing.expectEqual(@as(u64, 33), bits(try run(&module, 4, image.base, &image, true)));
    try testing.expectEqual(@as(u32, 16), get32(&image, 0));
    try testing.expectEqual(@as(u32, 0), get32(&image, 64));
    try testing.expectEqual(@as(u64, 11), bits(try run(&module, 1, image.base + 64, &image, true)));
    try testing.expectEqual(@as(u32, 8), get32(&image, 64));
    try testing.expectEqual(@as(u32, 16), get32(&image, 0));
    for (module.functions.items) |f| _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
    descriptor(&image, 0, 48, 0, image.base + 32);
    try testing.expectEqual(@as(u64, 42), bits(try run(&module, 5, image.base, &image, true)));
    try testing.expectEqual(@as(u32, 16), get32(&image, 0));
    descriptor(&image, 0, 48, 0, image.base + 32);
    try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, id(4), &.{.{ .long = image.base }}, .{ .memory_image = &image, .consume_vaargs = true, .max_call_depth = 1 }));
    try testing.expectEqual(@as(u32, 0), get32(&image, 0));
}

test "synthetic stack descriptors need only selected fields and preserve Image updates on undefined source" {
    for (types) |ty| for ([_]std.builtin.Endian{ .little, .big }) |endian| for ([_]bool{ false, true }) |overflow| {
        const class: []const u8 = switch (ty) {
            .word => "w",
            .long => "l",
            .single => "s",
            .double => "d",
        };
        const text = try std.fmt.allocPrint(testing.allocator, "function {s} $f() {{\n@e\n%list =l alloc16 24\n%save =l alloc8 8\n%field =l add %list, {d}\nstorew {d}, %field\n%base =l sub %save, {d}\n%ptr =l add %list, {d}\nstorel %base, %ptr\nstore{s} {s}, %save\n%r ={s} vaarg %list\nret %r\n}}", .{ class, @as(u8, if (ty.isInteger()) 0 else 4), @as(u8, if (overflow) (if (ty.isInteger()) @as(u8, 48) else 176) else (if (ty.isInteger()) @as(u8, 0) else 48)), @as(u8, if (overflow or ty.isInteger()) 0 else 48), @as(u8, if (overflow) 8 else 16), if (narrow(ty)) @as([]const u8, "w") else "l", if (narrow(ty)) @as([]const u8, "-2147483648") else "-9223372036854775808", class });
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        const value = (try interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .consume_vaargs = true, .stack_memory = .{ .endian = endian } })).?;
        try testing.expectEqual(@as(u64, if (narrow(ty)) 0x80000000 else 0x8000000000000000), bits(value));
        try testing.expectError(error.UnsupportedAllocation, interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .consume_vaargs = true }));
    };
    var undefined_module = try parse(testing.allocator, undefined_reader);
    defer undefined_module.deinit();
    var image = try Image.init(testing.allocator, 24, .{});
    defer image.deinit();
    descriptor(&image, 0, 48, 0, 0);
    try testing.expectError(error.UninitializedMemory, interpreter.evaluateModule(testing.allocator, &undefined_module, id(0), &.{.{ .long = image.base }}, .{ .consume_vaargs = true, .stack_memory = .{}, .memory_image = &image }));
    try testing.expectEqual(@as(u32, 8), get32(&image, 0));
    try testing.expectEqual(@as(usize, 24), image.bytes.len);
}

test "global descriptors reset and source regions retain independently configured byte order" {
    var module = try parse(testing.allocator, global_reader ++ "function l $cross(l %list) {\n@e\n%ptr =l add %list, 16\nstorel $save, %ptr\n%r =l vaarg %list\nret %r\n}\n");
    defer module.deinit();
    for ([_]std.builtin.Endian{ .little, .big }) |global_endian| {
        for (0..2) |_| try testing.expectEqual(@as(u64, 33), bits((try interpreter.evaluateModule(testing.allocator, &module, id(0), &.{}, .{ .consume_vaargs = true, .global_memory = .{ .endian = global_endian } })).?));
        for ([_]std.builtin.Endian{ .little, .big }) |image_endian| {
            var image = try Image.init(testing.allocator, 24, .{ .endian = image_endian });
            defer image.deinit();
            descriptor(&image, 0, 48, 0, 0);
            try testing.expectEqual(@as(u64, 11), bits((try interpreter.evaluateModule(testing.allocator, &module, id(1), &.{.{ .long = image.base }}, .{ .consume_vaargs = true, .global_memory = .{ .endian = global_endian }, .memory_image = &image })).?));
            try testing.expectEqual(@as(u32, 8), get32(&image, 0));
        }
    }
    try testing.expectError(error.GlobalsRequireModule, interpreter.evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .consume_vaargs = true, .global_memory = .{} }));
    try testing.expectEqual(@as(u64, 0), module.data.items[1].items.items[0].word);
}

test "vaarg cannot revive returned stack storage in a later active invocation" {
    var module = try parse(testing.allocator, "function l $first() {\n@e\n%p =l alloc8 8\nstorel 11, %p\nret %p\n}\nfunction l $second(l %list) {\n@e\n%p =l alloc8 8\nstorel 22, %p\n%r =l vaarg %list\nret %r\n}\nfunction l $root(l %list) {\n@e\n%old =l call $first()\n%field =l add %list, 16\nstorel %old, %field\n%r =l call $second(l %list)\nret %r\n}\n");
    defer module.deinit();
    var image = try Image.init(testing.allocator, 24, .{});
    defer image.deinit();
    descriptor(&image, 0, 48, 0, 0);
    try testing.expectError(error.MemoryOutOfBounds, interpreter.evaluateModule(testing.allocator, &module, id(2), &.{.{ .long = image.base }}, .{ .consume_vaargs = true, .stack_memory = .{}, .memory_image = &image }));
    try testing.expectEqual(@as(u32, 8), get32(&image, 0));
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, readers ++ stack_reader ++ global_reader ++ undefined_reader);
    defer module.deinit();
    var image = try Image.init(allocator, 64, .{});
    defer image.deinit();
    descriptor(&image, 0, 48, 0, image.base + 32);
    put64(&image, 32, 42);
    _ = try interpreter.evaluateModule(allocator, &module, id(1), &.{.{ .long = image.base }}, .{ .consume_vaargs = true, .memory_image = &image });
    _ = try interpreter.evaluateModule(allocator, &module, id(4), &.{}, .{ .consume_vaargs = true, .stack_memory = .{} });
    _ = try interpreter.evaluateModule(allocator, &module, id(5), &.{}, .{ .consume_vaargs = true, .global_memory = .{} });
    descriptor(&image, 0, 48, 0, 0);
    if (interpreter.evaluateModule(allocator, &module, id(6), &.{.{ .long = image.base }}, .{ .consume_vaargs = true, .stack_memory = .{}, .global_memory = .{}, .memory_image = &image })) |_| return error.ExpectedMemoryRefusal else |err| {
        if (err != error.UninitializedMemory) return err;
    }
    if (get32(&image, 0) != 8) return error.ExpectedCursorWrite;
}
test "all consumer frame global stack Image and later-fault allocation failures clean up ownership" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
