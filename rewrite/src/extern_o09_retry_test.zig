//! Bounded O09 witnesses. Sweep the measured zero-based allocation frontier
//! of GOT target refusal and reached/unreached operands; not the full ledger.
//! No partial evaluation resume is claimed: retry on the same immutable module.
const std = @import("std");
const t = std.testing;
const ir = @import("ir.zig");
const Module = @import("module.zig").Module;
const FunctionId = @import("module.zig").FunctionId;
const interpreter = @import("interpreter.zig");
const validation = @import("module_validation.zig");

fn parse(text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(t.allocator, .{ .name = "extern-o09", .text = text }, &diagnostic);
}
fn id(n: u32) FunctionId {
    return @fromBackingInt(n);
}
const Outcome = enum { step, indirect, standalone_call, address, safe };

fn expectOutcome(allocator: std.mem.Allocator, module: *const Module, entry: FunctionId, args: []const ir.Constant, options: interpreter.Options, standalone: bool, outcome: Outcome) !void {
    const result = if (standalone)
        interpreter.evaluate(allocator, module.functions.items[@backingInt(entry)], args, options)
    else
        interpreter.evaluateModule(allocator, module, entry, args, options);
    switch (outcome) {
        .step => try t.expectError(error.StepLimitExceeded, result),
        .indirect => try t.expectError(error.UnsupportedIndirectCall, result),
        .standalone_call => try t.expectError(error.UnsupportedCall, result),
        .address => try t.expectError(error.UnsupportedSymbolAddress, result),
        .safe => try t.expectEqual(@as(u64, 23), (try result).?.long),
    }
}

fn measured(module: *const Module, entry: FunctionId, args: []const ir.Constant, options: interpreter.Options, standalone: bool, outcome: Outcome) !usize {
    var count = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try expectOutcome(count.allocator(), module, entry, args, options, standalone, outcome);
    try t.expectEqual(count.allocated_bytes, count.freed_bytes);
    return count.alloc_index;
}

fn sweep(module: *const Module, entry: FunctionId, args: []const ir.Constant, options: interpreter.Options, standalone: bool, outcome: Outcome, attempts: usize) !void {
    try t.expect(attempts > 0);
    for (0..attempts) |ordinal| {
        var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = ordinal, .resize_fail_index = 0 });
        const result = if (standalone)
            interpreter.evaluate(failing.allocator(), module.functions.items[@backingInt(entry)], args, options)
        else
            interpreter.evaluateModule(failing.allocator(), module, entry, args, options);
        try t.expectError(error.OutOfMemory, result);
        try t.expect(failing.has_induced_failure);
        try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        failing.fail_index = std.math.maxInt(usize);
        try expectOutcome(failing.allocator(), module, entry, args, options, standalone, outcome);
        try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
    // Failing the first attempt after the measured trace must not be reached.
    var after = t.FailingAllocator.init(t.allocator, .{ .fail_index = attempts, .resize_fail_index = 0 });
    try expectOutcome(after.allocator(), module, entry, args, options, standalone, outcome);
    try t.expect(!after.has_induced_failure);
    try t.expectEqual(attempts, after.alloc_index);
    try t.expectEqual(after.allocated_bytes, after.freed_bytes);
}

test "O09 GOT call refusal preserves setup OOM and allocates nothing after the step frontier" {
    var module = try parse("data $local={ l 41 }\nfunction l $caller() {\n@entry\n%r =l call extern $target(env extern $environment, l extern $argument)\nret %r\n}");
    defer module.deinit();
    const call = &module.functions.items[0].blocks.items[0].instructions.items[0].call;
    const target = call.callee.extern_symbol;
    for ([_]ir.CallTarget{ .{ .extern_symbol = target }, .{ .address = .{ .got_symbol = target } } }) |form| {
        call.callee = form;
        try validation.validate(t.allocator, &module);
        for ([_]bool{ false, true }) |global| {
            const stopped: interpreter.Options = .{ .max_steps = 0, .max_call_depth = 1, .global_memory = if (global) .{} else null };
            const reached: interpreter.Options = .{ .max_steps = 1, .max_call_depth = 1, .global_memory = if (global) .{} else null };
            const before = try measured(&module, id(0), &.{}, stopped, false, .step);
            const after = try measured(&module, id(0), &.{}, reached, false, .indirect);
            // No additional allocation attempts are measured after the step frontier.
            try t.expectEqual(before, after);
            std.debug.print("O09 call global={} wrapped={} setup attempts={d}\n", .{ global, form == .address, after });
            try sweep(&module, id(0), &.{}, reached, false, .indirect, after);
        }
        const stopped: interpreter.Options = .{ .max_steps = 0, .max_call_depth = 1 };
        const reached: interpreter.Options = .{ .max_steps = 1, .max_call_depth = 1 };
        const before = try measured(&module, id(0), &.{}, stopped, true, .step);
        const after = try measured(&module, id(0), &.{}, reached, true, .standalone_call);
        try t.expectEqual(before, after);
        try sweep(&module, id(0), &.{}, reached, true, .standalone_call, after);
    }
}

test "O09 reached and unchosen GOT operands retry every measured setup OOM" {
    var module = try parse("data $local={ l 41 }\nfunction l $choose(w %c) {\n@entry\njnz %c, @use, @skip\n@use\n%p =l copy extern $target\nret %p\n@skip\nret 23\n}");
    defer module.deinit();
    try validation.validate(t.allocator, &module);
    for ([_]bool{ false, true }) |global| {
        const options: interpreter.Options = .{ .global_memory = if (global) .{} else null };
        for ([_]bool{ false, true }) |reached| {
            const args = [_]ir.Constant{.{ .word = if (reached) 1 else 0 }};
            const outcome: Outcome = if (reached) .address else .safe;
            const attempts = try measured(&module, id(0), &args, options, false, outcome);
            std.debug.print("O09 operand global={} reached={} setup attempts={d}\n", .{ global, reached, attempts });
            try sweep(&module, id(0), &args, options, false, outcome, attempts);
        }
    }
}
