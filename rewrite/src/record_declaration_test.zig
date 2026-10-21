const std = @import("std");
const testing = std.testing;
const records = @import("record_declaration.zig");
const Module = @import("module.zig").Module;
const frontend = @import("frontend.zig");
const interpreter = @import("interpreter.zig");
const amd64 = @import("amd64.zig");
const validation = @import("module_validation.zig");
const layout_source = @embedFile("fixtures/record_declaration_layouts.ssa");
const scalar_source = @embedFile("fixtures/record_declaration_scalar.ssa");
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "record_declaration", .text = text }, &diagnostic);
}
fn scalar(c: u8) records.Scalar {
    return switch (c) {
        'b' => .byte,
        'h' => .half,
        'w' => .word,
        'l' => .long,
        's' => .single,
        'd' => .double,
        else => unreachable,
    };
}
fn integer(text: []const u8) !u64 {
    return std.fmt.parseInt(u64, text, 10);
}
const byte_field: records.Field = .{ .element = .{ .scalar = .byte } };

test "record_declaration 271 independent layouts include all scalar fields nested strides and UINT64_MAX" {
    var module = try parse(testing.allocator, layout_source);
    defer module.deinit();
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/record_declaration_oracle.tsv"), '\n');
    var types: usize = 0;
    var runs: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const kind = fields.next().?;
        const name = fields.next().?;
        const id = module.findRecord(name).?;
        const record = module.getRecord(id).?;
        if (kind[0] == 'T') {
            const explicit = try integer(fields.next().?);
            try testing.expectEqual(if (explicit == 0) @as(?u8, null) else @as(u8, @intCast(explicit)), record.explicit_alignment);
            try testing.expectEqual(try integer(fields.next().?), record.alignment);
            try testing.expectEqual(try integer(fields.next().?), record.size);
            try testing.expectEqual(try integer(fields.next().?), record.runs.len);
            types += 1;
        } else {
            const index: usize = @intCast(try integer(fields.next().?));
            const member = fields.next().?;
            const run = record.runs[index];
            if (member[0] == ':') {
                try testing.expectEqual(module.findRecord(member[1..]).?, run.field.element.record);
                try testing.expect(@backingInt(run.field.element.record) < @backingInt(id));
            } else try testing.expectEqual(scalar(member[0]), run.field.element.scalar);
            try testing.expectEqual(try integer(fields.next().?), run.field.count);
            try testing.expectEqual(try integer(fields.next().?), run.offset);
            try testing.expectEqual(try integer(fields.next().?), run.stride);
            runs += 1;
        }
        try testing.expect(fields.next() == null);
    }
    try testing.expectEqual(@as(usize, 271), types);
    try testing.expectEqual(module.types.items.len, types);
    try testing.expect(runs > types);
    const extreme = module.getRecord(module.findRecord("ExtremeC").?).?;
    try testing.expectEqual(std.math.maxInt(u64), extreme.size);
    try testing.expectEqual(@as(usize, 3), extreme.runs.len);
    try module.validateRecords(testing.allocator);
}

test "record_declaration record namespace remains separate from functions and data" {
    var module = try parse(testing.allocator, "# names, source order and CRLF\r\ntype :T = { b, w, }\r\nfunction l $T(l %x) {\r\n@e\r\nret %x\r\n}\r\ndata $D = { w 73 }\r\ntype :D = { :T 2, h }\r\n");
    defer module.deinit();
    try testing.expectEqualStrings(module.record_names.get(module.types.items[0].name).?, module.symbols.get(module.functions.items[0].name).?);
    try testing.expectEqualStrings(module.record_names.get(module.types.items[1].name).?, module.symbols.get(module.data.items[0].name).?);
    try validation.validate(testing.allocator, &module);
    try testing.expectEqual(@as(u64, 91), (try interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 0)), &.{.{ .long = 91 }}, .{})).?.long);
    try testing.expectError(error.DuplicateType, module.addRecord("T", null, &.{byte_field}));
    try testing.expectError(error.DuplicateSymbol, module.addData("T"));
    // Numeric ordinals carry no cross-pool provenance. Prior globals must
    // neither consume type-name slots nor become available record names.
    var interleaved = try parse(testing.allocator, "data $OnlyGlobal = { b 0 }\ntype :First = { w }\ntype :Second = { :First 2 }");
    defer interleaved.deinit();
    const first = interleaved.findRecord("First").?;
    try testing.expectEqual(@as(usize, 1), interleaved.symbols.names.items.len);
    try testing.expectEqual(@as(usize, 2), interleaved.record_names.names.items.len);
    try testing.expectEqualStrings("OnlyGlobal", interleaved.symbols.names.items[0]);
    try testing.expectEqualStrings("First", interleaved.record_names.get(interleaved.getRecord(first).?.name).?);
    try testing.expectEqual(first, interleaved.types.items[1].runs[0].field.element.record);
    for ([_][]const u8{
        "data $OnlyGlobal = { b 0 }\ntype :Actual = { b }\ntype :Bad = { :OnlyGlobal }",
        "function $OnlyGlobal() {\n@e\nret\n}\ntype :Actual = { w }\ntype :Bad = { :OnlyGlobal }",
    }) |text| try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
}

test "record_declaration valid unused records leave scalar assembly byte identical in all eight modes" {
    const combined = try std.mem.concat(testing.allocator, u8, &.{ layout_source, scalar_source });
    defer testing.allocator.free(combined);
    var baseline = try parse(testing.allocator, scalar_source);
    defer baseline.deinit();
    var module = try parse(testing.allocator, combined);
    defer module.deinit();
    for (0..8) |mask| {
        if (mask & 1 != 0) {
            for (baseline.functions.items) |f| _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
            for (module.functions.items) |f| _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
        }
        const options: amd64.Options = .{ .reuse_stack_homes = mask & 2 != 0, .callee_saved_homes = mask & 4 != 0 };
        const before = try amd64.emitWithOptions(testing.allocator, &baseline, options);
        defer testing.allocator.free(before);
        const after = try amd64.emitWithOptions(testing.allocator, &module, options);
        defer testing.allocator.free(after);
        try testing.expectEqualStrings(before, after);
    }
    try testing.expectEqual(@as(u64, 0x8000000000000000 ^ 123456789 ^ 45), (try interpreter.evaluateModule(testing.allocator, &module, @fromBackingInt(@as(u32, 1)), &.{}, .{})).?.long);
    var only_types = try parse(testing.allocator, layout_source);
    defer only_types.deinit();
    var empty = Module.init(testing.allocator);
    defer empty.deinit();
    const a = try amd64.emit(testing.allocator, &only_types);
    defer testing.allocator.free(a);
    const b = try amd64.emit(testing.allocator, &empty);
    defer testing.allocator.free(b);
    try testing.expectEqualStrings(a, b);
}

const extremes = "type :A = { b 2147483647 }\ntype :B = { :A 2147483647 }\ntype :C = { :B 4, :A 8, b 3 }\n";
test "record_declaration product cursor member-alignment and final-round overflow are checked separately" {
    var module = try parse(testing.allocator, extremes);
    defer module.deinit();
    try testing.expectEqual(std.math.maxInt(u64), module.types.items[2].size);
    for ([_][]const u8{
        "type :Overflow = { :C 2 }", // product
        "type :Overflow = { b, :C }", // cursor addition
        "type :Overflow = { :C, w }", // align member cursor
        "type :Overflow = align 64 { :B 4, :A 8, b 3 }", // final rounding
    }) |suffix| {
        const text = try std.mem.concat(testing.allocator, u8, &.{ extremes, suffix });
        defer testing.allocator.free(text);
        try testing.expectError(error.RecordLayoutOverflow, parse(testing.allocator, text));
    }
}

test "record_declaration former union refusal now owns complete alternatives and scalar identity" {
    var m = try parse(testing.allocator, "type :U = { { b } { w } }");
    defer m.deinit();
    try testing.expectEqual(@as(u64, 4), m.types.items[0].size);
    try testing.expectEqual(@as(u8, 4), m.types.items[0].alignment);
    try testing.expectEqual(@import("record_declaration.zig").Kind.union_type, m.types.items[0].kind);
    try testing.expectEqual(@as(usize, 2), m.types.items[0].variants.len);
    for (m.types.items[0].runs) |run| try testing.expectEqual(@as(u64, 0), run.offset);
}

test "record_declaration unsupported forms aggregate-use positions and bad counts remain refusals" {
    for ([_][]const u8{
        "type :Opaque = align 16 { 32 }",
        "type :Empty = {}",
        "type :T = { b 0 }",
        "type :T = { b -1 }",
        "type :T = { b 2147483648 }",
        "type :T = { b 18446744073709551616 }",
        "type :T = align 0 { b }",
        "type :T = align 3 { b }",
        "type :T = align 128 { b }",
        "type :T = { sb }",
        "type :T = { :T }",
        "type :T = { :Later }\ntype :Later = { w }",
        "type :A = { :B }\ntype :B = { :A }",
        "type :T = { w }\ntype :T = { b }",
        "export type :T = { b }",
        "type :T = { w }\nfunction :T $f() {\n@e\nret\n}",
        "type :T = { w }\nfunction $f() {\n@e\n%x =:T copy 0\nret\n}",
        "type :T = { w }\nfunction l $f() {\n@e\n%x =l copy :T\nret %x\n}",
        "type :T = { w }\nfunction l $f() {\n@e\nret :T\n}",
        "type :T = { w }\nfunction l $f() {\n@e\njmp @b\n@b\n%x =l phi @e :T\nret %x\n}",
        "type :T = { w }\ndata $x = { :T 0 }",
    }) |text| try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
    for ([_]struct { text: []const u8, code: @import("source.zig").Diagnostic.Code, token: []const u8 }{
        .{ .text = "type :T = { :Missing }", .code = .unknown_type, .token = ":Missing" },
        .{ .text = "type :T = { b 0 }", .code = .invalid_record_count, .token = "0" },
        .{ .text = "type :T = { b }\ntype :T = { w }", .code = .duplicate_type, .token = ":T" },
    }) |case| {
        var diagnostic: ?@import("source.zig").Diagnostic = null;
        try testing.expectError(error.InvalidInput, frontend.parse(testing.allocator, .{ .name = "bad-record", .text = case.text }, &diagnostic));
        try testing.expectEqual(case.code, diagnostic.?.code);
        try testing.expectEqualStrings(case.token, case.text[diagnostic.?.span.start..diagnostic.?.span.end]);
    }
}

fn rejectedModule(module: *Module, expected: anyerror) !void {
    try testing.expectError(expected, module.validateRecords(testing.allocator));
    try testing.expectError(expected, validation.validate(testing.allocator, module));
    try testing.expectError(expected, amd64.emit(testing.allocator, module));
    try testing.expectError(expected, interpreter.evaluateModule(testing.allocator, module, @fromBackingInt(@as(u32, 0)), &.{}, .{}));
    // Standalone functions have no hidden owner/backpointer/global type table.
    try testing.expectEqual(@as(u32, 42), (try interpreter.evaluate(testing.allocator, module.functions.items[0], &.{}, .{})).?.word);
}

test "record_declaration ALL unused cached metadata is revalidated but detached functions stay scalar" {
    var module = try parse(testing.allocator, "type :Pair = { b, w }\ntype :Packet = { :Pair 2, h }\nfunction w $f() {\n@e\nret 42\n}");
    defer module.deinit();
    const pair = module.types.items[0];
    const packet = module.types.items[1];
    for (0..13) |mutation| {
        const saved_pair = pair.*;
        const saved_packet = packet.*;
        const saved_run = pair.runs[0];
        const saved_child = packet.runs[0];
        defer {
            pair.* = saved_pair;
            packet.* = saved_packet;
            pair.runs[0] = saved_run;
            packet.runs[0] = saved_child;
        }
        const expected: anyerror = switch (mutation) {
            0 => change: {
                pair.size += 1;
                break :change error.InvalidRecordLayout;
            },
            1 => change: {
                pair.alignment = 1;
                break :change error.InvalidRecordLayout;
            },
            2 => change: {
                pair.explicit_alignment = 3;
                break :change error.InvalidRecordAlignment;
            },
            3 => change: {
                pair.runs[0].offset = 1;
                break :change error.InvalidRecordLayout;
            },
            4 => change: {
                pair.runs[0].stride = 2;
                break :change error.InvalidRecordLayout;
            },
            5 => change: {
                pair.runs[0].field.count = 0;
                break :change error.InvalidRecordRepeat;
            },
            6 => change: {
                pair.runs[0].field.count = records.max_repeat + 1;
                break :change error.InvalidRecordRepeat;
            },
            7 => change: {
                pair.runs[0].field.element = .{ .record = @fromBackingInt(@as(u32, 1)) };
                break :change error.InvalidRecordReference;
            },
            8 => change: {
                packet.runs[0].field.element = .{ .record = @fromBackingInt(@as(u32, 1)) };
                break :change error.InvalidRecordReference;
            },
            9 => change: {
                packet.name = pair.name;
                break :change error.DuplicateType;
            },
            10 => change: {
                pair.name = @fromBackingInt(std.math.maxInt(u32));
                break :change error.InvalidRecordName;
            },
            11 => change: {
                pair.runs = pair.runs[0..0];
                break :change error.InvalidRecordLayout;
            },
            12 => change: {
                packet.runs[0].offset = 4;
                break :change error.InvalidRecordLayout;
            },
            else => unreachable,
        };
        try rejectedModule(&module, expected);
    }
    try validation.validate(testing.allocator, &module);
}

test "record_declaration owned source fields names and record pointers survive growth" {
    const source = try testing.allocator.dupe(u8, "type :Owned = { b, w }\ntype :Child = { :Owned 2, h }");
    var module = parse(testing.allocator, source) catch |err| {
        testing.allocator.free(source);
        return err;
    };
    defer module.deinit();
    @memset(source, 0xa5);
    testing.allocator.free(source);
    const stable = module.types.items[0];
    const name = module.record_names.get(stable.name).?;
    var fields = [_]records.Field{byte_field};
    var buffer: [64]u8 = undefined;
    for (0..96) |index| _ = try module.addRecord(try std.fmt.bufPrint(&buffer, "More{d}", .{index}), null, &fields);
    fields[0].count = 42;
    try testing.expect(stable == module.getRecord(module.findRecord("Owned").?).?);
    try testing.expectEqualStrings("Owned", name);
    try testing.expect(name.ptr == module.record_names.get(stable.name).?.ptr);
    try testing.expectEqual(@as(u32, 1), module.types.items[2].runs[0].field.count);
    try testing.expectEqual(@as(u64, 20), module.types.items[1].size);
    try testing.expect(module.getRecord(@fromBackingInt(std.math.maxInt(u32))) == null);
    try module.validateRecords(testing.allocator);
}

test "record_declaration every builder failure retries without partial ID lookup or run accounting" {
    var completed = false;
    for (0..64) |failure| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
        var module = Module.init(failing.allocator());
        defer module.deinit();
        try seedGlobalNames(&module);
        const parent = try module.addRecord("Parent", null, &.{byte_field});
        const stable = module.getRecord(parent).?;
        // Force publication to cross a type-table growth boundary, not merely
        // allocate field/name storage into an already-reserved handle table.
        var name_buffer: [64]u8 = undefined;
        while (module.types.items.len < module.types.capacity) {
            _ = try module.addRecord(try std.fmt.bufPrint(&name_buffer, "Padding{d}", .{module.types.items.len}), null, &.{byte_field});
        }
        try expectGlobalNames(&module);
        const previous_count = module.types.items.len;
        failing.fail_index = failing.alloc_index + failure;
        const fields = &[_]records.Field{.{ .element = .{ .record = parent }, .count = 2 }};
        if (module.addRecord("Child", 16, fields)) |id| {
            try testing.expectEqual(@as(u32, @intCast(previous_count)), @backingInt(id));
            try expectGlobalNames(&module);
            completed = true;
            break;
        } else |err| {
            try testing.expectEqual(error.OutOfMemory, err);
            try expectGlobalNames(&module);
            try testing.expectEqual(previous_count, module.types.items.len);
            try testing.expect(module.findRecord("Child") == null);
            try testing.expect(stable == module.getRecord(parent).?);
            failing.fail_index = std.math.maxInt(usize);
            try module.validateRecords(testing.allocator);
            const id = try module.addRecord("Child", 16, fields);
            try testing.expectEqual(@as(u32, @intCast(previous_count)), @backingInt(id));
            try testing.expectEqual(@as(u64, 16), module.getRecord(id).?.size);
            try testing.expectEqual(previous_count + 1, module.types.items.len);
            try expectGlobalNames(&module);
        }
    }
    try testing.expect(completed);
}

test "record_declaration exact metadata caps count runs not repeated conceptual bytes" {
    var module = Module.init(testing.allocator);
    defer module.deinit();
    const fields = try testing.allocator.alloc(records.Field, records.max_record_runs + 1);
    defer testing.allocator.free(fields);
    @memset(fields, byte_field);
    try testing.expectError(error.RecordLimitExceeded, module.addRecord("TooManyRuns", null, fields));
    var buffer: [64]u8 = undefined;
    for (0..16) |index| _ = try module.addRecord(try std.fmt.bufPrint(&buffer, "Record{d}", .{index}), null, fields[0..records.max_record_runs]);
    try module.validateRecords(testing.allocator);
    try testing.expectError(error.RecordLimitExceeded, module.addRecord("OneRunTooFar", null, &.{byte_field}));
    try testing.expect(module.findRecord("OneRunTooFar") == null);
    var many = Module.init(testing.allocator);
    defer many.deinit();
    for (0..records.max_records) |index| _ = try many.addRecord(try std.fmt.bufPrint(&buffer, "Type{d}", .{index}), null, &.{byte_field});
    try many.validateRecords(testing.allocator);
    try testing.expectError(error.RecordLimitExceeded, many.addRecord("OneTypeTooFar", null, &.{byte_field}));
    try testing.expectEqual(@as(usize, records.max_records), many.types.items.len);
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, "type :Pair = { b, w }\ntype :Packet = align 16 { :Pair 2, h }\nfunction l $f(l %x) {\n@e\nret %x\n}");
    defer module.deinit();
    try module.validateRecords(allocator);
    try testing.expectEqual(@as(u64, 32), module.types.items[1].size);
    try testing.expectEqual(@as(u64, 73), (try interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 0)), &.{.{ .long = 73 }}, .{})).?.long);
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true } }) |options| {
        const output = try amd64.emitWithOptions(allocator, &module, options);
        defer allocator.free(output);
        try testing.expect(std.mem.indexOf(u8, output, "Pair") == null);
    }
    // Exhaust failure cleanup on a late parser refusal after earlier records
    // have been published, not only on the successful construction path.
    if (parse(allocator, "type :A = { b, w }\ntype :B = { :A 2, h }\ntype :Bad = { b, :Missing }")) |unexpected| {
        var owned = unexpected;
        owned.deinit();
        return error.ExpectedRecordRefusal;
    } else |err| {
        if (err != error.InvalidInput) return err;
    }
    const saved_size = module.types.items[0].size;
    module.types.items[0].size += 1;
    defer module.types.items[0].size = saved_size;
    // Validator scratch also cleans up when an unused layout is invalid.
    if (validation.validate(allocator, &module)) |_| {
        return error.ExpectedRecordRefusal;
    } else |err| {
        if (err != error.InvalidRecordLayout) return err;
    }
}

test "record_declaration every parse owned layout module evaluation and emission allocation failure cleans up" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

fn expectGlobalNames(module: *const Module) !void {
    const expected = [_][]const u8{ "GlobalFirst", "Parent", "GlobalLast" };
    try testing.expectEqual(expected.len, module.symbols.names.items.len);
    for (expected, 0..) |name, index| {
        try testing.expectEqualStrings(name, module.symbols.names.items[index]);
        try testing.expectEqual(@as(u32, @intCast(index)), @backingInt(module.symbols.index.get(name).?));
    }
}
fn seedGlobalNames(module: *Module) !void {
    for ([_][]const u8{ "GlobalFirst", "Parent", "GlobalLast" }) |name| _ = try module.symbols.intern(name);
}

test "record_declaration name pool first publication OOM retry never touches global names" {
    var completed = false;
    for (0..32) |failure| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
        var module = Module.init(failing.allocator());
        defer module.deinit();
        try seedGlobalNames(&module);
        const stable_global = module.symbols.names.items[1];
        failing.fail_index = failing.alloc_index + failure;
        if (module.addRecord("Parent", null, &.{byte_field})) |id| {
            try testing.expectEqual(@as(u32, 0), @backingInt(id));
            completed = true;
        } else |err| {
            try testing.expectEqual(error.OutOfMemory, err);
            try testing.expectEqual(@as(usize, 0), module.types.items.len);
            try testing.expect(module.findRecord("Parent") == null);
            try expectGlobalNames(&module);
            failing.fail_index = std.math.maxInt(usize);
            try module.validateRecords(testing.allocator);
            try testing.expectEqual(@as(u32, 0), @backingInt(try module.addRecord("Parent", null, &.{byte_field})));
        }
        try expectGlobalNames(&module);
        try testing.expect(stable_global.ptr == module.symbols.names.items[1].ptr);
        try testing.expect(stable_global.ptr != module.record_names.get(module.types.items[0].name).?.ptr);
        try module.validateRecords(testing.allocator);
        if (completed) break;
    }
    try testing.expect(completed);
}

test "record_declaration global name ordinal cannot validate invalid unused record name" {
    var module = try parse(testing.allocator, "type :Only = { b }\ndata $Global = { b 0 }\nfunction w $f() {\n@e\nret 42\n}");
    defer module.deinit();
    const global_id = module.functions.items[0].name;
    try testing.expectEqualStrings("f", module.symbols.get(global_id).?);
    try testing.expect(module.record_names.get(global_id) == null);
    const saved = module.types.items[0].name;
    module.types.items[0].name = global_id;
    try rejectedModule(&module, error.InvalidRecordName);
    module.types.items[0].name = saved;
    try validation.validate(testing.allocator, &module);
}

test "record_declaration full alias assembly and global ordering remain identical all eight modes" {
    const alias_source = @embedFile("fixtures/record_declaration_symbol_identity.ssa");
    const declarations = "type :Unused = { b }\ntype :T = { w }\ntype :Normal = { :Unused 3 }\n";
    for ([_]bool{ false, true }) |prefix| {
        const combined = try std.mem.concat(testing.allocator, u8, if (prefix) &.{ declarations, alias_source } else &.{ alias_source, declarations });
        defer testing.allocator.free(combined);
        var baseline = try parse(testing.allocator, alias_source);
        defer baseline.deinit();
        var module = try parse(testing.allocator, combined);
        defer module.deinit();
        try testing.expectEqual(baseline.symbols.names.items.len, module.symbols.names.items.len);
        for (baseline.symbols.names.items, module.symbols.names.items, 0..) |before, after, index| {
            try testing.expectEqualStrings(before, after);
            try testing.expectEqual(@as(u32, @intCast(index)), @backingInt(module.symbols.index.get(before).?));
        }
        for (0..8) |mask| {
            if (mask & 1 != 0) {
                for (baseline.functions.items) |f| _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
                for (module.functions.items) |f| _ = try @import("optimize.zig").foldIntegerConstants(testing.allocator, f);
            }
            const options: amd64.Options = .{ .reuse_stack_homes = mask & 2 != 0, .callee_saved_homes = mask & 4 != 0 };
            const before = try amd64.emitWithOptions(testing.allocator, &baseline, options);
            defer testing.allocator.free(before);
            const after = try amd64.emitWithOptions(testing.allocator, &module, options);
            defer testing.allocator.free(after);
            try testing.expect(std.mem.indexOf(u8, before, ".Lzbe@common") != null);
            try testing.expect(std.mem.indexOf(u8, before, ".set \".Lzbe@s") != null);
            try testing.expectEqualStrings(before, after);
        }
    }
}
