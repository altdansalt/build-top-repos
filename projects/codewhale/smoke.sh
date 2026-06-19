#!/bin/sh
# Black-box smoke: run the built codewhale CLI (version + help). $PROJECT = built tree.
# libdbus-1 and its runtime deps are bundled in $PROJECT/.libs/ (captured at build
# time) so the smoke container needs no apt-get update inside the 300s timeout.
set -e
export LD_LIBRARY_PATH="$PROJECT/.libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
B="$PROJECT/target/debug/codewhale"
"$B" --version
"$B" --help >/dev/null
echo CODEWHALE_SMOKE_OK
