#!/bin/sh
# Black-box smoke: install the packed husky into a fresh git repo, init hooks,
# and confirm a hook actually fires on commit. $PROJECT = restored build tree.
set -e
rm -f /tmp/husky_marker
d=$(mktemp -d)
cd "$d"
git init -q
git config user.email a@b.c
git config user.name a
npm init -y >/dev/null 2>&1
npm install "$PROJECT/husky.tgz" >/dev/null 2>&1
npx --no-install husky init >/dev/null 2>&1
printf 'echo FIRED > /tmp/husky_marker\n' > .husky/pre-commit
git add -A
git commit -q -m smoke
test -f /tmp/husky_marker
echo "HUSKY_SMOKE_OK hooksPath=$(git config core.hooksPath)"
