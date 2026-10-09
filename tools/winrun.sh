#!/bin/sh
# Run a Windows executable under wine; wine refuses files without .exe
# (STATUS_DLL_NOT_FOUND c0000135), so copy the binary to NAME.exe first.
exe=$1; shift
case $exe in *.exe) ;; *) cp "$exe" "$exe.exe"; exe=$exe.exe ;; esac
WINEDEBUG=-all exec wine "$exe" "$@"
