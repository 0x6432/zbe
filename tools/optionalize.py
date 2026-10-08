#!/usr/bin/env python3
"""Canonicalization helper: turn `[*c]T` params and typed locals into `?*T`
(T from argv[1], comma separated).  Inside the function `x.*.f` -> `x.?.f` and
`x.*` -> `x.?.*`.  Then `zig build` repeatedly; every function that has a
compile error is restored to its original text and excluded.  Line count is
preserved by all edits, so functions are tracked by line range.  Run from src/."""
import re, subprocess, sys, glob
types = sys.argv[1].split(',')
files = [f for f in sorted(glob.glob('*.zig') + glob.glob('*/*.zig')) if not f.startswith('check_tmp')]
orig = {f: open(f).read().split('\n') for f in files}
def funcs(L):
    r = []; k = 0
    while k < len(L):
        if re.match(r'^(pub )?(inline )?(export )?fn ', L[k]):
            e = k
            while e < len(L) and L[e] != '}' and not (e == k and L[k].rstrip().endswith('}')): e += 1
            r.append((k, e)); k = e + 1
        else: k += 1
    return r
tyalt = '|'.join(map(re.escape, types))
cur = {}
nconv = 0
for f in files:
    L = list(orig[f])
    for (s, e) in funcs(L):
        names = []
        hdr = L[s]
        for m in re.finditer(r'(\w+): \[\*c\](' + tyalt + r')\b', hdr):
            names.append(m.group(1))
        L[s] = re.sub(r'(\w+): \[\*c\](' + tyalt + r')\b', r'\1: ?*\2', hdr)
        for q in range(s+1, e+1):
            m = re.match(r'^(\s*)(var|const) (\w+): \[\*c\](' + tyalt + r') = ', L[q])
            if m:
                names.append(m.group(3))
                L[q] = L[q].replace(': [*c]' + m.group(4) + ' = ', ': ?*' + m.group(4) + ' = ', 1)
            m = re.match(r'^(\s*)(var|const) (\w+) = (\w+);', L[q])
            if m and m.group(4) in names:
                names.append(m.group(3))
        body = '\n'.join(L[s+1:e+1])
        names = [x for x in names if not re.search(r'(?<![.\w])' + x + r'\s*(\[|\+|-[^>]|<|>)', body)]
        if not names:
            L[s:e+1] = orig[f][s:e+1]
            continue
        # undo type rewrites for names that were filtered out
        keep = set(names)
        for q in range(s, e+1):
            for m in re.finditer(r'(\w+): \?\*(' + tyalt + r')\b', L[q]):
                if m.group(1) not in keep and '[*c]' in orig[f][q]:
                    L[q] = L[q].replace(m.group(0), m.group(1) + ': [*c]' + m.group(2), 1)
        for q in range(s, e+1):
            for x in set(names):
                L[q] = re.sub(r'(?<![.\w])' + x + r'\.\*\.(?=[\w@])', x + '.?.', L[q])
                L[q] = re.sub(r'(?<![.\w])' + x + r'\.\*(?![.\w*])', x + '.?.*', L[q])
        nconv += 1
    cur[f] = L
    open(f, 'w').write('\n'.join(L))
print('functions touched', nconv)
it = 0
while True:
    it += 1
    r = subprocess.run(['zig', 'build'], cwd='..', capture_output=True, text=True)
    errs = re.findall(r'(?m)^src/(\S+?):(\d+):\d+: error:', r.stderr)
    errs += re.findall(r'(?m)^src/(\S+?):(\d+):\d+: note: parameter type declared here', r.stderr)
    if not errs:
        if 'error' in r.stderr: print(r.stderr[-2000:]); sys.exit(1)
        print('clean after', it); break
    nrev = 0
    for f, l in set(errs):
        l = int(l) - 1
        L = cur[f]
        for (s, e) in funcs(L):
            if s <= l <= e:
                if L[s:e+1] != orig[f][s:e+1]:
                    L[s:e+1] = orig[f][s:e+1]; nrev += 1
                break
        open(f, 'w').write('\n'.join(L))
    print('iter', it, 'errors', len(errs), 'reverted', nrev, flush=True)
    if nrev == 0:
        print(r.stderr[:3000]); sys.exit(1)
