#!/bin/sh
# Black-box smoke: run the scrapy CLI — version + scaffold a new project (a real
# end-user action). $PROJECT = restored tree (with the .venv).
set -e
S="$PROJECT/.venv/bin/scrapy"
"$S" version
d=$(mktemp -d)
cd "$d"
"$S" startproject smk >/dev/null
test -f smk/scrapy.cfg
echo SCRAPY_SMOKE_OK
