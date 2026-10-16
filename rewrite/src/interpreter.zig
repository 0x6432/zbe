const std = @import("std");
const ir = @import("ir.zig");
const ssa = @import("ssa.zig");
const semantics = @import("semantics.zig");
const memory = @import("memory.zig");
const module_validation = @import("module_validation.zig");
const Module = @import("module.zig").Module;
const FunctionId = @import("module.zig").FunctionId;

pub const Options = struct {
    max_steps: usize = 100_000,
    /// Borrowed for this invocation and all child frames; no host address space.
    memory_image: ?*memory.Image = null,
    /// Total active invocation frames, including the entry function.
    max_call_depth: usize = 64,
};
pub const ArithmeticError = semantics.ArithmeticError;
pub const Error = semantics.ConversionError || ArithmeticError || memory.Error || module_validation.Error || error{
    ArgumentCountMismatch,
    ArgumentTypeMismatch,
    StepLimitExceeded,
    UninitializedValue,
    Halted,
    UnsupportedCall,
    UnsupportedExternalCall,
    UnsupportedIndirectCall,
    UnsupportedMemory,
    InvalidFunction,
    CallDepthLimitExceeded,
};

/// Standalone scalar evaluator. Reached calls remain UnsupportedCall because
/// this API supplies no module resolver. Never executes arbitrary host code.
pub fn evaluate(allocator: std.mem.Allocator, function: *const ir.Function, arguments: []const ir.Constant, options: Options) Error!?ir.Constant {
    var issue: ?ssa.Issue = null;
    try ssa.validate(allocator, function, &issue);
    return execute(allocator, null, function, arguments, options);
}

/// Validate every module body/signature once, then execute internal direct calls
/// with an explicit owned frame stack. One shared step budget spans all frames;
/// external targets are never called. Function IDs belong to this module.
pub fn evaluateModule(allocator: std.mem.Allocator, module: *const Module, entry: FunctionId, arguments: []const ir.Constant, options: Options) Error!?ir.Constant {
    const index = @backingInt(entry);
    if (index >= module.functions.items.len) return error.InvalidFunction;
    try module_validation.validate(allocator, module);
    return execute(allocator, module, module.functions.items[index], arguments, options);
}

const Frame = struct {
    function: *const ir.Function,
    values: []?ir.Constant,
    phi_values: []ir.Constant,
    block: ir.BlockId = @fromBackingInt(@as(u32, 0)),
    previous: ?ir.BlockId = null,
    entered: bool = false,
    next_instruction: usize = 0,
    return_destination: ?ir.ValueId,

    fn init(allocator: std.mem.Allocator, function: *const ir.Function, arguments: []const ir.Constant, destination: ?ir.ValueId) Error!Frame {
        if (arguments.len != function.parameters.items.len) return error.ArgumentCountMismatch;
        for (function.parameters.items, arguments) |parameter, argument| {
            if (function.values.items[@backingInt(parameter)].scalar_type != argument.scalarType()) return error.ArgumentTypeMismatch;
        }
        const values = try allocator.alloc(?ir.Constant, function.values.items.len);
        errdefer allocator.free(values);
        @memset(values, null);
        for (function.parameters.items, arguments) |parameter, argument| values[@backingInt(parameter)] = argument;
        var max_phis: usize = 0;
        for (function.blocks.items) |block| max_phis = @max(max_phis, block.phis.items.len);
        const phis = try allocator.alloc(ir.Constant, max_phis);
        return .{ .function = function, .values = values, .phi_values = phis, .return_destination = destination };
    }

    fn deinit(self: *Frame, allocator: std.mem.Allocator) void {
        allocator.free(self.values);
        allocator.free(self.phi_values);
        self.* = undefined;
    }
};

fn appendFrame(allocator: std.mem.Allocator, frames: *std.ArrayList(Frame), function: *const ir.Function, arguments: []const ir.Constant, destination: ?ir.ValueId) Error!void {
    var frame = try Frame.init(allocator, function, arguments, destination);
    errdefer frame.deinit(allocator);
    try frames.append(allocator, frame);
}

fn execute(allocator: std.mem.Allocator, module: ?*const Module, function: *const ir.Function, arguments: []const ir.Constant, options: Options) Error!?ir.Constant {
    if (options.max_call_depth == 0) return error.CallDepthLimitExceeded;
    var frames: std.ArrayList(Frame) = .empty;
    defer {
        for (frames.items) |*frame| frame.deinit(allocator);
        frames.deinit(allocator);
    }
    try appendFrame(allocator, &frames, function, arguments, null);
    var remaining = options.max_steps;
    while (true) {
        // Do not retain this pointer across appendFrame: the handle array may
        // grow/move, whereas each invocation's separately owned values stay put.
        const frame = &frames.items[frames.items.len - 1];
        const block = &frame.function.blocks.items[@backingInt(frame.block)];
        if (!frame.entered) {
            for (block.phis.items, 0..) |phi, index| {
                try step(&remaining);
                const predecessor = frame.previous orelse return error.UninitializedValue;
                const incoming = incoming: {
                    for (phi.inputs) |input| if (input.predecessor == predecessor) break :incoming input.value;
                    return error.UninitializedValue;
                };
                frame.phi_values[index] = try resolve(frame.values, incoming);
            }
            for (block.phis.items, frame.phi_values[0..block.phis.items.len]) |phi, value| frame.values[@backingInt(phi.result)] = value;
            frame.entered = true;
        }
        if (frame.next_instruction < block.instructions.items.len) {
            try step(&remaining);
            const instruction = block.instructions.items[frame.next_instruction];
            frame.next_instruction += 1;
            switch (instruction) {
                .blit => |blit| {
                    const image = options.memory_image orelse return error.UnsupportedMemory;
                    const src = (try resolve(frame.values, blit.source)).long;
                    const dst = (try resolve(frame.values, blit.destination)).long;
                    try image.copy(src, dst, blit.byte_count);
                    continue;
                },
                .load => |read| {
                    const image = options.memory_image orelse return error.UnsupportedMemory;
                    const address = (try resolve(frame.values, read.address)).long;
                    const ty = frame.function.values.items[@backingInt(read.result)].scalar_type;
                    frame.values[@backingInt(read.result)] = try image.read(read.kind, ty, address);
                    continue;
                },
                .store => |store| {
                    const image = options.memory_image orelse return error.UnsupportedMemory;
                    const address = (try resolve(frame.values, store.address)).long;
                    try image.write(store.kind, try resolve(frame.values, store.value), address);
                    continue;
                },
                else => {},
            }
            if (instruction == .call) {
                const call = instruction.call;
                const owner = module orelse return error.UnsupportedCall;
                const symbol = switch (call.callee) {
                    .symbol => |symbol| symbol,
                    .address => return error.UnsupportedIndirectCall,
                };
                const callee = module_validation.findFunction(owner, symbol) orelse return error.UnsupportedExternalCall;
                if (frames.items.len >= options.max_call_depth) return error.CallDepthLimitExceeded;
                const actual = try allocator.alloc(ir.Constant, call.arguments.len);
                defer allocator.free(actual);
                for (call.arguments, actual) |argument, *value| value.* = try resolve(frame.values, argument.operand);
                try appendFrame(allocator, &frames, callee, actual, call.result);
                continue; // The old frame pointer may now be invalid.
            }
            frame.values[@backingInt(instruction.result().?)] = try scalarInstruction(frame.function, frame.values, instruction);
            continue;
        }
        try step(&remaining);
        const next = switch (block.terminator.?) {
            .halt => return error.Halted,
            .jump => |target| target,
            .branch => |branch| branch_target: {
                const condition = try resolve(frame.values, branch.condition);
                break :branch_target if (try condition.branchTaken()) branch.taken else branch.not_taken;
            },
            .return_value => |operand| {
                const value = if (operand) |v| try resolve(frame.values, v) else null;
                var completed = frames.pop().?;
                const destination = completed.return_destination;
                completed.deinit(allocator);
                if (frames.items.len == 0) return value;
                if (destination) |result| {
                    frames.items[frames.items.len - 1].values[@backingInt(result)] = value orelse return error.InvalidReturn;
                } else if (value != null) return error.InvalidReturn;
                continue;
            },
        };
        frame.previous = frame.block;
        frame.block = next;
        frame.entered = false;
        frame.next_instruction = 0;
    }
}

fn scalarInstruction(function: *const ir.Function, values: []const ?ir.Constant, instruction: ir.Instruction) Error!ir.Constant {
    return switch (instruction) {
        .load, .store, .blit => error.UnsupportedMemory,
        .call => error.UnsupportedCall,
        .copy => |copy| try resolve(values, copy.operand),
        .convert => |c| try semantics.convertedValue(c.op, try resolve(values, c.operand), function.values.items[@backingInt(c.result)].scalar_type),
        .unary => |unary| semantics.unaryValue(unary.op, try resolve(values, unary.operand), function.values.items[@backingInt(unary.result)].scalar_type),
        .shift => |shift| semantics.shiftedValue(shift.op, try resolve(values, shift.value), (try resolve(values, shift.amount)).word),
        .compare_float => |comparison| semantics.floatComparisonValue(comparison.predicate, try resolve(values, comparison.lhs), try resolve(values, comparison.rhs), function.values.items[@backingInt(comparison.result)].scalar_type),
        .compare_integer => |comparison| semantics.comparisonValue(comparison.predicate, try resolve(values, comparison.lhs), try resolve(values, comparison.rhs), function.values.items[@backingInt(comparison.result)].scalar_type),
        .binary => |binary| try semantics.binaryValue(binary.op, try resolve(values, binary.lhs), try resolve(values, binary.rhs)),
    };
}

fn step(remaining: *usize) error{StepLimitExceeded}!void {
    if (remaining.* == 0) return error.StepLimitExceeded;
    remaining.* -= 1;
}

fn resolve(values: []const ?ir.Constant, operand: ir.Operand) error{UninitializedValue}!ir.Constant {
    return switch (operand) {
        .constant => |constant| constant,
        .value => |value| values[@backingInt(value)] orelse error.UninitializedValue,
    };
}

const testing = std.testing;
const frontend = @import("frontend.zig");
const source = @import("source.zig");

fn parse(text: []const u8) !@import("module.zig").Module {
    var diagnostic: ?source.Diagnostic = null;
    return frontend.parse(testing.allocator, .{ .name = "interpreter-test", .text = text }, &diagnostic);
}

test "constant-jump regression evaluates all four functions with low-word semantics" {
    var module = try parse(@embedFile("fixtures/constant-jump.ssa"));
    defer module.deinit();
    for (module.functions.items, [_]u32{ 0, 0, 0, 1 }) |function, expected| {
        const result = try evaluate(testing.allocator, function, &.{}, .{});
        try testing.expectEqual(expected, result.?.word);
    }
}

test "integer operations wrap at their declared width" {
    const cases = .{
        .{ "w", "add 4294967295, 1", @as(u64, 0) },
        .{ "w", "sub 0, 1", @as(u64, 0xffffffff) },
        .{ "w", "mul 65536, 65536", @as(u64, 0) },
        .{ "l", "add 18446744073709551615, 1", @as(u64, 0) },
        .{ "l", "sub 0, 1", @as(u64, 0xffffffffffffffff) },
        .{ "l", "mul 1099511627776, 1099511627776", @as(u64, 0) },
        .{ "w", "and 4042322160, 252645135", @as(u64, 0) },
        .{ "w", "or 4042322160, 252645135", @as(u64, 0xffffffff) },
        .{ "l", "xor 12297829382473034410, 6148914691236517205", @as(u64, 0xffffffffffffffff) },
    };
    inline for (cases) |case| {
        var module = try parse("function " ++ case[0] ++ " $f() {\n@b\n%x =" ++ case[0] ++ " " ++ case[1] ++ "\nret %x\n}");
        defer module.deinit();
        const result = (try evaluate(testing.allocator, module.functions.items[0], &.{}, .{})).?;
        const bits: u64 = if (comptime std.mem.eql(u8, case[0], "w")) result.word else result.long;
        try testing.expectEqual(case[2], bits);
    }
}

test "long parameter branches use the low word and invocation state is isolated" {
    var module = try parse("function w $f(l %condition) {\n@entry\njnz %condition, @yes, @no\n@yes\nret 1\n@no\nret 0\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    for ([_]u64{ 1 << 40, (1 << 40) | 1, 0xffffffff00000000, 0x80000000 }, [_]u32{ 0, 1, 0, 1 }) |bits, expected| {
        const result = try evaluate(testing.allocator, f, &.{.{ .long = bits }}, .{});
        try testing.expectEqual(expected, result.?.word);
    }
    try testing.expectError(error.ArgumentCountMismatch, evaluate(testing.allocator, f, &.{}, .{}));
    try testing.expectError(error.ArgumentTypeMismatch, evaluate(testing.allocator, f, &.{.{ .word = 1 }}, .{}));
}

test "floating arithmetic has explicit width and copy retains signed zero" {
    var module = try parse("function d $f(d %a) {\n@entry\n%x =d mul %a, d_2\n%y =d sub %x, d_1\n%z =d add %y, d_0.5\nret %z\n}\nfunction s $zero() {\n@entry\n%x =s copy s_-0\nret %x\n}");
    defer module.deinit();
    const result = try evaluate(testing.allocator, module.functions.items[0], &.{.{ .double_bits = @bitCast(@as(f64, 1.25)) }}, .{});
    try testing.expectEqual(@as(u64, @bitCast(@as(f64, 2))), result.?.double_bits);
    const zero = try evaluate(testing.allocator, module.functions.items[1], &.{}, .{});
    try testing.expectEqual(@as(u32, 0x80000000), zero.?.single_bits);
}

test "exact instruction budgets bound both finite and infinite execution" {
    var module = try parse("function w $finite() {\n@b\n%x =w copy 1\nret %x\n}\nfunction $loop() {\n@entry\njmp @b\n@b\njmp @b\n}\nfunction $void() {\n@b\nret\n}");
    defer module.deinit();
    try testing.expectError(error.StepLimitExceeded, evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .max_steps = 0 }));
    try testing.expectError(error.StepLimitExceeded, evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .max_steps = 1 }));
    try testing.expectEqual(@as(u32, 1), (try evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .max_steps = 2 })).?.word);
    try testing.expectError(error.StepLimitExceeded, evaluate(testing.allocator, module.functions.items[1], &.{}, .{ .max_steps = 17 }));
    try testing.expect((try evaluate(testing.allocator, module.functions.items[2], &.{}, .{ .max_steps = 1 })) == null);
}

test "execution rejects non-dominating uses before interpreting them" {
    var module = try parse("function w $f() {\n@entry\njnz 0, @left, @join\n@left\n%x =w copy 1\njmp @join\n@join\nret %x\n}");
    defer module.deinit();
    try testing.expectError(error.InvalidSSA, evaluate(testing.allocator, module.functions.items[0], &.{}, .{}));
}

test "copying a manually built NaN preserves payload bits" {
    var f = ir.Function.init(testing.allocator, @fromBackingInt(@as(u32, 0)), .double);
    defer f.deinit();
    const block = try f.addBlock(null);
    const value = try f.appendCopy(block, .double, .{ .constant = .{ .double_bits = 0xfff8000000001234 } });
    try f.terminate(block, .{ .return_value = .{ .value = value } });
    const result = try evaluate(testing.allocator, &f, &.{}, .{});
    try testing.expectEqual(@as(u64, 0xfff8000000001234), result.?.double_bits);
}

fn exercise(allocator: std.mem.Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "fixture", .text = @embedFile("fixtures/constant-jump.ssa") }, &diagnostic);
    defer module.deinit();
    for (module.functions.items, [_]u32{ 0, 0, 0, 1 }) |f, expected| {
        const result = try evaluate(allocator, f, &.{}, .{});
        try testing.expectEqual(expected, result.?.word);
    }
}

test "every evaluator allocation failure frees analysis and execution frames" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

test "384 Python arbitrary-precision oracle cases agree through parser and evaluator" {
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/integer-oracle.tsv"), '\n');
    var case_count: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const ty = fields.next() orelse return error.MalformedOracle;
        const op = std.meta.stringToEnum(ir.BinaryOp, fields.next() orelse return error.MalformedOracle) orelse return error.MalformedOracle;
        const lhs = try std.fmt.parseInt(u64, fields.next() orelse return error.MalformedOracle, 10);
        const rhs = try std.fmt.parseInt(u64, fields.next() orelse return error.MalformedOracle, 10);
        const expected = try std.fmt.parseInt(u64, fields.next() orelse return error.MalformedOracle, 10);
        try testing.expect(fields.next() == null);
        const mnemonic = switch (op) {
            .bit_and => "and",
            .bit_or => "or",
            .bit_xor => "xor",
            else => @tagName(op),
        };
        const text = try std.fmt.allocPrint(testing.allocator, "function {s} $f() {{\n@entry\n%x ={s} {s} {d}, {d}\nret %x\n}}", .{ ty, ty, mnemonic, lhs, rhs });
        defer testing.allocator.free(text);
        var module = try parse(text);
        defer module.deinit();
        const result = (try evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .max_steps = 2 })).?;
        const actual: u64 = if (std.mem.eql(u8, ty, "w")) result.word else result.long;
        try testing.expectEqual(expected, actual);
        case_count += 1;
    }
    try testing.expectEqual(@as(usize, 384), case_count);
}

test "phi loop swaps are simultaneous and consume exact step budgets" {
    var module = try parse(@embedFile("fixtures/phi-loop.ssa"));
    defer module.deinit();
    const f = module.functions.items[0];
    try testing.expectEqual(@as(usize, 3), f.blocks.items[1].phis.items.len);
    for (0..6) |count| {
        const budget = 6 + 6 * count;
        const arguments: []const ir.Constant = &.{.{ .word = @intCast(count) }};
        const result = try evaluate(testing.allocator, f, arguments, .{ .max_steps = budget });
        try testing.expectEqual(@as(u32, if (count % 2 == 0) 1 else 2), result.?.word);
        try testing.expectError(error.StepLimitExceeded, evaluate(testing.allocator, f, arguments, .{ .max_steps = budget - 1 }));
    }
}

test "diamond phi reads the value on its incoming edge, not at the join" {
    var module = try parse("function w $choose(w %p) {\n@entry\njnz %p, @left, @right\n@left\n%l =w copy 10\njmp @join\n@right\n%r =w copy 20\njmp @join\n@join\n%x =w phi @left %l, @right %r\nret %x\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    try testing.expectEqual(@as(u32, 20), (try evaluate(testing.allocator, f, &.{.{ .word = 0 }}, .{})).?.word);
    try testing.expectEqual(@as(u32, 10), (try evaluate(testing.allocator, f, &.{.{ .word = 1 }}, .{})).?.word);
}

fn exercisePhi(allocator: std.mem.Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "phi-loop", .text = @embedFile("fixtures/phi-loop.ssa") }, &diagnostic);
    defer module.deinit();
    const result = try evaluate(allocator, module.functions.items[0], &.{.{ .word = 3 }}, .{});
    try testing.expectEqual(@as(u32, 2), result.?.word);
}

test "every phi parsing, validation and evaluation allocation failure cleans up" {
    try @import("test_support.zig").checkAllocationFailures(exercisePhi);
}

test "layout-independent forward value definitions pass dominance verification" {
    var module = try parse("function w $f() {\n@entry\njmp @definition\n@use\nret %x\n@definition\n%x =w copy 9\njmp @use\n}");
    defer module.deinit();
    try testing.expectEqual(@as(u32, 9), (try evaluate(testing.allocator, module.functions.items[0], &.{}, .{})).?.word);
}

test "floating phi selection retains payload bits without arithmetic conversion" {
    var module = try parse("function d $f(w %p, d %a, d %b) {\n@entry\njnz %p, @left, @right\n@left\njmp @join\n@right\njmp @join\n@join\n%x =d phi @left %a, @right %b\nret %x\n}");
    defer module.deinit();
    const result = try evaluate(testing.allocator, module.functions.items[0], &.{ .{ .word = 1 }, .{ .double_bits = 0xfff8000000001234 }, .{ .double_bits = 0x8000000000000000 } }, .{});
    try testing.expectEqual(@as(u64, 0xfff8000000001234), result.?.double_bits);
}

test "Python oracle checks typed shifts and signed and unsigned comparisons" {
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/scalar-extra-oracle.tsv"), '\n');
    var case_count: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const ty = fields.next().?;
        const opcode = fields.next().?;
        const lhs = fields.next().?;
        const rhs = fields.next().?;
        const expected = try std.fmt.parseInt(u64, fields.next().?, 10);
        try testing.expect(fields.next() == null);
        const text = try std.fmt.allocPrint(testing.allocator, "function {s} $f() {{\n@entry\n%x ={s} {s} {s}, {s}\nret %x\n}}", .{ ty, ty, opcode, lhs, rhs });
        defer testing.allocator.free(text);
        var module = try parse(text);
        defer module.deinit();
        const result = (try evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .max_steps = 2 })).?;
        const actual: u64 = if (std.mem.eql(u8, ty, "w")) result.word else result.long;
        try testing.expectEqual(expected, actual);
        case_count += 1;
    }
    try testing.expectEqual(@as(usize, 832), case_count);
}

test "unsigned integer comparison controls a loop with two carried values" {
    var module = try parse(@embedFile("fixtures/compare-loop.ssa"));
    defer module.deinit();
    for ([_]u64{ 0, 1, 2, 10, 100 }) |n| {
        const result = (try evaluate(testing.allocator, module.functions.items[0], &.{.{ .long = n }}, .{})).?;
        try testing.expectEqual(if (n == 0) 0 else n * (n - 1) / 2, result.long);
    }
}

fn exerciseScalarExtra(allocator: std.mem.Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "scalar-extra", .text = @embedFile("fixtures/compare-loop.ssa") ++ "\nfunction l $shift(l %x, w %n) {\n@b\n%v =l sar %x, %n\n%r =l csltl %v, 0\nret %r\n}" }, &diagnostic);
    defer module.deinit();
    const result = (try evaluate(allocator, module.functions.items[1], &.{ .{ .long = 0x8000000000000000 }, .{ .word = 127 } }, .{})).?;
    try testing.expectEqual(@as(u64, 1), result.long);
}

test "scalar extension parsing and evaluation clean up every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exerciseScalarExtra);
}

test "Python oracle checks integer negation and sign and zero extensions" {
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/unary-oracle.tsv"), '\n');
    var case_count: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const ty = fields.next().?;
        const opcode = fields.next().?;
        _ = fields.next().?; // Operand width is established by the opcode.
        const operand = fields.next().?;
        const expected = try std.fmt.parseInt(u64, fields.next().?, 10);
        try testing.expect(fields.next() == null);
        const text = try std.fmt.allocPrint(testing.allocator, "function {s} $f() {{\n@entry\n%x ={s} {s} {s}\nret %x\n}}", .{ ty, ty, opcode, operand });
        defer testing.allocator.free(text);
        var module = try parse(text);
        defer module.deinit();
        const result = (try evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .max_steps = 2 })).?;
        const actual: u64 = if (std.mem.eql(u8, ty, "w")) result.word else result.long;
        try testing.expectEqual(expected, actual);
        case_count += 1;
    }
    try testing.expectEqual(@as(usize, 384), case_count);
}

test "floating negation flips only the sign bit including zero infinity and NaN payloads" {
    var module = try parse("function s $s(s %v) {\n@b\n%r =s neg %v\nret %r\n}\nfunction d $d(d %v) {\n@b\n%r =d neg %v\nret %r\n}");
    defer module.deinit();
    for ([_]u32{ 0, 0x80000000, 0x3f800000, 0x7f800000, 0xff800000, 0x7fc01234, 0xff801234 }) |bits| {
        const result = (try evaluate(testing.allocator, module.functions.items[0], &.{.{ .single_bits = bits }}, .{})).?;
        try testing.expectEqual(bits ^ @as(u32, 0x80000000), result.single_bits);
    }
    for ([_]u64{ 0, 0x8000000000000000, 0x3ff0000000000000, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000001234, 0xfff0000000001234 }) |bits| {
        const result = (try evaluate(testing.allocator, module.functions.items[1], &.{.{ .double_bits = bits }}, .{})).?;
        try testing.expectEqual(bits ^ @as(u64, 0x8000000000000000), result.double_bits);
    }
}

fn exerciseUnary(allocator: std.mem.Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "unary", .text = "function l $f(w %x) {\n@b\n%a =l extsb %x\n%r =l neg %a\nret %r\n}" }, &diagnostic);
    defer module.deinit();
    const result = (try evaluate(allocator, module.functions.items[0], &.{.{ .word = 255 }}, .{})).?;
    try testing.expectEqual(@as(u64, 1), result.long);
}

test "unary parsing and evaluation clean up every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exerciseUnary);
}

test "Python oracle checks truncating signed division and dividend sign remainders" {
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/division-oracle.tsv"), '\n');
    var case_count: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const ty = fields.next().?;
        const opcode = fields.next().?;
        const lhs = fields.next().?;
        const rhs = fields.next().?;
        const expected = try std.fmt.parseInt(u64, fields.next().?, 10);
        try testing.expect(fields.next() == null);
        const text = try std.fmt.allocPrint(testing.allocator, "function {s} $f() {{\n@b\n%x ={s} {s} {s}, {s}\nret %x\n}}", .{ ty, ty, opcode, lhs, rhs });
        defer testing.allocator.free(text);
        var module = try parse(text);
        defer module.deinit();
        const result = (try evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .max_steps = 2 })).?;
        const actual: u64 = if (std.mem.eql(u8, ty, "w")) result.word else result.long;
        try testing.expectEqual(expected, actual);
        case_count += 1;
    }
    try testing.expectEqual(@as(usize, 1228), case_count);
}

test "integer division exceptions are typed errors before unsafe host operations" {
    for ([_][]const u8{ "w", "l" }) |ty| {
        for ([_][]const u8{ "div", "udiv", "rem", "urem" }) |opcode| {
            const text = try std.fmt.allocPrint(testing.allocator, "function {s} $f({s} %a, {s} %b) {{\n@entry\n%x ={s} {s} %a, %b\nret %x\n}}", .{ ty, ty, ty, ty, opcode });
            defer testing.allocator.free(text);
            var module = try parse(text);
            defer module.deinit();
            const word = std.mem.eql(u8, ty, "w");
            const zero: ir.Constant = if (word) .{ .word = 0 } else .{ .long = 0 };
            const minimum: ir.Constant = if (word) .{ .word = 0x80000000 } else .{ .long = 0x8000000000000000 };
            const minus_one: ir.Constant = if (word) .{ .word = 0xffffffff } else .{ .long = 0xffffffffffffffff };
            try testing.expectError(error.DivisionByZero, evaluate(testing.allocator, module.functions.items[0], &.{ minimum, zero }, .{}));
            if (std.mem.eql(u8, opcode, "div") or std.mem.eql(u8, opcode, "rem")) {
                try testing.expectError(error.IntegerOverflow, evaluate(testing.allocator, module.functions.items[0], &.{ minimum, minus_one }, .{}));
            }
        }
    }
}

test "floating division uses strict width arithmetic rather than integer exception rules" {
    var module = try parse("function s $s(s %a, s %b) {\n@entry\n%r =s div %a, %b\nret %r\n}\nfunction d $d(d %a, d %b) {\n@entry\n%r =d div %a, %b\nret %r\n}");
    defer module.deinit();
    const single = (try evaluate(testing.allocator, module.functions.items[0], &.{ .{ .single_bits = @bitCast(@as(f32, 3)) }, .{ .single_bits = @bitCast(@as(f32, 2)) } }, .{})).?;
    try testing.expectEqual(@as(u32, @bitCast(@as(f32, 1.5))), single.single_bits);
    const double = (try evaluate(testing.allocator, module.functions.items[1], &.{ .{ .double_bits = @bitCast(@as(f64, -1)) }, .{ .double_bits = 0 } }, .{})).?;
    try testing.expectEqual(@as(u64, 0xfff0000000000000), double.double_bits);
}

fn exerciseDivisionError(allocator: std.mem.Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try frontend.parse(allocator, .{ .name = "division", .text = "function w $f(w %b) {\n@entry\n%x =w rem 1, %b\nret %x\n}" }, &diagnostic);
    defer module.deinit();
    _ = evaluate(allocator, module.functions.items[0], &.{.{ .word = 0 }}, .{}) catch |err| switch (err) {
        error.DivisionByZero => return,
        else => return err,
    };
    return error.ExpectedDivisionByZero;
}

test "division exception evaluation frees frames and analysis on every allocation failure" {
    try @import("test_support.zig").checkAllocationFailures(exerciseDivisionError);
}

test "mixed programs agree with independent Python results through diamonds and loop phis" {
    var module = try parse(@embedFile("fixtures/mixed-programs.ssa"));
    defer module.deinit();
    try testing.expectEqual(@as(usize, 32), module.functions.items.len);
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/mixed-programs.tsv"), '\n');
    var case_count: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const function_index = try std.fmt.parseInt(usize, fields.next().?, 10);
        const ty = fields.next().?;
        const a = try std.fmt.parseInt(u64, fields.next().?, 10);
        const b = try std.fmt.parseInt(u64, fields.next().?, 10);
        const count = try std.fmt.parseInt(u32, fields.next().?, 10);
        const expected = try std.fmt.parseInt(u64, fields.next().?, 10);
        try testing.expect(fields.next() == null);
        const word = std.mem.eql(u8, ty, "w");
        const args: []const ir.Constant = &.{ if (word) .{ .word = @intCast(a) } else .{ .long = a }, if (word) .{ .word = @intCast(b) } else .{ .long = b }, .{ .word = count } };
        const result = (try evaluate(testing.allocator, module.functions.items[function_index], args, .{ .max_steps = 128 })).?;
        try testing.expectEqual(expected, if (word) @as(u64, result.word) else result.long);
        case_count += 1;
    }
    try testing.expectEqual(@as(usize, 512), case_count);
}

test "floating arithmetic agrees with exact rational rounding oracle" {
    var module = try parse(@embedFile("fixtures/float-operations.ssa"));
    defer module.deinit();
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/float-oracle.tsv"), '\n');
    var case_count: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const ty = fields.next().?;
        const opcode = fields.next().?;
        const a = try std.fmt.parseInt(u64, fields.next().?, 10);
        const b = try std.fmt.parseInt(u64, fields.next().?, 10);
        const expected = try std.fmt.parseInt(u64, fields.next().?, 10);
        try testing.expect(fields.next() == null);
        const single = std.mem.eql(u8, ty, "s");
        var index: usize = if (single) 0 else 7;
        for ([_][]const u8{ "add", "sub", "mul", "div" }, 0..) |op, offset| {
            if (std.mem.eql(u8, opcode, op)) {
                index += offset;
                break;
            }
        } else return error.UnknownFixtureOpcode;
        const args: []const ir.Constant = &.{ if (single) .{ .single_bits = @intCast(a) } else .{ .double_bits = a }, if (single) .{ .single_bits = @intCast(b) } else .{ .double_bits = b } };
        const result = (try evaluate(testing.allocator, module.functions.items[index], args, .{ .max_steps = 2 })).?;
        try testing.expectEqual(expected, if (single) @as(u64, result.single_bits) else result.double_bits);
        case_count += 1;
    }
    try testing.expectEqual(@as(usize, 512), case_count);
}

test "casts preserve every bit and single precision widening matches exact oracle" {
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/conversion-oracle.tsv"), '\n');
    var case_count: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const result_ty = fields.next().?;
        const opcode = fields.next().?;
        const source_ty = fields.next().?;
        const bits = try std.fmt.parseInt(u64, fields.next().?, 10);
        const expected = try std.fmt.parseInt(u64, fields.next().?, 10);
        try testing.expect(fields.next() == null);
        const text = try std.fmt.allocPrint(testing.allocator, "function {s} $f({s} %a) {{\n@b\n%r ={s} {s} %a\nret %r\n}}", .{ result_ty, source_ty, result_ty, opcode });
        defer testing.allocator.free(text);
        var module = try parse(text);
        defer module.deinit();
        const arg: ir.Constant = switch (source_ty[0]) {
            'w' => .{ .word = @intCast(bits) },
            'l' => .{ .long = bits },
            's' => .{ .single_bits = @intCast(bits) },
            'd' => .{ .double_bits = bits },
            else => return error.InvalidFixtureType,
        };
        const result = (try evaluate(testing.allocator, module.functions.items[0], &.{arg}, .{ .max_steps = 2 })).?;
        const actual: u64 = switch (result) {
            .word => |v| v,
            .long => |v| v,
            .single_bits => |v| v,
            .double_bits => |v| v,
        };
        try testing.expectEqual(expected, actual);
        case_count += 1;
    }
    try testing.expectEqual(@as(usize, 384), case_count);
}

test "floating comparisons agree with classification oracle including NaNs and signed zeros" {
    var lines = std.mem.tokenizeScalar(u8, @embedFile("fixtures/float-comparison-oracle.tsv"), '\n');
    var case_count: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const result_ty = fields.next().?;
        const opcode = fields.next().?;
        const operand_ty = fields.next().?;
        const a = try std.fmt.parseInt(u64, fields.next().?, 10);
        const b = try std.fmt.parseInt(u64, fields.next().?, 10);
        const expected = try std.fmt.parseInt(u64, fields.next().?, 10);
        try testing.expect(fields.next() == null);
        const text = try std.fmt.allocPrint(testing.allocator, "function {s} $f({s} %a, {s} %b) {{\n@entry\n%r ={s} {s} %a, %b\nret %r\n}}", .{ result_ty, operand_ty, operand_ty, result_ty, opcode });
        defer testing.allocator.free(text);
        var module = try parse(text);
        defer module.deinit();
        const single = std.mem.eql(u8, operand_ty, "s");
        const args: []const ir.Constant = &.{ if (single) .{ .single_bits = @intCast(a) } else .{ .double_bits = a }, if (single) .{ .single_bits = @intCast(b) } else .{ .double_bits = b } };
        const result = (try evaluate(testing.allocator, module.functions.items[0], args, .{ .max_steps = 2 })).?;
        try testing.expectEqual(expected, if (std.mem.eql(u8, result_ty, "w")) @as(u64, result.word) else result.long);
        case_count += 1;
    }
    try testing.expectEqual(@as(usize, 2560), case_count);
}

test "halt has a typed error consumes a step and preserves preceding faults" {
    var module = try parse(@embedFile("fixtures/halt.ssa"));
    defer module.deinit();
    try testing.expectError(error.StepLimitExceeded, evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .max_steps = 0 }));
    try testing.expectError(error.Halted, evaluate(testing.allocator, module.functions.items[0], &.{}, .{ .max_steps = 1 }));
    const conditional = module.functions.items[1];
    try testing.expectEqual(@as(u32, 42), (try evaluate(testing.allocator, conditional, &.{.{ .word = 0 }}, .{ .max_steps = 2 })).?.word);
    try testing.expectError(error.Halted, evaluate(testing.allocator, conditional, &.{.{ .word = 1 }}, .{ .max_steps = 2 }));
    try testing.expectError(error.StepLimitExceeded, evaluate(testing.allocator, conditional, &.{.{ .word = 1 }}, .{ .max_steps = 1 }));
    const preceding = module.functions.items[2];
    try testing.expectError(error.DivisionByZero, evaluate(testing.allocator, preceding, &.{.{ .word = 0 }}, .{}));
    try testing.expectError(error.Halted, evaluate(testing.allocator, preceding, &.{.{ .word = 1 }}, .{ .max_steps = 2 }));
}
