#!/bin/sh
# Black-box smoke: run the built rtk CLI (version + help). $PROJECT = built tree.
set -e
B="$PROJECT/target/debug/rtk"
"$B" --version
"$B" --help >/dev/null
echo RTK_SMOKE_OK
