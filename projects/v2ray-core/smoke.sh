#!/bin/sh
# Black-box smoke: run the built v2ray CLI (version + help). $PROJECT = built tree.
set -e
cd "$PROJECT"
./v2ray version
./v2ray help >/dev/null 2>&1 || true
echo V2RAY_SMOKE_OK
