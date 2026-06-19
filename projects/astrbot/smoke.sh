#!/bin/sh
# Smoke: verify astrbot installs cleanly and core imports work.
# Full agent execution requires IM platform credentials and LLM API keys.
# $PROJECT = restored build tree (with .venv).
set -e
PY="$PROJECT/.venv/bin/python"
AB="$PROJECT/.venv/bin/astrbot"

# 1. CLI version
"$AB" --version

# 2. Core module imports (no network, no keys)
"$PY" -c "
import importlib.metadata
v = importlib.metadata.version('AstrBot')
print('AstrBot version:', v)

# Core pipeline bootstrap
from astrbot.core.pipeline.bootstrap import ensure_builtin_stages_registered
from astrbot.core.pipeline.stage import registered_stages
ensure_builtin_stages_registered()
print('registered pipeline stages:', len(registered_stages))

# Key adapter imports
import astrbot.core.config.astrbot_config as cfg
print('AstrBotConfig:', cfg.AstrBotConfig)

import astrbot.core.pipeline as pipeline
print('ProcessStage:', pipeline.ProcessStage)
print('RespondStage:', pipeline.RespondStage)
"

echo ASTRBOT_SMOKE_OK
