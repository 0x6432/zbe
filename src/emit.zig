//! One-to-one translation of emit.c
const std = @import("std");
const assert = std.debug.assert;
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
const Lnk = all.Lnk;
const PHeap = all.PHeap;
const Writer = all.Writer;
const bits = all.bits;
const cfloat = all.cfloat;
const cs = all.cs;
const die = all.die;
const efree = all.efree;
const enew = all.enew;
const fail = all.fail;
const intern = all.intern;
const uint = all.uint;
const vgrow = all.vgrow;
const vnewT = all.vnewT;
// -- end imports --

const SecText = 0;
const SecData = 1;
const SecBss = 2;

const lnk_sec = [2][3][*:0]const u8{
    .{ ".text", ".data", ".bss" },
    .{ ".abort \"unreachable\"", ".section .tdata,\"awT\"", ".section .tbss,\"awT\"" },
};

pub fn emitlnk(n: [*:0]const u8, l: *Lnk, s: i32, f: *Writer) Writer.Error!void {
    const pfx: [*:0]const u8 = if (n[0] == '"') "" else @ptrCast(&all.T.assym);
    var sfx: [*:0]const u8 = "";
    if (all.T.apple != 0 and l.thread != 0) {
        l.sec = @constCast("__DATA");
        l.secf = @constCast("__thread_data,thread_local_regular");
        sfx = "$tlv$init";
        try f.writeAll(".section __DATA,__thread_vars," ++
            "thread_local_variables\n");
        try f.print("{s}{s}:\n", .{cs(pfx), cs(n)});
        try f.print("\t.quad __tlv_bootstrap\n" ++ "\t.quad 0\n" ++ "\t.quad {s}{s}{s}\n\n", .{cs(pfx), cs(n), cs(sfx)});
    }
    if (l.sec != null) {
        try f.print(".section {s}", .{cs(l.sec)});
        if (l.secf != null)
            try f.print(",{s}", .{cs(l.secf)});
    } else try f.writeAll(cs(lnk_sec[@intFromBool(l.thread != 0)][@intCast(s)]));
    try f.writeByte('\n');
    if (l.@"align" != 0)
        try f.print(".balign {d}\n", .{l.@"align"});
    if (l.@"export" != 0)
        try f.print(".globl {s}{s}\n", .{cs(pfx), cs(n)});
    try f.print("{s}{s}{s}:\n", .{cs(pfx), cs(n), cs(sfx)});
}

pub fn emitfnlnk(n: [*:0]const u8, l: *Lnk, f: *Writer) Writer.Error!void {
    try emitlnk(n, l, SecText, f);
}

const DatInfo = struct {
    decl: [*:0]const u8,
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
/// Data and debug-info emitter state.
const State = struct {
    emitdat_zero: i64 = 0,
    stash: ?*Asmbits = null,
    file: ?[*]u32 = null, // vector of interned file names
    nfile: uint = 0,
    curfile: uint = 0,
};
var st: State = .{};

pub fn emitdat(d: *Dat, f: *Writer) (Writer.Error || all.Error)!void {
    switch (d.type) {
        DStart => st.emitdat_zero = 0,
        DEnd => {
            if (d.lnk.?.common != 0) {
                if (st.emitdat_zero == -1)
                    die("invalid common data definition", .{});
                const p: [*:0]const u8 = if (d.name.?[0] == '"') "" else @ptrCast(&all.T.assym);
                try f.print(".comm {s}{s},{d}", .{cs(p), cs(d.name), st.emitdat_zero});
                if (d.lnk.?.@"align" != 0)
                    try f.print(",{d}", .{d.lnk.?.@"align"});
                try f.writeByte('\n');
            } else if (st.emitdat_zero != -1) {
                try emitlnk(d.name.?, d.lnk.?, SecBss, f);
                try f.print("\t.fill {d},1,0\n", .{st.emitdat_zero});
            }
        },
        DZ => {
            if (st.emitdat_zero != -1)
                st.emitdat_zero += d.u.num
            else
                try f.print("\t.fill {d},1,0\n", .{d.u.num});
        },
        else => {
            if (st.emitdat_zero != -1) {
                try emitlnk(d.name.?, d.lnk.?, SecData, f);
                if (st.emitdat_zero > 0)
                    try f.print("\t.fill {d},1,0\n", .{st.emitdat_zero});
                st.emitdat_zero = -1;
            }
            if (d.isstr != 0) {
                if (d.type != DB)
                    return fail("strings only supported for 'b' currently", .{});
                try f.print("\t.ascii {s}\n", .{cs(d.u.str)});
            } else if (d.isref != 0) {
                const p: [*:0]const u8 = if (d.u.ref.name.?[0] == '"') "" else @ptrCast(&all.T.assym);
                try f.print("{s} {s}{s}{d:1}\n", .{cs(di[@intCast(d.type)].decl), cs(p), cs(d.u.ref.name), d.u.ref.off});
            } else {
                try f.print("{s} {d}\n", .{cs(di[@intCast(d.type)].decl), d.u.num & di[@intCast(d.type)].mask});
            }
        },
    }
}

const Asmbits = extern struct {
    n: bits,
    size: i32,
    link: ?*Asmbits,
};


pub fn stashbits(n: bits, size: i32) i32 {
    assert(size == 4 or size == 8 or size == 16);
    var pb: *?*Asmbits = &st.stash;
    var i: i32 = 0;
    while (pb.*) |b| : ({
        pb = &b.link;
        i += 1;
    }) {
        if (size <= b.size and b.n == n)
            return i;
    }
    const b = enew(Asmbits);
    b.n = n;
    b.size = size;
    b.link = null;
    pb.* = b;
    return i;
}

fn emitfin(f: *Writer, sec: *const [3][*:0]const u8) Writer.Error!void {
    if (st.stash == null)
        return;
    try f.print("/* floating point constants */\n", .{});
    var lg: i32 = 4;
    while (lg >= 2) : (lg -= 1) {
        var b_it = st.stash;
        var i: i32 = 0;
        while (b_it) |b| : ({
            b_it = b.link;
            i += 1;
        }) {
            if (b.size == (@as(i32, 1) << @intCast(lg))) {
                try f.print(".section {s}\n" ++ ".p2align {d}\n" ++ "{s}fp{d}:", .{cs(sec[@intCast(lg - 2)]), lg, cs(&all.T.asloc), i});
                if (lg == 4) {
                    try f.print("\n\t.quad {d}" ++ "\n\t.quad 0\n\n", .{@as(i64, @bitCast(b.n))});
                } else if (lg == 3) {
                    const ui: i64 = @bitCast(b.n);
                    const uf: f64 = @bitCast(b.n);
                    try f.print("\n\t.quad {d}" ++ " /* {f} */\n\n", .{ ui, cfloat(uf) });
                } else if (lg == 2) {
                    const ui: i32 = @bitCast(@as(u32, @truncate(b.n)));
                    const uf: f32 = @bitCast(@as(u32, @truncate(b.n)));
                    try f.print("\n\t.int {d}" ++ " /* {f} */\n\n", .{ ui, cfloat(uf) });
                }
            }
        }
    }
    while (st.stash) |b| {
        st.stash = b.link;
        efree((b));
    }
}

pub fn elf_emitfin(f: *Writer) Writer.Error!void {
    const sec = [3][*:0]const u8{ ".rodata", ".rodata", ".rodata" };

    try emitfin(f, &sec);
    try f.print(".section .note.GNU-stack,\"\",@progbits\n", .{});
}

pub fn elf_emitfnfin(fname: [*:0]const u8, f: *Writer) Writer.Error!void {
    try f.print(".type {s}, @function\n", .{cs(fname)});
    try f.print(".size {s}, .-{s}\n", .{cs(fname), cs(fname)});
}

pub fn macho_emitfin(f: *Writer) Writer.Error!void {
    const sec = [3][*:0]const u8{
        "__TEXT,__literal4,4byte_literals",
        "__TEXT,__literal8,8byte_literals",
        "__TEXT,__literal16,16byte_literals",
    };

    try emitfin(f, &sec);
}

pub fn pe_emitfin(f: *Writer) Writer.Error!void {
    const sec = [3][*:0]const u8{ ".rodata", ".rodata", ".rodata" };

    try emitfin(f, &sec);
}


pub fn emitdbgfile(fname: [*:0]const u8, f: *Writer) Writer.Error!void {
    const id = intern(fname);
    var n: uint = 0;
    while (n < st.nfile) : (n += 1) {
        if (st.file.?[n] == id) {
            // gas requires positive
            // file numbers
            st.curfile = n + 1;
            return;
        }
    }
    if (st.file == null)
        st.file = vnewT(u32, 0, PHeap);
    st.nfile += 1;
    vgrow(&st.file, st.nfile);
    st.file.?[st.nfile - 1] = id;
    st.curfile = st.nfile;
    try f.print(".file {d} {s}\n", .{st.curfile, cs(fname)});
}

pub fn emitdbgloc(line: uint, col: uint, f: *Writer) Writer.Error!void {
    if (col != 0)
        try f.print("\t.loc {d} {d} {d}\n", .{st.curfile, line, col})
    else
        try f.print("\t.loc {d} {d}\n", .{st.curfile, line});
}
