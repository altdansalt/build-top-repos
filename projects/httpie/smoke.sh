#!/bin/sh
# Black-box smoke: run the installed httpie CLI. --offline builds a real request
# (method, headers) with no network -> deterministic. $PROJECT = restored tree.
set -e
"$PROJECT/.venv/bin/http" --version
"$PROJECT/.venv/bin/http" --help >/dev/null
"$PROJECT/.venv/bin/http" --offline GET example.com >/dev/null
echo HTTPIE_SMOKE_OK
