#!/bin/sh
# Black-box smoke: import rich and render with it (the library's job), plus its
# built-in demo. $PROJECT = restored tree (with the .venv).
set -e
PY="$PROJECT/.venv/bin/python"
"$PY" -m rich >/dev/null
"$PY" -c "from rich.console import Console; from rich.table import Table; t=Table(); t.add_column('a'); t.add_row('x'); Console().print(t)"
echo RICH_SMOKE_OK
