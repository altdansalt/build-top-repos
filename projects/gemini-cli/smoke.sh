#!/bin/sh
# Black-box smoke: run the built gemini CLI with --version and --help.
# $PROJECT = restored build tree (node_modules + packages/*/dist/).
# The CLI requires a Gemini API key for interactive AI operations; --version
# and --help exit cleanly without any authentication or network access.
set -e

node "$PROJECT/packages/cli/dist/index.js" --version
node "$PROJECT/packages/cli/dist/index.js" --help > /dev/null

echo "GEMINI_CLI_SMOKE_OK"
