#!/bin/sh
# Black-box smoke: minify a snippet through the esbuild CLI (its job).
# $PROJECT = built tree.
set -e
cd "$PROJECT"
./esbuild --version
out=$(printf 'let x = 1 ;\n' | ./esbuild --minify)
test "$out" = "let x=1;"
echo ESBUILD_SMOKE_OK
