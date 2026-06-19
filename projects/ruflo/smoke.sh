#!/bin/sh
# Black-box smoke: verify the ruflo CLI starts and can show version and help.
# $PROJECT = restored build tree (v3/@claude-flow/cli compiled; node_modules present).
set -e

# --version: fast path in v3/@claude-flow/cli/bin/cli.js — reads package.json
# directly, no dist import needed. Confirms the bin is intact and Node runs it.
node "$PROJECT/bin/cli.js" --version | tee /tmp/ruflo_version.txt
grep -E '^ruflo v[0-9]' /tmp/ruflo_version.txt

# --help: loads dist/src/index.js (compiled TypeScript). Exercises the full
# CLI boot: log-filters, command registry with lazy loaders, parser, output.
# No LLM/network calls happen here; update check fires async and is non-blocking.
node "$PROJECT/bin/cli.js" --help 2>/dev/null | head -20

echo "RUFLO_SMOKE_OK"
