#!/bin/sh
# Black-box smoke: import numpy and exercise basic array operations — the library's
# core job. $PROJECT = restored tree (with the .venv).
set -e
PY="$PROJECT/.venv/bin/python3"
cd /tmp
"$PY" -c "import numpy; print(numpy.__version__)"
"$PY" -c "
import numpy as np
a = np.array([1, 2, 3])
b = np.array([4, 5, 6])
c = a + b
assert list(c) == [5, 7, 9], 'add: got %s' % list(c)
d = int(np.dot(a, b))
assert d == 32, 'dot: expected 32, got %s' % d
e = np.zeros((3, 3))
assert e.shape == (3, 3), 'zeros shape: %s' % str(e.shape)
"
echo NUMPY_SMOKE_OK
