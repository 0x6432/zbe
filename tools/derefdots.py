#!/usr/bin/env python3
"""Canonicalization helper: drop redundant `.*.` (p.*.f -> p.f) wherever p is a
single-item pointer.  Strategy: rewrite every `X.*.f` to `X.f`, then compile
repeatedly; for each 'does not support field access' error, restore `.*.` for
that base expression throughout the enclosing function.  Run from src/."""
import re, subprocess, sys, glob, collections
files = sorted(glob.glob('*.zig') + glob.glob('*/*.zig'))
files = [f for f in files if not f.startswith('check_tmp')]
pat = re.compile(r'\.\*\.(?=[A-Za-z_@])')
for f in (files if '--resume' not in sys.argv else []):
    s = open(f).read()
    open(f, 'w').write(pat.sub('.', s))
def base_at(line, i):
    # line[i] == '.'; scan back over a postfix expression
    j = i
    while j > 0:
        c = line[j-1]
        if c.isalnum() or c in '_.?*@':
            j -= 1
        elif c == '"':
            k = line.rfind('@"', 0, j-1)
            if k < 0: break
            j = k
        elif c == ']' or c == ')':
            o = '[' if c == ']' else '('
            d = 0; k = j - 1
            while k >= 0:
                if line[k] in ')]': d += 1
                elif line[k] in '([':
                    d -= 1
                    if d == 0: break
                k -= 1
            if c == ')':
                # function call: include callee name
                j = k
                while j > 0 and (line[j-1].isalnum() or line[j-1] in '_.'): j -= 1
            else:
                j = k
        else:
            break
    b = line[j:i]
    b = b.lstrip('.*')
    return b
def fnrange(L, l):
    s = l
    while s > 0 and not re.match(r'^(pub )?(inline )?(export )?fn |^\S.*= struct|^test ', L[s]): s -= 1
    e = l
    while e < len(L) and L[e] != '}': e += 1
    return s, e
it = 0
while True:
    it += 1
    r = subprocess.run(['zig', 'build'], cwd='..', capture_output=True, text=True)
    r.stderr = re.sub(r'(?m)^src/', '', r.stderr)
    errs = [m for m in re.finditer(r'^(\S+?):(\d+):(\d+): error: (.*)$', r.stderr, re.M)]
    if not errs:
        print('clean after', it, 'iterations'); break
    todo = collections.defaultdict(set)
    other = []
    for m in errs:
        f, l, c, msg = m.group(1), int(m.group(2)) - 1, int(m.group(3)) - 1, m.group(4)
        if 'does not support field access' in msg or 'no field named' in msg or 'no member named' in msg:
            todo[f].add((l, c))
        else:
            other.append(m.group(0))
    if other and not todo:
        print('\n'.join(other)); sys.exit(1)
    n = 0
    for f, locs in todo.items():
        L = open(f).read().split('\n')
        for (l, c) in sorted(locs):
            line = L[l]
            if c >= len(line) or line[c] != '.':
                # caret may point at base start; find first '.' after
                k = line.find('.', c)
                if k < 0: print('?', f, l+1, line); continue
                c = k
            b = base_at(line, c)
            if not b: print('nobase', f, l+1, line); continue
            s, e = fnrange(L, l)
            rx = re.compile(r'(?<![\w.])' + re.escape(b) + r'\.(?=[A-Za-z_@])(?!\*)')
            for q in range(s, e+1):
                L[q], k = rx.subn(b + '.*.', L[q]); n += k
        open(f, 'w').write('\n'.join(L))
    print('iter', it, 'errors', len(errs), 'restored', n, flush=True)
    if n == 0:
        print('\n'.join(m.group(0) for m in errs[:10])); sys.exit(1)
