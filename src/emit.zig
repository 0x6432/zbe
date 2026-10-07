//! One-to-one translation of emit.c
const std = @import("std");
const assert = std.debug.assert;
const C = @import("libc.zig");
// -- imports --
const all = @import("all.zig");
const DB = all.DB;
const DEnd = all.DEnd;
const DH = all.DH;
const DL = all.DL;
const DStart = all.DStart;
const DW = all.DW;
const DZ = all.DZ;
const Dat = all.Dat;
const FILE = all.FILE;
const Lnk = all.Lnk;
const PHeap = all.PHeap;
const bits = all.bits;
const die = all.die;
const emalloc = all.emalloc;
const err = all.err;
const intern = all.intern;
const uint = all.uint;
const vgrow = all.vgrow;
const vnewT = all.vnewT;
// -- end imports --

const SecText = 0;
const SecData = 1;
const SecBss = 2;

const lnk_sec = [2][3][*c]const u8{
    .{ ".text", ".data", ".bss" },
    .{ ".abort \"unreachable\"", ".section .tdata,\"awT\"", ".section .tbss,\"awT\"" },
};

pub fn emitlnk(n: [*c]u8, l: [*c]Lnk, s: i32, f: *FILE) void {
    const pfx: [*c]const u8 = if (n[0] == '"') "" else &all.T.assym;
    var sfx: [*c]const u8 = "";
    if (all.T.apple != 0 and l.*.thread != 0) {
        l.*.sec = @constCast("__DATA");
        l.*.secf = @constCast("__thread_data,thread_local_regular");
        sfx = "$tlv$init";
        _ = C.fputs(".section __DATA,__thread_vars," ++
            "thread_local_variables\n", f);
        _ = C.fprintf(f, "%s%s:\n", pfx, n);
        _ = C.fprintf(f, "\t.quad __tlv_bootstrap\n" ++
            "\t.quad 0\n" ++
            "\t.quad %s%s%s\n\n", pfx, n, sfx);
    }
    if (l.*.sec != null) {
        _ = C.fprintf(f, ".section %s", l.*.sec);
        if (l.*.secf != null)
            _ = C.fprintf(f, ",%s", l.*.secf);
    } else _ = C.fputs(lnk_sec[@intFromBool(l.*.thread != 0)][@intCast(s)], f);
    _ = C.fputc('\n', f);
    if (l.*.@"align" != 0)
        _ = C.fprintf(f, ".balign %d\n", @as(c_int, l.*.@"align"));
    if (l.*.@"export" != 0)
        _ = C.fprintf(f, ".globl %s%s\n", pfx, n);
    _ = C.fprintf(f, "%s%s%s:\n", pfx, n, sfx);
}

pub fn emitfnlnk(n: [*c]u8, l: [*c]Lnk, f: *FILE) void {
    emitlnk(n, l, SecText, f);
}

const DatInfo = struct {
    decl: [*c]const u8,
    mask: i64,
};
const di = blk: {
    var t: [DL + 1]DatInfo = undefined;
    t[DB] = .{ .decl = "\t.byte", .mask = 0xff };
    t[DH] = .{ .decl = "\t.short", .mask = 0xffff };
    t[DW] = .{ .decl = "\t.int", .mask = 0xffffffff };
    t[DL] = .{ .decl = "\t.quad", .mask = -1 };
    break :blk t;
};
var emitdat_zero: i64 = 0;

pub fn emitdat(d: [*c]Dat, f: *FILE) void {
    switch (d.*.type) {
        DStart => emitdat_zero = 0,
        DEnd => {
            if (d.*.lnk.*.common != 0) {
                if (emitdat_zero == -1)
                    die("invalid common data definition", .{});
                const p: [*c]const u8 = if (d.*.name[0] == '"') "" else &all.T.assym;
                _ = C.fprintf(f, ".comm %s%s,%ld", p, d.*.name, @as(c_long, emitdat_zero));
                if (d.*.lnk.*.@"align" != 0)
                    _ = C.fprintf(f, ",%d", @as(c_int, d.*.lnk.*.@"align"));
                _ = C.fputc('\n', f);
            } else if (emitdat_zero != -1) {
                emitlnk(d.*.name, d.*.lnk, SecBss, f);
                _ = C.fprintf(f, "\t.fill %ld,1,0\n", @as(c_long, emitdat_zero));
            }
        },
        DZ => {
            if (emitdat_zero != -1)
                emitdat_zero += d.*.u.num
            else
                _ = C.fprintf(f, "\t.fill %ld,1,0\n", @as(c_long, d.*.u.num));
        },
        else => {
            if (emitdat_zero != -1) {
                emitlnk(d.*.name, d.*.lnk, SecData, f);
                if (emitdat_zero > 0)
                    _ = C.fprintf(f, "\t.fill %ld,1,0\n", @as(c_long, emitdat_zero));
                emitdat_zero = -1;
            }
            if (d.*.isstr != 0) {
                if (d.*.type != DB)
                    err("strings only supported for 'b' currently", .{});
                _ = C.fprintf(f, "\t.ascii %s\n", d.*.u.str);
            } else if (d.*.isref != 0) {
                const p: [*c]const u8 = if (d.*.u.ref.name[0] == '"') "" else &all.T.assym;
                _ = C.fprintf(f, "%s %s%s%+ld\n", di[@intCast(d.*.type)].decl, p, d.*.u.ref.name, @as(c_long, d.*.u.ref.off));
            } else {
                _ = C.fprintf(f, "%s %ld\n", di[@intCast(d.*.type)].decl, @as(c_long, d.*.u.num & di[@intCast(d.*.type)].mask));
            }
        },
    }
}

const Asmbits = extern struct {
    n: bits,
    size: i32,
    link: [*c]Asmbits,
};

var stash: [*c]Asmbits = null;

pub fn stashbits(n: bits, size: i32) i32 {
    assert(size == 4 or size == 8 or size == 16);
    var pb: *[*c]Asmbits = &stash;
    var i: i32 = 0;
    while (pb.* != null) : ({
        pb = &pb.*.*.link;
        i += 1;
    }) {
        const b = pb.*;
        if (size <= b.*.size and b.*.n == n)
            return i;
    }
    const b: [*c]Asmbits = @ptrCast(@alignCast(emalloc(@sizeOf(Asmbits))));
    b.*.n = n;
    b.*.size = size;
    b.*.link = null;
    pb.* = b;
    return i;
}

fn emitfin(f: *FILE, sec: *const [3][*c]const u8) void {
    if (stash == null)
        return;
    _ = C.fprintf(f, "/* floating point constants */\n");
    var lg: i32 = 4;
    while (lg >= 2) : (lg -= 1) {
        var b = stash;
        var i: i32 = 0;
        while (b != null) : ({
            b = b.*.link;
            i += 1;
        }) {
            if (b.*.size == (@as(i32, 1) << @intCast(lg))) {
                _ = C.fprintf(f, ".section %s\n" ++
                    ".p2align %d\n" ++
                    "%sfp%d:", sec[@intCast(lg - 2)], @as(c_int, lg), &all.T.asloc, @as(c_int, i));
                if (lg == 4) {
                    _ = C.fprintf(f, "\n\t.quad %ld" ++
                        "\n\t.quad 0\n\n", @as(c_long, @bitCast(b.*.n)));
                } else if (lg == 3) {
                    const ui: i64 = @bitCast(b.*.n);
                    const uf: f64 = @bitCast(b.*.n);
                    _ = C.fprintf(f, "\n\t.quad %ld" ++
                        " /* %f */\n\n", @as(c_long, ui), uf);
                } else if (lg == 2) {
                    const ui: i32 = @bitCast(@as(u32, @truncate(b.*.n)));
                    const uf: f32 = @bitCast(@as(u32, @truncate(b.*.n)));
                    _ = C.fprintf(f, "\n\t.int %d" ++
                        " /* %f */\n\n", @as(c_int, ui), @as(f64, uf));
                }
            }
        }
    }
    while (stash != null) {
        const b = stash;
        stash = b.*.link;
        C.free(@ptrCast(b));
    }
}

pub fn elf_emitfin(f: *FILE) void {
    const sec = [3][*c]const u8{ ".rodata", ".rodata", ".rodata" };

    emitfin(f, &sec);
    _ = C.fprintf(f, ".section .note.GNU-stack,\"\",@progbits\n");
}

pub fn elf_emitfnfin(fname: [*c]u8, f: *FILE) void {
    _ = C.fprintf(f, ".type %s, @function\n", fname);
    _ = C.fprintf(f, ".size %s, .-%s\n", fname, fname);
}

pub fn macho_emitfin(f: *FILE) void {
    const sec = [3][*c]const u8{
        "__TEXT,__literal4,4byte_literals",
        "__TEXT,__literal8,8byte_literals",
        "__TEXT,__literal16,16byte_literals",
    };

    emitfin(f, &sec);
}

pub fn pe_emitfin(f: *FILE) void {
    const sec = [3][*c]const u8{ ".rodata", ".rodata", ".rodata" };

    emitfin(f, &sec);
}

var file: [*c]u32 = null;
var nfile: uint = 0;
var curfile: uint = 0;

pub fn emitdbgfile(fname: [*c]u8, f: *FILE) void {
    const id = intern(fname);
    var n: uint = 0;
    while (n < nfile) : (n += 1) {
        if (file[n] == id) {
            // gas requires positive
            // file numbers
            curfile = n + 1;
            return;
        }
    }
    if (file == null)
        file = vnewT(u32, 0, PHeap);
    nfile += 1;
    vgrow(&file, nfile);
    file[nfile - 1] = id;
    curfile = nfile;
    _ = C.fprintf(f, ".file %u %s\n", @as(c_uint, curfile), fname);
}

pub fn emitdbgloc(line: uint, col: uint, f: *FILE) void {
    if (col != 0)
        _ = C.fprintf(f, "\t.loc %u %u %u\n", @as(c_uint, curfile), @as(c_uint, line), @as(c_uint, col))
    else
        _ = C.fprintf(f, "\t.loc %u %u\n", @as(c_uint, curfile), @as(c_uint, line));
}
