#!/bin/sh
# Black-box smoke: install gulp into a fresh project, author a gulpfile with a
# custom task, and run it via the gulp CLI. $PROJECT = restored build tree.
set -e
d=$(mktemp -d)
cd "$d"
npm init -y >/dev/null 2>&1
npm install "$PROJECT" >/dev/null 2>&1
cat > gulpfile.js <<'JS'
const g = require('gulp');
g.task('greet', function (cb) {
  console.log('GULP_SMOKE_OK');
  cb();
});
JS
npx gulp greet
