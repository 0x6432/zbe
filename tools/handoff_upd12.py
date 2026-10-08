p='/data/qbe-zig/HANDOFF.md'
s=open(p).read()
old='PLAN (user approved, in order): (1) strings DONE; (2) vectors DONE; (2b) tests DONE; (3) jump enum DONE, then'
new='''DONE 6n: tools/s6n_casts.py removed 111 redundant @intCast/@truncate/@ptrCast
(a cast builtin never passes its result type to its operand, so a removal that
still compiles is an identity or lossless widening). ~470 casts remain; they
are real narrowing/sign/pointer conversions inherited from C int/uint mixing.
REMAINING (optional, not started): ops/classes (Kw..Kd, O*) as enums - ops are
used as table indices and in range arithmetic everywhere, so convert like 6m
(enum + aliases + .int()/add()); Ins.op/cls are u32 while Tmp.cls is i16 -
unifying these types would remove many of the remaining casts.
PLAN (user approved, in order): (1) strings DONE; (2) vectors DONE; (2b) tests DONE; (3) jump enum DONE, cast reduction pass DONE, then'''
assert old in s
s=s.replace(old,new)
s=s.replace('stages 1-6m done','stages 1-6n done').replace('current as of stage 6m,','current as of stage 6n,')
open(p,'w').write(s)
