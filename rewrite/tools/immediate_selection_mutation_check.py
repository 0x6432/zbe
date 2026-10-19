#!/usr/bin/env python3
"""Require a compiling incorrect long-immediate mutant to fail native arithmetic."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--zig',required=True);p.add_argument('--evidence',required=True,type=Path);a=p.parse_args();a.evidence.mkdir(parents=True,exist_ok=True)
    root=Path(__file__).resolve().parents[1]
    old='const signed: i64 = @bitCast(bits);\n            break :immediate std.math.cast(i32, signed);'
    new='break :immediate @as(i32, @bitCast(@as(u32, @truncate(bits))));'
    with tempfile.TemporaryDirectory(prefix='zbe-immediate-mutant-') as d:
        work=Path(d);shutil.copytree(root/'src',work/'src');source=work/'src/amd64.zig';text=source.read_text()
        if text.count(old)!=1:raise SystemExit('Mutant anchor not unique')
        source.write_text(text.replace(old,new));binary=work/'mutant'
        build=subprocess.run([a.zig,'build-exe',str(work/'src/driver.zig'),'-O','Debug','-femit-bin='+str(binary)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
        (a.evidence/'build.log').write_bytes(build.stdout)
        if build.returncode:raise SystemExit('Mutant compilation failed: not a semantic kill')
        # --fold-integers suppresses shape assertions; only actual native values can kill.
        r=subprocess.run(['python3',str(root/'tools/immediate_selection_native_check.py'),'--compiler',str(binary),'--fold-integers'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
        (a.evidence/'runtime.log').write_bytes(r.stdout)
        if r.returncode==0 or b'immediate check ' not in r.stdout or b' failed' not in r.stdout:raise SystemExit('Mutant not killed by native arithmetic')
        print('Compiling low32-truncation mutant killed by executed native value assertion (not shape/assembly error)')
if __name__=='__main__':main()
