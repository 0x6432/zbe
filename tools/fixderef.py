#!/usr/bin/env python3
"""Read zig errors 'cannot dereference non-pointer type '?*all.T'' from stdin;
give the untyped local declaration of the dereferenced variable an explicit [*c]T type."""
import re, sys
fixed = 0
seen = set()
for line in sys.stdin:
    m = re.match(r"^(\S+?):(\d+):(\d+): error: cannot dereference non-pointer type '\?\*\w+\.(\w+)'", line)
    if not m: continue
    f, l, c, T = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)
    L = open(f).read().split('\n')
    s = L[l-1]
    # variable ending at column c-1 (the '.*' starts after name)
    mm = None
    for v in re.finditer(r'(\w+)\.\*', s):
        if v.end(1) <= c + 1 and v.end(1) >= c - 1: mm = v
    if not mm:
        cands = list(re.finditer(r'(\w+)\.\*', s))
        if len(cands) == 1: mm = cands[0]
    if not mm: print('no var', f, l, s.strip()); continue
    x = mm.group(1)
    for d in range(l-1, -1, -1):
        dm = re.match(r'^(\s*)(var|const) ' + x + r' = ', L[d])
        if dm:
            if (f, d) in seen: break
            L[d] = L[d].replace(dm.group(2) + ' ' + x + ' = ', dm.group(2) + ' ' + x + ': [*c]' + T + ' = ', 1)
            seen.add((f, d)); fixed += 1
            open(f, 'w').write('\n'.join(L))
            break
        if re.match(r'^(pub )?fn ', L[d]): print('no decl', f, l, x); break
print('fixed', fixed)
