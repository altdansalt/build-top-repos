#!/bin/sh
# Black-box smoke: run the built fish shell binary — version + execute a command.
# $PROJECT = built tree.
set -e
FISH="$PROJECT/target/debug/fish"
"$FISH" --version
"$FISH" -c 'echo fish_smoke_ok'
echo FISH_SMOKE_OK
