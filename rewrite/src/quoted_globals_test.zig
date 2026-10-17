const std = @import("std");
const testing = std.testing;
const Module = @import("module.zig").Module;
const fixture = @embedFile("fixtures/quoted-globals.ssa");
const amd64 = @import("amd64.zig");
const interpreter = @import("interpreter.zig");
const options = [_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } };
fn id(index: u32) @import("module.zig").FunctionId {
    return @fromBackingInt(index);
}
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "quoted-globals", .text = text }, &diagnostic);
}

test "quoted globals decode canonical owned names in definitions calls operands and relocations" {
    const text = try testing.allocator.dupe(u8, fixture);
    defer testing.allocator.free(text);
    var module = try parse(testing.allocator, text);
    defer module.deinit();
    @memset(text, 'x');
    try @import("module_validation.zig").validate(testing.allocator, &module);
    try testing.expectEqualStrings("quoted blob", module.symbols.get(module.data.items[0].name).?);
    try testing.expectEqualStrings("quote\"back\\name", module.symbols.get(module.functions.items[3].name).?);
    try testing.expectEqual(module.data.items[0].name, module.data.items[1].items.items[0].symbol_address.symbol);
    try testing.expectEqual(@as(u64, 8), (try interpreter.evaluateModule(testing.allocator, &module, id(1), &.{}, .{})).?.long);
    var aliases = try parse(testing.allocator, "function l $plain() {\n@e\nret 17\n}\nfunction l $caller() {\n@e\n%r =l call $\"\\x70l\\141in\"()\nret %r\n}");
    defer aliases.deinit();
    try testing.expectEqual(aliases.functions.items[0].name, aliases.functions.items[1].blocks.items[0].instructions.items[0].call.callee.symbol);
    try testing.expectEqual(@as(u64, 17), (try interpreter.evaluateModule(testing.allocator, &aliases, id(1), &.{}, .{})).?.long);
    try testing.expectError(error.InvalidInput, parse(testing.allocator, "function $plain() {\n@e\nret\n}\nfunction $\"pl\\141in\"() {\n@e\nret\n}"));
    try testing.expectError(error.InvalidInput, parse(testing.allocator, "data $plain = {}\ndata $\"plain\" = {}"));
}

test "quoted name grammar rejects empty dot control nul nonascii private namespace and malformed escapes" {
    for ([_][]const u8{ "", ".", "bad\\000name", "bad\\nname", "bad\\tname", "bad\\177name", "\\xff", ".Lzbe@0@b0", "bad\\q", "bad\\x1", "bad\\777", "é" }) |name| {
        const text = try std.fmt.allocPrint(testing.allocator, "function $\"{s}\"() {{\n@e\nret\n}}", .{name});
        defer testing.allocator.free(text);
        try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
    }
    for ([_][]const u8{ "semantic name;\nnot assembly", ".Lzbe@0@b0", "", ".", "bad\x00name", "é" }) |name| {
        var module = try parse(testing.allocator, "function w $f() {\n@e\nret 42\n}");
        defer module.deinit();
        module.functions.items[0].name = try module.symbols.intern(name);
        try @import("module_validation.zig").validate(testing.allocator, &module);
        try testing.expectError(error.InvalidSymbol, amd64.emit(testing.allocator, &module));
    }
    for ([_][]const u8{ "space name", "1leading", "quote\"back\\name", "semi;colon", "has@at", "$cash", " leading " }) |name| try testing.expect(@import("symbols.zig").validPortableName(name));
}

test "quoted emission escapes all contexts and quoted bare spelling leaves assembly byte identical" {
    var bare = try parse(testing.allocator, "export data $bytes = { l $bytes+8 }\nexport function l $get() {\n@e\nret $bytes+8\n}\nexport function l $caller() {\n@e\n%r =l call $get()\nret %r\n}");
    defer bare.deinit();
    var quoted = try parse(testing.allocator, "export data $\"bytes\" = { l $\"bytes\"+8 }\nexport function l $\"get\"() {\n@e\nret $\"bytes\"+8\n}\nexport function l $\"caller\"() {\n@e\n%r =l call $\"get\"()\nret %r\n}");
    defer quoted.deinit();
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    for (options) |option| {
        const a = try amd64.emitWithOptions(testing.allocator, &bare, option);
        defer testing.allocator.free(a);
        const b = try amd64.emitWithOptions(testing.allocator, &quoted, option);
        defer testing.allocator.free(b);
        try testing.expectEqualStrings(a, b);
        const assembly = try amd64.emitWithOptions(testing.allocator, &module, option);
        defer testing.allocator.free(assembly);
        for ([_][]const u8{ ".globl \"quoted blob\"", ".type \"quoted table\", @object", ".type \"quoted blob\", @object", ".size \"quoted blob\", .-\"quoted blob\"", ".type \"quote\\\"back\\\\name\", @function", "call \"quoted get\"", ".quad \"quoted blob\"+8", "leaq \"quoted blob\"+8(%rip)" }) |needle| try testing.expect(std.mem.indexOf(u8, assembly, needle) != null);
    }
}

test "quoted globals retain bounded synthetic addresses reset and default function external refusals" {
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    try testing.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(testing.allocator, &module, id(2), &.{}, .{}));
    for ([_]std.builtin.Endian{ .little, .big }) |endian| {
        try testing.expectEqual(@as(u64, 22), (try interpreter.evaluateModule(testing.allocator, &module, id(2), &.{}, .{ .global_memory = .{ .endian = endian } })).?.long);
        try testing.expectEqual(@as(u64, 0x200000008), (try interpreter.evaluateModule(testing.allocator, &module, id(5), &.{.{ .word = 1 }}, .{ .global_memory = .{ .endian = endian } })).?.long);
    }
    var unresolved = try parse(testing.allocator, "function l $f() {\n@e\nret $\"external name\"\n}");
    defer unresolved.deinit();
    try testing.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(testing.allocator, &unresolved, id(0), &.{}, .{ .global_memory = .{} }));
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, fixture);
    defer module.deinit();
    for (module.functions.items) |f| {
        var live = try @import("liveness.zig").Snapshot.init(allocator, f, .{});
        defer live.deinit();
        var graph = try @import("interference.zig").Graph.init(allocator, f, .{});
        defer graph.deinit();
        _ = try @import("optimize.zig").foldIntegerConstants(allocator, f);
    }
    _ = try interpreter.evaluateModule(allocator, &module, id(1), &.{}, .{});
    _ = try interpreter.evaluateModule(allocator, &module, id(2), &.{}, .{ .global_memory = .{} });
    for (options) |option| {
        const assembly = try amd64.emitWithOptions(allocator, &module, option);
        defer allocator.free(assembly);
    }
    for ([_][]const u8{ "data $\"good name\" = { l $\"bad\\qname\" }", "function $\"good name\"() {\n@e\ncall $\"bad\\000name\"()\nret\n}" }) |text| {
        if (parse(allocator, text)) |parsed| {
            var unexpected = parsed;
            unexpected.deinit();
            return error.TestExpectedError;
        } else |err| switch (err) {
            error.InvalidInput => {},
            else => return err,
        }
    }
}
test "all decoded-name parser analysis synthetic globals formatter and failure cleanup paths are owned" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

test "trailing backslash references use private aliases without changing ELF declarations or unused pool keys" {
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    _ = try module.symbols.intern("unused\ninvalid\\");
    for (options) |option| {
        const assembly = try amd64.emitWithOptions(testing.allocator, &module, option);
        defer testing.allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, ".set \".Lzbe@s") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "call \".Lzbe@s") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "leaq \".Lzbe@s") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "unused") == null);
    }
}
