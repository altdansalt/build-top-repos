#!/bin/sh
# Black-box smoke: run the built ruff linter (version + lint a clean snippet -> no
# findings, exit 0). $PROJECT = built tree.
set -e
R="$PROJECT/target/debug/ruff"
"$R" --version
printf 'x = 1\n' | "$R" check --isolated --stdin-filename ok.py -
echo RUFF_SMOKE_OK
