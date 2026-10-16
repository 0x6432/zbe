//! Independent Zig-native core and experimental base-scalar AMD64 slice.
//! No legacy module is imported and no compilation delegates to the old port.
pub const amd64 = @import("amd64.zig");
pub const stack_homes = @import("stack_homes.zig");
pub const interference = @import("interference.zig");
pub const liveness = @import("liveness.zig");
pub const optimize = @import("optimize.zig");
pub const semantics = @import("semantics.zig");
pub const interpreter = @import("interpreter.zig");
pub const cfg = @import("cfg.zig");
pub const ssa = @import("ssa.zig");
pub const source = @import("source.zig");
pub const frontend = @import("frontend.zig");
pub const lexer = @import("lexer.zig");
pub const symbols = @import("symbols.zig");
pub const ir = @import("ir.zig");
pub const Module = @import("module.zig").Module;

test {
    _ = @import("amd64.zig");
    _ = @import("interpreter.zig");
    _ = @import("optimize.zig");
    _ = @import("liveness.zig");
    _ = @import("interference.zig");
    _ = @import("stack_homes.zig");
    _ = @import("cfg.zig");
    _ = @import("ssa.zig");
    _ = @import("source.zig");
    _ = @import("lexer.zig");
    _ = @import("frontend.zig");
    _ = @import("symbols.zig");
    _ = @import("ir.zig");
    _ = @import("module.zig");
}

test "all SSA-dependent consumers reject entry backedges before analysis or mutation" {
    const std = @import("std");
    const testing = std.testing;
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(testing.allocator, .{ .name = "invalid-entry", .text = @embedFile("fixtures/entry-backedge.ssa") }, &diagnostic);
    defer module.deinit();
    const f = module.functions.items[0];
    var issue: ?ssa.Issue = null;
    try testing.expectError(error.EntryHasPredecessors, ssa.validate(testing.allocator, f, &issue));
    try testing.expectError(error.EntryHasPredecessors, liveness.Snapshot.init(testing.allocator, f, .{}));
    try testing.expectError(error.EntryHasPredecessors, interference.Graph.init(testing.allocator, f, .{}));
    try testing.expectError(error.EntryHasPredecessors, stack_homes.Layout.init(testing.allocator, f, .{}));
    try testing.expectError(error.EntryHasPredecessors, interpreter.evaluate(testing.allocator, f, &.{.{ .word = 1 }}, .{}));
    try testing.expectError(error.EntryHasPredecessors, optimize.foldIntegerConstants(testing.allocator, f));
    try testing.expect(f.blocks.items[1].instructions.items[0] == .copy);
    try testing.expectError(error.EntryHasPredecessors, amd64.emit(testing.allocator, &module));
    try testing.expectError(error.EntryHasPredecessors, amd64.emitWithOptions(testing.allocator, &module, .{ .reuse_stack_homes = true }));
    try testing.expectError(error.EntryHasPredecessors, amd64.emitWithOptions(testing.allocator, &module, .{ .callee_saved_homes = true }));
}
