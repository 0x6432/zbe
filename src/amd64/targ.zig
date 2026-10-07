//! One-to-one translation of amd64/targ.c
const std = @import("std");
// -- imports --
const all = @import("../all.zig");
const tgt = @import("all.zig");
const Amd64Op = tgt.Amd64Op;
const BIT = all.BIT;
const NFPR = tgt.NFPR;
const NFPS = tgt.NFPS;
const NGPR = tgt.NGPR;
const NGPS_SYSV = tgt.NGPS_SYSV;
const NGPS_WIN = tgt.NGPS_WIN;
const NOp = all.NOp;
const RAX = tgt.RAX;
const RBP = tgt.RBP;
const RSP = tgt.RSP;
const Target = all.Target;
const XMM0 = tgt.XMM0;
const amd64_isel = tgt.amd64_isel;
const amd64_sysv_abi = tgt.amd64_sysv_abi;
const amd64_sysv_argregs = tgt.amd64_sysv_argregs;
const amd64_sysv_emitfn = tgt.amd64_sysv_emitfn;
const amd64_sysv_retregs = tgt.amd64_sysv_retregs;
const amd64_winabi_abi = tgt.amd64_winabi_abi;
const amd64_winabi_argregs = tgt.amd64_winabi_argregs;
const amd64_winabi_emitfn = tgt.amd64_winabi_emitfn;
const amd64_winabi_retregs = tgt.amd64_winabi_retregs;
const elf_emitfin = all.elf_emitfin;
const elimsb = all.elimsb;
const macho_emitfin = all.macho_emitfin;
const pe_emitfin = all.pe_emitfin;
const strarr = all.strarr;
// -- end imports --

pub const amd64_op: [NOp]Amd64Op = blk: {
    var t: [NOp]Amd64Op = @splat(.{ .nmem = 0, .zflag = 0, .lflag = 0 });
    for (all.ops.defs, 1..) |d, i|
        t[i] = .{ .nmem = d.x[0], .zflag = d.x[1], .lflag = d.x[2] };
    break :blk t;
};

fn amd64_memargs(op: i32) i32 {
    return amd64_op[@intCast(op)].nmem;
}

fn common(t: Target) Target {
    var r = t;
    r.gpr0 = RAX;
    r.ngpr = NGPR;
    r.fpr0 = XMM0;
    r.nfpr = NFPR;
    r.rglob = BIT(RBP) | BIT(RSP);
    r.nrglob = 2;
    r.memargs = &amd64_memargs;
    r.abi0 = &elimsb;
    r.isel = &amd64_isel;
    r.cansel = 1;
    return r;
}

pub var T_amd64_sysv: Target = undefined;
pub var T_amd64_apple: Target = undefined;
pub var T_amd64_win: Target = undefined;

/// runtime initialization (C static initializers reference
/// mutable arrays, which Zig cannot take at comptime as [*c])
pub fn init() void {
    T_amd64_sysv = common(.{
        .name = strarr(16, "amd64_sysv"),
        .apple = 0,
        .windows = 0,
        .gpr0 = 0, .ngpr = 0, .fpr0 = 0, .nfpr = 0, .rglob = 0, .nrglob = 0,
        .emitfin = &elf_emitfin,
        .asloc = strarr(4, ".L"),
        .assym = strarr(4, ""),
        .abi1 = &amd64_sysv_abi,
        .rsave = &tgt.sysv.amd64_sysv_rsave,
        .nrsave = .{ NGPS_SYSV, NFPS },
        .retregs = &amd64_sysv_retregs,
        .argregs = &amd64_sysv_argregs,
        .emitfn = &amd64_sysv_emitfn,
        .memargs = &amd64_memargs, .abi0 = &elimsb, .isel = &amd64_isel, .cansel = 1,
    });
    T_amd64_apple = common(.{
        .name = strarr(16, "amd64_apple"),
        .apple = 1,
        .windows = 0,
        .gpr0 = 0, .ngpr = 0, .fpr0 = 0, .nfpr = 0, .rglob = 0, .nrglob = 0,
        .emitfin = &macho_emitfin,
        .asloc = strarr(4, "L"),
        .assym = strarr(4, "_"),
        .abi1 = &amd64_sysv_abi,
        .rsave = &tgt.sysv.amd64_sysv_rsave,
        .nrsave = .{ NGPS_SYSV, NFPS },
        .retregs = &amd64_sysv_retregs,
        .argregs = &amd64_sysv_argregs,
        .emitfn = &amd64_sysv_emitfn,
        .memargs = &amd64_memargs, .abi0 = &elimsb, .isel = &amd64_isel, .cansel = 1,
    });
    T_amd64_win = common(.{
        .name = strarr(16, "amd64_win"),
        .apple = 0,
        .windows = 1,
        .gpr0 = 0, .ngpr = 0, .fpr0 = 0, .nfpr = 0, .rglob = 0, .nrglob = 0,
        .emitfin = &pe_emitfin,
        .asloc = strarr(4, "L"),
        .assym = strarr(4, ""),
        .abi1 = &amd64_winabi_abi,
        .rsave = &tgt.winabi.amd64_winabi_rsave,
        .nrsave = .{ NGPS_WIN, NFPS },
        .retregs = &amd64_winabi_retregs,
        .argregs = &amd64_winabi_argregs,
        .emitfn = &amd64_winabi_emitfn,
        .memargs = &amd64_memargs, .abi0 = &elimsb, .isel = &amd64_isel, .cansel = 1,
    });
}
