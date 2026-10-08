#!/usr/bin/env python3
"""Canonicalization helper: rewrite C-style linked-list walks
    var X = INIT;
    while (X != null) : (X = X.*.LINK) BODY
into
    var X_it: ?*T = INIT;
    while (X_it) |X| : (X_it = X.LINK) BODY
(T = Phi if INIT ends in 'phi', else Blk) when X is not reassigned in BODY
and not used after the loop."""
import re, sys
loop = re.compile(r'^(\s*)while \((\w+) != null\) : \(\2 = \2\.\*\.(\w+)\)(.*)$')
total = 0
for f in sys.argv[1:]:
    L = open(f).read().split('\n')
    k = 1
    while k < len(L):
        m = loop.match(L[k])
        if not m: k += 1; continue
        ind, x, link, rest = m.groups()
        dm = re.match(r'^' + re.escape(ind) + r'var ' + x + r'(?:: [^=]+)? = (.+);$', L[k-1])
        if not dm: k += 1; continue
        init = dm.group(1)
        if rest.strip() == '{':
            e = k + 1
            while e < len(L) and not L[e].startswith(ind + '}'): e += 1
            if e >= len(L) or L[e] != ind + '}': k += 1; continue
            body = L[k+1:e]; end = e
        elif rest.strip() == '':
            body = [L[k+1]]; end = k + 1
            if not body[0].rstrip().endswith(';'): k += 1; continue
        else:
            k += 1; continue
        btxt = '\n'.join(body)
        if re.search(r'\b' + x + r'\s*=[^=]', btxt) or re.search(r'&' + x + r'\b', btxt):
            k += 1; continue
        fe = end + 1
        while fe < len(L) and not L[fe].startswith('}'): fe += 1
        if re.search(r'\b' + x + r'\b', '\n'.join(L[end+1:fe])):
            k += 1; continue
        T = 'Phi' if re.search(r'phi$', init) else 'Blk'
        it = x + '_it'
        body = [re.sub(r'\b' + x + r'\.\*\.', x + '.', l) for l in body]
        L[k-1:k+1] = [ind + 'var ' + it + ': ?*' + T + ' = ' + init + ';',
                      ind + 'while (' + it + ') |' + x + '| : (' + it + ' = ' + x + '.' + link + ')' + rest]
        L[k+1:end+1] = body + ([L[end]] if rest.strip() == '{' else [])
        total += 1
        k += 1
    open(f, 'w').write('\n'.join(L))
print('converted', total)
