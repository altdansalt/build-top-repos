#!/bin/sh
# Black-box smoke: verify the langflow-base CLI prints version + help without
# starting a server or connecting to a database.  $PROJECT = restored tree.
set -e
LF="$PROJECT/.venv/bin/langflow-base"
"$LF" --version
"$LF" --help > /dev/null
echo LANGFLOW_SMOKE_OK
