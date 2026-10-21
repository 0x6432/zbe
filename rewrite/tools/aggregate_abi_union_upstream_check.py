#!/usr/bin/env python3
"""Secondary pinned-QBE declared layout only, NOT native ABI/padding-lane parity.
Independent literal C/ASM/layout fixtures remain primary. Observe a TEMP copy;
never patch the production reference/archive or execute its aggregate ABI here.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import tarfile
import tempfile

def main():
    root=Path(__file__).resolve().parents[1]
    archive=root.parent/'tools/qbe-ref.tar.gz'
    if hashlib.sha256(archive.read_bytes()).hexdigest()!='ba0271b4722688e0fee53f59b0d05c1d5ad98ed35185bef5eea7e91ffe474f4e':
        raise SystemExit('Wrong pinned QBE archive')
    types=json.loads((root/'src/fixtures/aggregate_abi_union_layouts.json').read_text())['types']
    # The max4096 native case exceeds the reference's first32 expanded fields;
    # do not represent it as a complete reference representation/ABI oracle.
    types=[row for row in types if row['name']!='U4096']
    assert len(types)==15
    expected={row['name']:(row['size'],row['alignment']) for row in types}
    with tempfile.TemporaryDirectory(prefix='union_secondary_') as directory:
        path=Path(directory)
        with tarfile.open(archive) as tar:tar.extractall(path,filter='data')
        parse=path/'parse.c';text=parse.read_text();needle='\tty->nunion = n;\n'
        assert text.count(needle)==1
        parse.write_text(text.replace(needle,needle+'\tfprintf(stderr, "UNION_META %s %llu %llu\\n", ty->name, (unsigned long long)ty->size, 1ULL << ty->align);\n'))
        build=subprocess.run(['make','-s','-j1'],cwd=path,capture_output=True,text=True,timeout=120)
        if build.returncode:raise SystemExit(build.stdout+build.stderr)
        source=path/'layout.ssa';source.write_text(''.join('type :'+row['name']+' = '+row['IL']+'\n' for row in types))
        run=subprocess.run([str(path/'qbe'),str(source)],capture_output=True,text=True,timeout=30)
        if run.returncode:raise SystemExit(run.stderr)
        actual={}
        for line in run.stderr.splitlines():
            if line.startswith('UNION_META '):
                _,name,size,alignment=line.split();actual[name]=(int(size),int(alignment))
        if actual!=expected:raise SystemExit('Pinned declared layout differs from independent literals: '+repr(actual))
    print('15 pinned QBE secondary declared size/alignment checks passed; NOT aggregate ABI/padding-lane parity')

if __name__=='__main__':main()
