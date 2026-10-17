const std = @import("std");
const symbols = @import("symbols.zig");
const ir = @import("ir.zig");
const data = @import("data.zig");

pub const FunctionId = enum(u32) { _ };
pub const DataId = enum(u32) { _ };

/// Independent compilation ownership boundary; no global compiler state.
/// Function/data pointers remain stable when their handle tables grow.
pub const Module = struct {
    allocator: std.mem.Allocator,
    symbols: symbols.Pool,
    functions: std.ArrayList(*ir.Function) = .empty,
    data: std.ArrayList(*data.Data) = .empty,

    pub fn init(allocator: std.mem.Allocator) Module {
        return .{ .allocator = allocator, .symbols = symbols.Pool.init(allocator) };
    }

    pub fn deinit(self: *Module) void {
        for (self.functions.items) |function| {
            function.deinit();
            self.allocator.destroy(function);
        }
        self.functions.deinit(self.allocator);
        for (self.data.items) |object| {
            object.deinit();
            self.allocator.destroy(object);
        }
        self.data.deinit(self.allocator);
        self.symbols.deinit();
        self.* = undefined;
    }

    pub fn addFunction(self: *Module, name: []const u8, result: ?ir.ScalarType) !FunctionId {
        for (self.functions.items) |function| {
            if (std.mem.eql(u8, self.symbols.get(function.name).?, name)) return error.DuplicateFunction;
        }
        for (self.data.items) |object| {
            if (std.mem.eql(u8, self.symbols.get(object.name).?, name)) return error.DuplicateSymbol;
        }
        const number = std.math.cast(u32, self.functions.items.len) orelse return error.TooManyFunctions;
        const name_id = try self.symbols.intern(name);
        try self.functions.ensureUnusedCapacity(self.allocator, 1);
        const function = try self.allocator.create(ir.Function);
        function.* = ir.Function.init(self.allocator, name_id, result);
        self.functions.appendAssumeCapacity(function);
        return @fromBackingInt(@intCast(number));
    }

    pub fn addFunctionAbi(self: *Module, name: []const u8, result: ?ir.AbiType) !FunctionId {
        const id = try self.addFunction(name, if (result) |ty| ty.scalar() else null);
        self.getFunction(id).?.return_subword = if (result) |ty| ty.subword() else null;
        return id;
    }

    pub fn addData(self: *Module, name: []const u8) !DataId {
        for (self.functions.items) |function| {
            if (std.mem.eql(u8, self.symbols.get(function.name).?, name)) return error.DuplicateSymbol;
        }
        for (self.data.items) |object| {
            if (std.mem.eql(u8, self.symbols.get(object.name).?, name)) return error.DuplicateSymbol;
        }
        const number = std.math.cast(u32, self.data.items.len) orelse return error.TooManyData;
        const name_id = try self.symbols.intern(name);
        try self.data.ensureUnusedCapacity(self.allocator, 1);
        const object = try self.allocator.create(data.Data);
        object.* = data.Data.init(self.allocator, name_id);
        self.data.appendAssumeCapacity(object);
        return @fromBackingInt(number);
    }
    pub fn getData(self: *Module, id: DataId) ?*data.Data {
        const index = @backingInt(id);
        return if (index < self.data.items.len) self.data.items[index] else null;
    }
    /// Payload only, not alignment gaps, allocator metadata or output size.
    pub fn dataSize(self: *const Module) data.Error!usize {
        var total: usize = 0;
        for (self.data.items) |object| {
            total = std.math.add(usize, total, try object.validate()) catch return error.DataTooLarge;
            if (total > data.max_module_bytes) return error.DataTooLarge;
        }
        return total;
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
    try @import("test_support.zig").checkAllocationFailures(exercise);
}
