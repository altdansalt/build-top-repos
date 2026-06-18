#!/bin/sh
# Black-box smoke: run the built GitHub CLI (version + help). $PROJECT = built tree.
set -e
cd "$PROJECT"
./gh --version
./gh --help >/dev/null
echo GH_SMOKE_OK
