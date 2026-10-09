#!/usr/bin/env python3
"""Read zig build errors (src/ prefix stripped) on stdin.  For each error line,
give untyped locals declared from an Ins-array expression an explicit [*c]Ins type
(C pointers keep supporting pointer arithmetic/comparison)."""
import re, sys
fixed = 0
done = set()
for line in sys.stdin:
    m = re.match(r"^(\S+?):(\d+):(\d+): error: (.*)", line)
    if not m or 'Ins' not in m.group(4): continue
    f, l = m.group(1), int(m.group(2))
    L = open(f).read().split('\n')
    toks = set(re.findall(r'\b[A-Za-z_]\w*\b', L[l-1]))
    for d in range(l-1, -1, -1):
        if re.match(r'^(pub )?(inline )?fn ', L[d]): break
        dm = re.match(r'^(\s*)(var|const) (\w+) = (.+);$', L[d])
        if dm and dm.group(3) in toks and re.search(r'ins|curi|\bi\b|insb', dm.group(4)) and (f, d) not in done:
            L[d] = dm.group(1) + dm.group(2) + ' ' + dm.group(3) + ': [*c]Ins = ' + dm.group(4) + ';'
            done.add((f, d)); fixed += 1
    open(f, 'w').write('\n'.join(L))
print('fixed', fixed)
