const std = @import("std");
const source = @import("source.zig");
const lex = @import("lexer.zig");
const ir = @import("ir.zig");
const Module = @import("module.zig").Module;
const Allocator = std.mem.Allocator;
const binary_opcodes = std.StaticStringMap(ir.BinaryOp).initComptime(.{
    .{ "add", .add },     .{ "sub", .sub },   .{ "mul", .mul },
    .{ "and", .bit_and }, .{ "or", .bit_or }, .{ "xor", .bit_xor },
});
pub const Error = Allocator.Error || error{ InvalidInput, TooManySymbols, TooManyFunctions, TooManyValues, TooManyBlocks };

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
        try parser.function();
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

    fn function(self: *Parser) Error!void {
        self.values.clearRetainingCapacity();
        self.blocks.clearRetainingCapacity();
        const exported = self.word("export");
        if (exported) _ = self.advance();
        if (!self.word("function")) return self.fail(.unsupported_construct, self.peek());
        _ = self.advance();
        const result = if (self.peek().kind == .global) null else try self.takeType();
        const name_token = try self.expect(.global);
        const name = try self.globalName(name_token);
        const id = self.module.addFunction(name, result) catch |err| switch (err) {
            error.DuplicateFunction => return self.fail(.duplicate_function, name_token),
            else => |resource| return resource,
        };
        const f = self.module.getFunction(id).?;
        self.current_function = f;
        f.linkage = if (exported) .exported else .internal;
        _ = try self.expect(.lparen);
        if (self.peek().kind != .rparen) while (true) {
            const ty = try self.takeType();
            const parameter = try self.expect(.temporary);
            const parameter_name = self.nameText(parameter);
            try self.reserveValue(parameter);
            const value = f.addParameter(ty) catch |err| return self.irError(err, parameter);
            self.values.putAssumeCapacity(parameter_name, value);
            if (self.peek().kind != .comma) break;
            _ = self.advance();
        };
        _ = try self.expect(.rparen);
        _ = try self.expect(.lbrace);
        try self.declareBlocks();
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
                try self.terminator(active);
            } else return self.fail(.unsupported_construct, token);
            try self.lineEnd();
        }
        const close = self.advance();
        f.validateStructure() catch |err| return self.irError(err, close);
    }

    /// Declare only line-initial label definitions, not branch operands. Branches
    /// may target later blocks without storing raw pointers or dummy terminators.
    fn declareBlocks(self: *Parser) Error!void {
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
            }
            at_line_start = token.kind == .newline;
        }
        return self.fail(.unexpected_token, self.peek());
    }

    fn instruction(self: *Parser, block: ir.BlockId) Error!void {
        const destination = self.advance();
        try self.reserveValue(destination);
        _ = try self.expect(.equal);
        const ty = try self.takeType();
        const opcode = try self.expect(.identifier);
        const spelling = self.tokenText(opcode);
        const f = self.current_function.?;
        const result = if (std.mem.eql(u8, spelling, "copy")) copy: {
            const operand = try self.readOperand(ty);
            break :copy f.appendCopy(block, ty, operand) catch |err| return self.irError(err, opcode);
        } else binary: {
            const op = binary_opcodes.get(spelling) orelse return self.fail(.unsupported_construct, opcode);
            const lhs = try self.readOperand(ty);
            _ = try self.expect(.comma);
            const rhs = try self.readOperand(ty);
            break :binary f.appendBinary(block, ty, op, lhs, rhs) catch |err| return self.irError(err, opcode);
        };
        self.values.putAssumeCapacity(self.nameText(destination), result);
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
        } else if (std.mem.eql(u8, spelling, "ret")) .{ .return_value = if (f.return_type) |ty| try self.readOperand(ty) else null } else return self.fail(.unsupported_construct, opcode);
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
            .global, .type_name, .string => return self.fail(.unsupported_construct, token),
            else => return self.fail(.unexpected_token, token),
        };
        const actual = self.current_function.?.operandType(result) catch |err| return self.irError(err, token);
        if (expected) |ty| if (actual != ty) return self.fail(.type_mismatch, token);
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

    fn takeType(self: *Parser) Error!ir.ScalarType {
        const token = self.advance();
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
    try expectInvalid("data $x = { w 1 }", .unsupported_construct, "data");
    try expectInvalid("function w $f() {\n@b\n%x =w loadw 0\nret %x\n}", .unsupported_construct, "loadw");
    try expectInvalid("function $f(...) {\n@b\nret\n}", .unsupported_construct, "...");
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
