const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const memory = @import("memory.zig");
const interpreter = @import("interpreter.zig");
const entry: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 0));
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "memory-eval", .text = text }, &diagnostic);
}
fn fromBits(ty: ir.ScalarType, bits: u64) ir.Constant {
    return switch (ty) {
        .word => .{ .word = @truncate(bits) },
        .long => .{ .long = bits },
        .single => .{ .single_bits = @truncate(bits) },
        .double => .{ .double_bits = bits },
    };
}
fn bitsOf(value: ir.Constant) u64 {
    return switch (value) {
        .word => |v| v,
        .long => |v| v,
        .single_bits => |v| v,
        .double_bits => |v| v,
    };
}

test "owned memory image reserves null checks overflow and initializes even empty storage" {
    try testing.expectError(error.InvalidMemoryRange, memory.Image.init(testing.allocator, 1, .{ .base = 0 }));
    try testing.expectError(error.InvalidMemoryRange, memory.Image.init(testing.allocator, 9, .{ .base = std.math.maxInt(u64) - 7 }));
    var empty = try memory.Image.init(testing.allocator, 0, .{});
    defer empty.deinit();
    try testing.expectError(error.MemoryOutOfBounds, empty.addressAt(0));
    try testing.expectError(error.MemoryOutOfBounds, empty.read(.unsigned_byte, .word, empty.base));
    var image = try memory.Image.init(testing.allocator, 8, .{ .base = std.math.maxInt(u64) - 7 });
    defer image.deinit();
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0, 0, 0, 0, 0 }, image.bytes);
    try testing.expectEqual(std.math.maxInt(u64), try image.addressAt(7));
    try image.write(.byte, .{ .word = 255 }, std.math.maxInt(u64));
    try testing.expectEqual(@as(u32, 255), (try image.read(.unsigned_byte, .word, std.math.maxInt(u64))).word);
    try testing.expectError(error.MemoryOutOfBounds, image.read(.unsigned_half, .word, std.math.maxInt(u64)));
    try testing.expectError(error.MemoryOutOfBounds, image.write(.long, .{ .long = 1 }, std.math.maxInt(u64)));
    try testing.expectError(error.MemoryOutOfBounds, image.read(.long, .long, 0));
    try testing.expectError(error.MemoryOutOfBounds, image.addressAt(8));
    try image.write(.long, .{ .long = 0xfedcba9876543210 }, image.base);
    try testing.expectEqual(@as(u64, 0xfedcba9876543210), (try image.read(.long, .long, image.base)).long);
}

test "invalid image accesses and types never partially write or wrap addresses" {
    var image = try memory.Image.init(testing.allocator, 16, .{});
    defer image.deinit();
    for (std.enums.values(ir.StoreKind)) |kind| {
        const value = fromBits(kind.valueType(), std.math.maxInt(u64));
        for ([_]u64{ 0, image.base - 1, image.base + 16, std.math.maxInt(u64) }) |address| {
            @memset(image.bytes, 0xa5);
            try testing.expectError(error.MemoryOutOfBounds, image.write(kind, value, address));
            for (image.bytes) |byte| try testing.expectEqual(@as(u8, 0xa5), byte);
        }
        for (std.enums.values(ir.ScalarType)) |ty| if (ty != kind.valueType()) {
            @memset(image.bytes, 0xa5);
            try testing.expectError(error.TypeMismatch, image.write(kind, fromBits(ty, 1), image.base));
            for (image.bytes) |byte| try testing.expectEqual(@as(u8, 0xa5), byte);
        };
    }
    // The last byte is writable, but no multi-byte partial write may start there.
    for ([_]ir.StoreKind{ .half, .word, .long, .single, .double }) |kind| {
        @memset(image.bytes, 0xa5);
        try testing.expectError(error.MemoryOutOfBounds, image.write(kind, fromBits(kind.valueType(), 1), image.base + 15));
        for (image.bytes) |byte| try testing.expectEqual(@as(u8, 0xa5), byte);
    }
    for (std.enums.values(ir.LoadKind)) |kind| {
        const ty: ir.ScalarType = switch (kind) {
            .single => .single,
            .double => .double,
            else => .long,
        };
        try testing.expectError(error.MemoryOutOfBounds, image.read(kind, ty, image.base + 16));
        const wrong: ir.ScalarType = if (ty == .single) .double else .single;
        try testing.expectError(error.TypeMismatch, image.read(kind, wrong, image.base));
    }
}

test "1472 independent Python memory cases match image APIs and interpreter at all byte offsets" {
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/memory-oracle.tsv"), '\n');
    var case_count: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const direction = fields.next().?;
        const endian = std.meta.stringToEnum(std.builtin.Endian, fields.next().?).?;
        const opcode = fields.next().?;
        const ty = fields.next().?;
        const input = fields.next().?;
        const expected = fields.next().?;
        var image = try memory.Image.init(testing.allocator, 24, .{ .base = 0x100000000, .endian = endian });
        defer image.deinit();
        const is_load = direction[0] == 'L';
        const input_ty = if (ty[0] == 'w' or ty[0] == 's') "w" else "l";
        const text = if (is_load)
            try std.fmt.allocPrint(testing.allocator, "function {s} $f(l %p) {{\n@e\n%v ={s} {s} %p\nret %v\n}}", .{ ty, ty, opcode })
        else if (ty[0] == 's' or ty[0] == 'd')
            try std.fmt.allocPrint(testing.allocator, "function $f(l %p, {s} %bits) {{\n@e\n%v ={s} cast %bits\n{s} %v, %p\nret\n}}", .{ input_ty, ty, opcode })
        else
            try std.fmt.allocPrint(testing.allocator, "function $f(l %p, {s} %bits) {{\n@e\n{s} %bits, %p\nret\n}}", .{ ty, opcode });
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        const f = module.functions.items[0];
        for (0..8) |offset| {
            @memset(image.bytes, 0xa5);
            const address = try image.addressAt(offset);
            if (is_load) {
                var raw: [8]u8 = undefined;
                _ = try std.fmt.hexToBytes(&raw, input);
                @memcpy(image.bytes[offset..][0..8], &raw);
                const wanted = try std.fmt.parseInt(u64, expected, 10);
                const instruction = f.blocks.items[0].instructions.items[0].load;
                const result_type = f.values.items[@backingInt(instruction.result)].scalar_type;
                try testing.expectEqual(wanted, bitsOf(try image.read(instruction.kind, result_type, address)));
                const actual = (try interpreter.evaluate(testing.allocator, f, &.{.{ .long = address }}, .{ .memory_image = &image })).?;
                try testing.expectEqual(result_type, actual.scalarType());
                try testing.expectEqual(wanted, bitsOf(actual));
            } else {
                var expected_bytes: [8]u8 = undefined;
                const selected = try std.fmt.hexToBytes(&expected_bytes, expected);
                var expected_image: [24]u8 = @splat(0xa5);
                @memcpy(expected_image[offset..][0..selected.len], selected);
                const value_bits = try std.fmt.parseInt(u64, input, 16);
                const instruction = f.blocks.items[0].instructions.items[f.blocks.items[0].instructions.items.len - 1].store;
                try image.write(instruction.kind, fromBits(instruction.kind.valueType(), value_bits), address);
                try testing.expectEqualSlices(u8, &expected_image, image.bytes);
                @memset(image.bytes, 0xa5);
                const argument = fromBits(if (input_ty[0] == 'w') .word else .long, value_bits);
                try testing.expectEqual(@as(?ir.Constant, null), try interpreter.evaluate(testing.allocator, f, &.{ .{ .long = address }, argument }, .{ .memory_image = &image }));
                try testing.expectEqualSlices(u8, &expected_image, image.bytes);
            }
        }
        case_count += 1;
    }
    try testing.expectEqual(@as(usize, 1472), case_count);
}

const nested =
    \\function l $memory_sum(l %p, w %n) {
    \\@entry
    \\storel 0, %p
    \\jmp @loop
    \\@loop
    \\%i =w phi @entry %n, @body %next
    \\jnz %i, @body, @done
    \\@body
    \\call $memory_inc(l %p)
    \\%next =w sub %i, 1
    \\jmp @loop
    \\@done
    \\%r =l loadl %p
    \\ret %r
    \\}
    \\function $memory_inc(l %p) {
    \\@entry
    \\%v =l loadl %p
    \\%next =l add %v, 1
    \\storel %next, %p
    \\ret
    \\}
;

test "one borrowed image spans module frames loop phis repeated invocations and folding" {
    var module = try parse(testing.allocator, nested);
    defer module.deinit();
    for ([_]std.builtin.Endian{ .little, .big }) |endian| {
        var image = try memory.Image.init(testing.allocator, 16, .{ .endian = endian });
        defer image.deinit();
        for ([_]bool{ false, true }) |fold| {
            if (fold) for (module.functions.items) |f| {
                _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
            };
            for ([_]u32{ 0, 1, 7, 31 }) |n| {
                const args = [_]ir.Constant{ .{ .long = image.base + 1 }, .{ .word = n } };
                const result = (try interpreter.evaluateModule(testing.allocator, &module, entry, &args, .{ .memory_image = &image })).?;
                try testing.expectEqual(@as(u64, n), result.long);
                try testing.expectEqual(@as(u64, n), std.mem.readInt(u64, image.bytes[1..9], endian));
            }
        }
        try testing.expectError(error.CallDepthLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, entry, &.{ .{ .long = image.base }, .{ .word = 1 } }, .{ .memory_image = &image, .max_call_depth = 1 }));
    }
}

test "completed simulated stores persist after later faults budgets and callees without rollback" {
    for ([_]struct { tail: []const u8, expected: anyerror, steps: usize }{
        .{ .tail = "%x =l loadl 0\nret", .expected = error.MemoryOutOfBounds, .steps = 100 },
        .{ .tail = "%x =w div 1, 0\nret", .expected = error.DivisionByZero, .steps = 100 },
        .{ .tail = "hlt", .expected = error.Halted, .steps = 100 },
        .{ .tail = "ret", .expected = error.StepLimitExceeded, .steps = 1 },
        .{ .tail = "call $external()\nret", .expected = error.UnsupportedExternalCall, .steps = 100 },
    }) |case| {
        const text = try std.fmt.allocPrint(testing.allocator, "function $f(l %p) {{\n@e\nstorel 17, %p\n{s}\n}}", .{case.tail});
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        var image = try memory.Image.init(testing.allocator, 8, .{});
        defer image.deinit();
        try testing.expectError(case.expected, interpreter.evaluateModule(testing.allocator, &module, entry, &.{.{ .long = image.base }}, .{ .memory_image = &image, .max_steps = case.steps }));
        try testing.expectEqual(@as(u64, 17), std.mem.readInt(u64, image.bytes[0..8], .little));
    }
    var module = try parse(testing.allocator, "function $f(l %p) {\n@e\ncall $g(l %p)\nret\n}\nfunction $g(l %p) {\n@e\nstoreb 42, %p\nstorel 7, %p\nret\n}");
    defer module.deinit();
    var image = try memory.Image.init(testing.allocator, 1, .{});
    defer image.deinit();
    try testing.expectError(error.MemoryOutOfBounds, interpreter.evaluateModule(testing.allocator, &module, entry, &.{.{ .long = image.base }}, .{ .memory_image = &image }));
    try testing.expectEqual(@as(u8, 42), image.bytes[0]);
    image.bytes[0] = 99;
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, entry, &.{.{ .long = image.base }}, .{ .memory_image = &image, .max_steps = 0 }));
    try testing.expectEqual(@as(u8, 99), image.bytes[0]);
}

fn exercise(allocator: std.mem.Allocator) !void {
    var image = try memory.Image.init(allocator, 16, .{});
    defer image.deinit();
    var module = try parse(allocator, nested);
    defer module.deinit();
    const arguments = [_]ir.Constant{ .{ .long = image.base + 1 }, .{ .word = 3 } };
    try testing.expectEqual(@as(u64, 3), (try interpreter.evaluateModule(allocator, &module, entry, &arguments, .{ .memory_image = &image })).?.long);
    if (interpreter.evaluateModule(allocator, &module, entry, &.{ .{ .long = image.base + 15 }, .{ .word = 1 } }, .{ .memory_image = &image })) |_| return error.ExpectedBoundsFailure else |err| {
        if (err != error.MemoryOutOfBounds) return err;
    }
}
test "memory image and nested interpreter clean up every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
