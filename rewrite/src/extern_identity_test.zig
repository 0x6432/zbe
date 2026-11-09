//! Symbol identity and old ordinary-only boundaries for draft extern operands.
const std = @import("std");
const t = std.testing;
const frontend = @import("frontend.zig");
const validation = @import("module_validation.zig");
const amd64 = @import("amd64.zig");

fn parse(text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return frontend.parse(t.allocator, .{ .name = "extern-identity", .text = text }, &diagnostic);
}

test "extern_identity quoted alias shares owned ordinary symbol through source destruction and growth" {
    const borrowed = try t.allocator.dupe(u8, "function l $f() {\n@e\n%old =l copy $target\n%new =l copy extern $\"target\"\nret %new\n}");
    var module = parse(borrowed) catch |err| {
        t.allocator.free(borrowed);
        return err;
    };
    t.allocator.free(borrowed);
    defer module.deinit();
    const f = module.functions.items[0];
    const old = f.blocks.items[0].instructions.items[0].copy.operand.symbol;
    const new = f.blocks.items[0].instructions.items[1].copy.operand.got_symbol;
    try t.expectEqual(old, new);
    const original = module.symbols.get(new).?;
    try t.expectEqualStrings("target", original);
    try validation.validate(t.allocator, &module);
    const assembly = try amd64.emit(t.allocator, &module);
    defer t.allocator.free(assembly);
    try t.expect(std.mem.indexOf(u8, assembly, "target@GOTPCREL") != null);
    // Stress both owned symbol storage and the module's function table. The
    // extra empty functions are never executed or validated as complete IR.
    for (0..512) |i| {
        const name = try std.fmt.allocPrint(t.allocator, "growth_{d}", .{i});
        defer t.allocator.free(name);
        _ = try module.addFunctionAbi(name, null);
    }
    try t.expectEqual(f, module.functions.items[0]);
    const retained = module.symbols.get(new).?;
    try t.expectEqual(original.ptr, retained.ptr);
    try t.expectEqualStrings("target", retained);
    try t.expectEqual(new, f.blocks.items[0].instructions.items[1].copy.operand.got_symbol);
}

test "extern_identity unused pool names and ordinary-only names do not receive extern restrictions" {
    var module = try parse("function l $f() {\n@e\nret $.ordinary\n}");
    defer module.deinit();
    _ = try module.symbols.intern(".unused-nonnative");
    _ = try module.symbols.intern("unused\ninvalid");
    try validation.validate(t.allocator, &module);
    const text = try amd64.emit(t.allocator, &module);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, ".ordinary") != null);
}
