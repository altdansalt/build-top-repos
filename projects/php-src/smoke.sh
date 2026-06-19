#!/bin/sh
# Black-box smoke: run the built PHP CLI interpreter. $PROJECT = built tree.
set -e
cd "$PROJECT"
sapi/cli/php --version
test "$(sapi/cli/php -r 'echo 2 + 2;')" = "4"
test "$(sapi/cli/php -r 'echo strtoupper("hello");')" = "HELLO"
echo PHP_SMOKE_OK
