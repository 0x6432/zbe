#!/usr/bin/env python3
"""Like listloops.py but handles a variable reused for several list walks
in one function:  var X = I1; while (X != null) : (X = X.*.L) B1 ... X = I2; while ...
All uses of X in the function must lie inside such loops."""
import re, sys
total = 0
def ty(init, decl):
    if decl:
        m = re.match(r'(?:\[\*c\]|\?\*)(\w+)', decl)
        if m: return m.group(1)
    if re.search(r'phi$', init): return 'Phi'
    if re.search(r'(start|link|s1|s2|dlink|idom|dom)$', init): return 'Blk'
    return None
for f in sys.argv[1:]:
    L = open(f).read().split('\n')
    k = 0
    while k < len(L):
        if not re.match(r'^(pub )?fn ', L[k]): k += 1; continue
        fe = k + 1
        while fe < len(L) and L[fe] != '}': fe += 1
        changed = True
        while changed:
            changed = False
            for d in range(k+1, fe):
                dm = re.match(r'^(\s*)var (\w+)(?:: ([^=]+))? = (.+);$', L[d])
                if not dm: continue
                ind, x, decl, init = dm.groups()
                # collect loops
                loops = []  # (start, hdr, end, init, link, rest, ind)
                ok = True
                j = d
                first = True
                while j < fe:
                    if first:
                        m0 = dm; i0 = ind; init0 = init
                    else:
                        m0 = re.match(r'^(\s*)' + x + r' = (.+);$', L[j])
                        if not m0: j += 1; continue
                        i0, init0 = m0.group(1), m0.group(2)
                    if j+1 >= fe: ok = False; break
                    m = re.match(r'^' + re.escape(i0) + r'while \(' + x + r' != null\) : \(' + x + r' = ' + x + r'\.(?:\*|\?)\.(\w+)\)(.*)$', L[j+1])
                    if not m: ok = False; break
                    link, rest = m.groups()
                    if rest.strip() == '{':
                        e = j + 2
                        while e < fe and not L[e].startswith(i0 + '}'): e += 1
                        if e >= fe or L[e] != i0 + '}': ok = False; break
                    elif rest.strip() == '':
                        e = j + 2
                        if not L[e].rstrip().endswith(';'): ok = False; break
                    else: ok = False; break
                    btxt = '\n'.join(L[j+2:e+ (0 if rest.strip()=='{' else 1)])
                    if re.search(r'\b' + x + r'\s*=[^=]', btxt) or re.search(r'&' + x + r'\b(?!\.)', btxt): ok = False; break
                    T = ty(init0, decl)
                    if T is None: ok = False; break
                    loops.append((j, e, init0, link, rest, i0, T))
                    first = False
                    j = e + 1
                if not ok or not loops: continue
                # all uses covered?
                covered = set()
                for (s, e, *_ ) in loops: covered.update(range(s, e+1))
                bad = any(re.search(r'\b' + x + r'\b', L[q]) for q in range(k+1, fe) if q not in covered)
                if bad: continue
                # nesting depth: later loops must be at same indent as first or deeper w/ same scope -> require same indent
                if any(l[5] != ind for l in loops): continue
                if len(set(l[6] for l in loops)) != 1: continue
                T = loops[0][6]
                it = x + '_it'
                for n, (s, e, init0, link, rest, i0, _) in enumerate(loops):
                    L[s] = i0 + ('var ' + it + ': ?*' + T + ' = ' if n == 0 else it + ' = ') + init0 + ';'
                    L[s+1] = i0 + 'while (' + it + ') |' + x + '| : (' + it + ' = ' + x + '.' + link + ')' + rest
                    end = e if rest.strip() == '{' else e
                    for q in range(s+2, end+1):
                        L[q] = re.sub(r'\b' + x + r'\.(?:\*|\?)\.', x + '.', L[q])
                total += 1
                changed = True
                break
        k = fe + 1
    open(f, 'w').write('\n'.join(L))
print('converted', total)
