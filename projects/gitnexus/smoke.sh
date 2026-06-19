#!/bin/sh
# Black-box smoke: run the built gitnexus CLI — version check then help listing.
# $PROJECT = restored build tree; CLI is at gitnexus/dist/cli/index.js.
set -e

CLI="$PROJECT/gitnexus/dist/cli/index.js"

# --version prints the semver string (from package.json) and exits 0
ver=$(node "$CLI" --version 2>&1)
echo "gitnexus version: $ver"
test -n "$ver"

# --help should mention the analyze command (core CLI subcommand)
node "$CLI" --help 2>&1 | grep -q "analyze"

echo "GITNEXUS_SMOKE_OK version=$ver"
