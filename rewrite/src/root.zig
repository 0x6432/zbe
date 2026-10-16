//! Independent Zig-native core. This is not yet a compiler backend.
//! No legacy module is imported and no compilation delegates to the old port.
pub const source = @import("source.zig");
pub const frontend = @import("frontend.zig");
pub const lexer = @import("lexer.zig");
pub const symbols = @import("symbols.zig");
pub const ir = @import("ir.zig");
pub const Module = @import("module.zig").Module;

test {
    _ = @import("source.zig");
    _ = @import("lexer.zig");
    _ = @import("frontend.zig");
    _ = @import("symbols.zig");
    _ = @import("ir.zig");
    _ = @import("module.zig");
}
