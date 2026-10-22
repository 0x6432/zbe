const std = @import("std");

/// Half-open byte offsets into one Source. Offsets do not own the input.
pub const Span = struct { start: usize, end: usize };
pub const Location = struct { line: usize, column: usize };
pub const Source = struct {
    name: []const u8,
    text: []const u8,

    pub fn slice(self: Source, span: Span) ?[]const u8 {
        if (span.start > span.end or span.end > self.text.len) return null;
        return self.text[span.start..span.end];
    }

    /// One-based lines and byte columns. CRLF has one line break, at LF.
    pub fn location(self: Source, offset: usize) ?Location {
        if (offset > self.text.len) return null;
        var result: Location = .{ .line = 1, .column = 1 };
        for (self.text[0..offset]) |byte| {
            if (byte == '\n') {
                result.line += 1;
                result.column = 1;
            } else result.column += 1;
        }
        return result;
    }
};

/// Typed frontend errors; rendering/CLI wording is a separate boundary.
pub const Diagnostic = struct {
    code: Code,
    span: Span,

    pub const Code = enum {
        invalid_character,
        invalid_name,
        unterminated_string,
        invalid_integer,
        invalid_float,
        invalid_string,
        unexpected_token,
        unsupported_construct,
        duplicate_type,
        unknown_type,
        invalid_record_count,
        invalid_opaque_size,
        duplicate_function,
        duplicate_symbol,
        invalid_alignment,
        duplicate_block,
        duplicate_value,
        unknown_block,
        unknown_value,
        type_mismatch,
        missing_terminator,
        block_terminated,
        phi_after_instruction,
        invalid_return,
        invalid_ir,
    };
};

test "source spans are checked and locations use byte columns" {
    const s: Source = .{ .name = "test", .text = "a\r\nλ\nb" };
    try std.testing.expectEqualStrings("λ", s.slice(.{ .start = 3, .end = 5 }).?);
    try std.testing.expect(s.slice(.{ .start = 3, .end = 2 }) == null);
    try std.testing.expect(s.slice(.{ .start = 0, .end = 99 }) == null);
    try std.testing.expectEqual(Location{ .line = 2, .column = 3 }, s.location(5).?);
    try std.testing.expectEqual(Location{ .line = 3, .column = 2 }, s.location(s.text.len).?);
    try std.testing.expect(s.location(99) == null);
}
