#!/bin/sh
# Black-box smoke: run the built Bevy headless example.
# The example runs a one-shot app (prints "hello world") then enters a 60fps
# loop forever; we kill it after 15s and verify we got the expected output.
set -e
B="$PROJECT/target/debug/examples/headless"
output=$(timeout 15 "$B" 2>&1 || true)
echo "$output"
printf '%s' "$output" | grep -q "hello world"
echo BEVY_SMOKE_OK
