#!/bin/sh
# Black-box smoke: verify the 3x-ui binary runs headlessly.
# 3x-ui is a web panel server; -v exits cleanly without a DB or network.
# $PROJECT = restored build tree.
set -e

"$PROJECT/3x-ui" -v
echo "3X_UI_SMOKE_OK"
