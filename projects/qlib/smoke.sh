#!/bin/sh
# Black-box smoke: import qlib and verify the Cython rolling/expanding
# extensions compiled correctly. Financial-data access requires a downloaded
# dataset, so offline import + extension check is the verifiable end-user action.
# $PROJECT = restored tree (with the .venv).
set -e
PY="$PROJECT/.venv/bin/python"

# Run from /tmp so Python doesn't pick up the source qlib/ dir over the venv.
cd /tmp
"$PY" -c "import qlib; print('qlib', qlib.__version__)"
"$PY" -c "from qlib.data._libs import rolling, expanding; print('Cython extensions OK')"
echo QLIB_SMOKE_OK
