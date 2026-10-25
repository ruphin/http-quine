#!/bin/sh
# Build the HTTP quine: a Cosmopolitan APE (Windows PE + Unix shell bootstrap +
# ELF + Mach-O) that is also an HTML page, and serves itself over HTTP.
#
#   ./build.sh            -> dist/quine.exe   (fat: x86-64 + arm64, all OSes)
#   ARCH=x86_64 ./build.sh -> x86-64 only, smaller, no native Apple Silicon
#
# Needs the cosmocc toolchain in ./cosmocc (see setup-toolchain.sh).
set -eu
cd "$(dirname "$0")"

COSMOCC=${COSMOCC:-./cosmocc}
PATH="$COSMOCC/bin:$PATH"
export PATH
OUT=dist/quine.exe
mkdir -p build dist

# 1. Compile. -mtiny selects the size-optimised runtime (~200 KB floor for fat).
case "${ARCH:-fat}" in
  fat)    cosmocc -mtiny -Os -o build/quine.ape quine.c ;;
  x86_64) x86_64-unknown-cosmo-cc -mtiny -Os -o build/quine.elf quine.c
          apelink -l "$COSMOCC/bin/ape-x86_64.elf" -o build/quine.ape build/quine.elf ;;
  *)      echo "ARCH must be fat or x86_64" >&2; exit 2 ;;
esac

# 2. The binary must not contain an HTML comment terminator, or the comment
#    that hides it from the browser would end early.
if grep -q -a -e '-->' -e '--!>' build/quine.ape; then
  echo "error: binary contains '-->' or '--!>'; tweak the source and rebuild" >&2
  exit 1
fi

# 3. Open an HTML comment at offset 8. The file starts with the 8 bytes
#    MZqFpD=' (DOS magic + start of a shell string). Bytes 8..11 are DOS
#    header fields Windows ignores and the shell never sees.
cp build/quine.ape "$OUT"
printf '<!--' | dd of="$OUT" bs=1 seek=8 conv=notrunc 2>/dev/null

# 4. Close the comment and append the page.
printf -- '-->' >> "$OUT"
cat page.html >> "$OUT"
chmod +x "$OUT"

# 5. Sanity checks: PE header still valid, exactly one comment in the HTML.
pecheck "$OUT"
python3 -I - "$OUT" <<'EOF'
import sys
from html.parser import HTMLParser
d = open(sys.argv[1], "rb").read().decode("latin-1")
class P(HTMLParser):
    comments = 0; text = []
    def handle_comment(s, x): s.comments += 1
    def handle_data(s, x):
        if x.strip(): s.text.append(x.strip()[:30])
p = P(); p.feed(d); p.close()
assert p.comments == 1, f"expected 1 comment, got {p.comments}"
assert p.text[0] == "MZqFpD='", f"unexpected leading text {p.text[0]!r}"
print(f"ok: {len(d)} bytes, 1 comment, leading text {p.text[0]!r}")
EOF
ls -l "$OUT"
