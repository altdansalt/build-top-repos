#!/bin/sh
# Black-box smoke: import tinygrad and run a tensor add with the PYTHON (numpy)
# backend — the framework's core job. $PROJECT = restored tree (with .venv).
set -e
PY="$PROJECT/.venv/bin/python"
DEV=PYTHON "$PY" -c "
from tinygrad import Tensor
a = Tensor([1.0, 2.0, 3.0])
b = Tensor([4.0, 5.0, 6.0])
c = (a + b).numpy()
assert list(c) == [5.0, 7.0, 9.0], 'expected [5.0, 7.0, 9.0], got %s' % list(c)
"
echo TINYGRAD_SMOKE_OK
