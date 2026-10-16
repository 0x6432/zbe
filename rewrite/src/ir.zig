const std = @import("std");
const Allocator = std.mem.Allocator;
const SymbolId = @import("symbols.zig").Id;

/// IDs are function-scoped. Keep them with their owning Function.
pub const ValueId = enum(u32) { _ };
pub const BlockId = enum(u32) { _ };

pub const ScalarType = enum {
    word,
    long,
    single,
    double,

    pub fn isInteger(self: ScalarType) bool {
        return self == .word or self == .long;
    }
};

/// Preserve floating bit patterns (including NaN payloads), not host formatting.
pub const Constant = union(enum) {
    word: u32,
    long: u64,
    single_bits: u32,
    double_bits: u64,

    pub fn scalarType(self: Constant) ScalarType {
        return switch (self) {
            .word => .word,
            .long => .long,
            .single_bits => .single,
            .double_bits => .double,
        };
    }

    /// QBE jnz tests low 32 bits even when its operand has long type.
    pub fn branchTaken(self: Constant) error{NonIntegerCondition}!bool {
        return switch (self) {
            .word => |bits| bits != 0,
            .long => |bits| @as(u32, @truncate(bits)) != 0,
            else => error.NonIntegerCondition,
        };
    }
};

pub const Operand = union(enum) { value: ValueId, constant: Constant };
pub const BinaryOp = enum { add, sub, mul, bit_and, bit_or, bit_xor };
pub const Instruction = union(enum) {
    binary: struct { result: ValueId, op: BinaryOp, lhs: Operand, rhs: Operand },
};
pub const Terminator = union(enum) {
    jump: BlockId,
    branch: struct { condition: Operand, taken: BlockId, not_taken: BlockId },
    return_value: ?Operand,
};
const Definition = union(enum) {
    parameter: usize,
    instruction: struct { block: BlockId, index: usize },
};
const Value = struct { scalar_type: ScalarType, definition: Definition };
const Block = struct {
    label: ?SymbolId,
    instructions: std.ArrayList(Instruction) = .empty,
    terminator: ?Terminator = null,
};

pub const ValidationError = error{
    InvalidBlock,
    InvalidValue,
    InvalidDefinition,
    TypeMismatch,
    NonIntegerCondition,
    InvalidReturn,
    BlockTerminated,
    MissingTerminator,
    NoBlocks,
    ParametersAfterInstructions,
};
pub const BuildError = Allocator.Error || ValidationError || error{ TooManyValues, TooManyBlocks };

/// Owns all per-function storage. IDs survive growth; borrowed views do not.
/// This is a minimal initial IR, not yet the full QBE instruction vocabulary.
pub const Function = struct {
    allocator: Allocator,
    name: SymbolId,
    return_type: ?ScalarType,
    parameters: std.ArrayList(ValueId) = .empty,
    values: std.ArrayList(Value) = .empty,
    blocks: std.ArrayList(Block) = .empty,

    pub fn init(allocator: Allocator, name: SymbolId, return_type: ?ScalarType) Function {
        return .{ .allocator = allocator, .name = name, .return_type = return_type };
    }

    pub fn deinit(self: *Function) void {
        for (self.blocks.items) |*block| block.instructions.deinit(self.allocator);
        self.blocks.deinit(self.allocator);
        self.values.deinit(self.allocator);
        self.parameters.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn addParameter(self: *Function, ty: ScalarType) BuildError!ValueId {
        if (self.values.items.len != self.parameters.items.len) return error.ParametersAfterInstructions;
        const id = try self.nextValueId();
        try self.values.ensureUnusedCapacity(self.allocator, 1);
        try self.parameters.ensureUnusedCapacity(self.allocator, 1);
        self.values.appendAssumeCapacity(.{ .scalar_type = ty, .definition = .{ .parameter = self.parameters.items.len } });
        self.parameters.appendAssumeCapacity(id);
        return id;
    }

    pub fn addBlock(self: *Function, label: ?SymbolId) BuildError!BlockId {
        const number = std.math.cast(u32, self.blocks.items.len) orelse return error.TooManyBlocks;
        try self.blocks.append(self.allocator, .{ .label = label });
        return @fromBackingInt(@intCast(number));
    }

    pub fn appendBinary(self: *Function, block_id: BlockId, ty: ScalarType, op: BinaryOp, lhs: Operand, rhs: Operand) BuildError!ValueId {
        const block = try self.getBlock(block_id);
        if (block.terminator != null) return error.BlockTerminated;
        try self.checkBinary(ty, op, lhs, rhs);
        const result = try self.nextValueId();
        try self.values.ensureUnusedCapacity(self.allocator, 1);
        try block.instructions.ensureUnusedCapacity(self.allocator, 1);
        self.values.appendAssumeCapacity(.{ .scalar_type = ty, .definition = .{ .instruction = .{ .block = block_id, .index = block.instructions.items.len } } });
        block.instructions.appendAssumeCapacity(.{ .binary = .{ .result = result, .op = op, .lhs = lhs, .rhs = rhs } });
        return result;
    }

    pub fn terminate(self: *Function, block_id: BlockId, terminator: Terminator) ValidationError!void {
        const target = try self.getBlock(block_id);
        if (target.terminator != null) return error.BlockTerminated;
        try self.checkTerminator(terminator);
        target.terminator = terminator;
    }

    pub fn operandType(self: *const Function, operand: Operand) ValidationError!ScalarType {
        return switch (operand) {
            .constant => |constant| constant.scalarType(),
            .value => |id| if (@backingInt(id) < self.values.items.len)
                self.values.items[@backingInt(id)].scalar_type
            else
                error.InvalidValue,
        };
    }

    /// Checks structure/types only. Dominance, phi edges and SSA verification
    /// belong to the next IR/CFG milestone; this must not be sold as full SSA validation.
    pub fn validateStructure(self: *const Function) ValidationError!void {
        if (self.blocks.items.len == 0) return error.NoBlocks;
        for (self.parameters.items, 0..) |id, index| {
            if (@backingInt(id) >= self.values.items.len) return error.InvalidValue;
            switch (self.values.items[@backingInt(id)].definition) {
                .parameter => |p| if (p != index) return error.InvalidDefinition,
                else => return error.InvalidDefinition,
            }
        }
        // Validate reverse links too, so orphaned or duplicate values cannot hide.
        for (self.values.items, 0..) |value, number| switch (value.definition) {
            .parameter => |index| {
                if (index >= self.parameters.items.len or @backingInt(self.parameters.items[index]) != number)
                    return error.InvalidDefinition;
            },
            .instruction => |definition| {
                if (@backingInt(definition.block) >= self.blocks.items.len) return error.InvalidDefinition;
                const instructions = self.blocks.items[@backingInt(definition.block)].instructions.items;
                if (definition.index >= instructions.len) return error.InvalidDefinition;
                switch (instructions[definition.index]) {
                    .binary => |binary| if (@backingInt(binary.result) != number) return error.InvalidDefinition,
                }
            },
        };
        for (self.blocks.items, 0..) |b, number| {
            for (b.instructions.items, 0..) |instruction, index| switch (instruction) {
                .binary => |binary| {
                    const ty = try self.operandType(.{ .value = binary.result });
                    switch (self.values.items[@backingInt(binary.result)].definition) {
                        .instruction => |definition| {
                            if (@backingInt(definition.block) != number or definition.index != index) return error.InvalidDefinition;
                        },
                        else => return error.InvalidDefinition,
                    }
                    try self.checkBinary(ty, binary.op, binary.lhs, binary.rhs);
                },
            };
            try self.checkTerminator(b.terminator orelse return error.MissingTerminator);
        }
    }

    fn getBlock(self: *Function, id: BlockId) ValidationError!*Block {
        const index = @backingInt(id);
        if (index >= self.blocks.items.len) return error.InvalidBlock;
        return &self.blocks.items[index];
    }

    fn nextValueId(self: *const Function) error{TooManyValues}!ValueId {
        const number = std.math.cast(u32, self.values.items.len) orelse return error.TooManyValues;
        return @fromBackingInt(@intCast(number));
    }

    fn checkBinary(self: *const Function, ty: ScalarType, op: BinaryOp, lhs: Operand, rhs: Operand) ValidationError!void {
        if (try self.operandType(lhs) != ty or try self.operandType(rhs) != ty) return error.TypeMismatch;
        switch (op) {
            .bit_and, .bit_or, .bit_xor => if (!ty.isInteger()) return error.TypeMismatch,
            else => {},
        }
    }

    fn checkTerminator(self: *const Function, terminator: Terminator) ValidationError!void {
        switch (terminator) {
            .jump => |id| if (@backingInt(id) >= self.blocks.items.len) return error.InvalidBlock,
            .branch => |branch| {
                if (!(try self.operandType(branch.condition)).isInteger()) return error.NonIntegerCondition;
                if (@backingInt(branch.taken) >= self.blocks.items.len or @backingInt(branch.not_taken) >= self.blocks.items.len) return error.InvalidBlock;
            },
            .return_value => |operand| {
                if (self.return_type) |ty| {
                    if (try self.operandType(operand orelse return error.InvalidReturn) != ty) return error.InvalidReturn;
                } else if (operand != null) return error.InvalidReturn;
            },
        }
    }
};

const testing = std.testing;
const test_name: SymbolId = @fromBackingInt(@intCast(0));
const one: Operand = .{ .constant = .{ .word = 1 } };

test "typed function construction and branch targets" {
    var f = Function.init(testing.allocator, test_name, .word);
    defer f.deinit();
    const p = try f.addParameter(.word);
    const entry = try f.addBlock(null);
    const yes = try f.addBlock(null);
    const no = try f.addBlock(null);
    const sum = try f.appendBinary(entry, .word, .add, .{ .value = p }, one);
    try f.terminate(entry, .{ .branch = .{ .condition = .{ .value = sum }, .taken = yes, .not_taken = no } });
    try f.terminate(yes, .{ .return_value = .{ .value = sum } });
    try f.terminate(no, .{ .return_value = one });
    try f.validateStructure();
}

test "invalid builder operations do not publish partial state" {
    var f = Function.init(testing.allocator, test_name, .word);
    defer f.deinit();
    const b = try f.addBlock(null);
    const invalid: Operand = .{ .value = @fromBackingInt(@intCast(10)) };
    try testing.expectError(error.InvalidValue, f.appendBinary(b, .word, .add, invalid, one));
    try testing.expectError(error.TypeMismatch, f.appendBinary(b, .long, .add, one, one));
    try testing.expectError(error.InvalidBlock, f.appendBinary(@fromBackingInt(@intCast(9)), .word, .add, one, one));
    try testing.expectEqual(@as(usize, 0), f.values.items.len);
    try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
    try testing.expectError(error.InvalidReturn, f.terminate(b, .{ .return_value = null }));
    try testing.expect(f.blocks.items[0].terminator == null);
    try f.terminate(b, .{ .return_value = one });
    try testing.expectError(error.BlockTerminated, f.appendBinary(b, .word, .add, one, one));
    try testing.expectError(error.BlockTerminated, f.terminate(b, .{ .return_value = one }));
}

test "structural validation rejects missing terminators and invalid branch kinds" {
    var f = Function.init(testing.allocator, test_name, null);
    defer f.deinit();
    try testing.expectError(error.NoBlocks, f.validateStructure());
    const b = try f.addBlock(null);
    try testing.expectError(error.MissingTerminator, f.validateStructure());
    try testing.expectError(error.InvalidBlock, f.terminate(b, .{ .jump = @fromBackingInt(@intCast(99)) }));
    try testing.expectError(error.NonIntegerCondition, f.terminate(b, .{ .branch = .{ .condition = .{ .constant = .{ .single_bits = 0 } }, .taken = b, .not_taken = b } }));
    try f.terminate(b, .{ .return_value = null });
    try f.validateStructure();
}

test "float arithmetic is typed; bitwise floats are rejected" {
    var f = Function.init(testing.allocator, test_name, .single);
    defer f.deinit();
    const b = try f.addBlock(null);
    const value: Operand = .{ .constant = .{ .single_bits = 0x7fc01234 } };
    try testing.expectError(error.TypeMismatch, f.appendBinary(b, .single, .bit_and, value, value));
    const sum = try f.appendBinary(b, .single, .add, value, value);
    try f.terminate(b, .{ .return_value = .{ .value = sum } });
    try f.validateStructure();
    try testing.expectError(error.ParametersAfterInstructions, f.addParameter(.word));
}

test "branch constants implement low-word semantics without a compatibility bug" {
    try testing.expect(!try (Constant{ .long = 1 << 40 }).branchTaken());
    try testing.expect(try (Constant{ .long = (1 << 40) | 1 }).branchTaken());
    try testing.expect(!try (Constant{ .long = 0xffffffff00000000 }).branchTaken());
    try testing.expect(try (Constant{ .word = 0x80000000 }).branchTaken());
    try testing.expectError(error.NonIntegerCondition, (Constant{ .double_bits = 0 }).branchTaken());
}

fn exerciseGrowth(allocator: Allocator) !void {
    var f = Function.init(allocator, test_name, .word);
    defer f.deinit();
    var value: Operand = .{ .value = try f.addParameter(.word) };
    const entry = try f.addBlock(null);
    for (0..80) |_| value = .{ .value = try f.appendBinary(entry, .word, .add, value, one) };
    for (0..40) |_| {
        const b = try f.addBlock(null);
        try f.terminate(b, .{ .return_value = one });
    }
    try f.terminate(entry, .{ .return_value = value });
    try f.validateStructure();
    try testing.expectEqual(@as(usize, 81), f.values.items.len);
}

test "IR IDs survive growth and every allocation failure is cleaned up" {
    try testing.checkAllAllocationFailures(testing.allocator, exerciseGrowth, .{});
}

test "structural validation rejects corrupt definition backlinks and types" {
    var f = Function.init(testing.allocator, test_name, .word);
    defer f.deinit();
    const b = try f.addBlock(null);
    const result = try f.appendBinary(b, .word, .add, one, one);
    try f.terminate(b, .{ .return_value = .{ .value = result } });
    try f.validateStructure();
    const original = f.values.items[0];
    f.values.items[0].definition = .{ .instruction = .{ .block = b, .index = 99 } };
    try testing.expectError(error.InvalidDefinition, f.validateStructure());
    f.values.items[0].definition = .{ .parameter = 0 };
    try testing.expectError(error.InvalidDefinition, f.validateStructure());
    f.values.items[0] = original;
    f.values.items[0].scalar_type = .long;
    try testing.expectError(error.TypeMismatch, f.validateStructure());
    f.values.items[0] = original;
    try f.values.append(testing.allocator, original);
    try testing.expectError(error.InvalidDefinition, f.validateStructure());
    _ = f.values.pop();
    try f.validateStructure();
}

test "builders remain usable after either linked allocation fails" {
    for ([_]bool{ false, true }) |parameter| {
        for (0..2) |failure_offset| {
            var failing = testing.FailingAllocator.init(testing.allocator, .{});
            var f = Function.init(failing.allocator(), test_name, .word);
            defer f.deinit();
            const b = try f.addBlock(null);
            failing.fail_index = failing.alloc_index + failure_offset;
            if (parameter) {
                try testing.expectError(error.OutOfMemory, f.addParameter(.word));
            } else {
                try testing.expectError(error.OutOfMemory, f.appendBinary(b, .word, .add, one, one));
            }
            try testing.expectEqual(@as(usize, 0), f.values.items.len);
            try testing.expectEqual(@as(usize, 0), f.parameters.items.len);
            try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
            failing.fail_index = std.math.maxInt(usize);
            const result = if (parameter) try f.addParameter(.word) else try f.appendBinary(b, .word, .add, one, one);
            try f.terminate(b, .{ .return_value = .{ .value = result } });
            try f.validateStructure();
        }
    }
}
