//! U05: selected parse/IR/validation/assembly witnesses for operand sites.
//! Call-target forms have separate coverage in extern_operand_test.zig.
//! These are static witnesses, not a linked or executed native-runtime oracle.
//! In particular, the allocation-size witness is in an unreachable block:
//! a GOT-resolved address must never be used as an actual allocation length.
const std = @import("std");
const t = std.testing;
const ir = @import("ir.zig");
const frontend = @import("frontend.zig");
const validation = @import("module_validation.zig");
const amd64 = @import("amd64.zig");

const Site = enum {
    copy,
    copy_projection,
    phi,
    binary_lhs,
    binary_rhs,
    compare_lhs,
    compare_rhs,
    branch,
    result,
    load,
    store_value,
    store_address,
    blit_source,
    blit_destination,
    allocate_size,
    call_scalar,
    call_variadic,
    call_record,
    call_env,
    va_argument,
    va_start,
    unary,
    shift_value,
    convert,
};

const Case = struct {
    name: []const u8,
    text: []const u8,
    site: Site,
    block: usize = 0,
};

// Each witness has exactly one extern $target in the designated slot. Other
// operands are parameters or constants, so a relocation for an unrelated use
// cannot accidentally satisfy the emission assertion.
const cases = [_]Case{
    .{ .name = "copy", .site = .copy, .text = "function l $f() {\n@e\n%x =l copy extern $target\nret %x\n}" },
    .{ .name = "long materialized before word projection", .site = .copy_projection, .text = "function w $f() {\n@e\n%p =l copy extern $target\n%x =w copy %p\nret %x\n}" },
    .{ .name = "phi incoming edge", .site = .phi, .block = 3, .text = "function l $f(w %c) {\n@entry\njnz %c, @left, @right\n@left\njmp @join\n@right\njmp @join\n@join\n%x =l phi @left 7, @right extern $target\nret %x\n}" },
    .{ .name = "binary lhs", .site = .binary_lhs, .text = "function l $f(l %v) {\n@e\n%x =l sub extern $target, %v\nret %x\n}" },
    .{ .name = "binary rhs", .site = .binary_rhs, .text = "function l $f(l %v) {\n@e\n%x =l sub %v, extern $target\nret %x\n}" },
    .{ .name = "comparison lhs", .site = .compare_lhs, .text = "function w $f(l %v) {\n@e\n%x =w ceql extern $target, %v\nret %x\n}" },
    .{ .name = "comparison rhs", .site = .compare_rhs, .text = "function w $f(l %v) {\n@e\n%x =w ceql %v, extern $target\nret %x\n}" },
    .{ .name = "branch condition", .site = .branch, .text = "function w $f() {\n@e\njnz extern $target, @yes, @no\n@yes\nret 1\n@no\nret 0\n}" },
    .{ .name = "long return", .site = .result, .text = "function l $f() {\n@e\nret extern $target\n}" },
    .{ .name = "long load address", .site = .load, .text = "function l $f() {\n@e\n%x =l loadl extern $target\nret %x\n}" },
    .{ .name = "word load address", .site = .load, .text = "function w $f() {\n@e\n%x =w loadw extern $target\nret %x\n}" },
    .{ .name = "single load address", .site = .load, .text = "function s $f() {\n@e\n%x =s loads extern $target\nret %x\n}" },
    .{ .name = "double load address", .site = .load, .text = "function d $f() {\n@e\n%x =d loadd extern $target\nret %x\n}" },
    .{ .name = "store value", .site = .store_value, .text = "function $f(l %p) {\n@e\nstorel extern $target, %p\nret\n}" },
    .{ .name = "store address", .site = .store_address, .text = "function $f(l %v) {\n@e\nstorel %v, extern $target\nret\n}" },
    .{ .name = "blit source", .site = .blit_source, .text = "function $f(l %p) {\n@e\nblit extern $target, %p, 8\nret\n}" },
    .{ .name = "blit destination", .site = .blit_destination, .text = "function $f(l %p) {\n@e\nblit %p, extern $target, 8\nret\n}" },
    // This block is deliberately unreachable even if a future harness calls f.
    .{ .name = "allocation size, unexecuted", .site = .allocate_size, .block = 1, .text = "function l $f() {\n@entry\nret 0\n@dead\n%p =l alloc8 extern $target\nret %p\n}" },
    .{ .name = "scalar call argument", .site = .call_scalar, .text = "function l $f() {\n@e\n%x =l call $sink(l extern $target)\nret %x\n}" },
    .{ .name = "variadic scalar call argument", .site = .call_variadic, .text = "function l $f() {\n@e\n%x =l call $sink(w 1, ..., l extern $target)\nret %x\n}" },
    .{ .name = "record call argument", .site = .call_record, .text = "type :R={l 2}\nfunction l $f() {\n@e\n%x =l call $sink(:R extern $target)\nret %x\n}" },
    .{ .name = "call environment", .site = .call_env, .text = "function l $f() {\n@e\n%x =l call $sink(env extern $target, l 7)\nret %x\n}" },
    .{ .name = "word vaarg descriptor", .site = .va_argument, .text = "function w $f() {\n@e\n%x =w vaarg extern $target\nret %x\n}" },
    .{ .name = "long vaarg descriptor", .site = .va_argument, .text = "function l $f() {\n@e\n%x =l vaarg extern $target\nret %x\n}" },
    .{ .name = "single vaarg descriptor", .site = .va_argument, .text = "function s $f() {\n@e\n%x =s vaarg extern $target\nret %x\n}" },
    .{ .name = "double vaarg descriptor", .site = .va_argument, .text = "function d $f() {\n@e\n%x =d vaarg extern $target\nret %x\n}" },
    .{ .name = "vastart descriptor", .site = .va_start, .text = "function w $f(w %n, ...) {\n@e\nvastart extern $target\nret %n\n}" },
    .{ .name = "unary", .site = .unary, .text = "function l $f() {\n@e\n%x =l neg extern $target\nret %x\n}" },
    .{ .name = "shift value", .site = .shift_value, .text = "function l $f(w %n) {\n@e\n%x =l shl extern $target, %n\nret %x\n}" },
    .{ .name = "existing long conversion", .site = .convert, .text = "function d $f() {\n@e\n%x =d sltof extern $target\nret %x\n}" },
};

fn checkCase(case: Case) !void {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    var module = frontend.parse(t.allocator, .{ .name = case.name, .text = case.text }, &diagnostic) catch |err| {
        if (diagnostic) |d| std.debug.print("{s}: parse diagnostic {s} [{d},{d})\n", .{ case.name, @tagName(d.code), d.span.start, d.span.end });
        return err;
    };
    defer module.deinit();
    try validation.validate(t.allocator, &module);
    const f = module.functions.items[0];
    const block = f.blocks.items[case.block];
    const operand: ir.Operand = switch (case.site) {
        .phi => block.phis.items[0].inputs[1].value,
        .branch => block.terminator.?.branch.condition,
        .result => block.terminator.?.return_value.?,
        .copy, .copy_projection => block.instructions.items[0].copy.operand,
        .binary_lhs => block.instructions.items[0].binary.lhs,
        .binary_rhs => block.instructions.items[0].binary.rhs,
        .compare_lhs => block.instructions.items[0].compare_integer.lhs,
        .compare_rhs => block.instructions.items[0].compare_integer.rhs,
        .load => block.instructions.items[0].load.address,
        .store_value => block.instructions.items[0].store.value,
        .store_address => block.instructions.items[0].store.address,
        .blit_source => block.instructions.items[0].blit.source,
        .blit_destination => block.instructions.items[0].blit.destination,
        .allocate_size => block.instructions.items[0].allocate.size,
        .call_scalar, .call_record => block.instructions.items[0].call.arguments[0].operand,
        .call_variadic => block.instructions.items[0].call.arguments[1].operand,
        .call_env => block.instructions.items[0].call.environment.?,
        .va_argument => block.instructions.items[0].va_argument.list,
        .va_start => block.instructions.items[0].va_start.list,
        .unary => block.instructions.items[0].unary.operand,
        .shift_value => block.instructions.items[0].shift.value,
        .convert => block.instructions.items[0].convert.operand,
    };
    try t.expect(operand == .got_symbol);
    try t.expectEqualStrings("target", module.symbols.get(operand.got_symbol).?);
    try t.expectEqual(operand.got_symbol, operand.referencedSymbol().?);
    try t.expect(operand.referencedValue() == null);
    try t.expectEqual(ir.ScalarType.long, try f.operandType(operand));
    if (case.site == .copy_projection) {
        const projected = block.instructions.items[1].copy.operand;
        try t.expect(projected == .low_word);
        try t.expectEqual(block.instructions.items[0].copy.result, projected.low_word);
    }
    if (case.site == .call_variadic) {
        try t.expectEqual(@as(?usize, 1), block.instructions.items[0].call.variadic_start);
    }
    if (case.site == .call_record) {
        const descriptor = try block.instructions.items[0].call.arguments[0].abi();
        try t.expect(descriptor == .record);
    }
    if (case.site == .call_scalar) {
        const descriptor = try block.instructions.items[0].call.arguments[0].abi();
        try t.expect(descriptor == .scalar);
        try t.expectEqual(ir.ScalarType.long, descriptor.scalar.scalar());
    }
    const assembly = try amd64.emit(t.allocator, &module);
    defer t.allocator.free(assembly);
    try t.expect(std.mem.indexOf(u8, assembly, "movq target@GOTPCREL(%rip)") != null);
}

test "U05 extern operand sites retain GOT identity and emit GOTPCREL assembly" {
    for (cases) |case| {
        checkCase(case) catch |err| {
            std.debug.print("U05 witness failed: {s}\n", .{case.name});
            return err;
        };
    }
}
