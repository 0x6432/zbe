#!/usr/bin/env python3
"""Canonicalization helper: rewrite C-style pointer iteration
    var X = B;
    while (X < &B[N]) : (X += 1) ...      (or X < B + N)
into
    for (B[0..N]) |*X| ...                (|X| for pointer elements)
when X is not used after the loop and the body does no arithmetic on X."""
import re, sys
loop = re.compile(r'^(\s*)while \((\w+) < (?:&(.+)\[(.+)\]|(.+?) \+ (.+))\) : \(\2 \+= 1\)(.*)$')
def norm(e): return e.replace('.*.', '.')
total = 0
for f in sys.argv[1:]:
    L = open(f).read().split('\n')
    k = 1
    while k < len(L):
        m = loop.match(L[k])
        if not m: k += 1; continue
        ind, x = m.group(1), m.group(2)
        base = m.group(3) or m.group(5); n = m.group(4) or m.group(6)
        rest = m.group(7)
        dm = re.match(r'^' + re.escape(ind) + r'var ' + x + r'(?:: [^=]+)? = (.+);$', L[k-1])
        if not dm or norm(dm.group(1)) != norm(base):
            k += 1; continue
        if rest.strip() == '{':
            e = k + 1
            while e < len(L) and not L[e].startswith(ind + '}'): e += 1
            if e >= len(L) or L[e] != ind + '}':
                k += 1; continue
            body = L[k+1:e]; end = e
        elif rest.strip() == '':
            body = [L[k+1]]; end = k + 1
            if body[0].rstrip().endswith('{') or not body[0].rstrip().endswith(';'):
                k += 1; continue
        else:
            k += 1; continue
        btxt = '\n'.join(body)
        bad = re.search(r'\b' + x + r'\b\s*(\+|-[^>]|\[|<|>[^>]|==|!=|=[^=])', btxt) \
            or re.search(r'(\+|-|<|>|==|!=)\s*' + x + r'\b(?!\.)', btxt) \
            or re.search(r'&' + x + r'\b(?!\.)', btxt)
        fe = end + 1
        while fe < len(L) and not (L[fe].strip().startswith('}') and len(L[fe]) - len(L[fe].lstrip()) < len(ind)): fe += 1
        after = '\n'.join(L[end+1:fe])
        if bad or re.search(r'\b' + x + r'\b', after):
            k += 1; continue
        byval = re.search(r'\b' + x + r'\.\*\.\*', btxt) or re.search(r'(pred|rpo|fron|blk|stk)$', base)
        if byval:
            body = [re.sub(r'\b' + x + r'\.\*', x, l) for l in body]
        else:
            body = [re.sub(r'\b' + x + r'\.\*\.', x + '.', l) for l in body]
        L[k-1:end+1] = [ind + 'for (' + base + '[0..' + n + ']) |' + ('' if byval else '*') + x + '|' + rest] + body + ([L[end]] if rest.strip() == '{' else [])
        total += 1
        k += 1
    open(f, 'w').write('\n'.join(L))
print('converted', total)
