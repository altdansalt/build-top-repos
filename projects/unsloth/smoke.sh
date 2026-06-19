#!/bin/sh
# Black-box smoke: exercise the unsloth CLI at the help layer.
# Full use requires GPU + torch + transformers — not available here.
# The CLI defers all heavy imports to when commands are actually invoked,
# so --version and --help work without torch installed.
# $PROJECT = restored tree (with the .venv).
set -e
UNSLOTH="$PROJECT/.venv/bin/unsloth"

"$UNSLOTH" --version
"$UNSLOTH" --help

echo UNSLOTH_SMOKE_OK
