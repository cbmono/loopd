#!/usr/bin/env bash
# session-sweep.sh — stop what `agent-sessions.sh stop-ids` selects in this bundle, oldest
# first, at most 20 a run, each id resolving back to itself through `full`; a `busy` one goes
# through `session-handoff.sh --busy`, a stopped `stalled` one through `stall-counter.sh`.
#   session-sweep.sh <bundle-root>  -> `stopped <short> (<age>) <class>` | `handed-off …` |
#     `stop-failed <short>` | `deferred <short> (<age>) <class>` | `escalated <short> (<age>) stalled`
#     | `count-failed <short>` (stopped, but stall-counter.sh could not record or escalate it)
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
  n=$((n + 1)); head=-
  [ "$cls" = stalled ] && { head="${task##* }"; task="${task% *}"; }
  if [ "$cls" = busy ]; then
    out="$(bash "$HERE/session-handoff.sh" --busy "$task" 2>/dev/null </dev/null)" && echo "$out" \
      || echo "stop-failed $short"
  elif claude stop "$short" >/dev/null 2>&1 </dev/null; then tried+=("$sid $short $age $cls $head $task")
  else echo "stop-failed $short"; fi
done <<<"$ids"
[ ${#tried[@]} -gt 0 ] || exit 0

# A stop landed when the row no longer qualifies and holds no live pid.
holds_pid() { bash "$SESS" row "$1" 2>/dev/null | bash "$SESS" alive -; }
after="$(bash "$SESS" stop-ids "$1" 2>/dev/null)"; rc=$?
for t in "${tried[@]}"; do
  read -r sid short age cls head task <<<"$t"
  if [ $rc -ne 0 ]; then echo "stopped $short ($age) $cls unverified"
  elif grep -q "^$sid " <<<"$after" || holds_pid "$sid"; then echo "stop-failed $short"; continue
  else echo "stopped $short ($age) $cls"; fi
  [ "$cls" = stalled ] || continue
  bash "$HERE/stall-counter.sh" record "$task" --blocker "pr head still $head" \
    --note "* $(date -u +%Y-%m-%dT%H:%M:%SZ) stalled stop $sid · pr head still $head" >/dev/null 2>&1 </dev/null
  case $? in
    0) ;;
    1) bash "$HERE/stall-counter.sh" escalate "$task" >/dev/null 2>&1 </dev/null \
         && echo "escalated $short ($age) stalled" || echo "count-failed $short" ;;
    *) echo "count-failed $short" ;;
  esac
done
exit 0
