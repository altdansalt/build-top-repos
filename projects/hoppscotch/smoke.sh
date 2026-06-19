#!/bin/sh
# Black-box smoke: run the hopp CLI (built from packages/hoppscotch-cli) with
# --ver (the version flag) and --help to confirm the CLI loads and exits cleanly.
# isolated-vm is not needed: --ver exits before any sandbox code runs, and the
# default sandbox (faraday-cage/QuickJS) is pure JS/WASM.
set -e

HOPP="$PROJECT/packages/hoppscotch-cli/bin/hopp.js"

# --ver prints the version string (e.g. 0.31.2) and exits 0
ver=$(node "$HOPP" --ver 2>&1)
echo "hopp version: $ver"
test -n "$ver"

# --help should show the test command in the usage output
node "$HOPP" --help 2>&1 | grep -q "test"

echo "HOPPSCOTCH_CLI_SMOKE_OK version=$ver"
