//! Unit tests for the self-contained helpers in util.zig.
//! Run with `zig build test`. End-to-end behaviour (byte-identical output
//! vs C qbe) is covered by tools/all.sh and tools/edge.sh.
const std = @import("std");
const t = std.testing;
const all = @import("all.zig");
const Opc = all.Opc;
const u = @import("util.zig");

const PHeap = all.PHeap;
const PFn = all.PFn;

// ---- vectors -------------------------------------------------------------

test "vnewT: minimum capacity and power-of-two rounding" {
    const v0 = u.vnewT(u32, 0, PHeap);
    defer u.vfree(v0);
    try t.expectEqual(@as(all.ulong, 2), u.vcap(v0)); // VMin

    const v1 = u.vnewT(u32, 1, PHeap);
    defer u.vfree(v1);
    try t.expectEqual(@as(all.ulong, 2), u.vcap(v1));

    const v5 = u.vnewT(u64, 5, PHeap);
    defer u.vfree(v5);
    try t.expectEqual(@as(all.ulong, 8), u.vcap(v5));

    const v8 = u.vnewT(u8, 8, PHeap);
    defer u.vfree(v8);
    try t.expectEqual(@as(all.ulong, 8), u.vcap(v8));
}

test "vnewT: elements are 16-byte aligned" {
    const v = u.vnewT(u8, 3, PHeap);
    defer u.vfree(v);
    try t.expect(@intFromPtr(v) % 16 == 0);
}

test "vgrow: no-op when capacity suffices" {
    var v = u.vnewT(i32, 4, PHeap);
    defer u.vfree(v);
    const before = v;
    u.vgrow(&v, 4);
    u.vgrow(&v, 1);
    u.vgrow(&v, 0);
    try t.expectEqual(before, v);
}

test "vgrow: preserves contents across many reallocations" {
    var v = u.vnewT(i32, 1, PHeap);
    for (0..1000) |n| {
        u.vgrow(&v, n + 1);
        v[n] = @intCast(n * 7);
    }
    defer u.vfree(v);
    try t.expect(u.vcap(v) >= 1000);
    for (0..1000) |i| try t.expectEqual(@as(i32, @intCast(i * 7)), v[i]);
}

test "vgrow: struct elements and function pool" {
    const S = struct { a: u64, b: u8 };
    var v = u.vnewT(S, 2, PFn);
    v[0] = .{ .a = 1, .b = 2 };
    v[1] = .{ .a = 3, .b = 4 };
    u.vgrow(&v, 33);
    try t.expect(u.vcap(v) >= 33);
    try t.expectEqual(@as(u64, 3), v[1].a);
    try t.expectEqual(@as(u8, 2), v[0].b);
    u.vfree(v); // no-op for PFn
    u.freeall();
}

test "vgrow: optional and sentinel vector pointers" {
    var o: ?[*]u16 = u.vnewT(u16, 2, PHeap);
    o.?[1] = 0xbeef;
    u.vgrow(&o, 10);
    try t.expectEqual(@as(u16, 0xbeef), o.?[1]);
    u.vfree(o.?);

    var z: [*:0]u8 = @ptrCast(u.vnewT(u8, 2, PHeap));
    z[0] = 'h';
    z[1] = 0;
    u.vgrow(&z, 64);
    z[1] = 'i';
    z[2] = 0;
    try t.expectEqualStrings("hi", std.mem.span(z));
    u.vfree(z);
}

fn symname(buf: *[32]u8, i: usize) [:0]const u8 {
    const n = (std.fmt.bufPrint(buf[0..31], "sym{d}", .{i}) catch unreachable).len;
    buf[n] = 0;
    return buf[0..n :0];
}

// ---- strings -------------------------------------------------------------

test "hash: matches C qbe hash (h = c + 17*h)" {
    try t.expectEqual(@as(u32, 0), u.hash(""));
    try t.expectEqual(@as(u32, 'a'), u.hash("a"));
    try t.expectEqual(@as(u32, 'b' + 17 * @as(u32, 'a')), u.hash("ab"));
    // wrap-around must not trap
    _ = u.hash("a very long string that certainly overflows 32 bits of hash state");
}

test "intern/str: round trip, dedup, empty and colliding strings" {
    const a = u.intern("foo");
    const b = u.intern("bar");
    const a2 = u.intern("foo");
    try t.expectEqual(a, a2);
    try t.expect(a != b);
    try t.expectEqualStrings("foo", std.mem.span(u.str(a)));
    try t.expectEqualStrings("bar", std.mem.span(u.str(b)));

    const e = u.intern("");
    try t.expectEqualStrings("", std.mem.span(u.str(e)));
    try t.expectEqual(e, u.intern(""));

    // many distinct strings, forcing bucket growth and hash collisions
    var ids: [600]u32 = undefined;
    var buf: [32]u8 = undefined;
    for (&ids, 0..) |*id, i| {
        const s = symname(&buf, i);
        id.* = u.intern(s.ptr);
    }
    for (ids, 0..) |id, i| {
        const s = symname(&buf, i);
        try t.expectEqualStrings(s, std.mem.span(u.str(id)));
        try t.expectEqual(id, u.intern(s.ptr));
    }
    // interned copy is independent of the caller's buffer
    @memset(&buf, 'x');
    try t.expectEqualStrings("sym0", std.mem.span(u.str(ids[0])));
}

test "strf: formatting, NUL terminator, both pools" {
    const s = u.strf(PHeap, "{s}.{d}", .{ "tmp", 42 });
    try t.expectEqualStrings("tmp.42", std.mem.span(s));
    try t.expectEqual(@as(u8, 0), s[6]);
    const e = u.strf(PFn, "", .{});
    try t.expectEqual(@as(usize, 0), std.mem.len(e));
    u.freeall();
}

test "cs and streq" {
    const z: [*:0]const u8 = "abc";
    try t.expectEqualStrings("abc", u.cs(z));
    const on: ?[*:0]const u8 = null;
    _ = u.cs(on); // must not crash on null
    try t.expect(u.streq(z, "abc"));
    try t.expect(!u.streq(z, "abd"));
    try t.expect(!u.streq(z, "ab"));
}

// ---- bitsets -------------------------------------------------------------

test "bitset: set/clr/count/iter across word boundaries" {
    var bs: all.BSet = undefined;
    u.bsinit(&bs, 200);
    defer u.freeall();
    u.bszero(&bs);
    try t.expectEqual(@as(all.uint, 0), u.bscount(&bs));

    const elts = [_]i32{ 0, 1, 63, 64, 65, 127, 128, 199 };
    for (elts) |e| u.bsset(&bs, e);
    u.bsset(&bs, 64); // idempotent
    try t.expectEqual(@as(all.uint, elts.len), u.bscount(&bs));

    var got: [elts.len]i32 = undefined;
    var n: usize = 0;
    var i: i32 = 0;
    while (u.bsiter(&bs, &i)) : (i += 1) {
        got[n] = i;
        n += 1;
    }
    try t.expectEqual(elts.len, n);
    try t.expectEqualSlices(i32, &elts, &got);

    u.bsclr(&bs, 64);
    u.bsclr(&bs, 64);
    try t.expectEqual(@as(all.uint, elts.len - 1), u.bscount(&bs));
}

test "bitset: empty iteration and algebra" {
    var a: all.BSet = undefined;
    var b: all.BSet = undefined;
    u.bsinit(&a, 130);
    u.bsinit(&b, 130);
    defer u.freeall();
    u.bszero(&a);
    u.bszero(&b);
    var i: i32 = 0;
    try t.expect(!u.bsiter(&a, &i));

    u.bsset(&a, 3);
    u.bsset(&a, 100);
    u.bsset(&b, 100);
    u.bsset(&b, 129);

    var c: all.BSet = undefined;
    u.bsinit(&c, 130);
    u.bscopy(&c, &a);
    try t.expect(u.bsequal(&c, &a));
    u.bsunion(&c, &b);
    try t.expectEqual(@as(all.uint, 3), u.bscount(&c));
    u.bscopy(&c, &a);
    u.bsinter(&c, &b);
    try t.expectEqual(@as(all.uint, 1), u.bscount(&c));
    u.bscopy(&c, &a);
    u.bsdiff(&c, &b);
    try t.expectEqual(@as(all.uint, 1), u.bscount(&c));
    try t.expect(!u.bsequal(&c, &a));
}

// ---- misc ----------------------------------------------------------------

test "sort: matches qsort ordering for ints" {
    var a = [_]i32{ 5, -1, 3, 3, 0, 9, -7 };
    const ord = struct {
        fn f(x: i32, y: i32) std.math.Order {
            return std.math.order(x, y);
        }
    }.f;
    u.sort(i32, &a, a.len, ord);
    try t.expectEqualSlices(i32, &.{ -7, -1, 0, 3, 3, 5, 9 }, &a);
    u.sort(i32, &a, 0, ord); // empty is fine
}

test "ptrdiff" {
    var a: [10]u64 = undefined;
    const p: [*]u64 = &a;
    try t.expectEqual(@as(isize, 7), u.ptrdiff(p + 7, p));
    try t.expectEqual(@as(isize, -3), u.ptrdiff(p, p + 3));
}

// ---- igroup (stage 7 bug fix) ---------------------------------------------

fn mkblk(ops: []const all.Opc, buf: []all.Ins) all.Blk {
    var b = std.mem.zeroes(all.Blk);
    for (ops, 0..) |o, i| {
        buf[i] = std.mem.zeroes(all.Ins);
        buf[i].op = o;
    }
    b.ins = buf.ptr;
    b.nins = @intCast(ops.len);
    return b;
}

test "igroup: sel1 run resolves to its sel0" {
    var buf: [6]all.Ins = undefined;
    var b = mkblk(&.{ .copy, .sel0, .sel1, .sel1, .sel1, .copy }, &buf);
    for ([_]u32{ 1, 2, 3, 4 }) |n| {
        const g = u.igroup(&b, n);
        try t.expectEqual(@as(all.uint, 1), g[0]);
        try t.expectEqual(@as(all.uint, 5), g[1]);
    }
    // a plain instruction is its own group
    const g = u.igroup(&b, 5);
    try t.expectEqual(@as(all.uint, 5), g[0]);
    try t.expectEqual(@as(all.uint, 6), g[1]);
}

test "igroup: lone sel0 and blit pairs" {
    var buf: [4]all.Ins = undefined;
    var b = mkblk(&.{ .sel0, .blit0, .blit1, .copy }, &buf);
    var g = u.igroup(&b, 0);
    try t.expectEqual(@as(all.uint, 0), g[0]);
    try t.expectEqual(@as(all.uint, 1), g[1]);
    g = u.igroup(&b, 1);
    try t.expectEqual(@as(all.uint, 1), g[0]);
    try t.expectEqual(@as(all.uint, 3), g[1]);
    g = u.igroup(&b, 2);
    try t.expectEqual(@as(all.uint, 1), g[0]);
    try t.expectEqual(@as(all.uint, 3), g[1]);
}
