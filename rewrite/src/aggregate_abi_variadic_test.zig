const std = @import("std");
const t = std.testing;
const Module = @import("module.zig").Module;
const frontend = @import("frontend.zig");
const planner = @import("abi_amd64_plan.zig");
const amd64 = @import("amd64.zig");
const interpreter = @import("interpreter.zig");
fn id(n: u32) @import("module.zig").FunctionId {
    return @fromBackingInt(n);
}
fn parse(a: std.mem.Allocator, text: []const u8) !Module {
    var d: ?@import("source.zig").Diagnostic = null;
    return frontend.parse(a, .{ .name = "aggregate_abi_variadic", .text = text }, &d);
}
const owned = "type :S=align 16 {s}\ntype :M={b 23}\nfunction :M $f(:M %a,w %tag,...){\n@e\n%list =l alloc8 24\nvastart %list\n%x =:M call $outside(:M %a,w %tag,...,d d_1)\nret %x\n}\nfunction w $gap(){\n@e\nret 1\n}\nfunction :S $g(:S %s,...){\n@e\n%list =l alloc8 24\nvastart %list\n%x =:S call $other(:S %s,...,l 99)\nret %x\n}";
test "aggregate_abi_variadic exact named raw40 versus rounded48 occupancy and tail rollback" {
    var m = try parse(t.allocator, "type :SS={s 3}\ntype :II={b 13}\ntype :SI={s,l}\ntype :M={b 23}\nfunction :M $f(l %a,l %b,l %c,l %d,:SS %s,:II %i,l %last,:M %m,...){\n@e\n%list =l alloc8 24\nvastart %list\n%r =:M call $out(l 1,l 2,l 3,l 4,:SS %s,:II %i,l 5,:M %m,...,:SS %s,:SI 0,d d_1,l 99)\nret %r\n}");
    defer m.deinit();
    var p = try planner.FunctionPlan.init(t.allocator, &m, id(0), .{});
    defer p.deinit();
    try t.expectEqual(@as(u64, 40), p.signature.stack_bytes);
    try t.expectEqual(@as(u64, 48), p.signature.outgoing_bytes);
    try t.expectEqual(@as(i32, 56), try p.signature.stackEndIncomingOffset());
    try t.expectEqual(@as(u8, 6), p.signature.general_used);
    try t.expectEqual(@as(u8, 2), p.signature.vector_used);
    try t.expectEqual(@as(u64, 64), p.calls[0].signature.stack_bytes);
    try t.expectEqual(@as(u8, 5), p.calls[0].signature.vector_used);
    try t.expectEqual(@as(?usize, 8), p.calls[0].signature.variadic_start);
    try t.expect(p.frame.variadic_save_end != null);
    const output = try amd64.emit(t.allocator, &m);
    defer t.allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "leaq 56(%rbp), %rax") != null);
    try t.expect(std.mem.indexOf(u8, output, "movb $5, %al") != null);
}
test "aggregate_abi_variadic exact named56 versus64 with aligned fallback and checked endpoint" {
    var m = try parse(t.allocator, "type :N=align 16 {s}\ntype :M={b 23}\nfunction :M $f(l %a,l %b,l %c,l %d,l %e,d %d1,d %d2,d %d3,d %d4,d %d5,d %d6,d %d7,d %d8,:M %m,:N %n,l %last,...){\n@e\n%list =l alloc8 24\nvastart %list\nret %m\n}");
    defer m.deinit();
    var p = try planner.FunctionPlan.init(t.allocator, &m, id(0), .{});
    defer p.deinit();
    try t.expectEqual(@as(u64, 56), p.signature.stack_bytes);
    try t.expectEqual(@as(u64, 64), p.signature.outgoing_bytes);
    try t.expectEqual(@as(i32, 72), try p.signature.stackEndIncomingOffset());
    try t.expectEqual(@as(u8, 6), p.signature.general_used);
    try t.expectEqual(@as(u8, 8), p.signature.vector_used);
    var endpoint = p.signature;
    endpoint.stack_bytes = std.math.maxInt(i32) - 16;
    try t.expectEqual(std.math.maxInt(i32), try endpoint.stackEndIncomingOffset());
    endpoint.stack_bytes += 1;
    try t.expectError(error.StackArgumentsTooLarge, endpoint.stackEndIncomingOffset());
    endpoint.stack_bytes = std.math.maxInt(u64);
    try t.expectError(error.StackArgumentsTooLarge, endpoint.stackEndIncomingOffset());
}
fn exercise(a: std.mem.Allocator) !void {
    var m = try parse(a, owned);
    defer m.deinit();
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |o| {
        const text = try amd64.emitWithOptions(a, &m, o);
        a.free(text);
    }
}
test "aggregate_abi_variadic exhaustive parse plan savearea objects pads and writer allocation cleanup" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
test "aggregate_abi_variadic each emission failure leaves same module retryable and balanced" {
    var m = try parse(t.allocator, owned);
    defer m.deinit();
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |o| {
        var done = false;
        for (0..2048) |n| {
            var f = t.FailingAllocator.init(t.allocator, .{ .fail_index = n, .resize_fail_index = 0 });
            if (amd64.emitWithOptions(f.allocator(), &m, o)) |text| {
                f.allocator().free(text);
                done = true;
            } else |err| {
                try t.expectEqual(error.OutOfMemory, err);
                const retry = try amd64.emit(t.allocator, &m);
                t.allocator.free(retry);
            }
            try t.expectEqual(f.allocated_bytes, f.freed_bytes);
            if (done) break;
        }
        try t.expect(done);
    }
}
test "aggregate_abi_variadic plan facts survive source module and retain byte counts" {
    const text = try t.allocator.dupe(u8, owned);
    var m = try parse(t.allocator, text);
    @memset(text, 0xa5);
    t.allocator.free(text);
    var p = try planner.ModulePlans.init(t.allocator, &m, .{ .callee_saved_homes = true });
    m.deinit();
    defer p.deinit();
    try t.expect(p.get(0).?.signature.variadic);
    try t.expectEqual(@as(u64, 24), p.get(0).?.signature.stack_bytes);
    try t.expect(p.get(1) == null);
    try t.expectEqual(@as(u64, 0), p.get(2).?.signature.stack_bytes);
}
test "aggregate_abi_variadic known named prefix counts records once and refuses mismatched marker" {
    var m = try parse(t.allocator, "type :S={s 3}\nfunction $f(:S %p,w %tag,...){\n@e\nret\n}\nfunction $caller(){\n@e\ncall $f(:S 0,w 1,...,l 99)\nret\n}");
    defer m.deinit();
    try @import("module_validation.zig").validate(t.allocator, &m);
    m.functions.items[1].blocks.items[0].instructions.items[0].call.variadic_start = 1;
    try t.expectError(error.CallSignatureMismatch, @import("module_validation.zig").validate(t.allocator, &m));
}
test "aggregate_abi_variadic interpreter root and reached calls never gain aggregate tail execution" {
    var m = try parse(t.allocator, owned);
    defer m.deinit();
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluate(t.allocator, m.functions.items[0], &.{}, .{ .max_call_depth = 0 }));
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluateModule(t.allocator, &m, id(0), &.{}, .{ .max_call_depth = 0, .internal_variadic_calls = true }));
    var caller = try parse(t.allocator, "type :S={s}\nfunction $f(){\n@e\ncall 0(...,:S $missing)\nret\n}");
    defer caller.deinit();
    try t.expectError(error.StepLimitExceeded, interpreter.evaluate(t.allocator, caller.functions.items[0], &.{}, .{ .max_steps = 0 }));
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluate(t.allocator, caller.functions.items[0], &.{}, .{ .max_steps = 1 }));
}

test "aggregate_abi_variadic literal65536 boundary includes176 save and16 private object" {
    for ([_]usize{ 8166, 8167 }) |copies| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(t.allocator);
        try text.appendSlice(t.allocator, "type :T=align 16 {s}\nfunction :T $f(:T %p,...){\n@e\n%list =l alloc8 24\nvastart %list\n");
        for (0..copies) |n| {
            var buf: [80]u8 = undefined;
            try text.appendSlice(t.allocator, try std.fmt.bufPrint(&buf, "%v{d} =l copy 0\n", .{n}));
        }
        try text.appendSlice(t.allocator, "ret %p\n}\n");
        var m = try parse(t.allocator, text.items);
        defer m.deinit();
        if (copies == 8166) {
            var p = try planner.FunctionPlan.init(t.allocator, &m, id(0), .{});
            defer p.deinit();
            // (8166 dead values + p + list)*8 = 65344; +176 +16 =65536.
            try t.expectEqual(@as(u64, 65536), p.frame.bytes);
            try t.expectEqual(@as(u64, 65520), p.frame.variadic_save_end.?);
            try t.expectEqual(@as(u64, 65536), p.parameter_objects[0].end);
        } else try t.expectError(error.FrameTooLarge, planner.FunctionPlan.init(t.allocator, &m, id(0), .{}));
    }
}

fn movedSide(allocator: std.mem.Allocator, text: []const u8, prefix: bool) ![]u8 {
    if (!prefix) return allocator.dupe(u8, text);
    const first = std.mem.indexOf(u8, text, "export function ").?;
    const side = std.mem.indexOf(u8, text, "\nfunction ").? + 1;
    return std.mem.concat(allocator, u8, &.{ text[0..first], text[side..], text[first..side] });
}
fn fragment(assembly: []const u8, name: []const u8) []const u8 {
    var h: [128]u8 = undefined;
    var q: [128]u8 = undefined;
    const head = std.fmt.bufPrint(&h, ".globl {s}\n.type {s}, @function\n", .{ name, name }) catch unreachable;
    const tail = std.fmt.bufPrint(&q, ".size {s}, .-{s}\n", .{ name, name }) catch unreachable;
    const start = std.mem.indexOf(u8, assembly, head).?;
    return assembly[start .. start + std.mem.indexOf(u8, assembly[start..], tail).? + tail.len];
}
test "aggregate_abi_variadic mixed prefix suffix reference establishes exact symbol IDs and function ordinals" {
    for ([_]bool{ false, true }) |prefix| {
        const text = try movedSide(t.allocator, @embedFile("fixtures/aggregate_abi_variadic_mixed.ssa"), prefix);
        defer t.allocator.free(text);
        const other = try movedSide(t.allocator, @embedFile("fixtures/aggregate_abi_variadic_scalar_reference.ssa"), prefix);
        defer t.allocator.free(other);
        var module = try parse(t.allocator, text);
        defer module.deinit();
        var reference = try parse(t.allocator, other);
        defer reference.deinit();
        try t.expectEqual(reference.symbols.names.items.len, module.symbols.names.items.len);
        for (reference.symbols.names.items, module.symbols.names.items) |a, b| try t.expectEqualStrings(a, b);
        try t.expectEqual(reference.functions.items.len, module.functions.items.len);
        for (reference.functions.items, module.functions.items, 0..) |a, b, n| {
            try t.expectEqual(a.name, b.name);
            try t.expect(reference.getFunction(id(@intCast(n))).? == a and module.getFunction(id(@intCast(n))).? == b);
            if (n == (if (prefix) @as(usize, 0) else 4)) {
                try t.expect(!a.hasRecordSignature() and b.hasRecordSignature());
            } else try t.expect(!a.hasRecordSignature() and !b.hasRecordSignature());
        }
        for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
            const a = try amd64.emitWithOptions(t.allocator, &module, options);
            defer t.allocator.free(a);
            const b = try amd64.emitWithOptions(t.allocator, &reference, options);
            defer t.allocator.free(b);
            for ([_][]const u8{ "common_address", "ordinary_address", "external_address", "T" }) |symbol| try t.expectEqualSlices(u8, fragment(a, symbol), fragment(b, symbol));
        }
    }
}

test "aggregate_abi_variadic raw register save ordering precedes private object unpack" {
    var module = try parse(t.allocator, "type :T={s 3}\nfunction :T $f(:T %p,...){\n@e\n%list =l alloc8 24\nvastart %list\nret %p\n}");
    defer module.deinit();
    const output = try amd64.emit(t.allocator, &module);
    defer t.allocator.free(output);
    // An ordering assertion, not a claimed value-oracle mutation: named-argument
    // unpack can leave every eligible tail register intact. A separate executed
    // mutation delays saving until a real ABI-legal caller clobber and fails.
    const last_sse_save = std.mem.indexOf(u8, output, "movdqu %xmm7,").?;
    const first_object_address = std.mem.indexOf(u8, output, "leaq -").?;
    try t.expect(last_sse_save < first_object_address);
}
