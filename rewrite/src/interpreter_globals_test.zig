const std = @import("std");
const testing = std.testing;
const global_memory = @import("global_memory.zig");
const evaluation_memory = @import("evaluation_memory.zig");
const interpreter = @import("interpreter.zig");
const memory = @import("memory.zig");
const ir = @import("ir.zig");
const module_impl = @import("module.zig");
const entry: module_impl.FunctionId = @fromBackingInt(@as(u32, 0));
const fixture = @embedFile("fixtures/interpreter-globals.ssa");
fn parse(allocator: std.mem.Allocator, text: []const u8) !module_impl.Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "interpreter-globals", .text = text }, &diagnostic);
}

fn checkOracle(space: *const global_memory.Space, module: *const module_impl.Module, text: []const u8) !usize {
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    var total: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeScalar(u8, line, '\t');
        const name = fields.next().?;
        _ = fields.next().?;
        _ = fields.next().?;
        const hex = fields.next().?;
        const bytes = found: {
            for (space.objects) |object| if (std.mem.eql(u8, module.symbols.get(object.symbol).?, name)) break :found object.bytes;
            return error.MissingOracleObject;
        };
        if (std.mem.eql(u8, hex, "-")) {
            try testing.expectEqual(@as(usize, 0), bytes.len);
            continue;
        }
        try testing.expectEqual(hex.len / 2, bytes.len);
        for (bytes, 0..) |actual, i| try testing.expectEqual(try std.fmt.parseInt(u8, hex[i * 2 ..][0..2], 16), actual);
        total += bytes.len;
    }
    return total;
}

test "owned initialized globals match unchanged independent numeric and string byte oracles" {
    var module = try parse(testing.allocator, @embedFile("fixtures/data-oracle.ssa") ++ "\n" ++ @embedFile("fixtures/data-string-oracle.ssa"));
    defer module.deinit();
    var globals = try global_memory.Space.init(testing.allocator, &module, .{});
    defer globals.deinit();
    try testing.expectEqual(@as(usize, 1896), try checkOracle(&globals, &module, @embedFile("fixtures/data-oracle.tsv")));
    try testing.expectEqual(@as(usize, 358), try checkOracle(&globals, &module, @embedFile("fixtures/data-string-oracle.tsv")));
    // Independent storage: a second materialization and the module remain unchanged.
    @memset(globals.objects[0].bytes, 0xa5);
    var fresh = try global_memory.Space.init(testing.allocator, &module, .{});
    defer fresh.deinit();
    _ = try checkOracle(&fresh, &module, @embedFile("fixtures/data-oracle.tsv"));
    _ = try checkOracle(&fresh, &module, @embedFile("fixtures/data-string-oracle.tsv"));
}

test "global packing is explicit endian raw bits with no field padding or borrowed string storage" {
    var module = try parse(testing.allocator, "data $g = align 1 { b 171, h 4660, w 2309737967, l 81985529216486895, z 3, b \"A\\000Z\" }");
    defer module.deinit();
    try module.data.items[0].append(.{ .single_bits = 0x80000000 });
    try module.data.items[0].append(.{ .double_bits = 0x7ff0000000000001 });
    const little = "ab3412efcdab89efcdab896745230100000041005a00000080010000000000f07f";
    const big = "ab123489abcdef0123456789abcdef00000041005a800000007ff0000000000001";
    for ([_]std.builtin.Endian{ .little, .big }, [_][]const u8{ little, big }) |endian, hex| {
        var space = try evaluation_memory.Space.initForModule(testing.allocator, null, null, &module, .{ .endian = endian });
        defer space.deinit();
        const object = space.globals.?.objects[0];
        try testing.expectEqual(hex.len / 2, object.bytes.len);
        for (object.bytes, 0..) |actual, i| try testing.expectEqual(try std.fmt.parseInt(u8, hex[i * 2 ..][0..2], 16), actual);
        try testing.expectEqual(@as(u64, 0x0123456789abcdef), (try space.read(.long, .long, object.address + 7)).long);
        try testing.expectEqual(@as(u32, 0x80000000), (try space.read(.single, .single, object.address + 21)).single_bits);
        try testing.expectEqual(@as(u64, 0x7ff0000000000001), (try space.read(.double, .double, object.address + 25)).double_bits);
        try space.write(.byte, .{ .word = 0xff }, object.address + 19);
        try testing.expectEqualStrings("A\x00Z", module.data.items[0].items.items[5].bytes);
    }
}

test "global aligned guarded layout charges empty objects and rejects overflowing or overlapping reservations" {
    var module = try parse(testing.allocator, "data $a = align 1 { b 1 }\ndata $b = align 64 { b 2 }\ndata $empty = align 64 {}\nfunction l $f() {\n@e\nret 0\n}");
    defer module.deinit();
    var space = try evaluation_memory.Space.initForModule(testing.allocator, null, null, &module, .{ .max_bytes = 144 });
    defer space.deinit();
    const objects = space.globals.?.objects;
    try testing.expectEqual(@as(u64, 0x200000000), objects[0].address);
    try testing.expectEqual(objects[0].address + 64, objects[1].address);
    try testing.expectEqual(objects[0].address + 128, objects[2].address);
    try testing.expectError(error.MemoryOutOfBounds, space.read(.unsigned_byte, .long, objects[2].address));
    try testing.expectError(error.MemoryOutOfBounds, space.read(.unsigned_half, .long, objects[0].address));
    try testing.expectError(error.GlobalLimitExceeded, global_memory.Space.init(testing.allocator, &module, .{ .max_bytes = 143 }));
    for ([_]global_memory.Options{ .{ .base = 0 }, .{ .base = 65 }, .{ .base = 0xffffffffffffffc0, .max_bytes = 65 } }) |options| {
        try testing.expectError(error.InvalidGlobalRange, global_memory.Space.init(testing.allocator, &module, options));
    }
    var image = try memory.Image.init(testing.allocator, 1, .{ .base = 0x200000040 });
    defer image.deinit();
    try testing.expectError(error.InvalidGlobalRange, evaluation_memory.Space.initForModule(testing.allocator, &image, null, &module, .{ .max_bytes = 128 }));
    try testing.expectError(error.InvalidGlobalRange, evaluation_memory.Space.initForModule(testing.allocator, null, .{ .base = 0x200000080, .max_bytes = 64 }, &module, .{ .max_bytes = 192 }));
    // Complete configured reservations, even empty portions, are kept disjoint.
    try testing.expectError(error.InvalidGlobalRange, evaluation_memory.Space.initForModule(testing.allocator, null, .{ .base = 0x200001000, .max_bytes = 64 }, &module, .{ .max_bytes = 8192 }));
    var empty_module = try parse(testing.allocator, "function l $f() {\n@e\nret 0\n}");
    defer empty_module.deinit();
    var empty = try global_memory.Space.init(testing.allocator, &empty_module, .{ .max_bytes = 0 });
    defer empty.deinit();
    try testing.expectEqual(@as(usize, 0), empty.objects.len);
    try testing.expectError(error.GlobalLimitExceeded, global_memory.Space.init(testing.allocator, &module, .{ .max_bytes = 0 }));
    var zero_module = try parse(testing.allocator, "data $a = {}\ndata $b = {}");
    defer zero_module.deinit();
    var zeros = try global_memory.Space.init(testing.allocator, &zero_module, .{ .max_bytes = 32 });
    defer zeros.deinit();
    try testing.expectEqual(zeros.objects[0].address + 16, zeros.objects[1].address);
    try testing.expectEqual(@as(usize, 0), zeros.objects[0].bytes.len);
    try testing.expectEqual(@as(usize, 0), zeros.objects[1].bytes.len);
    var zero_reservation = try evaluation_memory.Space.initForModule(testing.allocator, &image, null, &empty_module, .{ .base = image.base, .max_bytes = 0 });
    defer zero_reservation.deinit();
    module.data.items[0].byte_len += 1;
    try testing.expectError(error.InvalidDataSize, global_memory.Space.init(testing.allocator, &module, .{}));
    module.data.items[0].byte_len -= 1;
}

test "global resolution checks u64 arithmetic but accesses enforce individual object extents" {
    var module = try parse(testing.allocator, "data $g = { l 1 }\nfunction l $f() {\n@e\nret $g+1\n}");
    defer module.deinit();
    var space = try evaluation_memory.Space.initForModule(testing.allocator, null, null, &module, .{ .base = 64, .max_bytes = 64 });
    defer space.deinit();
    const symbol = module.data.items[0].name;
    try testing.expectEqual(@as(u64, 0), try space.symbolAddress(symbol, -64));
    try testing.expectError(error.GlobalAddressOverflow, space.symbolAddress(symbol, std.math.minInt(i32)));
    const one_past = try space.symbolAddress(symbol, 8);
    try testing.expectError(error.MemoryOutOfBounds, space.read(.unsigned_byte, .long, one_past));
    try testing.expectEqual(@as(u64, 1), (try space.read(.long, .long, 64)).long); // Numeric forgery is not a capability.
    var top = try evaluation_memory.Space.initForModule(testing.allocator, null, null, &module, .{ .base = 0xffffffffffffffc0, .max_bytes = 64 });
    defer top.deinit();
    try testing.expectError(error.GlobalAddressOverflow, top.symbolAddress(symbol, 64));
    try testing.expectEqual(@as(u64, 0xffffffff7fffffc0), try top.symbolAddress(symbol, std.math.minInt(i32)));
    try testing.expectError(error.UnsupportedSymbolAddress, space.symbolAddress(module.functions.items[0].name, 0));
    try testing.expectError(error.UnsupportedSymbolAddress, space.symbolAddress(try module.symbols.intern("external"), 0));
}

fn runShared(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, fixture);
    defer module.deinit();
    var image = try memory.Image.init(allocator, 8, .{});
    defer image.deinit();
    const options: interpreter.Options = .{ .memory_image = &image, .stack_memory = .{}, .global_memory = .{} };
    for (0..2) |_| {
        try testing.expectEqual(@as(u64, 24), (try interpreter.evaluateModule(allocator, &module, entry, &.{.{ .long = image.base }}, options)).?.long);
        try testing.expectEqual(@as(u64, 12), (try image.read(.long, .long, image.base)).long);
        try testing.expectEqual(@as(u64, 7), module.data.items[0].items.items[0].long);
    }
    if (interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 3)), &.{.{ .long = image.base }}, options)) |_| return error.ExpectedExternalRefusal else |err| {
        if (err != error.UnsupportedExternalCall) return err;
    }
    try testing.expectEqual(@as(u64, 99), (try image.read(.long, .long, image.base)).long);
    if (interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 4)), &.{.{ .long = image.base }}, options)) |_| return error.ExpectedBoundsRefusal else |err| {
        if (err != error.MemoryOutOfBounds) return err;
    }
    try testing.expectEqual(@as(u64, 55), (try image.read(.long, .long, image.base)).long);
}
test "global mutations share all frames survive child stack release reset each evaluation and never mutate module" {
    try runShared(testing.allocator);
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    for (module.functions.items) |f| _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
    try testing.expectEqual(@as(u64, 122), (try interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 2)), &.{}, .{ .global_memory = .{} })).?.long);
    for ([_]u32{ 0, 1 }, [_]u64{ 66, 7 }) |take, expected| {
        try testing.expectEqual(expected, (try interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 5)), &.{.{ .word = take }}, .{ .global_memory = .{} })).?.long);
    }
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 5)), &.{.{ .word = 1 }}, .{ .global_memory = .{}, .max_steps = 2 }));
    try testing.expectEqual(@as(u32, 2), (try interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 6)), &.{}, .{ .global_memory = .{} })).?.word);
    try testing.expectEqual(@as(u32, 1), (try interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 6)), &.{}, .{ .global_memory = .{ .base = 64, .max_bytes = 256 } })).?.word);
    try testing.expectEqual(@as(u64, 66), (try interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 7)), &.{}, .{ .global_memory = .{} })).?.long);
}

test "global Image and stack blits are checked atomically across byte orders initialization and guards" {
    var module = try parse(testing.allocator, "data $a = { l 1234605616436508552 }\ndata $b = { z 8 }");
    defer module.deinit();
    var image = try memory.Image.init(testing.allocator, 8, .{ .endian = .big });
    defer image.deinit();
    var space = try evaluation_memory.Space.initForModule(testing.allocator, &image, .{}, &module, .{});
    defer space.deinit();
    const a = space.globals.?.objects[0].address;
    const b = space.globals.?.objects[1].address;
    const mark = space.mark();
    const stack = try space.allocate(8);
    try testing.expectError(error.UninitializedMemory, space.copy(stack, b, 8));
    try testing.expectEqual(@as(u64, 0), (try space.read(.long, .long, b)).long);
    try space.copy(a, image.base, 8);
    try testing.expectEqual(@as(u64, 0x8877665544332211), (try image.read(.long, .long, image.base)).long);
    try space.copy(image.base, stack, 8);
    try testing.expectEqual(@as(u64, 0x1122334455667788), (try space.read(.long, .long, stack)).long);
    try space.copy(stack, b, 8);
    try testing.expectEqual(@as(u64, 0x1122334455667788), (try space.read(.long, .long, b)).long);
    try testing.expectError(error.PartialMemoryOverlap, space.copy(b, b + 1, 7));
    try testing.expectError(error.MemoryOutOfBounds, space.copy(a + 1, b, 8));
    try testing.expectError(error.MemoryOutOfBounds, space.write(.long, .{ .long = 0 }, b + 1));
    try testing.expectEqual(@as(u64, 0x1122334455667788), (try space.read(.long, .long, b)).long);
    try space.copy(0, std.math.maxInt(u64), 0);
    space.releaseTo(mark);
    try testing.expectError(error.MemoryOutOfBounds, space.read(.long, .long, stack));
    try testing.expectEqual(@as(u64, 0x1122334455667788), (try space.read(.long, .long, b)).long);
}

test "global opt-in defaults context eager relocation boundary and reached error precedence remain explicit" {
    var module = try parse(testing.allocator, "data $g = { l 7 }\nfunction l $f(w %take) {\n@e\njnz %take, @yes, @no\n@yes\nret $g\n@no\nret 9\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    try testing.expectEqual(@as(u64, 9), (try interpreter.evaluateModule(testing.allocator, &module, entry, &.{.{ .word = 0 }}, .{})).?.long);
    try testing.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(testing.allocator, &module, entry, &.{.{ .word = 1 }}, .{}));
    try testing.expectError(error.GlobalsRequireModule, interpreter.evaluate(testing.allocator, f, &.{.{ .word = 0 }}, .{ .global_memory = .{} }));
    try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluate(testing.allocator, f, &.{.{ .word = 0 }}, .{ .max_call_depth = 0, .global_memory = .{} }));
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, entry, &.{.{ .word = 1 }}, .{ .max_steps = 1, .global_memory = .{} }));
    try testing.expectError(error.ArgumentCountMismatch, interpreter.evaluateModule(testing.allocator, &module, entry, &.{}, .{ .global_memory = .{} }));
    var relocation = try parse(testing.allocator, "data $unused = { l $external+1 }\nfunction l $f() {\n@e\nret 9\n}");
    defer relocation.deinit();
    try testing.expectEqual(@as(u64, 9), (try interpreter.evaluateModule(testing.allocator, &relocation, entry, &.{}, .{})).?.long);
    try testing.expectError(error.UnsupportedGlobalInitializer, interpreter.evaluateModule(testing.allocator, &relocation, entry, &.{}, .{ .global_memory = .{}, .max_steps = 0 }));
    relocation.data.items[0].items.items[0].symbol_address.symbol = @fromBackingInt(std.math.maxInt(u32));
    try testing.expectError(error.InvalidSymbol, interpreter.evaluateModule(testing.allocator, &relocation, entry, &.{}, .{ .global_memory = .{} }));
    var address_error = try parse(testing.allocator, "data $g = { l 7 }\nfunction l $f(l %image) {\n@e\nstorel 101, %image\nret $g+-2147483648\n}");
    defer address_error.deinit();
    var image = try memory.Image.init(testing.allocator, 8, .{});
    defer image.deinit();
    const error_options: interpreter.Options = .{ .memory_image = &image, .global_memory = .{ .base = 64, .max_bytes = 64 } };
    try testing.expectError(error.GlobalAddressOverflow, interpreter.evaluateModule(testing.allocator, &address_error, entry, &.{.{ .long = image.base }}, error_options));
    try testing.expectEqual(@as(u64, 101), (try image.read(.long, .long, image.base)).long);
    var exhausted = error_options;
    exhausted.max_steps = 1;
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &address_error, entry, &.{.{ .long = image.base }}, exhausted));
    try testing.expectEqual(@as(u64, 101), (try image.read(.long, .long, image.base)).long);
    var indirect = try parse(testing.allocator, "data $g = { l 7 }\nfunction l $f() {\n@e\n%p =l copy $g\n%r =l call %p()\nret %r\n}");
    defer indirect.deinit();
    try testing.expectError(error.UnsupportedIndirectCall, interpreter.evaluateModule(testing.allocator, &indirect, entry, &.{}, .{ .global_memory = .{} }));
    var external = try parse(testing.allocator, "function $f() {\n@e\ncall $external(l $unknown)\nret\n}");
    defer external.deinit();
    try testing.expectError(error.UnsupportedExternalCall, interpreter.evaluateModule(testing.allocator, &external, entry, &.{}, .{ .global_memory = .{} }));
}

fn exercise(allocator: std.mem.Allocator) !void {
    try runShared(allocator);
    var module = try parse(allocator, "data $a = { b \"owned\", l 7 }\ndata $b = { z 16 }\nfunction l $f() {\n@e\n%x =l loadub $a+1\nret %x\n}");
    defer module.deinit();
    try testing.expectEqual(@as(u64, 'w'), (try interpreter.evaluateModule(allocator, &module, entry, &.{}, .{ .global_memory = .{} })).?.long);
    var space = try evaluation_memory.Space.initForModule(allocator, null, .{}, &module, .{});
    defer space.deinit();
    const stack = try space.allocate(8);
    try testing.expectError(error.UninitializedMemory, space.copy(stack, space.globals.?.objects[1].address, 8));
}
test "all global materialization nested frames memory and failure paths release every owned allocation" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
