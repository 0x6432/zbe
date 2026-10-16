//! Independent Zig-native core. This is not yet a compiler backend.
//! No legacy module is imported and no compilation delegates to the old port.
pub const amd64 = @import("amd64.zig");
pub const interpreter = @import("interpreter.zig");
pub const cfg = @import("cfg.zig");
pub const ssa = @import("ssa.zig");
pub const source = @import("source.zig");
pub const frontend = @import("frontend.zig");
pub const lexer = @import("lexer.zig");
pub const symbols = @import("symbols.zig");
pub const ir = @import("ir.zig");
pub const Module = @import("module.zig").Module;

test {
    _ = @import("amd64.zig");
    _ = @import("interpreter.zig");
    _ = @import("cfg.zig");
    _ = @import("ssa.zig");
    _ = @import("source.zig");
    _ = @import("lexer.zig");
    _ = @import("frontend.zig");
    _ = @import("symbols.zig");
    _ = @import("ir.zig");
    _ = @import("module.zig");
}
