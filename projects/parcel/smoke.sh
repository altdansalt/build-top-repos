#!/bin/sh
# Black-box smoke for parcel (zero-config web bundler).
# $PROJECT = restored build tree (monorepo + node_modules).
# The parcel CLI (src/bin.js) auto-loads @parcel/babel-register in dev mode,
# so it runs from source. @parcel/rust-linux-x64-gnu provides the prebuilt
# Rust native module (installed as an optional dep during yarn install).
set -e

# 1. Verify the CLI loads and prints a version.
node "$PROJECT/node_modules/.bin/parcel" --version

# 2. Bundle a trivial Node.js project and execute the output.
d=$(mktemp -d)

cat > "$d/index.js" << 'JSEOF'
console.log('PARCEL_SMOKE_OK');
JSEOF

cat > "$d/package.json" << 'JSONEOF'
{
  "name": "smoke",
  "version": "1.0.0",
  "targets": {
    "main": {
      "context": "node",
      "outputFormat": "commonjs"
    }
  },
  "main": "dist/index.js",
  "source": "index.js"
}
JSONEOF

cd "$d"
node "$PROJECT/node_modules/.bin/parcel" build --no-cache 2>&1 | tail -5
node dist/index.js | grep -F 'PARCEL_SMOKE_OK'
echo 'PARCEL_SMOKE_OK bundle verified'
