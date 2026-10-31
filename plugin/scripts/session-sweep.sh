#!/usr/bin/env bash
# session-sweep.sh — stop this bundle's dead, unattributed background sessions, oldest first,
# at most 20 per run. `agent-sessions.sh dead-ids` selects; each id must resolve back to
# itself through `full` before `claude stop <short>`, and one listing afterwards confirms it.
#
#   session-sweep.sh <bundle-root>  -> `stopped <short> (<age>)` | `stop-failed <short>` per id
#
# Exit 0 swept (a refused stop included — never retried this run) · 2 the selection is
# unknown, nothing stopped · 3 usage. Reasoning: docs/pm-design.md#step-5.
# Verified by tests/dead-session-sweep.test.sh.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SESS="$HERE/agent-sessions.sh"; MAX=20
[ $# -eq 1 ] && [ -d "$1" ] || { echo "Usage: $(basename "$0") <bundle-root>" >&2; exit 3; }

ids="$(bash "$SESS" dead-ids "$1" 2>/dev/null)" \
  || { echo "session-sweep: cannot read this bundle's sessions — nothing stopped" >&2; exit 2; }

n=0; tried=()
while read -r sid short age; do
  [ -n "$sid" ] && [ "$n" -lt "$MAX" ] || continue
  [ "$(bash "$SESS" full "$short" 2>/dev/null)" = "$sid" ] || continue
  n=$((n + 1))
  if claude stop "$short" >/dev/null 2>&1 </dev/null; then tried+=("$sid $short $age")
  else echo "stop-failed $short"; fi
done <<<"$ids"
[ ${#tried[@]} -gt 0 ] || exit 0

after="$(bash "$SESS" states "${tried[@]%% *}" 2>/dev/null)" || after=""
for t in "${tried[@]}"; do
  read -r sid short age <<<"$t"
  st="$(awk -v s="$sid" '$1 == s { print $2 }' <<<"$after")"
  case " done gone stopped completed cancelled failed error exited " in
    *" ${st:-?} "*) echo "stopped $short ($age)" ;;
    *) [ -z "$after" ] && echo "stopped $short ($age) unverified" || echo "stop-failed $short" ;;
  esac
done
exit 0
