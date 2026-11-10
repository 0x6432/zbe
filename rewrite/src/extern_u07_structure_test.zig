//! Bounded malformed public-metadata/precedence witnesses; not the complete U07 ledger.
//! Modules are modified only in memory and restored; no native code is executed.
const std = @import("std");
const t = std.testing;
const ir = @import("ir.zig");
const validation = @import("module_validation.zig");
const planner = @import("abi_amd64_plan.zig");
const amd64 = @import("amd64.zig");
const Module = @import("module.zig").Module;

fn rejectEvery(module: *const Module, expected: anyerror) !void {
    try t.expectError(expected, validation.validate(t.allocator, module));
    try t.expectError(expected, planner.FunctionPlan.init(t.allocator, module, @fromBackingInt(@as(u32, 0)), .{}));
    try t.expectError(expected, planner.ModulePlans.init(t.allocator, module, .{}));
    try t.expectError(expected, amd64.emit(t.allocator, module));
}

fn target(symbol: @import("symbols.zig").Id, wrapped: bool) ir.CallTarget {
    return if (wrapped) .{ .address = .{ .got_symbol = symbol } } else .{ .extern_symbol = symbol };
}

test "U07 malformed GOT call type and backlink precede invalid symbol" {
    const text = "function l $f() {\n@e\n%r =l call extern $callee(l extern $payload)\nret %r\n}";
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    var module = try @import("frontend.zig").parse(t.allocator, .{ .name = "u07-structure", .text = text }, &diagnostic);
    defer module.deinit();
    const f = module.functions.items[0];
    const call = &f.blocks.items[0].instructions.items[0].call;
    const symbol = call.callee.symbolicIdentity().?;
    const argument = &@constCast(call.arguments)[0];
    const original_argument = argument.*;
    const value = &f.values.items[@backingInt(call.result.?)];
    const original_definition = value.definition;
    const bad_symbol: @import("symbols.zig").Id = @fromBackingInt(std.math.maxInt(u32));
    for ([_]bool{ false, true }) |wrapped| {
        call.callee = target(symbol, wrapped);
        try validation.validate(t.allocator, &module);
        argument.operand = .{ .got_symbol = bad_symbol };
        argument.scalar_type = .word;
        try rejectEvery(&module, error.TypeMismatch);
        argument.scalar_type = .long;
        call.environment = .{ .constant = .{ .word = 0 } };
        try rejectEvery(&module, error.TypeMismatch);
        call.environment = null;
        value.definition.instruction.index = 99;
        try rejectEvery(&module, error.InvalidDefinition);
        value.definition = original_definition;
        try rejectEvery(&module, error.InvalidSymbol);
        argument.* = original_argument;
        try validation.validate(t.allocator, &module);
    }
}

test "U07 later record descriptors are resolved before known GOT signature mismatch" {
    const text =
        \\type :R={l}
        \\function l $caller() {
        \\@entry
        \\%r =l call extern $known()
        \\ret %r
        \\}
        \\function l $known(l %x) {
        \\@entry
        \\ret %x
        \\}
        \\function :R $later() {
        \\@entry
        \\%r =:R call extern $sink(:R extern $payload)
        \\ret %r
        \\}
    ;
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    var module = try @import("frontend.zig").parse(t.allocator, .{ .name = "u07-descriptor-order", .text = text }, &diagnostic);
    defer module.deinit();
    const call = &module.functions.items[0].blocks.items[0].instructions.items[0].call;
    const known = call.callee.symbolicIdentity().?;
    const later = &module.functions.items[2].blocks.items[0].instructions.items[0].call;
    const argument = &@constCast(later.arguments)[0];
    const old_argument_descriptor = argument.descriptor;
    const old_result_descriptor = later.result_descriptor;
    const bad = ir.AbiDescriptor{ .record = @fromBackingInt(std.math.maxInt(u32)) };
    for ([_]bool{ false, true }) |wrapped| {
        call.callee = target(known, wrapped);
        try rejectEvery(&module, error.CallSignatureMismatch);
        argument.descriptor = bad;
        try rejectEvery(&module, error.InvalidAggregateType);
        argument.descriptor = old_argument_descriptor;
        later.result_descriptor = bad;
        try rejectEvery(&module, error.InvalidAggregateType);
        later.result_descriptor = old_result_descriptor;
        try rejectEvery(&module, error.CallSignatureMismatch);
        // Restore a semantically valid external target on the same module.
        call.callee = target(later.callee.symbolicIdentity().?, wrapped);
        try validation.validate(t.allocator, &module);
    }
}
