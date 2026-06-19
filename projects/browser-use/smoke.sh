#!/bin/sh
# Black-box smoke: verify browser-use installs and the library is importable.
# Full use requires Playwright browser binaries and an LLM API key — neither
# available here. We verify the package loads and its public API is accessible.
# $PROJECT = restored tree (with the .venv).
set -e
PY="$PROJECT/.venv/bin/python"

# Version from installed metadata
"$PY" -c "
import importlib.metadata
v = importlib.metadata.version('browser-use')
print('browser-use', v)
"

# Core package import
"$PY" -c "import browser_use; print('browser_use:', browser_use.__name__)"

echo BROWSER_USE_SMOKE_OK
