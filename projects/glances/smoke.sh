#!/bin/sh
# Black-box smoke: run the glances CLI — version + a one-shot non-interactive
# CPU reading (its core job). $PROJECT = restored tree (with the .venv).
set -e
G="$PROJECT/.venv/bin/glances"
"$G" --version
"$G" --stdout cpu.total --stop-after 1 | grep -q 'cpu.total'
echo GLANCES_SMOKE_OK
