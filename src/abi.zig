//! One-to-one translation of abi.c
// -- imports --
const all = @import("all.zig");
const J = all.J;
const Blk = all.Blk;
const Fn = all.Fn;
const isargbh = all.isargbh;
const isparbh = all.isparbh;
const isretbh = all.isretbh;
// -- end imports --

/// eliminate sub-word abi op
/// variants for targets that
/// treat char/short/... as
/// words with arbitrary high
/// bits
pub fn elimsb(f: *Fn) void {
    var b_it: ?*Blk = f.start;
    while (b_it) |b| : (b_it = b.link) {
        for (b.ins[0..b.nins]) |*i| {
            if (isargbh(i.op))
                i.op = .arg;
            if (isparbh(i.op))
                i.op = .par;
        }
        if (isretbh(b.jmp.type))
            b.jmp.type = .retw;
    }
}
