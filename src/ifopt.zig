//! One-to-one translation of ifopt.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const Blk = all.Blk;
const Fn = all.Fn;
const INS = all.INS;
const INS0 = all.INS0;
const Ins = all.Ins;
const Jjmp = all.Jjmp;
const KBASE = all.KBASE;
const Kw = all.Kw;
const Odbgloc = all.ops.Odbgloc;
const Onop = all.ops.Onop;
const Osel0 = all.ops.Osel0;
const Osel1 = all.ops.Osel1;
const PHeap = all.PHeap;
const Phi = all.Phi;
const R = all.R;
const addbins = all.addbins;
const addins = all.addins;
const cs = all.cs;
const dprint = all.dprint;
const idup = all.idup;
const ifgraph = all.ifgraph;
const phiarg = all.phiarg;
const pinned = all.pinned;
const printfn = all.printfn;
const uint = all.uint;
const vfree = all.vfree;
const vnewT = all.vnewT;
// -- end imports --

const MaxIns = 2;
const MaxPhis = 2;

fn okbranch(b: *Blk) bool {
    var n: i32 = 0;
    for (b.ins[0..b.nins]) |*i| {
        if (i.op != Odbgloc) {
            if (pinned(i))
                return false;
            if (i.op != Onop)
                n += 1;
        }
    }
    return n <= MaxIns;
}

fn okjoin(b: *Blk) bool {
    var n: i32 = 0;
    var p_it: ?*Phi = b.phi;
    while (p_it) |p| : (p_it = p.link) {
        if (KBASE(p.cls) != 0)
            return false;
        n += 1;
    }
    return n <= MaxPhis;
}

fn okgraph(ifb: [*c]Blk, thenb: [*c]Blk, elseb: [*c]Blk, joinb: *Blk) bool {
    if (joinb.npred != 2 or !okjoin(joinb))
        return false;
    assert(thenb != elseb);
    if (thenb != ifb and !okbranch(thenb))
        return false;
    if (elseb != ifb and !okbranch(elseb))
        return false;
    return true;
}

fn convert(ifb: [*c]Blk, thenb: [*c]Blk, elseb: [*c]Blk, joinb: *Blk) void {
    var ins = vnewT(Ins, 0, PHeap);
    var nins: uint = 0;
    addbins(&ins, &nins, ifb);
    if (thenb != ifb)
        addbins(&ins, &nins, thenb);
    if (elseb != ifb)
        addbins(&ins, &nins, elseb);
    assert(joinb.npred == 2);
    var sel: Ins = undefined;
    if (joinb.phi != null) {
        sel = INS(Osel0, Kw, R, ifb.*.jmp.arg, R);
        addins(&ins, &nins, &sel);
    }
    sel = INS0(Osel1);
    var p_it: ?*Phi = joinb.phi;
    while (p_it) |p| : (p_it = p.link) {
        sel.to = p.to;
        sel.cls = @intCast(p.cls);
        sel.arg[0] = phiarg(p, thenb);
        sel.arg[1] = phiarg(p, elseb);
        addins(&ins, &nins, &sel);
    }
    idup(ifb, ins, nins);
    ifb.*.jmp.type = Jjmp;
    ifb.*.jmp.arg = R;
    ifb.*.s1 = joinb;
    ifb.*.s2 = null;
    joinb.npred = 1;
    joinb.pred[0] = ifb;
    joinb.phi = null;
    vfree(@ptrCast(ins));
}

/// eliminate if-then[-else] graphlets
/// using sel instructions
/// needs rpo pred use; breaks cfg use
pub fn ifconvert(f: *Fn) void {
    var thenb: [*c]Blk = undefined;
    var elseb: [*c]Blk = undefined;
    var joinb: [*c]Blk = undefined;

    if (all.debug['K'] != 0)
        dprint("\n> If-conversion:\n", .{});

    var ifb_it: ?*Blk = f.start;
    while (ifb_it) |ifb| : (ifb_it = ifb.link) {
        if (ifgraph(ifb, &thenb, &elseb, &joinb))
            if (okgraph(ifb, thenb, elseb, joinb)) {
                if (all.debug['K'] != 0)
                    dprint("    @{s} -> @{s}, @{s} -> @{s}\n", .{cs(ifb.name), cs(thenb.*.name), cs(elseb.*.name), cs(joinb.*.name)});
                convert(ifb, thenb, elseb, joinb);
            };
    }

    if (all.debug['K'] != 0) {
        dprint("\n> After if-conversion:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
