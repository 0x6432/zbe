const std = @import("std");
const source = @import("source.zig");
pub const Kind = enum {
    eof,
    newline,
    comma,
    lparen,
    rparen,
    lbrace,
    rbrace,
    equal,
    plus,
    identifier,
    temporary,
    label,
    global,
    type_name,
    string,
    integer,
    single,
    double,
    ellipsis,
};
pub const Token = struct { kind: Kind, span: source.Span };
pub const Error = error{InvalidInput};

/// Allocation-free scanner borrowing immutable source. Keywords are contextual:
/// unknown instructions are rejected by the parser, not a global keyword table.
pub const Lexer = struct {
    input: source.Source,
    cursor: usize = 0,
    diagnostic: ?source.Diagnostic = null,

    pub fn next(self: *Lexer) Error!Token {
        self.diagnostic = null;
        const text = self.input.text;
        while (self.cursor < text.len and (text[self.cursor] == ' ' or text[self.cursor] == '\t')) self.cursor += 1;
        const start = self.cursor;
        if (start == text.len) return self.token(.eof, start);
        const c = text[self.cursor];
        self.cursor += 1;
        switch (c) {
            ',' => return self.token(.comma, start),
            '(' => return self.token(.lparen, start),
            ')' => return self.token(.rparen, start),
            '{' => return self.token(.lbrace, start),
            '}' => return self.token(.rbrace, start),
            '=' => return self.token(.equal, start),
            '+' => return self.token(.plus, start),
            '\n' => return self.token(.newline, start),
            '\r' => {
                if (self.cursor < text.len and text[self.cursor] == '\n') {
                    self.cursor += 1;
                    return self.token(.newline, start);
                }
                return self.fail(.invalid_character, start);
            },
            '#' => {
                while (self.cursor < text.len and text[self.cursor] != '\n') self.cursor += 1;
                if (self.cursor < text.len) self.cursor += 1;
                return self.token(.newline, start);
            },
            '"' => return self.quoted(.string, start),
            '%', '@', '$', ':' => {
                const kind: Kind = switch (c) {
                    '%' => .temporary,
                    '@' => .label,
                    '$' => .global,
                    else => .type_name,
                };
                if (c == '$' and self.cursor < text.len and text[self.cursor] == '"') {
                    self.cursor += 1;
                    return self.quoted(kind, start);
                }
                if (self.cursor == text.len or !nameStart(text[self.cursor])) return self.fail(.invalid_name, start);
                self.cursor += 1;
                while (self.cursor < text.len and nameContinue(text[self.cursor])) self.cursor += 1;
                return self.token(kind, start);
            },
            else => {},
        }
        if ((c == 's' or c == 'd') and self.cursor < text.len and text[self.cursor] == '_') {
            self.cursor += 1;
            while (self.cursor < text.len and std.ascii.isWhitespace(text[self.cursor])) self.cursor += 1;
            const number_start = self.cursor;
            if (self.cursor < text.len and (text[self.cursor] == '+' or text[self.cursor] == '-')) self.cursor += 1;
            while (self.cursor < text.len) {
                const byte = text[self.cursor];
                if (std.ascii.isAlphanumeric(byte) or byte == '.' or byte == '_') {
                    self.cursor += 1;
                } else if ((byte == '+' or byte == '-') and self.cursor > number_start and
                    std.mem.indexOfScalar(u8, "eEpP", text[self.cursor - 1]) != null)
                {
                    self.cursor += 1;
                } else break;
            }
            // Keep a NaN payload spelling intact. Conversion is an explicit
            // unsupported boundary for now, rather than silently discarding it.
            var special = text[number_start..self.cursor];
            if (special.len > 0 and (special[0] == '+' or special[0] == '-')) special = special[1..];
            if (std.ascii.eqlIgnoreCase(special, "nan") and self.cursor < text.len and text[self.cursor] == '(') {
                self.cursor += 1;
                while (self.cursor < text.len and (std.ascii.isAlphanumeric(text[self.cursor]) or text[self.cursor] == '_')) self.cursor += 1;
                if (self.cursor == text.len or text[self.cursor] != ')') return self.fail(.invalid_float, start);
                self.cursor += 1;
            } else {
                // Validate a complete spelling, not scanf-style prefix recovery.
                if (self.cursor == number_start) return self.fail(.invalid_float, start);
                if (std.mem.indexOfScalar(u8, text[number_start..self.cursor], '_') != null) return self.fail(.invalid_float, start);
                _ = std.fmt.parseFloat(f64, text[number_start..self.cursor]) catch return self.fail(.invalid_float, start);
            }
            return self.token(if (c == 's') .single else .double, start);
        }
        if (std.ascii.isDigit(c) or c == '-') {
            if (c == '-' and (self.cursor == text.len or !std.ascii.isDigit(text[self.cursor]))) return self.fail(.invalid_integer, start);
            while (self.cursor < text.len and std.ascii.isDigit(text[self.cursor])) self.cursor += 1;
            if (self.cursor < text.len and nameContinue(text[self.cursor])) {
                while (self.cursor < text.len and nameContinue(text[self.cursor])) self.cursor += 1;
                return self.fail(.invalid_integer, start);
            }
            return self.token(.integer, start);
        }
        if (nameStart(c)) {
            while (self.cursor < text.len and nameContinue(text[self.cursor])) self.cursor += 1;
            const word = text[start..self.cursor];
            return self.token(if (std.mem.eql(u8, word, "...")) .ellipsis else .identifier, start);
        }
        return self.fail(.invalid_character, start);
    }

    fn quoted(self: *Lexer, kind: Kind, start: usize) Error!Token {
        var escaped = false;
        while (self.cursor < self.input.text.len) {
            const byte = self.input.text[self.cursor];
            self.cursor += 1;
            if (byte == '"' and !escaped) return self.token(kind, start);
            escaped = byte == '\\' and !escaped;
        }
        return self.fail(.unterminated_string, start);
    }

    fn token(self: Lexer, kind: Kind, start: usize) Token {
        return .{ .kind = kind, .span = .{ .start = start, .end = self.cursor } };
    }

    fn fail(self: *Lexer, code: source.Diagnostic.Code, start: usize) Error {
        self.diagnostic = .{ .code = code, .span = .{ .start = start, .end = self.cursor } };
        return error.InvalidInput;
    }
};

fn nameStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '.' or c == '_';
}
fn nameContinue(c: u8) bool {
    return nameStart(c) or std.ascii.isDigit(c) or c == '$';
}

/// QBE decimal integers are interpreted modulo 2^64, including negative input.
pub fn integerBits(text: []const u8) error{InvalidInteger}!u64 {
    if (text.len == 0) return error.InvalidInteger;
    const negative = text[0] == '-';
    const digits = text[@intFromBool(negative)..];
    if (digits.len == 0) return error.InvalidInteger;
    var bits: u64 = 0;
    for (digits) |c| {
        if (!std.ascii.isDigit(c)) return error.InvalidInteger;
        bits = bits *% 10 +% (c - '0');
    }
    return if (negative) 0 -% bits else bits;
}

test "token kinds, sigils, comments and source slices" {
    const input: source.Source = .{ .name = "test", .text = "export function w $f(w %a) {\r\n@entry\n%x =w add -1, 2 # tail\nret %x\n}\n:type ... +" };
    var lexer: Lexer = .{ .input = input };
    const expected = [_]Kind{ .identifier, .identifier, .identifier, .global, .lparen, .identifier, .temporary, .rparen, .lbrace, .newline, .label, .newline, .temporary, .equal, .identifier, .identifier, .integer, .comma, .integer, .newline, .identifier, .temporary, .newline, .rbrace, .newline, .type_name, .ellipsis, .plus, .eof };
    var previous: usize = 0;
    for (expected) |kind| {
        const token = try lexer.next();
        try std.testing.expectEqual(kind, token.kind);
        try std.testing.expect(token.span.start >= previous);
        try std.testing.expect(input.slice(token.span) != null);
        previous = token.span.end;
    }
    try std.testing.expectEqual(Kind.eof, (try lexer.next()).kind);
}

test "quoted strings preserve spelling and escape parity" {
    const text = "\"a\\\"b\" $\"quoted name\" \"ends\\\\\"";
    var lexer: Lexer = .{ .input = .{ .name = "test", .text = text } };
    try std.testing.expectEqualStrings("\"a\\\"b\"", lexer.input.slice((try lexer.next()).span).?);
    try std.testing.expectEqual(Kind.global, (try lexer.next()).kind);
    try std.testing.expectEqualStrings("\"ends\\\\\"", lexer.input.slice((try lexer.next()).span).?);
    try std.testing.expectEqual(Kind.eof, (try lexer.next()).kind);
}

test "float spellings retain widths, signs, hexadecimal and payload text" {
    var lexer: Lexer = .{ .input = .{ .name = "test", .text = "s_-0 d_0x1.8p+2 s_1.25e-3 d_+INF s_nan(payload) d_ 2.5" } };
    for ([_]Kind{ .single, .double, .single, .double, .single, .double }) |kind| try std.testing.expectEqual(kind, (try lexer.next()).kind);
    try std.testing.expectEqual(Kind.eof, (try lexer.next()).kind);
}

test "malformed tokens report precise typed diagnostics" {
    const cases = .{
        .{ "%1", source.Diagnostic.Code.invalid_name },
        .{ "-", source.Diagnostic.Code.invalid_integer },
        .{ "123abc", source.Diagnostic.Code.invalid_integer },
        .{ "s_1e+", source.Diagnostic.Code.invalid_float },
        .{ "d_", source.Diagnostic.Code.invalid_float },
        .{ "d_1_0", source.Diagnostic.Code.invalid_float },
        .{ "\"unterminated", source.Diagnostic.Code.unterminated_string },
        .{ "\r", source.Diagnostic.Code.invalid_character },
        .{ "\x00", source.Diagnostic.Code.invalid_character },
        .{ "s_nan(bad!", source.Diagnostic.Code.invalid_float },
    };
    inline for (cases) |case| {
        var lexer: Lexer = .{ .input = .{ .name = "bad", .text = case[0] } };
        try std.testing.expectError(error.InvalidInput, lexer.next());
        try std.testing.expectEqual(case[1], lexer.diagnostic.?.code);
        try std.testing.expectEqual(@as(usize, 0), lexer.diagnostic.?.span.start);
        try std.testing.expect(lexer.cursor > 0);
    }
}

test "decimal bit patterns wrap without host signed overflow" {
    try std.testing.expectEqual(@as(u64, 0xffffffffffffffff), try integerBits("-1"));
    try std.testing.expectEqual(@as(u64, 0), try integerBits("18446744073709551616"));
    try std.testing.expectEqual(@as(u64, 0x8000000000000000), try integerBits("-9223372036854775808"));
    try std.testing.expectError(error.InvalidInteger, integerBits("+1"));
}

test "arbitrary byte pairs always advance or reach EOF without invalid spans" {
    var bytes: [2]u8 = undefined;
    for (0..256) |a| for (0..256) |b| {
        bytes = .{ @intCast(a), @intCast(b) };
        var lexer: Lexer = .{ .input = .{ .name = "bytes", .text = &bytes } };
        for (0..3) |_| {
            const previous = lexer.cursor;
            const token = lexer.next() catch {
                try std.testing.expect(lexer.cursor > previous);
                try std.testing.expect(lexer.input.slice(lexer.diagnostic.?.span) != null);
                continue;
            };
            try std.testing.expect(lexer.input.slice(token.span) != null);
            if (token.kind == .eof) break;
            try std.testing.expect(lexer.cursor > previous);
        }
    };
}
