#!/usr/bin/env bash
# Cron wrapper: add the next unhandled project, one per tick.
#
# Cron-safe: an flock guard makes overlapping ticks exit immediately (a long
# build can outlast the cron interval). Sets PATH so claude/bazel/git/gh resolve
# under cron's minimal environment, then runs the orchestrator once.
#
# Example crontab line (every 30 min; the lock prevents pile-ups):
#   */30 * * * * /home/exedev/build-top-repos/automation/run.sh >> /home/exedev/build-top-repos/automation/logs/cron.log 2>&1
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
mkdir -p automation/logs

# cron runs with a minimal PATH; ensure the tools we shell out to are findable.
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

LOCK="automation/.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "[$(date -u +%H:%M:%S)] another run holds the lock; exiting" >&2
  exit 0
fi

echo "===== $(date -u +%Y-%m-%dT%H:%M:%SZ) add_next_project ====="
exec python3 automation/add_next_project.py "$@"
