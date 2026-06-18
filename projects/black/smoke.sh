#!/bin/sh
# Black-box smoke: run black on a snippet (its job) — `x=1` should format to
# `x = 1`. $PROJECT = restored tree (with the .venv).
set -e
B="$PROJECT/.venv/bin/black"
"$B" --version
out=$(printf 'x=1\n' | "$B" -)
test "$out" = "x = 1"
echo BLACK_SMOKE_OK
