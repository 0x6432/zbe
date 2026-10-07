//! One-to-one translation of abi.c
// -- imports --
const all = @import("all.zig");
const Fn = all.Fn;
const Jretw = all.Jretw;
const Oarg = all.ops.Oarg;
const Opar = all.ops.Opar;
const isargbh = all.isargbh;
const isparbh = all.isparbh;
const isretbh = all.isretbh;
// -- end imports --

/// eliminate sub-word abi op
/// variants for targets that
/// treat char/short/... as
/// words with arbitrary high
/// bits
pub fn elimsb(f: [*c]Fn) void {
    var b = f.*.start;
    while (b != null) : (b = b.*.link) {
        var i = b.*.ins;
        while (i < &b.*.ins[b.*.nins]) : (i += 1) {
            if (isargbh(i.*.op))
                i.*.op = Oarg;
            if (isparbh(i.*.op))
                i.*.op = Opar;
        }
        if (isretbh(b.*.jmp.type))
            b.*.jmp.type = Jretw;
    }
}
