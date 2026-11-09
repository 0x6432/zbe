//! Conservative native ELF/GOT symbol eligibility. This does not change the
//! module symbol pool or restrictions on existing ordinary symbol references.
const std = @import("std");
const symbols = @import("symbols.zig");

fn isAlpha(byte: u8) bool {
    return (byte >= 'A' and byte <= 'Z') or (byte >= 'a' and byte <= 'z');
}
fn isDigit(byte: u8) bool {
    return byte >= '0' and byte <= '9';
}

/// The intersection of portable symbol rules and [A-Za-z_][A-Za-z0-9_.$]*.
/// This checks decoded canonical bytes, never source spelling or a GOT suffix.
pub fn validNativeExternName(name: []const u8) bool {
    if (!symbols.validPortableName(name)) return false;
    if (!(isAlpha(name[0]) or name[0] == '_')) return false;
    for (name[1..]) |byte| {
        if (!(isAlpha(byte) or isDigit(byte) or byte == '_' or byte == '.' or byte == '$')) return false;
    }
    return true;
}

/// Called only after generic module validation. Scan every actual GOT operand,
/// including dead blocks and phi inputs; ordinary pool entries are untouched.
pub fn validateFunction(module: *const @import("module.zig").Module, function: *const @import("ir.zig").Function) error{ InvalidSymbol, UnsupportedExternSymbol }!void {
    for (function.blocks.items) |block| {
        for (block.phis.items) |phi| for (phi.inputs) |input| try validateOperand(module, input.value);
        for (block.instructions.items) |instruction| {
            var operands = instruction.operands();
            while (operands.next()) |operand| try validateOperand(module, operand);
        }
        switch (block.terminator.?) {
            .branch => |branch| try validateOperand(module, branch.condition),
            .return_value => |value| if (value) |operand| try validateOperand(module, operand),
            .jump, .halt => {},
        }
    }
}

fn validateOperand(module: *const @import("module.zig").Module, operand: @import("ir.zig").Operand) error{ InvalidSymbol, UnsupportedExternSymbol }!void {
    if (operand != .got_symbol) return;
    const name = module.symbols.get(operand.got_symbol) orelse return error.InvalidSymbol;
    if (!symbols.validPortableName(name)) return error.InvalidSymbol;
    if (!validNativeExternName(name)) return error.UnsupportedExternSymbol;
}

test "extern names use conservative decoded native spelling" {
    const testing = std.testing;
    for ([_][]const u8{ "a", "Z", "_", "_x", "alpha", "a.b", "a$b", "a0_.$" }) |name| {
        try testing.expect(validNativeExternName(name));
    }
    for ([_][]const u8{ "", ".", ".Lx", ".Lzbe@0", "0a", "$x", "a@v", "a b", "a-b", "a\\b", "a\"b", "a\n", "\xc3\xa9" }) |name| {
        try testing.expect(!validNativeExternName(name));
    }
    // Ordinary portable-but-nonnative names remain valid for the old pathway.
    try testing.expect(symbols.validPortableName(".local"));
    try testing.expect(!validNativeExternName(".local"));
}

test "all byte values independently checked in initial and suffix positions" {
    const testing = std.testing;
    for (0..256) |value| {
        const byte: u8 = @intCast(value);
        const expected_alpha = (value >= 'A' and value <= 'Z') or (value >= 'a' and value <= 'z');
        const expected_digit = value >= '0' and value <= '9';
        const initial = [_]u8{byte};
        const suffix = [_]u8{ 'a', byte };
        try testing.expectEqual(expected_alpha or value == '_', validNativeExternName(&initial));
        try testing.expectEqual(expected_alpha or expected_digit or value == '_' or value == '.' or value == '$', validNativeExternName(&suffix));
    }
}
