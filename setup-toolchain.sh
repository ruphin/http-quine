#!/bin/sh
# Fetch cosmocc 4.0.2 into ./cosmocc and make it usable on this machine.
#
# Two things the stock zip needs here:
#  - Python's zipfile turns symlinks into text files, so the per-arch wrapper
#    scripts (x86_64-unknown-cosmo-cc -> cosmocross) break. We recreate them.
#  - On WSL with interop enabled, binfmt_misc hands every "MZ" file to Windows,
#    and cosmocc's helper tools are themselves APE files. We convert them to
#    plain x86-64 ELF in place with the bundled ape loader + assimilate, which
#    needs no sudo. (The alternative is: sudo sh -c 'echo -1 > /proc/sys/fs/binfmt_misc/WSLInterop')
set -eu
cd "$(dirname "$0")"
VER=${VER:-4.0.2}
ZIP=cosmocc-$VER.zip
URL=https://github.com/jart/cosmopolitan/releases/download/$VER/$ZIP

mkdir -p cosmocc
[ -f "cosmocc/$ZIP" ] || curl -L -o "cosmocc/$ZIP" "$URL"

python3 -I - "cosmocc/$ZIP" cosmocc <<'EOF'
import os, stat, sys, zipfile
z = zipfile.ZipFile(sys.argv[1]); dest = sys.argv[2]
for i in z.infolist():
    mode = i.external_attr >> 16
    p = os.path.join(dest, i.filename)
    if stat.S_ISLNK(mode):
        if os.path.lexists(p): os.remove(p)
        os.symlink(z.read(i).decode(), p)
    else:
        z.extract(i, dest)
        if mode & 0o777: os.chmod(p, mode & 0o777)
EOF

if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ] && grep -q enabled /proc/sys/fs/binfmt_misc/WSLInterop; then
  echo "WSL interop is enabled: converting cosmocc's APE helpers to ELF"
  cp cosmocc/bin/assimilate build-assimilate.tmp
  find cosmocc/bin cosmocc/libexec -type f | while read -r f; do
    if [ "$(head -c2 "$f")" = MZ ]; then
      cosmocc/bin/ape-x86_64.elf ./build-assimilate.tmp -c -e -x "$f"
    fi
  done
  rm -f build-assimilate.tmp
fi
echo "toolchain ready in ./cosmocc"
