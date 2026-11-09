//! Focused O04 witnesses: owned phi inputs and representative GOT-bearing
//! copy/binary instruction builders. Not the full O04 ledger or an M12
//! mutation run. Ordinals are zero-based allocation attempts in the measured
//! successful transaction; in-place resize is disabled. Failed reservations
//! may remain on the surviving function until its eventual destruction.
const std = @import("std");
const t = std.testing;
const ir = @import("ir.zig");
const Module = @import("module.zig").Module;
const SymbolId = @import("symbols.zig").Id;
const validation = @import("module_validation.zig");

const Kind = enum { append_copy, append_binary, define_copy, define_binary };

fn phiAttempt(f: *ir.Function, join: ir.BlockId, result: ir.ValueId, left: ir.BlockId, right: ir.BlockId, symbol: SymbolId, fail: bool) !void {
    // The builder must neither consume nor retain this caller-owned buffer.
    const inputs = try t.allocator.dupe(ir.PhiInput, &.{
        .{ .predecessor = left, .value = .{ .got_symbol = symbol } },
        .{ .predecessor = right, .value = .{ .constant = .{ .long = 17 } } },
    });
    defer {
        inputs[0].value = .{ .constant = .{ .long = 99 } };
        inputs[1].predecessor = left;
        t.allocator.free(inputs);
    }
    if (fail) {
        try t.expectError(error.OutOfMemory, f.definePhi(join, result, inputs));
        try t.expectEqual(left, inputs[0].predecessor);
        try t.expectEqual(symbol, inputs[0].value.got_symbol);
        try t.expectEqual(right, inputs[1].predecessor);
        try t.expectEqual(@as(u64, 17), inputs[1].value.constant.long);
    } else {
        try f.definePhi(join, result, inputs);
        const stored = f.blocks.items[@backingInt(join)].phis.items;
        try t.expect(@intFromPtr(stored[stored.len - 1].inputs.ptr) != @intFromPtr(inputs.ptr));
    }
}

fn checkOldPhis(f: *const ir.Function, join: ir.BlockId, count: usize, symbol: SymbolId) !void {
    const phis = f.blocks.items[@backingInt(join)].phis.items;
    for (phis[0..count], 0..) |phi, index| {
        try t.expectEqual(symbol, phi.inputs[0].value.got_symbol);
        const link = f.values.items[@backingInt(phi.result)].definition.phi;
        try t.expectEqual(join, link.block);
        try t.expectEqual(index, link.index);
    }
}

fn phiRetry(allocator: std.mem.Allocator, growth: bool, ordinal: ?usize) !usize {
    var failing = t.FailingAllocator.init(allocator, .{ .resize_fail_index = 0 });
    var module = Module.init(failing.allocator());
    defer module.deinit();
    const symbol = try module.symbols.intern("external_phi");
    const id = try module.addFunction("phi_owner", .long);
    const f = module.getFunction(id).?;
    const entry = try f.addBlock(null);
    const left = try f.addBlock(null);
    const right = try f.addBlock(null);
    const join = try f.addBlock(null);
    if (growth) {
        // Saturate the existing phi array so the transaction must grow it.
        while (true) {
            const filler = try f.declareValue(.long);
            try f.definePhi(join, filler, &.{
                .{ .predecessor = left, .value = .{ .got_symbol = symbol } },
                .{ .predecessor = right, .value = .{ .constant = .{ .long = 17 } } },
            });
            const phis = f.blocks.items[@backingInt(join)].phis;
            if (phis.items.len == phis.capacity) break;
        }
    }
    const result = try f.declareValue(.long);
    const before = f.blocks.items[@backingInt(join)].phis.items.len;
    const value_count = f.values.items.len;
    const start = failing.alloc_index;
    if (ordinal) |n| failing.fail_index = start + n;
    try phiAttempt(f, join, result, left, right, symbol, ordinal != null);
    const attempts = failing.alloc_index - start;
    if (ordinal != null) {
        try t.expect(failing.has_induced_failure);
        try t.expectEqual(before, f.blocks.items[@backingInt(join)].phis.items.len);
        try t.expectEqual(value_count, f.values.items.len);
        try t.expect(f.values.items[@backingInt(result)].definition == .pending);
        try checkOldPhis(f, join, before, symbol);
        // The failed attempt's input has already been overwritten and freed.
        failing.fail_index = std.math.maxInt(usize);
        try phiAttempt(f, join, result, left, right, symbol, false);
    }
    const phis = f.blocks.items[@backingInt(join)].phis.items;
    try t.expectEqual(before + 1, phis.len);
    try t.expectEqual(result, phis[before].result);
    try t.expectEqual(left, phis[before].inputs[0].predecessor);
    try t.expectEqual(symbol, phis[before].inputs[0].value.got_symbol);
    try t.expectEqual(right, phis[before].inputs[1].predecessor);
    try t.expectEqual(@as(u64, 17), phis[before].inputs[1].value.constant.long);
    const backlink = f.values.items[@backingInt(result)].definition.phi;
    try t.expectEqual(join, backlink.block);
    try t.expectEqual(before, backlink.index);
    try checkOldPhis(f, join, before, symbol);
    try f.terminate(entry, .{ .branch = .{ .condition = .{ .constant = .{ .word = 1 } }, .taken = left, .not_taken = right } });
    try f.terminate(left, .{ .jump = join });
    try f.terminate(right, .{ .jump = join });
    try f.terminate(join, .{ .return_value = .{ .value = result } });
    try validation.validate(t.allocator, &module);
    return attempts;
}

fn buildOperand(f: *ir.Function, block: ir.BlockId, kind: Kind, pending: ?ir.ValueId, a: ir.Operand, b: ir.Operand) !ir.ValueId {
    return switch (kind) {
        .append_copy => try f.appendCopy(block, .long, a),
        .append_binary => try f.appendBinary(block, .long, .sub, a, b),
        .define_copy => blk: {
            try f.defineCopy(block, pending.?, a);
            break :blk pending.?;
        },
        .define_binary => blk: {
            try f.defineBinary(block, pending.?, .sub, a, b);
            break :blk pending.?;
        },
    };
}

fn checkOldInstructions(f: *const ir.Function, block: ir.BlockId, count: usize, symbol: SymbolId) !void {
    const instructions = f.blocks.items[@backingInt(block)].instructions.items;
    for (instructions[0..count], 0..) |instruction, index| {
        try t.expectEqual(symbol, instruction.copy.operand.got_symbol);
        const link = f.values.items[@backingInt(instruction.result().?)].definition.instruction;
        try t.expectEqual(block, link.block);
        try t.expectEqual(index, link.index);
    }
}

fn operandRetry(allocator: std.mem.Allocator, kind: Kind, growth: bool, ordinal: ?usize) !usize {
    var failing = t.FailingAllocator.init(allocator, .{ .resize_fail_index = 0 });
    var module = Module.init(failing.allocator());
    defer module.deinit();
    const a = try module.symbols.intern("external_lhs");
    const b = try module.symbols.intern("external_rhs");
    const id = try module.addFunction("operand_owner", .long);
    const f = module.getFunction(id).?;
    const block = try f.addBlock(null);
    const filler_block = try f.addBlock(null);
    if (growth) {
        while (true) {
            _ = try f.appendCopy(block, .long, .{ .got_symbol = a });
            const instructions = f.blocks.items[@backingInt(block)].instructions;
            if (instructions.items.len == instructions.capacity) break;
        }
    }
    const pending: ?ir.ValueId = switch (kind) {
        .define_copy, .define_binary => try f.declareValue(.long),
        else => null,
    };
    if (growth) {
        // Saturate values independently without changing the target block.
        while (f.values.items.len < f.values.capacity) {
            _ = try f.appendCopy(filler_block, .long, .{ .got_symbol = b });
        }
    }
    const instruction_count = f.blocks.items[@backingInt(block)].instructions.items.len;
    const value_count = f.values.items.len;
    var inputs = [_]ir.Operand{ .{ .got_symbol = a }, .{ .got_symbol = b } };
    const start = failing.alloc_index;
    if (ordinal) |n| {
        failing.fail_index = start + n;
        try t.expectError(error.OutOfMemory, buildOperand(f, block, kind, pending, inputs[0], inputs[1]));
        try t.expect(failing.has_induced_failure);
        try t.expectEqual(instruction_count, f.blocks.items[@backingInt(block)].instructions.items.len);
        try t.expectEqual(value_count, f.values.items.len);
        if (pending) |result| try t.expect(f.values.items[@backingInt(result)].definition == .pending);
        try checkOldInstructions(f, block, instruction_count, a);
        try t.expectEqual(a, inputs[0].got_symbol);
        try t.expectEqual(b, inputs[1].got_symbol);
        failing.fail_index = std.math.maxInt(usize);
    }
    const failed_attempts = failing.alloc_index - start;
    const result = try buildOperand(f, block, kind, pending, inputs[0], inputs[1]);
    const attempts = if (ordinal == null) failing.alloc_index - start else failed_attempts;
    // Fixed operands are passed by value; clobber the caller's copies.
    inputs[0] = .{ .constant = .{ .long = 99 } };
    inputs[1] = inputs[0];
    const instructions = f.blocks.items[@backingInt(block)].instructions.items;
    try t.expectEqual(instruction_count + 1, instructions.len);
    try t.expectEqual(value_count + @as(usize, if (pending == null) 1 else 0), f.values.items.len);
    try t.expectEqual(result, instructions[instruction_count].result().?);
    switch (kind) {
        .append_copy, .define_copy => try t.expectEqual(a, instructions[instruction_count].copy.operand.got_symbol),
        .append_binary, .define_binary => {
            try t.expectEqual(a, instructions[instruction_count].binary.lhs.got_symbol);
            try t.expectEqual(b, instructions[instruction_count].binary.rhs.got_symbol);
        },
    }
    const link = f.values.items[@backingInt(result)].definition.instruction;
    try t.expectEqual(block, link.block);
    try t.expectEqual(instruction_count, link.index);
    try checkOldInstructions(f, block, instruction_count, a);
    try f.terminate(block, .{ .return_value = .{ .value = result } });
    try f.terminate(filler_block, .{ .return_value = .{ .got_symbol = b } });
    try validation.validate(t.allocator, &module);
    return attempts;
}

test "O04 owned GOT phi retries every measured allocation on the same function" {
    var tracked = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    for ([_]bool{ false, true }) |growth| {
        const attempts = try phiRetry(tracked.allocator(), growth, null);
        std.debug.print("O04 phi growth={} measured allocation attempts={d}\n", .{ growth, attempts });
        try t.expect(attempts > 0);
        try t.expectEqual(tracked.allocated_bytes, tracked.freed_bytes);
        for (0..attempts) |ordinal| {
            _ = try phiRetry(tracked.allocator(), growth, ordinal);
            try t.expectEqual(tracked.allocated_bytes, tracked.freed_bytes);
        }
    }
}

test "O04 GOT copy and binary builders retry every measured allocation" {
    var tracked = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    for ([_]Kind{ .append_copy, .append_binary, .define_copy, .define_binary }) |kind| {
        for ([_]bool{ false, true }) |growth| {
            const attempts = try operandRetry(tracked.allocator(), kind, growth, null);
            std.debug.print("O04 {s} growth={} measured allocation attempts={d}\n", .{ @tagName(kind), growth, attempts });
            try t.expect(attempts > 0);
            try t.expectEqual(tracked.allocated_bytes, tracked.freed_bytes);
            for (0..attempts) |ordinal| {
                _ = try operandRetry(tracked.allocator(), kind, growth, ordinal);
                try t.expectEqual(tracked.allocated_bytes, tracked.freed_bytes);
            }
        }
    }
}
