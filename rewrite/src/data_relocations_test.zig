const std = @import("std");
const testing = std.testing;
const data = @import("data.zig");
const frontend = @import("frontend.zig");
const source = @import("source.zig");
const amd64 = @import("amd64.zig");
const validation = @import("module_validation.zig");
const fixture = @embedFile("fixtures/data-relocations.ssa");
fn parse(allocator: std.mem.Allocator, text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?source.Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "data-relocations", .text = text }, &diagnostic);
}

test "typed eight-byte symbolic initializers retain module identity signed addends and packed layout" {
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    const table = module.data.items[0];
    try testing.expectEqual(@as(usize, 120), try table.validate());
    try testing.expectEqual(@as(usize, 15), table.items.items.len);
    const initial = table.items.items[0].symbol_address;
    try testing.expectEqualStrings("reloc_bytes", module.symbols.get(initial.symbol).?);
    try testing.expectEqual(@as(i64, 0), initial.addend);
    try testing.expectEqual(initial.symbol, table.items.items[1].symbol_address.symbol);
    try testing.expectEqual(@as(i64, 1), table.items.items[1].symbol_address.addend);
    try testing.expectEqual(std.math.maxInt(i64), table.items.items[12].symbol_address.addend);
    try testing.expectEqual(std.math.minInt(i64), table.items.items[13].symbol_address.addend);
    try testing.expectEqual(@as(u64, 81985529216486895), table.items.items[14].long);
    try testing.expectEqual(@as(usize, 11), try module.data.items[5].validate());
    try validation.validate(testing.allocator, &module);
    // A minus-prefixed integer is a second item, not subtraction syntax.
    var adjacent = try parse(testing.allocator, "data $x = { l $target-8 }");
    defer adjacent.deinit();
    try testing.expectEqual(@as(usize, 2), adjacent.data.items[0].items.items.len);
    try testing.expectEqual(@as(u64, 0xfffffffffffffff8), adjacent.data.items[0].items.items[1].long);

    var multiline = try parse(testing.allocator, "data $x = { l $external\n+\n-17\n $x + 0, }\n");
    defer multiline.deinit();
    try testing.expectEqual(@as(i64, -17), multiline.data.items[0].items.items[0].symbol_address.addend);
    try testing.expectEqual(multiline.data.items[0].name, multiline.data.items[0].items.items[1].symbol_address.symbol);
}

test "symbolic initializer module validation and target validation cover unused invalid IDs and names" {
    var module = try parse(testing.allocator, "data $unused = { l $unresolved+3 }");
    defer module.deinit();
    const item = &module.data.items[0].items.items[0];
    const original = item.symbol_address.symbol;
    item.symbol_address.symbol = @fromBackingInt(std.math.maxInt(u32));
    try testing.expectError(error.InvalidSymbol, validation.validate(testing.allocator, &module));
    try testing.expectError(error.InvalidSymbol, amd64.emit(testing.allocator, &module));
    item.symbol_address.symbol = try module.symbols.intern("bad\n.quad injected");
    try validation.validate(testing.allocator, &module);
    try testing.expectError(error.InvalidSymbol, amd64.emit(testing.allocator, &module));
    item.symbol_address.symbol = original;
    try validation.validate(testing.allocator, &module);
    // Eight bytes are charged before publishing symbolic items, just like numbers.
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    var object = data.Data.init(failing.allocator(), original);
    defer object.deinit();
    failing.fail_index = failing.alloc_index;
    try testing.expectError(error.OutOfMemory, object.append(.{ .symbol_address = .{ .symbol = original } }));
    try testing.expectEqual(@as(usize, 0), object.byte_len);
    try testing.expectEqual(@as(usize, 0), object.items.items.len);
    failing.fail_index = std.math.maxInt(usize);
    try object.append(.{ .symbol_address = .{ .symbol = original } });
    try testing.expectEqual(@as(usize, 8), try object.validate());
    try object.append(.{ .zero = data.max_object_bytes - 15 });
    try testing.expectError(error.DataTooLarge, object.append(.{ .symbol_address = .{ .symbol = original } }));
    try testing.expectEqual(@as(usize, 2), object.items.items.len);
}

test "symbolic data syntax rejects narrow float quoted malformed and out-of-range references" {
    for ([_][]const u8{
        "data $x = { b $target }",                      "data $x = { h $target }",                      "data $x = { w $target }",
        "data $x = { s $target }",                      "data $x = { d $target }",                      "data $x = { z $target }",
        "data $x = { l $\"quoted\" }",                  "data $x = { l thread $target }",               "data $x = { l $target+9223372036854775808 }",
        "data $x = { l $target+-9223372036854775809 }", "data $x = { l $target+18446744073709551616 }", "data $x = { l $target+d_1 }",
        "data $x = { l $target+$other }",               "data $x = { l $target - 8 }",                  "data $x = { l $target++8 }",
        "data $x = { l $target+ }",                     "data $x = { l $target+1+2 }",
    }) |text| {
        if (parse(testing.allocator, text)) |owned| {
            var unexpected = owned;
            unexpected.deinit();
            return error.ExpectedInvalidRelocation;
        } else |err| try testing.expectEqual(error.InvalidInput, err);
    }
    // Ordinary scalar symbol+offset syntax is intentionally still unsupported.
    try testing.expectError(error.InvalidInput, parse(testing.allocator, "function l $f() {\n@e\nret $target+1\n}"));
}

test "symbolic data does not resolve host or synthetic globals and validation precedes execution" {
    var module = try parse(testing.allocator, "data $x = { l $external+1 }\nfunction l $f(w %c) {\n@e\njnz %c, @yes, @no\n@yes\nret $x\n@no\nret 9\n}");
    defer module.deinit();
    const interpreter = @import("interpreter.zig");
    const entry: @import("module.zig").FunctionId = @fromBackingInt(@as(u32, 0));
    try testing.expectEqual(@as(u64, 9), (try interpreter.evaluateModule(testing.allocator, &module, entry, &.{.{ .word = 0 }}, .{})).?.long);
    try testing.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(testing.allocator, &module, entry, &.{.{ .word = 1 }}, .{ .stack_memory = .{} }));
    module.data.items[0].items.items[0].symbol_address.symbol = @fromBackingInt(std.math.maxInt(u32));
    try testing.expectError(error.InvalidSymbol, interpreter.evaluateModule(testing.allocator, &module, entry, &.{.{ .word = 0 }}, .{}));
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, fixture);
    defer module.deinit();
    for (module.functions.items) |function| _ = try @import("optimize.zig").foldIntegerConstants(allocator, function);
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(allocator, &module, options);
        defer allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, "\t.quad reloc_bytes+9223372036854775807\n") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "\t.quad reloc_bytes-9223372036854775808\n") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "\t.quad reloc_self\n") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "\t.quad reloc_external_middle-17\n") != null);
    }
}
fn malformed(allocator: std.mem.Allocator) !void {
    if (parse(allocator, "data $x = { l $forward+1, l $x+-9 }\ndata $bad = { l $other+9223372036854775808 }")) |owned| {
        var unexpected = owned;
        unexpected.deinit();
        return error.ExpectedInvalidRelocation;
    } else |err| if (err != error.InvalidInput) return err;
}

test "symbolic initializer parser folder emitter and partial failure exhaustively clean all allocations" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
    try @import("test_support.zig").checkAllocationFailures(malformed);
}
