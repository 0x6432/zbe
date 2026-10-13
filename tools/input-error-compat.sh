#!/bin/sh
# Shared exception for input errors that C aborts on but zbe returns.
# Internal aborts, successful output and all other diagnostics remain strict.
input_error_matches() (
  [ "$1" -ge 128 ] && [ "$2" = 1 ] || return 1
  grep -Fxq -f - "$4" <<'MESSAGES' || return 1
qbe: dying: extern thread unavailable on arm64
qbe: dying: extern thread unavailable on rv64
qbe: dying: extern/thread unsupported on amd64_win
qbe: dying: extern with offset is not supported
qbe: dying: alloc too large
qbe: dying: invalid constant
qbe: dying: can't use env with varargs
qbe: dying: invalid common data definition
MESSAGES
  # Compare the ENTIRE stderr byte-for-byte after prefix normalization.
  work=$(mktemp -d) || return 1
  trap 'rm -rf "$work"' EXIT
  sed 's/^[^ ]*: dying:/dying:/' "$3" > "$work/c.err"
  sed 's/^[^ ]*: dying:/dying:/' "$4" > "$work/z.err"
  cmp -s "$work/c.err" "$work/z.err"
)
