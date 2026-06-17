#!/bin/sh
# Black-box smoke: run the built rustlings CLI as a user would (version + help).
# Exercises the clap entry point and the embedded exercise data. $PROJECT =
# restored build tree (has target/debug/rustlings).
set -e
"$PROJECT/target/debug/rustlings" --version
"$PROJECT/target/debug/rustlings" --help >/dev/null
echo RUSTLINGS_SMOKE_OK
