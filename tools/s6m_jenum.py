# stage 6m: jump kinds become `enum(i16) J`; Blk.jmp.type: J
import re
p='/data/qbe-zig/src/all.zig'
s=open(p).read()
m=re.search(r'// enum J\n((?:pub const J\w+ = \d+;\n)+)',s)
block=m.group(1)
names=re.findall(r'pub const J(\w+) = (\d+);',block)
fields=[]
for n,v in names:
    if n=='NJmp' or n=='Jmp': continue
consts=[(n,int(v)) for n,v in names]
for i,(n,v) in enumerate(consts):
    assert v==i,(n,v)
def fname(n):
    # Jretw -> retw ; Jjmp -> jmp ; Jjfieq -> jfieq ; Jxxx -> xxx
    return n[0].lower()+n[1:]
enum='pub const J = enum(i16) {\n'+''.join('    %s,\n'%fname(n) for n,_ in consts)+'''
    /// offset into the jump kinds, e.g. `J.jfieq.add(cmp)` (C: Jjf + cmp)
    pub inline fn add(j: J, n: anytype) J {
        return @enumFromInt(@intFromEnum(j) + @as(i16, @intCast(n)));
    }
    pub inline fn int(j: J) i32 {
        return @intFromEnum(j);
    }
};
'''
new='// enum J\n'+enum+''.join('pub const J%s = J.%s;\n'%(n,fname(n)) for n,_ in consts)+'pub const NJmp = %d;\n'%len(consts)
s=s.replace(m.group(0),new)
# INRANGE accepts enums
old='''pub inline fn INRANGE(x: anytype, comptime l: comptime_int, comptime u: comptime_int) bool {
    return @as(u32, @bitCast(@as(i32, @intCast(x)) -% l)) <= u - l;
}'''
assert old in s
s=s.replace(old,'''inline fn ordinal(x: anytype) i32 {
    return switch (@typeInfo(@TypeOf(x))) {
        .@"enum", .enum_literal => @intFromEnum(x),
        else => @intCast(x),
    };
}
pub inline fn INRANGE(x: anytype, comptime l: anytype, comptime u: anytype) bool {
    const lo = comptime ordinal(l);
    const hi = comptime ordinal(u);
    return @as(u32, @bitCast(ordinal(x) -% lo)) <= hi - lo;
}''')
old='''    jmp: extern struct {
        type: i16,'''
assert old in s
s=s.replace(old,'''    jmp: extern struct {
        type: J,''')
open(p,'w').write(s)
print(len(consts),'jump kinds')
