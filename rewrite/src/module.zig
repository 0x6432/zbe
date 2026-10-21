const std = @import("std");
const symbols = @import("symbols.zig");
const ir = @import("ir.zig");
const data = @import("data.zig");
const records = @import("record_declaration.zig");
pub const AggregateTypeId = records.Id;

pub const FunctionId = enum(u32) { _ };
pub const DataId = enum(u32) { _ };

/// Independent compilation ownership boundary; no global compiler state.
/// Function/data pointers remain stable when their handle tables grow.
pub const Module = struct {
    allocator: std.mem.Allocator,
    symbols: symbols.Pool,
    /// Owns type spellings without consuming code-generation symbol IDs.
    record_names: symbols.Pool,
    functions: std.ArrayList(*ir.Function) = .empty,
    data: std.ArrayList(*data.Data) = .empty,
    /// A separate declaration namespace, never an ELF definition or SSA type.
    types: std.ArrayList(*records.Record) = .empty,

    pub fn init(allocator: std.mem.Allocator) Module {
        return .{ .allocator = allocator, .symbols = symbols.Pool.init(allocator), .record_names = symbols.Pool.init(allocator) };
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
        for (self.types.items) |record| {
            record.deinit();
            self.allocator.destroy(record);
        }
        self.types.deinit(self.allocator);
        self.record_names.deinit();
        self.symbols.deinit();
        self.* = undefined;
    }

    /// No retained name lookup or run-total cache can become stale. The small,
    /// bounded declaration table is authoritative, including after IR edits.
    pub fn findRecord(self: *const Module, name: []const u8) ?AggregateTypeId {
        for (self.types.items, 0..) |record, index| {
            const stored = self.record_names.get(record.name) orelse continue;
            if (std.mem.eql(u8, stored, name)) return @fromBackingInt(@as(u32, @intCast(index)));
        }
        return null;
    }
    pub fn getRecord(self: *const Module, id: AggregateTypeId) ?*records.Record {
        const index = @backingInt(id);
        return if (index < self.types.items.len) self.types.items[index] else null;
    }
    pub fn validateRecords(self: *const Module, allocator: std.mem.Allocator) records.Error!void {
        try records.validate(allocator, self.types.items, &self.record_names);
    }
    pub fn addRecord(self: *Module, name: []const u8, alignment: ?u8, fields: []const records.Field) (records.Error || error{TooManySymbols})!AggregateTypeId {
        try self.validateRecords(self.allocator);
        if (!records.validName(name)) return error.InvalidRecordName;
        if (self.findRecord(name) != null) return error.DuplicateType;
        if (self.types.items.len >= records.max_records) return error.RecordLimitExceeded;
        var total = fields.len;
        for (self.types.items) |record| total = std.math.add(usize, total, record.runs.len) catch return error.RecordLimitExceeded;
        if (total > records.max_module_runs) return error.RecordLimitExceeded;
        const name_id = try self.record_names.intern(name);
        const record = try records.Record.create(self.allocator, name_id, alignment, fields, self.types.items);
        errdefer {
            record.deinit();
            self.allocator.destroy(record);
        }
        try self.types.ensureUnusedCapacity(self.allocator, 1);
        const id: AggregateTypeId = @fromBackingInt(@as(u32, @intCast(self.types.items.len)));
        self.types.appendAssumeCapacity(record);
        return id;
    }

    pub fn addUnion(self: *Module, name: []const u8, alignment: ?u8, alternatives: []const []const records.Field) (records.Error || error{TooManySymbols})!AggregateTypeId {
        try self.validateRecords(self.allocator);
        if (!records.validName(name)) return error.InvalidRecordName;
        if (self.findRecord(name) != null) return error.DuplicateType;
        if (self.types.items.len >= records.max_records) return error.RecordLimitExceeded;
        if (alternatives.len == 0) return error.InvalidRecordLayout;
        if (alternatives.len > records.max_record_runs) return error.RecordLimitExceeded;
        var added: usize = 0;
        for (alternatives) |fields| {
            if (fields.len == 0) return error.InvalidRecordLayout;
            added = std.math.add(usize, added, fields.len) catch return error.RecordLimitExceeded;
            if (added > records.max_record_runs) return error.RecordLimitExceeded;
        }
        var total = added;
        for (self.types.items) |record| total = std.math.add(usize, total, record.runs.len) catch return error.RecordLimitExceeded;
        if (total > records.max_module_runs) return error.RecordLimitExceeded;
        const name_id = try self.record_names.intern(name);
        const record = try records.Record.createUnion(self.allocator, name_id, alignment, alternatives, self.types.items);
        errdefer {
            record.deinit();
            self.allocator.destroy(record);
        }
        try self.types.ensureUnusedCapacity(self.allocator, 1);
        const id: AggregateTypeId = @fromBackingInt(@as(u32, @intCast(self.types.items.len)));
        self.types.appendAssumeCapacity(record);
        return id;
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

    /// IDs are resolved only with this explicit module. No hidden owner link.
    pub fn checkAbiDescriptor(self: *const Module, descriptor: ir.AbiDescriptor) error{InvalidAggregateType}!void {
        switch (descriptor) {
            .scalar => {},
            .record => |id| if (self.getRecord(id) == null) return error.InvalidAggregateType,
        }
    }
    pub fn addFunctionDescriptor(self: *Module, name: []const u8, result: ?ir.AbiDescriptor) !FunctionId {
        if (result) |ty| try self.checkAbiDescriptor(ty);
        const id = try self.addFunction(name, if (result) |ty| ty.carrierType() else null);
        const function = self.getFunction(id).?;
        function.return_subword = if (result) |ty| ty.subword() else null;
        function.return_descriptor = result;
        return id;
    }
    pub fn addParameterDescriptor(self: *Module, function_id: FunctionId, descriptor: ir.AbiDescriptor) !ir.ValueId {
        try self.checkAbiDescriptor(descriptor);
        const function = self.getFunction(function_id) orelse return error.InvalidFunction;
        return function.addParameterDescriptor(descriptor);
    }
    pub fn appendCallDescriptor(self: *Module, function_id: FunctionId, block: ir.BlockId, result: ?ir.ValueId, target: ir.CallTarget, arguments: []const ir.CallArgument, options: ir.CallOptions) !void {
        if (options.result_descriptor) |ty| try self.checkAbiDescriptor(ty);
        for (arguments) |argument| try self.checkAbiDescriptor(try argument.abi());
        const function = self.getFunction(function_id) orelse return error.InvalidFunction;
        try function.appendCall(block, result, target, arguments, options);
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
