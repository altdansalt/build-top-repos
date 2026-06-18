#!/bin/sh
# Black-box smoke: bundle a trivial two-file JS project via webpack's JS API
# (no webpack-cli dependency) and verify the bundle runs correctly.
# $PROJECT = restored build tree (lib/ + node_modules/ + bin/).
set -e

d=$(mktemp -d)

# Simple module to import
cat > "$d/msg.js" << 'JSEOF'
module.exports = 'WEBPACK_SMOKE_OK';
JSEOF

# Entry point that imports the module
cat > "$d/entry.js" << 'JSEOF'
const msg = require('./msg');
console.log(msg);
JSEOF

# Bundle script: use webpack's JS API via environment variables to avoid
# shell quoting issues with embedded paths.
cat > "$d/run-webpack.js" << 'JSEOF'
"use strict";
const webpack = require(process.env.WEBPACK_PROJECT);
const path = require("path");
const entry = process.env.ENTRY;
const outDir = process.env.OUT_DIR;

webpack(
  {
    mode: "production",
    entry: entry,
    output: { path: outDir, filename: "bundle.js" },
    devtool: false,
  },
  (err, stats) => {
    if (err) {
      process.stderr.write(String(err) + "\n");
      process.exit(1);
    }
    if (stats.hasErrors()) {
      process.stderr.write(stats.toString("errors-only") + "\n");
      process.exit(1);
    }
    process.stdout.write("bundle written to " + outDir + "\n");
  }
);
JSEOF

mkdir -p "$d/dist"
WEBPACK_PROJECT="$PROJECT" ENTRY="$d/entry.js" OUT_DIR="$d/dist" \
  node "$d/run-webpack.js"

# Verify and execute the bundle
test -f "$d/dist/bundle.js"
node "$d/dist/bundle.js" | grep -F 'WEBPACK_SMOKE_OK'
echo "WEBPACK_SMOKE_OK"
