#!/bin/sh
# Black-box smoke: verify the ecc CLI starts correctly and can list its
# available commands and component catalog. $PROJECT = restored build tree.
set -e

# Top-level help shows all sub-commands (exits 0).
node "$PROJECT/scripts/ecc.js" --help

# catalog sub-command lists available profiles and component IDs (local read).
node "$PROJECT/scripts/ecc.js" catalog

echo "ECC_SMOKE_OK"
