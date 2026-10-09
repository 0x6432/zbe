#!/bin/sh
# Build the C reference: upstream qbe at the commit this port is based on,
# (vendored as tools/qbe-ref.tar.gz) plus tools/qbe-cfix.patch, the upstream
# bug fixes mirrored in zbe (see BUGS.md).
# Usage: ci-ref.sh [dir]   -> prints the path of the reference binary.
set -e
D=$(cd "$(dirname "$0")/.." && pwd)
O=${1:-$HOME/qbe-cfix}
REV=e786f06032fefa2e3790d6b1c9e31ed138f475a6
if [ ! -x "$O/qbe" ]; then
  rm -rf "$O"
  if [ -f "$D/tools/qbe-ref.tar.gz" ]; then
    # vendored pristine upstream source at REV (git archive), no network needed
    mkdir -p "$O" && tar -xzf "$D/tools/qbe-ref.tar.gz" -C "$O" && cd "$O"
  else
    git clone -q https://c9x.me/git/qbe.git "$O" 2>/dev/null ||
      git clone -q git://c9x.me/qbe.git "$O"
    cd "$O" && git checkout -q $REV
  fi
  { patch -s -p1 < "$D/tools/qbe-cfix.patch" || git apply "$D/tools/qbe-cfix.patch"; }
  make -s >/dev/null
fi
echo "$O/qbe"
