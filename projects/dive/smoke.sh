#!/bin/sh
# Black-box smoke: run the built dive binary as a user would — analyze a real
# Docker image tarball (the repo's own fixture) into a JSON report, no daemon.
# $PROJECT = restored build tree (has divebin + .data/ fixtures).
set -e
cd "$PROJECT"
./divebin --version
./divebin --source docker-archive .data/test-docker-image.tar --json /tmp/dive-smoke.json
test -s /tmp/dive-smoke.json
echo "DIVE_SMOKE_OK ($(wc -c < /tmp/dive-smoke.json) bytes of analysis)"
