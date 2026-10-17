//! Independent Zig-native core and experimental base-scalar AMD64 slice.
//! No legacy module is imported and no compilation delegates to the old port.
pub const abi_amd64 = @import("abi_amd64.zig");
pub const amd64 = @import("amd64.zig");
pub const stack_homes = @import("stack_homes.zig");
pub const interference = @import("interference.zig");
pub const liveness = @import("liveness.zig");
pub const optimize = @import("optimize.zig");
pub const semantics = @import("semantics.zig");
pub const memory = @import("memory.zig");
pub const interpreter = @import("interpreter.zig");
pub const cfg = @import("cfg.zig");
pub const ssa = @import("ssa.zig");
pub const source = @import("source.zig");
pub const frontend = @import("frontend.zig");
pub const lexer = @import("lexer.zig");
pub const symbols = @import("symbols.zig");
pub const ir = @import("ir.zig");
pub const module_validation = @import("module_validation.zig");
pub const byte_strings = @import("byte_strings.zig");
pub const data = @import("data.zig");
pub const DataId = @import("module.zig").DataId;
pub const Module = @import("module.zig").Module;

test {
    _ = @import("calls_test.zig");
    _ = @import("module_eval_test.zig");
    _ = @import("void_calls_test.zig");
    _ = @import("indirect_calls_test.zig");
    _ = @import("memory_test.zig");
    _ = @import("memory_eval_test.zig");
    _ = @import("blit_test.zig");
    _ = @import("operands_test.zig");
    _ = @import("signed_conversions_test.zig");
    _ = @import("unsigned_conversions_test.zig");
    _ = @import("low_word_test.zig");
    _ = @import("native_allocations_test.zig");
    _ = @import("interpreter_allocations_test.zig");
    _ = @import("symbol_addresses_test.zig");
    _ = @import("symbol_offsets_test.zig");
    _ = @import("data_test.zig");
    _ = @import("data_relocations_test.zig");
    _ = @import("data_strings_test.zig");
    _ = @import("data_bss_test.zig");
    _ = @import("interpreter_globals_test.zig");
    _ = @import("interpreter_data_relocations_test.zig");
    _ = @import("subword_abi_test.zig");
    _ = @import("amd64.zig");
    _ = @import("abi_amd64.zig");
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

fn exerciseHalt(allocator: @import("std").mem.Allocator) !void {
    const testing = @import("std").testing;
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "halt", .text = @embedFile("fixtures/halt.ssa") }, &diagnostic);
    defer module.deinit();
    for (module.functions.items) |f| {
        var graph = try cfg.Graph.init(allocator, f);
        defer graph.deinit();
        var live = try liveness.Snapshot.init(allocator, f, .{});
        defer live.deinit();
        var conflicts = try interference.Graph.init(allocator, f, .{});
        defer conflicts.deinit();
        var layout = try stack_homes.Layout.init(allocator, f, .{});
        defer layout.deinit();
        _ = try optimize.foldIntegerConstants(allocator, f);
        const arguments: []const ir.Constant = if (f.parameters.items.len == 0) &.{} else &.{.{ .word = 1 }};
        if (interpreter.evaluate(allocator, f, arguments, .{})) |_| return error.ExpectedHalt else |err| {
            if (err != error.Halted) return err;
        }
        for (f.blocks.items, 0..) |block, index| {
            if (block.terminator.? == .halt) {
                const id: ir.BlockId = @fromBackingInt(@as(u32, @intCast(index)));
                try testing.expectEqual(@as(usize, 0), graph.successors[index].slice().len);
                for (f.values.items, 0..) |_, value| try testing.expect(!live.isLiveOut(id, @fromBackingInt(@as(u32, @intCast(value)))).?);
            }
        }
    }
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(allocator, &module, options);
        defer allocator.free(assembly);
        try testing.expectEqual(@as(usize, 3), @import("std").mem.count(u8, assembly, "\tud2\n"));
        try testing.expect(@import("std").mem.indexOf(u8, assembly, "idivl") != null);
    }
}

test "halt analyses evaluation folding and all home modes clean up every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exerciseHalt);
}
