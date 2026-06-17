#!/bin/sh
# Black-box smoke: run the built starship binary — version + render a prompt
# (its core job). $PROJECT = built tree.
set -e
BIN="$PROJECT/target/debug/starship"
"$BIN" --version
# Render a prompt for a temp dir; just needs to succeed and print something.
out=$(cd /tmp && "$BIN" prompt)
test -n "$out"
echo STARSHIP_SMOKE_OK
