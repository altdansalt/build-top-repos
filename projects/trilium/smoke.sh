#!/bin/sh
# Black-box smoke: start the Trilium server (dist/main.cjs), wait for the
# /api/health-check endpoint to return HTTP 200, then kill the server.
# The health-check route requires no auth and works without the built client
# frontend. $PROJECT = restored build tree.
set -e

DATA_DIR=$(mktemp -d)
export TRILIUM_DATA_DIR="$DATA_DIR"
export TRILIUM_PORT=3000

node "$PROJECT/apps/server/dist/main.cjs" >"$DATA_DIR/srv.log" 2>&1 &
SRV=$!

# Server initialises the SQLite database (schema + demo import) before
# starting HTTP, so allow up to 90 s for it to become ready.
i=0
while ! node -e "require('http').get('http://127.0.0.1:3000/api/health-check',function(r){process.exit(r.statusCode===200?0:1)}).on('error',function(){process.exit(1)})" 2>/dev/null; do
  i=$((i+1))
  if [ $i -gt 90 ]; then
    echo "TIMEOUT: Trilium server did not start within 90s" >&2
    cat "$DATA_DIR/srv.log" >&2
    kill "$SRV" 2>/dev/null || true
    exit 1
  fi
  if ! kill -0 "$SRV" 2>/dev/null; then
    echo "ERROR: Trilium server process exited early" >&2
    cat "$DATA_DIR/srv.log" >&2
    exit 1
  fi
  sleep 1
done

kill "$SRV" 2>/dev/null || true
echo "TRILIUM_SMOKE_OK"
