#!/bin/sh
# Black-box smoke: start the built redis-server and exercise it with redis-cli
# (ping + set/get) — a real end-to-end run. $PROJECT = built tree.
set -e
cd "$PROJECT"
./src/redis-server --version
./src/redis-server --port 7777 --save "" --appendonly no &
SRV=$!
i=0; while ! ./src/redis-cli -p 7777 ping 2>/dev/null | grep -q PONG; do i=$((i+1)); [ $i -gt 30 ] && exit 1; sleep 0.3; done
./src/redis-cli -p 7777 set foo bar >/dev/null
test "$(./src/redis-cli -p 7777 get foo)" = "bar"
./src/redis-cli -p 7777 shutdown nosave 2>/dev/null || kill "$SRV" 2>/dev/null
echo REDIS_SMOKE_OK
