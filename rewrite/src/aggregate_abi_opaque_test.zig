const std = @import("std");
const t = std.testing;
const records = @import("record_declaration.zig");
const Module = @import("module.zig").Module;
const frontend = @import("frontend.zig");
const validation = @import("module_validation.zig");
const planner = @import("abi_amd64_plan.zig");
const amd64 = @import("amd64.zig");
const interpreter = @import("interpreter.zig");
fn id(n: u32) @import("module.zig").FunctionId {
    return @fromBackingInt(n);
}
fn parse(a: std.mem.Allocator, text: []const u8) !Module {
    var d: ?@import("source.zig").Diagnostic = null;
    return frontend.parse(a, .{ .name = "opaque", .text = text }, &d);
}
const decls = "type :O1=align 16 {1}\ntype :O13=align 8 {13}\ntype :O17=align 16 {17}\ntype :O3=align 1 {3}\n";
const scalar = "function w $scalar(){\n@e\nret 42\n}\n";
test "aggregate_abi_opaque exact bytes raw nested stride union and maximum compact metadata" {
    var m = try parse(t.allocator, decls ++ "type :R={:O13 2,b}\ntype :S={:O1}\ntype :L={:O1,b}\ntype :U={{:O1}{b 17}}\ntype :MAX=align 64 {18446744073709551615}");
    defer m.deinit();
    const sizes = [_]u64{ 1, 13, 17, 3, 32, 16, 16, 32, std.math.maxInt(u64) };
    const aligns = [_]u8{ 16, 8, 16, 1, 8, 16, 16, 16, 64 };
    for (m.types.items, sizes, aligns) |r, s, a| {
        try t.expectEqual(s, r.size);
        try t.expectEqual(a, r.alignment);
    }
    try t.expectEqual(@as(u64, 13), m.types.items[4].runs[0].stride);
    try t.expectEqual(@as(u64, 26), m.types.items[4].runs[1].offset);
    try t.expectEqual(@as(usize, 0), m.types.items[8].runs.len);
    try validation.validate(t.allocator, &m);
    for ([_][]const u8{ "type :X={:MAX}", "type :X={:MAX 2}", "type :X={b,:MAX}", "type :X={{:MAX}}" }) |tail| {
        const text = try std.mem.concat(t.allocator, u8, &.{ decls, "type :MAX=align 64 {18446744073709551615}\n", tail });
        defer t.allocator.free(text);
        try t.expectError(error.RecordLayoutOverflow, parse(t.allocator, text));
    }
}
test "aggregate_abi_opaque diagnostic exact size alignment and closing token spans" {
    for ([_]struct { text: []const u8, token: []const u8, code: @import("source.zig").Diagnostic.Code }{
        .{ .text = "type :O={13}", .token = "13", .code = .invalid_alignment },
        .{ .text = "type :O=align 8 {0}", .token = "0", .code = .invalid_opaque_size },
        .{ .text = "type :O=align 8 {-1}", .token = "-1", .code = .invalid_opaque_size },
        .{ .text = "type :O=align 8 {18446744073709551616}", .token = "18446744073709551616", .code = .invalid_opaque_size },
        .{ .text = "type :O=align 3 {1}", .token = "3", .code = .invalid_alignment },
        .{ .text = "type :O=align 8 {13,}", .token = ",", .code = .unexpected_token },
        .{ .text = "type :O=align 8 {13 b}", .token = "b", .code = .unexpected_token },
        .{ .text = "type :O=align 8 {13 2}", .token = "2", .code = .unexpected_token },
        .{ .text = "type :O=align 8 {1}\ntype :O=align 8 {1}", .token = ":O", .code = .duplicate_type },
    }) |c| {
        var d: ?@import("source.zig").Diagnostic = null;
        try t.expectError(error.InvalidInput, frontend.parse(t.allocator, .{ .name = "bad", .text = c.text }, &d));
        try t.expectEqual(c.code, d.?.code);
        try t.expectEqualStrings(c.token, c.text[d.?.span.start..d.?.span.end]);
    }
    var m = Module.init(t.allocator);
    defer m.deinit();
    try t.expectError(error.InvalidOpaqueSize, m.addOpaque("Zero", 8, 0));
    for ([_]u8{ 0, 3, 128 }) |a| try t.expectError(error.InvalidRecordAlignment, m.addOpaque("Bad", a, 1));
    try t.expectEqual(@as(usize, 0), m.types.items.len);
}
test "aggregate_abi_opaque ALL unused payload kind arrays and child facts validate without hidden owner" {
    var m = try parse(t.allocator, decls ++ "type :R={:O13 2,b}\n" ++ scalar);
    defer m.deinit();
    const o = m.types.items[1];
    const saved = o.*;
    var fake_variants = [_]records.Variant{.{ .first_run = 0, .run_count = 1, .size = 13, .alignment = 8 }};
    for (0..10) |n| {
        o.* = saved;
        switch (n) {
            0 => o.opaque_bytes = null,
            1 => o.opaque_bytes = 0,
            2 => o.opaque_bytes = 14,
            3 => o.size = 16,
            4 => o.alignment = 16,
            5 => o.explicit_alignment = null,
            6 => o.explicit_alignment = 3,
            7 => o.kind = .regular,
            8 => o.runs = m.types.items[4].runs,
            9 => o.variants = &fake_variants,
            else => unreachable,
        }
        try t.expectError(error.InvalidRecordLayout, validation.validate(t.allocator, &m));
        try t.expectError(error.InvalidRecordLayout, amd64.emit(t.allocator, &m));
        try t.expectError(error.InvalidRecordLayout, interpreter.evaluateModule(t.allocator, &m, id(0), &.{}, .{}));
        try t.expectEqual(@as(u32, 42), (try interpreter.evaluate(t.allocator, m.functions.items[0], &.{}, .{})).?.word);
    }
    o.* = saved;
    // A coherent child edit still invalidates the enclosing cached raw stride.
    o.size = 12;
    o.opaque_bytes = 12;
    try t.expectError(error.InvalidRecordLayout, validation.validate(t.allocator, &m));
    o.* = saved;
    m.types.items[4].opaque_bytes = 32;
    try t.expectError(error.InvalidRecordLayout, validation.validate(t.allocator, &m));
    m.types.items[4].opaque_bytes = null;
    // Destructor follows owned allocations, even when kind has been edited.
    m.types.items[4].kind = .@"opaque";
}
fn stack(a: planner.Argument, offset: u64, extent: u64, bytes: u64) !void {
    try t.expect(a.location == .stack);
    try t.expectEqual(offset, a.location.stack.offset);
    try t.expectEqual(extent, a.location.stack.extent);
    try t.expectEqual(bytes, a.declared_bytes);
    try t.expectEqual(@as(i32, @intCast(16 + offset)), a.location.stack.incoming);
}
const pressureA = decls ++ "function :O1 $f(l %a,l %b,l %c,l %d,l %e,:O1 %o,l %six,...){\n@e\n%list =l alloc8 24\nvastart %list\n%r =:O1 call $ext(l %a,l %b,l %c,l %d,l %e,:O1 %o,l %six,...,:O13 0,d d_1,l 99,:O1 %o,l 101)\nret %r\n}";
const pressureB = decls ++ "function :O13 $f(d %a,d %b,d %c,d %d,d %e,d %f,d %g,d %h,:O3 %o,l %last,...){\n@e\n%list =l alloc8 24\nvastart %list\n%r =:O13 call $ext(d %a,d %b,d %c,d %d,d %e,d %f,d %g,d %h,:O3 %o,l %last,...,d d_1,l 99,:O17 0,:O1 0)\nret %r\n}";
test "aggregate_abi_opaque independent pressure A and B hidden RDI raw named end occupied extents AL" {
    var a = try parse(t.allocator, pressureA);
    defer a.deinit();
    var p = try planner.FunctionPlan.init(t.allocator, &a, id(0), .{});
    defer p.deinit();
    try t.expect(p.signature.result == .memory);
    try t.expectEqual(@as(u64, 1), p.signature.result.memory.declared_bytes);
    try t.expectEqual(@as(u8, 6), p.signature.general_used);
    try t.expectEqual(@as(u8, 0), p.signature.vector_used);
    try stack(p.signature.arguments[5], 0, 16, 1);
    try stack(p.signature.arguments[6], 16, 8, 8);
    try t.expectEqual(@as(u64, 24), p.signature.stack_bytes);
    try t.expectEqual(@as(u64, 32), p.signature.outgoing_bytes);
    try t.expectEqual(@as(i32, 40), try p.signature.stackEndIncomingOffset());
    const c = p.calls[0].signature;
    try stack(c.arguments[7], 24, 16, 13);
    try stack(c.arguments[9], 40, 8, 8);
    try stack(c.arguments[10], 48, 16, 1);
    try stack(c.arguments[11], 64, 8, 8);
    try t.expectEqual(@as(u64, 72), c.stack_bytes);
    try t.expectEqual(@as(u64, 80), c.outgoing_bytes);
    try t.expectEqual(@as(u8, 1), c.vector_used);
    try t.expectEqual(@as(usize, 0), p.parameter_objects.len);
    var b = try parse(t.allocator, pressureB);
    defer b.deinit();
    var q = try planner.FunctionPlan.init(t.allocator, &b, id(0), .{});
    defer q.deinit();
    try t.expectEqual(@as(u8, 2), q.signature.general_used);
    try t.expectEqual(@as(u8, 8), q.signature.vector_used);
    try stack(q.signature.arguments[8], 0, 8, 3);
    try t.expectEqual(@as(u64, 8), q.signature.stack_bytes);
    try t.expectEqual(@as(i32, 24), try q.signature.stackEndIncomingOffset());
    const d = q.calls[0].signature;
    try stack(d.arguments[10], 8, 8, 8);
    try stack(d.arguments[12], 16, 32, 17);
    try stack(d.arguments[13], 48, 16, 1);
    try t.expectEqual(@as(u64, 64), d.stack_bytes);
    try t.expectEqual(@as(u8, 3), d.general_used);
    try t.expectEqual(@as(u8, 8), d.vector_used);
}
const owned = decls ++ "type :U={{:O17}{b 32}}\nfunction :O1 $f(:O13 %o,:U %u,...){\n@e\n%list =l alloc8 24\nvastart %list\n%r =:O1 call $ext(:O13 %o,...,:U %u,d d_1)\nret %r\n}\nfunction :O13 $env(env %e,:O13 %o){\n@e\n%r =:O13 call %e(env %e,:O13 %o)\nret %r\n}";
fn exercise(a: std.mem.Allocator) !void {
    var m = try parse(a, owned);
    defer m.deinit();
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |o| {
        const out = try amd64.emitWithOptions(a, &m, o);
        a.free(out);
    }
}
test "aggregate_abi_opaque exhaustive owned parse validation plans pads homes writer final cleanup" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
test "aggregate_abi_opaque exhaustive SAME module plan and emit retries no metadata mutation" {
    var m = try parse(t.allocator, owned);
    defer m.deinit();
    for ([_]bool{ false, true }) |emit| {
        var done = false;
        for (0..1024) |n| {
            var f = t.FailingAllocator.init(t.allocator, .{ .fail_index = n, .resize_fail_index = 0 });
            const result: anyerror!void = if (emit) emitExercise(f.allocator(), &m) else planExercise(f.allocator(), &m);
            if (result) |_| {
                try t.expect(!f.has_induced_failure);
                done = true;
            } else |err| {
                try t.expectEqual(error.OutOfMemory, err);
                try t.expectEqual(f.allocated_bytes, f.freed_bytes);
                f.fail_index = std.math.maxInt(usize);
                if (emit) try emitExercise(f.allocator(), &m) else try planExercise(f.allocator(), &m);
            }
            try t.expectEqual(f.allocated_bytes, f.freed_bytes);
            try validation.validate(t.allocator, &m);
            if (done) break;
        }
        try t.expect(done);
    }
}
fn emitExercise(a: std.mem.Allocator, m: *Module) !void {
    const out = try amd64.emitWithOptions(a, m, .{ .reuse_stack_homes = true, .callee_saved_homes = true });
    a.free(out);
}
fn planExercise(a: std.mem.Allocator, m: *Module) !void {
    var p = try planner.ModulePlans.init(a, m, .{ .reuse_stack_homes = true, .callee_saved_homes = true });
    p.deinit();
}
test "aggregate_abi_opaque builder first and grown publication exhaustive OOM same module retry" {
    for ([_]usize{ 0, 8 }) |seed| {
        var done = false;
        for (0..64) |n| {
            var f = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
            var m = Module.init(f.allocator());
            _ = try m.symbols.intern("OnlyGlobal");
            for (0..seed) |j| {
                var b: [32]u8 = undefined;
                _ = try m.addOpaque(try std.fmt.bufPrint(&b, "Seed{d}", .{j}), 8, 13);
            }
            const stable = if (seed > 0) m.types.items[0] else null;
            f.fail_index = f.alloc_index + n;
            if (m.addOpaque("New", 16, 1)) |new| {
                try t.expectEqual(seed, @backingInt(new));
                done = true;
            } else |err| {
                try t.expectEqual(error.OutOfMemory, err);
                try t.expectEqual(seed, m.types.items.len);
                try t.expect(m.findRecord("New") == null);
                f.fail_index = std.math.maxInt(usize);
                try t.expectEqual(seed, @backingInt(try m.addOpaque("New", 16, 1)));
            }
            try t.expectEqual(@as(usize, 1), m.symbols.names.items.len);
            try t.expectEqualStrings("OnlyGlobal", m.symbols.names.items[0]);
            if (stable) |s| try t.expect(m.types.items[0] == s);
            try m.validateRecords(t.allocator);
            m.deinit();
            try t.expectEqual(f.allocated_bytes, f.freed_bytes);
            if (done) break;
        }
        try t.expect(done);
    }
}
test "aggregate_abi_opaque source name lifetime stable growth type cap4096 and zero run budget" {
    var m = Module.init(t.allocator);
    defer m.deinit();
    const name = try t.allocator.dupe(u8, "First");
    const first = try m.addOpaque(name, 64, std.math.maxInt(u64));
    @memset(name, 0xa5);
    t.allocator.free(name);
    const ptr = m.getRecord(first).?;
    for (1..records.max_records) |n| {
        var b: [32]u8 = undefined;
        _ = try m.addOpaque(try std.fmt.bufPrint(&b, "O{d}", .{n}), 1, 1);
    }
    try t.expect(m.getRecord(first).? == ptr);
    try t.expectEqualStrings("First", m.record_names.get(ptr.name).?);
    try t.expectEqual(@as(usize, 0), m.symbols.names.items.len);
    const names = m.record_names.names.items.len;
    try t.expectError(error.RecordLimitExceeded, m.addOpaque("Over", 8, 1));
    try t.expectEqual(names, m.record_names.names.items.len);
    const text = try t.allocator.dupe(u8, owned);
    var other = try parse(t.allocator, text);
    @memset(text, 0xa5);
    t.allocator.free(text);
    var p = try planner.FunctionPlan.init(t.allocator, &other, id(0), .{});
    other.deinit();
    defer p.deinit();
    try t.expectEqual(@as(u64, 1), p.signature.result.memory.declared_bytes);
}
test "aggregate_abi_opaque transitive small regular union and all unsupported slots refuse globally" {
    for ([_][]const u8{
        "function :S $f(:S %p){\n@e\nret %p\n}",
        "function $f(:S %p){\n@e\nret\n}",
        "function $f(){\n@e\ncall $ext(:S 0)\nret\n}",
        "function $f(){\n@e\ncall 0(:S 0)\nret\n}",
        "function $f(){\n@e\nret\n@unreachable\n%r =:S call $ext()\nret\n}",
    }) |body| {
        for ([_][]const u8{ "type :S={:O1}", "type :X={:O1}\ntype :S={{w}{:X}}", "type :S=align 32 {1}", "type :S=align 8 {4097}" }) |definition| {
            const text = try std.mem.concat(t.allocator, u8, &.{ decls, definition, "\n", body });
            defer t.allocator.free(text);
            var m = try parse(t.allocator, text);
            defer m.deinit();
            try t.expectError(error.UnsupportedAggregatePlan, planner.ModulePlans.init(t.allocator, &m, .{}));
            try t.expectError(error.UnsupportedAggregateAbi, amd64.emit(t.allocator, &m));
            // Count the generic validation allocations. Next allocation must never be attempted.
            var count = t.FailingAllocator.init(t.allocator, .{});
            try validation.validate(count.allocator(), &m);
            const boundary = count.alloc_index;
            try t.expectEqual(count.allocated_bytes, count.freed_bytes);
            var fail = t.FailingAllocator.init(t.allocator, .{ .fail_index = boundary });
            try t.expectError(error.UnsupportedAggregatePlan, planner.ModulePlans.init(fail.allocator(), &m, .{}));
            try t.expect(!fail.has_induced_failure);
            try t.expectEqual(fail.allocated_bytes, fail.freed_bytes);
        }
    }
    var m = try parse(t.allocator, decls ++ "type :Large={{:O1}{b 17}}\nfunction :Large $f(:Large %p){\n@e\nret %p\n}");
    defer m.deinit();
    var p = try planner.FunctionPlan.init(t.allocator, &m, id(0), .{});
    defer p.deinit();
    try t.expect(p.signature.result == .memory);
    try stack(p.signature.arguments[0], 0, 32, 32);
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluateModule(t.allocator, &m, id(0), &.{}, .{ .internal_variadic_calls = true }));
}
test "aggregate_abi_opaque unused prefixes suffixes leave exact symbols ordinals and assembly all8 options" {
    const text = @embedFile("fixtures/record_declaration_symbol_identity.ssa");
    var baseline = try parse(t.allocator, text);
    defer baseline.deinit();
    for ([_]bool{ false, true }) |prefix| {
        const source = try std.mem.concat(t.allocator, u8, if (prefix) &.{ decls, text } else &.{ text, decls });
        defer t.allocator.free(source);
        var m = try parse(t.allocator, source);
        defer m.deinit();
        for (m.symbols.names.items, baseline.symbols.names.items) |a, b| try t.expectEqualStrings(a, b);
        for (m.functions.items, baseline.functions.items) |a, b| try t.expectEqual(a.name, b.name);
        for (0..8) |mask| {
            if (mask & 1 != 0) {
                for (m.functions.items) |f| _ = try @import("optimize.zig").foldIntegerConstants(t.allocator, f);
                for (baseline.functions.items) |f| _ = try @import("optimize.zig").foldIntegerConstants(t.allocator, f);
            }
            const o: amd64.Options = .{ .reuse_stack_homes = mask & 2 != 0, .callee_saved_homes = mask & 4 != 0 };
            const a = try amd64.emitWithOptions(t.allocator, &m, o);
            defer t.allocator.free(a);
            const b = try amd64.emitWithOptions(t.allocator, &baseline, o);
            defer t.allocator.free(b);
            try t.expectEqualStrings(a, b);
        }
    }
}

test "aggregate_abi_opaque shared module run budget remains65536 while opaque adds zero runs" {
    var m = Module.init(t.allocator);
    defer m.deinit();
    const fields = try t.allocator.alloc(records.Field, records.max_record_runs);
    defer t.allocator.free(fields);
    @memset(fields, .{ .element = .{ .scalar = .byte } });
    for (0..16) |n| {
        var b: [24]u8 = undefined;
        _ = try m.addRecord(try std.fmt.bufPrint(&b, "R{d}", .{n}), null, fields);
    }
    _ = try m.addOpaque("ZeroRuns", 64, std.math.maxInt(u64));
    try t.expectError(error.RecordLimitExceeded, m.addRecord("TooMany", null, fields[0..1]));
    try t.expectError(error.RecordLimitExceeded, m.addUnion("TooMany", null, &.{fields[0..1]}));
    try t.expectEqual(@as(usize, 17), m.types.items.len);
    try m.validateRecords(t.allocator);
}
test "aggregate_abi_opaque exact65536 frame hidden slot176 variadic save no parameter object" {
    for ([_]usize{ 8164, 8165 }) |copies| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(t.allocator);
        try text.appendSlice(t.allocator, "type :O=align 16 {1}\nfunction :O $f(:O %p,...){\n@e\n%list =l alloc8 24\nvastart %list\n");
        for (0..copies) |n| {
            var b: [48]u8 = undefined;
            try text.appendSlice(t.allocator, try std.fmt.bufPrint(&b, "%v{d} =l copy 0\n", .{n}));
        }
        try text.appendSlice(t.allocator, "ret %p\n}");
        var m = try parse(t.allocator, text.items);
        defer m.deinit();
        // 8166 slots ->65328, +176 save ->65504, +8 hidden ->65512 =>65520.
        // Actual exact boundary includes8165/8166 copies; these near cases
        // also ensure hidden MEMORY storage is not replaced by a register object.
        var p = try planner.FunctionPlan.init(t.allocator, &m, id(0), .{});
        defer p.deinit();
        try t.expectEqual(@as(usize, 0), p.parameter_objects.len);
        try t.expectEqual(@as(u64, if (copies == 8164) 65520 else 65536), p.frame.bytes);
    }
    for ([_]usize{ 8166, 8167 }) |copies| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(t.allocator);
        try text.appendSlice(t.allocator, "type :O=align 16 {1}\nfunction :O $f(:O %p,...){\n@e\n%list =l alloc8 24\nvastart %list\n");
        for (0..copies) |n| {
            var b: [48]u8 = undefined;
            try text.appendSlice(t.allocator, try std.fmt.bufPrint(&b, "%v{d} =l copy 0\n", .{n}));
        }
        try text.appendSlice(t.allocator, "ret %p\n}");
        var m = try parse(t.allocator, text.items);
        defer m.deinit();
        if (copies == 8167) {
            try t.expectError(error.FrameTooLarge, planner.FunctionPlan.init(t.allocator, &m, id(0), .{}));
        } else {
            var p = try planner.FunctionPlan.init(t.allocator, &m, id(0), .{});
            defer p.deinit();
            try t.expectEqual(@as(u64, 65536), p.frame.bytes);
            try t.expectEqual(@as(u64, 65520), p.frame.variadic_save_end.?);
            try t.expectEqual(@as(u64, 65528), p.frame.hidden_return_end.?);
        }
    }
    // Both next eightbyte values cross the cap, not an allocation failure.
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(t.allocator);
    try text.appendSlice(t.allocator, "type :O=align 16 {1}\nfunction :O $f(:O %p,...){\n@e\n%list =l alloc8 24\nvastart %list\n");
    for (0..8168) |n| {
        var b: [48]u8 = undefined;
        try text.appendSlice(t.allocator, try std.fmt.bufPrint(&b, "%v{d} =l copy 0\n", .{n}));
    }
    try text.appendSlice(t.allocator, "ret %p\n}");
    var m = try parse(t.allocator, text.items);
    defer m.deinit();
    try t.expectError(error.FrameTooLarge, planner.FunctionPlan.init(t.allocator, &m, id(0), .{}));
}
test "aggregate_abi_opaque nominal descriptor validation and interpreter refusals retain precedence" {
    for ([_][]const u8{
        "type :O=align 8 {3}\nfunction :O $f(env %e,:O %p,...){\n@e\nret %p\n}",
        "type :O=align 8 {3}\nfunction $f(){\n@e\n%r =:O vaarg 0\nret\n}",
    }) |text| try t.expectError(error.InvalidInput, parse(t.allocator, text));
    var m = try parse(t.allocator, "type :O=align 1 {3}\ntype :P=align 1 {3}\nfunction :O $g(:O %p){\n@e\nret %p\n}\nfunction $f(){\n@e\n%r =:P call $g(:O 0)\nret\n}");
    defer m.deinit();
    try t.expectError(error.CallSignatureMismatch, amd64.emit(t.allocator, &m));
    var root = try parse(t.allocator, "type :O=align 1 {3}\nfunction :O $f(:O %p){\n@e\nret %p\n}\nfunction w $caller(){\n@e\n%r =:O call $f(:O 0)\nret 0\n}");
    defer root.deinit();
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluate(t.allocator, root.functions.items[0], &.{}, .{ .max_call_depth = 0 }));
    try t.expectError(error.StepLimitExceeded, interpreter.evaluateModule(t.allocator, &root, id(1), &.{}, .{ .max_steps = 0 }));
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluateModule(t.allocator, &root, id(1), &.{}, .{ .max_steps = 1, .internal_variadic_calls = true }));
}

test "aggregate_abi_opaque unused union payload rejects and destruction ignores mutated kinds" {
    var m = try parse(t.allocator, decls ++ "type :U={{:O13}{b 32}}\ntype :R={b}\n");
    defer m.deinit();
    const u = m.types.items[4];
    u.opaque_bytes = u.size;
    try t.expectError(error.InvalidRecordLayout, m.validateRecords(t.allocator));
    u.opaque_bytes = null;
    u.kind = .@"opaque";
    m.types.items[5].kind = .@"opaque";
}
test "aggregate_abi_opaque later invalid descriptor precedes unsupported small container target" {
    var m = try parse(t.allocator, "type :O=align 16 {1}\ntype :S={:O}\nfunction $f(:S %p){\n@e\ncall $ext(:O 0)\nret\n}");
    defer m.deinit();
    @constCast(m.functions.items[0].blocks.items[0].instructions.items[0].call.arguments)[0].descriptor = .{ .record = @fromBackingInt(@as(u32, 999)) };
    try t.expectError(error.InvalidAggregateType, planner.ModulePlans.init(t.allocator, &m, .{}));
    try t.expectError(error.InvalidAggregateType, amd64.emit(t.allocator, &m));
}
