#!/usr/bin/env python3
"""Kill wrong-scale and displacement mutants; retain eleven simpl.zig patterns.
Run only in an exclusive verification worktree. Restore source and build even
on failure; never label an unsuccessful compiler build as a killed regression mutant.
"""
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'src/amd64/isel.zig'
PATTERN = 'return @as(i64, 1) << @intCast(c.bits.i);'
MUTANT = 'return @as(i64, 1) << @intCast(c.bits.i - 1);'
MUTATIONS = [
    ('wrong scale', PATTERN, MUTANT, 'memory oracle mismatch:'),
    ('unencodable displacement',
     'if (all.optlevel > 0 and a.offset.type != CUndef and',
     'if (all.optlevel == 0 and a.offset.type != CUndef and',
     'address assembly failure:'),
]

def run(args):
    env = dict(os.environ)
    env.pop('QBE_COMPAT', None)
    # Rebuilds install here, so do not accidentally test a different ZQBE.
    env['ZQBE'] = str(ROOT / 'zig-out/bin/qbe')
    return subprocess.run(args, cwd=ROOT, env=env, capture_output=True, text=True, timeout=300)

def require(result):
    if result.returncode:
        sys.stderr.write(result.stdout[-4000:] + result.stderr[-4000:])
        raise RuntimeError('prerequisite or restoration failed')

def main():
    original = SOURCE.read_text()
    require(run(['zig', 'build']))
    require(run([sys.executable, 'tools/address-scales.py']))
    try:
        for name, pattern, replacement, expected in MUTATIONS:
            assert original.count(pattern) == 1, name
            SOURCE.write_text(original.replace(pattern, replacement))
            require(run(['zig', 'build']))
            result = run([sys.executable, 'tools/address-scales.py'])
            if result.returncode == 0:
                raise RuntimeError(name + ' mutant survived')
            if expected not in result.stderr:
                sys.stderr.write(result.stdout[-4000:] + result.stderr[-4000:])
                raise RuntimeError(name + ' failed without the expected regression')
            print(name + ' mutant killed by ' + expected, flush=True)
    finally:
        SOURCE.write_text(original)
        require(run(['zig', 'build']))
    print('address mutation: 2 killed, 0 survived')

if __name__ == '__main__':
    main()
