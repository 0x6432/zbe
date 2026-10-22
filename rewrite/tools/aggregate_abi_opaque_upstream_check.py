#!/usr/bin/env python3
"""Secondary pinned-QBE positive opaque transport and observed exact layout only.
The independent assembly/real-C and checked owned metadata tests are primary.
Never execute an ambiguous small containing type or mutate the reference archive.
Caller must serialize this compiler/native test with the shared verification lock.
"""
from pathlib import Path
import hashlib
import subprocess
import tarfile
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    fixtures = root/'src/fixtures'
    archive = root.parent/'tools/qbe-ref.tar.gz'
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == 'ba0271b4722688e0fee53f59b0d05c1d5ad98ed35185bef5eea7e91ffe474f4e'
    with tempfile.TemporaryDirectory(prefix='opaque_secondary_') as d:
        path = Path(d)
        with tarfile.open(archive) as tar:
            tar.extractall(path, filter='data')
        subprocess.run(['make', '-s', '-j1'], cwd=path, check=True, timeout=120)
        asm, exe = path/'native.s', path/'run'
        subprocess.run([str(path/'qbe'), '-o', str(asm), str(fixtures/'aggregate_abi_opaque.ssa')], check=True, timeout=90)
        subprocess.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fPIE', '-pie', str(fixtures/'aggregate_abi_opaque.c'), str(fixtures/'aggregate_abi_opaque_shim.s'), str(asm), '-o', str(exe)], check=True, timeout=90)
        subprocess.run([str(exe)], check=True, timeout=90)
        print('Actual unmodified pinned QBE positive opaque ASM/packed-C native fixture passed (secondary, NOT blanket ABI parity)')
        # Observe a temporary copy after the unmodified native run. Prints only;
        # never substitute rounded or host-C sizes for the exact source facts.
        parse = path/'parse.c'
        text = parse.read_text()
        needle = '\t\tif (nextnl() != Trbrace)\n\t\t\terr("} expected");\n\t\treturn;'
        assert text.count(needle) == 1
        observation = '\n\t\tfprintf(stderr, "OPAQUE_META %s %llu %llu\\n", ty->name, (unsigned long long)ty->size, 1ULL << ty->align);'
        text = text.replace(needle, needle.replace('\n\t\treturn;', observation+'\n\t\treturn;'))
        needle = '\tty->nunion = n;\n'
        assert text.count(needle) == 1
        text = text.replace(needle, needle+'\tfprintf(stderr, "OPAQUE_META %s %llu %llu\\n", ty->name, (unsigned long long)ty->size, 1ULL << ty->align);\n')
        parse.write_text(text)
        subprocess.run(['make', '-s', '-j1'], cwd=path, check=True, timeout=120)
        source = path/'layout.ssa'
        source.write_text('type :O1=align 16 {1}\ntype :O13=align 8 {13}\ntype :O17=align 16 {17}\ntype :R={:O13 2,b}\ntype :S={:O1}\ntype :U={{:O1}{b 17}}\n')
        result = subprocess.run([str(path/'qbe'), str(source)], check=True, capture_output=True, text=True, timeout=30)
        actual = {}
        for line in result.stderr.splitlines():
            if line.startswith('OPAQUE_META '):
                _, name, size, alignment = line.split()
                actual[name] = (int(size), int(alignment))
        assert actual == {'O1': (1, 16), 'O13': (13, 8), 'O17': (17, 16), 'R': (32, 8), 'S': (16, 16), 'U': (32, 16)}, actual
        print('6 pinned QBE exact-size/align/raw-child-stride secondary observations passed; small containing S is metadata only')


if __name__ == '__main__':
    main()
