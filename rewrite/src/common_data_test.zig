const std = @import("std");
const testing = std.testing;
const data = @import("data.zig");
const Module = @import("module.zig").Module;
const interpreter = @import("interpreter.zig");
const amd64 = @import("amd64.zig");
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return @import("frontend.zig").parse(allocator, .{ .name = "common-data", .text = text }, &diagnostic);
}
fn entry() @import("module.zig").FunctionId {
    return @fromBackingInt(@as(u32, 0));
}

test "common and export flags are independent with exact explicit alignment and compact comm emission" {
    for ([_][]const u8{ "common", "export common", "common export", "common\nexport\n" }) |prefix| {
        const text = try std.fmt.allocPrint(testing.allocator, "{s} data $item = {{ z 0, z 17, z 0 }}\ncommon data $empty = {{}}\ncommon data $\"quoted object\" = align 64 {{ z 0 }}", .{prefix});
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        try testing.expect(module.data.items[0].common);
        try testing.expectEqual(std.mem.indexOf(u8, prefix, "export") != null, module.data.items[0].linkage == .exported);
        try testing.expectEqual(@as(usize, 17), try module.data.items[0].validate());
        const assembly = try amd64.emit(testing.allocator, &module);
        defer testing.allocator.free(assembly);
        try testing.expect(std.mem.indexOf(u8, assembly, ".comm item,17,8\n") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, ".comm empty,0,8\n") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, ".comm \"quoted object\",0,64\n") != null);
        try testing.expect(std.mem.indexOf(u8, assembly, "item:") == null);
        try testing.expect(std.mem.indexOf(u8, assembly, ".size item") == null);
        try testing.expect(std.mem.indexOf(u8, assembly, ".globl item") == null);
    }
    for ([_]u8{ 1, 2, 4, 8, 16, 32, 64 }) |alignment| {
        const text = try std.fmt.allocPrint(testing.allocator, "common data $item = align {d} {{ z 1 }}", .{alignment});
        defer testing.allocator.free(text);
        var module = try parse(testing.allocator, text);
        defer module.deinit();
        try testing.expectEqual(alignment, module.data.items[0].alignment.bytes());
    }
}

test "common rejects all non-z initializers including raw zero and empty strings plus invalid linkage syntax" {
    for ([_][]const u8{ "b 0", "h 0", "w 0", "l 0", "s s_0", "d d_0", "b \"\"", "b \"x\"", "l $other+0", "z 0, w 0", "z -1", "z 4294967296", "z 1 2" }) |body| {
        const text = try std.fmt.allocPrint(testing.allocator, "common data $item = {{ {s} }}", .{body});
        defer testing.allocator.free(text);
        try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
    }
    for ([_][]const u8{
        "common common data $x = {}",            "export common export data $x = {}",              "common function $x() {\n@e\nret\n}",
        "common thread data $x = {}",            "thread common data $x = {}",                     "section \".data\" common data $x = {}",
        "common section \".data\" data $x = {}", "common data $x = align 0 {}",                    "common data $x = align 3 {}",
        "common data $x = align 63 {}",          "common data $x = align 65 {}",                   "common data $x = align 128 {}",
        "common data $x = align -1 {}",          "common data $x = align 18446744073709551616 {}",
    }) |text| try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
}

test "same-module common symbols never coalesce and canonical duplicate definitions stay rejected" {
    for ([_][]const u8{ "common data $x = { z 1 }", "data $x = { b 1 }", "function $x() {\n@e\nret\n}", "common data $\"x\" = {}" }) |other| for ([_]bool{ false, true }) |reverse| {
        const text = try std.fmt.allocPrint(testing.allocator, "{s}\n{s}", .{ if (reverse) other else "common data $x = {}", if (reverse) "common data $x = {}" else other });
        defer testing.allocator.free(text);
        try testing.expectError(error.InvalidInput, parse(testing.allocator, text));
    };
}

test "common append refuses before allocation or publication and public validation catches mutated typed zeros" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{});
    var object = data.Data.init(failing.allocator(), @fromBackingInt(@as(u32, 0)));
    defer object.deinit();
    object.common = true;
    const before = failing.alloc_index;
    try testing.expectError(error.InvalidCommonInitializer, object.append(.{ .bytes = "" }));
    try testing.expectError(error.InvalidCommonInitializer, object.append(.{ .word = 0 }));
    try testing.expectEqual(before, failing.alloc_index);
    try testing.expectEqual(@as(usize, 0), object.byte_len);
    failing.fail_index = failing.alloc_index;
    try testing.expectError(error.OutOfMemory, object.append(.{ .zero = 4 }));
    try testing.expectEqual(@as(usize, 0), object.items.items.len);
    failing.fail_index = std.math.maxInt(usize);
    try object.append(.{ .zero = 4 });
    try testing.expectEqual(@as(usize, 4), try object.validate());
    object.items.items[0] = .{ .word = 0 };
    try testing.expectError(error.InvalidCommonInitializer, object.validate());
    object.items.items[0] = .{ .zero = 4 };
    object.byte_len = 3;
    try testing.expectError(error.InvalidDataSize, object.validate());
    object.byte_len = 4;
    try testing.expectError(error.DataTooLarge, object.append(.{ .zero = data.max_object_bytes }));
    try testing.expectEqual(@as(usize, 4), try object.validate());
    var module = try parse(testing.allocator, "data $zero = { w 0 }\nfunction $entry() {\n@e\nret\n}");
    defer module.deinit();
    module.data.items[0].common = true;
    try testing.expectError(error.InvalidCommonInitializer, amd64.emit(testing.allocator, &module));
    try testing.expectError(error.InvalidCommonInitializer, interpreter.evaluateModule(testing.allocator, &module, entry(), &.{}, .{}));
}

test "common object and module caps remain exact with no payload-sized assembly allocation" {
    var module = try parse(testing.allocator, "common data $a = { z 16777216 }\ncommon data $b = { z 16777216 }\ncommon data $c = { z 16777216 }\ncommon data $d = { z 16777216 }");
    defer module.deinit();
    try testing.expectEqual(@as(usize, 67108864), try module.dataSize());
    const assembly = try amd64.emit(testing.allocator, &module);
    defer testing.allocator.free(assembly);
    try testing.expect(assembly.len < 1024);
    const extra = try module.addData("extra");
    module.getData(extra).?.common = true;
    try module.getData(extra).?.append(.{ .zero = 1 });
    try testing.expectError(error.DataTooLarge, module.dataSize());
    try testing.expectError(error.DataTooLarge, parse(testing.allocator, "common data $a = { z 16777217 }"));
}

const global_source = "common data $object = align 64 { z 8 }\nfunction l $entry(l %value) {\n@e\n%old =l loadl $object\nstorel %value, $object\nret %old\n}\n";
test "common synthetic globals are fresh per module evaluation not host linker storage" {
    var module = try parse(testing.allocator, global_source);
    defer module.deinit();
    for ([_]std.builtin.Endian{ .little, .big }) |endian| for (0..2) |_| {
        try testing.expectEqual(@as(u64, 0), (try interpreter.evaluateModule(testing.allocator, &module, entry(), &.{.{ .long = 99 }}, .{ .global_memory = .{ .endian = endian, .max_bytes = 24 } })).?.long);
    };
    try testing.expectError(error.UnsupportedSymbolAddress, interpreter.evaluateModule(testing.allocator, &module, entry(), &.{.{ .long = 99 }}, .{}));
    try testing.expectError(error.GlobalLimitExceeded, interpreter.evaluateModule(testing.allocator, &module, entry(), &.{.{ .long = 99 }}, .{ .global_memory = .{ .max_bytes = 23 } }));
    try testing.expectEqual(@as(u32, 8), module.data.items[0].items.items[0].zero);
    var empty = try parse(testing.allocator, "common data $empty = {}\nfunction w $entry() {\n@e\n%x =w loadub $empty\nret %x\n}");
    defer empty.deinit();
    try testing.expectError(error.MemoryOutOfBounds, interpreter.evaluateModule(testing.allocator, &empty, entry(), &.{}, .{ .global_memory = .{} }));
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, global_source ++ quoted_source ++ "common export data $\"quoted object\" = { z 0, z 17 }");
    defer module.deinit();
    const assembly = try amd64.emit(allocator, &module);
    defer allocator.free(assembly);
    if (std.mem.indexOf(u8, assembly, ".comm object,8,64") == null) return error.MissingCommon;
    if ((try interpreter.evaluateModule(allocator, &module, entry(), &.{.{ .long = 99 }}, .{ .global_memory = .{} })).?.long != 0) return error.NotReset;
}
test "common parse emission globals and frame ownership survive every injected allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

fn existingExercise(allocator: std.mem.Allocator, module: *const Module) !void {
    const assembly = try amd64.emit(allocator, module);
    defer allocator.free(assembly);
    if ((try interpreter.evaluateModule(allocator, module, entry(), &.{.{ .long = 99 }}, .{ .global_memory = .{} })).?.long != 0) return error.NotReset;
}
test "each common emission and evaluation allocation failure permits same-module successful retry" {
    var module = try parse(testing.allocator, global_source);
    defer module.deinit();
    var count = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try existingExercise(count.allocator(), &module);
    try testing.expectEqual(count.allocated_bytes, count.freed_bytes);
    for (0..count.alloc_index) |fail_at| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = fail_at, .resize_fail_index = 0 });
        try testing.expectError(error.OutOfMemory, existingExercise(failing.allocator(), &module));
        try testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        failing.fail_index = std.math.maxInt(usize);
        try existingExercise(failing.allocator(), &module);
        try testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        try testing.expectEqual(@as(u32, 8), module.data.items[0].items.items[0].zero);
    }
}

const quoted_source = "common data $\"tail\\\\\" = align 64 { z 17 }\ndata $\"ordinary\\\\\" = { b 9 }\ndata $table = { l $\"tail\\\\\", l $\"tail\\\\\"+16 }\nfunction l $q() {\n@e\n%x =l copy $\"tail\\\\\"+-2147483648\nret %x\n}\nfunction l $ordinary() {\n@e\nret $\"ordinary\\\\\"\n}\n";

test "quoted common trailing backslash uses relocation cell not illegal set alias while ordinary alias stays" {
    var module = try parse(testing.allocator, quoted_source);
    defer module.deinit();
    const assembly = try amd64.emit(testing.allocator, &module);
    defer testing.allocator.free(assembly);
    try testing.expect(std.mem.indexOf(u8, assembly, ".comm \"tail\\\\\",17,64") != null);
    try testing.expect(std.mem.indexOf(u8, assembly, ".set \".Lzbe@s0\"") == null);
    try testing.expect(std.mem.indexOf(u8, assembly, ".set \".Lzbe@s1\"") != null);
    try testing.expect(std.mem.indexOf(u8, assembly, ".pushsection .data.rel.ro.local,\"aw\",@progbits") != null);
    try testing.expect(std.mem.indexOf(u8, assembly, "movq \".Lzbe@common0\"(%rip), %rax") != null);
    try testing.expect(std.mem.indexOf(u8, assembly, "leaq -2147483648(%rax), %rax") != null);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, assembly, "\".Lzbe@common0\":\n"));
}
