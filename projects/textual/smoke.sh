#!/bin/sh
# Black-box smoke: drive a real Textual app headlessly via its test pilot (the
# library's intended way to run an app without a terminal). $PROJECT = built tree.
set -e
cat > /tmp/tx_smoke.py <<'PY'
import asyncio
from textual.app import App
from textual.widgets import Label


class A(App):
    def compose(self):
        yield Label("hi")


async def main():
    async with A().run_test() as pilot:
        assert pilot.app.query_one(Label) is not None


asyncio.run(main())
print("TEXTUAL_SMOKE_OK")
PY
"$PROJECT/.venv/bin/python" /tmp/tx_smoke.py
