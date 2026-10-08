//! One-to-one translation of rv64/targ.c
const std = @import("std");
// -- imports --
const all = @import("../all.zig");
const tgt = @import("all.zig");
const A0 = tgt.A0;
const A1 = tgt.A1;
const A2 = tgt.A2;
const A3 = tgt.A3;
const A4 = tgt.A4;
const A5 = tgt.A5;
const A6 = tgt.A6;
const A7 = tgt.A7;
const BIT = all.BIT;
const FA0 = tgt.FA0;
const FA1 = tgt.FA1;
const FA2 = tgt.FA2;
const FA3 = tgt.FA3;
const FA4 = tgt.FA4;
const FA5 = tgt.FA5;
const FA6 = tgt.FA6;
const FA7 = tgt.FA7;
const FP = tgt.FP;
const FS0 = tgt.FS0;
const FS1 = tgt.FS1;
const FS10 = tgt.FS10;
const FS11 = tgt.FS11;
const FS2 = tgt.FS2;
const FS3 = tgt.FS3;
const FS4 = tgt.FS4;
const FS5 = tgt.FS5;
const FS6 = tgt.FS6;
const FS7 = tgt.FS7;
const FS8 = tgt.FS8;
const FS9 = tgt.FS9;
const FT0 = tgt.FT0;
const FT1 = tgt.FT1;
const FT10 = tgt.FT10;
const FT2 = tgt.FT2;
const FT3 = tgt.FT3;
const FT4 = tgt.FT4;
const FT5 = tgt.FT5;
const FT6 = tgt.FT6;
const FT7 = tgt.FT7;
const FT8 = tgt.FT8;
const FT9 = tgt.FT9;
const GP = tgt.GP;
const NCLR = tgt.NCLR;
const NFPR = tgt.NFPR;
const NFPS = tgt.NFPS;
const NGPR = tgt.NGPR;
const NGPS = tgt.NGPS;
const NOp = all.NOp;
const RA = tgt.RA;
const Rv64Op = tgt.Rv64Op;
const S1 = tgt.S1;
const S10 = tgt.S10;
const S11 = tgt.S11;
const S2 = tgt.S2;
const S3 = tgt.S3;
const S4 = tgt.S4;
const S5 = tgt.S5;
const S6 = tgt.S6;
const S7 = tgt.S7;
const S8 = tgt.S8;
const S9 = tgt.S9;
const SP = tgt.SP;
const T0 = tgt.T0;
const T1 = tgt.T1;
const T2 = tgt.T2;
const T3 = tgt.T3;
const T4 = tgt.T4;
const T5 = tgt.T5;
const TP = tgt.TP;
const Target = all.Target;
const elf_emitfin = all.elf_emitfin;
const elimsb = all.elimsb;
const rv64_abi = tgt.rv64_abi;
const rv64_argregs = tgt.rv64_argregs;
const rv64_emitfn = tgt.rv64_emitfn;
const rv64_isel = tgt.rv64_isel;
const rv64_retregs = tgt.rv64_retregs;
const strarr = all.strarr;
// -- end imports --

pub const rv64_op: [NOp]Rv64Op = blk: {
    var t: [NOp]Rv64Op = @splat(.{ .imm = 0 });
    for (all.ops.defs, 1..) |d, i|
        t[i] = .{ .imm = d.v };
    break :blk t;
};

pub var rv64_rsave = [_]i32{
    T0,  T1,  T2,   T3,  T4,  T5,
    A0,  A1,  A2,   A3,  A4,  A5,  A6, A7,
    FA0, FA1, FA2,  FA3, FA4, FA5, FA6, FA7,
    FT0, FT1, FT2,  FT3, FT4, FT5, FT6, FT7,
    FT8, FT9, FT10,
    -1,
};
pub var rv64_rclob = [_]i32{
    S1,  S2,  S3,   S4,   S5,  S6,  S7,
    S8,  S9,  S10,  S11,
    FS0, FS1, FS2,  FS3,  FS4, FS5, FS6, FS7,
    FS8, FS9, FS10, FS11,
    -1,
};

const RGLOB = BIT(FP) | BIT(SP) | BIT(GP) | BIT(TP) | BIT(RA);

fn rv64_memargs(op: i32) i32 {
    _ = op;
    return 0;
}

pub var T_rv64: Target = undefined;

pub fn init() void {
    T_rv64 = .{
        .name = strarr(16, "rv64"),
        .apple = 0,
        .windows = 0,
        .gpr0 = T0,
        .ngpr = NGPR,
        .fpr0 = FT0,
        .nfpr = NFPR,
        .rglob = RGLOB,
        .nrglob = 5,
        .rsave = &rv64_rsave,
        .nrsave = .{ NGPS, NFPS },
        .retregs = &rv64_retregs,
        .argregs = &rv64_argregs,
        .memargs = &rv64_memargs,
        .abi0 = &elimsb,
        .abi1 = &rv64_abi,
        .isel = &rv64_isel,
        .emitfn = &rv64_emitfn,
        .emitfin = &elf_emitfin,
        .asloc = strarr(4, ".L"),
        .assym = strarr(4, ""),
        .cansel = 0,
    };
}

comptime {
    if (rv64_rsave.len != NGPS + NFPS + 1) @compileError("rsave_size_ok");
    if (rv64_rclob.len != NCLR + 1) @compileError("rclob_size_ok");
}
