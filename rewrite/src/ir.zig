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
pub const BinaryOp = enum { add, sub, mul, bit_and, bit_or, bit_xor, signed_divide, unsigned_divide, signed_remainder, unsigned_remainder };
pub const IntegerType = enum {
    word,
    long,
    pub fn scalar(self: IntegerType) ScalarType {
        return switch (self) {
            .word => .word,
            .long => .long,
        };
    }
};
/// Integer extensions read a word even when their result is long.
pub const UnaryOp = enum {
    negate,
    bitcast,
    widen_float,
    sign_extend_byte,
    zero_extend_byte,
    sign_extend_half,
    zero_extend_half,
    sign_extend_word,
    zero_extend_word,

    pub fn operandType(self: UnaryOp, result_type: ScalarType) error{TypeMismatch}!ScalarType {
        return switch (self) {
            .negate => result_type,
            .bitcast => switch (result_type) {
                .word => .single,
                .long => .double,
                .single => .word,
                .double => .long,
            },
            .widen_float => if (result_type == .double) .single else error.TypeMismatch,
            .sign_extend_byte, .zero_extend_byte, .sign_extend_half, .zero_extend_half => if (result_type.isInteger()) .word else error.TypeMismatch,
            .sign_extend_word, .zero_extend_word => if (result_type == .long) .word else error.TypeMismatch,
        };
    }
};
/// Numeric conversions are distinct from non-fallible bit-pattern unary ops.
pub const ConvertOp = enum {
    signed_word_to_float,
    signed_long_to_float,
    single_to_signed_integer,
    double_to_signed_integer,
    unsigned_word_to_float,
    unsigned_long_to_float,
    single_to_unsigned_integer,
    double_to_unsigned_integer,

    pub fn operandType(self: ConvertOp, result_type: ScalarType) error{TypeMismatch}!ScalarType {
        return switch (self) {
            .signed_word_to_float, .unsigned_word_to_float => if (!result_type.isInteger()) .word else error.TypeMismatch,
            .signed_long_to_float, .unsigned_long_to_float => if (!result_type.isInteger()) .long else error.TypeMismatch,
            .single_to_signed_integer, .single_to_unsigned_integer => if (result_type.isInteger()) .single else error.TypeMismatch,
            .double_to_signed_integer, .double_to_unsigned_integer => if (result_type.isInteger()) .double else error.TypeMismatch,
        };
    }
};
pub const ShiftOp = enum { left, logical_right, arithmetic_right };
pub const FloatType = enum {
    single,
    double,
    pub fn scalar(self: FloatType) ScalarType {
        return switch (self) {
            .single => .single,
            .double => .double,
        };
    }
};
pub const FloatPredicate = enum { equal, not_equal, less, less_equal, greater, greater_equal, ordered, unordered };
pub const IntegerPredicate = enum {
    equal,
    not_equal,
    signed_less,
    signed_less_equal,
    signed_greater,
    signed_greater_equal,
    unsigned_less,
    unsigned_less_equal,
    unsigned_greater,
    unsigned_greater_equal,
};
/// Access width and signedness are semantic, independent of machine opcodes.
pub const LoadKind = enum {
    signed_byte,
    unsigned_byte,
    signed_half,
    unsigned_half,
    signed_word,
    unsigned_word,
    long,
    single,
    double,

    pub fn accepts(self: LoadKind, ty: ScalarType) bool {
        return switch (self) {
            .long => ty == .long,
            .single => ty == .single,
            .double => ty == .double,
            else => ty.isInteger(),
        };
    }
};
pub const StoreKind = enum {
    byte,
    half,
    word,
    long,
    single,
    double,

    pub fn valueType(self: StoreKind) ScalarType {
        return switch (self) {
            .byte, .half, .word => .word,
            .long => .long,
            .single => .single,
            .double => .double,
        };
    }
};
pub const CallArgument = struct { scalar_type: ScalarType, operand: Operand };
/// Symbol targets use the module pool; address operands use function-scoped IDs.
pub const CallTarget = union(enum) {
    symbol: SymbolId,
    address: Operand,

    pub fn addressOperand(self: CallTarget) ?Operand {
        return switch (self) {
            .symbol => null,
            .address => |operand| operand,
        };
    }
};
/// Argument storage is owned by Function, not borrowed from callers.
pub const Call = struct { result: ?ValueId, callee: CallTarget, arguments: []const CallArgument };
pub const Instruction = union(enum) {
    /// Nonnegative signed-word byte count, not a packed reference field.
    blit: struct { source: Operand, destination: Operand, byte_count: u31 },
    load: struct { result: ValueId, kind: LoadKind, address: Operand },
    store: struct { kind: StoreKind, value: Operand, address: Operand },
    call: Call,
    binary: struct { result: ValueId, op: BinaryOp, lhs: Operand, rhs: Operand },
    copy: struct { result: ValueId, operand: Operand },
    unary: struct { result: ValueId, op: UnaryOp, operand: Operand },
    convert: struct { result: ValueId, op: ConvertOp, operand: Operand },
    shift: struct { result: ValueId, op: ShiftOp, value: Operand, amount: Operand },
    compare_float: struct { result: ValueId, predicate: FloatPredicate, operand_type: FloatType, lhs: Operand, rhs: Operand },
    compare_integer: struct { result: ValueId, predicate: IntegerPredicate, operand_type: IntegerType, lhs: Operand, rhs: Operand },

    /// Stores, blits and void calls have effects, not dummy value definitions.
    pub fn result(self: Instruction) ?ValueId {
        return switch (self) {
            .load => |load| load.result,
            .store, .blit => null,
            .call => |call| call.result,
            .binary => |binary| binary.result,
            .copy => |copy| copy.result,
            .unary => |unary| unary.result,
            .convert => |conversion| conversion.result,
            .shift => |shift| shift.result,
            .compare_integer => |comparison| comparison.result,
            .compare_float => |comparison| comparison.result,
        };
    }
    /// Scalar uses in stable operand order; never results or symbol IDs.
    /// Fixed operands are copied. Call arguments borrow their Function's storage,
    /// which must remain alive and unmodified until iteration finishes.
    pub fn operands(self: Instruction) OperandIterator {
        return switch (self) {
            .blit => |b| .{ .first = b.source, .second = b.destination },
            .load => |l| .{ .first = l.address },
            .store => |s| .{ .first = s.value, .second = s.address },
            .call => |c| .{ .first = c.callee.addressOperand(), .arguments = c.arguments },
            .binary => |b| .{ .first = b.lhs, .second = b.rhs },
            .copy => |c| .{ .first = c.operand },
            .unary => |u| .{ .first = u.operand },
            .convert => |c| .{ .first = c.operand },
            .shift => |s| .{ .first = s.value, .second = s.amount },
            .compare_float => |c| .{ .first = c.lhs, .second = c.rhs },
            .compare_integer => |c| .{ .first = c.lhs, .second = c.rhs },
        };
    }
};

/// Allocation-free scalar-use iterator. The optional fixed operands are values,
/// not pointers/slices into a temporary union payload. Only call storage borrows.
pub const OperandIterator = struct {
    first: ?Operand = null,
    second: ?Operand = null,
    arguments: []const CallArgument = &.{},

    pub fn next(self: *OperandIterator) ?Operand {
        if (self.first) |operand| {
            self.first = self.second;
            self.second = null;
            return operand;
        }
        if (self.arguments.len == 0) return null;
        const operand = self.arguments[0].operand;
        self.arguments = self.arguments[1..];
        return operand;
    }
};
pub const Terminator = union(enum) {
    halt,
    jump: BlockId,
    branch: struct { condition: Operand, taken: BlockId, not_taken: BlockId },
    return_value: ?Operand,
};
pub const PhiInput = struct { predecessor: BlockId, value: Operand };
pub const Phi = struct { result: ValueId, inputs: []const PhiInput };

const Definition = union(enum) {
    pending,
    phi: struct { block: BlockId, index: usize },
    parameter: usize,
    instruction: struct { block: BlockId, index: usize },
};
const Value = struct { scalar_type: ScalarType, definition: Definition };
const Block = struct {
    label: ?SymbolId,
    phis: std.ArrayList(Phi) = .empty,
    instructions: std.ArrayList(Instruction) = .empty,
    terminator: ?Terminator = null,
};

pub const ValidationError = error{
    InvalidBlock,
    InvalidValue,
    InvalidDefinition,
    InvalidPhi,
    PhiAfterInstructions,
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
    linkage: enum { internal, exported } = .internal,
    parameters: std.ArrayList(ValueId) = .empty,
    values: std.ArrayList(Value) = .empty,
    blocks: std.ArrayList(Block) = .empty,

    pub fn init(allocator: Allocator, name: SymbolId, return_type: ?ScalarType) Function {
        return .{ .allocator = allocator, .name = name, .return_type = return_type };
    }

    pub fn deinit(self: *Function) void {
        for (self.blocks.items) |*block| {
            for (block.phis.items) |phi| self.allocator.free(phi.inputs);
            block.phis.deinit(self.allocator);
            for (block.instructions.items) |instruction| switch (instruction) {
                .call => |call| self.allocator.free(call.arguments),
                else => {},
            };
            block.instructions.deinit(self.allocator);
        }
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

    pub fn appendCopy(self: *Function, block_id: BlockId, ty: ScalarType, operand: Operand) BuildError!ValueId {
        const target = try self.getBlock(block_id);
        if (target.terminator != null) return error.BlockTerminated;
        if (try self.operandType(operand) != ty) return error.TypeMismatch;
        const result = try self.nextValueId();
        try self.values.ensureUnusedCapacity(self.allocator, 1);
        try target.instructions.ensureUnusedCapacity(self.allocator, 1);
        self.values.appendAssumeCapacity(.{ .scalar_type = ty, .definition = .{ .instruction = .{ .block = block_id, .index = target.instructions.items.len } } });
        target.instructions.appendAssumeCapacity(.{ .copy = .{ .result = result, .operand = operand } });
        return result;
    }

    /// Reserve a typed value for forward references. Finish it with a define
    /// builder before validation. Failed define calls leave it pending/retryable.
    pub fn declareValue(self: *Function, ty: ScalarType) BuildError!ValueId {
        const id = try self.nextValueId();
        try self.values.append(self.allocator, .{ .scalar_type = ty, .definition = .pending });
        return id;
    }

    pub fn defineBinary(self: *Function, block_id: BlockId, result: ValueId, op: BinaryOp, lhs: Operand, rhs: Operand) BuildError!void {
        const target = try self.getBlock(block_id);
        if (target.terminator != null) return error.BlockTerminated;
        const value = try self.pendingValue(result);
        try self.checkBinary(value.scalar_type, op, lhs, rhs);
        try target.instructions.ensureUnusedCapacity(self.allocator, 1);
        value.definition = .{ .instruction = .{ .block = block_id, .index = target.instructions.items.len } };
        target.instructions.appendAssumeCapacity(.{ .binary = .{ .result = result, .op = op, .lhs = lhs, .rhs = rhs } });
    }

    pub fn appendBlit(self: *Function, block: BlockId, source: Operand, destination: Operand, byte_count: u31) BuildError!void {
        const target = try self.getBlock(block);
        if (target.terminator != null) return error.BlockTerminated;
        if (try self.operandType(source) != .long or try self.operandType(destination) != .long) return error.TypeMismatch;
        try target.instructions.append(self.allocator, .{ .blit = .{ .source = source, .destination = destination, .byte_count = byte_count } });
    }

    pub fn defineLoad(self: *Function, block: BlockId, result: ValueId, kind: LoadKind, address: Operand) BuildError!void {
        const target = try self.getBlock(block);
        if (target.terminator != null) return error.BlockTerminated;
        const value = try self.pendingValue(result);
        if (!kind.accepts(value.scalar_type) or try self.operandType(address) != .long) return error.TypeMismatch;
        try target.instructions.ensureUnusedCapacity(self.allocator, 1);
        value.definition = .{ .instruction = .{ .block = block, .index = target.instructions.items.len } };
        target.instructions.appendAssumeCapacity(.{ .load = .{ .result = result, .kind = kind, .address = address } });
    }

    pub fn appendStore(self: *Function, block: BlockId, kind: StoreKind, value: Operand, address: Operand) BuildError!void {
        const target = try self.getBlock(block);
        if (target.terminator != null) return error.BlockTerminated;
        if (try self.operandType(value) != kind.valueType() or try self.operandType(address) != .long) return error.TypeMismatch;
        try target.instructions.append(self.allocator, .{ .store = .{ .kind = kind, .value = value, .address = address } });
    }

    pub fn defineCopy(self: *Function, block_id: BlockId, result: ValueId, operand: Operand) BuildError!void {
        const target = try self.getBlock(block_id);
        if (target.terminator != null) return error.BlockTerminated;
        const value = try self.pendingValue(result);
        if (try self.operandType(operand) != value.scalar_type) return error.TypeMismatch;
        try target.instructions.ensureUnusedCapacity(self.allocator, 1);
        value.definition = .{ .instruction = .{ .block = block_id, .index = target.instructions.items.len } };
        target.instructions.appendAssumeCapacity(.{ .copy = .{ .result = result, .operand = operand } });
    }

    pub fn defineConvert(self: *Function, block: BlockId, result: ValueId, op: ConvertOp, operand: Operand) BuildError!void {
        const target = try self.getBlock(block);
        if (target.terminator != null) return error.BlockTerminated;
        const value = try self.pendingValue(result);
        if (try self.operandType(operand) != try op.operandType(value.scalar_type)) return error.TypeMismatch;
        try target.instructions.ensureUnusedCapacity(self.allocator, 1);
        value.definition = .{ .instruction = .{ .block = block, .index = target.instructions.items.len } };
        target.instructions.appendAssumeCapacity(.{ .convert = .{ .result = result, .op = op, .operand = operand } });
    }

    pub fn defineUnary(self: *Function, block_id: BlockId, result: ValueId, op: UnaryOp, operand: Operand) BuildError!void {
        const target = try self.getBlock(block_id);
        if (target.terminator != null) return error.BlockTerminated;
        const value = try self.pendingValue(result);
        try self.checkUnary(value.scalar_type, op, operand);
        try target.instructions.ensureUnusedCapacity(self.allocator, 1);
        value.definition = .{ .instruction = .{ .block = block_id, .index = target.instructions.items.len } };
        target.instructions.appendAssumeCapacity(.{ .unary = .{ .result = result, .op = op, .operand = operand } });
    }

    pub fn defineShift(self: *Function, block_id: BlockId, result: ValueId, op: ShiftOp, operand: Operand, amount: Operand) BuildError!void {
        const target = try self.getBlock(block_id);
        if (target.terminator != null) return error.BlockTerminated;
        const value = try self.pendingValue(result);
        try self.checkShift(value.scalar_type, operand, amount);
        try target.instructions.ensureUnusedCapacity(self.allocator, 1);
        value.definition = .{ .instruction = .{ .block = block_id, .index = target.instructions.items.len } };
        target.instructions.appendAssumeCapacity(.{ .shift = .{ .result = result, .op = op, .value = operand, .amount = amount } });
    }

    pub fn defineFloatCompare(self: *Function, block_id: BlockId, result: ValueId, predicate: FloatPredicate, operand_type: FloatType, lhs: Operand, rhs: Operand) BuildError!void {
        const target = try self.getBlock(block_id);
        if (target.terminator != null) return error.BlockTerminated;
        const value = try self.pendingValue(result);
        try self.checkFloatCompare(value.scalar_type, operand_type, lhs, rhs);
        try target.instructions.ensureUnusedCapacity(self.allocator, 1);
        value.definition = .{ .instruction = .{ .block = block_id, .index = target.instructions.items.len } };
        target.instructions.appendAssumeCapacity(.{ .compare_float = .{ .result = result, .predicate = predicate, .operand_type = operand_type, .lhs = lhs, .rhs = rhs } });
    }

    pub fn defineIntegerCompare(self: *Function, block_id: BlockId, result: ValueId, predicate: IntegerPredicate, operand_type: IntegerType, lhs: Operand, rhs: Operand) BuildError!void {
        const target = try self.getBlock(block_id);
        if (target.terminator != null) return error.BlockTerminated;
        const value = try self.pendingValue(result);
        try self.checkIntegerCompare(value.scalar_type, operand_type, lhs, rhs);
        try target.instructions.ensureUnusedCapacity(self.allocator, 1);
        value.definition = .{ .instruction = .{ .block = block_id, .index = target.instructions.items.len } };
        target.instructions.appendAssumeCapacity(.{ .compare_integer = .{ .result = result, .predicate = predicate, .operand_type = operand_type, .lhs = lhs, .rhs = rhs } });
    }

    /// Argument storage is duplicated before publication. Failed type checks or
    /// allocations leave a scalar result pending and retryable.
    pub fn defineCall(self: *Function, block: BlockId, result: ValueId, symbol: SymbolId, arguments: []const CallArgument) BuildError!void {
        return self.addCall(block, result, .{ .symbol = symbol }, arguments);
    }

    pub fn defineIndirectCall(self: *Function, block: BlockId, result: ValueId, address: Operand, arguments: []const CallArgument) BuildError!void {
        return self.addCall(block, result, .{ .address = address }, arguments);
    }

    /// A void call adds an effect, not an SSA definition or dummy value.
    pub fn appendVoidCall(self: *Function, block: BlockId, symbol: SymbolId, arguments: []const CallArgument) BuildError!void {
        return self.addCall(block, null, .{ .symbol = symbol }, arguments);
    }

    pub fn appendVoidIndirectCall(self: *Function, block: BlockId, address: Operand, arguments: []const CallArgument) BuildError!void {
        return self.addCall(block, null, .{ .address = address }, arguments);
    }

    fn addCall(self: *Function, block_id: BlockId, result: ?ValueId, callee: CallTarget, arguments: []const CallArgument) BuildError!void {
        const target = try self.getBlock(block_id);
        if (target.terminator != null) return error.BlockTerminated;
        const value = if (result) |id| try self.pendingValue(id) else null;
        try self.checkCallTarget(callee);
        try self.checkArguments(arguments);
        try target.instructions.ensureUnusedCapacity(self.allocator, 1);
        const owned = try self.allocator.dupe(CallArgument, arguments);
        if (value) |definition| definition.definition = .{ .instruction = .{ .block = block_id, .index = target.instructions.items.len } };
        target.instructions.appendAssumeCapacity(.{ .call = .{ .result = result, .callee = callee, .arguments = owned } });
    }

    fn checkCallTarget(self: *const Function, target: CallTarget) ValidationError!void {
        if (target.addressOperand()) |operand| if (try self.operandType(operand) != .long) return error.TypeMismatch;
    }

    fn checkArguments(self: *const Function, arguments: []const CallArgument) ValidationError!void {
        for (arguments) |argument| if (try self.operandType(argument.operand) != argument.scalar_type) return error.TypeMismatch;
    }

    pub fn definePhi(self: *Function, block_id: BlockId, result: ValueId, inputs: []const PhiInput) BuildError!void {
        const target = try self.getBlock(block_id);
        if (target.terminator != null) return error.BlockTerminated;
        if (target.instructions.items.len != 0) return error.PhiAfterInstructions;
        const value = try self.pendingValue(result);
        if (inputs.len == 0) return error.InvalidPhi;
        for (inputs) |input| {
            if (@backingInt(input.predecessor) >= self.blocks.items.len) return error.InvalidBlock;
            if (try self.operandType(input.value) != value.scalar_type) return error.TypeMismatch;
        }
        try target.phis.ensureUnusedCapacity(self.allocator, 1);
        const owned = try self.allocator.dupe(PhiInput, inputs);
        value.definition = .{ .phi = .{ .block = block_id, .index = target.phis.items.len } };
        target.phis.appendAssumeCapacity(.{ .result = result, .inputs = owned });
    }

    fn pendingValue(self: *Function, id: ValueId) ValidationError!*Value {
        if (@backingInt(id) >= self.values.items.len) return error.InvalidValue;
        const value = &self.values.items[@backingInt(id)];
        if (value.definition != .pending) return error.InvalidDefinition;
        return value;
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

    /// Checks structure/types only. Also call ssa.validate for current scalar
    /// use ordering/dominance and phi edges. Full IL verification remains future work.
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
            .pending => return error.InvalidDefinition,
            .phi => |definition| {
                if (@backingInt(definition.block) >= self.blocks.items.len) return error.InvalidDefinition;
                const phis = self.blocks.items[@backingInt(definition.block)].phis.items;
                if (definition.index >= phis.len or @backingInt(phis[definition.index].result) != number) return error.InvalidDefinition;
            },
            .parameter => |index| {
                if (index >= self.parameters.items.len or @backingInt(self.parameters.items[index]) != number)
                    return error.InvalidDefinition;
            },
            .instruction => |definition| {
                if (@backingInt(definition.block) >= self.blocks.items.len) return error.InvalidDefinition;
                const instructions = self.blocks.items[@backingInt(definition.block)].instructions.items;
                if (definition.index >= instructions.len) return error.InvalidDefinition;
                if (@backingInt(instructions[definition.index].result() orelse return error.InvalidDefinition) != number) return error.InvalidDefinition;
            },
        };
        for (self.blocks.items, 0..) |b, number| {
            for (b.phis.items, 0..) |phi, index| {
                const ty = try self.operandType(.{ .value = phi.result });
                switch (self.values.items[@backingInt(phi.result)].definition) {
                    .phi => |definition| {
                        if (@backingInt(definition.block) != number or definition.index != index) return error.InvalidDefinition;
                    },
                    else => return error.InvalidDefinition,
                }
                if (phi.inputs.len == 0) return error.InvalidPhi;
                for (phi.inputs) |input| {
                    if (@backingInt(input.predecessor) >= self.blocks.items.len) return error.InvalidBlock;
                    if (try self.operandType(input.value) != ty) return error.TypeMismatch;
                }
            }
            for (b.instructions.items, 0..) |instruction, index| {
                var ty: ?ScalarType = null;
                if (instruction.result()) |result| {
                    ty = try self.operandType(.{ .value = result });
                    switch (self.values.items[@backingInt(result)].definition) {
                        .instruction => |definition| {
                            if (@backingInt(definition.block) != number or definition.index != index) return error.InvalidDefinition;
                        },
                        else => return error.InvalidDefinition,
                    }
                }
                switch (instruction) {
                    .blit => |blit| {
                        if (try self.operandType(blit.source) != .long or try self.operandType(blit.destination) != .long) return error.TypeMismatch;
                    },
                    .load => |load| {
                        if (!load.kind.accepts(ty.?) or try self.operandType(load.address) != .long) return error.TypeMismatch;
                    },
                    .store => |store| {
                        if (try self.operandType(store.value) != store.kind.valueType() or try self.operandType(store.address) != .long) return error.TypeMismatch;
                    },
                    .call => |call| {
                        try self.checkCallTarget(call.callee);
                        try self.checkArguments(call.arguments);
                    },
                    .binary => |binary| try self.checkBinary(ty.?, binary.op, binary.lhs, binary.rhs),
                    .copy => |copy| if (try self.operandType(copy.operand) != ty.?) return error.TypeMismatch,
                    .unary => |unary| try self.checkUnary(ty.?, unary.op, unary.operand),
                    .convert => |conversion| {
                        if (try self.operandType(conversion.operand) != try conversion.op.operandType(ty.?)) return error.TypeMismatch;
                    },
                    .shift => |shift| try self.checkShift(ty.?, shift.value, shift.amount),
                    .compare_float => |comparison| try self.checkFloatCompare(ty.?, comparison.operand_type, comparison.lhs, comparison.rhs),
                    .compare_integer => |comparison| try self.checkIntegerCompare(ty.?, comparison.operand_type, comparison.lhs, comparison.rhs),
                }
            }
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
            .bit_and, .bit_or, .bit_xor, .unsigned_divide, .signed_remainder, .unsigned_remainder => if (!ty.isInteger()) return error.TypeMismatch,
            else => {},
        }
    }

    fn checkUnary(self: *const Function, ty: ScalarType, op: UnaryOp, operand: Operand) ValidationError!void {
        if (try self.operandType(operand) != try op.operandType(ty)) return error.TypeMismatch;
    }

    fn checkShift(self: *const Function, ty: ScalarType, value: Operand, amount: Operand) ValidationError!void {
        if (!ty.isInteger() or try self.operandType(value) != ty or try self.operandType(amount) != .word) return error.TypeMismatch;
    }

    fn checkFloatCompare(self: *const Function, result_type: ScalarType, operand_type: FloatType, lhs: Operand, rhs: Operand) ValidationError!void {
        if (!result_type.isInteger() or try self.operandType(lhs) != operand_type.scalar() or try self.operandType(rhs) != operand_type.scalar()) return error.TypeMismatch;
    }

    fn checkIntegerCompare(self: *const Function, result_type: ScalarType, operand_type: IntegerType, lhs: Operand, rhs: Operand) ValidationError!void {
        if (!result_type.isInteger() or try self.operandType(lhs) != operand_type.scalar() or try self.operandType(rhs) != operand_type.scalar()) return error.TypeMismatch;
    }

    fn checkTerminator(self: *const Function, terminator: Terminator) ValidationError!void {
        switch (terminator) {
            .halt => {},
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
    try @import("test_support.zig").checkAllocationFailures(exerciseGrowth);
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

test "copy is typed and participates in definition validation" {
    var f = Function.init(testing.allocator, test_name, .double);
    defer f.deinit();
    const b = try f.addBlock(null);
    const input: Operand = .{ .constant = .{ .double_bits = 0x7ff8000000000042 } };
    try testing.expectError(error.TypeMismatch, f.appendCopy(b, .word, input));
    const value = try f.appendCopy(b, .double, input);
    try f.terminate(b, .{ .return_value = .{ .value = value } });
    try f.validateStructure();
    try testing.expectEqual(@as(?ValueId, value), f.blocks.items[0].instructions.items[0].result());
    try testing.expectEqual(@as(u64, 0x7ff8000000000042), f.blocks.items[0].instructions.items[0].copy.operand.constant.double_bits);
}

test "forward declarations must be completed and cannot be redefined" {
    var f = Function.init(testing.allocator, test_name, .word);
    defer f.deinit();
    const b = try f.addBlock(null);
    const value = try f.declareValue(.word);
    try f.terminate(b, .{ .return_value = .{ .value = value } });
    try testing.expectError(error.InvalidDefinition, f.validateStructure());
    f.blocks.items[0].terminator = null;
    try testing.expectError(error.TypeMismatch, f.defineCopy(b, value, .{ .constant = .{ .long = 1 } }));
    try testing.expect(f.values.items[@backingInt(value)].definition == .pending);
    try f.defineCopy(b, value, one);
    try testing.expectError(error.InvalidDefinition, f.defineCopy(b, value, one));
    try f.terminate(b, .{ .return_value = .{ .value = value } });
    try f.validateStructure();
}

test "phi input ownership and retry after either allocation fails" {
    for (0..2) |failure_offset| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{});
        var f = Function.init(failing.allocator(), test_name, .word);
        defer f.deinit();
        const entry = try f.addBlock(null);
        const join = try f.addBlock(null);
        const result = try f.declareValue(.word);
        var inputs = [_]PhiInput{.{ .predecessor = entry, .value = one }};
        failing.fail_index = failing.alloc_index + failure_offset;
        try testing.expectError(error.OutOfMemory, f.definePhi(join, result, &inputs));
        try testing.expect(f.values.items[@backingInt(result)].definition == .pending);
        try testing.expectEqual(@as(usize, 0), f.blocks.items[@backingInt(join)].phis.items.len);
        failing.fail_index = std.math.maxInt(usize);
        try f.definePhi(join, result, &inputs);
        inputs[0].value = .{ .constant = .{ .word = 99 } };
        try testing.expectEqual(@as(u32, 1), f.blocks.items[@backingInt(join)].phis.items[0].inputs[0].value.constant.word);
        try f.terminate(entry, .{ .jump = join });
        try f.terminate(join, .{ .return_value = .{ .value = result } });
        try f.validateStructure();
        f.values.items[@backingInt(result)].definition.phi.index = 99;
        try testing.expectError(error.InvalidDefinition, f.validateStructure());
    }
}

test "unary builder rejects bad types and permits retry after failed allocation" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{});
    var f = Function.init(failing.allocator(), test_name, .long);
    defer f.deinit();
    const b = try f.addBlock(null);
    const value = try f.declareValue(.long);
    try testing.expectError(error.TypeMismatch, f.defineUnary(b, value, .sign_extend_byte, .{ .constant = .{ .long = 255 } }));
    try testing.expect(f.values.items[@backingInt(value)].definition == .pending);
    failing.fail_index = failing.alloc_index;
    try testing.expectError(error.OutOfMemory, f.defineUnary(b, value, .sign_extend_byte, .{ .constant = .{ .word = 255 } }));
    try testing.expect(f.values.items[@backingInt(value)].definition == .pending);
    try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
    failing.fail_index = std.math.maxInt(usize);
    try f.defineUnary(b, value, .sign_extend_byte, .{ .constant = .{ .word = 255 } });
    try f.terminate(b, .{ .return_value = .{ .value = value } });
    try f.validateStructure();
    f.blocks.items[0].instructions.items[0].unary.operand = .{ .constant = .{ .long = 255 } };
    try testing.expectError(error.TypeMismatch, f.validateStructure());
}

test "floating comparison builder validates types and retries after allocation failure" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{});
    var f = Function.init(failing.allocator(), test_name, .word);
    defer f.deinit();
    const b = try f.addBlock(null);
    const value = try f.declareValue(.word);
    const operand: Operand = .{ .constant = .{ .single_bits = 0 } };
    try testing.expectError(error.TypeMismatch, f.defineFloatCompare(b, value, .equal, .double, operand, operand));
    try testing.expect(f.values.items[@backingInt(value)].definition == .pending);
    failing.fail_index = failing.alloc_index;
    try testing.expectError(error.OutOfMemory, f.defineFloatCompare(b, value, .equal, .single, operand, operand));
    try testing.expect(f.values.items[@backingInt(value)].definition == .pending);
    try testing.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
    failing.fail_index = std.math.maxInt(usize);
    try f.defineFloatCompare(b, value, .equal, .single, operand, operand);
    try f.terminate(b, .{ .return_value = .{ .value = value } });
    try f.validateStructure();
    f.blocks.items[0].instructions.items[0].compare_float.operand_type = .double;
    try testing.expectError(error.TypeMismatch, f.validateStructure());
}

test "halt terminates void and every scalar result class without a return operand" {
    for ([_]?ScalarType{ null, .word, .long, .single, .double }) |result_type| {
        var f = Function.init(testing.allocator, test_name, result_type);
        defer f.deinit();
        const block = try f.addBlock(null);
        try f.terminate(block, .halt);
        try f.validateStructure();
        try testing.expectError(error.BlockTerminated, f.terminate(block, .halt));
        try testing.expectError(error.BlockTerminated, f.appendCopy(block, .word, one));
    }
}
