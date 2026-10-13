#!/bin/sh
# Shared exception for input errors that C aborts on but zbe returns.
# Internal aborts, successful output and all other diagnostics remain strict.
input_error_matches() {
  [ "$1" -ge 128 ] && [ "$2" = 1 ] || return 1
  grep -Eq '^qbe: dying: (extern thread unavailable on (arm64|rv64)|extern/thread unsupported on amd64_win|extern with offset is not supported|alloc too large|invalid constant|can.t use env with varargs|invalid common data definition)$' "$4" || return 1
  # Compare the ENTIRE stderr, changing only the binary/source-file prefix.
  # Command substitutions remove trailing newlines identically on both sides.
  [ "$(sed 's/^[^ ]*: dying:/dying:/' "$3")" = "$(sed 's/^[^ ]*: dying:/dying:/' "$4")" ]
}
