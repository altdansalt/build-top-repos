#!/bin/sh
# Black-box smoke: verify g4f library installs and the main API surface is
# importable. gpt4free's core use case is as a library (users `import g4f`);
# actual AI calls require live provider endpoints, so offline import is the
# verifiable end-user action. $PROJECT = restored tree (with the .venv).
set -e
PY="$PROJECT/.venv/bin/python"

# Base package
"$PY" -c "import g4f; print('g4f:', g4f.__name__)"

# Main user-facing API: Client + Provider
"$PY" -c "from g4f.client import Client; c = Client(); print('Client: OK')"
"$PY" -c "from g4f import Provider; print('Provider:', Provider)"

echo GPT4FREE_SMOKE_OK
