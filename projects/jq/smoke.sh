#!/bin/sh
# Black-box smoke: run the built jq binary on real filters. $PROJECT = built tree.
set -e
cd "$PROJECT"
./jq --version
test "$(echo '{"foo":42}' | ./jq '.foo')" = "42"
test "$(echo '[1,2,3]' | ./jq 'add')" = "6"
echo JQ_SMOKE_OK
