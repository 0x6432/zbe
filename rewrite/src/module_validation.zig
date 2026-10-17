//! Target-independent scalar SSA and direct-call signature validation.
const std = @import("std");
const ir = @import("ir.zig");
const ssa = @import("ssa.zig");
const Module = @import("module.zig").Module;
pub const Error = ssa.Error || @import("data.zig").Error || error{ InvalidSymbol, DuplicateSymbol, CallSignatureMismatch, CalledDataSymbol };

/// Validate all bodies before following callee parameter IDs. Externals remain
/// contractual, but their symbol IDs must belong to this module's pool.
/// This does not impose a target assembler's symbol spelling restrictions.
pub fn validate(allocator: std.mem.Allocator, module: *const Module) Error!void {
    _ = try module.dataSize();
    for (module.data.items, 0..) |object, index| {
        _ = module.symbols.get(object.name) orelse return error.InvalidSymbol;
        for (object.items.items) |item| if (item == .symbol_address) {
            _ = module.symbols.get(item.symbol_address.symbol) orelse return error.InvalidSymbol;
        };
        for (module.data.items[0..index]) |previous| if (previous.name == object.name) return error.DuplicateSymbol;
        for (module.functions.items) |function| if (function.name == object.name) return error.DuplicateSymbol;
    }
    for (module.functions.items, 0..) |function, index| {
        _ = module.symbols.get(function.name) orelse return error.InvalidSymbol;
        for (module.functions.items[0..index]) |previous| if (previous.name == function.name) return error.DuplicateSymbol;
        var issue: ?ssa.Issue = null;
        try ssa.validate(allocator, function, &issue);
    }
    // Symbols in scalar positions are module-scoped, not SSA references.
    for (module.functions.items) |function| for (function.blocks.items) |block| {
        for (block.phis.items) |phi| for (phi.inputs) |input| try checkOperandSymbol(module, input.value);
        for (block.instructions.items) |instruction| {
            var operands = instruction.operands();
            while (operands.next()) |operand| try checkOperandSymbol(module, operand);
        }
        switch (block.terminator.?) {
            .branch => |branch| try checkOperandSymbol(module, branch.condition),
            .return_value => |value| if (value) |operand| try checkOperandSymbol(module, operand),
            .jump, .halt => {},
        }
    };
    for (module.functions.items) |function| for (function.blocks.items) |block| for (block.instructions.items) |instruction| switch (instruction) {
        .call => |call| {
            const symbol = switch (call.callee) {
                .symbol => |symbol| symbol,
                .address => continue,
            };
            _ = module.symbols.get(symbol) orelse return error.InvalidSymbol;
            for (module.data.items) |object| if (object.name == symbol) return error.CalledDataSymbol;
            const callee = findFunction(module, symbol) orelse continue;
            const result_type: ?ir.ScalarType = if (call.result) |result| function.values.items[@backingInt(result)].scalar_type else null;
            if (callee.return_type != result_type or callee.return_subword != call.result_subword) return error.CallSignatureMismatch;
            if (call.environment == null and callee.usesEnvironment()) return error.CallSignatureMismatch;
            const named = callee.ordinaryParameters().len;
            if (callee.variadic) {
                if (call.variadic_start != @as(?usize, named) or call.arguments.len < named) return error.CallSignatureMismatch;
            } else if (call.variadic_start != null or call.arguments.len != named) return error.CallSignatureMismatch;
            for (callee.ordinaryParameters(), call.arguments[0..named]) |parameter, argument| {
                if (callee.values.items[@backingInt(parameter)].scalar_type != argument.scalar_type or callee.values.items[@backingInt(parameter)].parameter_subword != argument.subword_type) return error.CallSignatureMismatch;
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

fn checkOperandSymbol(module: *const Module, operand: ir.Operand) Error!void {
    if (operand.referencedSymbol()) |symbol| if (module.symbols.get(symbol) == null) return error.InvalidSymbol;
}
