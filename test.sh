#!/bin/sh
# Run dist/quine.exe on this machine, fetch it, and check the body equals the file.
# On WSL, running ./dist/quine.exe directly hands the file to Windows (binfmt
# WSLInterop matches "MZ"), so launch it through the shell bootstrap instead.
set -eu
cd "$(dirname "$0")"
F=dist/quine.exe
TMPDIR=${TMPDIR:-$PWD/build/tmp}; export TMPDIR; mkdir -p "$TMPDIR"

sh "$F" & PID=$!
trap 'kill $PID 2>/dev/null' EXIT
curl -s --retry 10 --retry-connrefused --retry-delay 1 -D build/headers.txt \
     -o build/served.bin http://127.0.0.1:8080/
cat build/headers.txt
cmp build/served.bin "$F" && echo "ok: served body is identical to $F"
