const std = @import("std");
const source = @import("source.zig");
const lex = @import("lexer.zig");
const ir = @import("ir.zig");
const data = @import("data.zig");
const Module = @import("module.zig").Module;
const Allocator = std.mem.Allocator;
const binary_opcodes = std.StaticStringMap(ir.BinaryOp).initComptime(.{
    .{ "add", .add },                 .{ "sub", .sub },              .{ "mul", .mul },
    .{ "and", .bit_and },             .{ "or", .bit_or },            .{ "xor", .bit_xor },
    .{ "div", .signed_divide },       .{ "udiv", .unsigned_divide }, .{ "rem", .signed_remainder },
    .{ "urem", .unsigned_remainder },
});
const allocation_opcodes = std.StaticStringMap(ir.AllocationAlignment).initComptime(.{
    .{ "alloc4", .four }, .{ "alloc8", .eight }, .{ "alloc16", .sixteen },
});
const unary_opcodes = std.StaticStringMap(ir.UnaryOp).initComptime(.{
    .{ "neg", .negate },
    .{ "cast", .bitcast },
    .{ "exts", .widen_float },
    .{ "extsb", .sign_extend_byte },
    .{ "extub", .zero_extend_byte },
    .{ "extsh", .sign_extend_half },
    .{ "extuh", .zero_extend_half },
    .{ "extsw", .sign_extend_word },
    .{ "extuw", .zero_extend_word },
});
const shift_opcodes = std.StaticStringMap(ir.ShiftOp).initComptime(.{
    .{ "shl", .left }, .{ "shr", .logical_right }, .{ "sar", .arithmetic_right },
});
const comparison_predicates = std.StaticStringMap(ir.IntegerPredicate).initComptime(.{
    .{ "ceq", .equal },             .{ "cne", .not_equal },
    .{ "cslt", .signed_less },      .{ "csle", .signed_less_equal },
    .{ "csgt", .signed_greater },   .{ "csge", .signed_greater_equal },
    .{ "cult", .unsigned_less },    .{ "cule", .unsigned_less_equal },
    .{ "cugt", .unsigned_greater }, .{ "cuge", .unsigned_greater_equal },
});
const ComparisonOpcode = struct { predicate: ir.IntegerPredicate, operand_type: ir.IntegerType };
fn comparisonOpcode(spelling: []const u8) ?ComparisonOpcode {
    if (spelling.len < 4) return null;
    const ty: ir.IntegerType = switch (spelling[spelling.len - 1]) {
        'w' => .word,
        'l' => .long,
        else => return null,
    };
    const predicate = comparison_predicates.get(spelling[0 .. spelling.len - 1]) orelse return null;
    return .{ .predicate = predicate, .operand_type = ty };
}
const float_comparison_predicates = std.StaticStringMap(ir.FloatPredicate).initComptime(.{
    .{ "ceq", .equal },   .{ "cne", .not_equal },     .{ "clt", .less },   .{ "cle", .less_equal },
    .{ "cgt", .greater }, .{ "cge", .greater_equal }, .{ "co", .ordered }, .{ "cuo", .unordered },
});
const FloatComparisonOpcode = struct { predicate: ir.FloatPredicate, operand_type: ir.FloatType };
fn floatComparisonOpcode(spelling: []const u8) ?FloatComparisonOpcode {
    if (spelling.len < 3) return null;
    const ty: ir.FloatType = switch (spelling[spelling.len - 1]) {
        's' => .single,
        'd' => .double,
        else => return null,
    };
    const predicate = float_comparison_predicates.get(spelling[0 .. spelling.len - 1]) orelse return null;
    return .{ .predicate = predicate, .operand_type = ty };
}
pub const Error = Allocator.Error || error{ InvalidInput, TooManySymbols, TooManyFunctions, TooManyData, DataTooLarge, InvalidDataSize, TooManyValues, TooManyBlocks };

/// Parse the documented scalar subset into an independently owned module.
/// Input is borrowed only during this call. On failure all partial IR is freed;
/// syntax/type failures set diagnostic, while allocation/resource errors do not.
/// This does NOT establish SSA dominance or accept the full QBE language.
pub fn parse(allocator: Allocator, input: source.Source, diagnostic: *?source.Diagnostic) Error!Module {
    diagnostic.* = null;
    var tokens: std.ArrayList(lex.Token) = .empty;
    defer tokens.deinit(allocator);
    var lexer: lex.Lexer = .{ .input = input };
    while (true) {
        const token = lexer.next() catch {
            diagnostic.* = lexer.diagnostic;
            return error.InvalidInput;
        };
        try tokens.append(allocator, token);
        if (token.kind == .eof) break;
    }
    var parser: Parser = .{
        .allocator = allocator,
        .input = input,
        .tokens = tokens.items,
        .diagnostic = diagnostic,
        .module = Module.init(allocator),
    };
    errdefer parser.module.deinit();
    defer parser.values.deinit(allocator);
    defer parser.blocks.deinit(allocator);
    parser.skipLines();
    while (parser.peek().kind != .eof) {
        const start = parser.index;
        if (parser.word("export")) {
            _ = parser.advance();
            parser.skipLines();
        }
        const is_data = parser.word("data");
        parser.index = start;
        if (is_data) try parser.dataDefinition() else try parser.function();
        parser.skipLines();
    }
    return parser.module;
}

const Parser = struct {
    allocator: Allocator,
    input: source.Source,
    tokens: []const lex.Token,
    index: usize = 0,
    diagnostic: *?source.Diagnostic,
    module: Module,
    current_function: ?*ir.Function = null,
    values: std.StringHashMapUnmanaged(ir.ValueId) = .empty,
    blocks: std.StringHashMapUnmanaged(ir.BlockId) = .empty,

    fn dataDefinition(self: *Parser) Error!void {
        const exported = self.word("export");
        if (exported) {
            _ = self.advance();
            self.skipLines();
        }
        _ = self.advance(); // Contextual `data` dispatch established by parse.
        self.skipLines();
        const name_token = try self.expect(.global);
        self.skipLines();
        const id = self.module.addData(try self.globalName(name_token)) catch |err| switch (err) {
            error.DuplicateSymbol => return self.fail(.duplicate_symbol, name_token),
            else => |resource| return resource,
        };
        const object = self.module.getData(id).?;
        object.linkage = if (exported) .exported else .internal;
        _ = try self.expect(.equal);
        self.skipLines();
        if (self.word("align")) {
            _ = self.advance();
            self.skipLines();
            const token = try self.expect(.integer);
            self.skipLines();
            const count = std.fmt.parseInt(u64, self.tokenText(token), 10) catch return self.fail(.invalid_alignment, token);
            object.alignment = data.Alignment.fromBytes(count) catch return self.fail(.invalid_alignment, token);
        }
        _ = try self.expect(.lbrace);
        self.skipLines();
        while (self.peek().kind != .rbrace) {
            const kind_token = try self.expect(.identifier);
            const spelling = self.tokenText(kind_token);
            if (spelling.len != 1 or std.mem.indexOfScalar(u8, "bhwlsdz", spelling[0]) == null)
                return self.fail(.unsupported_construct, kind_token);
            const kind = spelling[0];
            self.skipLines();
            var count: usize = 0;
            while (self.peek().kind != .comma and self.peek().kind != .rbrace) {
                const token = self.advance();
                if (token.kind == .string) {
                    if (kind != 'b') return self.fail(.unsupported_construct, token);
                    const bytes = @import("byte_strings.zig").decode(self.allocator, self.tokenText(token), data.max_object_bytes - object.byte_len) catch |err| switch (err) {
                        error.InvalidStringLiteral => return self.fail(.invalid_string, token),
                        else => |resource| return resource,
                    };
                    defer self.allocator.free(bytes);
                    try object.append(.{ .bytes = bytes });
                    count += 1;
                    self.skipLines();
                    continue;
                }
                const item: data.Item = if (kind == 'z') zero: {
                    if (count != 0 or token.kind != .integer) return self.fail(.unexpected_token, token);
                    const text = self.tokenText(token);
                    if (text[0] == '-') return self.fail(.invalid_integer, token);
                    const n = std.fmt.parseInt(u32, text, 10) catch return self.fail(.invalid_integer, token);
                    break :zero .{ .zero = n };
                } else if (kind == 's' or kind == 'd') floating: {
                    if (token.kind != (if (kind == 's') lex.Kind.single else lex.Kind.double)) return self.fail(.type_mismatch, token);
                    const text = std.mem.trim(u8, self.tokenText(token)[2..], " \t\r\n\x0b\x0c");
                    if (std.mem.indexOfScalar(u8, text, '(') != null) return self.fail(.unsupported_construct, token);
                    break :floating if (kind == 's')
                        .{ .single_bits = @bitCast(parseFloating(f32, text) catch return self.fail(.invalid_float, token)) }
                    else
                        .{ .double_bits = @bitCast(parseFloating(f64, text) catch return self.fail(.invalid_float, token)) };
                } else if (token.kind == .global) symbolic: {
                    if (kind != 'l') return self.fail(.unsupported_construct, token);
                    const symbol = try self.module.symbols.intern(try self.globalName(token));
                    self.skipLines();
                    var addend: i64 = 0;
                    if (self.peek().kind == .plus) {
                        _ = self.advance();
                        self.skipLines();
                        const offset = try self.expect(.integer);
                        addend = std.fmt.parseInt(i64, self.tokenText(offset), 10) catch return self.fail(.invalid_integer, offset);
                    }
                    break :symbolic .{ .symbol_address = .{ .symbol = symbol, .addend = addend } };
                } else integer: {
                    if (token.kind == .string) return self.fail(.unsupported_construct, token);
                    if (token.kind != .integer) return self.fail(.type_mismatch, token);
                    const bits = lex.integerBits(self.tokenText(token)) catch return self.fail(.invalid_integer, token);
                    break :integer switch (kind) {
                        'b' => .{ .byte = @truncate(bits) },
                        'h' => .{ .half = @truncate(bits) },
                        'w' => .{ .word = @truncate(bits) },
                        'l' => .{ .long = bits },
                        else => unreachable,
                    };
                };
                try object.append(item);
                count += 1;
                self.skipLines();
            }
            if (count == 0) return self.fail(.unexpected_token, self.peek());
            if (self.peek().kind == .comma) {
                _ = self.advance();
                self.skipLines();
            }
        }
        _ = self.advance();
        _ = try self.module.dataSize();
    }

    fn function(self: *Parser) Error!void {
        self.values.clearRetainingCapacity();
        self.blocks.clearRetainingCapacity();
        const exported = self.word("export");
        if (exported) _ = self.advance();
        if (!self.word("function")) return self.fail(.unsupported_construct, self.peek());
        _ = self.advance();
        const result = if (self.peek().kind == .global) null else try self.takeAbiType();
        const name_token = try self.expect(.global);
        const name = try self.globalName(name_token);
        const id = self.module.addFunctionAbi(name, result) catch |err| switch (err) {
            error.DuplicateFunction => return self.fail(.duplicate_function, name_token),
            error.DuplicateSymbol => return self.fail(.duplicate_symbol, name_token),
            else => |resource| return resource,
        };
        const f = self.module.getFunction(id).?;
        self.current_function = f;
        f.linkage = if (exported) .exported else .internal;
        _ = try self.expect(.lparen);
        if (self.peek().kind != .rparen) while (true) {
            if (self.peek().kind == .ellipsis) {
                _ = self.advance();
                f.variadic = true;
                break; // Only the closing parenthesis may follow this final marker.
            }
            const is_environment = self.peek().kind == .identifier and std.mem.eql(u8, self.tokenText(self.peek()), "env");
            const ty: ir.AbiType = if (is_environment) ty: {
                _ = self.advance();
                break :ty .long;
            } else try self.takeAbiType();
            const parameter = try self.expect(.temporary);
            const parameter_name = self.nameText(parameter);
            try self.reserveValue(parameter);
            const value = (if (is_environment) f.addEnvironmentParameter() else f.addParameterAbi(ty)) catch |err| return self.irError(err, parameter);
            self.values.putAssumeCapacity(parameter_name, value);
            if (self.peek().kind != .comma) break;
            _ = self.advance();
        };
        _ = try self.expect(.rparen);
        _ = try self.expect(.lbrace);
        try self.declareBody();
        self.skipLines();
        var block: ?ir.BlockId = null;
        while (self.peek().kind != .rbrace) {
            const token = self.peek();
            if (token.kind == .eof) return self.fail(.unexpected_token, token);
            if (token.kind == .label) {
                if (block) |previous| {
                    if (f.blocks.items[@backingInt(previous)].terminator == null) return self.fail(.missing_terminator, token);
                }
                block = self.blocks.get(self.nameText(token)).?;
                _ = self.advance();
                _ = try self.expect(.newline);
                self.skipLines();
                continue;
            }
            const active = block orelse return self.fail(.unexpected_token, token);
            if (f.blocks.items[@backingInt(active)].terminator != null) return self.fail(.block_terminated, token);
            if (token.kind == .temporary) {
                try self.instruction(active);
            } else if (token.kind == .identifier) {
                if (std.mem.eql(u8, self.tokenText(token), "call")) {
                    _ = self.advance();
                    try self.call(active, null, token, null);
                } else if (std.mem.eql(u8, self.tokenText(token), "vastart")) {
                    _ = self.advance();
                    const list = try self.readOperand(.long);
                    f.appendVaStart(active, list) catch |err| return self.irError(err, token);
                } else if (std.mem.eql(u8, self.tokenText(token), "blit")) {
                    _ = self.advance();
                    const src = try self.readOperand(.long);
                    _ = try self.expect(.comma);
                    const dst = try self.readOperand(.long);
                    _ = try self.expect(.comma);
                    const count_token = try self.expect(.integer);
                    const spelling = self.tokenText(count_token);
                    // Counts are exact nonnegative signed-word constants, not
                    // modulo-2^64 data literals or legacy packed references.
                    if (spelling[0] == '-') return self.fail(.invalid_integer, count_token);
                    const count = std.fmt.parseInt(u31, spelling, 10) catch return self.fail(.invalid_integer, count_token);
                    f.appendBlit(active, src, dst, count) catch |err| return self.irError(err, token);
                } else if (store_opcodes.get(self.tokenText(token))) |kind| {
                    _ = self.advance();
                    const value = try self.readOperand(kind.valueType());
                    _ = try self.expect(.comma);
                    const address = try self.readOperand(.long);
                    f.appendStore(active, kind, value, address) catch |err| return self.irError(err, token);
                } else try self.terminator(active);
            } else return self.fail(.unsupported_construct, token);
            try self.lineEnd();
        }
        const close = self.advance();
        f.validateStructure() catch |err| return self.irError(err, close);
    }

    /// Predeclare typed temporary and label definitions, not operands. This
    /// resolves loop backedges and layout-independent SSA forward references.
    fn declareBody(self: *Parser) Error!void {
        var at_line_start = true;
        var index = self.index;
        const f = self.current_function.?;
        while (index < self.tokens.len) : (index += 1) {
            const token = self.tokens[index];
            if (token.kind == .rbrace) return;
            if (token.kind == .eof) return self.fail(.unexpected_token, token);
            if (at_line_start and token.kind == .label) {
                const name = self.nameText(token);
                if (self.blocks.contains(name)) return self.fail(.duplicate_block, token);
                try self.blocks.ensureUnusedCapacity(self.allocator, 1);
                const symbol = try self.module.symbols.intern(name);
                const id = f.addBlock(symbol) catch |err| return self.irError(err, token);
                self.blocks.putAssumeCapacity(name, id);
            } else if (at_line_start and token.kind == .temporary) {
                try self.reserveValue(token);
                if (index + 2 >= self.tokens.len) return self.fail(.unexpected_token, self.tokens[self.tokens.len - 1]);
                if (self.tokens[index + 1].kind != .equal) return self.fail(.unexpected_token, self.tokens[index + 1]);
                const ty = try self.abiType(self.tokens[index + 2]);
                if (ty.subword() != null and (index + 3 >= self.tokens.len or
                    self.tokens[index + 3].kind != .identifier or
                    !std.mem.eql(u8, self.tokenText(self.tokens[index + 3]), "call")))
                    return self.fail(.unsupported_construct, self.tokens[index + 2]);
                const value = f.declareValue(ty.scalar()) catch |err| return self.irError(err, token);
                self.values.putAssumeCapacity(self.nameText(token), value);
            }
            at_line_start = token.kind == .newline;
        }
        return self.fail(.unexpected_token, self.peek());
    }

    fn instruction(self: *Parser, block: ir.BlockId) Error!void {
        const destination = self.advance();
        const result = self.values.get(self.nameText(destination)).?;
        _ = try self.expect(.equal);
        const type_token = self.peek();
        const abi_type = try self.takeAbiType();
        const ty = abi_type.scalar();
        const opcode = try self.expect(.identifier);
        if (abi_type.subword() != null and !std.mem.eql(u8, self.tokenText(opcode), "call")) return self.fail(.unsupported_construct, type_token);
        const spelling = self.tokenText(opcode);
        const f = self.current_function.?;
        if (std.mem.eql(u8, spelling, "call")) {
            try self.call(block, result, opcode, abi_type);
        } else if (std.mem.eql(u8, spelling, "vaarg")) {
            const list = try self.readOperand(.long);
            f.defineVaArg(block, result, list) catch |err| return self.irError(err, opcode);
        } else if (allocation_opcodes.get(spelling)) |alignment| {
            const size = try self.readOperand(.long);
            f.defineAllocate(block, result, size, alignment) catch |err| return self.irError(err, opcode);
        } else if (load_opcodes.get(spelling)) |kind| {
            const address = try self.readOperand(.long);
            f.defineLoad(block, result, kind, address) catch |err| return self.irError(err, opcode);
        } else if (std.mem.eql(u8, spelling, "copy")) {
            const operand = try self.readOperand(ty);
            f.defineCopy(block, result, operand) catch |err| return self.irError(err, opcode);
        } else if (std.mem.eql(u8, spelling, "phi")) {
            var inputs: std.ArrayList(ir.PhiInput) = .empty;
            defer inputs.deinit(self.allocator);
            while (true) {
                const predecessor = try self.target();
                const value = try self.readOperand(ty);
                try inputs.append(self.allocator, .{ .predecessor = predecessor, .value = value });
                if (self.peek().kind != .comma) break;
                _ = self.advance();
            }
            f.definePhi(block, result, inputs.items) catch |err| return self.irError(err, opcode);
        } else if (conversion_opcodes.get(spelling)) |op| {
            const operand_type = op.operandType(ty) catch |err| return self.irError(err, opcode);
            const operand = try self.readOperand(operand_type);
            f.defineConvert(block, result, op, operand) catch |err| return self.irError(err, opcode);
        } else if (unary_opcodes.get(spelling)) |op| {
            const operand_type = op.operandType(ty) catch |err| return self.irError(err, opcode);
            const operand = try self.readOperand(operand_type);
            f.defineUnary(block, result, op, operand) catch |err| return self.irError(err, opcode);
        } else if (shift_opcodes.get(spelling)) |op| {
            const operand = try self.readOperand(ty);
            _ = try self.expect(.comma);
            const amount = try self.readOperand(.word);
            f.defineShift(block, result, op, operand, amount) catch |err| return self.irError(err, opcode);
        } else if (comparisonOpcode(spelling)) |comparison| {
            const lhs = try self.readOperand(comparison.operand_type.scalar());
            _ = try self.expect(.comma);
            const rhs = try self.readOperand(comparison.operand_type.scalar());
            f.defineIntegerCompare(block, result, comparison.predicate, comparison.operand_type, lhs, rhs) catch |err| return self.irError(err, opcode);
        } else if (floatComparisonOpcode(spelling)) |comparison| {
            const lhs = try self.readOperand(comparison.operand_type.scalar());
            _ = try self.expect(.comma);
            const rhs = try self.readOperand(comparison.operand_type.scalar());
            f.defineFloatCompare(block, result, comparison.predicate, comparison.operand_type, lhs, rhs) catch |err| return self.irError(err, opcode);
        } else {
            const op = binary_opcodes.get(spelling) orelse return self.fail(.unsupported_construct, opcode);
            const lhs = try self.readOperand(ty);
            _ = try self.expect(.comma);
            const rhs = try self.readOperand(ty);
            f.defineBinary(block, result, op, lhs, rhs) catch |err| return self.irError(err, opcode);
        }
    }

    fn call(self: *Parser, block: ir.BlockId, result: ?ir.ValueId, opcode: lex.Token, result_abi: ?ir.AbiType) Error!void {
        // Scalar ABI call sites; an indirect address must be long.
        const callee: ir.CallTarget = switch (self.peek().kind) {
            .global => symbol: {
                const token = self.advance();
                break :symbol .{ .symbol = try self.module.symbols.intern(try self.globalName(token)) };
            },
            .temporary, .integer => .{ .address = try self.readOperand(.long) },
            else => return self.fail(.unsupported_construct, self.peek()),
        };
        _ = try self.expect(.lparen);
        var arguments: std.ArrayList(ir.CallArgument) = .empty;
        defer arguments.deinit(self.allocator);
        var variadic_start: ?usize = null;
        var environment: ?ir.Operand = null;
        if (self.peek().kind != .rparen) while (true) {
            if (self.peek().kind == .identifier and std.mem.eql(u8, self.tokenText(self.peek()), "env")) {
                const marker = self.advance();
                if (environment != null or arguments.items.len != 0 or variadic_start != null) return self.fail(.unsupported_construct, marker);
                environment = try self.readOperand(.long);
            } else if (self.peek().kind == .ellipsis) {
                const marker = self.advance();
                if (variadic_start != null) return self.fail(.unsupported_construct, marker);
                variadic_start = arguments.items.len;
            } else {
                const argument_type = try self.takeAbiType();
                const operand = try self.readOperand(argument_type.scalar());
                try arguments.append(self.allocator, ir.CallArgument.init(argument_type, operand));
            }
            if (self.peek().kind != .comma) break;
            _ = self.advance();
        };
        _ = try self.expect(.rparen);
        const f = self.current_function.?;
        f.appendCall(block, result, callee, arguments.items, .{ .result_abi = result_abi, .variadic_start = variadic_start, .environment = environment }) catch |err| return self.irError(err, opcode);
    }

    fn terminator(self: *Parser, block: ir.BlockId) Error!void {
        const opcode = self.advance();
        const spelling = self.tokenText(opcode);
        const f = self.current_function.?;
        const term: ir.Terminator = if (std.mem.eql(u8, spelling, "jmp")) .{ .jump = try self.target() } else if (std.mem.eql(u8, spelling, "jnz")) branch: {
            const condition = try self.readOperand(null);
            _ = try self.expect(.comma);
            const taken = try self.target();
            _ = try self.expect(.comma);
            const not_taken = try self.target();
            break :branch .{ .branch = .{ .condition = condition, .taken = taken, .not_taken = not_taken } };
        } else if (std.mem.eql(u8, spelling, "ret")) .{ .return_value = if (f.return_type) |ty| try self.readOperand(ty) else null } else if (std.mem.eql(u8, spelling, "hlt")) .halt else return self.fail(.unsupported_construct, opcode);
        f.terminate(block, term) catch |err| return self.irError(err, opcode);
    }

    fn readOperand(self: *Parser, expected: ?ir.ScalarType) Error!ir.Operand {
        const token = self.advance();
        const result: ir.Operand = switch (token.kind) {
            .temporary => .{ .value = self.values.get(self.nameText(token)) orelse return self.fail(.unknown_value, token) },
            .integer => integer: {
                const bits = lex.integerBits(self.tokenText(token)) catch return self.fail(.invalid_integer, token);
                const ty = expected orelse .long;
                break :integer .{ .constant = switch (ty) {
                    .word => .{ .word = @truncate(bits) },
                    .long => .{ .long = bits },
                    else => return self.fail(.type_mismatch, token),
                } };
            },
            .single, .double => floating: {
                const spelling = std.mem.trim(u8, self.tokenText(token)[2..], " \t\r\n\x0b\x0c");
                if (std.mem.indexOfScalar(u8, spelling, '(') != null) return self.fail(.unsupported_construct, token);
                break :floating .{ .constant = if (token.kind == .single)
                    .{ .single_bits = @bitCast(parseFloating(f32, spelling) catch return self.fail(.invalid_float, token)) }
                else
                    .{ .double_bits = @bitCast(parseFloating(f64, spelling) catch return self.fail(.invalid_float, token)) } };
            },
            .global => symbolic: {
                const symbol = try self.module.symbols.intern(try self.globalName(token));
                if (self.peek().kind != .plus) break :symbolic .{ .symbol = symbol };
                _ = self.advance();
                const offset = try self.expect(.integer);
                const addend = std.fmt.parseInt(i32, self.tokenText(offset), 10) catch return self.fail(.invalid_integer, offset);
                break :symbolic .{ .symbol_offset = .{ .symbol = symbol, .addend = addend } };
            },
            .type_name, .string => return self.fail(.unsupported_construct, token),
            else => return self.fail(.unexpected_token, token),
        };
        const actual = self.current_function.?.operandType(result) catch |err| return self.irError(err, token);
        if (expected) |ty| if (actual != ty) {
            // Normalize QBE's one implicit scalar subtype into an explicit IR
            // projection. No guessed signedness or fresh SSA value is needed.
            if (ty == .word and actual == .long and result == .value) return .{ .low_word = result.value };
            return self.fail(.type_mismatch, token);
        };
        return result;
    }

    fn target(self: *Parser) Error!ir.BlockId {
        const token = try self.expect(.label);
        return self.blocks.get(self.nameText(token)) orelse self.fail(.unknown_block, token);
    }

    fn reserveValue(self: *Parser, token: lex.Token) Error!void {
        if (self.values.contains(self.nameText(token))) return self.fail(.duplicate_value, token);
        try self.values.ensureUnusedCapacity(self.allocator, 1);
    }

    fn takeAbiType(self: *Parser) Error!ir.AbiType {
        return self.abiType(self.advance());
    }

    fn abiType(self: *Parser, token: lex.Token) Error!ir.AbiType {
        if (token.kind == .identifier) {
            const text = self.tokenText(token);
            if (std.mem.eql(u8, text, "sb")) return .signed_byte;
            if (std.mem.eql(u8, text, "ub")) return .unsigned_byte;
            if (std.mem.eql(u8, text, "sh")) return .signed_half;
            if (std.mem.eql(u8, text, "uh")) return .unsigned_half;
        }
        return ir.AbiType.fromScalar(try self.scalarType(token));
    }

    fn scalarType(self: *Parser, token: lex.Token) Error!ir.ScalarType {
        if (token.kind != .identifier) return self.fail(.unsupported_construct, token);
        const text = self.tokenText(token);
        if (text.len == 1) return switch (text[0]) {
            'w' => .word,
            'l' => .long,
            's' => .single,
            'd' => .double,
            else => self.fail(.unsupported_construct, token),
        };
        return self.fail(.unsupported_construct, token);
    }

    fn globalName(self: *Parser, token: lex.Token) Error![]const u8 {
        const name = self.nameText(token);
        if (name[0] == '"') return self.fail(.unsupported_construct, token);
        return name;
    }

    fn lineEnd(self: *Parser) Error!void {
        switch (self.peek().kind) {
            .newline => self.skipLines(),
            .rbrace, .eof => {},
            else => return self.fail(.unexpected_token, self.peek()),
        }
    }
    fn skipLines(self: *Parser) void {
        while (self.peek().kind == .newline) _ = self.advance();
    }
    fn peek(self: Parser) lex.Token {
        return self.tokens[self.index];
    }
    fn advance(self: *Parser) lex.Token {
        const token = self.peek();
        if (token.kind != .eof) self.index += 1;
        return token;
    }
    fn expect(self: *Parser, kind: lex.Kind) Error!lex.Token {
        if (self.peek().kind != kind) return self.fail(.unexpected_token, self.peek());
        return self.advance();
    }
    fn tokenText(self: Parser, token: lex.Token) []const u8 {
        return self.input.slice(token.span).?;
    }
    fn nameText(self: Parser, token: lex.Token) []const u8 {
        return self.tokenText(token)[1..];
    }
    fn word(self: Parser, spelling: []const u8) bool {
        return self.peek().kind == .identifier and std.mem.eql(u8, self.tokenText(self.peek()), spelling);
    }
    fn fail(self: *Parser, code: source.Diagnostic.Code, token: lex.Token) Error {
        self.diagnostic.* = .{ .code = code, .span = token.span };
        return error.InvalidInput;
    }
    fn irError(self: *Parser, err: ir.BuildError, token: lex.Token) Error {
        return switch (err) {
            error.OutOfMemory, error.TooManyValues, error.TooManyBlocks => |resource| resource,
            error.TypeMismatch, error.NonIntegerCondition => self.fail(.type_mismatch, token),
            error.InvalidReturn => self.fail(.invalid_return, token),
            error.MissingTerminator => self.fail(.missing_terminator, token),
            error.BlockTerminated => self.fail(.block_terminated, token),
            error.PhiAfterInstructions => self.fail(.phi_after_instruction, token),
            else => self.fail(.invalid_ir, token),
        };
    }
};

// Parse magnitude and apply sign explicitly: Zig's plain NaN conversion does
// not retain a leading minus, while the IR must keep that sign bit too.
fn parseFloating(comptime F: type, spelling: []const u8) std.fmt.ParseFloatError!F {
    const negative = spelling.len > 0 and spelling[0] == '-';
    const signed = spelling.len > 0 and (spelling[0] == '-' or spelling[0] == '+');
    const magnitude = try std.fmt.parseFloat(F, spelling[@intFromBool(signed)..]);
    return if (negative) -magnitude else magnitude;
}

const testing = std.testing;
const fixture = @embedFile("fixtures/constant-jump.ssa");

test "real constant-jump regression parses into independent typed IR" {
    var diagnostic: ?source.Diagnostic = null;
    var module = try parse(testing.allocator, .{ .name = "constant-jump.ssa", .text = fixture }, &diagnostic);
    defer module.deinit();
    try testing.expect(diagnostic == null);
    try testing.expectEqual(@as(usize, 4), module.functions.items.len);
    for (module.functions.items) |f| {
        try testing.expectEqual(.exported, f.linkage);
        try f.validateStructure();
        try testing.expectEqual(@as(usize, 3), f.blocks.items.len);
    }
    const direct = module.functions.items[0].blocks.items[0].terminator.?.branch;
    try testing.expect(!try direct.condition.constant.branchTaken());
    try testing.expectEqual(@as(u32, 1), @backingInt(direct.taken));
    try testing.expectEqual(@as(u32, 2), @backingInt(direct.not_taken));
    const negative = module.functions.items[2].blocks.items[0].instructions.items[0].copy;
    try testing.expectEqual(@as(u64, 0xffffffff00000000), negative.operand.constant.long);
}

test "parameters, all current binary opcodes and void functions" {
    const text =
        \\function w $arith(w %a, w %b) {
        \\@start
        \\%c =w add %a, %b
        \\%d =w sub %c, -1
        \\%e =w mul %d, 2
        \\%f =w and %e, 255
        \\%g =w or %f, 1
        \\%h =w xor %g, 2
        \\ret %h
        \\}
        \\function $nothing() {
        \\@start
        \\jmp @done
        \\@done
        \\ret
        \\}
    ;
    var diagnostic: ?source.Diagnostic = null;
    var module = try parse(testing.allocator, .{ .name = "arith", .text = text }, &diagnostic);
    defer module.deinit();
    try testing.expectEqual(@as(usize, 2), module.functions.items.len);
    try testing.expectEqual(.internal, module.functions.items[0].linkage);
    try testing.expectEqual(@as(usize, 2), module.functions.items[0].parameters.items.len);
    try testing.expectEqual(@as(usize, 6), module.functions.items[0].blocks.items[0].instructions.items.len);
    for (module.functions.items) |f| try f.validateStructure();
}

test "float parsing preserves signed zero and typed hexadecimal constants" {
    const text = "function d $f() {\n@b\n%x =d copy d_-0\n%y =d add %x, d_0x1.8p+2\nret %y\n}\nfunction s $g() {\n@b\nret s_1.25\n}";
    var diagnostic: ?source.Diagnostic = null;
    var module = try parse(testing.allocator, .{ .name = "float", .text = text }, &diagnostic);
    defer module.deinit();
    const instructions = module.functions.items[0].blocks.items[0].instructions.items;
    try testing.expectEqual(@as(u64, 0x8000000000000000), instructions[0].copy.operand.constant.double_bits);
    try testing.expectEqual(@as(u64, @bitCast(@as(f64, 6))), instructions[1].binary.rhs.constant.double_bits);
    try testing.expectEqual(@as(u32, @bitCast(@as(f32, 1.25))), module.functions.items[1].blocks.items[0].terminator.?.return_value.?.constant.single_bits);
}

fn expectInvalid(text: []const u8, code: source.Diagnostic.Code, spelling: []const u8) !void {
    var diagnostic: ?source.Diagnostic = null;
    try testing.expectError(error.InvalidInput, parse(testing.allocator, .{ .name = "bad", .text = text }, &diagnostic));
    try testing.expectEqual(code, diagnostic.?.code);
    try testing.expectEqualStrings(spelling, text[diagnostic.?.span.start..diagnostic.?.span.end]);
}

test "diagnostics reject undefined and duplicate names at their source spans" {
    try expectInvalid("function w $f() {\n@b\nret %missing\n}", .unknown_value, "%missing");
    try expectInvalid("function $f() {\n@b\njmp @missing\n}", .unknown_block, "@missing");
    try expectInvalid("function $f() {\n@b\nret\n@b\nret\n}", .duplicate_block, "@b");
    try expectInvalid("function w $f(w %a, w %a) {\n@b\nret %a\n}", .duplicate_value, "%a");
    try expectInvalid("function w $f() {\n@b\n%x =w copy 1\n%x =w copy 2\nret %x\n}", .duplicate_value, "%x");
    try expectInvalid("function $f() {\n@b\nret\n}\nfunction $f() {\n@b\nret\n}", .duplicate_function, "$f");
}

test "malformed syntax, types and unsupported IL never silently lower" {
    try expectInvalid("data $x = { w $other }", .unsupported_construct, "$other");
    try expectInvalid("function w $f() {\n@b\n%x =w alloc8 8\nret %x\n}", .type_mismatch, "alloc8");
    try expectInvalid("function $f(..., ...) {\n@b\nret\n}", .unexpected_token, ",");
    try expectInvalid("function w $\"quoted\"() {\n@b\nret 0\n}", .unsupported_construct, "$\"quoted\"");
    try expectInvalid("function w $f() {\n@b\nret d_1\n}", .type_mismatch, "d_1");
    try expectInvalid("function s $f() {\n@b\nret s_nan(payload)\n}", .unsupported_construct, "s_nan(payload)");
    try expectInvalid("function $f() {\n@b\njnz d_1, @b, @b\n}", .type_mismatch, "jnz");
    try expectInvalid("function $f() {\n@b\nret\nret\n}", .block_terminated, "ret");
    try expectInvalid("function $f() {\n@b\n}", .missing_terminator, "}");
    try expectInvalid("function $f() {\n@a\n@b\nret\n}", .missing_terminator, "@b");
    try expectInvalid("function $f() {\n@b\nret", .unexpected_token, "");
    try expectInvalid("function w $f() {\n@b\n%x =w add 1 2\nret %x\n}", .unexpected_token, "2");
}

test "lexer diagnostics propagate and empty input is a valid empty module" {
    try expectInvalid("%1", .invalid_name, "%");
    var diagnostic: ?source.Diagnostic = null;
    var module = try parse(testing.allocator, .{ .name = "empty", .text = "# comment" }, &diagnostic);
    defer module.deinit();
    try testing.expectEqual(@as(usize, 0), module.functions.items.len);
}

test "successful module owns names independently of mutable source" {
    var text = "function w $owned(w %arg) {\n@entry\nret %arg\n}".*;
    var diagnostic: ?source.Diagnostic = null;
    var module = try parse(testing.allocator, .{ .name = "owned", .text = &text }, &diagnostic);
    defer module.deinit();
    @memset(&text, 'x');
    const f = module.functions.items[0];
    try testing.expectEqualStrings("owned", module.symbols.get(f.name).?);
    try testing.expectEqualStrings("entry", module.symbols.get(f.blocks.items[0].label.?).?);
    try f.validateStructure();
}

fn exerciseParsing(allocator: Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = try parse(allocator, .{ .name = "fixture", .text = fixture }, &diagnostic);
    defer module.deinit();
    for (module.functions.items) |f| try f.validateStructure();
    try testing.expect(diagnostic == null);
}

test "every frontend allocation failure frees tokens, maps and partial IR" {
    try @import("test_support.zig").checkAllocationFailures(exerciseParsing);
}

fn exerciseInvalidParsing(allocator: Allocator) !void {
    var diagnostic: ?source.Diagnostic = null;
    var module = parse(allocator, .{ .name = "partial", .text = fixture ++ "\nfunction w $broken() {\n@b\nret %missing\n}" }, &diagnostic) catch |err| switch (err) {
        error.InvalidInput => {
            try testing.expectEqual(source.Diagnostic.Code.unknown_value, diagnostic.?.code);
            return;
        },
        else => return err,
    };
    module.deinit();
    return error.ExpectedInvalidInput;
}

test "malformed trailing function frees previously parsed functions under OOM" {
    try @import("test_support.zig").checkAllocationFailures(exerciseInvalidParsing);
}

test "floating conversion retains negative NaN sign and width" {
    const single: u32 = @bitCast(try parseFloating(f32, "-nan"));
    const double: u64 = @bitCast(try parseFloating(f64, "-NAN"));
    try testing.expect(single & 0x80000000 != 0);
    try testing.expect(double & 0x8000000000000000 != 0);
    try testing.expect(std.math.isNan(@as(f32, @bitCast(single))));
    try testing.expect(std.math.isNan(@as(f64, @bitCast(double))));
}

test "all fixture truncations and deterministic byte mutations are memory safe" {
    var diagnostic: ?source.Diagnostic = null;
    for (0..fixture.len + 1) |length| {
        var module = parse(testing.allocator, .{ .name = "truncated", .text = fixture[0..length] }, &diagnostic) catch |err| switch (err) {
            error.InvalidInput => {
                try testing.expect((source.Source{ .name = "truncated", .text = fixture[0..length] }).slice(diagnostic.?.span) != null);
                continue;
            },
            else => |resource| return resource,
        };
        defer module.deinit();
        for (module.functions.items) |f| try f.validateStructure();
    }
    var bytes: [fixture.len]u8 = undefined;
    var state: u32 = 0x1f123bb5;
    for (0..1024) |_| {
        @memcpy(&bytes, fixture);
        for (0..3) |_| {
            state = state *% 1664525 +% 1013904223;
            const index = state % bytes.len;
            state = state *% 1664525 +% 1013904223;
            bytes[index] = @truncate(state >> 16);
        }
        var module = parse(testing.allocator, .{ .name = "mutated", .text = &bytes }, &diagnostic) catch |err| switch (err) {
            error.InvalidInput => {
                try testing.expect((source.Source{ .name = "mutated", .text = &bytes }).slice(diagnostic.?.span) != null);
                continue;
            },
            else => |resource| return resource,
        };
        defer module.deinit();
        for (module.functions.items) |f| try f.validateStructure();
    }
}

test "phi syntax predeclares backedge values and rejects late phi nodes" {
    var diagnostic: ?source.Diagnostic = null;
    var module = try parse(testing.allocator, .{ .name = "phi-loop", .text = @embedFile("fixtures/phi-loop.ssa") }, &diagnostic);
    defer module.deinit();
    try module.functions.items[0].validateStructure();
    try testing.expectEqual(@as(usize, 3), module.functions.items[0].blocks.items[1].phis.items.len);
    try expectInvalid("function w $f() {\n@entry\njmp @b\n@b\n%x =w copy 1\n%y =w phi @entry 2\nret %y\n}", .phi_after_instruction, "phi");
    try expectInvalid("function w $f() {\n@entry\njmp @b\n@b\n%x =w phi @entry d_2\nret %x\n}", .type_mismatch, "d_2");
}

test "shifts require integer values and word counts and comparisons require integer results" {
    try expectInvalid("function l $f(s %count) {\n@b\n%x =l shl 1, %count\nret %x\n}", .type_mismatch, "%count");
    try expectInvalid("function d $f() {\n@b\n%x =d shl d_1, 1\nret %x\n}", .type_mismatch, "shl");
    try expectInvalid("function d $f() {\n@b\n%x =d ceqw 1, 1\nret %x\n}", .type_mismatch, "ceqw");
}

test "integer extensions require word operands and valid result widths" {
    try expectInvalid("function w $f() {\n@b\n%x =w extsw 1\nret %x\n}", .type_mismatch, "extsw");
    try expectInvalid("function s $f() {\n@b\n%x =s extub 1\nret %x\n}", .type_mismatch, "extub");
    try expectInvalid("function l $f(s %v) {\n@b\n%x =l extuh %v\nret %x\n}", .type_mismatch, "%v");
    try expectInvalid("function w $f(s %v) {\n@b\n%x =w neg %v\nret %x\n}", .type_mismatch, "%v");
}

test "unsigned division and both remainders reject floating types" {
    try expectInvalid("function s $f() {\n@b\n%x =s udiv s_1, s_2\nret %x\n}", .type_mismatch, "udiv");
    try expectInvalid("function d $f() {\n@b\n%x =d rem d_1, d_2\nret %x\n}", .type_mismatch, "rem");
    try expectInvalid("function d $f() {\n@b\n%x =d urem d_1, d_2\nret %x\n}", .type_mismatch, "urem");
}

test "casts require the opposite same-width class and widening requires single input" {
    try expectInvalid("function w $f(w %v) {\n@b\n%r =w cast %v\nret %r\n}", .type_mismatch, "%v");
    try expectInvalid("function l $f(s %v) {\n@b\n%r =l cast %v\nret %r\n}", .type_mismatch, "%v");
    try expectInvalid("function s $f(s %v) {\n@b\n%r =s exts %v\nret %r\n}", .type_mismatch, "exts");
    try expectInvalid("function d $f(d %v) {\n@b\n%r =d exts %v\nret %r\n}", .type_mismatch, "%v");
}

test "floating comparisons require integer results and matching operand widths" {
    try expectInvalid("function s $f(s %a) {\n@b\n%r =s ceqs %a, %a\nret %r\n}", .type_mismatch, "ceqs");
    try expectInvalid("function w $f(d %a) {\n@b\n%r =w ceqs %a, s_1\nret %r\n}", .type_mismatch, "%a");
    try expectInvalid("function l $f(s %a) {\n@b\n%r =l cod %a, d_1\nret %r\n}", .type_mismatch, "%a");
}

test "halt takes no operands and closes its block" {
    var diagnostic: ?source.Diagnostic = null;
    var module = try parse(testing.allocator, .{ .name = "halt", .text = @embedFile("fixtures/halt.ssa") }, &diagnostic);
    defer module.deinit();
    try testing.expect(module.functions.items[0].blocks.items[0].terminator.? == .halt);
    try testing.expect(module.functions.items[1].blocks.items[1].terminator.? == .halt);
    try expectInvalid("function $f() {\n@b\nhlt 1\n}", .unexpected_token, "1");
    try expectInvalid("function $f() {\n@b\nhlt\nret\n}", .block_terminated, "ret");
}

const load_opcodes = std.StaticStringMap(ir.LoadKind).initComptime(.{
    .{ "loadsb", .signed_byte }, .{ "loadub", .unsigned_byte },
    .{ "loadsh", .signed_half }, .{ "loaduh", .unsigned_half },
    .{ "loadsw", .signed_word }, .{ "loaduw", .unsigned_word },
    .{ "loadw", .signed_word },  .{ "loadl", .long },
    .{ "loads", .single },       .{ "loadd", .double },
});
const store_opcodes = std.StaticStringMap(ir.StoreKind).initComptime(.{
    .{ "storeb", .byte }, .{ "storeh", .half },   .{ "storew", .word },
    .{ "storel", .long }, .{ "stores", .single }, .{ "stored", .double },
});

const conversion_opcodes = std.StaticStringMap(ir.ConvertOp).initComptime(.{
    .{ "uwtof", .unsigned_word_to_float },     .{ "ultof", .unsigned_long_to_float },
    .{ "stoui", .single_to_unsigned_integer }, .{ "dtoui", .double_to_unsigned_integer },
    .{ "swtof", .signed_word_to_float },       .{ "sltof", .signed_long_to_float },
    .{ "stosi", .single_to_signed_integer },   .{ "dtosi", .double_to_signed_integer },
});
