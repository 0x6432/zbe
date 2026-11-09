//! Focused extern/GOT boundaries: planning scope, interpreter and SSA uses.
const std = @import("std");
const t = std.testing;
const ir = @import("ir.zig");
const Module = @import("module.zig").Module;
const FunctionId = @import("module.zig").FunctionId;
const planner = @import("abi_amd64_plan.zig");
const validation = @import("module_validation.zig");
const interpreter = @import("interpreter.zig");

fn parse(text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(t.allocator, .{ .name = "extern-safety", .text = text }, &diagnostic);
}
fn id(n: u32) FunctionId {
    return @fromBackingInt(n);
}

test "extern_safety scalar plans scan whole module but detached plans scan selected function" {
    var module = try parse("function l $good() {\n@e\nret extern $native_name\n}\nfunction l $other() {\n@e\nret 0\n@dead\nret extern $.nonnative\n}");
    defer module.deinit();
    try validation.validate(t.allocator, &module);
    var selected = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
    defer selected.deinit();
    try t.expectError(error.UnsupportedExternSymbol, planner.FunctionPlan.init(t.allocator, &module, id(1), .{}));
    try t.expectError(error.UnsupportedExternSymbol, planner.ModulePlans.init(t.allocator, &module, .{}));
    const native = try module.symbols.intern("native_other");
    module.functions.items[1].blocks.items[1].terminator.?.return_value = .{ .got_symbol = native };
    var all = try planner.ModulePlans.init(t.allocator, &module, .{});
    defer all.deinit();
    try t.expectEqual(@as(usize, 0), all.functions.len);
    try t.expect(all.get(0) == null);
}

test "extern_safety generic errors and aggregate policy precede extern policy" {
    var module = try parse("type :A={b 4097}\nfunction l $first() {\n@e\nret extern $.bad\n}\nfunction $later(:A %p) {\n@e\nret\n}");
    defer module.deinit();
    try validation.validate(t.allocator, &module);
    // The later unsupported aggregate wins over the earlier unsupported extern.
    try t.expectError(error.UnsupportedAggregatePlan, planner.ModulePlans.init(t.allocator, &module, .{}));
    try t.expectError(error.UnsupportedExternSymbol, planner.FunctionPlan.init(t.allocator, &module, id(0), .{}));
    try t.expectError(error.UnsupportedAggregatePlan, planner.FunctionPlan.init(t.allocator, &module, id(1), .{}));
    module.types.items[0].size += 1;
    try t.expectError(error.InvalidRecordLayout, planner.ModulePlans.init(t.allocator, &module, .{}));
    try t.expectError(error.InvalidRecordLayout, planner.FunctionPlan.init(t.allocator, &module, id(0), .{}));
    try t.expectError(error.InvalidFunction, planner.FunctionPlan.init(t.allocator, &module, id(99), .{}));
}

test "extern_safety unselected aggregate ignored only after global validation" {
    var module = try parse("type :A={b 4097}\nfunction l $first() {\n@e\nret extern $native_name\n}\nfunction $later(:A %p) {\n@e\nret\n}");
    defer module.deinit();
    var plan = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
    defer plan.deinit();
    try t.expectError(error.UnsupportedAggregatePlan, planner.ModulePlans.init(t.allocator, &module, .{}));
    module.types.items[0].size += 1;
    try t.expectError(error.InvalidRecordLayout, planner.FunctionPlan.init(t.allocator, &module, id(0), .{}));
}

test "extern_safety signature errors precede native name eligibility" {
    var module = try parse("function l $first() {\n@e\n%r =l call $known()\nret extern $.bad\n}\nfunction l $known(l %x) {\n@e\nret %x\n}");
    defer module.deinit();
    try t.expectError(error.CallSignatureMismatch, validation.validate(t.allocator, &module));
    try t.expectError(error.CallSignatureMismatch, planner.ModulePlans.init(t.allocator, &module, .{}));
    try t.expectError(error.CallSignatureMismatch, planner.FunctionPlan.init(t.allocator, &module, id(1), .{}));
}

test "extern_safety interpreter nonnative phi selected only and invalid dead IDs checked" {
    var module = try parse("function l $f(w %c) {\n@entry\njnz %c, @left, @right\n@left\njmp @join\n@right\njmp @join\n@join\n%x =l phi @left 17, @right extern $.nonnative\nret %x\n@dead\nret extern $.nonnative\n}");
    defer module.deinit();
    try validation.validate(t.allocator, &module);
    for ([_]interpreter.Options{ .{}, .{ .global_memory = .{} } }) |opts| {
        try t.expectEqual(@as(u64, 17), (try interpreter.evaluateModule(t.allocator, &module, id(0), &.{.{ .word = 1 }}, opts)).?.long);
        try t.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(t.allocator, &module, id(0), &.{.{ .word = 0 }}, opts));
    }
    const f = module.functions.items[0];
    const inputs = @constCast(f.blocks.items[3].phis.items[0].inputs);
    const saved = inputs[1].value;
    inputs[1].value = .{ .got_symbol = @fromBackingInt(std.math.maxInt(u32)) };
    try t.expectError(error.InvalidSymbol, interpreter.evaluateModule(t.allocator, &module, id(0), &.{.{ .word = 1 }}, .{}));
    inputs[1].value = saved;
    f.blocks.items[4].terminator.?.return_value = .{ .got_symbol = @fromBackingInt(std.math.maxInt(u32)) };
    try t.expectError(error.InvalidSymbol, interpreter.evaluateModule(t.allocator, &module, id(0), &.{.{ .word = 1 }}, .{}));
}

test "extern_safety same named local is not a GOT fallback" {
    var module = try parse("data $local = { l 41 }\nfunction l $f() {\n@e\nret $local\n}");
    defer module.deinit();
    const term = &module.functions.items[0].blocks.items[0].terminator.?.return_value;
    const symbol = term.*.?.symbol;
    try t.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(t.allocator, &module, id(0), &.{}, .{}));
    const ordinary = (try interpreter.evaluateModule(t.allocator, &module, id(0), &.{}, .{ .global_memory = .{} })).?.long;
    try t.expect(ordinary != 0);
    term.* = .{ .got_symbol = symbol };
    try validation.validate(t.allocator, &module);
    for ([_]interpreter.Options{ .{}, .{ .global_memory = .{} } }) |opts| {
        try t.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(t.allocator, &module, id(0), &.{}, opts));
    }
}

test "extern_safety call iterator exposes target environment and arguments without SSA aliases" {
    var module = try parse("function l $f(l %v) {\n@e\n%r =l call extern $target(env extern $environment, l extern $argument, l %v)\nret %r\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    const inst = &f.blocks.items[0].instructions.items[0];
    const target = inst.call.callee.extern_symbol;
    const env = inst.call.environment.?.got_symbol;
    const arg = inst.call.arguments[0].operand.got_symbol;
    for ([_]ir.CallTarget{ .{ .extern_symbol = target }, .{ .address = .{ .got_symbol = target } } }) |form| {
        inst.call.callee = form;
        try validation.validate(t.allocator, &module);
        var uses = inst.operands();
        for ([_]@import("symbols.zig").Id{ target, env, arg }) |expected| {
            const operand = uses.next().?;
            try t.expectEqual(expected, operand.referencedSymbol().?);
            try t.expect(operand.referencedValue() == null);
            try t.expect(operand == .got_symbol);
        }
        try t.expectEqual(f.parameters.items[0], uses.next().?.referencedValue().?);
        try t.expect(uses.next() == null);
    }
}

test "extern_safety phi liveness interference and folding preserve GOT identity" {
    var module = try parse("function l $f(w %c, l %v, l %keep) {\n@entry\njnz %c, @left, @right\n@left\njmp @join\n@right\njmp @join\n@join\n%x =l phi @left %v, @right extern $global\n%y =l add %x, extern $other\n%z =l add %y, 0\n%r =l add %z, %keep\nret %r\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    const phi = f.blocks.items[3].phis.items[0];
    const v = f.parameters.items[1];
    const keep = f.parameters.items[2];
    const x = phi.result;
    const y = f.blocks.items[3].instructions.items[0].binary.result;
    const z = f.blocks.items[3].instructions.items[1].binary.result;
    try t.expect(phi.inputs[1].value.referencedValue() == null);
    try t.expect(phi.inputs[1].value.referencedSymbol() != null);
    try validation.validate(t.allocator, &module);
    // A real SSA use of the join-defined phi on the incoming right edge is
    // invalid; the GOT operand in the same slot is not an SSA use.
    const inputs = @constCast(f.blocks.items[3].phis.items[0].inputs);
    const saved = inputs[1].value;
    inputs[1].value = .{ .value = x };
    try t.expectError(error.InvalidSSA, validation.validate(t.allocator, &module));
    inputs[1].value = saved;
    var live = try @import("liveness.zig").Snapshot.init(t.allocator, f, .{});
    defer live.deinit();
    const left: ir.BlockId = @fromBackingInt(@as(u32, 1));
    const right: ir.BlockId = @fromBackingInt(@as(u32, 2));
    const join: ir.BlockId = @fromBackingInt(@as(u32, 3));
    try t.expect(live.isLiveOut(left, v).?);
    try t.expect(!live.isLiveOut(right, v).?);
    try t.expect(!live.isLiveIn(join, v).?);
    try t.expect(live.isLiveOut(left, keep).?);
    try t.expect(live.isLiveOut(right, keep).?);
    try t.expect(live.isLiveIn(join, keep).?);
    var graph = try @import("interference.zig").Graph.init(t.allocator, f, .{});
    defer graph.deinit();
    try t.expect(graph.interferes(keep, x).?);
    try t.expect(graph.interferes(keep, y).?);
    try t.expect(graph.interferes(keep, z).?);
    try t.expect(!graph.interferes(x, y).?);
    try t.expect(!graph.interferes(y, z).?);
    const sym = f.blocks.items[3].instructions.items[0].binary.rhs.got_symbol;
    _ = try @import("optimize.zig").foldIntegerConstants(t.allocator, f);
    try t.expect(f.blocks.items[3].instructions.items[0] == .binary);
    try t.expectEqual(sym, f.blocks.items[3].instructions.items[0].binary.rhs.got_symbol);
    try t.expectEqual(y, f.blocks.items[3].instructions.items[1].copy.operand.value);
    try t.expectEqual(phi.inputs[1].value.got_symbol, f.blocks.items[3].phis.items[0].inputs[1].value.got_symbol);
    try validation.validate(t.allocator, &module);
}

test "extern_safety both GOT call targets obey detached and whole module scope" {
    var module = try parse("function l $first() {\n@e\nret 1\n}\nfunction l $later() {\n@e\n%r =l call extern $.nonnative()\nret %r\n}");
    defer module.deinit();
    const call = &module.functions.items[1].blocks.items[0].instructions.items[0].call;
    const symbol = call.callee.extern_symbol;
    for ([_]ir.CallTarget{ .{ .extern_symbol = symbol }, .{ .address = .{ .got_symbol = symbol } } }) |form| {
        call.callee = form;
        try validation.validate(t.allocator, &module);
        var selected = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
        selected.deinit();
        try t.expectError(error.UnsupportedExternSymbol, planner.FunctionPlan.init(t.allocator, &module, id(1), .{}));
        try t.expectError(error.UnsupportedExternSymbol, planner.ModulePlans.init(t.allocator, &module, .{}));
    }
}

test "extern_safety reached instruction refuses nonnative GOT without native scan" {
    var module = try parse("function l $f(w %c) {\n@entry\njnz %c, @use, @skip\n@use\n%p =l copy extern $.nonnative\nret %p\n@skip\nret 42\n}");
    defer module.deinit();
    for ([_]interpreter.Options{ .{}, .{ .global_memory = .{} } }) |opts| {
        try t.expectEqual(@as(u64, 42), (try interpreter.evaluateModule(t.allocator, &module, id(0), &.{.{ .word = 0 }}, opts)).?.long);
        try t.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(t.allocator, &module, id(0), &.{.{ .word = 1 }}, opts));
    }
    module.functions.items[0].blocks.items[1].instructions.items[0].copy.operand = .{ .got_symbol = @fromBackingInt(std.math.maxInt(u32)) };
    try t.expectError(error.InvalidSymbol, interpreter.evaluateModule(t.allocator, &module, id(0), &.{.{ .word = 0 }}, .{}));
}

test "extern_safety neutral fold retains reached GOT and native relocation" {
    var module = try parse("function l $f() {\n@e\n%x =l add extern $target, 0\nret %x\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    const symbol = f.blocks.items[0].instructions.items[0].binary.lhs.got_symbol;
    const amd64 = @import("amd64.zig");
    const before = try amd64.emit(t.allocator, &module);
    defer t.allocator.free(before);
    try t.expect(std.mem.indexOf(u8, before, "target@GOTPCREL") != null);
    try t.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(t.allocator, &module, id(0), &.{}, .{}));
    try t.expectEqual(@as(usize, 1), try @import("optimize.zig").foldIntegerConstants(t.allocator, f));
    const operand = f.blocks.items[0].instructions.items[0].copy.operand;
    try t.expectEqual(symbol, operand.got_symbol);
    try t.expect(operand.referencedValue() == null);
    try t.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(t.allocator, &module, id(0), &.{}, .{}));
    const after = try amd64.emit(t.allocator, &module);
    defer t.allocator.free(after);
    try t.expect(std.mem.indexOf(u8, after, "target@GOTPCREL") != null);
}
