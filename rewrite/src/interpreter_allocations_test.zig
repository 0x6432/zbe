const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const memory = @import("memory.zig");
const runtime = @import("evaluation_memory.zig");
const interpreter = @import("interpreter.zig");
const entry: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 0));
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "interpreter-allocations", .text = text }, &diagnostic);
}
fn bitsOf(value: ir.Constant) u64 {
    return switch (value) {
        .word => |v| v,
        .long => |v| v,
        .single_bits => |v| v,
        .double_bits => |v| v,
    };
}

test "synthetic stack validates full disjoint reservation before any allocation" {
    for ([_]runtime.StackOptions{
        .{ .base = 0 },                                          .{ .base = 17 },
        .{ .base = std.math.maxInt(u64) - 15, .max_bytes = 17 },
    }) |options| try testing.expectError(error.InvalidStackRange, runtime.Space.init(testing.allocator, null, options));
    var image = try memory.Image.init(testing.allocator, 32, .{});
    defer image.deinit();
    for ([_]u64{ image.base - 16, image.base, image.base + 16 }) |base| {
        try testing.expectError(error.InvalidStackRange, runtime.Space.init(testing.allocator, &image, .{ .base = base, .max_bytes = 32 }));
    }
    // Both adjacent boundaries and the last representable byte are valid.
    for ([_]runtime.StackOptions{
        .{ .base = image.base - 32, .max_bytes = 32 },
        .{ .base = image.base + 32, .max_bytes = 32 },
        .{ .base = std.math.maxInt(u64) - 31, .max_bytes = 32 },
    }) |options| {
        var space = try runtime.Space.init(testing.allocator, &image, options);
        defer space.deinit();
        const p = try space.allocate(1);
        try space.write(.byte, .{ .word = 73 }, p);
        try testing.expectEqual(@as(u32, 73), (try space.read(.unsigned_byte, .word, p)).word);
    }
    var zero = try runtime.Space.init(testing.allocator, &image, .{ .base = image.base, .max_bytes = 0 });
    defer zero.deinit();
    try testing.expectEqual(@as(u64, 0), try zero.allocate(0));
    try testing.expectError(error.StackLimitExceeded, zero.allocate(1));
    var no_stack = try runtime.Space.init(testing.allocator, &image, null);
    defer no_stack.deinit();
    try testing.expectError(error.UnsupportedAllocation, no_stack.allocate(0));
}

test "synthetic allocation sizes round independently and bounds exclude padding guards dead extents" {
    var space = try runtime.Space.init(testing.allocator, null, .{ .max_bytes = 256 });
    defer space.deinit();
    const caller = try space.allocate(1);
    const mark = space.mark();
    const child = try space.allocate(17);
    try testing.expectEqual(caller + 32, child);
    try testing.expectEqual(@as(u64, 0), child % 16);
    try space.write(.byte, .{ .word = 91 }, caller);
    try space.write(.byte, .{ .word = 19 }, child + 16);
    for ([_]u64{ 0, caller + 1, caller + 16, child + 17, child + 32, std.math.maxInt(u64) }) |p| {
        try testing.expectError(error.MemoryOutOfBounds, space.read(.unsigned_byte, .word, p));
        try testing.expectError(error.MemoryOutOfBounds, space.write(.byte, .{ .word = 0 }, p));
    }
    try testing.expectError(error.MemoryOutOfBounds, space.write(.half, .{ .word = 0 }, child + 16));
    try testing.expectEqual(@as(u32, 19), (try space.read(.unsigned_byte, .word, child + 16)).word);
    space.releaseTo(mark);
    try testing.expectError(error.MemoryOutOfBounds, space.read(.unsigned_byte, .word, child));
    const sibling = try space.allocate(17);
    try testing.expectEqual(child + 48, sibling);
    try testing.expectError(error.MemoryOutOfBounds, space.write(.byte, .{ .word = 0 }, child));
    try testing.expectEqual(@as(u32, 91), (try space.read(.unsigned_byte, .word, caller)).word);
    const used = space.used;
    const count = space.mark();
    for ([_]u64{ std.math.maxInt(u64), std.math.maxInt(u64) - 14 }) |size|
        try testing.expectError(error.AllocationSizeOverflow, space.allocate(size));
    for ([_]u64{ std.math.maxInt(u64) - 15, 257, 256 }) |size|
        try testing.expectError(error.StackLimitExceeded, space.allocate(size));
    try testing.expectEqual(used, space.used);
    try testing.expectEqual(count, space.mark());
    space.releaseTo(0);
    try testing.expectEqual(used, space.used);
    try testing.expectEqual(@as(u64, 0), try space.allocate(0));
    // Exact cumulative reservation, including objects already freed.
    _ = try space.allocate(112); // 128 + earlier 128 = 256
    try testing.expectEqual(@as(usize, 256), space.used);
    try testing.expectError(error.StackLimitExceeded, space.allocate(1));
}

test "undefined stack bytes reject reads and copies without partial mutation" {
    var image = try memory.Image.init(testing.allocator, 32, .{});
    defer image.deinit();
    @memset(image.bytes, 0xa5);
    var space = try runtime.Space.init(testing.allocator, &image, .{});
    defer space.deinit();
    const a = try space.allocate(16);
    const b = try space.allocate(16);
    try testing.expectError(error.UninitializedMemory, space.read(.long, .long, a));
    try space.write(.byte, .{ .word = 42 }, a);
    try testing.expectError(error.UninitializedMemory, space.read(.unsigned_half, .word, a));
    try testing.expectError(error.UninitializedMemory, space.copy(a, image.base, 8));
    for (image.bytes) |byte| try testing.expectEqual(@as(u8, 0xa5), byte);
    try testing.expectError(error.UninitializedMemory, space.copy(a, b, 2));
    try testing.expectError(error.UninitializedMemory, space.read(.unsigned_byte, .word, b));
    try testing.expectError(error.UninitializedMemory, space.copy(b, b, 1));
    try space.copy(image.base, a, 16);
    try space.copy(a, b, 16);
    try space.copy(b, b, 16);
    try testing.expectEqual(@as(u64, 0xa5a5a5a5a5a5a5a5), (try space.read(.long, .long, b)).long);
    try testing.expectError(error.PartialMemoryOverlap, space.copy(a, a + 1, 8));
    try testing.expectError(error.MemoryOutOfBounds, space.copy(image.base, b + 15, 2));
    try testing.expectError(error.MemoryOutOfBounds, space.copy(a + 15, image.base, 2));
    try testing.expectError(error.TypeMismatch, space.write(.long, .{ .word = 0 }, a));
    try testing.expectError(error.TypeMismatch, space.read(.single, .word, a));
    try space.copy(0, std.math.maxInt(u64), 0);
    // Blits are raw bytes, independent of either region's scalar byte order.
    space.stack.?.endian = .big;
    try space.write(.word, .{ .word = 0x01020304 }, a + 1);
    try space.copy(a + 1, image.base + 3, 4);
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, image.bytes[3..7]);
}

test "1472 unchanged independent memory oracle rows pass through stack and cross-region blits at eight offsets" {
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/memory-oracle.tsv"), '\n');
    var rows: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const is_load = fields.next().?[0] == 'L';
        const endian = std.meta.stringToEnum(std.builtin.Endian, fields.next().?).?;
        const op = fields.next().?;
        const ty = fields.next().?;
        const input = fields.next().?;
        const expected = fields.next().?;
        const input_ty = if (ty[0] == 'w' or ty[0] == 's') "w" else "l";
        const prefix = "function {s} $f(l %image, l %offset, {s} %bits) {{\n@e\n%p =l alloc16 24\nblit %image, %p, 24\n%q =l add %p, %offset\n";
        const text = if (is_load)
            try std.fmt.allocPrint(testing.allocator, prefix ++ "%r ={s} {s} %q\nret %r\n}}", .{ ty, input_ty, ty, op })
        else if (ty[0] == 's' or ty[0] == 'd')
            try std.fmt.allocPrint(testing.allocator, prefix ++ "%v ={s} cast %bits\n{s} %v, %q\nblit %p, %image, 24\nret\n}}", .{ "", input_ty, ty, op })
        else
            try std.fmt.allocPrint(testing.allocator, prefix ++ "{s} %bits, %q\nblit %p, %image, 24\nret\n}}", .{ "", input_ty, op });
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        var image = try memory.Image.init(testing.allocator, 24, .{ .endian = endian });
        defer image.deinit();
        for (0..8) |offset| {
            @memset(image.bytes, 0xa5);
            var wanted: [24]u8 = @splat(0xa5);
            const value_bits: u64 = if (is_load) 0 else try std.fmt.parseInt(u64, input, 16);
            const argument: ir.Constant = if (input_ty[0] == 'w') .{ .word = @truncate(value_bits) } else .{ .long = value_bits };
            if (is_load) {
                _ = try std.fmt.hexToBytes(image.bytes[offset..][0..8], input);
            } else {
                var raw: [8]u8 = undefined;
                const bytes = try std.fmt.hexToBytes(&raw, expected);
                @memcpy(wanted[offset..][0..bytes.len], bytes);
            }
            const result = try interpreter.evaluate(testing.allocator, module.functions.items[0], &.{ .{ .long = image.base }, .{ .long = offset }, argument }, .{ .memory_image = &image, .stack_memory = .{ .endian = endian } });
            if (is_load) {
                try testing.expectEqual(try std.fmt.parseInt(u64, expected, 10), bitsOf(result.?));
            } else {
                try testing.expect(result == null);
                try testing.expectEqualSlices(u8, &wanted, image.bytes);
            }
        }
        rows += 1;
    }
    try testing.expectEqual(@as(usize, 1472), rows);
}

test "all allocation forms loop freshness and recursive caller lifetimes have independent expected results" {
    var module = try parse(testing.allocator, @embedFile("fixtures/native-allocations.ssa"));
    defer module.deinit();
    for ([_]bool{ false, true }) |fold| {
        if (fold) for (module.functions.items) |f| {
            _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
        };
        for (module.functions.items[0..3]) |f| {
            for ([_]u64{ 0, 1, 2, 7, 15, 16, 17, 31, 32, 63, 255, 256, 257, 4095, 4096, 4097 }) |size| {
                var expected: u64 = 0;
                for (0..@intCast(size)) |i| expected += (i + 193) % 256;
                const result = (try interpreter.evaluate(testing.allocator, f, &.{ .{ .long = size }, .{ .long = 193 } }, .{ .stack_memory = .{}, .max_steps = 200_000 })).?;
                try testing.expectEqual(expected, result.long);
            }
        }
        const fresh = module.functions.items[3];
        try testing.expectEqual(@as(u64, 33586), (try interpreter.evaluate(testing.allocator, fresh, &.{.{ .long = 300 }}, .{ .stack_memory = .{} })).?.long); // sum(0..255) + sum(0..43)
        var found_recursive = false;
        for (module.functions.items, 0..) |f, index| {
            if (std.mem.eql(u8, module.symbols.get(f.name).?, "alloc_recursive")) {
                found_recursive = true;
                const id: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, @intCast(index)));
                try testing.expectEqual(@as(u64, 500500), (try interpreter.evaluateModule(testing.allocator, &module, id, &.{.{ .long = 1000 }}, .{ .stack_memory = .{}, .max_call_depth = 1001 })).?.long);
            }
        }
        try testing.expect(found_recursive);
    }
}

const nested =
    \\function l $root() {
    \\@e
    \\%p =l alloc4 8
    \\storel 9, %p
    \\%r =l call $child(l %p)
    \\%v =l loadl %p
    \\%sum =l add %r, %v
    \\ret %sum
    \\}
    \\function l $child(l %parent) {
    \\@e
    \\%p =l alloc8 8
    \\storel 7, %p
    \\storel 11, %parent
    \\%r =l loadl %p
    \\ret %r
    \\}
;

test "child mutates caller object and return releases only its own objects" {
    var module = try parse(testing.allocator, nested);
    defer module.deinit();
    for (0..3) |_| try testing.expectEqual(@as(u64, 18), (try interpreter.evaluateModule(testing.allocator, &module, entry, &.{}, .{ .stack_memory = .{} })).?.long);
    const stale =
        \\function l $root() {
        \\@e
        \\%old =l call $escape()
        \\%new =l call $escape()
        \\%r =l loadl %old
        \\ret %r
        \\}
        \\function l $escape() {
        \\@e
        \\%p =l alloc16 8
        \\storel 99, %p
        \\ret %p
        \\}
    ;
    var escaped = try parse(testing.allocator, stale);
    defer escaped.deinit();
    try testing.expectError(error.MemoryOutOfBounds, interpreter.evaluateModule(testing.allocator, &escaped, entry, &.{}, .{ .stack_memory = .{} }));
    // Cumulative space cannot be evaded by returning and reusing a child frame.
    try testing.expectError(error.StackLimitExceeded, interpreter.evaluateModule(testing.allocator, &escaped, entry, &.{}, .{ .stack_memory = .{ .max_bytes = 32 } }));
}

test "stack instructions consume exact shared budgets and default refusal is preserved" {
    var module = try parse(testing.allocator, "function l $f() {\n@e\n%p =l alloc4 8\nstorel 73, %p\n%r =l loadl %p\nret %r\n}\nfunction l $zero() {\n@e\n%p =l alloc8 0\nret %p\n}");
    defer module.deinit();
    for (0..4) |steps| try testing.expectError(error.StepLimitExceeded, interpreter.evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .stack_memory = .{}, .max_steps = steps }));
    try testing.expectEqual(@as(u64, 73), (try interpreter.evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .stack_memory = .{}, .max_steps = 4 })).?.long);
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .stack_memory = .{ .max_bytes = 0 }, .max_steps = 0 }));
    try testing.expectError(error.UnsupportedAllocation, interpreter.evaluate(testing.allocator, module.functions.items[1], &.{}, .{}));
    try testing.expectEqual(@as(u64, 0), (try interpreter.evaluate(testing.allocator, module.functions.items[1], &.{}, .{ .stack_memory = .{ .max_bytes = 0 } })).?.long);
    var calls = try parse(testing.allocator, nested);
    defer calls.deinit();
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &calls, entry, &.{}, .{ .stack_memory = .{}, .max_steps = 10 }));
    try testing.expectEqual(@as(u64, 18), (try interpreter.evaluateModule(testing.allocator, &calls, entry, &.{}, .{ .stack_memory = .{}, .max_steps = 11 })).?.long);
}

fn exerciseErrors(allocator: std.mem.Allocator) !void {
    for ([_]struct { tail: []const u8, expected: anyerror, steps: usize = 100, capacity: usize = 128 }{
        .{ .tail = "%p =l alloc4 129\nret", .expected = error.StackLimitExceeded },
        .{ .tail = "%p =l alloc4 18446744073709551615\nret", .expected = error.AllocationSizeOverflow },
        .{ .tail = "%v =l loadl %object\nret", .expected = error.UninitializedMemory },
        .{ .tail = "blit %object, %image, 8\nret", .expected = error.UninitializedMemory },
        .{ .tail = "%v =l loadl 0\nret", .expected = error.MemoryOutOfBounds },
        .{ .tail = "%v =l div 1, 0\nret", .expected = error.DivisionByZero },
        .{ .tail = "hlt", .expected = error.Halted },
        .{ .tail = "call $external()\nret", .expected = error.UnsupportedExternalCall },
        .{ .tail = "call 0()\nret", .expected = error.UnsupportedIndirectCall },
        .{ .tail = "ret", .expected = error.StepLimitExceeded, .steps = 4 },
    }) |case| {
        const text = try std.fmt.allocPrint(allocator, "function $f(l %image) {{\n@e\nstorel 17, %image\n%parent =l alloc4 8\ncall $child(l %image)\nret\n}}\nfunction $child(l %image) {{\n@e\n%object =l alloc16 8\n{s}\n}}", .{case.tail});
        defer allocator.free(text);
        var module = try parse(allocator, text);
        defer module.deinit();
        var image = try memory.Image.init(allocator, 8, .{});
        defer image.deinit();
        if (interpreter.evaluateModule(allocator, &module, entry, &.{.{ .long = image.base }}, .{ .memory_image = &image, .stack_memory = .{ .max_bytes = case.capacity }, .max_steps = case.steps })) |_| return error.ExpectedFailure else |err| {
            if (err != case.expected) return err; // Propagate injected OOM, do not mask it.
        }
        try testing.expectEqual(@as(u64, 17), (try image.read(.long, .long, image.base)).long);
    }
}

test "earlier image writes persist across stack faults and unsupported calls" {
    try exerciseErrors(testing.allocator);
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, nested);
    defer module.deinit();
    for ([_]bool{ false, true }) |fold| {
        if (fold) for (module.functions.items) |f| {
            _ = try @import("optimize.zig").foldIntegerConstants(allocator, f);
        };
        const result = (try interpreter.evaluateModule(allocator, &module, entry, &.{}, .{ .stack_memory = .{} })).?;
        try testing.expectEqual(@as(u64, 18), result.long);
        if (interpreter.evaluateModule(allocator, &module, entry, &.{}, .{ .stack_memory = .{}, .max_call_depth = 1 })) |_| return error.ExpectedFailure else |err| {
            if (err != error.CallDepthLimitExceeded) return err;
        }
    }
    var recursive_module = try parse(allocator, "function l $sum(l %n) {\n@e\n%p =l alloc16 8\nstorel %n, %p\n%base =w ceql %n, 0\njnz %base, @done, @child\n@child\n%next =l sub %n, 1\n%r =l call $sum(l %next)\n%own =l loadl %p\n%total =l add %r, %own\nret %total\n@done\nret 0\n}");
    defer recursive_module.deinit();
    try testing.expectEqual(@as(u64, 78), (try interpreter.evaluateModule(allocator, &recursive_module, entry, &.{.{ .long = 12 }}, .{ .stack_memory = .{} })).?.long);
    var space = try runtime.Space.init(allocator, null, .{ .max_bytes = 4096 });
    defer space.deinit();
    const p = try space.allocate(16);
    try space.write(.long, .{ .long = 42 }, p);
    for (0..50) |_| _ = try space.allocate(1);
    try testing.expectEqual(@as(u64, 42), (try space.read(.long, .long, p)).long);
}

test "every stack object initialization metadata frame and error allocation cleans up" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
    try @import("test_support.zig").checkAllocationFailures(exerciseErrors);
}

test "each allocation publication failure can retry without losing live bytes or reservation" {
    for (0..3) |failure| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = failure, .resize_fail_index = 0 });
        var space = try runtime.Space.init(failing.allocator(), null, .{});
        defer space.deinit();
        try testing.expectError(error.OutOfMemory, space.allocate(8));
        try testing.expectEqual(@as(usize, 0), space.used);
        try testing.expectEqual(@as(usize, 0), space.mark());
        try testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        failing.fail_index = std.math.maxInt(usize);
        const first = try space.allocate(8);
        try testing.expectEqual(@as(u64, 0x100000000), first);
        try space.write(.long, .{ .long = 73 }, first);
        failing.fail_index = failing.alloc_index;
        try testing.expectError(error.OutOfMemory, space.allocate(17));
        try testing.expectEqual(@as(usize, 32), space.used);
        try testing.expectEqual(@as(usize, 1), space.mark());
        try testing.expectEqual(@as(u64, 73), (try space.read(.long, .long, first)).long);
        failing.fail_index = std.math.maxInt(usize);
        try testing.expectEqual(first + 32, try space.allocate(17));
    }
}
