#!/bin/sh
# Black-box smoke: verify mempalace installs and the CLI is runnable.
# Full use (mining, search) requires a ChromaDB palace and an embedding model
# loaded at query time — not available here. We verify the CLI entry point,
# version reporting, and top-level imports.
# $PROJECT = restored tree (with the .venv).
set -e
PY="$PROJECT/.venv/bin/python"
MP="$PROJECT/.venv/bin/mempalace"

# CLI version and help
"$MP" --version
"$MP" --help | grep -q "mine"

# Package import and version metadata
"$PY" -c "
import importlib.metadata
v = importlib.metadata.version('mempalace')
print('mempalace', v)
"

echo MEMPALACE_SMOKE_OK
