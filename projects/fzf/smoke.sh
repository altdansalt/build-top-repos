#!/bin/sh
# Black-box smoke: run fzf non-interactively (--filter) over piped input.
# $PROJECT = built tree (has the fzf binary).
set -e
cd "$PROJECT"
./fzf --version
out=$(printf 'foo\nbar\nbaz\n' | ./fzf --filter bar)
test "$out" = "bar"
echo FZF_SMOKE_OK
