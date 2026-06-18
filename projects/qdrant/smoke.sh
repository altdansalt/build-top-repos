#!/bin/sh
# Black-box smoke: run the built qdrant server binary (version + help).
# $PROJECT = built tree.
set -e
B="$PROJECT/target/debug/qdrant"
"$B" --version
"$B" --help >/dev/null
echo QDRANT_SMOKE_OK
