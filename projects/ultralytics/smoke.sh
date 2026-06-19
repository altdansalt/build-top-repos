#!/bin/sh
# Black-box smoke: run the ultralytics yolo CLI as an end user would.
# libGL/libGLdispatch are bundled in $PROJECT/.libs/ (captured at build time)
# so the restored container needs no apt-get update inside the 300s timeout.
# $PROJECT = restored build tree (with .venv and .libs/).
set -e

export LD_LIBRARY_PATH="$PROJECT/.libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
YOLO="$PROJECT/.venv/bin/yolo"

"$YOLO" --version
"$YOLO" --help >/dev/null
echo ULTRALYTICS_SMOKE_OK
