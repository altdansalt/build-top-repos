#!/bin/sh
# Black-box smoke: run the built btop binary. It's a full-screen TUI, so we
# exercise the non-interactive paths (version + help). $PROJECT = built tree.
set -e
cd "$PROJECT"
./bin/btop --version
./bin/btop --help >/dev/null
echo BTOP_SMOKE_OK
