#!/usr/bin/env python3
"""Canonicalization helper: rewrite backward pointer walks
    var X: [*c]Ins = B.ins + B.nins;      (B.*.ins also accepted)
    while (X != B.ins) {
        X -= 1;
        BODY
    }
into
    var X_n = B.nins;
    while (X_n > 0) {
        X_n -= 1;
        const X = &B.ins[X_n];
        BODY
    }
when BODY does no arithmetic/reassignment on X and X is not used after."""
import re, sys
def norm(e): return e.replace('.*.', '.')
total = 0
for f in sys.argv[1:]:
    L = open(f).read().split('\n')
    k = 0
    while k + 2 < len(L):
        dm = re.match(r'^(\s*)var (\w+)(?:: \[\*c\]Ins)? = (\w+)((?:\.\*)?)\.ins \+ \3(?:\.\*)?\.nins;$', L[k])
        if not dm: k += 1; continue
        ind, x, b, star = dm.groups()
        wm = re.match(r'^' + re.escape(ind) + r'while \(' + x + r' != ' + b + r'(?:\.\*)?\.ins\) \{$', L[k+1])
        if not wm or L[k+2].strip() != x + ' -= 1;': k += 1; continue
        e = k + 3
        while e < len(L) and not L[e].startswith(ind + '}'): e += 1
        if e >= len(L) or L[e] != ind + '}': k += 1; continue
        btxt = '\n'.join(L[k+3:e])
        bad = re.search(r'\b' + x + r'\b\s*(\+|-[^>]|\[|<|>[^>]|==|!=|=[^=]|\+=|-=)', btxt) \
            or re.search(r'(\+|-|<|>|==|!=)\s*' + x + r'\b(?!\.)', btxt) \
            or re.search(r'&' + x + r'\b(?!\.)', btxt)
        fe = e + 1
        while fe < len(L) and not (L[fe].strip().startswith('}') and len(L[fe]) - len(L[fe].lstrip()) < len(ind)): fe += 1
        if bad or re.search(r'\b' + x + r'\b', '\n'.join(L[e+1:fe])):
            k += 1; continue
        n = x + '_n'
        body = [re.sub(r'\b' + x + r'\.\*\.', x + '.', l) for l in L[k+3:e]]
        b = b + star
        L[k:e] = [ind + 'var ' + n + ' = ' + b + '.nins;',
                  ind + 'while (' + n + ' > 0) {',
                  ind + '    ' + n + ' -= 1;',
                  ind + '    const ' + x + ' = &' + b + '.ins[' + n + '];'] + body
        total += 1
        k += 1
    open(f, 'w').write('\n'.join(L))
print('converted', total)
