#!/usr/bin/env bash
# Watch automation logs.
#   tail.sh            follow cron.log (high-level orchestrator progress; default)
#   tail.sh claude     pretty-follow the newest headless-Sonnet transcript
#   tail.sh raw        raw-follow the newest transcript (stream-json)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

newest_transcript() { ls -t automation/logs/2026*-*.log 2>/dev/null | head -1; }

case "${1:-cron}" in
  cron)
    exec tail -n +1 -f automation/logs/cron.log
    ;;
  raw)
    f="$(newest_transcript)"; [ -n "$f" ] || { echo "no transcript yet" >&2; exit 1; }
    echo "# following $f" >&2
    exec tail -n +1 -f "$f"
    ;;
  claude)
    f="$(newest_transcript)"; [ -n "$f" ] || { echo "no transcript yet" >&2; exit 1; }
    echo "# following $f" >&2
    tail -n +1 -f "$f" | python3 -c '
import sys, json
for l in sys.stdin:
    l = l.strip()
    if not l.startswith("{"): continue
    try: o = json.loads(l)
    except ValueError: continue
    t = o.get("type")
    if t == "assistant":
        for c in o.get("message", {}).get("content", []):
            if c.get("type") == "text" and c.get("text", "").strip():
                print("·", c["text"].strip()[:200], flush=True)
            elif c.get("type") == "tool_use":
                i = c.get("input", {})
                d = i.get("command") or i.get("file_path") or i.get("pattern") or ""
                print("⚙", c.get("name"), str(d)[:160], flush=True)
    elif t == "result":
        print("== result:", o.get("subtype"), o.get("duration_ms"), "ms", flush=True)
'
    ;;
  *)
    echo "usage: tail.sh [cron|claude|raw]" >&2; exit 2
    ;;
esac
