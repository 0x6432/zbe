//! Target-independent scalar SSA and direct-call signature validation.
const std = @import("std");
const ir = @import("ir.zig");
const ssa = @import("ssa.zig");
const Module = @import("module.zig").Module;
pub const Error = ssa.Error || error{ InvalidSymbol, DuplicateSymbol, CallSignatureMismatch };

/// Validate all bodies before following callee parameter IDs. Externals remain
/// contractual, but their symbol IDs must belong to this module's pool.
/// This does not impose a target assembler's symbol spelling restrictions.
pub fn validate(allocator: std.mem.Allocator, module: *const Module) Error!void {
    for (module.functions.items, 0..) |function, index| {
        _ = module.symbols.get(function.name) orelse return error.InvalidSymbol;
        for (module.functions.items[0..index]) |previous| if (previous.name == function.name) return error.DuplicateSymbol;
        var issue: ?ssa.Issue = null;
        try ssa.validate(allocator, function, &issue);
    }
    for (module.functions.items) |function| for (function.blocks.items) |block| for (block.instructions.items) |instruction| switch (instruction) {
        .call => |call| {
            const symbol = switch (call.callee) {
                .symbol => |symbol| symbol,
                .address => continue,
            };
            _ = module.symbols.get(symbol) orelse return error.InvalidSymbol;
            const callee = findFunction(module, symbol) orelse continue;
            const result_type: ?ir.ScalarType = if (call.result) |result| function.values.items[@backingInt(result)].scalar_type else null;
            if (callee.return_type != result_type or callee.parameters.items.len != call.arguments.len) return error.CallSignatureMismatch;
            for (callee.parameters.items, call.arguments) |parameter, argument| {
                if (callee.values.items[@backingInt(parameter)].scalar_type != argument.scalar_type) return error.CallSignatureMismatch;
            }
        },
        else => {},
    };
}

/// Module-pool ID lookup, not a host/linker resolver. Validate the module before
/// following the returned function's scalar structure in a verified consumer.
pub fn findFunction(module: *const Module, name: @import("symbols.zig").Id) ?*const ir.Function {
    for (module.functions.items) |function| if (function.name == name) return function;
    return null;
}
