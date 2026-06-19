#!/bin/sh
# Black-box smoke: run the built podman CLI (version + help).
# Built as the remote-client variant; --version and --help exit before
# contacting any daemon. $PROJECT = built tree.
set -e
cd "$PROJECT"
./podman --version
./podman --help >/dev/null
echo PODMAN_SMOKE_OK
