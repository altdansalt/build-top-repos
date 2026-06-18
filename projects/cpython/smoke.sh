#!/bin/sh
# Black-box smoke: run the freshly built CPython interpreter. $PROJECT = built tree.
set -e
cd "$PROJECT"
./python --version
test "$(./python -c 'print(sum(range(10)))')" = "45"
echo CPYTHON_SMOKE_OK
