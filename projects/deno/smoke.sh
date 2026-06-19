#!/bin/sh
# Black-box smoke: run the built deno binary and execute a trivial JS snippet.
# $PROJECT = built tree (restored artifact).
set -e
B="$PROJECT/target/debug/deno"
"$B" --version
"$B" eval 'console.log("DENO_SMOKE_OK")'
