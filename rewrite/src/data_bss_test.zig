const std = @import("std");
const testing = std.testing;
const data = @import("data.zig");
const amd64 = @import("amd64.zig");
const frontend = @import("frontend.zig");
const source = @import("source.zig");
const fixture = @embedFile("fixtures/data-bss.ssa");
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?source.Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "data-bss", .text = text }, &diagnostic);
}

test "zero-data classification uses exact bits not numeric floating equality or symbolic guesses" {
    const zero_items = [_]data.Item{ .{ .byte = 0 }, .{ .half = 0 }, .{ .word = 0 }, .{ .long = 0 }, .{ .single_bits = 0 }, .{ .double_bits = 0 }, .{ .zero = 17 }, .{ .bytes = &.{ 0, 0, 0 } }, .{ .bytes = "" } };
    var object = data.Data.init(testing.allocator, @fromBackingInt(@as(u32, 0)));
    defer object.deinit();
    try testing.expect(object.isAllZero());
    for (zero_items) |item| {
        try object.append(item);
        try testing.expect(object.isAllZero());
    }
    for ([_]data.Item{ .{ .byte = 1 }, .{ .half = 0x100 }, .{ .word = 0x80000000 }, .{ .long = 0x8000000000000000 }, .{ .single_bits = 0x80000000 }, .{ .double_bits = 0x8000000000000000 }, .{ .bytes = &.{ 0, 0, 1 } }, .{ .symbol_address = .{ .symbol = @fromBackingInt(@as(u32, 0)) } } }) |item| {
        var nonzero = data.Data.init(testing.allocator, @fromBackingInt(@as(u32, 0)));
        defer nonzero.deinit();
        try nonzero.append(item);
        try testing.expect(!nonzero.isAllZero());
    }
}

test "ELF zero data gets compact BSS while signed zero and linker references retain PROGBITS" {
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    for (module.data.items, [_]bool{ true, true, true, true, false, false, false, true }) |object, expected| try testing.expectEqual(expected, object.isAllZero());
    const assembly = try amd64.emit(testing.allocator, &module);
    defer testing.allocator.free(assembly);
    try testing.expect(std.mem.indexOf(u8, assembly, ".bss\n.balign 64\n.globl bss_numbers\n.type bss_numbers, @object\nbss_numbers:\n\t.zero 15\n.size bss_numbers, .-bss_numbers") != null);
    try testing.expect(std.mem.indexOf(u8, assembly, ".bss\n.balign 32\n.globl bss_bytes\n.type bss_bytes, @object\nbss_bytes:\n\t.zero 3\n") != null);
    try testing.expect(std.mem.indexOf(u8, assembly, "bss_empty:\n.size bss_empty, .-bss_empty") != null);
    try testing.expect(std.mem.indexOf(u8, assembly, ".data\n.balign 8\n.globl bss_negative\n") != null);
    try testing.expect(std.mem.indexOf(u8, assembly, "\t.long 2147483648\n\t.quad 9223372036854775808\n") != null);
    try testing.expect(std.mem.indexOf(u8, assembly, "bss_pointer:\n\t.quad bss_bytes\n") != null);
    try testing.expect(std.mem.indexOf(u8, assembly, "bss_mixed:\n\t.zero 35\n") != null);
}

test "BSS selection never bypasses module size ID and symbol validation" {
    var module = try parse(testing.allocator, "data $x = { z 17 }");
    defer module.deinit();
    module.data.items[0].byte_len = 18;
    try testing.expectError(error.InvalidDataSize, amd64.emit(testing.allocator, &module));
    module.data.items[0].byte_len = 17;
    module.data.items[0].name = try module.symbols.intern("bad\n.section injected");
    try testing.expectError(error.InvalidSymbol, amd64.emit(testing.allocator, &module));
    module.data.items[0].name = @fromBackingInt(std.math.maxInt(u32));
    try testing.expectError(error.InvalidSymbol, amd64.emit(testing.allocator, &module));
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, fixture);
    defer module.deinit();
    const bytes = module.data.items[1].items.items[0].bytes;
    for (module.functions.items) |function| _ = try @import("optimize.zig").foldIntegerConstants(allocator, function);
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(allocator, &module, options);
        defer allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "\t.zero 35\n") != null);
        try testing.expect(bytes.ptr == module.data.items[1].items.items[0].bytes.ptr);
        try testing.expectEqualSlices(u8, &.{ 0, 0, 0 }, bytes);
        try testing.expectEqual(@as(usize, 8), module.data.items.len);
    }
}
test "BSS parser and emission remain read-only and clean every injected allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
