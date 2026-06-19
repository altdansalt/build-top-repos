#!/bin/sh
# Black-box smoke: verify the Meteor CLI (dev_bundle/bin/node + tools/index.js).
# $PROJECT = restored build tree (source + dev_bundle/ + tools/).
#
# --arch always exits 0 from a git checkout (unlike --version which exits 1).
# It executes the full tool bootstrap path: Babel setup, main.js, archinfo.ts.
set -e

arch=$(METEOR_ALLOW_SUPERUSER=1 "$PROJECT/meteor" --arch)
echo "meteor --arch: $arch"
printf '%s\n' "$arch" | grep -E '^os\.linux\.'
echo "METEOR_ARCH_OK"
