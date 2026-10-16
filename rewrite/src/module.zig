const std = @import("std");
const symbols = @import("symbols.zig");
const ir = @import("ir.zig");

pub const FunctionId = enum(u32) { _ };

/// Independent compilation ownership boundary; no global compiler state.
/// Function pointers remain stable when the module's handle table grows.
pub const Module = struct {
    allocator: std.mem.Allocator,
    symbols: symbols.Pool,
    functions: std.ArrayList(*ir.Function) = .empty,

    pub fn init(allocator: std.mem.Allocator) Module {
        return .{ .allocator = allocator, .symbols = symbols.Pool.init(allocator) };
    }

    pub fn deinit(self: *Module) void {
        for (self.functions.items) |function| {
            function.deinit();
            self.allocator.destroy(function);
        }
        self.functions.deinit(self.allocator);
        self.symbols.deinit();
        self.* = undefined;
    }

    pub fn addFunction(self: *Module, name: []const u8, result: ?ir.ScalarType) !FunctionId {
        for (self.functions.items) |function| {
            if (std.mem.eql(u8, self.symbols.get(function.name).?, name)) return error.DuplicateFunction;
        }
        const number = std.math.cast(u32, self.functions.items.len) orelse return error.TooManyFunctions;
        const name_id = try self.symbols.intern(name);
        try self.functions.ensureUnusedCapacity(self.allocator, 1);
        const function = try self.allocator.create(ir.Function);
        function.* = ir.Function.init(self.allocator, name_id, result);
        self.functions.appendAssumeCapacity(function);
        return @fromBackingInt(@intCast(number));
    }

    pub fn getFunction(self: *Module, id: FunctionId) ?*ir.Function {
        const index = @backingInt(id);
        return if (index < self.functions.items.len) self.functions.items[index] else null;
    }
};

test "independent modules own distinct functions and name storage" {
    var a = Module.init(std.testing.allocator);
    defer a.deinit();
    var b = Module.init(std.testing.allocator);
    defer b.deinit();
    const fa = try a.addFunction("same", .word);
    const fb = try b.addFunction("same", null);
    try std.testing.expect(a.getFunction(fa).? != b.getFunction(fb).?);
    try std.testing.expectError(error.DuplicateFunction, a.addFunction("same", .word));
    try std.testing.expect(a.getFunction(@fromBackingInt(@intCast(9))) == null);
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = Module.init(allocator);
    defer module.deinit();
    const id = try module.addFunction("first", .word);
    const stable = module.getFunction(id).?;
    const block = try stable.addBlock(null);
    try stable.terminate(block, .{ .return_value = .{ .constant = .{ .word = 42 } } });
    var buffer: [32]u8 = undefined;
    for (0..48) |n| _ = try module.addFunction(try std.fmt.bufPrint(&buffer, "function.{d}", .{n}), null);
    try std.testing.expect(stable == module.getFunction(id).?);
    try stable.validateStructure();
}

test "module growth preserves function pointers and OOM cleans every owner" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exercise, .{});
}
