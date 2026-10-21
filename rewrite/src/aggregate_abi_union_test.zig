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
    return frontend.parse(a, .{ .name = "aggregate_abi_union", .text = text }, &d);
}
const declarations = "type :U4={{s}{w}}\ntype :U8={{s 2}{d}}\ntype :U12={{s 3}{w}}\ntype :U16={{s,l}{l,s}}\ntype :UM={{b 17}{d 2}}\ntype :UN=align 16 {{s}{b}}\ntype :Q={{s,w}{s,s}}\ntype :P={s,:Q}\ntype :QR={{w,s}{s,s}}\ntype :PR={s,:QR}\n";
test "aggregate_abi_union literal max rather than sum and all alternative origin zero" {
    var m = try parse(t.allocator, declarations);
    defer m.deinit();
    const sizes = [_]u64{ 4, 8, 12, 16, 24, 16, 8, 12, 8, 12 };
    const aligns = [_]u8{ 4, 8, 4, 8, 8, 16, 4, 4, 4, 4 };
    for (m.types.items, sizes, aligns, 0..) |record, size, alignment, n| {
        try t.expectEqual(size, record.size);
        try t.expectEqual(alignment, record.alignment);
        if (n == 7 or n == 9) {
            try t.expectEqual(records.Kind.regular, record.kind);
            try t.expectEqual(@as(usize, 0), record.variants.len);
        } else {
            try t.expectEqual(records.Kind.union_type, record.kind);
            try t.expectEqual(@as(usize, 2), record.variants.len);
            try t.expectEqual(@as(u64, 0), record.runs[record.variants[1].first_run].offset);
        }
    }
    try validation.validate(t.allocator, &m);
}
test "aggregate_abi_union byte shifted children and merged mixed alternatives choose physical lanes" {
    const text = try std.mem.concat(t.allocator, u8, &.{ declarations, "function :U16 $i(:U16 %p){\n@e\nret %p\n}\nfunction :P $si(:P %p){\n@e\nret %p\n}\nfunction :PR $is(:PR %p){\n@e\nret %p\n}\nfunction :UN $n(:UN %p){\n@e\nret %p\n}" });
    defer t.allocator.free(text);
    var m = try parse(t.allocator, text);
    defer m.deinit();
    var a = try planner.FunctionPlan.init(t.allocator, &m, id(0), .{});
    defer a.deinit();
    try t.expectEqual(@as(u8, 2), a.signature.result.integer_record.lane_count);
    var b = try planner.FunctionPlan.init(t.allocator, &m, id(1), .{});
    defer b.deinit();
    try t.expect(b.signature.result.register_record.lanes[0].register == .vector);
    try t.expect(b.signature.result.register_record.lanes[1].register == .general);
    var c = try planner.FunctionPlan.init(t.allocator, &m, id(2), .{});
    defer c.deinit();
    try t.expect(c.signature.result.register_record.lanes[0].register == .general);
    try t.expect(c.signature.result.register_record.lanes[1].register == .vector);
    var d = try planner.FunctionPlan.init(t.allocator, &m, id(3), .{});
    defer d.deinit();
    try t.expectEqual(@as(u8, 1), d.signature.result.register_record.lane_count);
    try t.expectEqual(@as(u64, 16), d.signature.result.register_record.declared_bytes);
}
test "aggregate_abi_union hidden UM variadic raw24 rounded32 independently calculated stack oracle" {
    const text = try std.mem.concat(t.allocator, u8, &.{ declarations, "function :UM $f(l %a,l %b,l %c,l %d,l %e,:U12 %u,l %last,...){\n@e\n%list =l alloc8 24\nvastart %list\n%r =:UM call $outside(l 1,l 2,l 3,l 4,l 5,:U12 %u,l 6,...,:U8 0,l 99,:UM 0,l 101)\nret %r\n}" });
    defer t.allocator.free(text);
    var m = try parse(t.allocator, text);
    defer m.deinit();
    var p = try planner.FunctionPlan.init(t.allocator, &m, id(0), .{});
    defer p.deinit();
    try t.expectEqual(@as(u8, 6), p.signature.general_used);
    try t.expectEqual(@as(u8, 0), p.signature.vector_used);
    try t.expectEqual(@as(u64, 24), p.signature.stack_bytes);
    try t.expectEqual(@as(u64, 32), p.signature.outgoing_bytes);
    try t.expectEqual(@as(i32, 40), try p.signature.stackEndIncomingOffset());
    try t.expectEqual(@as(u8, 1), p.calls[0].signature.vector_used);
    try t.expectEqual(@as(u64, 64), p.calls[0].signature.stack_bytes);
}
test "aggregate_abi_union unused variant partition overflow kind caches and child IDs always validate" {
    var m = try parse(t.allocator, "type :A={b}\ntype :U={{:A}{s,w}}\nfunction w $f(){\n@e\nret 7\n}");
    defer m.deinit();
    const u = m.types.items[1];
    const original = u.variants[1];
    u.variants[1].first_run = std.math.maxInt(usize);
    try t.expectError(error.InvalidRecordLayout, validation.validate(t.allocator, &m));
    u.variants[1] = original;
    u.variants[1].run_count = std.math.maxInt(usize);
    try t.expectError(error.InvalidRecordLayout, amd64.emit(t.allocator, &m));
    u.variants[1] = original;
    u.variants[1].size += 1;
    try t.expectError(error.InvalidRecordLayout, interpreter.evaluateModule(t.allocator, &m, id(0), &.{}, .{}));
    u.variants[1] = original;
    u.kind = .regular;
    try t.expectError(error.InvalidRecordLayout, validation.validate(t.allocator, &m));
    u.kind = .union_type;
    const first = u.runs[0];
    u.runs[0].field.element = .{ .record = @fromBackingInt(@intCast(1)) };
    try t.expectError(error.InvalidRecordReference, validation.validate(t.allocator, &m));
    u.runs[0] = first;
    u.runs[original.first_run].offset += 1;
    try t.expectError(error.InvalidRecordLayout, validation.validate(t.allocator, &m));
    u.runs[original.first_run].offset -= 1;
    try validation.validate(t.allocator, &m);
    // Detached scalar evaluation cannot inspect unrelated module metadata.
    u.variants[1].size += 1;
    const detached = try interpreter.evaluate(t.allocator, m.functions.items[0], &.{}, .{});
    try t.expectEqual(@as(u32, 7), detached.?.word);
    u.variants[1] = original;
}
const huge = "type :A={b 2147483647}\ntype :B={:A 2147483647}\ntype :C={:B 4,:A 8,b 3}\n";
test "aggregate_abi_union compact UINT64_MAX alternatives and distinct checked max round product failures" {
    const good = try std.mem.concat(t.allocator, u8, &.{ huge, "type :U={{:C}{b}}" });
    defer t.allocator.free(good);
    var m = try parse(t.allocator, good);
    defer m.deinit();
    try t.expectEqual(std.math.maxInt(u64), m.types.items[3].size);
    try t.expectEqual(@as(usize, 2), m.types.items[3].runs.len);
    try validation.validate(t.allocator, &m);
    for ([_][]const u8{ "type :U={{:C}{d}}", "type :U={{b}{:C 2}}", "type :U={{b}{b,:C}}" }) |tail| {
        const bad = try std.mem.concat(t.allocator, u8, &.{ huge, tail });
        defer t.allocator.free(bad);
        try t.expectError(error.RecordLayoutOverflow, parse(t.allocator, bad));
    }
}
const owned = "type :U={{s 3}{w}}\ntype :M={{b 17}{d 2}}\nfunction :M $f(:U %u,:M %m,...){\n@e\n%list =l alloc8 24\nvastart %list\n%r =:M call $external(:U %u,:M %m,...,:U %u,d d_1)\nret %r\n}\nfunction w $gap(){\n@e\nret 1\n}\nfunction :U $g(env %e,:U %u){\n@e\n%r =:U call %e(env %e,:U %u)\nret %r\n}";
fn allocationExercise(a: std.mem.Allocator) !void {
    var m = try parse(a, owned);
    defer m.deinit();
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |o| {
        const output = try amd64.emitWithOptions(a, &m, o);
        a.free(output);
    }
}
test "aggregate_abi_union every owned parser variants runs plans objects homes writer failure cleans up" {
    try t.checkAllAllocationFailures(t.allocator, allocationExercise, .{});
}
test "aggregate_abi_union same module emitter allocation retry preserves all variants and balances" {
    var m = try parse(t.allocator, owned);
    defer m.deinit();
    var finished = false;
    for (0..512) |n| {
        var failing = std.testing.FailingAllocator.init(t.allocator, .{ .fail_index = n });
        const out = amd64.emitWithOptions(failing.allocator(), &m, .{ .reuse_stack_homes = true, .callee_saved_homes = true }) catch |err| {
            try t.expectEqual(error.OutOfMemory, err);
            try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
            try validation.validate(t.allocator, &m);
            continue;
        };
        failing.allocator().free(out);
        try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        finished = true;
        break;
    }
    try t.expect(finished);
}
test "aggregate_abi_union source lifetime snapshot and interpreter default guards stay explicit" {
    const text = try t.allocator.dupe(u8, owned);
    var m = try parse(t.allocator, text);
    t.allocator.free(text);
    var p = try planner.FunctionPlan.init(t.allocator, &m, id(0), .{});
    defer p.deinit();
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluate(t.allocator, m.functions.items[0], &.{}, .{ .max_call_depth = 0 }));
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluateModule(t.allocator, &m, id(0), &.{}, .{ .internal_variadic_calls = true, .max_call_depth = 0 }));
    m.deinit();
    try t.expectEqual(@as(u64, 24), p.signature.result.memory.declared_bytes);
}

test "aggregate_abi_union builder copies all alternatives and type names without touching global symbol IDs" {
    var m = Module.init(t.allocator);
    defer m.deinit();
    const global = try m.symbols.intern("OnlyGlobal");
    const byte = records.Field{ .element = .{ .scalar = .byte } };
    const a = try m.addRecord("A", null, &.{byte});
    var first = [_]records.Field{.{ .element = .{ .record = a }, .count = 3 }};
    var second = [_]records.Field{.{ .element = .{ .scalar = .double } }};
    var alternatives = [_][]const records.Field{ &first, &second };
    const name = try t.allocator.dupe(u8, "U");
    const u = try m.addUnion(name, null, &alternatives);
    t.allocator.free(name);
    const stable = m.getRecord(u).?;
    first[0].count = 0;
    second[0].element = .{ .record = u };
    alternatives[0] = &.{};
    try m.validateRecords(t.allocator);
    try t.expectEqual(@as(u64, 8), stable.size);
    try t.expectEqual(@as(u32, 3), stable.runs[0].field.count);
    try t.expectEqualStrings("U", m.record_names.get(stable.name).?);
    for (0..24) |n| {
        var buf: [32]u8 = undefined;
        _ = try m.addRecord(try std.fmt.bufPrint(&buf, "Later{d}", .{n}), null, &.{byte});
    }
    try t.expect(m.getRecord(u).? == stable);
    try t.expectEqual(@as(usize, 1), m.symbols.names.items.len);
    try t.expectEqualStrings("OnlyGlobal", m.symbols.get(global).?);
}
test "aggregate_abi_union every builder allocation failure retains coherent publication and same module retry" {
    var completed = false;
    for (0..64) |index| {
        var failing = std.testing.FailingAllocator.init(t.allocator, .{});
        var m = Module.init(failing.allocator());
        const a = try m.addRecord("A", null, &.{.{ .element = .{ .scalar = .byte } }});
        const g = try m.symbols.intern("OnlyGlobal");
        const old_global_count = m.symbols.names.items.len;
        failing.fail_index = failing.alloc_index + index;
        const result = m.addUnion("U", null, &.{ &.{.{ .element = .{ .record = a }, .count = 3 }}, &.{.{ .element = .{ .scalar = .double } }} });
        if (result) |u| {
            try t.expectEqual(@as(u32, 1), @backingInt(u));
            completed = true;
        } else |err| {
            try t.expectEqual(error.OutOfMemory, err);
            try t.expectEqual(@as(usize, 1), m.types.items.len);
            try t.expect(m.findRecord("U") == null);
            try t.expectEqual(old_global_count, m.symbols.names.items.len);
            try t.expectEqualStrings("OnlyGlobal", m.symbols.get(g).?);
            failing.fail_index = std.math.maxInt(usize);
            try m.validateRecords(t.allocator);
            const retry = try m.addUnion("U", null, &.{ &.{.{ .element = .{ .record = a }, .count = 3 }}, &.{.{ .element = .{ .scalar = .double } }} });
            try t.expectEqual(@as(u32, 1), @backingInt(retry));
        }
        try m.validateRecords(t.allocator);
        try t.expectEqual(old_global_count, m.symbols.names.items.len);
        m.deinit();
        try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        if (completed) break;
    }
    try t.expect(completed);
}
test "aggregate_abi_union parser enforces temporary run and header caps while growing" {
    var input: std.ArrayList(u8) = .empty;
    defer input.deinit(t.allocator);
    try input.appendSlice(t.allocator, "type :U={");
    for (0..records.max_record_runs) |_| try input.appendSlice(t.allocator, "{b}");
    try input.append(t.allocator, '}');
    var good = try parse(t.allocator, input.items);
    defer good.deinit();
    try t.expectEqual(records.max_record_runs, good.types.items[0].variants.len);
    try t.expectEqual(records.max_record_runs, good.types.items[0].runs.len);
    _ = input.pop();
    try input.appendSlice(t.allocator, "{b}}");
    try t.expectError(error.RecordLimitExceeded, parse(t.allocator, input.items));
    input.clearRetainingCapacity();
    try input.appendSlice(t.allocator, "type :U={{");
    for (0..records.max_record_runs) |n| {
        if (n != 0) try input.append(t.allocator, ',');
        try input.append(t.allocator, 'b');
    }
    try input.appendSlice(t.allocator, "}{b}}");
    try t.expectError(error.RecordLimitExceeded, parse(t.allocator, input.items));
}

test "aggregate_abi_union malformed grammar and precise prior refusal positions remain errors" {
    for ([_][]const u8{
        "type :U={{}}",                                                "type :U={{b}{}}",                                              "type :U={{b},{w}}",                "type :U={{b} w}",
        "type :U={b {w}}",                                             "type :U={{{b}}}",                                              "type :U={{:U}{w}}",                "type :U={{:Later}{b}}\ntype :Later={b}",
        "type :U={{b 0}{w}}",                                          "type :U={{b -1}{w}}",                                          "type :U={{b 2147483648}{w}}",      "type :U={{b}{w}}\ntype :U={b}",
        "type :U={{b}{w}}\nfunction $f(){\n@e\n%x =:U copy 0\nret\n}", "type :U={{b}{w}}\nfunction $f(){\n@e\n%x =:U vaarg 0\nret\n}", "type :U={{b}{w}}\ndata $g={:U 0}",
    }) |text| try t.expectError(error.InvalidInput, parse(t.allocator, text));
    for ([_]struct { text: []const u8, token: []const u8, code: @import("source.zig").Diagnostic.Code }{
        .{ .text = "type :U={{b}{:Unknown}}", .token = ":Unknown", .code = .unknown_type },
        .{ .text = "type :U={{b}{w 0}}", .token = "0", .code = .invalid_record_count },
        .{ .text = "type :U={{b}{w}}\ntype :U={{d}{b}}", .token = ":U", .code = .duplicate_type },
    }) |case| {
        var diagnostic: ?@import("source.zig").Diagnostic = null;
        try t.expectError(error.InvalidInput, frontend.parse(t.allocator, .{ .name = "union-error", .text = case.text }, &diagnostic));
        try t.expectEqual(case.code, diagnostic.?.code);
        try t.expectEqualStrings(case.token, case.text[diagnostic.?.span.start..diagnostic.?.span.end]);
    }
}
test "aggregate_abi_union unused last arm alignment partition and repeat caches all recompute" {
    var m = try parse(t.allocator, "type :U={{b 3}{d,w}}\nfunction w $f(){\n@e\nret 7\n}");
    defer m.deinit();
    const u = m.types.items[0];
    const arm = u.variants[1];
    u.variants[1].alignment = 1;
    try t.expectError(error.InvalidRecordLayout, validation.validate(t.allocator, &m));
    u.variants[1] = arm;
    u.variants[1].run_count = 1;
    try t.expectError(error.InvalidRecordLayout, validation.validate(t.allocator, &m));
    u.variants[1] = arm;
    u.variants[1].run_count = 0;
    try t.expectError(error.InvalidRecordLayout, validation.validate(t.allocator, &m));
    u.variants[1] = arm;
    u.variants[1].first_run = 0;
    try t.expectError(error.InvalidRecordLayout, validation.validate(t.allocator, &m));
    u.variants[1] = arm;
    const field = u.runs[2].field;
    u.runs[2].field.count = 0;
    try t.expectError(error.InvalidRecordRepeat, validation.validate(t.allocator, &m));
    u.runs[2].field = field;
    u.size += 8;
    try t.expectError(error.InvalidRecordLayout, validation.validate(t.allocator, &m));
    u.size -= 8;
    u.alignment = 16;
    try t.expectError(error.InvalidRecordLayout, validation.validate(t.allocator, &m));
    u.alignment = 8;
    try validation.validate(t.allocator, &m);
    // Kind is untrusted validation metadata, NOT an ownership discriminator.
    u.kind = .regular;
}
test "aggregate_abi_union literal65536 frame includes176 save plus16 private union object" {
    for ([_]usize{ 8166, 8167 }) |copies| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(t.allocator);
        try text.appendSlice(t.allocator, "type :U=align 16 {{s}{b}}\nfunction :U $f(:U %p,...){\n@e\n%list =l alloc8 24\nvastart %list\n");
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
            try t.expectEqual(@as(u64, 65536), p.frame.bytes);
            try t.expectEqual(@as(u64, 65520), p.frame.variadic_save_end.?);
            try t.expectEqual(@as(u64, 65536), p.parameter_objects[0].end);
        } else try t.expectError(error.FrameTooLarge, planner.FunctionPlan.init(t.allocator, &m, id(0), .{}));
    }
}
test "aggregate_abi_union reached call step budget precedes aggregate refusal not symbol resolution" {
    var m = try parse(t.allocator, "type :U={{s}{w}}\nfunction w $f(){\n@e\n%x =:U call $unresolved(...,:U 0)\nret 0\n}");
    defer m.deinit();
    try t.expectError(error.StepLimitExceeded, interpreter.evaluateModule(t.allocator, &m, id(0), &.{}, .{ .max_steps = 0 }));
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluateModule(t.allocator, &m, id(0), &.{}, .{ .max_steps = 1 }));
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluate(t.allocator, m.functions.items[0], &.{}, .{ .max_steps = 1 }));
}

test "aggregate_abi_union all alternatives consume shared65536 module run budget without name publication" {
    var m = Module.init(t.allocator);
    defer m.deinit();
    const fields = try t.allocator.alloc(records.Field, records.max_record_runs);
    defer t.allocator.free(fields);
    @memset(fields, .{ .element = .{ .scalar = .byte } });
    for (0..16) |n| {
        var buf: [24]u8 = undefined;
        _ = try m.addRecord(try std.fmt.bufPrint(&buf, "R{d}", .{n}), null, fields);
    }
    try t.expectEqual(@as(usize, 16), m.types.items.len);
    const names = m.record_names.names.items.len;
    try t.expectError(error.RecordLimitExceeded, m.addUnion("OverBudget", null, &.{&.{fields[0]}}));
    try t.expectEqual(names, m.record_names.names.items.len);
    try t.expect(m.findRecord("OverBudget") == null);
    // Parser must enforce the remaining module budget BEFORE temporary arm append.
    var input: std.ArrayList(u8) = .empty;
    defer input.deinit(t.allocator);
    for (0..16) |n| {
        var buf: [32]u8 = undefined;
        try input.appendSlice(t.allocator, try std.fmt.bufPrint(&buf, "type :R{d}={{", .{n}));
        for (0..records.max_record_runs) |j| {
            if (j != 0) try input.append(t.allocator, ',');
            try input.append(t.allocator, 'b');
        }
        try input.appendSlice(t.allocator, "}\n");
    }
    try input.appendSlice(t.allocator, "type :U={{b}}\n");
    try t.expectError(error.RecordLimitExceeded, parse(t.allocator, input.items));
}
test "aggregate_abi_union matched scalar comparison first proves exact global IDs and function ordinals" {
    const mixed = @embedFile("fixtures/aggregate_abi_union_mixed.ssa");
    const scalar = @embedFile("fixtures/aggregate_abi_union_scalar_reference.ssa");
    for ([_]bool{ false, true }) |prefix| {
        const texts = [_][]const u8{ mixed, scalar };
        var modules: [2]Module = undefined;
        for (texts, 0..) |text, n| {
            const first = std.mem.indexOf(u8, text, "export function ").?;
            const side = std.mem.indexOf(u8, text, "\nfunction ").? + 1;
            const moved = if (prefix) try std.mem.concat(t.allocator, u8, &.{ text[0..first], text[side..], text[first..side] }) else try t.allocator.dupe(u8, text);
            defer t.allocator.free(moved);
            modules[n] = try parse(t.allocator, moved);
        }
        defer modules[0].deinit();
        defer modules[1].deinit();
        try t.expectEqual(modules[0].symbols.names.items.len, modules[1].symbols.names.items.len);
        for (modules[0].symbols.names.items, modules[1].symbols.names.items) |a, b| try t.expectEqualStrings(a, b);
        try t.expectEqual(modules[0].functions.items.len, modules[1].functions.items.len);
        for (modules[0].functions.items, modules[1].functions.items) |a, b| try t.expectEqual(a.name, b.name);
        try t.expectEqual(records.Kind.union_type, modules[0].types.items[0].kind);
        try t.expectEqual(records.Kind.regular, modules[1].types.items[0].kind);
    }
}

test "aggregate_abi_union SSE exhausted mixed tuple leaves GP for following named long" {
    const text = try std.mem.concat(t.allocator, u8, &.{ declarations, "function :UM $f(d %a,d %b,d %c,d %d,d %e,d %f,d %g,d %h,:U12 %u,l %last,...){\n@e\n%r =:UM call $g(d %a,d %b,d %c,d %d,d %e,d %f,d %g,d %h,:U12 %u,l 77,...,:U8 0,l 99,:UM 0,l 101)\nret %r\n}" });
    defer t.allocator.free(text);
    var m = try parse(t.allocator, text);
    defer m.deinit();
    var p = try planner.FunctionPlan.init(t.allocator, &m, id(0), .{});
    defer p.deinit();
    try t.expectEqual(@as(u8, 2), p.signature.general_used);
    try t.expectEqual(@as(u8, 8), p.signature.vector_used);
    try t.expectEqual(@as(u64, 16), p.signature.stack_bytes);
    try t.expectEqual(@as(u8, 4), p.calls[0].signature.general_used);
    try t.expectEqual(@as(u8, 8), p.calls[0].signature.vector_used);
    try t.expectEqual(@as(u64, 48), p.calls[0].signature.stack_bytes);
}

test "aggregate_abi_union one alternative trailing comma and repeated named union retain padded stride" {
    var m = try parse(t.allocator, "type :One={{b 3,}}\ntype :Many={b,:One 3}\ntype :Outer={{:Many}{h}}\nfunction :Outer $f(:Outer %p){\n@e\nret %p\n}");
    defer m.deinit();
    try t.expectEqual(@as(usize, 1), m.types.items[0].variants.len);
    try t.expectEqual(@as(u64, 3), m.types.items[0].size);
    try t.expectEqual(@as(u64, 1), m.types.items[1].runs[1].offset);
    try t.expectEqual(@as(u64, 3), m.types.items[1].runs[1].stride);
    try t.expectEqual(@as(u32, 3), m.types.items[1].runs[1].field.count);
    try t.expectEqual(@as(u64, 10), m.types.items[1].size);
    try t.expectEqual(@as(u64, 10), m.types.items[2].size);
    try t.expectEqual(@as(u8, 2), m.types.items[2].alignment);
    var p = try planner.FunctionPlan.init(t.allocator, &m, id(0), .{});
    defer p.deinit();
    try t.expectEqual(@as(u8, 2), p.signature.result.integer_record.lane_count);
}
