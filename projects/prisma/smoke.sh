#!/bin/sh
# Black-box smoke: verify the built prisma CLI works without a database.
# $PROJECT = restored build tree (packages/ + node_modules/).
set -e

cd "$PROJECT"

# Help listing — exercises CLI init and argument parsing; no engine/DB needed.
node packages/cli/build/index.js --help

# Version — reports prisma + @prisma/client versions and the detected platform.
node packages/cli/build/index.js version

echo "PRISMA_SMOKE_OK"
