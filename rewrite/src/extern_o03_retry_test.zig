//! Bounded O03 call-ownership witness; not the complete O03 ledger.
//! Fresh setup per failure ordinal; retry occurs on the same surviving function.
const std = @import("std");
const t = std.testing;
const ir = @import("ir.zig");
const Module = @import("module.zig").Module;
const validation = @import("module_validation.zig");

const Kind = enum { record_env, variadic };

fn transaction(allocator: std.mem.Allocator, ordinal: ?usize, expect_oom: bool, wrapped: bool, kind: Kind) !usize {
    var failing = t.FailingAllocator.init(allocator, .{ .resize_fail_index = 0 });
    var module = Module.init(failing.allocator());
    defer module.deinit();
    const record = try module.addRecord("T", null, &.{.{ .element = .{ .scalar = .byte } }});
    const target = try module.symbols.intern("external_target");
    const argument = try module.symbols.intern("external_record");
    const second = try module.symbols.intern("external_scalar");
    const environment = try module.symbols.intern("external_environment");
    const function_id = try module.addFunction("caller", null);
    const f = module.getFunction(function_id).?;
    const block = try f.addBlock(null);
    // Fill the instruction backing array so the tested append must grow it.
    while (f.blocks.items[0].instructions.items.len == 0 or
        f.blocks.items[0].instructions.items.len < f.blocks.items[0].instructions.capacity)
    {
        const filler = try f.declareValue(.long);
        try f.defineCopy(block, filler, .{ .constant = .{ .long = 17 } });
    }
    const old_len = f.blocks.items[0].instructions.items.len;
    const old_capacity = f.blocks.items[0].instructions.capacity;
    const result = try f.declareValue(.long);
    const callee: ir.CallTarget = if (wrapped) .{ .address = .{ .got_symbol = target } } else .{ .extern_symbol = target };
    var args = [_]ir.CallArgument{
        ir.CallArgument.initDescriptor(.{ .record = record }, .{ .got_symbol = argument }),
        .{ .scalar_type = .long, .operand = .{ .got_symbol = second } },
    };
    const options: ir.CallOptions = switch (kind) {
        .record_env => .{ .result_descriptor = .{ .record = record }, .environment = .{ .got_symbol = environment } },
        .variadic => .{ .variadic_start = 1 },
    };
    const start = failing.alloc_index;
    if (ordinal) |n| {
        failing.fail_index = start + n;
        if (expect_oom) {
            try t.expectError(error.OutOfMemory, f.appendCall(block, result, callee, &args, options));
            try t.expect(failing.has_induced_failure);
            try t.expectEqual(old_len, f.blocks.items[0].instructions.items.len);
            try t.expect(f.blocks.items[0].instructions.capacity >= old_capacity);
            try t.expect(f.values.items[@backingInt(result)].definition == .pending);
            for (f.blocks.items[0].instructions.items, 0..) |instruction, index| {
                try t.expect(instruction == .copy);
                const backlink = f.values.items[@backingInt(instruction.copy.result)].definition.instruction;
                try t.expectEqual(block, backlink.block);
                try t.expectEqual(index, backlink.index);
            }
            failing.fail_index = std.math.maxInt(usize);
        }
    }
    try f.appendCall(block, result, callee, &args, options);
    if (!expect_oom) try t.expect(!failing.has_induced_failure);
    const attempts = failing.alloc_index - start;
    // Overwrite the borrowed inputs and verify the published metadata is owned.
    args[0] = .{ .scalar_type = .long, .operand = .{ .constant = .{ .long = 0 } } };
    args[1] = .{ .scalar_type = .long, .operand = .{ .constant = .{ .long = 1 } } };
    try t.expectEqual(old_len + 1, f.blocks.items[0].instructions.items.len);
    for (f.blocks.items[0].instructions.items[0..old_len], 0..) |instruction, index| {
        try t.expect(instruction == .copy);
        const prior = f.values.items[@backingInt(instruction.copy.result)].definition.instruction;
        try t.expectEqual(block, prior.block);
        try t.expectEqual(index, prior.index);
    }
    const call = f.blocks.items[0].instructions.items[old_len].call;
    try t.expectEqual(std.meta.activeTag(callee), std.meta.activeTag(call.callee));
    try t.expectEqual(target, call.callee.symbolicIdentity().?);
    try t.expect(call.arguments[0].operand == .got_symbol);
    try t.expectEqual(argument, call.arguments[0].operand.got_symbol);
    try t.expectEqual(record, call.arguments[0].descriptor.?.record);
    try t.expectEqual(second, call.arguments[1].operand.got_symbol);
    switch (kind) {
        .record_env => {
            try t.expectEqual(record, call.result_descriptor.?.record);
            try t.expectEqual(environment, call.environment.?.got_symbol);
            try t.expect(call.variadic_start == null);
        },
        .variadic => {
            try t.expectEqual(@as(?usize, 1), call.variadic_start);
            try t.expect(call.environment == null and call.result_descriptor == null);
        },
    }
    const backlink = f.values.items[@backingInt(result)].definition.instruction;
    try t.expectEqual(block, backlink.block);
    try t.expectEqual(old_len, backlink.index);
    try f.terminate(block, .{ .return_value = null });
    try validation.validate(allocator, &module);
    return attempts;
}

test "O03 record and variadic GOT call builders retry after each growth OOM" {
    var tracked = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    for ([_]bool{ false, true }) |wrapped| for ([_]Kind{ .record_env, .variadic }) |kind| {
        const attempts = try transaction(tracked.allocator(), null, false, wrapped, kind);
        try t.expect(attempts > 0);
        std.debug.print("O03 wrapped={} kind={s} attempts={d}\n", .{ wrapped, @tagName(kind), attempts });
        for (0..attempts) |ordinal| _ = try transaction(tracked.allocator(), ordinal, true, wrapped, kind);
        try t.expectEqual(attempts, try transaction(tracked.allocator(), attempts, false, wrapped, kind));
    };
    try t.expectEqual(tracked.allocated_bytes, tracked.freed_bytes);
}
