#!/bin/sh
# Black-box smoke: run the built sing-box CLI (version + help). $PROJECT = built tree.
set -e
cd "$PROJECT"
./sing-box version
./sing-box --help >/dev/null
echo SINGBOX_SMOKE_OK
