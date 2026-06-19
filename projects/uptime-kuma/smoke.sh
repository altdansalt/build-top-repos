#!/bin/sh
# Black-box smoke: start the uptime-kuma Node.js server, wait for HTTP on port
# 3001, confirm a response is received, then kill it.
# $PROJECT = restored build tree (Node.js backend + node_modules + built dist/).
set -e

DATA_DIR=$(mktemp -d)
export DATA_DIR
export PORT=3001

node "$PROJECT/server/server.js" >"$DATA_DIR/srv.log" 2>&1 &
SRV=$!

# Wait up to 60s for the server to accept HTTP connections
i=0
while ! node -e "require('http').get('http://127.0.0.1:3001/',r=>process.exit(0)).on('error',()=>process.exit(1))" 2>/dev/null; do
  i=$((i+1))
  if [ $i -gt 60 ]; then
    echo "TIMEOUT: server did not start in 60s" >&2
    cat "$DATA_DIR/srv.log" >&2
    kill "$SRV" 2>/dev/null || true
    exit 1
  fi
  if ! kill -0 "$SRV" 2>/dev/null; then
    echo "Server process exited early" >&2
    cat "$DATA_DIR/srv.log" >&2
    exit 1
  fi
  sleep 1
done

kill "$SRV" 2>/dev/null || true
echo "UPTIME_KUMA_SMOKE_OK"
