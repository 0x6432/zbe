import re
R='/data/qbe-zig/src/'
def fix(f, pairs):
    p=R+f; s=open(p).read()
    for a,b,n in pairs:
        c=s.count(a)
        assert c==n,(f,a,c)
        s=s.replace(a,b)
    open(p,'w').write(s)
#fix('amd64/emit.zig',[('const c: i32 = @as(i32, @intCast(b.jmp.type)) - Jjf;','const c: i32 = b.jmp.type.int() - Jjf.int();',2)])
#fix('arm64/emit.zig',[('const c: i32 = @as(i32, @intCast(b.jmp.type)) - Jjf;','const c: i32 = b.jmp.type.int() - Jjf.int();',1)])
#fix('amd64/isel.zig',[('b.jmp.type = Jjf + Cine;','b.jmp.type = Jjf.add(Cine);',3)])
#fix('amd64/sysv.zig',[('const j: i32 = @intCast(b.jmp.type);','const j: i32 = b.jmp.type.int();',1)])
#fix('arm64/abi.zig',[('const j: i32 = @intCast(b.jmp.type);','const j: i32 = b.jmp.type.int();',2)])
#fix('rv64/abi.zig',[('const j: i32 = @intCast(b.jmp.type);','const j: i32 = b.jmp.type.int();',1)])
#fix('amd64/winabi.zig',[('const jmp_type: i32 = block.jmp.type;','const jmp_type: i32 = block.jmp.type.int();',1)])
#fix('arm64/isel.zig',[('b.jmp.type = @intCast(Jjf + cc);','b.jmp.type = Jjf.add(cc);',1)])
fix('parse.zig',[('curb.?.jmp.type = @intCast(Jretw + rcls);','curb.?.jmp.type = Jretw.add(rcls);',1),
  ('else if (b.jmp.type >= Jretsb)','else if (b.jmp.type.int() >= Jretsb.int())',1),
  ('jtoa[@intCast(b.jmp.type - 1)]','jtoa[@intCast(b.jmp.type.int() - 1)]',2)])
