//! Draft bounded U06 nominal and subword signature witnesses.
//! No mismatched call is executed. This is not a complete U06 ledger.
const std = @import("std");
const t = std.testing;
const ir = @import("ir.zig");
const Module = @import("module.zig").Module;
const validation = @import("module_validation.zig");
const planner = @import("abi_amd64_plan.zig");
const amd64 = @import("amd64.zig");

fn target(symbol: @import("symbols.zig").Id, wrapped: bool) ir.CallTarget {
    return if (wrapped) .{ .address = .{ .got_symbol = symbol } } else .{ .extern_symbol = symbol };
}
fn mismatch(module: *const Module) !void {
    try t.expectError(error.CallSignatureMismatch, validation.validate(t.allocator, module));
    try t.expectError(error.CallSignatureMismatch, planner.FunctionPlan.init(t.allocator, module, @fromBackingInt(@as(u32, 1)), .{}));
    try t.expectError(error.CallSignatureMismatch, planner.ModulePlans.init(t.allocator, module, .{}));
    try t.expectError(error.CallSignatureMismatch, amd64.emit(t.allocator, module));
}

const cases = [_]struct { name: []const u8, text: []const u8 }{
    .{ .name = "regular", .text = "type :A={l}\ntype :B={l}\nfunction :A $known(:A %p){\n@e\nret %p\n}\nfunction l $caller(){\n@e\n%r =:A call extern $known(:A extern $data)\nret %r\n}" },
    .{ .name = "union", .text = "type :A={{l}{d}}\ntype :B={{l}{d}}\nfunction :A $known(:A %p){\n@e\nret %p\n}\nfunction l $caller(){\n@e\n%r =:A call extern $known(:A extern $data)\nret %r\n}" },
    .{ .name = "opaque", .text = "type :A=align 1 {17}\ntype :B=align 1 {17}\nfunction :A $known(:A %p){\n@e\nret %p\n}\nfunction l $caller(){\n@e\n%r =:A call extern $known(:A extern $data)\nret %r\n}" },
};

test "U06 both GOT target forms preserve regular union and opaque nominal identity" {
    for (cases) |case| {
        var diagnostic: ?@import("source.zig").Diagnostic = null;
        var module = try @import("frontend.zig").parse(t.allocator, .{ .name = case.name, .text = case.text }, &diagnostic);
        defer module.deinit();
        const call = &module.functions.items[1].blocks.items[0].instructions.items[0].call;
        const known = call.callee.symbolicIdentity().?;
        const argument = &@constCast(call.arguments)[0];
        const original_arg = argument.descriptor;
        const original_result = call.result_descriptor;
        const twin: ir.AbiDescriptor = .{ .record = @fromBackingInt(@as(u32, 1)) };
        for ([_]bool{ false, true }) |wrapped| {
            call.callee = target(known, wrapped);
            try validation.validate(t.allocator, &module);
            argument.descriptor = twin;
            try mismatch(&module);
            argument.descriptor = original_arg;
            call.result_descriptor = twin;
            try mismatch(&module);
            call.result_descriptor = original_result;
            try validation.validate(t.allocator, &module);
        }
    }
}

test "U06 both GOT target forms retain exact subword argument and result ABI" {
    const text = "function sb $known(sb %p){\n@e\nret %p\n}\nfunction w $caller(){\n@e\n%r =sb call extern $known(sb 1)\nret %r\n}";
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    var module = try @import("frontend.zig").parse(t.allocator, .{ .name = "u06-subword", .text = text }, &diagnostic);
    defer module.deinit();
    const call = &module.functions.items[1].blocks.items[0].instructions.items[0].call;
    const known = call.callee.symbolicIdentity().?;
    const argument = &@constCast(call.arguments)[0];
    const old_arg = argument.subword_type;
    const old_result = call.result_subword;
    for ([_]bool{ false, true }) |wrapped| {
        call.callee = target(known, wrapped);
        try validation.validate(t.allocator, &module);
        argument.subword_type = .unsigned_byte;
        try mismatch(&module);
        argument.subword_type = old_arg;
        call.result_subword = .unsigned_byte;
        try mismatch(&module);
        call.result_subword = old_result;
        try validation.validate(t.allocator, &module);
    }
}
