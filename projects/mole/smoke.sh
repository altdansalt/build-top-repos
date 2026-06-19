#!/bin/sh
# Black-box smoke for Mole: verify Go binaries are built and status-go outputs
# valid JSON on Linux. Piped stdout triggers the binary's auto-JSON mode.
# $PROJECT = restored build tree.
set -e

# analyze-go is darwin-only; on Linux the stub exits 1 with a clear message.
# Just verify the binary is present and executable.
test -x "$PROJECT/bin/analyze-go"

# status-go is cross-platform (gopsutil). Pipe stdout to get JSON output.
out=$("$PROJECT/bin/status-go" --json 2>/dev/null)

# Verify it produced a non-empty JSON object with expected fields.
echo "$out" | grep -q '"cpu"'    || { echo "FAIL: missing cpu field"; exit 1; }
echo "$out" | grep -q '"memory"' || { echo "FAIL: missing memory field"; exit 1; }

echo MOLE_SMOKE_OK
