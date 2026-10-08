p='/data/qbe-zig/HANDOFF.md'
s=open(p).read()
old='PLAN (user approved, in order): (1) strings DONE; (2) vectors DONE; (2b) tests DONE; (3)'
new='''DONE 6m: jump kinds are `pub const J = enum(i16)` in all.zig (fields xxx,
retw..hlt); the old names `Jjmp`, `Jretw`, ... are aliases `= J.jmp` etc.;
Blk.jmp.type and cfg.zig Jmp.type are `J`. Arithmetic uses `J.add(n)`
(C: `Jjf + c`) and `.int()`; INRANGE/isret/isretbh accept enums or ints.
SANDBOX NOTE: long foreground commands (all.sh ~2 min) have killed the sandbox
twice and rolled /data back to an older snapshot. Always run all.sh in the
background (`(sh tools/all.sh > /tmp/all.log 2>&1; echo EXIT $? >> /tmp/all.log) &`)
and poll with `sleep 100; tail -12 /tmp/all.log`. Commit WIP before verifying.
PLAN (user approved, in order): (1) strings DONE; (2) vectors DONE; (2b) tests DONE; (3) jump enum DONE, then'''
assert old in s
s=s.replace(old,new)
s=s.replace('stages 1-6l done','stages 1-6m done').replace('current as of stage 6l,','current as of stage 6m,')
open(p,'w').write(s)
