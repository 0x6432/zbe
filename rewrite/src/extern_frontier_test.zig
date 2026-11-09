//! Narrow allocation-frontier witnesses for extern name refusal.
const std = @import("std");
const t = std.testing;
const ir = @import("ir.zig");
const frontend = @import("frontend.zig");
const validation = @import("module_validation.zig");
const planner = @import("abi_amd64_plan.zig");
const amd64 = @import("amd64.zig");
const Module = @import("module.zig").Module;
const Mode = enum { whole, detached, emit };

fn run(mode: Mode, allocator: std.mem.Allocator, module: *const Module) !void {
    switch (mode) {
        .whole => {
            var p = try planner.ModulePlans.init(allocator, module, .{});
            defer p.deinit();
        },
        .detached => {
            var p = try planner.FunctionPlan.init(allocator, module, @fromBackingInt(@as(u32, 0)), .{});
            defer p.deinit();
        },
        .emit => {
            const text = try amd64.emit(allocator, module);
            defer allocator.free(text);
        },
    }
}

test "extern_frontier refuses before post-validation allocations and retries same module" {
    const inputs = [_][]const u8{
        "function l $f() {\n@e\nret extern $.bad\n}",
        "type :R={l 2}\nfunction l $f(:R %p) {\n@e\nret extern $.bad\n}",
        "function l $f() {\n@e\nret 0\n@dead\nret extern $.bad\n}",
        "function l $f() {\n@e\n%r =l call extern $.bad()\nret %r\n}",
    };
    for (inputs, 0..) |text, case_index| {
        var diagnostic: ?@import("source.zig").Diagnostic = null;
        var module = try frontend.parse(t.allocator, .{ .name = "frontier", .text = text }, &diagnostic);
        defer module.deinit();
        const forms: usize = if (case_index == 3) 2 else 1;
        for (0..forms) |form| {
            if (form == 1) {
                const call = &module.functions.items[0].blocks.items[0].instructions.items[0].call;
                const symbol = call.callee.extern_symbol;
                call.callee = .{ .address = .{ .got_symbol = symbol } };
            }
            var measure = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
            try validation.validate(measure.allocator(), &module);
            const generic_allocs = measure.alloc_index;
            try t.expectEqual(measure.allocated_bytes, measure.freed_bytes);
            for ([_]Mode{ .whole, .detached, .emit }) |mode| {
                // Fail each generic validation allocation and the very next
                // allocation. The last must remain untouched on name refusal.
                for (0..generic_allocs + 1) |ordinal| {
                    var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = ordinal, .resize_fail_index = 0 });
                    if (ordinal < generic_allocs) {
                        try t.expectError(error.OutOfMemory, run(mode, failing.allocator(), &module));
                        try t.expect(failing.has_induced_failure);
                    } else {
                        try t.expectError(error.UnsupportedExternSymbol, run(mode, failing.allocator(), &module));
                        try t.expect(!failing.has_induced_failure);
                        try t.expectEqual(generic_allocs, failing.alloc_index);
                    }
                    try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
                    // Same surviving module must give the normal refusal after
                    // any injected failure, without leaking partial state.
                    failing.fail_index = std.math.maxInt(usize);
                    try t.expectError(error.UnsupportedExternSymbol, run(mode, failing.allocator(), &module));
                    try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
                }
            }
        }
    }
}

// These are focused witnesses, not the full O01–O10 ledger. Ordinals are
// zero-based allocation attempts within each measured transaction. In-place
// resize is disabled; successful reservations may remain after a failed attempt.
fn poolRetry(allocator: std.mem.Allocator, ordinal: ?usize) !usize {
    var failing = t.FailingAllocator.init(allocator, .{ .resize_fail_index = 0 });
    var module = Module.init(failing.allocator());
    defer module.deinit();
    const first = try module.symbols.intern("first");
    const stable = module.symbols.get(first).?;
    var buffer: [32]u8 = undefined;
    while (module.symbols.names.items.len < module.symbols.names.capacity) {
        const name = try std.fmt.bufPrint(&buffer, "filler{d}", .{module.symbols.names.items.len});
        _ = try module.symbols.intern(name);
    }
    const count = module.symbols.names.items.len;
    const start = failing.alloc_index;
    if (ordinal) |n| failing.fail_index = start + n;
    var spelling = "external_target".*;
    const id = if (ordinal != null) blk: {
        try t.expectError(error.OutOfMemory, module.symbols.intern(&spelling));
        try t.expect(failing.has_induced_failure);
        try t.expectEqual(count, module.symbols.names.items.len);
        try t.expect(module.symbols.index.get(&spelling) == null);
        try t.expect(module.symbols.get(@fromBackingInt(@as(u32, @intCast(count)))) == null);
        try t.expectEqualStrings("first", module.symbols.get(first).?);
        try t.expectEqual(@intFromPtr(stable.ptr), @intFromPtr(module.symbols.get(first).?.ptr));
        failing.fail_index = std.math.maxInt(usize);
        break :blk try module.symbols.intern(&spelling);
    } else try module.symbols.intern(&spelling);
    const attempts = failing.alloc_index - start;
    try t.expectEqual(count, @as(usize, @intCast(@backingInt(id))));
    @memset(&spelling, 'x');
    try t.expectEqualStrings("external_target", module.symbols.get(id).?);
    const before_alias = failing.alloc_index;
    try t.expectEqual(id, try module.symbols.intern("external_target"));
    try t.expectEqual(before_alias, failing.alloc_index);
    try t.expectEqual(@intFromPtr(stable.ptr), @intFromPtr(module.symbols.get(first).?.ptr));
    return attempts;
}

fn callRetry(allocator: std.mem.Allocator, ordinal: ?usize, wrapped: bool) !usize {
    var failing = t.FailingAllocator.init(allocator, .{ .resize_fail_index = 0 });
    var module = Module.init(failing.allocator());
    defer module.deinit();
    const target = try module.symbols.intern("external_target");
    const argument = try module.symbols.intern("external_argument");
    const environment = try module.symbols.intern("external_environment");
    const function_id = try module.addFunction("caller", .long);
    const f = module.getFunction(function_id).?;
    const block = try f.addBlock(null);
    const result = try f.declareValue(.long);
    const callee: ir.CallTarget = if (wrapped) .{ .address = .{ .got_symbol = target } } else .{ .extern_symbol = target };
    var args = [_]ir.CallArgument{.{ .scalar_type = .long, .operand = .{ .got_symbol = argument } }};
    const options: ir.CallOptions = .{ .environment = .{ .got_symbol = environment } };
    const start = failing.alloc_index;
    if (ordinal) |n| {
        failing.fail_index = start + n;
        try t.expectError(error.OutOfMemory, f.appendCall(block, result, callee, &args, options));
        try t.expect(failing.has_induced_failure);
        try t.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
        try t.expect(f.values.items[@backingInt(result)].definition == .pending);
        failing.fail_index = std.math.maxInt(usize);
    }
    try f.appendCall(block, result, callee, &args, options);
    const attempts = failing.alloc_index - start;
    args[0].operand = .{ .constant = .{ .long = 99 } };
    const call = f.blocks.items[0].instructions.items[0].call;
    try t.expectEqual(target, call.callee.symbolicIdentity().?);
    try t.expectEqual(argument, call.arguments[0].operand.got_symbol);
    try t.expectEqual(environment, call.environment.?.got_symbol);
    const backlink = f.values.items[@backingInt(result)].definition.instruction;
    try t.expectEqual(block, backlink.block);
    try t.expectEqual(@as(usize, 0), backlink.index);
    try f.terminate(block, .{ .return_value = .{ .value = result } });
    try validation.validate(allocator, &module);
    return attempts;
}

test "extern pool and both call builders retry the same owner after OOM" {
    var tracked = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    const pool_attempts = try poolRetry(tracked.allocator(), null);
    try t.expect(pool_attempts > 0);
    for (0..pool_attempts) |ordinal| _ = try poolRetry(tracked.allocator(), ordinal);
    for ([_]bool{ false, true }) |wrapped| {
        const call_attempts = try callRetry(tracked.allocator(), null, wrapped);
        try t.expect(call_attempts > 0);
        for (0..call_attempts) |ordinal| _ = try callRetry(tracked.allocator(), ordinal, wrapped);
    }
    try t.expectEqual(tracked.allocated_bytes, tracked.freed_bytes);
}

test "successful extern emission retries same module after every measured OOM" {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    var module = try frontend.parse(t.allocator, .{ .name = "emit-retry", .text = "function l $f() {\n@e\n%p =l copy extern $target\n%r =l call extern $callee(l %p)\nret %r\n}" }, &diagnostic);
    defer module.deinit();
    var measure = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    const baseline = try amd64.emit(measure.allocator(), &module);
    try t.expect(std.mem.indexOf(u8, baseline, "target@GOTPCREL") != null);
    try t.expect(std.mem.indexOf(u8, baseline, "callee@GOTPCREL") != null);
    defer measure.allocator().free(baseline);
    const attempts = measure.alloc_index;
    try t.expect(attempts > 0);
    for (0..attempts) |ordinal| {
        var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = ordinal, .resize_fail_index = 0 });
        try t.expectError(error.OutOfMemory, amd64.emit(failing.allocator(), &module));
        try t.expect(failing.has_induced_failure);
        try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        failing.fail_index = std.math.maxInt(usize);
        const text = try amd64.emit(failing.allocator(), &module);
        try t.expectEqualStrings(baseline, text);
        failing.allocator().free(text);
        try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
}

// Focused O06/O07/O08 witnesses, not the complete acceptance ledger. Each
// zero-based ordinal is measured on a successful fresh transaction with moving
// allocations (in-place resize/remap disabled). A failed transaction must be
// induced, clean up completely, and permit retry on the same immutable module.
const success_scalar =
    \\function l $f(l %v) {
    \\@e
    \\%n =l add 1, 2
    \\%r =l call extern $external_fn(l extern $external_data, l %v, l %n)
    \\ret %r
    \\}
;
const success_record =
    \\type :R={b 23}
    \\function :R $f(:R %p) {
    \\@e
    \\%n =l add 1, 2
    \\%r =:R call extern $external_fn(:R extern $external_data, :R %p, l %n)
    \\ret %r
    \\}
;

const SymbolId = @import("symbols.zig").Id;
const General = @import("abi_amd64.zig").General;

fn checkTarget(target: ir.CallTarget, wrapped: bool, symbol: SymbolId) !void {
    if (wrapped) {
        try t.expect(target == .address);
        try t.expect(target.address == .got_symbol);
        try t.expectEqual(symbol, target.address.got_symbol);
    } else {
        try t.expect(target == .extern_symbol);
        try t.expectEqual(symbol, target.extern_symbol);
    }
    try t.expectEqual(symbol, target.symbolicIdentity().?);
}

fn checkPlan(plan: *const planner.FunctionPlan, module: *const Module, wrapped: bool, symbol: SymbolId, record: bool) !void {
    try t.expectEqual(@as(usize, 1), plan.calls.len);
    const site = plan.calls[0];
    try checkTarget(site.target, wrapped, symbol);
    try t.expectEqual(@as(usize, 1), site.instruction);
    const call = module.functions.items[0].blocks.items[0].instructions.items[1].call;
    try t.expectEqual(call.result, site.result_value);
    try t.expectEqual(@as(usize, 3), site.signature.arguments.len);
    try t.expect(!site.signature.environment and !site.signature.variadic);
    try t.expectEqual(@as(u8, 0), site.signature.vector_used);
    if (record) {
        const record_id = (try call.arguments[0].abi()).record;
        try t.expect(site.signature.result == .memory);
        try t.expectEqual(record_id, site.signature.result.memory.record_id);
        try t.expectEqual(@as(u64, 23), site.signature.result.memory.declared_bytes);
        try t.expectEqual(General.rdi, site.signature.result.memory.hidden);
        try t.expectEqual(@as(usize, 1), plan.pads.len);
        try t.expectEqual(@as(?usize, 0), site.pad_index);
        try t.expectEqual(record_id, plan.pads[0].record_id);
        try t.expectEqual(@as(u64, 23), plan.pads[0].declared_bytes);
        for (site.signature.arguments[0..2], 0..) |arg, index| {
            try t.expect(arg.descriptor == .record and arg.location == .stack);
            try t.expectEqual(record_id, arg.descriptor.record);
            try t.expectEqual(@as(u64, 23), arg.declared_bytes);
            try t.expectEqual(@as(u64, @intCast(index * 24)), arg.location.stack.offset);
            try t.expectEqual(@as(u64, 24), arg.location.stack.extent);
        }
        try t.expectEqual(@as(u64, 48), site.signature.stack_bytes);
        try t.expectEqual(@as(u64, 48), site.signature.outgoing_bytes);
        try t.expectEqual(@as(u8, 2), site.signature.general_used);
        try t.expect(site.signature.arguments[2].location == .general);
        try t.expectEqual(General.rsi, site.signature.arguments[2].location.general);
    } else {
        try t.expect(site.signature.result == .scalar);
        try t.expectEqual(ir.AbiType.long, site.signature.result.scalar);
        try t.expectEqual(@as(usize, 0), plan.pads.len);
        try t.expect(site.pad_index == null);
        try t.expectEqual(@as(u8, 3), site.signature.general_used);
        try t.expectEqual(@as(u64, 0), site.signature.stack_bytes);
        for (site.signature.arguments, [_]General{ .rdi, .rsi, .rdx }) |arg, reg| {
            try t.expect(arg.descriptor == .scalar and arg.location == .general);
            try t.expectEqual(ir.AbiType.long, arg.descriptor.scalar);
            try t.expectEqual(reg, arg.location.general);
        }
    }
}

fn successfulTransaction(mode: Mode, allocator: std.mem.Allocator, module: *const Module, options: planner.Options, record: bool, wrapped: bool, symbol: SymbolId, expected: []const u8) !void {
    switch (mode) {
        .detached => {
            var plan = try planner.FunctionPlan.init(allocator, module, @fromBackingInt(@as(u32, 0)), options);
            defer plan.deinit();
            try checkPlan(&plan, module, wrapped, symbol, record);
        },
        .whole => {
            var plans = try planner.ModulePlans.init(allocator, module, options);
            defer plans.deinit();
            if (record) {
                try t.expectEqual(@as(usize, 1), plans.functions.len);
                try checkPlan(plans.get(0).?, module, wrapped, symbol, record);
            } else {
                try t.expectEqual(@as(usize, 0), plans.functions.len);
                try t.expect(plans.get(0) == null);
            }
        },
        .emit => {
            const text = try amd64.emitWithOptions(allocator, module, .{ .reuse_stack_homes = options.reuse_stack_homes, .callee_saved_homes = options.callee_saved_homes });
            defer allocator.free(text);
            // Equality proves deterministic retry only, not independent ABI correctness.
            try t.expectEqualStrings(expected, text);
            try t.expect(std.mem.indexOf(u8, text, "\tmovq external_data@GOTPCREL(%rip), %rax\n") != null);
            try t.expect(std.mem.indexOf(u8, text, "\tmovq external_fn@GOTPCREL(%rip), %rax\n\tmovq %rax, %r11\n\tcall *%r11\n") != null);
        },
    }
}

test "extern successful planning and emission sweep measured OOM frontiers" {
    for ([_]bool{ false, true }) |record| {
        for ([_]bool{ false, true }) |wrapped| {
            for ([_]bool{ false, true }) |fold| {
                // Fresh module per form: the wrapper must exist before folding.
                var diagnostic: ?@import("source.zig").Diagnostic = null;
                var module = try frontend.parse(t.allocator, .{ .name = "extern-success-frontier", .text = if (record) success_record else success_scalar }, &diagnostic);
                defer module.deinit();
                const before_call = &module.functions.items[0].blocks.items[0].instructions.items[1].call;
                const symbol = before_call.callee.extern_symbol;
                const data = before_call.arguments[0].operand.got_symbol;
                try t.expectEqualStrings("external_fn", module.symbols.get(symbol).?);
                try t.expectEqualStrings("external_data", module.symbols.get(data).?);
                before_call.callee = if (wrapped) .{ .address = .{ .got_symbol = symbol } } else .{ .extern_symbol = symbol };
                try checkTarget(before_call.callee, wrapped, symbol);
                if (fold) try t.expectEqual(@as(usize, 1), try @import("optimize.zig").foldIntegerConstants(t.allocator, module.functions.items[0]));
                const instructions = module.functions.items[0].blocks.items[0].instructions.items;
                if (fold) {
                    try t.expect(instructions[0] == .copy and instructions[0].copy.operand == .constant);
                    try t.expectEqual(@as(u64, 3), instructions[0].copy.operand.constant.long);
                } else try t.expect(instructions[0] == .binary);
                try checkTarget(instructions[1].call.callee, wrapped, symbol);
                try t.expect(instructions[1].call.arguments[0].operand == .got_symbol);
                try t.expectEqual(data, instructions[1].call.arguments[0].operand.got_symbol);
                for ([_]planner.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
                    const expected = try amd64.emitWithOptions(t.allocator, &module, .{ .reuse_stack_homes = options.reuse_stack_homes, .callee_saved_homes = options.callee_saved_homes });
                    defer t.allocator.free(expected);
                    for ([_]Mode{ .detached, .whole, .emit }) |mode| {
                        var measure = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
                        try successfulTransaction(mode, measure.allocator(), &module, options, record, wrapped, symbol, expected);
                        const attempts = measure.alloc_index;
                        try t.expect(attempts > 0);
                        try t.expectEqual(measure.allocated_bytes, measure.freed_bytes);
                        std.debug.print("extern-frontier record={} fold={} wrapped={} reuse={} callee={} mode={s} attempts={d}\n", .{ record, fold, wrapped, options.reuse_stack_homes, options.callee_saved_homes, @tagName(mode), attempts });
                        for (0..attempts) |ordinal| {
                            var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = ordinal, .resize_fail_index = 0 });
                            try t.expectError(error.OutOfMemory, successfulTransaction(mode, failing.allocator(), &module, options, record, wrapped, symbol, expected));
                            try t.expect(failing.has_induced_failure);
                            try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
                            failing.fail_index = std.math.maxInt(usize);
                            try successfulTransaction(mode, failing.allocator(), &module, options, record, wrapped, symbol, expected);
                            try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
                        }
                    }
                }
            }
        }
    }
}

// O01 witness: each parse starts from scratch; there is no partial-module
// resume contract. The aliases force both quoted decoding and interning.
const parse_aliases =
    \\function l $f() {
    \\@e
    \\%old =l copy $external_data
    \\%new =l copy extern $"\x65xternal_data"
    \\%r =l call extern $"\x65xternal_fn"(l %new)
    \\ret %r
    \\}
;

fn parseAliasTransaction(allocator: std.mem.Allocator) !void {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "extern-parse-frontier", .text = parse_aliases }, &diagnostic);
    defer module.deinit();
    const instructions = module.functions.items[0].blocks.items[0].instructions.items;
    const ordinary = instructions[0].copy.operand.symbol;
    const got = instructions[1].copy.operand.got_symbol;
    try t.expectEqual(ordinary, got);
    try t.expectEqualStrings("external_data", module.symbols.get(got).?);
    try t.expectEqualStrings("external_fn", module.symbols.get(instructions[2].call.callee.extern_symbol).?);
}

test "extern quoted parse sweeps measured allocation failures from fresh state" {
    var measure = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try parseAliasTransaction(measure.allocator());
    const attempts = measure.alloc_index;
    try t.expect(attempts > 0);
    try t.expectEqual(measure.allocated_bytes, measure.freed_bytes);
    std.debug.print("extern-parse-frontier attempts={d}\n", .{attempts});
    for (0..attempts) |ordinal| {
        var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = ordinal, .resize_fail_index = 0 });
        try t.expectError(error.OutOfMemory, parseAliasTransaction(failing.allocator()));
        try t.expect(failing.has_induced_failure);
        try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        // A fresh parse, not continuation of a destroyed partial module.
        failing.fail_index = std.math.maxInt(usize);
        try parseAliasTransaction(failing.allocator());
        try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
}
