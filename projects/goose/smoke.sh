#!/bin/sh
# Black-box smoke: run the built goose CLI (version + help). $PROJECT = built tree.
set -e
BIN="$PROJECT/target/debug/goose"
"$BIN" --version
"$BIN" --help >/dev/null
echo GOOSE_SMOKE_OK
