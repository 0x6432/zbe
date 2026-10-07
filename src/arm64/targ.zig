//! One-to-one translation of arm64/targ.c
const std = @import("std");
// -- imports --
const all = @import("../all.zig");
const tgt = @import("all.zig");
const BIT = all.BIT;
const FP = tgt.FP;
const IP0 = tgt.IP0;
const IP1 = tgt.IP1;
const LR = tgt.LR;
const NCLR = tgt.NCLR;
const NFPR = tgt.NFPR;
const NFPS = tgt.NFPS;
const NGPR = tgt.NGPR;
const NGPS = tgt.NGPS;
const R0 = tgt.R0;
const R1 = tgt.R1;
const R10 = tgt.R10;
const R11 = tgt.R11;
const R12 = tgt.R12;
const R13 = tgt.R13;
const R14 = tgt.R14;
const R15 = tgt.R15;
const R18 = tgt.R18;
const R19 = tgt.R19;
const R2 = tgt.R2;
const R20 = tgt.R20;
const R21 = tgt.R21;
const R22 = tgt.R22;
const R23 = tgt.R23;
const R24 = tgt.R24;
const R25 = tgt.R25;
const R26 = tgt.R26;
const R27 = tgt.R27;
const R28 = tgt.R28;
const R3 = tgt.R3;
const R4 = tgt.R4;
const R5 = tgt.R5;
const R6 = tgt.R6;
const R7 = tgt.R7;
const R8 = tgt.R8;
const R9 = tgt.R9;
const SP = tgt.SP;
const Target = all.Target;
const V0 = tgt.V0;
const V1 = tgt.V1;
const V10 = tgt.V10;
const V11 = tgt.V11;
const V12 = tgt.V12;
const V13 = tgt.V13;
const V14 = tgt.V14;
const V15 = tgt.V15;
const V16 = tgt.V16;
const V17 = tgt.V17;
const V18 = tgt.V18;
const V19 = tgt.V19;
const V2 = tgt.V2;
const V20 = tgt.V20;
const V21 = tgt.V21;
const V22 = tgt.V22;
const V23 = tgt.V23;
const V24 = tgt.V24;
const V25 = tgt.V25;
const V26 = tgt.V26;
const V27 = tgt.V27;
const V28 = tgt.V28;
const V29 = tgt.V29;
const V3 = tgt.V3;
const V30 = tgt.V30;
const V4 = tgt.V4;
const V5 = tgt.V5;
const V6 = tgt.V6;
const V7 = tgt.V7;
const V8 = tgt.V8;
const V9 = tgt.V9;
const apple_extsb = tgt.apple_extsb;
const arm64_abi = tgt.arm64_abi;
const arm64_argregs = tgt.arm64_argregs;
const arm64_emitfn = tgt.arm64_emitfn;
const arm64_isel = tgt.arm64_isel;
const arm64_retregs = tgt.arm64_retregs;
const elf_emitfin = all.elf_emitfin;
const elimsb = all.elimsb;
const macho_emitfin = all.macho_emitfin;
const strarr = all.strarr;
// -- end imports --

pub var arm64_rsave = [_]i32{
    R0,  R1,  R2,  R3,  R4,  R5,  R6,  R7,
    R8,  R9,  R10, R11, R12, R13, R14, R15,
    IP0, IP1, R18, LR,
    V0,  V1,  V2,  V3,  V4,  V5,  V6,  V7,
    V16, V17, V18, V19, V20, V21, V22, V23,
    V24, V25, V26, V27, V28, V29, V30,
    -1,
};
pub var arm64_rclob = [_]i32{
    R19, R20, R21, R22, R23, R24, R25, R26,
    R27, R28,
    V8,  V9,  V10, V11, V12, V13, V14, V15,
    -1,
};

const RGLOB = BIT(FP) | BIT(SP) | BIT(IP1) | BIT(R18);

fn arm64_memargs(op: i32) i32 {
    _ = op;
    return 0;
}

fn common(t: Target) Target {
    var r = t;
    r.gpr0 = R0;
    r.ngpr = NGPR;
    r.fpr0 = V0;
    r.nfpr = NFPR;
    r.rglob = RGLOB;
    r.nrglob = 4;
    r.rsave = &arm64_rsave;
    r.nrsave = .{ NGPS, NFPS };
    r.retregs = &arm64_retregs;
    r.argregs = &arm64_argregs;
    r.memargs = &arm64_memargs;
    r.isel = &arm64_isel;
    r.abi1 = &arm64_abi;
    r.emitfn = &arm64_emitfn;
    r.cansel = 0;
    return r;
}

pub var T_arm64: Target = undefined;
pub var T_arm64_apple: Target = undefined;

pub fn init() void {
    var t: Target = undefined;
    t.windows = 0;
    t.apple = 0;
    t.name = strarr(16, "arm64");
    t.abi0 = &elimsb;
    t.emitfin = &elf_emitfin;
    t.asloc = strarr(4, ".L");
    t.assym = strarr(4, "");
    T_arm64 = common(t);
    t.name = strarr(16, "arm64_apple");
    t.apple = 1;
    t.abi0 = &apple_extsb;
    t.emitfin = &macho_emitfin;
    t.asloc = strarr(4, "L");
    t.assym = strarr(4, "_");
    T_arm64_apple = common(t);
}

comptime {
    if ((RGLOB & (BIT(R8 + 1) - 1)) != 0) @compileError("globals_are_not_arguments");
    if (!(arm64_rsave.len == NGPS + NFPS + 1 and arm64_rclob.len == NCLR + 1))
        @compileError("arrays_size_ok");
}
