#!/bin/sh
# Black-box smoke: run the built llama-cli binary. $PROJECT = built tree.
# Full inference needs a GGUF model file; --help works without one.
set -e
cd "$PROJECT"

./build/bin/llama-cli --help > /tmp/llama_help.txt 2>&1 || true
grep -qi "llama\|model\|usage" /tmp/llama_help.txt

echo LLAMA_CPP_SMOKE_OK
