#!/bin/sh
# Black-box smoke: run the built syncthing daemon binary (version). $PROJECT = built tree.
set -e
cd "$PROJECT"
./syncthing --version
echo SYNCTHING_SMOKE_OK
