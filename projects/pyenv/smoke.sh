#!/bin/sh
# Black-box smoke: drive the pyenv CLI as a user would (no Python builds).
# $PROJECT = restored build tree.
set -e
export PYENV_ROOT=/tmp/pyenv-root
export PATH="$PROJECT/bin:$PATH"
pyenv --version
pyenv commands >/dev/null
pyenv versions   # no versions installed -> shows "* system"
echo PYENV_SMOKE_OK
