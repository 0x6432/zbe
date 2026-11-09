#!/usr/bin/env python3
"""Focused extern CLI failure-output regression; not the complete U16 ledger."""
import argparse
import os
from pathlib import Path
import platform
import resource
import subprocess
import tempfile

CASES = (
    ('suffix', 'function l $f() {\n@e\nret extern $x+0\n}', b'unsupported_construct'),
    ('type', 'function w $f() {\n@e\nret extern $x\n}', b'type_mismatch'),
    ('declaration', 'data extern $x = { l 1 }', b'unsupported_construct'),
    ('extern-name', 'function l $f() {\n@e\nret extern $".bad"\n}', b'UnsupportedExternSymbol'),
    ('call-signature', 'function l $f() {\n@e\n%r =l call extern $g()\nret %r\n}\nfunction l $g(l %x) {\n@e\nret %x\n}', b'CallSignatureMismatch'),
)
SENTINEL=b'existing output must survive extern failure\x00\xff\n'

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler',type=Path,required=True)
    p.add_argument('--fold-integers',action='store_true')
    p.add_argument('--reuse-stack-homes',action='store_true')
    p.add_argument('--callee-saved-homes',action='store_true')
    args=p.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'): raise SystemExit('Linux AMD64 required')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    compiler=args.compiler.resolve(strict=True)
    flags=[flag for enabled,flag in ((args.fold_integers,'--fold-integers'),(args.reuse_stack_homes,'--reuse-stack-homes'),(args.callee_saved_homes,'--callee-saved-homes')) if enabled]
    with tempfile.TemporaryDirectory(prefix='zbe-extern-cli-') as tmp:
        d=Path(tmp); source=d/'input.ssa'; out=d/'output.s'
        clean={k:os.environ[k] for k in ('PATH','HOME','TMPDIR') if k in os.environ}
        clean['LC_ALL']='C'
        for name,text,expected in CASES:
            source.write_text(text)
            for exists in (False,True):
                if exists: out.write_bytes(SENTINEL)
                elif out.exists(): out.unlink()
                result=subprocess.run([str(compiler),*flags,str(source),str(out)],env=clean,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=90)
                if result.returncode==0 or expected not in result.stderr:
                    raise RuntimeError(f'{name}: wrong exit/diagnostic: {result.returncode}, {result.stderr!r}')
                if exists:
                    if out.read_bytes()!=SENTINEL: raise RuntimeError(f'{name}: existing output changed')
                elif out.exists(): raise RuntimeError(f'{name}: output created on failure')
        source.write_text('function l $f() {\n@e\nret extern $valid_symbol\n}')
        out.write_bytes(SENTINEL)
        result=subprocess.run([str(compiler),*flags,str(source),str(out)],env=clean,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=90)
        if result.returncode or b'valid_symbol@GOTPCREL' not in out.read_bytes():
            raise RuntimeError(f'success output did not replace sentinel: {result.returncode}, {result.stderr!r}')
    print(f'{len(CASES)*2} extern failure-output checks and one success passed; flags={flags!r}')

if __name__=='__main__': main()
