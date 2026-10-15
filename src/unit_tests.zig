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
    u.sort(i32, &a, ord);
    try t.expectEqualSlices(i32, &.{ -7, -1, 0, 3, 3, 5, 9 }, &a);
    u.sort(i32, a[0..0], ord); // empty is fine
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

// Include private backend-boundary regression tests in the unit test root.
test {
    std.testing.refAllDecls(@import("amd64/isel.zig"));
    std.testing.refAllDecls(@import("rv64/emit.zig"));
    std.testing.refAllDecls(@import("live.zig"));
    std.testing.refAllDecls(@import("spill.zig"));
    std.testing.refAllDecls(@import("gvn.zig"));
    std.testing.refAllDecls(@import("parse.zig"));
    std.testing.refAllDecls(@import("emit.zig"));
    std.testing.refAllDecls(@import("load.zig"));
    std.testing.refAllDecls(@import("mem.zig"));
}

// ---- bounded instruction copies ------------------------------------------

fn numberedIns(comptime n: usize) [n]all.Ins {
    var items: [n]all.Ins = undefined;
    for (&items, 0..) |*i, index| {
        i.* = all.insOp(.copy);
        i.to = all.tmpRef(index);
    }
    return items;
}

fn expectInsNumbers(items: []const all.Ins, expected: []const u32) !void {
    try t.expectEqual(expected.len, items.len);
    for (items, expected) |i, number| {
        try t.expectEqual(Opc.copy, i.op);
        try t.expectEqual(number, i.to.val);
    }
}

test "icpy slices: disjoint copy returns bounded tail for chaining" {
    const source = numberedIns(4);
    var destination = numberedIns(6);
    const tail = u.icpy(&destination, &source);
    try t.expectEqual(@as(usize, 2), tail.len);
    try t.expectEqual(@intFromPtr(&destination[4]), @intFromPtr(tail.ptr));
    const more = [_]all.Ins{
        all.mkIns(.copy, .w, all.tmpRef(8), all.R, all.R),
        all.mkIns(.copy, .w, all.tmpRef(9), all.R, all.R),
    };
    try t.expectEqual(@as(usize, 0), u.icpy(tail, &more).len);
    try expectInsNumbers(&destination, &.{ 0, 1, 2, 3, 8, 9 });
}

test "icpy slices: overlapping copy toward the start" {
    var items = numberedIns(6);
    _ = u.icpy(items[0..4], items[1..5]);
    try expectInsNumbers(&items, &.{ 1, 2, 3, 4, 4, 5 });
}

test "icpy slices: overlapping copy toward the end" {
    var items = numberedIns(6);
    _ = u.icpy(items[1..5], items[0..4]);
    try expectInsNumbers(&items, &.{ 0, 0, 1, 2, 3, 5 });
}

test "icpy slices: empty and identical copies" {
    var items = numberedIns(3);
    const tail = u.icpy(&items, &.{});
    try t.expectEqual(items.len, tail.len);
    try t.expectEqual(@intFromPtr(&items), @intFromPtr(tail.ptr));
    try t.expectEqual(@as(usize, 0), u.icpy(items[0..0], &.{}).len);
    try t.expectEqual(@as(usize, 0), u.icpy(&items, &items).len);
    try expectInsNumbers(&items, &.{ 0, 1, 2 });
}

test "idup slices: growth, independent storage, shrinking and empty input" {
    var block = std.mem.zeroes(all.Blk);
    block.ins = u.vnewT(all.Ins, 0, PHeap);
    defer u.vfree(block.ins);
    var source = numberedIns(5);
    u.idup(&block, &source);
    try t.expectEqual(@as(all.uint, 5), block.nins);
    source[0].to = all.tmpRef(99);
    try expectInsNumbers(block.insns(), &.{ 0, 1, 2, 3, 4 });
    u.idup(&block, source[1..3]);
    try t.expectEqual(@as(all.uint, 2), block.nins);
    try expectInsNumbers(block.insns(), &.{ 1, 2 });
    u.idup(&block, &.{});
    try t.expectEqual(@as(all.uint, 0), block.nins);
    try t.expectEqual(@as(usize, 0), block.insns().len);
}

test "sort slices: equal keys retain their input order" {
    const Item = struct { key: i32, original: u32 };
    var items = [_]Item{
        .{ .key = 1, .original = 0 },
        .{ .key = 2, .original = 1 },
        .{ .key = 1, .original = 2 },
        .{ .key = 2, .original = 3 },
        .{ .key = 0, .original = 4 },
    };
    const order = struct {
        fn compare(a: Item, b: Item) std.math.Order {
            return std.math.order(a.key, b.key);
        }
    }.compare;
    u.sort(Item, &items, order);
    for (items, [_]u32{ 4, 0, 2, 1, 3 }) |i, original|
        try t.expectEqual(original, i.original);
}

test "instruction-buffer slices expose the active head and tail" {
    const saved = all.curi;
    defer all.curi = saved;
    all.curi = @as([*]all.Ins, &all.insb) + 3;
    try t.expectEqual(@as(usize, 3), all.insbHeadSlice().len);
    try t.expectEqual(@intFromPtr(&all.insb), @intFromPtr(all.insbHeadSlice().ptr));
    all.curi = all.insbEnd() - 2;
    try t.expectEqual(@as(usize, 2), all.insbTailSlice().len);
    try t.expectEqual(@intFromPtr(all.curi), @intFromPtr(all.insbTailSlice().ptr));
    all.curi = all.insbEnd();
    try t.expectEqual(@as(usize, 0), all.insbTailSlice().len);
    all.curi = &all.insb;
    try t.expectEqual(@as(usize, 0), all.insbHeadSlice().len);
}

// ---- bounded temporary arrays --------------------------------------------

test "phicls slices: compresses chains without modifying neighboring storage" {
    var storage = std.mem.zeroes([8]all.Tmp);
    storage[0].phi = 99;
    storage[7].phi = 100;
    const temps = storage[1..7];
    temps[5].phi = 4;
    temps[4].phi = 2;
    temps[2].phi = 1;
    temps[4].cost = 123;
    try t.expectEqual(@as(i32, 1), u.phicls(5, temps));
    for ([_]usize{ 2, 4, 5 }) |index|
        try t.expectEqual(@as(i32, 1), temps[index].phi);
    try t.expectEqual(@as(i32, 0), temps[1].phi);
    try t.expectEqual(@as(i32, 3), u.phicls(3, temps));
    try t.expectEqual(@as(i32, 0), u.phicls(0, temps));
    try t.expectEqual(@as(all.uint, 123), temps[4].cost);
    try t.expectEqual(@as(i32, 99), storage[0].phi);
    try t.expectEqual(@as(i32, 100), storage[7].phi);
}

test "dumpts slices: reads const temporaries and preserves debug output" {
    var temps = std.mem.zeroes([all.Tmp0 + 4]all.Tmp);
    var first: [5:0]u8 = "alpha".*;
    var last: [5:0]u8 = "gamma".*;
    temps[all.Tmp0].name = &first;
    temps[all.Tmp0 + 2].name = &last;
    const view: []const all.Tmp = &temps;
    var set: all.BSet = undefined;
    u.bsinit(&set, temps.len);
    defer u.freeall();
    u.bszero(&set);
    u.bsset(&set, all.Tmp0 + 2);
    u.bsset(&set, all.Tmp0);
    u.bsset(&set, 0); // machine-register bits are intentionally omitted
    var buffer: [64]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);
    try u.dumpts(&set, view, &output);
    try t.expectEqualStrings("[ alpha gamma ]\n", output.buffered());
}

test "dumpts slices: empty set accepts an empty temporary array" {
    var set: all.BSet = undefined;
    u.bsinit(&set, all.Tmp0 + 1);
    defer u.freeall();
    u.bszero(&set);
    var buffer: [16]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);
    try u.dumpts(&set, &.{}, &output);
    try t.expectEqualStrings("[ ]\n", output.buffered());
}

// ---- bounded address-matcher tables ---------------------------------------

test "runmatch slices: pushsym orders children by pattern number" {
    var numbers = std.mem.zeroes([2]all.Num);
    numbers[1].l = all.tmpRef(11);
    numbers[1].r = all.tmpRef(12);
    numbers[1].nl = 5;
    numbers[1].nr = 2;
    const view: []const all.Num = &numbers;
    var vars: [2]all.Ref = undefined;
    u.runmatch(&.{ 1, 3, 0, 3, 1, 0 }, view, all.tmpRef(1), &vars);
    try t.expect(all.req(vars[0], all.tmpRef(12)));
    try t.expect(all.req(vars[1], all.tmpRef(11)));
    numbers[1].nl = 2;
    u.runmatch(&.{ 1, 3, 0, 3, 1, 0 }, view, all.tmpRef(1), &vars);
    try t.expect(all.req(vars[0], all.tmpRef(11)));
    try t.expect(all.req(vars[1], all.tmpRef(12)));
}

test "runmatch slices: push preserves left-right order" {
    var numbers = std.mem.zeroes([2]all.Num);
    numbers[1].l = all.tmpRef(11);
    numbers[1].r = all.tmpRef(12);
    numbers[1].nl = 5;
    numbers[1].nr = 2;
    var vars: [2]all.Ref = undefined;
    u.runmatch(&.{ 2, 3, 0, 3, 1, 0 }, &numbers, all.tmpRef(1), &vars);
    try t.expect(all.req(vars[0], all.tmpRef(11)));
    try t.expect(all.req(vars[1], all.tmpRef(12)));
}

test "runmatch slices: dispatch handles cases and the default branch" {
    const code = [_]u8{ 5, 2, 4, 7, 8, 10, 13, 3, 0, 0, 3, 1, 0, 3, 2, 0 };
    var numbers = std.mem.zeroes([2]all.Num);
    for ([_]u8{ 4, 8, 1 }, 0..) |number, selected| {
        numbers[1].n = number;
        var vars: [3]all.Ref = @splat(all.conRef(99));
        u.runmatch(&code, &numbers, all.tmpRef(1), &vars);
        for (vars, 0..) |value, index|
            try t.expect(all.req(value, if (index == selected) all.tmpRef(1) else all.conRef(99)));
        try t.expectEqual(number, numbers[1].n);
    }
}

test "runmatch slices: jump and termination do not access number storage" {
    var vars = [_]all.Ref{all.conRef(99)};
    u.runmatch(&.{ 12, 0, 3, 0, 0 }, &.{}, all.tmpRef(7), &vars);
    try t.expect(all.req(vars[0], all.tmpRef(7)));
    u.runmatch(&.{0}, &.{}, all.tmpRef(8), &vars);
    try t.expect(all.req(vars[0], all.tmpRef(7)));
}
