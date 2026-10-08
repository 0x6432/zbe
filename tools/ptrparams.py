#!/usr/bin/env python3
"""Canonicalization helper: turn `name: [*c]T` function parameters into
`name: *T` when the body never does pointer arithmetic, indexing, null
or pointer comparisons on them, and rewrite `name.*.` to `name.`.
usage: ptrparams.py T1,T2,... files..."""
import re, sys
TYPES = sys.argv[1].split(',')
files = sys.argv[2:]
sig = re.compile(r'^((?:pub )?(?:export )?(?:inline )?fn \w+\()(.*)(\) [^{\n]* \{)$', re.M)
def body_end(s, i):
    d = 0; j = i
    while j < len(s):
        ch = s[j]
        if ch == '/' and s.startswith('//', j):
            j = s.index('\n', j); continue
        if ch in '"\'':
            j += 1
            while s[j] != ch:
                j += 2 if s[j] == '\\' else 1
        elif ch == '{': d += 1
        elif ch == '}':
            d -= 1
            if d == 0: return j
        j += 1
total = 0
for f in files:
    s = open(f).read()
    out = []; pos = 0
    for m in sig.finditer(s):
        params = m.group(2)
        bstart = m.end() - 1; bend = body_end(s, bstart)
        body = s[bstart:bend]
        newparams = params
        for pm in re.finditer(r'(\w+): \[\*c\](' + '|'.join(TYPES) + r')\b', params):
            n = pm.group(1)
            nb = re.sub(r'//.*', '', body)
            bad = re.search(r'\b' + n + r'\b\s*(\+|-[^>]|\[|<|>[^>]|==|!=|\+=|-=|orelse)', nb) \
                or re.search(r'(\+|-|<|>|==|!=)\s*' + n + r'\b(?!\.)', nb) \
                or re.search(r'&' + n + r'\b(?!\.)', nb) \
                or re.search(r'\b' + n + r'\s*=[^=]', nb) \
                or re.search(r'\bvar \w+(: [^=]+)? = ' + n + r'\b', nb)
            if bad: continue
            newparams = re.sub(r'\b' + n + r': \[\*c\]' + pm.group(2) + r'\b', n + ': *' + pm.group(2), newparams)
            body = re.sub(r'\b' + n + r'\.\*\.', n + '.', body)
            total += 1
        out.append(s[pos:m.start()]); out.append(m.group(1) + newparams + m.group(3)[:-1]); out.append(body); pos = bend
    out.append(s[pos:])
    open(f, 'w').write(''.join(out))
print('converted', total)
