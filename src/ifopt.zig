//! One-to-one translation of ifopt.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("all.zig");
const Cls = all.Cls;
const J = all.J;
const Blk = all.Blk;
const Fn = all.Fn;
const mkIns = all.mkIns;
const insOp = all.insOp;
const Ins = all.Ins;
const clsBase = all.clsBase;
const PHeap = all.PHeap;
const Phi = all.Phi;
const R = all.R;
const appendInsSlice = all.appendInsSlice;
const appendIns = all.appendIns;
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
    for (b.insns()) |*i| {
        if (i.op != .dbgloc) {
            if (pinned(i))
                return false;
            if (i.op != .nop)
                n += 1;
        }
    }
    return n <= MaxIns;
}

fn okjoin(b: *Blk) bool {
    var n: i32 = 0;
    var p_it: ?*Phi = b.phi;
    while (p_it) |p| : (p_it = p.link) {
        if (clsBase(p.cls) != 0)
            return false;
        n += 1;
    }
    return n <= MaxPhis;
}

fn okgraph(ifb: *Blk, thenb: *Blk, elseb: *Blk, joinb: *Blk) bool {
    if (joinb.npred != 2 or !okjoin(joinb))
        return false;
    assert(thenb != elseb);
    if (thenb != ifb and !okbranch(thenb))
        return false;
    if (elseb != ifb and !okbranch(elseb))
        return false;
    return true;
}

fn convert(ifb: *Blk, thenb: *Blk, elseb: *Blk, joinb: *Blk) void {
    var ins: []Ins = vnewT(Ins, 0, PHeap)[0..0];
    appendInsSlice(&ins, ifb.insns());
    if (thenb != ifb)
        appendInsSlice(&ins, thenb.insns());
    if (elseb != ifb)
        appendInsSlice(&ins, elseb.insns());
    assert(joinb.npred == 2);
    var sel: Ins = undefined;
    if (joinb.phi != null) {
        sel = mkIns(.sel0, .w, R, ifb.jmp.arg, R);
        appendIns(&ins, sel);
    }
    sel = insOp(.sel1);
    var p_it: ?*Phi = joinb.phi;
    while (p_it) |p| : (p_it = p.link) {
        sel.to = p.to;
        sel.cls = p.cls;
        sel.arg[0] = phiarg(p, thenb);
        sel.arg[1] = phiarg(p, elseb);
        appendIns(&ins, sel);
    }
    idup(ifb, ins);
    ifb.jmp.type = .jmp;
    ifb.jmp.arg = R;
    ifb.s1 = joinb;
    ifb.s2 = null;
    joinb.npred = 1;
    joinb.pred[0] = ifb;
    joinb.phi = null;
    vfree(ins.ptr);
}

/// eliminate if-then[-else] graphlets
/// using sel instructions
/// needs rpo pred use; breaks cfg use
pub fn ifconvert(f: *Fn) void {
    var thenb: *Blk = undefined;
    var elseb: *Blk = undefined;
    var joinb: *Blk = undefined;

    if (all.debug['K'] != 0)
        dprint("\n> If-conversion:\n", .{});

    var ifb_it: ?*Blk = f.start;
    while (ifb_it) |ifb| : (ifb_it = ifb.link) {
        if (ifgraph(ifb, &thenb, &elseb, &joinb))
            if (okgraph(ifb, thenb, elseb, joinb)) {
                if (all.debug['K'] != 0)
                    dprint("    @{s} -> @{s}, @{s} -> @{s}\n", .{cs(ifb.name), cs(thenb.name), cs(elseb.name), cs(joinb.name)});
                convert(ifb, thenb, elseb, joinb);
            };
    }

    if (all.debug['K'] != 0) {
        dprint("\n> After if-conversion:\n", .{});
        printfn(f, all.dbg) catch {};
    }
}
