#!/usr/bin/env bash
# session-sweep.sh — stop what `agent-sessions.sh stop-ids` selects in this bundle (dead,
# finished, idle or busy past their bound), oldest first, at most 20 per run; each id must
# resolve back to itself through `full`, a `busy` one goes through `session-handoff.sh --busy`.
#
#   session-sweep.sh <bundle-root>  -> `stopped <short> (<age>) <class>` | `handed-off …` |
#                                      `stop-failed <short>` | `deferred <short> (<age>) <class>`
#
# Exit 0 swept (a refused stop included — never retried this run) · 2 the selection is
# unknown, nothing stopped · 3 usage. Reasoning: docs/pm-design.md#step-5.
# Verified by tests/dead-session-sweep.test.sh and tests/session-sweep-bounds.test.sh.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SESS="$HERE/agent-sessions.sh"; MAX=20
[ $# -eq 1 ] && [ -d "$1" ] || { echo "Usage: $(basename "$0") <bundle-root>" >&2; exit 3; }

ids="$(bash "$SESS" stop-ids "$1" 2>/dev/null)" \
  || { echo "session-sweep: cannot read this bundle's sessions — nothing stopped" >&2; exit 2; }

n=0; tried=()
while read -r sid short age cls task; do
  [ -n "$sid" ] || continue
  [ "$n" -lt "$MAX" ] || { echo "deferred $short ($age) $cls"; continue; }
  [ "$(bash "$SESS" full "$short" 2>/dev/null)" = "$sid" ] || continue
  n=$((n + 1))
  if [ "$cls" = busy ]; then
    out="$(bash "$HERE/session-handoff.sh" --busy "$task" 2>/dev/null </dev/null)" && echo "$out" \
      || echo "stop-failed $short"
  elif claude stop "$short" >/dev/null 2>&1 </dev/null; then tried+=("$sid $short $age $cls")
  else echo "stop-failed $short"; fi
done <<<"$ids"
[ ${#tried[@]} -gt 0 ] || exit 0

# A stop landed when the row no longer qualifies and holds no live pid.
holds_pid() { bash "$SESS" row "$1" 2>/dev/null | python3 -c 'import json, os, sys
try:
    p = json.load(sys.stdin).get("pid")
    assert isinstance(p, int) and not isinstance(p, bool) and p > 0
    os.kill(p, 0)
except PermissionError:
    pass
except Exception:
    sys.exit(1)'; }
after="$(bash "$SESS" stop-ids "$1" 2>/dev/null)"; rc=$?
for t in "${tried[@]}"; do
  read -r sid short age cls <<<"$t"
  if [ $rc -ne 0 ]; then echo "stopped $short ($age) $cls unverified"
  elif grep -q "^$sid " <<<"$after" || holds_pid "$sid"; then echo "stop-failed $short"
  else echo "stopped $short ($age) $cls"; fi
done
exit 0
