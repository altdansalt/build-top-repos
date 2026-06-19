#!/bin/sh
# Black-box smoke: run the built whisper-cli binary. $PROJECT = built tree.
# Full inference needs a model file; --help works without one.
set -e
cd "$PROJECT"

./build/bin/whisper-cli --help > /tmp/wc_help.txt 2>&1 || true
grep -qi "whisper\|usage\|model" /tmp/wc_help.txt

echo WHISPER_CPP_SMOKE_OK
