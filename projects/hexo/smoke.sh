#!/bin/sh
# Black-box smoke: run the built hexo CLI — version check then help listing.
# $PROJECT = restored build tree (node_modules + dist/).
set -e

# Version prints hexo version plus system info
node "$PROJECT/bin/hexo" version

# Help lists available commands
node "$PROJECT/bin/hexo" help

echo "HEXO_SMOKE_OK"
