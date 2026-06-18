#!/bin/sh
# Black-box smoke: run the built xray CLI (version + help). $PROJECT = built tree.
set -e
cd "$PROJECT"
./xray version
./xray help >/dev/null 2>&1 || true
echo XRAY_SMOKE_OK
