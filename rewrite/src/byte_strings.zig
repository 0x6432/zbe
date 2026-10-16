//! Deliberately bounded byte-string syntax, independent of GNU assembler parsing.
const std = @import("std");
pub const Error = std.mem.Allocator.Error || error{ InvalidStringLiteral, DataTooLarge };
/// Caller owns the result. Validate/count before allocating; bytes are never
/// normalized as Unicode or interpreted as assembly. max_bytes is a payload cap.
pub fn decode(allocator: std.mem.Allocator, token: []const u8, max_bytes: usize) Error![]u8 {
    const count = try scan(token, null);
    if (count > max_bytes) return error.DataTooLarge;
    const bytes = try allocator.alloc(u8, count);
    errdefer allocator.free(bytes);
    _ = try scan(token, bytes);
    return bytes;
}
fn scan(token: []const u8, output: ?[]u8) error{InvalidStringLiteral}!usize {
    if (token.len < 2 or token[0] != '"' or token[token.len - 1] != '"') return error.InvalidStringLiteral;
    const limit = token.len - 1;
    var index: usize = 1;
    var count: usize = 0;
    while (index < limit) {
        var byte = token[index];
        index += 1;
        if (byte == '"' or byte == '\n' or byte == '\r') return error.InvalidStringLiteral;
        if (byte == '\\') {
            if (index == limit) return error.InvalidStringLiteral;
            const escape = token[index];
            index += 1;
            byte = switch (escape) {
                '"' => '"',
                '\\' => '\\',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                'a' => 7,
                'b' => 8,
                'f' => 12,
                'v' => 11,
                'x' => hex: {
                    if (limit - index < 2) return error.InvalidStringLiteral;
                    const high = std.fmt.charToDigit(token[index], 16) catch return error.InvalidStringLiteral;
                    const low = std.fmt.charToDigit(token[index + 1], 16) catch return error.InvalidStringLiteral;
                    index += 2;
                    break :hex high * 16 + low;
                },
                '0'...'7' => octal: {
                    var value: u16 = escape - '0';
                    var digits: usize = 1;
                    while (digits < 3 and index < limit and token[index] >= '0' and token[index] <= '7') : (digits += 1) {
                        value = value * 8 + (token[index] - '0');
                        index += 1;
                    }
                    if (value > 255) return error.InvalidStringLiteral;
                    break :octal @intCast(value);
                },
                else => return error.InvalidStringLiteral,
            };
        }
        if (output) |bytes| bytes[count] = byte;
        count += 1;
    }
    return count;
}
