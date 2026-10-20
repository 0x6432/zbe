const std = @import("std");
const t = std.testing;
const planner = @import("abi_amd64_plan.zig");
const ir = @import("ir.zig");
const abi = @import("abi_amd64.zig");
const Module = @import("module.zig").Module;
const frontend = @import("frontend.zig");
const amd64 = @import("amd64.zig");
const interpreter = @import("interpreter.zig");
fn id(n: u32) @import("module.zig").FunctionId {
    return @fromBackingInt(n);
}
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "aggregate_abi_planner", .text = text }, &diagnostic);
}
const mixed =
    \\type :A = { b 17 }
    \\type :B = align 16 { l 3 }
    \\function :A $f(l %p0,l %p1,l %p2,l %p3,l %p4,l %p5,:A %a,:B %b,d %d0,d %d1,d %d2,d %d3,d %d4,d %d5,d %d6,d %d7,d %d8) {
    \\@e
    \\%r =:A call $external(l 0,l 0,l 0,l 0,l 0,l 0,:A 0,:B 0,d d_0,d d_0,d d_0,d d_0,d d_0,d d_0,d d_0,d d_0,d d_0)
    \\ret %r
    \\}
;
fn stack(arg: planner.Argument, offset: u64, extent: u64, incoming: i32, payload: u64, alignment: u8) !void {
    try t.expect(arg.location == .stack);
    try t.expectEqual(offset, arg.location.stack.offset);
    try t.expectEqual(extent, arg.location.stack.extent);
    try t.expectEqual(incoming, arg.location.stack.incoming);
    try t.expectEqual(payload, arg.declared_bytes);
    try t.expectEqual(alignment, arg.location.stack.alignment);
}
fn mixedOracle(s: planner.Signature) !void {
    // Independent literal table, NOT calculated with production cursor/helpers.
    const gp = [_]abi.General{ .rsi, .rdx, .rcx, .r8, .r9 };
    const fp = [_]abi.Vector{ .xmm0, .xmm1, .xmm2, .xmm3, .xmm4, .xmm5, .xmm6, .xmm7 };
    try t.expect(s.result == .memory);
    try t.expectEqual(abi.General.rdi, s.result.memory.hidden);
    try t.expect(s.result.memory.returned == .rax);
    try t.expectEqual(@as(u64, 17), s.result.memory.declared_bytes);
    for (gp, s.arguments[0..5]) |reg, arg| try t.expectEqual(reg, arg.location.general);
    try stack(s.arguments[5], 0, 8, 16, 8, 8);
    try stack(s.arguments[6], 8, 24, 24, 17, 8);
    try stack(s.arguments[7], 32, 32, 48, 32, 16);
    for (fp, s.arguments[8..16]) |reg, arg| try t.expectEqual(reg, arg.location.vector);
    try stack(s.arguments[16], 64, 8, 80, 8, 8);
    try t.expectEqual(@as(u8, 6), s.general_used);
    try t.expectEqual(@as(u8, 8), s.vector_used);
    try t.expectEqual(@as(u64, 80), s.outgoing_bytes);
}
test "aggregate_abi_planner independent mixed MEMORY hidden GP and SSE offset oracle" {
    var module = try parse(t.allocator, mixed);
    defer module.deinit();
    var plan = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
    defer plan.deinit();
    try mixedOracle(plan.signature);
    try mixedOracle(plan.calls[0].signature);
    try t.expectEqual(@as(u64, 80), plan.frame.outgoing_bytes);
    try t.expectEqual(@as(usize, 1), plan.pads.len);
    // This approved eligible case now lowers natively; independent C/assembly
    // endpoint fixtures verify runtime ABI correctness, not just emission.
    const assembly = try amd64.emit(t.allocator, &module);
    defer t.allocator.free(assembly);
    try t.expect(std.mem.indexOf(u8, assembly, "rep movsb") != null);
    try t.expect(std.mem.indexOf(u8, assembly, "movq %rdi, -") != null);
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluateModule(t.allocator, &module, id(0), &.{}, .{}));
    // Remove only the record result: six GP args stay in registers, A starts0,
    // B still starts32 (hole24..31), overflow double remains64.
    const text = try std.mem.replaceOwned(u8, t.allocator, mixed, "function :A $f", "function l $f");
    defer t.allocator.free(text);
    var scalar_result = try parse(t.allocator, text);
    defer scalar_result.deinit();
    var other = try planner.FunctionPlan.init(t.allocator, &scalar_result, id(0), .{});
    defer other.deinit();
    try t.expectEqual(abi.General.rdi, other.signature.arguments[0].location.general);
    try t.expectEqual(abi.General.r9, other.signature.arguments[5].location.general);
    try stack(other.signature.arguments[6], 0, 24, 16, 17, 8);
    try stack(other.signature.arguments[7], 32, 32, 48, 32, 16);
    try stack(other.signature.arguments[16], 64, 8, 80, 8, 8);
    try t.expect(other.frame.hidden_return_end == null);
}

test "aggregate_abi_planner distinct syntactic pads fixed geometry and owned detached lifetime" {
    const source = try t.allocator.dupe(u8, "type :A={b 17}\ntype :B=align 16 {l 3}\nfunction :A $f(){\n@e\n%a =:A call $one()\n%b =:B call $two()\nret %a\n}");
    var module = parse(t.allocator, source) catch |err| {
        t.allocator.free(source);
        return err;
    };
    @memset(source, 0xa5);
    t.allocator.free(source);
    var plan = planner.FunctionPlan.init(t.allocator, &module, id(0), .{}) catch |err| {
        module.deinit();
        return err;
    };
    module.deinit(); // Snapshot owns facts; no borrowed Function/record/name ptrs.
    defer plan.deinit();
    try t.expectEqual(@as(usize, 2), plan.pads.len);
    try t.expectEqual(@as(u64, 24), plan.frame.hidden_return_end.?);
    try t.expectEqual(@as(u64, 48), plan.pads[0].end);
    try t.expectEqual(@as(u64, 80), plan.pads[1].end);
    try t.expectEqual(@as(u64, 80), plan.frame.bytes);
    try t.expectEqual(@as(usize, 0), plan.calls[0].pad_index.?);
    try t.expectEqual(@as(usize, 1), plan.calls[1].pad_index.?);
    try t.expectEqual(@as(u64, 17), plan.pads[0].declared_bytes);
    try t.expectEqual(@as(u64, 32), plan.pads[1].declared_bytes);
}

test "aggregate_abi_planner site local aggregate eligibility retains scalar env vararg indirect sites" {
    for ([_][]const u8{
        "type :A={b 17}\nfunction $f(env %env){\n@e\ncall $direct(:A 0)\nret\n}",
        "type :A={b 17}\nfunction $f(...){\n@e\ncall $direct(:A 0)\nret\n}",
        "type :A={b 17}\nfunction $f(:A %a){\n@e\ncall $scalar(env 0)\ncall $vararg(..., d d_0)\ncall 0()\nret\n}",
    }, 0..) |text, i| {
        var module = try parse(t.allocator, text);
        defer module.deinit();
        var plan = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
        defer plan.deinit();
        if (i == 0) {
            try t.expect(plan.signature.environment);
            try t.expectEqual(@as(u64, 0), plan.signature.outgoing_bytes);
        }
        if (i == 1) {
            try t.expect(plan.signature.variadic);
            try t.expectEqual(@as(u64, 176), plan.frame.variadic_save_end.?);
        }
        if (i == 2) {
            try t.expect(plan.calls[0].signature.environment);
            try t.expect(plan.calls[1].signature.variadic);
            try t.expectEqual(@as(u8, 1), plan.calls[1].signature.vector_used);
            try t.expect(plan.calls[2].target == .address);
        }
    }
    for ([_][]const u8{
        "function $f(env %e,:A %a){\n@e\nret\n}",
        "function :A $f(...){\n@e\nret 0\n}",
        "function $f(){\n@e\ncall $ext(env 0,:A 0)\nret\n}",
        "function $f(){\n@e\ncall $ext(...,:A 0)\nret\n}",
        "function $f(){\n@e\ncall 0(:A 0)\nret\n}",
    }) |body| {
        const text = try std.mem.concat(t.allocator, u8, &.{ "type :A={b 17}\n", body });
        defer t.allocator.free(text);
        var module = try parse(t.allocator, text);
        defer module.deinit();
        if (std.mem.indexOf(u8, body, "...") != null) {
            try t.expectError(error.UnsupportedAggregatePlan, planner.FunctionPlan.init(t.allocator, &module, id(0), .{}));
        } else {
            var positive = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
            defer positive.deinit();
            if (positive.calls.len == 0) {
                try t.expect(positive.signature.environment);
                try t.expectEqual(@as(u64, 32), positive.signature.outgoing_bytes);
            } else {
                try t.expectEqual(@as(usize, 1), positive.calls.len);
                try t.expectEqual(@as(u64, 32), positive.calls[0].signature.outgoing_bytes);
                try t.expect(positive.calls[0].signature.environment or positive.calls[0].target == .address);
            }
        }
    }
}

test "aggregate_abi_planner scalar payload carrier stack extent and independent register spill table" {
    var module = try parse(t.allocator, "function $f(){\n@e\ncall $outside(l 0,l 0,l 0,l 0,l 0,l 0,sb 1,ub 2,sh 3,uh 4,w 5,l 6,s s_0,s s_0,s s_0,s s_0,s s_0,s s_0,s s_0,s s_0,s s_0,d d_0)\nret\n}");
    defer module.deinit();
    var plan = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
    defer plan.deinit();
    const signature = plan.calls[0].signature;
    const tags = [_]ir.AbiType{ .signed_byte, .unsigned_byte, .signed_half, .unsigned_half, .word, .long };
    const payloads = [_]u64{ 1, 1, 2, 2, 4, 8 };
    const carriers = [_]ir.ScalarType{ .word, .word, .word, .word, .word, .long };
    for (tags, payloads, carriers, 0..) |tag, payload, carrier, i| {
        const arg = signature.arguments[6 + i];
        try t.expectEqual(tag, arg.descriptor.scalar);
        try t.expectEqual(carrier, arg.carrier);
        try stack(arg, @intCast(i * 8), 8, @intCast(16 + i * 8), payload, 8);
    }
    try stack(signature.arguments[20], 48, 8, 64, 4, 8);
    try stack(signature.arguments[21], 56, 8, 72, 8, 8);
    try t.expectEqual(@as(u64, 64), signature.outgoing_bytes);
}

test "aggregate_abi_planner generic metadata limits target policy and module validation precedence" {
    for ([_][]const u8{ "s", "d 2", "b 4097", "b 2147483647" }, 0..) |fields, index| {
        const text = try std.fmt.allocPrint(t.allocator, "type :A={{{s}}}\nfunction $f(:A %p){{\n@e\nret\n}}", .{fields});
        defer t.allocator.free(text);
        var module = try parse(t.allocator, text);
        defer module.deinit();
        try @import("module_validation.zig").validate(t.allocator, &module);
        if (index < 2) {
            // Individually approved SSE4 / SSE8+8 positive upgrades; exact
            // independent classes and reached C/ASM paths are tested separately.
            var plan = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
            defer plan.deinit();
            try t.expect(plan.signature.arguments[0].location == .register_record);
            try t.expectEqual(@as(u8, @intCast(index + 1)), plan.signature.vector_used);
        } else try t.expectError(error.UnsupportedAggregatePlan, planner.FunctionPlan.init(t.allocator, &module, id(0), .{}));
    }
    var unused = try parse(t.allocator, "type :A=align 64 {b 4097}\nfunction $f(){\n@e\nret\n}");
    defer unused.deinit();
    var plan = try planner.FunctionPlan.init(t.allocator, &unused, id(0), .{});
    defer plan.deinit();
    unused.types.items[0].size += 1;
    try t.expectError(error.InvalidRecordLayout, planner.FunctionPlan.init(t.allocator, &unused, id(0), .{}));
    try t.expectError(error.InvalidFunction, planner.FunctionPlan.init(t.allocator, &unused, id(99), .{}));
    // A valid plan snapshot is unchanged but cannot authorize edited metadata.
    try t.expectEqual(@as(u64, 0), plan.frame.bytes);
    var ids = try parse(t.allocator, "type :A={b}\nfunction $f(){\n@e\ncall $ext(:A 0)\nret\n}");
    defer ids.deinit();
    @constCast(ids.functions.items[0].blocks.items[0].instructions.items[0].call.arguments)[0].descriptor = .{ .record = @fromBackingInt(std.math.maxInt(u32)) };
    try t.expectError(error.InvalidAggregateType, planner.FunctionPlan.init(t.allocator, &ids, id(0), .{}));
}

test "aggregate_abi_planner complete eligibility scan wins over huge home geometry and unreachable site" {
    var module = Module.init(t.allocator);
    defer module.deinit();
    const tiny = try module.addRecord("OveralignedFloat", 32, &.{.{ .element = .{ .scalar = .single } }});
    const f_id = try module.addFunction("f", null);
    const f = module.getFunction(f_id).?;
    for (0..8193) |_| _ = try f.addParameter(.long);
    const b = try f.addBlock(null);
    try f.terminate(b, .{ .return_value = null });
    const dead_block = try f.addBlock(null);
    const argument = ir.CallArgument.initDescriptor(.{ .record = tiny }, .{ .constant = .{ .long = 0 } });
    try f.appendCall(dead_block, null, .{ .symbol = try module.symbols.intern("outside") }, &.{argument}, .{});
    try f.terminate(dead_block, .{ .return_value = null });
    for ([_]planner.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true } }) |options| try t.expectError(error.UnsupportedAggregatePlan, planner.FunctionPlan.init(t.allocator, &module, f_id, options));
}

test "aggregate_abi_planner scalar output byte identity all home modes and no module mutation" {
    const text = @embedFile("fixtures/record_declaration_symbol_identity.ssa");
    var module = try parse(t.allocator, text);
    defer module.deinit();
    for ([_]planner.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        const emit_options: amd64.Options = .{ .reuse_stack_homes = options.reuse_stack_homes, .callee_saved_homes = options.callee_saved_homes };
        const before = try amd64.emitWithOptions(t.allocator, &module, emit_options);
        defer t.allocator.free(before);
        for (module.functions.items, 0..) |_, i| {
            var plan = try planner.FunctionPlan.init(t.allocator, &module, id(@intCast(i)), options);
            defer plan.deinit();
            try t.expectEqual(@as(u64, 0), plan.frame.bytes % 16);
        }
        const after = try amd64.emitWithOptions(t.allocator, &module, emit_options);
        defer t.allocator.free(after);
        try t.expectEqualSlices(u8, before, after);
    }
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, mixed);
    defer module.deinit();
    var first = try planner.FunctionPlan.init(allocator, &module, id(0), .{});
    defer first.deinit();
    var second = try planner.FunctionPlan.init(allocator, &module, id(0), .{ .reuse_stack_homes = true, .callee_saved_homes = true });
    defer second.deinit();
    if (first.calls.len != 1 or second.calls.len != 1) return error.BadSnapshot;
}
test "aggregate_abi_planner every parse validation plan home allocation failure cleans owned snapshot" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

test "aggregate_abi_planner scalar bank exhaustion independent prefix counts and old cursor compatibility" {
    const gp = [_]abi.General{ .rdi, .rsi, .rdx, .rcx, .r8, .r9 };
    const fp = [_]abi.Vector{ .xmm0, .xmm1, .xmm2, .xmm3, .xmm4, .xmm5, .xmm6, .xmm7 };
    for (0..256) |bits| {
        var module = Module.init(t.allocator);
        defer module.deinit();
        const fid = try module.addFunction("f", null);
        const f = module.getFunction(fid).?;
        const block = try f.addBlock(null);
        var arguments: [16]ir.CallArgument = undefined;
        for (&arguments, 0..) |*arg, i| {
            const floating = bits & (@as(usize, 1) << @intCast(i % 8)) != 0;
            const ty: ir.AbiType = if (floating) (if (i % 2 == 0) .single else .double) else (if (i % 2 == 0) .word else .long);
            const constant: ir.Constant = switch (ty) {
                .word => .{ .word = 0 },
                .long => .{ .long = 0 },
                .single => .{ .single_bits = 0 },
                .double => .{ .double_bits = 0 },
                else => unreachable,
            };
            arg.* = ir.CallArgument.init(ty, .{ .constant = constant });
        }
        try f.appendVoidCall(block, try module.symbols.intern("outside"), &arguments);
        try f.terminate(block, .{ .return_value = null });
        var plan = try planner.FunctionPlan.init(t.allocator, &module, fid, .{});
        defer plan.deinit();
        var old: abi.ArgumentCursor = .{};
        for (plan.calls[0].signature.arguments, 0..) |arg, i| {
            var integers: usize = 0;
            var floats: usize = 0;
            for (arguments[0..i]) |prior| {
                if (prior.scalar_type == .word or prior.scalar_type == .long) integers += 1 else floats += 1;
            }
            const old_location = try old.next(arguments[i].scalar_type);
            if (arguments[i].scalar_type == .word or arguments[i].scalar_type == .long) {
                if (integers < 6) {
                    try t.expectEqual(gp[integers], arg.location.general);
                    try t.expectEqual(gp[integers], old_location.general);
                    continue;
                }
            } else if (floats < 8) {
                try t.expectEqual(fp[floats], arg.location.vector);
                try t.expectEqual(fp[floats], old_location.vector);
                continue;
            }
            const ordinal = (integers -| 6) + (floats -| 8);
            try t.expectEqual(@as(u64, @intCast(ordinal * 8)), arg.location.stack.offset);
            try t.expectEqual(@as(u32, @intCast(16 + ordinal * 8)), try old_location.stack.incomingOffset());
        }
    }
}

test "aggregate_abi_planner max outgoing is not sum and high end padding is retained" {
    var module = try parse(t.allocator, "function $f(){\n@e\ncall $two(l 0,l 0,l 0,l 0,l 0,l 0,l 0,l 0)\ncall $three(l 0,l 0,l 0,l 0,l 0,l 0,l 0,l 0,l 0)\nret\n}");
    defer module.deinit();
    var plan = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
    defer plan.deinit();
    try t.expectEqual(@as(u64, 16), plan.calls[0].signature.outgoing_bytes);
    try t.expectEqual(@as(u64, 32), plan.calls[1].signature.outgoing_bytes);
    try t.expectEqual(@as(u64, 32), plan.frame.outgoing_bytes);
    try t.expectEqual(@as(u64, 32), plan.frame.bytes);
    try stack(plan.calls[1].signature.arguments[6], 0, 8, 16, 8, 8);
    try stack(plan.calls[1].signature.arguments[7], 8, 8, 24, 8, 8);
    try stack(plan.calls[1].signature.arguments[8], 16, 8, 32, 8, 8);
}

test "aggregate_abi_planner fixed pads never coalesce with pointer homes and enforce complete frame cap" {
    for ([_]usize{ 15, 16 }) |count| {
        var module = Module.init(t.allocator);
        defer module.deinit();
        const record_id = try module.addRecord("Big", null, &.{.{ .element = .{ .scalar = .byte }, .count = 4096 }});
        const fid = try module.addFunction("f", null);
        const f = module.getFunction(fid).?;
        const block = try f.addBlock(null);
        const external = try module.symbols.intern("outside");
        for (0..count) |_| {
            const result = try f.declareValue(.long);
            try f.appendCall(block, result, .{ .symbol = external }, &.{}, .{ .result_descriptor = .{ .record = record_id } });
        }
        try f.terminate(block, .{ .return_value = null });
        for ([_]planner.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true } }, 0..) |options, index| {
            if (count == 16) {
                try t.expectError(error.FrameTooLarge, planner.FunctionPlan.init(t.allocator, &module, fid, options));
            } else {
                var plan = try planner.FunctionPlan.init(t.allocator, &module, fid, options);
                defer plan.deinit();
                try t.expectEqual(@as(usize, 15), plan.pads.len);
                try t.expectEqual(@as(u64, if (index == 0) 61568 else 61456), plan.frame.bytes);
                for (plan.pads[1..], plan.pads[0 .. plan.pads.len - 1]) |next, prior| try t.expectEqual(@as(u64, 4096), next.end - prior.end);
            }
        }
    }
}

test "aggregate_abi_planner snapshot stays valid on every failure and same module retry balances ownership" {
    var module = try parse(t.allocator, mixed);
    defer module.deinit();
    var retained = try planner.FunctionPlan.init(t.allocator, &module, id(0), .{});
    defer retained.deinit();
    const globals = module.symbols.names.items.len;
    const names = module.record_names.names.items.len;
    for ([_]planner.Options{ .{}, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        var finished = false;
        for (0..512) |failure| {
            var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = failure, .resize_fail_index = 0 });
            if (planner.FunctionPlan.init(failing.allocator(), &module, id(0), options)) |value| {
                var plan = value;
                plan.deinit();
                finished = true;
            } else |err| {
                try t.expectEqual(error.OutOfMemory, err);
                failing.fail_index = std.math.maxInt(usize);
                var retry = try planner.FunctionPlan.init(failing.allocator(), &module, id(0), options);
                try mixedOracle(retry.signature);
                retry.deinit();
            }
            try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
            try mixedOracle(retained.signature);
            try t.expectEqual(globals, module.symbols.names.items.len);
            try t.expectEqual(names, module.record_names.names.items.len);
            if (finished) break;
        }
        try t.expect(finished);
    }
}

test "aggregate_abi_planner module scoped ordinals resolve current records not snapshot owner guesses" {
    var first = try parse(t.allocator, "type :A={b 17}\nfunction $f(:A %p){\n@e\nret\n}");
    defer first.deinit();
    var second = try parse(t.allocator, "type :Other={l 3}\nfunction $f(:Other %p){\n@e\nret\n}");
    defer second.deinit();
    var a = try planner.FunctionPlan.init(t.allocator, &first, id(0), .{});
    defer a.deinit();
    var b = try planner.FunctionPlan.init(t.allocator, &second, id(0), .{});
    defer b.deinit();
    try t.expectEqual(@as(u32, 0), @backingInt(a.signature.arguments[0].descriptor.record));
    try t.expectEqual(@as(u32, 0), @backingInt(b.signature.arguments[0].descriptor.record));
    try t.expectEqual(@as(u64, 17), a.signature.arguments[0].declared_bytes);
    try t.expectEqual(@as(u64, 24), b.signature.arguments[0].declared_bytes);
    const nominal = "type :A={b 17}\ntype :Twin={b 17}\nfunction $f(){\n@e\ncall $g(:Twin 0)\nret\n}\nfunction $g(:A %p){\n@e\nret\n}";
    var mismatch = try parse(t.allocator, nominal);
    defer mismatch.deinit();
    try t.expectError(error.CallSignatureMismatch, planner.FunctionPlan.init(t.allocator, &mismatch, id(0), .{}));
    for ([_]u8{ 32, 64 }) |alignment| {
        const text = try std.fmt.allocPrint(t.allocator, "type :A=align {d} {{b 17}}\nfunction $f(:A %p){{\n@e\nret\n}}", .{alignment});
        defer t.allocator.free(text);
        var module = try parse(t.allocator, text);
        defer module.deinit();
        try t.expectError(error.UnsupportedAggregatePlan, planner.FunctionPlan.init(t.allocator, &module, id(0), .{}));
    }
}

test "aggregate_abi_planner scalar home scratch saved and variadic geometry remains exact" {
    var module = try parse(t.allocator, "function l $f(l %p){\n@e\n%a =l add %p,1\n%b =l add %a,1\nret %b\n}");
    defer module.deinit();
    for ([_]planner.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }, 0..) |options, i| {
        var plan = try planner.FunctionPlan.init(t.allocator, &module, id(0), options);
        defer plan.deinit();
        // Three dead-to-live chain values: baseline3 slots, coloring1 slot;
        // preserved option takes that1 slot into register and saves original8.
        const scratch = [_]u64{ 24, 8, 0, 0 };
        const saved_base = [_]u64{ 24, 8, 0, 0 };
        const bytes = [_]u64{ 32, 16, 16, 16 };
        const saved_count = [_]usize{ 0, 0, 1, 1 };
        try t.expectEqual(scratch[i], plan.frame.scratch_base);
        try t.expectEqual(saved_base[i], plan.frame.saved_base);
        try t.expectEqual(bytes[i], plan.frame.bytes);
        try t.expectEqual(saved_count[i], plan.frame.saved_count);
    }
    var vararg = try parse(t.allocator, "function l $f(l %p,...){\n@e\nret %p\n}");
    defer vararg.deinit();
    var plan = try planner.FunctionPlan.init(t.allocator, &vararg, id(0), .{});
    defer plan.deinit();
    try t.expectEqual(@as(u64, 192), plan.frame.variadic_save_end.?);
    try t.expectEqual(@as(u64, 192), plan.frame.bytes);
    try t.expectEqual(@as(u64, 8), plan.frame.scratch_base);
}
