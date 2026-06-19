#!/bin/sh
# Black-box smoke: run the built wifi-densepose CLI. $PROJECT = built tree.
set -e
B="$PROJECT/v2/target/debug/wifi-densepose"
"$B" --version
"$B" --help >/dev/null
echo RUVIEW_SMOKE_OK
