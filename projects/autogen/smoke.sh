#!/bin/sh
# Smoke: import autogen_core + autogen_agentchat; verify version metadata and
# basic API object construction. Full agent execution requires a model client
# (OpenAI, Azure, etc.) — not available here.
# $PROJECT = restored tree (with the .venv).
set -e
PY="$PROJECT/.venv/bin/python"

# Version from installed metadata
"$PY" -c "
import importlib.metadata
for pkg in ('autogen-core', 'autogen-agentchat'):
    v = importlib.metadata.version(pkg)
    print(pkg, v)
"

# Core API imports and basic object construction (no LLM call)
"$PY" -c "
import autogen_core
import autogen_agentchat
print('autogen_core:', autogen_core.__version__)
print('autogen_agentchat:', autogen_agentchat.__version__)

from autogen_core import AgentId, CancellationToken
from autogen_agentchat.messages import TextMessage

aid = AgentId('smoke-test', 'default')
print('AgentId:', aid)

tok = CancellationToken()
print('CancellationToken created')

msg = TextMessage(content='hello from smoke', source='smoke')
print('TextMessage:', msg.content)
"

echo AUTOGEN_SMOKE_OK
