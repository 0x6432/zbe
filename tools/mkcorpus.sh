#!/bin/sh
# Rebuild the external test corpus + integration tests (needs network, cc).
# Usage: tools/mkcorpus.sh [/data]   then: tools/corpus.sh $D/corpus/*.qbe $D/corpus/hare/*.ssa
set -e
D=${1:-/data}
Z=$(cd "$(dirname "$0")/.." && pwd)/zig-out/bin/qbe
mkdir -p $D/zbin $D/corpus/hare && ln -sf $Z $D/zbin/qbe
export PATH=$D/zbin:$PATH
# cproc (uses `qbe` from PATH => zig qbe)
[ -d $D/cproc ] || git clone https://git.sr.ht/~mcf/cproc $D/cproc
(cd $D/cproc && ./configure --host=x86_64-linux-gnu && make && make bootstrap && make check-stage2)
cd $D/corpus
for f in $D/cproc/*.c; do $D/cproc/cproc -emit-qbe -I$D/cproc -o cproc_$(basename $f .c).qbe $f; done
for f in $D/qbe-c/*.c $D/qbe-c/*/*.c; do
  b=$(echo $f | sed "s|$D/qbe-c/||; s|/|_|g; s|\.c\$||")
  $D/cproc/cproc -D__CHAR_BIT__=8 -emit-qbe -I$D/qbe-c -o qbe_$b.qbe $f || true
done
cp $D/cproc/test/*.qbe $D/corpus/
# harec
[ -d $D/harec ] || git clone https://git.sr.ht/~sircmpwn/harec $D/harec
(cd $D/harec && cp configs/linux.mk config.mk && make && make check)
cp $D/harec/.cache/*.ssa $D/corpus/hare/
