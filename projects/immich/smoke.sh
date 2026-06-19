#!/bin/sh
# Black-box smoke: run the built immich CLI — version check then help listing.
# $PROJECT = restored build tree (packages/cli/dist/index.js bundled by vite 8).
set -e

IMMICH_BIN="$PROJECT/packages/cli/bin/immich"

# --version prints the semver string and exits 0
ver=$(node "$IMMICH_BIN" --version 2>&1)
echo "immich version: $ver"
test -n "$ver"

# --help should show the upload command (core CLI subcommand)
node "$IMMICH_BIN" --help 2>&1 | grep -q "upload"

echo "IMMICH_SMOKE_OK version=$ver"
