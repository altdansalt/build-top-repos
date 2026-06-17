#!/bin/sh
# Black-box smoke: run the installed thefuck CLI (version + help). Exercises the
# console entry point and the full rule/import graph. $PROJECT = restored tree.
set -e
"$PROJECT/.venv/bin/thefuck" --version
"$PROJECT/.venv/bin/thefuck" --help >/dev/null
echo THEFUCK_SMOKE_OK
