"""Helpers for rewriting ABI files: pointer-range loops over [i_0, i_1)
with a parallel Class pointer become `for (ins, ca) |*i, *c|` loops."""
import re
LOOP = re.compile(r'''( *)(?:var )?i = i_0;\n\1(?:var )?c = ca;\n\1while \(i < i_1\) : \(\{\n\1    i \+= 1;\n\1    c \+= 1;\n\1\}\) \{''')
def loops(t):
    return LOOP.sub(lambda m: m.group(1) + 'for (ins, ca) |*i, *c| {', t)
def derefs(t, names=('c', 'i', 'i_1', 'b', 'il')):
    for n in names:
        t = re.sub(r'(?<![\w.])' + n + r'\.\*\.', n + '.', t)
    return t
