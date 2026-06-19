#!/bin/sh
# Black-box smoke: run the built Continue CLI with --version and --help.
# $PROJECT = restored build tree (extensions/cli/dist/cn.js bundled by esbuild).
# Both flags exit cleanly without a Continue API key or network access.
set -e

CN="$PROJECT/extensions/cli/dist/cn.js"

# --version prints the semver from extensions/cli/package.json and exits 0
ver=$(node "$CN" --version 2>&1)
echo "continue (cn) version: $ver"
test -n "$ver"

# --help should list the available commands (chat, ls, serve, checks, review)
node "$CN" --help 2>&1 | grep -q "chat\|serve\|AI-powered"

echo "CONTINUE_SMOKE_OK version=$ver"
