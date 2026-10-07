//! One-to-one translation of QBE's all.h: core types, constants and
//! the cross-module "prototype" list (re-exports).
const std = @import("std");
pub const libc = @import("libc.zig");
pub const ops = @import("ops.zig");

pub const FILE = libc.FILE;
pub const uchar = u8;
pub const uint = u32;
pub const ulong = u64;
pub const bits = u64;

pub const NIns = 1 << 20;
pub const NAlign = 3;
pub const NField = 32;
pub const NBit = 64;

pub const Target = struct {
    name: [16]u8,
    apple: i8,
    windows: i8,
    gpr0: i32, // first general purpose reg
    ngpr: i32,
    fpr0: i32, // first floating point reg
    nfpr: i32,
    rglob: bits, // globally live regs (e.g., sp, fp)
    nrglob: i32,
    rsave: [*c]i32, // caller-save
    nrsave: [2]i32,
    retregs: *const fn (Ref, [*c]i32) bits,
    argregs: *const fn (Ref, [*c]i32) bits,
    memargs: *const fn (i32) i32,
    abi0: *const fn ([*c]Fn) void,
    abi1: *const fn ([*c]Fn) void,
    isel: *const fn ([*c]Fn) void,
    emitfn: *const fn ([*c]Fn, *FILE) void,
    emitfin: *const fn (*FILE) void,
    asloc: [4]u8,
    assym: [4]u8,
    cansel: u1,
};

pub inline fn BIT(n: anytype) bits {
    return @as(bits, 1) << @intCast(n);
}

pub const RXX = 0;
pub const Tmp0 = NBit; // first non-reg temporary

pub const BSet = extern struct {
    nt: uint,
    t: [*c]bits,
};

pub const Ref = packed struct(u32) {
    type: u3,
    val: u29,
};

pub const RTmp = 0;
pub const RCon = 1;
pub const RInt = 2;
pub const RType = 3; // last kind to come out of the parser
pub const RSlot = 4;
pub const RCall = 5;
pub const RMem = 6;

pub const R = Ref{ .type = RTmp, .val = 0 };
pub const UNDEF = Ref{ .type = RCon, .val = 0 }; // represents uninitialized data
pub const CON_Z = Ref{ .type = RCon, .val = 1 };
pub inline fn TMP(x: anytype) Ref {
    return .{ .type = RTmp, .val = @intCast(x) };
}
pub inline fn CON(x: anytype) Ref {
    return .{ .type = RCon, .val = @intCast(x) };
}
pub inline fn SLOT(x: anytype) Ref {
    return .{ .type = RSlot, .val = @truncate(@as(u64, @bitCast(@as(i64, x))) & 0x1fffffff) };
}
pub inline fn TYPE(x: anytype) Ref {
    return .{ .type = RType, .val = @intCast(x) };
}
pub inline fn CALL(x: anytype) Ref {
    return .{ .type = RCall, .val = @intCast(x) };
}
pub inline fn MEM(x: anytype) Ref {
    return .{ .type = RMem, .val = @intCast(x) };
}
pub inline fn INT(x: anytype) Ref {
    return .{ .type = RInt, .val = @truncate(@as(u64, @bitCast(@as(i64, x))) & 0x1fffffff) };
}

pub inline fn req(a: Ref, b: Ref) bool {
    return a.type == b.type and a.val == b.val;
}

pub inline fn rtype(r: Ref) i32 {
    if (req(r, R))
        return -1;
    return r.type;
}

pub inline fn rsval(r: Ref) i32 {
    return (@as(i32, @intCast(r.val)) ^ 0x10000000) - 0x10000000;
}

// enum CmpI
pub const Cieq = 0;
pub const Cine = 1;
pub const Cisge = 2;
pub const Cisgt = 3;
pub const Cisle = 4;
pub const Cislt = 5;
pub const Ciuge = 6;
pub const Ciugt = 7;
pub const Ciule = 8;
pub const Ciult = 9;
pub const NCmpI = 10;

// enum CmpF
pub const Cfeq = 0;
pub const Cfge = 1;
pub const Cfgt = 2;
pub const Cfle = 3;
pub const Cflt = 4;
pub const Cfne = 5;
pub const Cfo = 6;
pub const Cfuo = 7;
pub const NCmpF = 8;
pub const NCmp = NCmpI + NCmpF;

// enum O (generated from ops.h)
pub const Oxxx = ops.Oxxx;
pub const NOp = ops.NOp;

// enum J
pub const Jxxx = 0;
pub const Jretw = 1;
pub const Jretl = 2;
pub const Jrets = 3;
pub const Jretd = 4;
pub const Jretsb = 5;
pub const Jretub = 6;
pub const Jretsh = 7;
pub const Jretuh = 8;
pub const Jretc = 9;
pub const Jret0 = 10;
pub const Jjmp = 11;
pub const Jjnz = 12;
pub const Jjfieq = 13;
pub const Jjfine = 14;
pub const Jjfisge = 15;
pub const Jjfisgt = 16;
pub const Jjfisle = 17;
pub const Jjfislt = 18;
pub const Jjfiuge = 19;
pub const Jjfiugt = 20;
pub const Jjfiule = 21;
pub const Jjfiult = 22;
pub const Jjffeq = 23;
pub const Jjffge = 24;
pub const Jjffgt = 25;
pub const Jjffle = 26;
pub const Jjfflt = 27;
pub const Jjffne = 28;
pub const Jjffo = 29;
pub const Jjffuo = 30;
pub const Jhlt = 31;
pub const NJmp = 32;
pub const jmp_names = [_][:0]const u8{ "retw", "retl", "rets", "retd", "retsb", "retub", "retsh", "retuh", "retc", "ret0", "jmp", "jnz", "jfieq", "jfine", "jfisge", "jfisgt", "jfisle", "jfislt", "jfiuge", "jfiugt", "jfiule", "jfiult", "jffeq", "jffge", "jffgt", "jffle", "jfflt", "jffne", "jffo", "jffuo", "hlt" };

const O = ops;
pub const Ocmpw = O.Oceqw;
pub const Ocmpw1 = O.Ocultw;
pub const Ocmpl = O.Oceql;
pub const Ocmpl1 = O.Ocultl;
pub const Ocmps = O.Oceqs;
pub const Ocmps1 = O.Ocuos;
pub const Ocmpd = O.Oceqd;
pub const Ocmpd1 = O.Ocuod;
pub const Oalloc = O.Oalloc4;
pub const Oalloc1 = O.Oalloc16;
pub const Oflag = O.Oflagieq;
pub const Oflag1 = O.Oflagfuo;
pub const Oxsel = O.Oxselieq;
pub const Oxsel1 = O.Oxselfuo;
pub const NPubOp = O.Onop;
pub const Jjf = Jjfieq;
pub const Jjf1 = Jjffuo;

/// linear in x
pub inline fn INRANGE(x: anytype, comptime l: comptime_int, comptime u: comptime_int) bool {
    return @as(u32, @bitCast(@as(i32, @intCast(x)) -% l)) <= u - l;
}
pub inline fn isstore(o: anytype) bool {
    return INRANGE(o, O.Ostoreb, O.Ostored);
}
pub inline fn isload(o: anytype) bool {
    return INRANGE(o, O.Oloadsb, O.Oload);
}
pub inline fn isalloc(o: anytype) bool {
    return INRANGE(o, O.Oalloc4, O.Oalloc16);
}
pub inline fn isext(o: anytype) bool {
    return INRANGE(o, O.Oextsb, O.Oextuw);
}
pub inline fn ispar(o: anytype) bool {
    return INRANGE(o, O.Opar, O.Opare);
}
pub inline fn isarg(o: anytype) bool {
    return INRANGE(o, O.Oarg, O.Oargv);
}
pub inline fn isret(j: anytype) bool {
    return INRANGE(j, Jretw, Jret0);
}
pub inline fn isparbh(o: anytype) bool {
    return INRANGE(o, O.Oparsb, O.Oparuh);
}
pub inline fn isargbh(o: anytype) bool {
    return INRANGE(o, O.Oargsb, O.Oarguh);
}
pub inline fn isretbh(j: anytype) bool {
    return INRANGE(j, Jretsb, Jretuh);
}
pub inline fn isxsel(o: anytype) bool {
    return INRANGE(o, Oxsel, Oxsel1);
}

pub const Kx = -1; // "top" class (see usecheck() and clsmerge())
pub const Kw = 0;
pub const Kl = 1;
pub const Ks = 2;
pub const Kd = 3;

pub inline fn KWIDE(k: anytype) i32 {
    return @as(i32, @intCast(k)) & 1;
}
pub inline fn KBASE(k: anytype) i32 {
    return @as(i32, @intCast(k)) >> 1;
}

pub const Op = struct {
    name: [*c]const u8,
    argcls: [2][4]i16,
    canfold: u1,
    hasid: u1, // op identity value?
    idval: u1, // identity value 0/1
    commutes: u1, // commutative op?
    assoc: u1, // associative op?
    idemp: u1, // idempotent op?
    cmpeqwl: u1, // Kl/Kw cmp eq/ne?
    cmplgtewl: u1, // Kl/Kw cmp lt/gt/le/ge?
    eqval: u1, // 1 for eq; 0 for ne
    pinned: u1, // GCM pinned op?
};

pub const Ins = extern struct {
    op: u32, // C: uint op:30
    cls: u32, // C: uint cls:2
    to: Ref,
    arg: [2]Ref,
};

pub const Phi = extern struct {
    to: Ref,
    cls: i16,
    visit: i32,
    narg: uint,
    arg: [*c]Ref,
    blk: [*c][*c]Blk,
    link: [*c]Phi,
};

pub const Blk = extern struct {
    phi: [*c]Phi,
    ins: [*c]Ins,
    nins: uint,
    jmp: extern struct {
        type: i16,
        arg: Ref,
    },
    s1: [*c]Blk,
    s2: [*c]Blk,
    link: [*c]Blk,

    id: uint,
    visit: uint,

    idom: [*c]Blk,
    dom: [*c]Blk,
    dlink: [*c]Blk,
    fron: [*c][*c]Blk,
    nfron: uint,
    depth: i32,

    pred: [*c][*c]Blk,
    npred: uint,
    in: [1]BSet,
    out: [1]BSet,
    gen: [1]BSet,
    nlive: [2]i32,
    loop: i32,
    name: [*c]u8,
};

pub const UXXX = 0;
pub const UPhi = 1;
pub const UIns = 2;
pub const UJmp = 3;

pub const Use = extern struct {
    type: i32,
    bid: uint,
    u: extern union {
        ins: [*c]Ins,
        phi: [*c]Phi,
    },
};

pub const SGlo = 0; // direct access
pub const SThr = 1; // local-exec TLS
pub const SExt = 2; // GOT/PLT access
pub const SExtThr = SExt | SThr; // initial-exec TLS

pub const Sym = extern struct {
    type: i32,
    id: u32,
};

pub const Num = extern struct {
    n: uchar,
    nl: uchar,
    nr: uchar,
    l: Ref,
    r: Ref,
};

pub const NoAlias = 0;
pub const MayAlias = 1;
pub const MustAlias = 2;

pub const ABot = 0;
pub const ALoc = 1; // stack local
pub const ACon = 2;
pub const AEsc = 3; // stack escaping
pub const ASym = 4;
pub const AUnk = 6;
pub inline fn astack(t: anytype) i32 {
    return @as(i32, @intCast(t)) & 1;
}

pub const Alias = extern struct {
    type: i32,
    base: i32,
    offset: i64,
    u: extern union {
        sym: Sym,
        loc: extern struct {
            sz: i32, // -1 if > NBit
            m: bits,
        },
    },
    slot: [*c]Alias,
};

pub const WFull = 0;
pub const Wsb = 1; // must match Oload/Oext order
pub const Wub = 2;
pub const Wsh = 3;
pub const Wuh = 4;
pub const Wsw = 5;
pub const Wuw = 6;

pub const Tmp = extern struct {
    name: [*c]u8,
    def: [*c]Ins,
    use: [*c]Use,
    ndef: uint,
    nuse: uint,
    bid: uint, // id of a defining block
    cost: uint,
    slot: i32, // -1 for unset
    cls: i16,
    hint: extern struct {
        r: i32, // register or -1
        w: i32, // weight
        m: bits, // avoid these registers
    },
    phi: i32,
    alias: Alias,
    width: i32,
    visit: i32,
    gcmbid: uint,
};

pub const CUndef = 0;
pub const CBits = 1;
pub const CAddr = 2;

pub const Con = extern struct {
    type: i32,
    sym: Sym,
    bits: extern union {
        i: i64,
        d: f64,
        s: f32,
    },
    flt: i8, // 1 to print as s, 2 to print as d
};

pub const Addr = extern struct { // amd64 addressing
    offset: Con,
    base: Ref,
    index: Ref,
    scale: i32,
};
pub const Mem = Addr;

pub const Lnk = extern struct {
    @"export": i8,
    thread: i8,
    common: i8,
    @"align": i8,
    sec: [*c]u8,
    secf: [*c]u8,
};

pub const Fn = extern struct {
    start: [*c]Blk,
    tmp: [*c]Tmp,
    con: [*c]Con,
    mem: [*c]Mem,
    ntmp: i32,
    ncon: i32,
    nmem: i32,
    nblk: uint,
    retty: i32, // index in typ[], -1 if no aggregate return
    retr: Ref,
    rpo: [*c][*c]Blk,
    reg: bits,
    slot: i32,
    salign: i32,
    vararg: i8,
    dynalloc: i8,
    leaf: i8,
    name: [*c]u8,
    lnk: Lnk,
};

pub const FEnd = 0;
pub const Fb = 1;
pub const Fh = 2;
pub const Fw = 3;
pub const Fl = 4;
pub const Fs = 5;
pub const Fd = 6;
pub const FPad = 7;
pub const FTyp = 8;

pub const Field = extern struct {
    type: i32,
    len: uint, // or index in typ[] for FTyp
};

pub const Typ = extern struct {
    name: [*c]u8,
    isdark: i8,
    isunion: i8,
    @"align": i32,
    size: u64,
    nunion: uint,
    fields: [*c][NField + 1]Field,
};

pub const DStart = 0;
pub const DEnd = 1;
pub const DB = 2;
pub const DH = 3;
pub const DW = 4;
pub const DL = 5;
pub const DZ = 6;

pub const Dat = extern struct {
    type: i32,
    name: [*c]u8,
    lnk: [*c]Lnk,
    u: extern union {
        num: i64,
        fltd: f64,
        flts: f32,
        str: [*c]u8,
        ref: extern struct {
            name: [*c]u8,
            off: i64,
        },
    },
    isref: i8,
    isstr: i8,
};

// main.c
pub const main_ = @import("main.zig");
pub var T: Target = undefined;
pub var debug: ['Z' + 1]u8 = [_]u8{0} ** ('Z' + 1);

// util.c
pub const PHeap = 0; // free() necessary
pub const PFn = 1; // discarded after processing the function
pub const Pool = i32;

pub const util = @import("util.zig");
pub var typ: [*c]Typ = null;
pub var insb: [NIns]Ins = undefined;
pub var curi: [*c]Ins = null;
pub const hash = util.hash;
pub const die_ = util.die_;
pub const emalloc = util.emalloc;
pub const alloc = util.alloc;
pub const freeall = util.freeall;
pub const vnew = util.vnew;
pub const vfree = util.vfree;
pub const vgrow = util.vgrow;
pub const addins = util.addins;
pub const addbins = util.addbins;
pub const strf = util.strf;
pub const intern = util.intern;
pub const str = util.str;
pub const argcls = util.argcls;
pub const isreg = util.isreg;
pub const iscmp = util.iscmp;
pub const igroup = util.igroup;
pub const emit = util.emit;
pub const emiti = util.emiti;
pub const idup = util.idup;
pub const icpy = util.icpy;
pub const cmpop = util.cmpop;
pub const cmpwlneg = util.cmpwlneg;
pub const clsmerge = util.clsmerge;
pub const phicls = util.phicls;
pub const phiargn = util.phiargn;
pub const phiarg = util.phiarg;
pub const newtmp = util.newtmp;
pub const chuse = util.chuse;
pub const symeq = util.symeq;
pub const newcon = util.newcon;
pub const getcon = util.getcon;
pub const addcon = util.addcon;
pub const isconbits = util.isconbits;
pub const salloc = util.salloc;
pub const dumpts = util.dumpts;
pub const runmatch = util.runmatch;
pub const bsinit = util.bsinit;
pub const bszero = util.bszero;
pub const bscount = util.bscount;
pub const bsset = util.bsset;
pub const bsclr = util.bsclr;
pub const bscopy = util.bscopy;
pub const bsunion = util.bsunion;
pub const bsinter = util.bsinter;
pub const bsdiff = util.bsdiff;
pub const bsequal = util.bsequal;
pub const bsiter = util.bsiter;
pub const die = util.die;
pub const vnewT = util.vnewT;
pub const ptrdiff = util.ptrdiff;

pub inline fn bshas(bs: [*c]BSet, elt: anytype) bool {
    std.debug.assert(elt < bs.*.nt * NBit);
    return (bs.*.t[@intCast(elt / NBit)] & BIT(elt % NBit)) != 0;
}

// parse.c
pub const parse_ = @import("parse.zig");
pub var optab: [NOp]Op = parse_.optab_init;
pub const parse = parse_.parse;
pub const printfn = parse_.printfn;
pub const printref = parse_.printref;
pub const err = parse_.err;

// abi.c
pub const elimsb = @import("abi.zig").elimsb;

// cfg.c
pub const cfg = @import("cfg.zig");
pub const newblk = cfg.newblk;
pub const fillpreds = cfg.fillpreds;
pub const fillcfg = cfg.fillcfg;
pub const filldom = cfg.filldom;
pub const sdom = cfg.sdom;
pub const dom = cfg.dom;
pub const fillfron = cfg.fillfron;
pub const loopiter = cfg.loopiter;
pub const filldepth = cfg.filldepth;
pub const lca = cfg.lca;
pub const fillloop = cfg.fillloop;
pub const simpljmp = cfg.simpljmp;
pub const reaches = cfg.reaches;
pub const reachesnotvia = cfg.reachesnotvia;
pub const ifgraph = cfg.ifgraph;
pub const simplcfg = cfg.simplcfg;

// mem.c
pub const promote = @import("mem.zig").promote;
pub const coalesce = @import("mem.zig").coalesce;

// alias.c
pub const fillalias = @import("alias.zig").fillalias;
pub const getalias = @import("alias.zig").getalias;
pub const alias = @import("alias.zig").alias;
pub const escapes = @import("alias.zig").escapes;

// load.c
pub const loadsz = @import("load.zig").loadsz;
pub const storesz = @import("load.zig").storesz;
pub const loadopt = @import("load.zig").loadopt;

// ssa.c
pub const adduse = @import("ssa.zig").adduse;
pub const filluse = @import("ssa.zig").filluse;
pub const ssa = @import("ssa.zig").ssa;
pub const ssacheck = @import("ssa.zig").ssacheck;

// copy.c
pub const narrowpars = @import("copy.zig").narrowpars;
pub const copyref = @import("copy.zig").copyref;
pub const phicopyref = @import("copy.zig").phicopyref;

// fold.c
pub const foldint = @import("fold.zig").foldint;
pub const foldref = @import("fold.zig").foldref;

// gvn.c
pub const gvn_ = @import("gvn.zig");
pub var con01: [2]Ref = undefined; // 0 and 1
pub const zeroval = gvn_.zeroval;
pub const gvn = gvn_.gvn;

// gcm.c
pub const pinned = @import("gcm.zig").pinned;
pub const gcm = @import("gcm.zig").gcm;

// ifopt.c
pub const ifconvert = @import("ifopt.zig").ifconvert;

// simpl.c
pub const simpl = @import("simpl.zig").simpl;

// live.c
pub const liveon = @import("live.zig").liveon;
pub const filllive = @import("live.zig").filllive;

// spill.c
pub const fillcost = @import("spill.zig").fillcost;
pub const spill = @import("spill.zig").spill;

// rega.c
pub const rega = @import("rega.zig").rega;

// emit.c
pub const emit_ = @import("emit.zig");
pub const emitfnlnk = emit_.emitfnlnk;
pub const emitdat = emit_.emitdat;
pub const emitdbgfile = emit_.emitdbgfile;
pub const emitdbgloc = emit_.emitdbgloc;
pub const stashbits = emit_.stashbits;
pub const elf_emitfnfin = emit_.elf_emitfnfin;
pub const elf_emitfin = emit_.elf_emitfin;
pub const macho_emitfin = emit_.macho_emitfin;
pub const pe_emitfin = emit_.pe_emitfin;
