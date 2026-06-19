#!/bin/sh
# Black-box smoke: run freqtrade CLI (version + help) — exercises the console
# entry point and the full import graph (pandas, numpy, ta-lib, ccxt, ...).
# $PROJECT = restored build tree (with the .venv).
set -e
FT="$PROJECT/.venv/bin/freqtrade"
"$FT" --version
"$FT" --help >/dev/null
echo FREQTRADE_SMOKE_OK
