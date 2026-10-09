#!/usr/bin/env python3
"""stage 6n: drop redundant @intCast/@truncate/@ptrCast.

A cast builtin never passes its result type down into its operand, so
replacing `@intCast(e)` by `(e)` either fails to compile (narrowing /
sign change / pointer change needed) or compiles to exactly the same value
(identity or lossless widening coercion).  We therefore remove every cast in
a file, build, and put back the casts on every line the compiler complains
about, until the build is clean.
"""
import os, re, subprocess, sys
ROOT = '/data/qbe-zig'
BUILT = ('@intCast(', '@truncate(', '@ptrCast(')
ERR = re.compile(r'^(?:/\S*?/)?(src/[\w/]+\.zig):(\d+):\d+: error:', re.M)

def sites(line):
    """yield (start, open_paren_end, close_idx) of cast calls in a line"""
    out = []
    i = 0
    while True:
        hits = [(line.find(b, i), b) for b in BUILT]
        hits = [(p, b) for p, b in hits if p >= 0]
        if not hits:
            return out
        p, b = min(hits)
        j = p + len(b)
        depth = 1
        k = j
        while k < len(line) and depth:
            c = line[k]
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
            elif c == '"':
                k = line.find('"', k + 1)
                if k < 0:
                    return out
            k += 1
        if depth:
            return out  # spans lines: leave alone
        out.append((p, j, k - 1))
        i = j

def strip(line):
    # remove innermost-last so indices stay valid: process from the right
    for p, j, k in reversed(sites(line)):
        line = line[:p] + '(' + line[j:k] + ')' + line[k + 1:]
    return line

def build():
    r = subprocess.run(['zig', 'build'], cwd=ROOT, capture_output=True, text=True)
    return r.returncode == 0, r.stderr

def process(rel):
    path = os.path.join(ROOT, rel)
    orig = open(path).read().split('\n')
    cur = []
    for ln in orig:
        s = ln.lstrip()
        cur.append(ln if s.startswith('//') else strip(ln))
    changed = {i for i in range(len(orig)) if cur[i] != orig[i]}
    if not changed:
        return 0, 0
    before = sum(len(sites(orig[i])) for i in changed)
    for _ in range(60):
        open(path, 'w').write('\n'.join(cur))
        ok, err = build()
        if ok:
            break
        bad = set()
        foreign = False
        for f, ln in ERR.findall(err):
            if f == rel:
                bad.add(int(ln) - 1)
            else:
                foreign = True
        restored = False
        for i in bad:
            if cur[i] != orig[i]:
                cur[i] = orig[i]
                restored = True
        if foreign or not restored:
            # cannot attribute: give up on this file
            open(path, 'w').write('\n'.join(orig))
            print(rel, 'GAVE UP', err[:600], file=sys.stderr)
            return before, 0
    else:
        open(path, 'w').write('\n'.join(orig))
        return before, 0
    after = sum(len(sites(cur[i])) for i in changed)
    return before, before - after

if __name__ == '__main__':
    ok, err = build()
    assert ok, err
    files = sys.argv[1:] or sorted(
        os.path.relpath(os.path.join(d, f), ROOT)
        for d, _, fs in os.walk(os.path.join(ROOT, 'src')) for f in fs
        if f.endswith('.zig') and f != 'unit_tests.zig')
    tot = 0
    for rel in files:
        b, removed = process(rel)
        tot += removed
        if b:
            print('%-24s %4d casts, removed %4d' % (rel, b, removed), flush=True)
    print('TOTAL removed', tot)
