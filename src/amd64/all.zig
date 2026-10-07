//! One-to-one translation of amd64/all.h
const all = @import("../all.zig");

pub const RAX = all.RXX + 1; // caller-save
pub const RCX = RAX + 1; // caller-save
pub const RDX = RAX + 2; // caller-save
pub const RSI = RAX + 3; // caller-save on sysv, callee-save on win
pub const RDI = RAX + 4; // caller-save on sysv, callee-save on win
pub const R8 = RAX + 5; // caller-save
pub const R9 = RAX + 6; // caller-save
pub const R10 = RAX + 7; // caller-save
pub const R11 = RAX + 8; // caller-save

pub const RBX = RAX + 9; // callee-save
pub const R12 = RAX + 10;
pub const R13 = RAX + 11;
pub const R14 = RAX + 12;
pub const R15 = RAX + 13;

pub const RBP = RAX + 14; // globally live
pub const RSP = RAX + 15;

pub const XMM0 = RAX + 16; // sse
pub const XMM1 = XMM0 + 1;
pub const XMM2 = XMM0 + 2;
pub const XMM3 = XMM0 + 3;
pub const XMM4 = XMM0 + 4;
pub const XMM5 = XMM0 + 5;
pub const XMM6 = XMM0 + 6;
pub const XMM7 = XMM0 + 7;
pub const XMM8 = XMM0 + 8;
pub const XMM9 = XMM0 + 9;
pub const XMM10 = XMM0 + 10;
pub const XMM11 = XMM0 + 11;
pub const XMM12 = XMM0 + 12;
pub const XMM13 = XMM0 + 13;
pub const XMM14 = XMM0 + 14;
pub const XMM15 = XMM0 + 15;

pub const NFPR = XMM14 - XMM0 + 1; // reserve XMM15
pub const NGPR = RSP - RAX + 1;
pub const NFPS = NFPR;

pub const NGPS_SYSV = R11 - RAX + 1;
pub const NCLR_SYSV = R15 - RBX + 1;

pub const NGPS_WIN = R11 - RAX + 1 - 2; // -2 for RDI/RDI
pub const NCLR_WIN = R15 - RBX + 1 + 2; // +2 for RDI/RDI

comptime {
    if (!(XMM15 < all.Tmp0)) @compileError("reg_not_tmp");
}

pub const Amd64Op = extern struct {
    nmem: u8,
    zflag: u8,
    lflag: u8,
};

// targ.c
pub const targ = @import("targ.zig");
pub const amd64_op = &targ.amd64_op;

// sysv.c (abi)
pub const sysv = @import("sysv.zig");
pub const amd64_sysv_retregs = sysv.amd64_sysv_retregs;
pub const amd64_sysv_argregs = sysv.amd64_sysv_argregs;
pub const amd64_sysv_abi = sysv.amd64_sysv_abi;

// winabi.c
pub const winabi = @import("winabi.zig");
pub const amd64_winabi_retregs = winabi.amd64_winabi_retregs;
pub const amd64_winabi_argregs = winabi.amd64_winabi_argregs;
pub const amd64_winabi_abi = winabi.amd64_winabi_abi;

// isel.c
pub const amd64_isel = @import("isel.zig").amd64_isel;

// emit.c
pub const emit_ = @import("emit.zig");
pub const amd64_sysv_emitfn = emit_.amd64_sysv_emitfn;
pub const amd64_winabi_emitfn = emit_.amd64_winabi_emitfn;
