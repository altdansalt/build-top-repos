#!/bin/sh
# Black-box smoke: verify the built Babel CLI and core transform work.
# $PROJECT = restored build tree (node_modules/ + packages/*/lib/).
set -e

cd "$PROJECT"

# 1. Version check — exercises CLI init, @babel/core + commander wiring.
node packages/babel-cli/bin/babel.mjs --version

# 2. Direct core transform — exercises @babel/core's transformSync without
#    config discovery (babelrc: false, configFile: false are core options, not CLI flags).
node -e "
var babel = require('./packages/babel-core/lib/index.js');
var result = babel.transformSync('const fn = (x) => x * 2;', {babelrc: false, configFile: false});
if (!result || !result.code || result.code.indexOf('fn') === -1) process.exit(1);
console.log('transform ok');
"

echo "BABEL_SMOKE_OK"
