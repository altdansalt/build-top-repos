#!/bin/sh
# Black-box smoke: manim --version + render a minimal Circle scene to PNG via
# the Cairo renderer (headless, no display required).
# Runtime Cairo/Pango libs are bundled in $PROJECT/.libs/ (captured at build
# time) to avoid apt-get update inside the 300s sh_test timeout window.
# $PROJECT = restored build tree (with .venv and .libs/).
set -e

export LD_LIBRARY_PATH="$PROJECT/.libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
MANIM="$PROJECT/.venv/bin/manim"

"$MANIM" --version
"$MANIM" --help >/dev/null

# Render a minimal Circle scene to PNG via the Cairo renderer.
cat > /tmp/smoke_scene.py << 'PYEOF'
from manim import *

class SmokeCircle(Scene):
    def construct(self):
        self.play(Create(Circle()))
PYEOF

cd /tmp
"$MANIM" render -ql --format png --renderer cairo /tmp/smoke_scene.py SmokeCircle

find /tmp/media -name '*.png' | head -1 | grep -q .
echo MANIM_SMOKE_OK
