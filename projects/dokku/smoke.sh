#!/bin/sh
# Black-box smoke for dokku: verify Go helper binaries are present, then run
# `dokku version` through the main bash CLI with a minimal environment.
# The full PaaS needs Docker; `version` only reads a VERSION file.
# $PROJECT = restored build tree.
set -e

# Verify Go helper binaries were compiled
test -x "$PROJECT/plugins/common/prop"
test -x "$PROJECT/plugins/common/common"

# Minimal dokku directory structure
DOKKU_LIB=/tmp/dokku-lib
DOKKU_PLUGINS=/tmp/dokku-plugins
DOKKU_HOME=/tmp/dokku-home

# dokku_auth() does: count=$(find "$PLUGIN_PATH/enabled/*/user-auth" 2>/dev/null | wc -l)
# It short-circuits to return 0 when count==1 AND 20_events/user-auth exists.
# Create exactly that sentinel file so auth passes without needing plugn.
mkdir -p "$DOKKU_LIB/plugins/enabled/20_events"
touch "$DOKKU_LIB/plugins/enabled/20_events/user-auth"
mkdir -p "$DOKKU_PLUGINS/common"
mkdir -p "$DOKKU_HOME"

# common/functions is sourced unconditionally by the main dokku script
cp "$PROJECT/plugins/common/functions" "$DOKKU_PLUGINS/common/functions"

# VERSION is generated at install-time (not committed); write a known value
echo "0.38.19" > "$DOKKU_LIB/VERSION"

# The main dokku script sudo-s to the `dokku` system user for most commands.
# We create that user and run directly as it via runuser to skip sudo entirely.
useradd -m -d "$DOKKU_HOME" dokku 2>/dev/null || true
chown dokku "$DOKKU_HOME" 2>/dev/null || true

export DOKKU_ROOT="$DOKKU_HOME"
export DOKKU_LIB_PATH="$DOKKU_LIB"
export PLUGIN_PATH="$DOKKU_LIB/plugins"
export PLUGIN_CORE_AVAILABLE_PATH="$DOKKU_PLUGINS"

out=$(runuser -u dokku -- bash "$PROJECT/dokku" version)
echo "$out" | grep -q "dokku version" || { echo "FAIL: unexpected output: $out"; exit 1; }
echo "$out"

echo DOKKU_SMOKE_OK
