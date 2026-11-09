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
