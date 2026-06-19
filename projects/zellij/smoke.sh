#!/bin/sh
# Black-box smoke: run the built zellij binary — version + help.
# $PROJECT = built tree.
set -e
BIN="$PROJECT/target/debug/zellij"
"$BIN" --version
"$BIN" --help >/dev/null 2>&1
echo ZELLIJ_SMOKE_OK
