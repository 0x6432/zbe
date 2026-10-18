#!/usr/bin/env python3
"""Check that focused neutral-identity assertions kill compiling semantic mutants.

Mutations affect only temporary source copies, never the candidate worktree.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--zig',required=True);p.add_argument('--evidence',type=Path,required=True);args=p.parse_args()
    args.evidence.mkdir(parents=True,exist_ok=True)
    root=Path(__file__).resolve().parents[1]
    text=(root/'src/optimize.zig').read_text()
    mutants={
        'long-shift-word-mask':('if (ty == .word) 31 else 63','if (ty == .word) 31 else 31'),
        'long-and-word-ones':('std.math.maxInt(u32) else std.math.maxInt(u64)','std.math.maxInt(u32) else std.math.maxInt(u32)'),
        'drop-unknown-multiply':('.mul => 1,','.mul => 0,'),
        'drop-symbol-payload':('if (integerBits(known(facts, b.rhs)) == neutral) return b.lhs;', 'if (integerBits(known(facts, b.rhs)) == neutral) return if (b.lhs == .symbol_offset) .{ .symbol = b.lhs.symbol_offset.symbol } else b.lhs;'),
    }
    for name,(old,new) in mutants.items():
        if text.count(old)!=1: raise SystemExit(f'Mutant anchor not unique: {name}')
        with tempfile.TemporaryDirectory(prefix='zbe-neutral-mutant-') as d:
            work=Path(d);shutil.copytree(root/'src',work/'src')
            (work/'src/optimize.zig').write_text(text.replace(old,new))
            r=subprocess.run([args.zig,'test',str(work/'src/root.zig'),'--test-filter','neutral_identity_test'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
            (args.evidence/(name+'.log')).write_bytes(r.stdout)
            if r.returncode==0 or b' failed.' not in r.stdout or b'FAIL (' not in r.stdout:
                raise SystemExit(f'Mutant not killed by an executing semantic assertion: {name} ({r.returncode})')
            print(f'Compiling semantic mutant killed: {name}')
if __name__=='__main__': main()
