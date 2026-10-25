#!/bin/sh
# Install dist/quine.exe on a Linux host as the "quine" systemd service.
#
#   ./deploy.sh root@ruphin.net
#
# The service listens on 127.0.0.1:8080 only. On ruphin.net, redbean proxies
# https://quine.ruphin.net/ to it (see src/.lua/quine.lua in the ruphin.net repo).
#
# The installed file must stay the untouched APE, because it is the file that
# gets served and downloaded. Never run --assimilate on it: that rewrites the
# header to ELF, which breaks the Windows side and the HTML comment opener.
set -eu
cd "$(dirname "$0")"
TARGET=${1:?usage: $0 user@host}
INSTALL_DIR=/opt/quine
FILE=quine.exe
PORT=8080

[ -f dist/$FILE ] || ./build.sh

unit() {
cat <<EOF
[Unit]
Description=HTTP quine (serves its own executable on 127.0.0.1:${PORT})
After=network-online.target
Wants=network-online.target

[Service]
# The kernel cannot exec an APE directly. The shell bootstrap inside the file
# extracts a small loader to \$TMPDIR/.ape-* on first start and execs it, so
# TMPDIR points at the state directory, the only writable place under
# ProtectSystem=strict.
ExecStart=/bin/sh ${INSTALL_DIR}/${FILE}
DynamicUser=yes
StateDirectory=quine
WorkingDirectory=%S/quine
Environment=TMPDIR=%S/quine
ProtectSystem=strict
ProtectHome=yes
PrivateDevices=yes
NoNewPrivileges=yes
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF
}

# Refuse to install over something else listening on the port
ssh "$TARGET" sh -s <<EOF
set -e
if ss -Hltn 2>/dev/null | grep -q ':${PORT} ' && ! systemctl is-active --quiet quine; then
    echo "127.0.0.1:${PORT} is in use by something other than the quine service"; exit 1
fi
mkdir -p ${INSTALL_DIR}
EOF

scp dist/$FILE "$TARGET:${INSTALL_DIR}/${FILE}.new"
unit | ssh "$TARGET" "cat > /etc/systemd/system/quine.service"
ssh "$TARGET" sh -s <<EOF
set -e
chmod 755 ${INSTALL_DIR}/${FILE}.new
mv -f ${INSTALL_DIR}/${FILE}.new ${INSTALL_DIR}/${FILE}
systemctl daemon-reload
systemctl enable quine
systemctl restart quine
sleep 2
systemctl --no-pager status quine | head -n 3
if command -v curl >/dev/null; then
    curl -s -o /tmp/quine.check -w 'local check: HTTP %{http_code}, %{size_download} bytes\n' http://127.0.0.1:${PORT}/
    cmp -s /tmp/quine.check ${INSTALL_DIR}/${FILE} && echo 'served body is identical to the installed file' || echo 'WARNING: served body differs from the installed file'
    rm -f /tmp/quine.check
fi
EOF
