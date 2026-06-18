#!/bin/sh
# Black-box smoke: run the yt-dlp CLI (version + help). $PROJECT = restored tree.
set -e
Y="$PROJECT/.venv/bin/yt-dlp"
"$Y" --version
"$Y" --help >/dev/null
echo YTDLP_SMOKE_OK
