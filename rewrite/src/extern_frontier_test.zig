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

// Multiple initialized call signatures and multiple initialized FunctionPlans
// must be destroyed when a later allocation fails. The middle scalar function
// also checks that ModulePlans preserves a null entry between owned plans.
const multi_plan_source =
    \\type :R={l, d}
    \\type :M={b 23}
    \\function :R $register_caller(:R %p) {
    \\@e
    \\%a =:R call extern $reg_first(:R extern $reg_data)
    \\%b =:R call extern $reg_second(:R %a)
    \\ret %b
    \\}
    \\function l $scalar_caller() {
    \\@e
    \\%n =l add 1, 2
    \\%v =l call extern $scalar_target(l %n)
    \\ret %v
    \\}
    \\function :M $memory_caller(:M %p) {
    \\@e
    \\%a =:M call extern $mem_first(:M extern $mem_data)
    \\%b =:M call extern $mem_second(:M %a)
    \\ret %b
    \\}
;

const MultiMode = enum { detached_register, detached_memory, whole, emit };

// Save identities before folding, then check the actual target representations
// and operands both before and after folding rather than comparing a plan only
// with whatever IR happens to survive.
fn checkMultiIr(module: *const Module, targets: [2][2]SymbolId, data: [2]SymbolId, scalar_target: SymbolId, fold: bool) !void {
    for ([_]usize{ 0, 2 }, 0..) |index, family| {
        const instructions = module.functions.items[index].blocks.items[0].instructions.items;
        try t.expectEqual(@as(usize, 2), instructions.len);
        for (instructions, 0..) |instruction, i| {
            try t.expect(instruction == .call);
            const call = instruction.call;
            try checkTarget(call.callee, i == 1, targets[family][i]);
            try t.expect(call.result != null);
            try t.expectEqual(@as(u32, @intCast(i + 1)), @backingInt(call.result.?));
            try t.expectEqual(@as(usize, 1), call.arguments.len);
            if (i == 0) {
                try t.expect(call.arguments[0].operand == .got_symbol);
                try t.expectEqual(data[family], call.arguments[0].operand.got_symbol);
            } else {
                try t.expect(call.arguments[0].operand == .value);
                try t.expectEqual(@as(u32, 1), @backingInt(call.arguments[0].operand.value));
            }
        }
    }
    const scalar = module.functions.items[1].blocks.items[0].instructions.items;
    try t.expectEqual(@as(usize, 2), scalar.len);
    if (fold) {
        try t.expect(scalar[0] == .copy);
        try t.expectEqual(@as(u32, 0), @backingInt(scalar[0].copy.result));
        try t.expect(scalar[0].copy.operand == .constant);
        try t.expect(scalar[0].copy.operand.constant == .long);
        try t.expectEqual(@as(u64, 3), scalar[0].copy.operand.constant.long);
    } else {
        try t.expect(scalar[0] == .binary);
        try t.expectEqual(ir.BinaryOp.add, scalar[0].binary.op);
        try t.expectEqual(@as(u32, 0), @backingInt(scalar[0].binary.result));
    }
    try t.expect(scalar[1] == .call);
    const call = scalar[1].call;
    try checkTarget(call.callee, false, scalar_target);
    try t.expect(call.result != null);
    try t.expectEqual(@as(u32, 1), @backingInt(call.result.?));
    try t.expectEqual(@as(usize, 1), call.arguments.len);
    try t.expect(call.arguments[0].operand == .value);
    try t.expectEqual(@as(u32, 0), @backingInt(call.arguments[0].operand.value));
}

fn checkMultiPlan(plan: *const planner.FunctionPlan, module: *const Module, index: usize) !void {
    const function = module.functions.items[index];
    const expected_record: @import("record_declaration.zig").Id = @fromBackingInt(@as(u32, if (index == 0) 0 else 1));
    try t.expectEqual(@as(u32, @intCast(index)), @backingInt(plan.function_id));
    try t.expectEqual(@as(usize, 2), plan.calls.len);
    try t.expectEqual(@as(usize, 2), plan.pads.len);
    try t.expectEqual(@as(usize, if (index == 0) 1 else 0), plan.parameter_objects.len);
    for (plan.calls, 0..) |site, i| {
        try t.expect(function.blocks.items[0].instructions.items[i] == .call);
        const call = function.blocks.items[0].instructions.items[i].call;
        try t.expectEqual(i, site.instruction);
        try t.expectEqual(call.result, site.result_value);
        try t.expect(site.result_value != null);
        try t.expectEqual(@as(u32, @intCast(i + 1)), @backingInt(site.result_value.?));
        try checkTarget(site.target, i == 1, call.callee.symbolicIdentity().?);
        const expected_name = if (index == 0)
            (if (i == 0) "reg_first" else "reg_second")
        else
            (if (i == 0) "mem_first" else "mem_second");
        try t.expectEqualStrings(expected_name, module.symbols.get(site.target.symbolicIdentity().?).?);
        try t.expectEqual(@as(?usize, i), site.pad_index);
        try t.expectEqual(i, plan.pads[i].call_index);
        try t.expectEqual(@as(usize, 1), site.signature.arguments.len);
        const arg = site.signature.arguments[0];
        try t.expect(arg.descriptor == .record);
        try t.expectEqual(expected_record, arg.descriptor.record);
        try t.expectEqual(expected_record, plan.pads[i].record_id);
        const maybe_call_result = try call.resultAbi(function);
        try t.expect(maybe_call_result != null);
        const call_result = maybe_call_result.?;
        try t.expect(call_result == .record);
        try t.expectEqual(expected_record, call_result.record);
        if (i == 0) {
            try t.expect(call.arguments[0].operand == .got_symbol);
            try t.expectEqualStrings(if (index == 0) "reg_data" else "mem_data", module.symbols.get(call.arguments[0].operand.got_symbol).?);
        } else {
            try t.expect(call.arguments[0].operand == .value);
            try t.expectEqual(function.blocks.items[0].instructions.items[0].call.result.?, call.arguments[0].operand.value);
        }
        if (index == 0) {
            try t.expect(site.signature.result == .register_record);
            const result = site.signature.result.register_record;
            try t.expectEqual(arg.descriptor.record, result.record_id);
            try t.expectEqual(@as(u64, 16), result.declared_bytes);
            try t.expectEqual(@as(u8, 2), result.lane_count);
            try t.expect(result.lanes[0].register == .general);
            try t.expect(result.lanes[1].register == .vector);
            try t.expectEqual(planner.ResultGeneral.rax, result.lanes[0].register.general);
            try t.expectEqual(planner.ResultVector.xmm0, result.lanes[1].register.vector);
            try t.expectEqual(@as(u8, 0), result.lanes[0].offset);
            try t.expectEqual(@as(u8, 8), result.lanes[1].offset);
            try t.expectEqual(@as(u8, 8), result.lanes[0].bytes);
            try t.expectEqual(@as(u8, 8), result.lanes[1].bytes);
            try t.expect(arg.location == .register_record);
            const lanes = arg.location.register_record;
            try t.expectEqual(@as(u8, 2), lanes.lane_count);
            try t.expect(lanes.lanes[0].register == .general);
            try t.expect(lanes.lanes[1].register == .vector);
            try t.expectEqual(General.rdi, lanes.lanes[0].register.general);
            try t.expectEqual(@import("abi_amd64.zig").Vector.xmm0, lanes.lanes[1].register.vector);
            try t.expectEqual(@as(u8, 0), lanes.lanes[0].offset);
            try t.expectEqual(@as(u8, 8), lanes.lanes[1].offset);
            try t.expectEqual(@as(u8, 8), lanes.lanes[0].bytes);
            try t.expectEqual(@as(u8, 8), lanes.lanes[1].bytes);
            try t.expectEqual(@as(u64, 0), site.signature.stack_bytes);
            try t.expectEqual(@as(u64, 0), site.signature.outgoing_bytes);
            try t.expectEqual(@as(u64, 16), plan.pads[i].declared_bytes);
        } else {
            try t.expect(site.signature.result == .memory and arg.location == .stack);
            try t.expectEqual(arg.descriptor.record, site.signature.result.memory.record_id);
            try t.expectEqual(General.rdi, site.signature.result.memory.hidden);
            try t.expectEqual(@as(u64, 23), site.signature.result.memory.declared_bytes);
            try t.expectEqual(@as(u64, 0), arg.location.stack.offset);
            try t.expectEqual(@as(u64, 24), arg.location.stack.extent);
            try t.expectEqual(@as(u8, 8), arg.location.stack.alignment);
            try t.expectEqual(@as(i32, 16), arg.location.stack.incoming);
            try t.expectEqual(@as(u64, 24), site.signature.stack_bytes);
            try t.expectEqual(@as(u64, 32), site.signature.outgoing_bytes);
            try t.expectEqual(@as(u64, 23), plan.pads[i].declared_bytes);
        }
        try t.expectEqual(@as(u8, 8), plan.pads[i].alignment);
        try t.expectEqual(@as(u64, 0), plan.pads[i].end % 8);
        try t.expect(plan.pads[i].end >= plan.pads[i].declared_bytes);
        try t.expect(plan.pads[i].end <= plan.frame.fixed_prefix_bytes);
    }
    // Coordinates are positive distances below RBP: the second pad starts
    // at end-size, so distinct end coordinates alone do not prove separation.
    try t.expect(plan.pads[0].end <= plan.pads[1].end - plan.pads[1].declared_bytes);
    try t.expect(plan.frame.fixed_prefix_bytes + plan.frame.outgoing_bytes <= plan.frame.bytes);
    try t.expectEqual(@as(u64, if (index == 0) 0 else 32), plan.frame.outgoing_bytes);
    try t.expectEqual(@as(usize, 1), plan.signature.arguments.len);
    try t.expect(plan.signature.arguments[0].descriptor == .record);
    try t.expectEqual(expected_record, plan.signature.arguments[0].descriptor.record);
    if (index == 0) {
        try t.expect(plan.signature.result == .register_record);
        try t.expectEqual(expected_record, plan.signature.result.register_record.record_id);
        try t.expect(plan.signature.arguments[0].location == .register_record);
        try t.expectEqual(@as(usize, 0), plan.parameter_objects[0].position);
        try t.expectEqual(expected_record, plan.parameter_objects[0].record_id);
        try t.expectEqual(@as(u64, 16), plan.parameter_objects[0].declared_bytes);
        try t.expect(plan.parameter_objects[0].end <= plan.pads[0].end - plan.pads[0].declared_bytes);
        try t.expect(plan.frame.hidden_return_end == null);
    } else {
        try t.expect(plan.signature.result == .memory);
        try t.expectEqual(expected_record, plan.signature.result.memory.record_id);
        try t.expect(plan.frame.hidden_return_end != null);
        try t.expect(plan.frame.hidden_return_end.? <= plan.pads[0].end - plan.pads[0].declared_bytes);
    }
}

fn multiTransaction(mode: MultiMode, allocator: std.mem.Allocator, module: *const Module, options: planner.Options, expected: []const u8) !void {
    switch (mode) {
        .detached_register, .detached_memory => {
            const index: usize = if (mode == .detached_register) 0 else 2;
            var plan = try planner.FunctionPlan.init(allocator, module, @fromBackingInt(@as(u32, @intCast(index))), options);
            defer plan.deinit();
            try checkMultiPlan(&plan, module, index);
        },
        .whole => {
            var plans = try planner.ModulePlans.init(allocator, module, options);
            defer plans.deinit();
            try t.expectEqual(@as(usize, 3), plans.functions.len);
            try t.expect(plans.get(1) == null);
            try checkMultiPlan(plans.get(0).?, module, 0);
            try checkMultiPlan(plans.get(2).?, module, 2);
        },
        .emit => {
            const text = try amd64.emitWithOptions(allocator, module, .{ .reuse_stack_homes = options.reuse_stack_homes, .callee_saved_homes = options.callee_saved_homes });
            defer allocator.free(text);
            // Same-emitter equality is a retry/ownership oracle, not ABI proof.
            try t.expectEqualStrings(expected, text);
            for ([_][]const u8{
                "\tmovq reg_first@GOTPCREL(%rip), %rax\n\tmovq %rax, %r11\n\tcall *%r11\n",
                "\tmovq reg_second@GOTPCREL(%rip), %rax\n\tmovq %rax, %r11\n\tcall *%r11\n",
                "\tmovq scalar_target@GOTPCREL(%rip), %rax\n\tmovq %rax, %r11\n\tcall *%r11\n",
                "\tmovq mem_first@GOTPCREL(%rip), %rax\n\tmovq %rax, %r11\n\tcall *%r11\n",
                "\tmovq mem_second@GOTPCREL(%rip), %rax\n\tmovq %rax, %r11\n\tcall *%r11\n",
                "\tmovq reg_data@GOTPCREL(%rip), %rax\n\tmovq %rax, %r11\n",
                "\tmovq mem_data@GOTPCREL(%rip), %rax\n\tmovq %rax, %rsi\n",
            }) |needle| {
                try t.expect(std.mem.indexOf(u8, text, needle) != null);
            }
        },
    }
}

test "extern multi-function multi-call plans retry every moving-allocation OOM" {
    for ([_]bool{ false, true }) |fold| {
        var diagnostic: ?@import("source.zig").Diagnostic = null;
        var module = try frontend.parse(t.allocator, .{ .name = "multi-plan-frontier", .text = multi_plan_source }, &diagnostic);
        defer module.deinit();
        // Exercise both target representations together, before optimization.
        var targets: [2][2]SymbolId = undefined;
        var data: [2]SymbolId = undefined;
        for ([_]usize{ 0, 2 }, 0..) |index, family| {
            const instructions = module.functions.items[index].blocks.items[0].instructions.items;
            try t.expectEqual(@as(usize, 2), instructions.len);
            for (instructions, 0..) |*instruction, i| {
                try t.expect(instruction.* == .call);
                const call = &instruction.call;
                try t.expect(call.callee == .extern_symbol);
                targets[family][i] = call.callee.extern_symbol;
                if (i == 0) {
                    try t.expectEqual(@as(usize, 1), call.arguments.len);
                    try t.expect(call.arguments[0].operand == .got_symbol);
                    data[family] = call.arguments[0].operand.got_symbol;
                } else {
                    call.callee = .{ .address = .{ .got_symbol = targets[family][i] } };
                }
            }
        }
        const scalar_instructions = module.functions.items[1].blocks.items[0].instructions.items;
        try t.expectEqual(@as(usize, 2), scalar_instructions.len);
        try t.expect(scalar_instructions[1] == .call);
        try t.expect(scalar_instructions[1].call.callee == .extern_symbol);
        const scalar_target = scalar_instructions[1].call.callee.extern_symbol;
        try t.expectEqualStrings("scalar_target", module.symbols.get(scalar_target).?);
        try checkMultiIr(&module, targets, data, scalar_target, false);
        if (fold) {
            var folded: usize = 0;
            for (module.functions.items) |function| folded += try @import("optimize.zig").foldIntegerConstants(t.allocator, function);
            try t.expectEqual(@as(usize, 1), folded);
        }
        try checkMultiIr(&module, targets, data, scalar_target, fold);
        for ([_]planner.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
            const expected = try amd64.emitWithOptions(t.allocator, &module, .{ .reuse_stack_homes = options.reuse_stack_homes, .callee_saved_homes = options.callee_saved_homes });
            defer t.allocator.free(expected);
            for ([_]MultiMode{ .detached_register, .detached_memory, .whole, .emit }) |mode| {
                var measure = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
                try multiTransaction(mode, measure.allocator(), &module, options, expected);
                const attempts = measure.alloc_index;
                try t.expect(attempts > 0);
                try t.expectEqual(measure.allocated_bytes, measure.freed_bytes);
                std.debug.print("extern-multi-frontier fold={} reuse={} callee={} mode={s} attempts={d}\n", .{ fold, options.reuse_stack_homes, options.callee_saved_homes, @tagName(mode), attempts });
                for (0..attempts) |ordinal| {
                    var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = ordinal, .resize_fail_index = 0 });
                    try t.expectError(error.OutOfMemory, multiTransaction(mode, failing.allocator(), &module, options, expected));
                    try t.expect(failing.has_induced_failure);
                    try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
                    failing.fail_index = std.math.maxInt(usize);
                    try multiTransaction(mode, failing.allocator(), &module, options, expected);
                    try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
                }
            }
        }
    }
}

// Observe the allocator boundary rather than assuming the last allocation is
// final extraction. With remaps refused, Allocating.toOwnedSlice first attempts
// a shrink remap, then allocates exactly the written length and frees the old
// writer buffer. The address/length trace below verifies that sequence.
const WriterTrace = struct {
    const Kind = enum { alloc, resize, remap, free };
    const Event = struct {
        kind: Kind,
        old_ptr: usize = 0,
        old_len: usize = 0,
        new_len: usize = 0,
        result_ptr: usize = 0,
        alloc_ordinal: usize = 0,
    };
    backing: std.mem.Allocator,
    allow_remap: bool,
    events: [2048]Event = undefined,
    count: usize = 0,
    alloc_attempts: usize = 0,
    fail_ordinal: ?usize = null,
    induced: bool = false,

    fn allocator(self: *WriterTrace) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn push(self: *WriterTrace, event: Event) void {
        // A truncated trace cannot establish the identity of the final slice.
        if (self.count == self.events.len) @panic("writer allocation trace overflow");
        self.events[self.count] = event;
        self.count += 1;
    }
    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *WriterTrace = @ptrCast(@alignCast(ctx));
        const ordinal = self.alloc_attempts;
        self.alloc_attempts += 1;
        const result = if (self.fail_ordinal == ordinal) blk: {
            self.induced = true;
            break :blk null;
        } else self.backing.rawAlloc(len, alignment, ra);
        self.push(.{ .kind = .alloc, .new_len = len, .result_ptr = if (result) |p| @intFromPtr(p) else 0, .alloc_ordinal = ordinal });
        return result;
    }
    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, ra: usize) bool {
        const self: *WriterTrace = @ptrCast(@alignCast(ctx));
        const ok = self.allow_remap and self.backing.rawResize(memory, alignment, len, ra);
        self.push(.{ .kind = .resize, .old_ptr = @intFromPtr(memory.ptr), .old_len = memory.len, .new_len = len, .result_ptr = if (ok) @intFromPtr(memory.ptr) else 0 });
        return ok;
    }
    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, ra: usize) ?[*]u8 {
        const self: *WriterTrace = @ptrCast(@alignCast(ctx));
        const result = if (self.allow_remap) self.backing.rawRemap(memory, alignment, len, ra) else null;
        self.push(.{ .kind = .remap, .old_ptr = @intFromPtr(memory.ptr), .old_len = memory.len, .new_len = len, .result_ptr = if (result) |p| @intFromPtr(p) else 0 });
        return result;
    }
    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self: *WriterTrace = @ptrCast(@alignCast(ctx));
        self.push(.{ .kind = .free, .old_ptr = @intFromPtr(memory.ptr), .old_len = memory.len });
        self.backing.rawFree(memory, alignment, ra);
    }
};

fn findFree(trace: *const WriterTrace, start: usize, ptr: usize, len: usize) bool {
    for (trace.events[start..trace.count]) |event| {
        if (event.kind == .free and event.old_ptr == ptr and event.old_len == len) return true;
    }
    return false;
}

test "extern emission final owned slice OOM cleans writer and retries" {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    var module = try frontend.parse(t.allocator, .{ .name = "final-slice", .text = success_scalar }, &diagnostic);
    defer module.deinit();

    // The accounting allocator is also backed by testing.allocator's leak check.
    var accounting = t.FailingAllocator.init(t.allocator, .{});
    var baseline: WriterTrace = .{ .backing = accounting.allocator(), .allow_remap = false };
    {
        const expected = try amd64.emit(baseline.allocator(), &module);
        defer baseline.allocator().free(expected);
        try t.expect(expected.len > 0);
        const owned_ptr = @intFromPtr(expected.ptr);
        var extraction: ?usize = null;
        for (baseline.events[0..baseline.count], 0..) |event, i| {
            if (event.kind == .alloc and event.result_ptr == owned_ptr) extraction = i;
        }
        const i = extraction orelse return error.FinalAllocationNotObserved;
        try t.expect(i > 0);
        const allocation = baseline.events[i];
        const shrink = baseline.events[i - 1];
        try t.expectEqual(WriterTrace.Kind.remap, shrink.kind);
        try t.expectEqual(@as(usize, 0), shrink.result_ptr);
        try t.expect(shrink.old_len > expected.len);
        try t.expectEqual(expected.len, shrink.new_len);
        try t.expectEqual(expected.len, allocation.new_len);
        std.debug.print("\nfinal copy: alloc ordinal {d} of {d}; writer capacity {d}, output {d} bytes\n", .{ allocation.alloc_ordinal, baseline.alloc_attempts, shrink.old_len, expected.len });
        try t.expect(findFree(&baseline, i + 1, shrink.old_ptr, shrink.old_len));
        try t.expect(!findFree(&baseline, i + 1, owned_ptr, expected.len));

        // Re-run the identical trace, fail exactly the identified extraction, and
        // prove that the old writer buffer was freed on the error path. The normal
        // success retry uses the same module and same allocator instance.
        var failed_accounting = t.FailingAllocator.init(t.allocator, .{});
        var failed: WriterTrace = .{ .backing = failed_accounting.allocator(), .allow_remap = false, .fail_ordinal = allocation.alloc_ordinal };
        try t.expectError(error.OutOfMemory, amd64.emit(failed.allocator(), &module));
        try t.expect(failed.induced);
        try t.expectEqual(i + 1, blk: {
            for (failed.events[0..failed.count], 0..) |event, j| {
                if (event.kind == .alloc and event.alloc_ordinal == allocation.alloc_ordinal) break :blk j + 1;
            }
            return error.FailedAllocationNotObserved;
        });
        const failed_shrink = failed.events[i - 1];
        try t.expectEqual(WriterTrace.Kind.remap, failed_shrink.kind);
        try t.expectEqual(shrink.old_len, failed_shrink.old_len);
        try t.expectEqual(expected.len, failed_shrink.new_len);
        try t.expectEqual(@as(usize, 0), failed.events[i].result_ptr);
        try t.expectEqual(expected.len, failed.events[i].new_len);
        try t.expect(findFree(&failed, i + 1, failed_shrink.old_ptr, failed_shrink.old_len));
        try t.expectEqual(failed_accounting.allocated_bytes, failed_accounting.freed_bytes);
        failed.fail_ordinal = null;
        {
            const retry = try amd64.emit(failed.allocator(), &module);
            defer failed.allocator().free(retry);
            try t.expectEqualStrings(expected, retry);
        }
        try t.expectEqual(failed_accounting.allocated_bytes, failed_accounting.freed_bytes);
    }
    try t.expectEqual(accounting.allocated_bytes, accounting.freed_bytes);
}

// A bounded test allocator reserves extra backing bytes per allocation, so it
// can truthfully grow and shrink in place while preserving the allocator API's
// logical lengths. Backing blocks are freed at their actual reserved lengths.
const InPlaceAllocator = struct {
    const Slot = struct { ptr: [*]u8, logical: usize, capacity: usize, alignment: std.mem.Alignment };
    backing: std.mem.Allocator,
    slots: [512]?Slot = @splat(null),

    fn allocator(self: *InPlaceAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn slot(self: *InPlaceAllocator, memory: []u8, alignment: std.mem.Alignment) *Slot {
        for (&self.slots) |*entry| {
            if (entry.*) |*s| {
                if (s.ptr == memory.ptr) {
                    if (s.logical != memory.len or s.alignment != alignment) @panic("invalid logical allocation");
                    return s;
                }
            }
        }
        @panic("unknown allocation");
    }
    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *InPlaceAllocator = @ptrCast(@alignCast(ctx));
        const capacity = std.math.add(usize, std.math.mul(usize, len, 2) catch return null, 1024) catch return null;
        for (&self.slots) |*entry| if (entry.* == null) {
            const ptr = self.backing.rawAlloc(capacity, alignment, ra) orelse return null;
            entry.* = .{ .ptr = ptr, .logical = len, .capacity = capacity, .alignment = alignment };
            return ptr;
        };
        @panic("in-place allocator slots exhausted");
    }
    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, _: usize) bool {
        const self: *InPlaceAllocator = @ptrCast(@alignCast(ctx));
        const s = self.slot(memory, alignment);
        if (len > s.capacity) return false;
        s.logical = len;
        return true;
    }
    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, ra: usize) ?[*]u8 {
        if (!resize(ctx, memory, alignment, len, ra)) return null;
        return memory.ptr;
    }
    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self: *InPlaceAllocator = @ptrCast(@alignCast(ctx));
        const s = self.slot(memory, alignment);
        const ptr = s.ptr;
        const capacity = s.capacity;
        for (&self.slots) |*entry| {
            if (entry.*) |v| if (v.ptr == ptr) {
                entry.* = null;
                self.backing.rawFree(ptr[0..capacity], alignment, ra);
                return;
            };
        }
        unreachable;
    }
};

test "extern emission in-place final remap and allocation failures retry" {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    var module = try frontend.parse(t.allocator, .{ .name = "in-place-final", .text = success_scalar }, &diagnostic);
    defer module.deinit();
    var accounting = t.FailingAllocator.init(t.allocator, .{});
    var in_place: InPlaceAllocator = .{ .backing = accounting.allocator() };
    var baseline: WriterTrace = .{ .backing = in_place.allocator(), .allow_remap = true };
    {
        const expected = try amd64.emit(baseline.allocator(), &module);
        defer baseline.allocator().free(expected);
        const owned_ptr = @intFromPtr(expected.ptr);
        var final_remap: ?usize = null;
        for (baseline.events[0..baseline.count], 0..) |event, i| {
            if (event.kind == .remap and event.result_ptr == owned_ptr and event.new_len == expected.len) final_remap = i;
        }
        const i = final_remap orelse return error.FinalRemapNotObserved;
        const event = baseline.events[i];
        try t.expectEqual(owned_ptr, event.old_ptr);
        try t.expect(event.old_len > event.new_len);
        try t.expect(!findFree(&baseline, i + 1, owned_ptr, expected.len));
        var saw_growth = false;
        for (baseline.events[0..i]) |prior| {
            if ((prior.kind == .remap or prior.kind == .resize) and prior.result_ptr == prior.old_ptr and prior.new_len > prior.old_len) saw_growth = true;
        }
        try t.expect(saw_growth);
        const attempts = baseline.alloc_attempts;
        try t.expect(attempts > 0);
        std.debug.print("\nin-place final shrink: {d} to {d} bytes; {d} allocation ordinals\n", .{ event.old_len, event.new_len, attempts });
        for (0..attempts) |ordinal| {
            var failed_accounting = t.FailingAllocator.init(t.allocator, .{});
            var failed_in_place: InPlaceAllocator = .{ .backing = failed_accounting.allocator() };
            var trace: WriterTrace = .{ .backing = failed_in_place.allocator(), .allow_remap = true, .fail_ordinal = ordinal };
            try t.expectError(error.OutOfMemory, amd64.emit(trace.allocator(), &module));
            try t.expect(trace.induced);
            try t.expectEqual(failed_accounting.allocated_bytes, failed_accounting.freed_bytes);
            trace.fail_ordinal = null;
            trace.count = 0;
            {
                const retry = try amd64.emit(trace.allocator(), &module);
                defer trace.allocator().free(retry);
                try t.expectEqualStrings(expected, retry);
            }
            try t.expectEqual(failed_accounting.allocated_bytes, failed_accounting.freed_bytes);
        }
    }
    try t.expectEqual(accounting.allocated_bytes, accounting.freed_bytes);
}
