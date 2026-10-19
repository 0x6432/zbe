const std = @import("std");
const testing = std.testing;
const ir = @import("ir.zig");
const amd64 = @import("amd64.zig");
const interpreter = @import("interpreter.zig");
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "immediate-selection", .text = text }, &diagnostic);
}
test "literal selection and refusal match independently encoded width boundaries" {
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/immediate_selection_oracle.tsv"), '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeScalar(u8, line, '\t');
        const ty = fields.next().?;
        const op = fields.next().?;
        const rhs = fields.next().?;
        const lhs = try std.fmt.parseInt(u64, fields.next().?, 10);
        const expected = try std.fmt.parseInt(u64, fields.next().?, 10);
        const eligible = std.mem.eql(u8, fields.next().?, "1");
        const encoding = fields.next().?;
        const text = try std.fmt.allocPrint(testing.allocator, "export function {s} $f({s} %x) {{\n@e\n%r ={s} {s} %x, {s}\nret %r\n}}", .{ ty, ty, ty, op, rhs });
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        const f = module.functions.items[0];
        const original = f.blocks.items[0].instructions.items[0];
        const assembly = try amd64.emit(testing.allocator, &module);
        defer testing.allocator.free(assembly);
        const suffix: u8 = if (ty[0] == 'w') 'l' else 'q';
        const shape = if (eligible)
            try std.fmt.allocPrint(testing.allocator, "\t{s}{c} ${s}, %{s}\n", .{ op, suffix, encoding, if (ty[0] == 'w') "eax" else "rax" })
        else
            try std.fmt.allocPrint(testing.allocator, "\t{s}{c} %{s}, %rax\n", .{ op, suffix, "r10" });
        defer testing.allocator.free(shape);
        try testing.expect(std.mem.indexOf(u8, assembly, shape) != null);
        try testing.expectEqualDeep(original, f.blocks.items[0].instructions.items[0]);
        const args = [_]ir.Constant{if (ty[0] == 'w') .{ .word = @intCast(lhs) } else .{ .long = lhs }};
        const evaluated = (try interpreter.evaluate(testing.allocator, f, &args, .{ .max_steps = 2 })).?;
        try testing.expectEqual(expected, if (ty[0] == 'w') @as(u64, evaluated.word) else evaluated.long);
        count += 1;
    }
    try testing.expectEqual(@as(usize, 500), count);
}

test "nonliteral projection symbol float and other integer operations retain fallback paths" {
    const source = "function l $f(l %x, l %y) {\n@e\n%n =l copy 7\n%a =l add %x, %n\n%b =l sub 7, %x\n%c =l add %b, $external+3\n%d =l mul %c, 7\n%e =l div %d, 7\nret %e\n}\nfunction w $g(w %x, l %y) {\n@e\n%r =w xor %x, %y\nret %r\n}\nfunction d $h(d %x) {\n@e\n%r =d add %x, d_1\nret %r\n}";
    var module = try parse(testing.allocator, source);
    defer module.deinit();
    const assembly = try amd64.emit(testing.allocator, &module);
    defer testing.allocator.free(assembly);
    for ([_][]const u8{ "addq %r10, %rax", "subq %r10, %rax", "imulq %r10, %rax", "idivq %r10", "xorl %r10d, %eax", "addsd %xmm1, %xmm0" }) |needle|
        try testing.expect(std.mem.indexOf(u8, assembly, needle) != null);
    try testing.expect(std.mem.indexOf(u8, assembly, "\taddq $7") == null);
    try testing.expect(module.functions.items[1].blocks.items[0].instructions.items[0].binary.rhs == .low_word);
}

const exercise_source = "function l $f(l %x) {\n@e\n%a =l add %x, 2147483647\n%b =l sub %a, 18446744071562067968\n%c =l and %b, 4294967295\n%d =l or %c, -1\n%r =l xor %d, 128\nret %r\n}";
fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, exercise_source);
    defer module.deinit();
    const assembly = try amd64.emit(allocator, &module);
    defer allocator.free(assembly);
}
test "all allocation failures clean up and emission permits same-module retry without mutation" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        var module = try parse(testing.allocator, exercise_source);
        defer module.deinit();
        const before = try testing.allocator.dupe(ir.Instruction, module.functions.items[0].blocks.items[0].instructions.items);
        defer testing.allocator.free(before);
        var counter = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
        const expected = try amd64.emitWithOptions(counter.allocator(), &module, options);
        const saved = try testing.allocator.dupe(u8, expected);
        defer testing.allocator.free(saved);
        counter.allocator().free(expected);
        try testing.expectEqual(counter.allocated_bytes, counter.freed_bytes);
        for (0..counter.alloc_index) |fail_at| {
            var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = fail_at, .resize_fail_index = 0 });
            try testing.expectError(error.OutOfMemory, amd64.emitWithOptions(failing.allocator(), &module, options));
            try testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
            try testing.expectEqualDeep(before, module.functions.items[0].blocks.items[0].instructions.items);
            failing.fail_index = std.math.maxInt(usize);
            const recovered = try amd64.emitWithOptions(failing.allocator(), &module, options);
            try testing.expectEqualStrings(saved, recovered);
            failing.allocator().free(recovered);
            try testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        }
    }
}
