#!/bin/sh
# One authoritative full local gate; never hide failures behind tail/sed pipes.
set -eu
cd "$(dirname "$0")/.."
export QBEREF=${QBEREF:-/data/qbe-cfix/qbe}
unset QBE_COMPAT
zig build
sh tools/ci.sh core

# Keep the established optional local corpus and extended fuzz entry points.
corpus=${CORPUS:-/data/corpus}
if [ -d "$corpus" ]; then
  sh tools/ci.sh corpus "$corpus"
fi
if [ -n "${FUZZ:-}" ]; then
  QBE_COMPAT=1 python3 tests/abifuzz.py -n 15 -s 1000 -k 60
  QBE_COMPAT=1 python3 tests/irfuzz.py -n 15 -s 5000 -k 100
fi
