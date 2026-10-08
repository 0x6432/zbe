#!/usr/bin/env python3
"""Stage-1 canonicalization helper: rewrite C.fprintf/fputs/fputc/sprintf
calls into std.Io.Writer calls. Usage: conv_print.py FILE..."""
import re, sys

def find_close(s, i):  # s[i] == '(' ; return index of matching ')'
    depth = 0; j = i
    while j < len(s):
        c = s[j]
        if c == '"':
            j += 1
            while s[j] != '"':
                if s[j] == '\\': j += 1
                j += 1
        elif c == "'":
            j += 1
            while s[j] != "'":
                if s[j] == '\\': j += 1
                j += 1
        elif c in '([{': depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0: return j
        j += 1
    raise ValueError('unbalanced')

def split_args(s):
    out = []; depth = 0; cur = ''; j = 0
    while j < len(s):
        c = s[j]
        if c == '"':
            k = j + 1
            while s[k] != '"':
                if s[k] == '\\': k += 1
                k += 1
            cur += s[j:k + 1]; j = k + 1; continue
        if c == "'":
            k = j + 1
            while s[k] != "'":
                if s[k] == '\\': k += 1
                k += 1
            cur += s[j:k + 1]; j = k + 1; continue
        if c in '([{': depth += 1
        if c in ')]}': depth -= 1
        if c == ',' and depth == 0:
            out.append(cur.strip()); cur = ''
        else:
            cur += c
        j += 1
    if cur.strip(): out.append(cur.strip())
    return out

def strip_as(a):
    m = re.fullmatch(r'@as\((c_int|c_long|c_ulong|c_uint|f64|i64|u64|i32|u32)\s*,\s*(.*)\)', a, re.S)
    return m.group(2).strip() if m else a

def lit_parts(fmtexpr):
    """format expr is "a" ++ "b" ... ; return the concatenated literal body or None"""
    parts = re.findall(r'"((?:\\.|[^"\\])*)"', fmtexpr)
    rest = re.sub(r'"((?:\\.|[^"\\])*)"', '', fmtexpr).replace('++', '').strip()
    if rest: return None
    return parts

spec = re.compile(r'%([-+0 ]*)(\d*)(?:\.(\d+))?(l{0,2}|z)([diuxXcsf%])')

def conv_fmt(parts, args):
    """returns (new literal parts joined with ' ++ ', new args) """
    ai = 0; newargs = []; outparts = []
    for p in parts:
        o = ''; pos = 0
        for m in spec.finditer(p):
            o += p[pos:m.start()].replace('{', '{{').replace('}', '}}')
            pos = m.end()
            flags, width, prec, _, conv = m.groups()
            if conv == '%':
                o += '%'; continue
            a = strip_as(args[ai]); ai += 1
            if conv == 's':
                if not a.startswith('"'): a = 'cs(%s)' % a
                if '-' in flags and width: o += '{s:<%s}' % width
                elif width: o += '{s:>%s}' % width
                else: o += '{s}'
            elif conv in 'diu':
                if '+' in flags: o += '{d:1}'  # signed + width => '+' sign
                elif width and '0' in flags: o += '{d:0>%s}' % width
                elif width: o += '{d:>%s}' % width
                else: o += '{d}'
            elif conv in 'xX':
                c = 'x' if conv == 'x' else 'X'
                if width and '0' in flags: o += '{%s:0>%s}' % (c, width)
                else: o += '{%s}' % c
            elif conv == 'c':
                o += '{c}'
            elif conv == 'f':
                o += '{d:.%s}' % (prec or '6')
            newargs.append(a)
        o += p[pos:].replace('{', '{{').replace('}', '}}')
        outparts.append('"%s"' % o)
    assert ai == len(args), (parts, args)
    return ' ++ '.join(outparts), newargs

def conv_file(path):
    s = open(path).read()
    out = ''; i = 0; n = 0
    pat = re.compile(r'(_ = )?(?:C\.(fprintf|fputs|fputc|sprintf)|\b(die|err))\(')
    while True:
        m = pat.search(s, i)
        if not m:
            out += s[i:]; break
        out += s[i:m.start()]
        op = m.group(2) or m.group(3)
        lp = m.end() - 1
        rp = find_close(s, lp)
        args = split_args(s[lp + 1:rp])
        repl = None
        if op == 'fprintf':
            parts = lit_parts(args[1])
            if parts is not None:
                f, na = conv_fmt(parts, args[2:])
                repl = 'try %s.print(%s, .{%s})' % (W(args[0]), f, ', '.join(na))
        elif op == 'fputs':
            a = args[0]
            repl = 'try %s.writeAll(%s)' % (W(args[1]), a if a.startswith('"') else 'cs(%s)' % a)
        elif op == 'fputc':
            repl = 'try %s.writeByte(%s)' % (W(args[1]), strip_as(args[0]))
        elif op == 'sprintf':
            parts = lit_parts(args[1])
            if parts is not None:
                f, na = conv_fmt(parts, args[2:])
                repl = 'bufPrintZ(%s, %s, .{%s})' % (args[0], f, ', '.join(na))
        elif op in ('die', 'err') and len(args) == 2 and args[1].startswith('.{'):
            parts = lit_parts(args[0])
            inner = args[1][2:-1]
            targs = split_args(inner)
            if parts is not None:
                f, na = conv_fmt(parts, targs)
                repl = '%s(%s, .{%s})' % (op, f, ', '.join(na))
        if repl is None:
            out += s[m.start():rp + 1]
            print('%s: left as is: %s' % (path, s[m.start():m.start() + 60].replace('\n', ' ')))
        else:
            out += repl; n += 1
        i = rp + 1
    open(path, 'w').write(out)
    print('%s: %d calls converted' % (path, n))

def W(e):
    e = e.strip()
    if e == 'C.stderr': return 'dbg'
    if e == 'C.stdout': return 'stdout'
    return e

for p in sys.argv[1:]:
    conv_file(p)
