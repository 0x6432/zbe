# stage 6k: typed vector API (no anyopaque, no esz, typed memcpy)
import re,glob
p='/data/qbe-zig/src/util.zig'
s=open(p).read()
def rep(a,b):
    global s
    assert s.count(a)==1,a[:60]
    s=s.replace(a,b)
rep('''const Vec = extern struct {
    mag: ulong align(16),
    pool: Pool,
    esz: usize,
    cap: ulong,
};''','''/// header stored just before the elements of every vector
const Vec = extern struct {
    mag: ulong align(16),
    pool: Pool,
    cap: ulong,
};''')
start=s.index('pub fn vnew(len: ulong, esz: usize, pl: Pool) ?*anyopaque {')
end=s.index('pub fn addins(')
s=s[:start]+'''/// element type of a vector pointer type ([*]T, [*:0]T or ?[*]T)
fn VElem(comptime P: type) type {
    return switch (@typeInfo(P)) {
        .optional => |o| VElem(o.child),
        .pointer => |ptr| blk: {
            if (ptr.size != .many) @compileError("vector must be a many-pointer");
            break :blk ptr.child;
        },
        else => @compileError("vector must be a many-pointer"),
    };
}

fn vhdr(p: anytype) *Vec {
    const v: [*]Vec = @ptrCast(@alignCast(@constCast(p)));
    const h = &(v - 1)[0];
    assert(h.mag == VMag);
    return h;
}

/// new growable array of at least len T's in pool pl (C: vnew)
pub fn vnewT(comptime T: type, len: anytype, pl: Pool) [*]T {
    var cap: ulong = VMin;
    while (cap < len) cap *= 2;
    const f = if (pl == PHeap) &emalloc else &alloc;
    const v: [*]Vec = @ptrCast(@alignCast(f(cap * @sizeOf(T) + @sizeOf(Vec))));
    v[0] = .{ .mag = VMag, .pool = pl, .cap = cap };
    return @ptrCast(@alignCast(v + 1));
}

/// capacity of vector p
pub fn vcap(p: anytype) ulong {
    return vhdr(p).cap;
}

/// release vector p (no-op for function-pool vectors)
pub fn vfree(p: anytype) void {
    const h = vhdr(p);
    if (h.pool == PHeap) {
        h.mag = 0;
        efree(@ptrCast(h));
    }
}

/// make *vp hold at least len elements, preserving contents
pub fn vgrow(vp: anytype, len: anytype) void {
    const T = VElem(@TypeOf(vp.*));
    const old = vp.*;
    const h = vhdr(old);
    if (h.cap >= len)
        return;
    const n = vnewT(T, len, h.pool);
    const src: [*]const T = @ptrCast(old);
    @memcpy(n[0..h.cap], src[0..h.cap]);
    vfree(old);
    vp.* = @ptrCast(n);
}

'''+s[end:]
open(p,'w').write(s)
for f in glob.glob('/data/qbe-zig/src/**/*.zig',recursive=True):
    t=open(f).read()
    t2=re.sub(r'vfree\(@ptrCast\((.*)\)\);',r'vfree(\1);',t)
    if t2!=t: open(f,'w').write(t2); print('vfree',f)
