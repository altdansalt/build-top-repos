#!/bin/sh
# Black-box smoke: run the built helix (hx) binary — version + help.
# $PROJECT = built tree.
set -e
HX="$PROJECT/target/debug/hx"
"$HX" --version
"$HX" --help >/dev/null 2>&1
echo HELIX_SMOKE_OK
