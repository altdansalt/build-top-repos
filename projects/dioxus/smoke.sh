#!/bin/sh
# Black-box smoke: run the built dx CLI (version + help). $PROJECT = built tree.
set -e
B="$PROJECT/target/debug/dx"
"$B" --version
"$B" --help >/dev/null
echo DIOXUS_SMOKE_OK
