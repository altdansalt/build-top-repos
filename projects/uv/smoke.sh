#!/bin/sh
# Black-box smoke: run the built uv CLI (version + help). $PROJECT = built tree.
set -e
U="$PROJECT/target/debug/uv"
"$U" --version
"$U" --help >/dev/null
"$U" pip --help >/dev/null
echo UV_SMOKE_OK
