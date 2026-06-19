#!/bin/sh
# Black-box smoke: verify the one-api binary can be invoked headlessly.
# one-api is a web server; --version and --help exit cleanly without a DB or network.
# $PROJECT = restored build tree.
set -e

"$PROJECT/one-api" --version
"$PROJECT/one-api" --help
echo "ONE_API_SMOKE_OK"
