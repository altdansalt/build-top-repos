#!/bin/sh
# Black-box smoke: use the built zx CLI as a user would — print its version and
# run a real zx script that shells out. $PROJECT = restored build tree (build/ +
# node_modules). Needs Node 24 (zx's CLI auto-run uses import.meta.main).
set -e
node "$PROJECT/build/cli.js" --version
echo 'await $`echo ZX_SMOKE_OK`' > /tmp/zx-smoke.mjs
node "$PROJECT/build/cli.js" /tmp/zx-smoke.mjs
