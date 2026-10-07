//! One-to-one translation of arm64/all.h
const all = @import("../all.zig");

pub const R0 = all.RXX + 1;
pub const R1 = all.RXX + 2;
pub const R2 = all.RXX + 3;
pub const R3 = all.RXX + 4;
pub const R4 = all.RXX + 5;
pub const R5 = all.RXX + 6;
pub const R6 = all.RXX + 7;
pub const R7 = all.RXX + 8;
pub const R8 = all.RXX + 9;
pub const R9 = all.RXX + 10;
pub const R10 = all.RXX + 11;
pub const R11 = all.RXX + 12;
pub const R12 = all.RXX + 13;
pub const R13 = all.RXX + 14;
pub const R14 = all.RXX + 15;
pub const R15 = all.RXX + 16;
pub const IP0 = all.RXX + 17;
pub const IP1 = all.RXX + 18;
pub const R18 = all.RXX + 19;
pub const R19 = all.RXX + 20;
pub const R20 = all.RXX + 21;
pub const R21 = all.RXX + 22;
pub const R22 = all.RXX + 23;
pub const R23 = all.RXX + 24;
pub const R24 = all.RXX + 25;
pub const R25 = all.RXX + 26;
pub const R26 = all.RXX + 27;
pub const R27 = all.RXX + 28;
pub const R28 = all.RXX + 29;
pub const FP = all.RXX + 30;
pub const LR = all.RXX + 31;
pub const SP = all.RXX + 32;
pub const V0 = all.RXX + 33;
pub const V1 = all.RXX + 34;
pub const V2 = all.RXX + 35;
pub const V3 = all.RXX + 36;
pub const V4 = all.RXX + 37;
pub const V5 = all.RXX + 38;
pub const V6 = all.RXX + 39;
pub const V7 = all.RXX + 40;
pub const V8 = all.RXX + 41;
pub const V9 = all.RXX + 42;
pub const V10 = all.RXX + 43;
pub const V11 = all.RXX + 44;
pub const V12 = all.RXX + 45;
pub const V13 = all.RXX + 46;
pub const V14 = all.RXX + 47;
pub const V15 = all.RXX + 48;
pub const V16 = all.RXX + 49;
pub const V17 = all.RXX + 50;
pub const V18 = all.RXX + 51;
pub const V19 = all.RXX + 52;
pub const V20 = all.RXX + 53;
pub const V21 = all.RXX + 54;
pub const V22 = all.RXX + 55;
pub const V23 = all.RXX + 56;
pub const V24 = all.RXX + 57;
pub const V25 = all.RXX + 58;
pub const V26 = all.RXX + 59;
pub const V27 = all.RXX + 60;
pub const V28 = all.RXX + 61;
pub const V29 = all.RXX + 62;
pub const V30 = all.RXX + 63;

pub const NFPR = V30 - V0 + 1;
pub const NGPR = SP - R0 + 1;
pub const NGPS = R18 - R0 + 1 + 1; // + LR
pub const NFPS = (V7 - V0 + 1) + (V30 - V16 + 1);
pub const NCLR = (R28 - R19 + 1) + (V15 - V8 + 1);

comptime {
    if (!(V30 < all.Tmp0)) @compileError("reg_not_tmp");
}

// targ.c
pub const targ = @import("targ.zig");
pub const arm64_rsave = &targ.arm64_rsave;
pub const arm64_rclob = &targ.arm64_rclob;

// abi.c
pub const abi = @import("abi.zig");
pub const arm64_retregs = abi.arm64_retregs;
pub const arm64_argregs = abi.arm64_argregs;
pub const arm64_abi = abi.arm64_abi;
pub const apple_extsb = abi.apple_extsb;

// isel.c
pub const isel = @import("isel.zig");
pub const arm64_logimm = isel.arm64_logimm;
pub const arm64_isel = isel.arm64_isel;

// emit.c
pub const emit_ = @import("emit.zig");
pub const arm64_emitfn = emit_.arm64_emitfn;
