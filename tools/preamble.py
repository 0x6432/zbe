#!/usr/bin/env python3
"""Regenerate the import block of src files (between the marker lines
'// -- imports --' and '// -- end imports --') with exactly the all.zig /
ops.zig names the file uses. Zig has no usingnamespace, this emulates
'#include "all.h"' without polluting files with unused names."""
import re, sys, os
src = os.path.join(os.path.dirname(__file__), '..', 'src')
decl = re.compile(r'^pub (?:inline )?(const|fn|var) ([A-Za-z_][A-Za-z0-9_]*)', re.M)
def exports(path):
    return {m.group(2): m.group(1) for m in decl.finditer(open(path).read())}
allx = exports(os.path.join(src, 'all.zig'))
opsx = exports(os.path.join(src, 'ops.zig'))
ident = re.compile(r'(?<![.\w@])([A-Za-z_][A-Za-z0-9_]*)\b')
B, E = '// -- imports --', '// -- end imports --'
for f in sys.argv[1:]:
    text = open(f).read()
    if B not in text: continue
    head, rest = text.split(B, 1)
    _, body = rest.split(E, 1)
    body_nc = re.sub(r'//.*', '', body)
    body_nc = re.sub(r'"(\\.|[^"\\])*"', '""', body_nc)
    used = set(ident.findall(body_nc))
    local = set(re.findall(r'^(?:pub )?(?:export )?(?:inline )?(?:const|var|fn) ([A-Za-z_]\w*)', body, re.M))
    lines = []
    for n in sorted(used - local):
        if n in allx and allx[n] != 'var':
            lines.append(f'const {n} = all.{n};')
        elif n in opsx and n not in allx:
            lines.append(f'const {n} = all.ops.{n};')
    rel = os.path.relpath(os.path.join(src, 'all.zig'), os.path.dirname(os.path.abspath(f)))
    out = head + B + '\nconst all = @import("' + rel + '");\n' + '\n'.join(lines) + '\n' + E + body
    open(f, 'w').write(out)
