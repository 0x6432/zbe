//! Focused O05 generic-validation allocation sweep; not the full O05 ledger.
//! Each failed call is destroyed, then validation retries on the same module.
const std = @import("std");
const t = std.testing;
const ir = @import("ir.zig");
const validation = @import("module_validation.zig");
const Module = @import("module.zig").Module;

const source =
    \\type :R={l, d}
    \\type :Unused={b 3}
    \\data $unused={l 11, l $known}
    \\function l $caller(w %c) {
    \\@entry
    \\jnz %c, @left, @right
    \\@left
    \\%v =l copy extern $target_data
    \\jmp @join
    \\@right
    \\jmp @join
    \\@join
    \\%p =l phi @left %v, @right extern $target_data
    \\%r =l call extern $known(l %p)
    \\ret %r
    \\}
    \\function l $known(l %x) {
    \\@entry
    \\ret %x
    \\}
    \\function :R $record(:R %v) {
    \\@entry
    \\%r =:R call extern $record_target(:R extern $record_data)
    \\ret %r
    \\}
;

fn form(symbol: @import("symbols.zig").Id, wrapped: bool) ir.CallTarget {
    return if (wrapped) .{ .address = .{ .got_symbol = symbol } } else .{ .extern_symbol = symbol };
}

test "O05 generic validation retries each measured OOM on the same module" {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    var module: Module = try @import("frontend.zig").parse(t.allocator, .{ .name = "extern-o05", .text = source }, &diagnostic);
    defer module.deinit();
    const scalar = &module.functions.items[0].blocks.items[3].instructions.items[0].call;
    const record = &module.functions.items[2].blocks.items[0].instructions.items[0].call;
    const scalar_target = scalar.callee.extern_symbol;
    const record_target = record.callee.extern_symbol;
    const record_argument = record.arguments[0].operand.got_symbol;
    for ([_]bool{ false, true }) |scalar_wrapped| for ([_]bool{ false, true }) |record_wrapped| {
        scalar.callee = form(scalar_target, scalar_wrapped);
        record.callee = form(record_target, record_wrapped);
        var count = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
        try validation.validate(count.allocator(), &module);
        try t.expectEqual(count.allocated_bytes, count.freed_bytes);
        const attempts = count.alloc_index;
        try t.expect(attempts > 0);
        std.debug.print("O05 scalar_wrapped={} record_wrapped={} validation attempts={d}\n", .{ scalar_wrapped, record_wrapped, attempts });
        for (0..attempts) |ordinal| {
            var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = ordinal, .resize_fail_index = 0 });
            try t.expectError(error.OutOfMemory, validation.validate(failing.allocator(), &module));
            try t.expect(failing.has_induced_failure);
            try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
            try t.expectEqual(scalar_target, scalar.callee.symbolicIdentity().?);
            try t.expectEqual(record_target, record.callee.symbolicIdentity().?);
            try t.expectEqual(record_argument, record.arguments[0].operand.got_symbol);
            failing.fail_index = std.math.maxInt(usize);
            try validation.validate(failing.allocator(), &module);
            try t.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        }
        var after = t.FailingAllocator.init(t.allocator, .{ .fail_index = attempts, .resize_fail_index = 0 });
        try validation.validate(after.allocator(), &module);
        try t.expect(!after.has_induced_failure);
        try t.expectEqual(attempts, after.alloc_index);
        try t.expectEqual(after.allocated_bytes, after.freed_bytes);
        // Known-symbol checking must apply equally to both target shapes.
        scalar.callee = form(module.functions.items[2].name, scalar_wrapped);
        try t.expectError(error.CallSignatureMismatch, validation.validate(t.allocator, &module));
        scalar.callee = form(module.data.items[0].name, scalar_wrapped);
        try t.expectError(error.CalledDataSymbol, validation.validate(t.allocator, &module));
        scalar.callee = form(scalar_target, scalar_wrapped);
    };
}
