#!/bin/sh
# Black-box smoke: run the installed sherlock CLI as a user would. --version and
# --help exercise the console entry point + the full import graph (pandas,
# requests, ...). $PROJECT = restored build tree (with the .venv).
set -e
"$PROJECT/.venv/bin/sherlock" --version
"$PROJECT/.venv/bin/sherlock" --help >/dev/null
echo SHERLOCK_SMOKE_OK
