#!/bin/sh
# Black-box smoke: run the @tooljet/cli built from cli/.
# $PROJECT = restored build tree (cli/dist/ + cli/node_modules/).
set -e

# oclif --version: outputs "@tooljet/cli/<ver> <platform>-<arch> node-v<ver>"
node "$PROJECT/cli/bin/run" --version

# info command: prints OS platform/arch, Node.js version, npm version
out=$(node "$PROJECT/cli/bin/run" info 2>&1)
echo "$out"
echo "$out" | grep -q "node:"

echo "TOOLJET_SMOKE_OK"
