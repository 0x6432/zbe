const std = @import("std");
const testing = std.testing;
const data = @import("data.zig");
const strings = @import("byte_strings.zig");
const source = @import("source.zig");
const frontend = @import("frontend.zig");
const amd64 = @import("amd64.zig");
const fixture = @embedFile("fixtures/data-string-oracle.ssa");
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?source.Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "data-strings", .text = text }, &diagnostic);
}

test "owned string data matches independent all-byte UTF8 escape and packed expectations" {
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/data-string-oracle.tsv"), '\n');
    var index: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeScalar(u8, line, '\t');
        const object = module.data.items[index];
        try testing.expectEqualStrings(fields.next().?, module.symbols.get(object.name).?);
        try testing.expectEqual(try std.fmt.parseInt(u8, fields.next().?, 10), object.alignment.bytes());
        try testing.expectEqual(std.mem.eql(u8, fields.next().?, "1"), object.linkage == .exported);
        const expected = fields.next().?;
        const hex: []const u8 = if (std.mem.eql(u8, expected, "-")) "" else expected;
        var offset: usize = 0;
        for (object.items.items) |item| {
            for (0..item.size()) |i| {
                const byte: u8 = switch (item) {
                    .bytes => |bytes| bytes[i],
                    .byte => |x| x,
                    .half => |x| @truncate(x >> @intCast(i * 8)),
                    .zero => 0,
                    else => return error.UnexpectedStringOracleField,
                };
                try testing.expect(offset * 2 + 2 <= hex.len);
                try testing.expectEqual(try std.fmt.parseInt(u8, hex[offset * 2 ..][0..2], 16), byte);
                offset += 1;
            }
        }
        try testing.expectEqual(hex.len / 2, offset);
        try testing.expectEqual(offset, try object.validate());
        index += 1;
    }
    try testing.expectEqual(@as(usize, 8), index);
    try testing.expectEqual(@as(usize, 0), module.data.items[5].byte_len);
}

test "byte string builders copy input and parser storage survives source mutation" {
    var object = data.Data.init(testing.allocator, @fromBackingInt(@as(u32, 0)));
    defer object.deinit();
    var input = [_]u8{ 1, 2, 3 };
    try object.append(.{ .bytes = &input });
    input[0] = 99;
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, object.items.items[0].bytes);
    const text = try testing.allocator.dupe(u8, "data $owned = { b \"hello\\000world\" }");
    defer testing.allocator.free(text);
    var module = try parse(testing.allocator, text);
    defer module.deinit();
    @memset(text, 'x');
    try testing.expectEqualStrings("owned", module.symbols.get(module.data.items[0].name).?);
    try testing.expectEqualSlices(u8, "hello\x00world", module.data.items[0].items.items[0].bytes);
}

test "byte string append is atomic on copy or table failure and respects decoded payload limits" {
    for (0..2) |failure| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
        var object = data.Data.init(failing.allocator(), @fromBackingInt(@as(u32, 0)));
        defer object.deinit();
        failing.fail_index = failing.alloc_index + failure;
        try testing.expectError(error.OutOfMemory, object.append(.{ .bytes = "abc" }));
        try testing.expectEqual(@as(usize, 0), object.items.items.len);
        try testing.expectEqual(@as(usize, 0), object.byte_len);
        failing.fail_index = std.math.maxInt(usize);
        try object.append(.{ .bytes = "abc" });
        try object.append(.{ .zero = data.max_object_bytes - 3 });
        try object.append(.{ .bytes = "" });
        try testing.expectError(error.DataTooLarge, object.append(.{ .bytes = "a" }));
        try testing.expectEqual(@as(usize, data.max_object_bytes), try object.validate());
    }
    const exact = try strings.decode(testing.allocator, "\"\\377\\x00\"", 2);
    defer testing.allocator.free(exact);
    try testing.expectEqualSlices(u8, &.{ 255, 0 }, exact);
    try testing.expectError(error.DataTooLarge, strings.decode(testing.allocator, "\"\\377\\x00\"", 1));
    try testing.expectError(error.DataTooLarge, parse(testing.allocator, "data $x = { z 16777216, b \"a\" }"));
}

test "byte decoder rejects malformed escapes raw line breaks and unsupported field classes" {
    for ([_][]const u8{ "", "abc", "\"", "\"abc\\\"", "\"a\nb\"", "\"a\rb\"", "\"\\q\"", "\"\\8\"", "\"\\400\"", "\"\\777\"", "\"\\x\"", "\"\\x0\"", "\"\\xG0\"", "\"\\u0041\"", "\"\\\n\"" }) |text| {
        try testing.expectError(error.InvalidStringLiteral, strings.decode(testing.allocator, text, 1024));
    }
    for ([_][]const u8{ "h", "w", "l", "s", "d", "z" }) |kind| {
        var buffer: [128]u8 = undefined;
        const text = try std.fmt.bufPrint(&buffer, "data $x = {{ {s} \"string\" }}", .{kind});
        try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
    }
    var diagnostic: ?source.Diagnostic = null;
    try testing.expectError(error.InvalidInput, frontend.parse(testing.allocator, .{ .name = "bad-escape", .text = "data $x = { b \"\\400\" }" }, &diagnostic));
    try testing.expectEqual(source.Diagnostic.Code.invalid_string, diagnostic.?.code);
    try testing.expectError(error.InvalidInput, parse(testing.allocator, "function l $f() {\n@e\nret \"string\"\n}"));
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, fixture ++ "\nfunction l $f() {\n@e\nret $string_all\n}");
    defer module.deinit();
    _ = try @import("optimize.zig").foldIntegerConstants(allocator, module.functions.items[0]);
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(allocator, &module, options);
        defer allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, ".ascii") == null);
        try testing.expect(std.mem.indexOf(u8, assembly, "zbe_injected_symbol") == null);
        try testing.expect(std.mem.indexOf(u8, assembly, "\t.byte 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15\n") != null);
    }
}
fn malformed(allocator: std.mem.Allocator) !void {
    if (parse(allocator, "data $x = { b \"first\" \"second\\000\", h 3 }\ndata $bad = { b \"\\400\" }")) |owned| {
        var unexpected = owned;
        unexpected.deinit();
        return error.ExpectedInvalidString;
    } else |err| if (err != error.InvalidInput) return err;
}

test "byte string parser decoder ownership and emitter exhaustively clean all allocation failures" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
    try @import("test_support.zig").checkAllocationFailures(malformed);
}

test "byte strings do not initialize interpreter globals or caller Image" {
    var module = try parse(testing.allocator, "data $x = { b \"abc\" }\nfunction l $f() {\n@e\nret $x\n}");
    defer module.deinit();
    var image = try @import("memory.zig").Image.init(testing.allocator, 8, .{});
    defer image.deinit();
    const entry: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 0));
    try testing.expectError(error.UnsupportedSymbolAddress, @import("interpreter.zig").evaluateModule(testing.allocator, &module, entry, &.{}, .{ .memory_image = &image, .stack_memory = .{} }));
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0, 0, 0, 0, 0 }, image.bytes);
}
