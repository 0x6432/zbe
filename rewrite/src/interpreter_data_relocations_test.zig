const std = @import("std");
const testing = std.testing;
const global_memory = @import("global_memory.zig");
const evaluation_memory = @import("evaluation_memory.zig");
const interpreter = @import("interpreter.zig");
const memory = @import("memory.zig");
const module_impl = @import("module.zig");
const entry: module_impl.FunctionId = @fromBackingInt(@as(u32, 0));
const fixture = @embedFile("fixtures/interpreter-data-relocations.ssa");
const base: u64 = 0x200000000;
fn parse(allocator: std.mem.Allocator, text: []const u8) !module_impl.Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "interpreter-data-relocations", .text = text }, &diagnostic);
}
// Independent expected byte extraction, never the production serializer/lookup.
fn expectPointer(bytes: []const u8, expected: u64, endian: std.builtin.Endian) !void {
    try testing.expectEqual(@as(usize, 8), bytes.len);
    for (bytes, 0..) |byte, i| {
        const shift: u6 = @intCast((if (endian == .little) i else 7 - i) * 8);
        try testing.expectEqual(@as(u8, @truncate(expected >> shift)), byte);
    }
}

test "synthetic forward self mutual empty and unaligned data references match independent guarded layout bytes" {
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    for ([_]std.builtin.Endian{ .little, .big }) |endian| {
        var space = try evaluation_memory.Space.initForModule(testing.allocator, null, null, &module, .{ .endian = endian, .max_bytes = 144 });
        defer space.deinit();
        // Hand layout: table33+guard16 ->49; align32 later at64, length5 ->85;
        // align8 mutual at88, length8 ->112; align64 empty at128 ->144.
        const objects = space.globals.?.objects;
        for (objects, [_]u64{ base, base + 64, base + 88, base + 128 }) |object, expected| try testing.expectEqual(expected, object.address);
        for ([_]u64{ base + 65, base + 8, base + 88, base + 128 }, 0..) |expected, i| {
            try expectPointer(objects[0].bytes[i * 8 ..][0..8], expected, endian);
            try testing.expectEqual(expected, (try space.read(.long, .long, base + i * 8)).long);
        }
        try testing.expectEqual(@as(usize, 33), objects[0].bytes.len);
        try testing.expectEqual(@as(u8, 17), objects[0].bytes[32]);
        try testing.expectEqualStrings("abcd\x00", objects[1].bytes);
        try expectPointer(objects[2].bytes, base + 16, endian);
        try testing.expectEqual(@as(usize, 0), objects[3].bytes.len);
        try space.write(.long, .{ .long = 0 }, base);
        try testing.expectEqual(@as(i64, 1), module.data.items[0].items.items[0].symbol_address.addend);
        var fresh = try global_memory.Space.init(testing.allocator, &module, .{ .endian = endian });
        defer fresh.deinit();
        try expectPointer(fresh.objects[0].bytes[0..8], base + 65, endian);
    }
}

test "full signed i64 data addends check u64 arithmetic including null and max integers without host dereference" {
    var module = try parse(testing.allocator, "data $g = { b 0 }\ndata $refs = { l $g+-9223372036854775808 $g+9223372036854775807 }");
    defer module.deinit();
    for ([_]std.builtin.Endian{ .little, .big }) |endian| {
        var space = try evaluation_memory.Space.initForModule(testing.allocator, null, null, &module, .{ .base = 0x8000000000000000, .max_bytes = 64, .endian = endian });
        defer space.deinit();
        const references = space.globals.?.objects[1];
        try expectPointer(references.bytes[0..8], 0, endian);
        try expectPointer(references.bytes[8..16], std.math.maxInt(u64), endian);
        try testing.expectEqual(@as(u64, 0), (try space.read(.long, .long, references.address)).long);
        try testing.expectEqual(std.math.maxInt(u64), (try space.read(.long, .long, references.address + 8)).long);
        try testing.expectError(error.MemoryOutOfBounds, space.read(.unsigned_byte, .long, 0));
        try testing.expectError(error.MemoryOutOfBounds, space.read(.unsigned_byte, .long, std.math.maxInt(u64)));
    }
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    try testing.expectError(error.GlobalAddressOverflow, global_memory.Space.init(failing.allocator(), &module, .{ .base = 64, .max_bytes = 64 }));
    try testing.expectError(error.GlobalAddressOverflow, global_memory.Space.init(failing.allocator(), &module, .{ .base = 0x8000000000000040, .max_bytes = 64 }));
    try testing.expectEqual(@as(usize, 0), failing.alloc_index); // Both failures precede payload/table allocation.
}

test "only defined data relocation targets are accepted with validation before eager setup refusal" {
    for ([_][]const u8{
        "data $g = { l $external }\nfunction l $f() {\n@e\nret 9\n}",
        "data $g = { l $f }\nfunction l $f() {\n@e\nret 9\n}",
    }) |text| {
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        try testing.expectEqual(@as(u64, 9), (try interpreter.evaluateModule(testing.allocator, &module, entry, &.{}, .{})).?.long);
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
        try testing.expectError(error.UnsupportedGlobalInitializer, global_memory.Space.init(failing.allocator(), &module, .{}));
        try testing.expectEqual(@as(usize, 0), failing.alloc_index);
        try testing.expectError(error.UnsupportedGlobalInitializer, interpreter.evaluateModule(testing.allocator, &module, entry, &.{}, .{ .global_memory = .{}, .max_steps = 0 }));
        module.data.items[0].items.items[0].symbol_address.symbol = @fromBackingInt(std.math.maxInt(u32));
        try testing.expectError(error.InvalidSymbol, interpreter.evaluateModule(testing.allocator, &module, entry, &.{}, .{ .global_memory = .{} }));
        module.data.items[0].byte_len += 1;
        try testing.expectError(error.InvalidDataSize, interpreter.evaluateModule(testing.allocator, &module, entry, &.{}, .{ .global_memory = .{} }));
        module.data.items[0].byte_len -= 1;
    }
    var self = try parse(testing.allocator, "data $g = { l $g }\nfunction l $f() {\n@e\n%p =l loadl $g\n%r =l ceql %p, $g\nret %r\n}");
    defer self.deinit();
    try testing.expectEqual(@as(u64, 1), (try interpreter.evaluateModule(testing.allocator, &self, entry, &.{}, .{ .global_memory = .{} })).?.long);
    try testing.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(testing.allocator, &self, entry, &.{}, .{}));
}

fn run(allocator: std.mem.Allocator, endian: std.builtin.Endian) !void {
    var module = try parse(allocator, fixture);
    defer module.deinit();
    for (module.functions.items) |f| _ = try @import("optimize.zig").foldIntegerConstants(allocator, f);
    var image = try memory.Image.init(allocator, 32, .{ .endian = endian });
    defer image.deinit();
    const options: interpreter.Options = .{ .global_memory = .{ .endian = endian }, .stack_memory = .{}, .memory_image = &image };
    for (0..2) |_| {
        try testing.expectEqual(@as(u64, 1098), (try interpreter.evaluateModule(allocator, &module, entry, &.{}, options)).?.long);
        _ = try interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 2)), &.{.{ .long = image.base }}, options);
        for ([_]u64{ base + 65, base + 8, base + 88, base + 128 }, 0..) |expected, i| try testing.expectEqual(expected, (try image.read(.long, .long, image.base + i * 8)).long);
    }
    if (interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 3)), &.{.{ .long = image.base }}, options)) |_| return error.ExpectedBoundsError else |err| {
        if (err != error.MemoryOutOfBounds) return err;
    }
    try testing.expectEqual(@as(u64, 37), (try image.read(.long, .long, image.base)).long);
    var budget = options;
    budget.max_steps = 2;
    if (interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 3)), &.{.{ .long = image.base }}, budget)) |_| return error.ExpectedBudgetError else |err| {
        if (err != error.StepLimitExceeded) return err;
    }
    try testing.expectEqual(@as(u64, 37), (try image.read(.long, .long, image.base)).long);
}
test "initialized synthetic pointer tables survive nested calls blits reset and reached faults with prior Image writes" {
    try run(testing.allocator, .little);
    try run(testing.allocator, .big);
}

test "relocation setup cap arithmetic and unsupported failures leave caller Image unchanged before zero-step execution" {
    var image = try memory.Image.init(testing.allocator, 8, .{});
    defer image.deinit();
    try image.write(.long, .{ .long = 123 }, image.base);
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    try testing.expectError(error.GlobalLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, entry, &.{}, .{ .global_memory = .{ .max_bytes = 143 }, .memory_image = &image, .max_steps = 0 }));
    try testing.expectEqual(@as(u64, 123), (try image.read(.long, .long, image.base)).long);
    for ([_][]const u8{
        "data $g = { l $g+-9223372036854775808 }\nfunction $f(l %image) {\n@e\nstorel 999, %image\nret\n}",
        "data $g = { l $external }\nfunction $f(l %image) {\n@e\nstorel 999, %image\nret\n}",
    }, 0..) |text, i| {
        var bad = try parse(testing.allocator, text);
        defer bad.deinit();
        const options: interpreter.Options = .{ .global_memory = .{}, .memory_image = &image, .max_steps = 0 };
        const expected = if (i == 0) error.GlobalAddressOverflow else error.UnsupportedGlobalInitializer;
        try testing.expectError(expected, interpreter.evaluateModule(testing.allocator, &bad, entry, &.{.{ .long = image.base }}, options));
        try testing.expectEqual(@as(u64, 123), (try image.read(.long, .long, image.base)).long);
    }
}

fn exercise(allocator: std.mem.Allocator) !void {
    try run(allocator, .little);
    try run(allocator, .big);
    var module = try parse(allocator, fixture);
    defer module.deinit();
    var globals = try global_memory.Space.init(allocator, &module, .{});
    defer globals.deinit();
    const assembly = try @import("amd64.zig").emitWithOptions(allocator, &module, .{ .reuse_stack_homes = true, .callee_saved_homes = true });
    defer allocator.free(assembly);
    try expectPointer(globals.objects[2].bytes, base + 16, .little);
}
test "all internal data relocation parsing preflight materialization evaluation and emission allocations clean up" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
