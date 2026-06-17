#!/usr/bin/env bash
# Assemble a cached toolchain rootfs tarball: ubuntu-base + CA bundle + a set of
# apt packages baked in via one apt pass against the pinned snapshot mirror, plus
# an optional language tarball overlaid at /opt/node. Run by a genrule, so Bazel
# caches the result keyed on the pinned inputs + this script + the package list.
#
# Usage: assemble_toolchain.sh <crun> <gen_config.py> <cacert.pem> <ubuntu_base.tgz> \
#                              <out.tgz> "<apt packages>" [node.txz]
set -euo pipefail

CRUN="$(realpath "$1")"
GENCFG="$(realpath "$2")"
CACERT="$(realpath "$3")"
UBUNTU="$(realpath "$4")"
OUT="$5"
APT_PKGS="$6"
NODE="${7:-}"

# Pinned apt snapshot: reproducible to this date (apt also GPG-verifies).
SNAPSHOT="20260601T000000Z"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/rootfs"
mkdir -p "$ROOT" "$WORK/out" "$ROOT/out"

tar -xzf "$UBUNTU" -C "$ROOT"
if [ -n "$NODE" ]; then
  NODE="$(realpath "$NODE")"
  mkdir -p "$ROOT/opt/node"
  tar -xJf "$NODE" -C "$ROOT/opt/node" --strip-components=1
fi
mkdir -p "$ROOT/etc/ssl/certs"
cp "$CACERT" "$ROOT/etc/ssl/certs/ca-certificates.crt"
cp /etc/resolv.conf "$ROOT/etc/resolv.conf"

echo 'APT::Sandbox::User "root";' > "$ROOT/etc/apt/apt.conf.d/00sandbox"
cat > "$ROOT/etc/apt/sources.list.d/ubuntu.sources" <<EOF
Types: deb
URIs: https://snapshot.ubuntu.com/ubuntu/$SNAPSHOT
Suites: noble noble-updates noble-security
Components: main universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

# One apt pass to bake the requested packages, then tar the rootfs from *inside*
# the container (as container-root, so files owned by mapped sub-ids are
# readable). tar exits 1 on the benign "file changed as we read it"; tolerate <=1.
INNER="set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq $APT_PKGS
apt-get clean
rm -rf /var/lib/apt/lists/*
tar -czf /out/toolchain.tgz --exclude='./out/*' --exclude='./proc/*' --exclude='./sys/*' --exclude='./dev/*' -C / . ; rc=\$?; [ \$rc -le 1 ] || exit \$rc
echo BAKE_DONE"

ARGS_JSON="$(python3 -c 'import json,sys; print(json.dumps(["/bin/sh","-c",sys.argv[1]]))' "$INNER")"
MNT_JSON="$(python3 -c 'import json,sys; print(json.dumps([{"destination":"/out","type":"bind","source":sys.argv[1],"options":["bind","rw"]}]))' "$WORK/out")"
python3 "$GENCFG" "$CRUN" "$WORK" "/" "$ARGS_JSON" "$MNT_JSON"
"$CRUN" --root "$WORK/state" run -b "$WORK" toolchain-build

mv "$WORK/out/toolchain.tgz" "$OUT"
