# HTTP quine

One file that is a Windows executable, a Linux/macOS executable, and an HTML
page. Run it and it starts an HTTP server on `127.0.0.1:8080` that serves
its own bytes as `text/html`. Built on Justine Tunney's Cosmopolitan Libc
(Actually Portable Executable format).

```
./setup-toolchain.sh   # once: downloads cosmocc 4.0.2 into ./cosmocc (~420 MB)
./build.sh             # -> dist/quine.exe (~230 KB)
./test.sh              # runs it, curls it, checks body == file
```

## Files

- `quine.c` – the whole server, 25 lines of POSIX C. Reads its own file once
  via `GetProgramExecutableName()`, then loops: accept, one `read()` to drain
  the request, write `HTTP/1.0 200 OK` + `Content-Type`, write the file, close.
  No parsing, no threads, no Content-Length (HTTP/1.0 close delimits the body).
- `page.html` – the visible page, appended to the binary by `build.sh`.
- `build.sh` – compile with `cosmocc -mtiny -Os`, write `<!--` over bytes 8..11
  of the DOS header, append `-->` + `page.html`, then verify with `pecheck`
  and an HTML parse. `ARCH=x86_64 ./build.sh` gives a smaller x86-only file
  that does not run natively on Apple Silicon.

## How the polyglot holds together

- Offset 0 must be `MZ` for Windows; ELF and Mach-O also demand offset 0, so
  only Windows gets a native header. On Unix the kernel rejects the file, the
  shell interprets it as a script (the header `MZqFpD='` opens a shell string,
  a heredoc swallows the binary), and the script execs an embedded ELF loader.
- The browser renders `MZqFpD='` as text, then everything up to the appended
  `-->` is one HTML comment. A script at the top of `page.html` removes both
  nodes before the page renders. The binary must never contain `-->` or
  `--!>`; `build.sh` checks this.
- That leading text makes the parser open `<body>` before `page.html` starts,
  so `page.html` has no doctype, `<html>`, `<head>` or `<body>` tags (they
  would be ignored). The same script sets `lang`, the title and the viewport
  meta instead. The page always renders in quirks mode.
- The `<!--` goes at offset 9, not 8. bash and zsh only run an ENOEXEC file as
  a script if a line with a lowercase letter ends before the first NUL byte,
  so the newline after `MZqFpD='` has to survive. Overwriting it makes
  `./quine.exe` fail with "exec format error" on every Unix shell.
- Serve with `charset=utf-8` in the header, since a `<meta charset>` cannot
  be within the first 1024 bytes of the file.

## Deploying (quine.ruphin.net)

```
./deploy.sh root@ruphin.net
```

Installs `dist/quine.exe` and the standalone APE loader to `/opt/quine` and
runs it as the `quine` systemd service, bound to `127.0.0.1:8080`, as a
dynamic unprivileged user with a read-only filesystem. The unit execs the
loader with the file as argument because the kernel cannot exec an APE
directly. The installed file is never assimilated: it is the file that gets
served, so it has to stay the untouched polyglot.

The public side is redbean in the ruphin.net repo: `src/.lua/quine.lua`
fetches `http://127.0.0.1:8080/` on every request for `quine.ruphin.net` and
passes the body through with a `Via: 1.1 redbean` header. Nothing is cached,
so every response still comes from the quine process. Steps on that side:
add a DNS record for `quine.ruphin.net`, `./build.sh pack`, `./build.sh deploy
root@ruphin.net`, then `./build.sh cert root@ruphin.net` to expand the
certificate.

## Platform notes

- **Windows**: native. Keep the `.exe` extension.
- **Linux / BSD**: needs dash, bash, or zsh 5.9+. First run extracts a 4 KB
  loader to `$TMPDIR/.ape-1.10` (or `$HOME`). The file itself is not modified.
- **macOS x86-64**: works as is. **Apple Silicon**: the loader must be compiled
  locally because of code signing, so Xcode Command Line Tools are required
  (`xcode-select --install`). Downloaded files also need the quarantine
  attribute cleared before they will run.
- **WSL**: with interop enabled, `./dist/quine.exe` is sent to Windows. Use
  `sh dist/quine.exe` or `cosmocc/bin/ape-x86_64.elf dist/quine.exe` instead.

Verified: Linux (loader and shell paths) and native Windows serve the file
byte-identical, and the shell bootstrap runs it on Apple Silicon (M4, with
the Xcode Command Line Tools installed). macOS x86-64 untested.
