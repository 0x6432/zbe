p='/data/qbe-zig/HANDOFF.md'
s=open(p).read()
mark='PLAN (user approved, in order):'
assert mark in s
new='''TAG v2-idiomatic (= backup 40, 51b20dc): end of Phase 3, byte-identical to
upstream C QBE e786f06.
STAGE 7 (bug fixes, IN PROGRESS -> tag v3-bugfix when all.sh is green):
  The 3 BUGS.md issues are fixed in Zig (tools/s7_bugfix.py) AND in a patched
  C reference /data/qbe-cfix/qbe built from tools/qbe-cfix.patch
  (`cp -r /data/qbe-c /data/qbe-cfix; cd /data/qbe-cfix; patch -p1 <
  /data/qbe-zig/tools/qbe-cfix.patch; make`). All compare tools now default
  to ${QBEREF:-/data/qbe-cfix/qbe}, so "byte-identical" now means identical to
  the FIXED C. 1: ops.zig sar/shr/shl X(1,0,0) (no zero-flag reuse);
  2: amd64/isel.zig masks constant shift counts to 31/63; 3: util.zig igroup
  steps back onto the sel0. Tests: tools/bugs.sh (89 property checks; fails
  55/89 on unfixed C, 0 on fixed) + unit tests "igroup: ..." (16 unit tests).
  all.sh now also prints `bugs: N passed, 0 failed`.
NEXT after v3-bugfix: new optimization passes (user request), each verified
  with unit/edge/bugs/fuzz; output may then differ from C by design, so
  compare program BEHAVIOUR (abifuzz/irfuzz run the code) not bytes.
'''
s=s.replace(mark,new+mark,1)
s=s.replace('stages 1-6n done','stages 1-6n done + stage 7 bugfixes')
open(p,'w').write(s)
