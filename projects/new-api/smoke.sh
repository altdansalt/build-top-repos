#!/bin/sh
# Black-box smoke: new-api is a Go AI model gateway with --version/--help flags
# declared via flag.Bool() in common/init.go; both exit cleanly without a DB or network.
# $PROJECT = restored build tree.
set -e

"$PROJECT/new-api" --version
"$PROJECT/new-api" --help
echo "NEW_API_SMOKE_OK"
