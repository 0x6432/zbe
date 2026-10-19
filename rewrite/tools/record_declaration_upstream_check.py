#!/usr/bin/env python3
"""Secondary evidence only: dump pinned QBE type sizes/alignments in a temp copy.
No reference/archive/production source is modified. Exact integer TSV remains primary.
"""
from pathlib import Path
import os
import subprocess
import tarfile
import tempfile


def main():
    root=Path(__file__).resolve().parents[1]
    expected={}
    for line in (root/'src/fixtures/record_declaration_oracle.tsv').read_text().splitlines():
        if line.startswith('T\t'):
            _,name,explicit,alignment,size,runs=line.split()
            expected[name]=(int(size),int(alignment))
    with tempfile.TemporaryDirectory(prefix='record_declaration_upstream_') as directory:
        path=Path(directory)
        with tarfile.open(root.parent/'tools/qbe-ref.tar.gz') as archive:
            archive.extractall(path,filter='data')
        source=path/'parse.c'
        text=source.read_text()
        needle='\tty->nunion = n;\n'
        assert text.count(needle)==1
        text=text.replace(needle,needle+'\tfprintf(stderr, "RECORD_META %s %llu %llu\\n", ty->name, (unsigned long long)ty->size, 1ULL << ty->align);\n')
        source.write_text(text)
        build=subprocess.run(['make','-s','-j1'],cwd=path,capture_output=True,text=True,timeout=120)
        if build.returncode:raise SystemExit(build.stdout+build.stderr)
        run=subprocess.run([str(path/'qbe'),str(root/'src/fixtures/record_declaration_layouts.ssa')],capture_output=True,text=True,timeout=30)
        if run.returncode:raise SystemExit(run.stderr)
        actual={}
        for line in run.stderr.splitlines():
            if line.startswith('RECORD_META '):
                _,name,size,alignment=line.split()
                actual[name]=(int(size),int(alignment))
        if actual!=expected:raise SystemExit('Pinned QBE secondary layout size/alignment differs from independent fixture')
    print(f'{len(expected)} pinned QBE secondary size/alignment checks passed (temporary observer only)')


if __name__=='__main__':main()
