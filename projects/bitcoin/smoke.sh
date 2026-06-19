#!/bin/sh
# Black-box smoke: run the built Bitcoin Core binaries. $PROJECT = built tree.
# Binaries land in build/bin/ via CMake's CMAKE_RUNTIME_OUTPUT_DIRECTORY.
# Runtime libevent libs bundled in .libs/ at build time; set LD_LIBRARY_PATH.
set -e
cd "$PROJECT"

export LD_LIBRARY_PATH="$PROJECT/.libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

./build/bin/bitcoind --version
./build/bin/bitcoin-cli --version

echo BITCOIN_SMOKE_OK
