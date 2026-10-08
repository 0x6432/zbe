//! One-to-one translation of rv64/all.h
const all = @import("../all.zig");

// caller-save: T0..A7; callee-save: S1..S11; globally live: FP..RA;
// FP caller-save: FT0..FA7; FP callee-save: FS0..FS11;
// reserved (see rv64/emit.c): T6, FT11
pub const T0 = all.RXX + 1;
pub const T1 = all.RXX + 2;
pub const T2 = all.RXX + 3;
pub const T3 = all.RXX + 4;
pub const T4 = all.RXX + 5;
pub const T5 = all.RXX + 6;
pub const A0 = all.RXX + 7;
pub const A1 = all.RXX + 8;
pub const A2 = all.RXX + 9;
pub const A3 = all.RXX + 10;
pub const A4 = all.RXX + 11;
pub const A5 = all.RXX + 12;
pub const A6 = all.RXX + 13;
pub const A7 = all.RXX + 14;
pub const S1 = all.RXX + 15;
pub const S2 = all.RXX + 16;
pub const S3 = all.RXX + 17;
pub const S4 = all.RXX + 18;
pub const S5 = all.RXX + 19;
pub const S6 = all.RXX + 20;
pub const S7 = all.RXX + 21;
pub const S8 = all.RXX + 22;
pub const S9 = all.RXX + 23;
pub const S10 = all.RXX + 24;
pub const S11 = all.RXX + 25;
pub const FP = all.RXX + 26;
pub const SP = all.RXX + 27;
pub const GP = all.RXX + 28;
pub const TP = all.RXX + 29;
pub const RA = all.RXX + 30;
pub const FT0 = all.RXX + 31;
pub const FT1 = all.RXX + 32;
pub const FT2 = all.RXX + 33;
pub const FT3 = all.RXX + 34;
pub const FT4 = all.RXX + 35;
pub const FT5 = all.RXX + 36;
pub const FT6 = all.RXX + 37;
pub const FT7 = all.RXX + 38;
pub const FT8 = all.RXX + 39;
pub const FT9 = all.RXX + 40;
pub const FT10 = all.RXX + 41;
pub const FA0 = all.RXX + 42;
pub const FA1 = all.RXX + 43;
pub const FA2 = all.RXX + 44;
pub const FA3 = all.RXX + 45;
pub const FA4 = all.RXX + 46;
pub const FA5 = all.RXX + 47;
pub const FA6 = all.RXX + 48;
pub const FA7 = all.RXX + 49;
pub const FS0 = all.RXX + 50;
pub const FS1 = all.RXX + 51;
pub const FS2 = all.RXX + 52;
pub const FS3 = all.RXX + 53;
pub const FS4 = all.RXX + 54;
pub const FS5 = all.RXX + 55;
pub const FS6 = all.RXX + 56;
pub const FS7 = all.RXX + 57;
pub const FS8 = all.RXX + 58;
pub const FS9 = all.RXX + 59;
pub const FS10 = all.RXX + 60;
pub const FS11 = all.RXX + 61;
pub const T6 = all.RXX + 62;
pub const FT11 = all.RXX + 63;

pub const NFPR = FS11 - FT0 + 1;
pub const NGPR = RA - T0 + 1;
pub const NGPS = A7 - T0 + 1;
pub const NFPS = FA7 - FT0 + 1;
pub const NCLR = (S11 - S1 + 1) + (FS11 - FS0 + 1);

comptime {
    if (!(FT11 < all.Tmp0)) @compileError("reg_not_tmp");
}

pub const Rv64Op = extern struct {
    imm: u8,
};

// targ.c
pub const targ = @import("targ.zig");
pub const rv64_rsave = &targ.rv64_rsave;
pub const rv64_rclob = &targ.rv64_rclob;
pub const rv64_op = &targ.rv64_op;

// abi.c
pub const abi = @import("abi.zig");
pub const rv64_retregs = abi.rv64_retregs;
pub const rv64_argregs = abi.rv64_argregs;
pub const rv64_abi = abi.rv64_abi;

// isel.c
pub const rv64_isel = @import("isel.zig").rv64_isel;

// emit.c
pub const emit_ = @import("emit.zig");
pub const rv64_emitfn = emit_.rv64_emitfn;
