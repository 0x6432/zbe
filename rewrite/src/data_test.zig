const std = @import("std");
const testing = std.testing;
const data = @import("data.zig");
const module_impl = @import("module.zig");
const frontend = @import("frontend.zig");
const source = @import("source.zig");
const amd64 = @import("amd64.zig");
const validation = @import("module_validation.zig");
const interpreter = @import("interpreter.zig");
const fixture = @embedFile("fixtures/data-oracle.ssa");
const usage =
    \\export function l $data_get() {
    \\@entry
    \\%p =l copy $data_default
    \\%x =l loadl %p
    \\ret %x
    \\}
;
fn parse(allocator: std.mem.Allocator, text: []const u8) !module_impl.Module {
    var diagnostic: ?source.Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "data-test", .text = text }, &diagnostic);
}

// Deliberately independent test encoding, not a production serializer/emitter.
fn expectBytes(object: *const data.Data, hex: []const u8) !void {
    var offset: usize = 0;
    for (object.items.items) |item| {
        const bits: u64 = switch (item) {
            .byte => |x| x,
            .half => |x| x,
            .word => |x| x,
            .long => |x| x,
            .single_bits => |x| x,
            .double_bits => |x| x,
            .zero => 0,
            .symbol_address => return error.UnexpectedRelocationInNumericOracle,
        };
        for (0..item.size()) |i| {
            const actual: u8 = if (item == .zero) 0 else @truncate(bits >> @intCast(i * 8));
            try testing.expect(offset * 2 + 2 <= hex.len);
            const expected = try std.fmt.parseInt(u8, hex[offset * 2 ..][0..2], 16);
            try testing.expectEqual(expected, actual);
            offset += 1;
        }
    }
    try testing.expectEqual(hex.len / 2, offset);
    try testing.expectEqual(offset, try object.validate());
}

test "packed owned data matches independent Python bytes including integer wraps and float bits" {
    var module = try parse(testing.allocator, fixture);
    defer module.deinit();
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/data-oracle.tsv"), '\n');
    var index: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeScalar(u8, line, '\t');
        const name = fields.next().?;
        const alignment = try std.fmt.parseInt(u8, fields.next().?, 10);
        const exported = std.mem.eql(u8, fields.next().?, "1");
        const hex = fields.next().?;
        const object = module.data.items[index];
        try testing.expectEqualStrings(name, module.symbols.get(object.name).?);
        try testing.expectEqual(alignment, object.alignment.bytes());
        try testing.expectEqual(exported, object.linkage == .exported);
        try expectBytes(object, if (std.mem.eql(u8, hex, "-")) "" else hex);
        index += 1;
    }
    try testing.expectEqual(@as(usize, 10), index);
    try validation.validate(testing.allocator, &module);
    var multiline = try parse(testing.allocator, "export\ndata\n$x\n=\nalign\n64\n{\nb\n1\n2,\nz\n0,\n}\n");
    defer multiline.deinit();
    try expectBytes(multiline.data.items[0], "0102");
    try testing.expectEqual(data.Alignment.sixty_four, multiline.data.items[0].alignment);
    // Matching-width literals preserve signed NaNs; payload syntax is still rejected.
    var special = try parse(testing.allocator, "data $x = { s s_-nan, d d_-nan }");
    defer special.deinit();
    try testing.expect(special.data.items[0].items.items[0].single_bits & 0x80000000 != 0);
    try testing.expect(special.data.items[0].items.items[1].double_bits & 0x8000000000000000 != 0);
}

test "data builders reserve atomically and reject object limits before publishing" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    var object = data.Data.init(failing.allocator(), @fromBackingInt(@as(u32, 0)));
    defer object.deinit();
    failing.fail_index = failing.alloc_index;
    try testing.expectError(error.OutOfMemory, object.append(.{ .word = 9 }));
    try testing.expectEqual(@as(usize, 0), object.items.items.len);
    try testing.expectEqual(@as(usize, 0), object.byte_len);
    failing.fail_index = std.math.maxInt(usize);
    try object.append(.{ .zero = data.max_object_bytes });
    try testing.expectError(error.DataTooLarge, object.append(.{ .byte = 1 }));
    try object.append(.{ .zero = 0 });
    try testing.expectEqual(@as(usize, data.max_object_bytes), try object.validate());
    for ([_]u64{ 0, 3, 7, 65, 128, std.math.maxInt(u64) }) |n| try testing.expectError(error.InvalidAlignment, data.Alignment.fromBytes(n));
    for ([_]u64{ 1, 2, 4, 8, 16, 32, 64 }) |n| try testing.expectEqual(n, (try data.Alignment.fromBytes(n)).bytes());
}

fn grow(allocator: std.mem.Allocator) !void {
    var module = module_impl.Module.init(allocator);
    defer module.deinit();
    const id = try module.addData("owned");
    const stable = module.getData(id).?;
    try stable.append(.{ .long = 123 });
    var name: [32]u8 = undefined;
    for (0..40) |n| _ = try module.addData(try std.fmt.bufPrint(&name, "object_{d}", .{n}));
    try testing.expect(stable == module.getData(id).?);
    try testing.expect(module.getData(@fromBackingInt(std.math.maxInt(u32))) == null);
    try testing.expectError(error.DuplicateSymbol, module.addData("owned"));
    try testing.expectError(error.DuplicateSymbol, module.addFunction("owned", null));
    _ = try module.addFunction("function", null);
    try testing.expectError(error.DuplicateSymbol, module.addData("function"));
}

test "data module ownership pointer stability duplicate definitions and exhaustive failure cleanup" {
    try @import("test_support.zig").checkAllocationFailures(grow);
    // Each allocation in addData may fail; no data handle is published, retry works.
    for (0..4) |offset| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
        var module = module_impl.Module.init(failing.allocator());
        defer module.deinit();
        // Intern first so these iterations cover growth table and Data ownership.
        _ = try module.symbols.intern("retry");
        failing.fail_index = failing.alloc_index + offset;
        if (module.addData("retry")) |_| {} else |err| {
            try testing.expectEqual(error.OutOfMemory, err);
            try testing.expectEqual(@as(usize, 0), module.data.items.len);
            failing.fail_index = std.math.maxInt(usize);
            _ = try module.addData("retry");
        }
        try testing.expectEqual(@as(usize, 1), module.data.items.len);
    }
}

test "data parser rejects malformed unsupported and duplicate definitions precisely" {
    for ([_][]const u8{
        "data $x = align 3 { b 1 }",                 "data $x = align 0 { b 1 }",                 "data $x = align -1 { b 1 }",
        "data $x = align 128 { b 1 }",               "data $x = { z -1 }",                        "data $x = { z 4294967296 }",
        "data $x = { z 1 2 }",                       "data $x = { b }",                           "data $x = { b 1,, }",
        "data $x = { b 1 h 2 }",                     "data $x = { w $symbol }",                   "data $x = { h $symbol+8 }",
        "data $x = { b \"text\" }",                  "data $\"quoted\" = {}",                     "thread data $x = {}",
        "section \"a\" data $x = {}",                "data $x = { s d_1 }",                       "data $x = { w s_1 }",
        "data $x = { s 1 }",                         "data $x = { d d_nan(payload) }",            "data $x = {}\ndata $x = {}",
        "data $x = {}\nfunction $x() {\n@e\nret\n}", "function $x() {\n@e\nret\n}\ndata $x = {}", "data $x = { b 1",
        "data $x = { , }",
    }) |text| {
        var diagnostic: ?source.Diagnostic = null;
        if (frontend.parse(testing.allocator, .{ .name = "bad-data", .text = text }, &diagnostic)) |owned| {
            var unexpected = owned;
            unexpected.deinit();
            return error.ExpectedInvalidData;
        } else |err| try testing.expectEqual(error.InvalidInput, err);
        try testing.expect(diagnostic != null);
    }
    try testing.expectError(error.DataTooLarge, parse(testing.allocator, "data $x = { z 16777217 }"));
}

test "module validation rejects tampered data IDs sizes duplicate symbols calls and aggregate limits" {
    var module = try parse(testing.allocator, "data $x = { b 1 }\ndata $y = { b 2 }\n" ++ usage);
    defer module.deinit();
    const object = module.data.items[0];
    const name = object.name;
    object.name = @fromBackingInt(std.math.maxInt(u32));
    try testing.expectError(error.InvalidSymbol, validation.validate(testing.allocator, &module));
    object.name = module.data.items[1].name;
    try testing.expectError(error.DuplicateSymbol, validation.validate(testing.allocator, &module));
    object.name = module.functions.items[0].name;
    try testing.expectError(error.DuplicateSymbol, validation.validate(testing.allocator, &module));
    object.name = try module.symbols.intern("bad\n.globl injected");
    try testing.expectError(error.InvalidSymbol, amd64.emit(testing.allocator, &module));
    object.name = name;
    object.byte_len = 2;
    try testing.expectError(error.InvalidDataSize, amd64.emit(testing.allocator, &module));
    object.byte_len = 1;
    object.items.items[0] = .{ .zero = data.max_object_bytes + 1 };
    try testing.expectError(error.DataTooLarge, amd64.emit(testing.allocator, &module));
    var capped = try parse(testing.allocator, "data $a = { z 16777216 }\ndata $b = { z 16777216 }\ndata $c = { z 16777216 }\ndata $d = { z 16777216 }");
    defer capped.deinit();
    try testing.expectEqual(@as(usize, data.max_module_bytes), try capped.dataSize());
    const cap_assembly = try amd64.emit(testing.allocator, &capped);
    defer testing.allocator.free(cap_assembly);
    try testing.expectEqual(@as(usize, 4), std.mem.count(u8, cap_assembly, "\t.zero 16777216\n"));
    const id = try capped.addData("over");
    try capped.getData(id).?.append(.{ .byte = 1 });
    try testing.expectError(error.DataTooLarge, validation.validate(testing.allocator, &capped));
    var called = try parse(testing.allocator, "data $x = {}\nfunction $f() {\n@e\ncall $x()\nret\n}");
    defer called.deinit();
    try testing.expectError(error.CalledDataSymbol, amd64.emit(testing.allocator, &called));
}

test "data does not fabricate interpreter globals and prior Image writes survive refusal" {
    var module = try parse(testing.allocator, "data $x = { w 123 }\nfunction w $f(w %c) {\n@e\njnz %c, @use, @safe\n@safe\nret 9\n@use\nstoreb 42, 8192\n%p =l copy $x\nret 0\n}");
    defer module.deinit();
    var image = try @import("memory.zig").Image.init(testing.allocator, 8, .{ .base = 8192 });
    defer image.deinit();
    const entry: module_impl.FunctionId = @fromBackingInt(@as(u32, 0));
    try testing.expectEqual(@as(u32, 9), (try interpreter.evaluateModule(testing.allocator, &module, entry, &.{.{ .word = 0 }}, .{})).?.word);
    try testing.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(testing.allocator, &module, entry, &.{.{ .word = 1 }}, .{ .memory_image = &image, .stack_memory = .{} }));
    try testing.expectEqual(@as(u8, 42), image.bytes[0]);
    try testing.expectError(error.StepLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, entry, &.{.{ .word = 1 }}, .{ .memory_image = &image, .max_steps = 2 }));
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, fixture ++ "\n" ++ usage);
    defer module.deinit();
    _ = try @import("optimize.zig").foldIntegerConstants(allocator, module.functions.items[0]);
    for ([_]amd64.Options{ .{}, .{ .reuse_stack_homes = true }, .{ .callee_saved_homes = true }, .{ .reuse_stack_homes = true, .callee_saved_homes = true } }) |options| {
        const assembly = try amd64.emitWithOptions(allocator, &module, options);
        defer allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, ".balign 64\n.globl data_oracle_6\n.type data_oracle_6, @object") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "\t.quad 18446744073709551615") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, ".size data_empty, .-data_empty") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, ".globl data_oracle_1") == null);
        try testing.expect(std.mem.indexOf(u8, assembly, "leaq data_default(%rip)") != null);
    }
}
fn malformed(allocator: std.mem.Allocator) !void {
    if (parse(allocator, "data $x = { b 1 2, h 3, z 2 }\ndata $bad = { l 1, s s_2, d $unsupported }")) |owned| {
        var unexpected = owned;
        unexpected.deinit();
        return error.ExpectedInvalidData;
    } else |err| if (err != error.InvalidInput) return err;
}

test "mixed data parser folding emission and partial parse exhaustively clean all allocation failures" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
    try @import("test_support.zig").checkAllocationFailures(malformed);
}
