#!/usr/bin/env bash
#
# merge-hold.sh — does the task's role session or an open hand-off hold its PR's merge?
#
#   merge-hold.sh check <task-doc> --head <sha> [--instance DIR] [--record --repo O/R --pr N]
#                       -> clear · role session live · hand-off open · session unknown
#   merge-hold.sh verify --bundle DIR --repo O/R --pr N --head SHA <task-doc>...  (merge-permit.sh)
#
# Exit 0 clear · 1 held, or verify refuses · 2 unknown, or usage. The session is read from the
# listing step 4 saves (agent-sessions.sh save), stale past FRESH_MINUTES. Reasoning:
# docs/pm-design.md#step-4. Verified by tests/awaiting-render.test.sh, tests/subagent-merge-yolo.test.sh.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)" || exit 2
. "$HERE/bundle-paths.sh" || exit 2
FRESH_MINUTES=30
TERMINAL=" done gone stopped completed cancelled failed error exited "
usage() { sed -n '5,7p' "$0" >&2; exit 2; }

fmval() { # <doc> <key>
  awk 'NR == 1 && $0 != "---" { exit } /^---[[:space:]]*$/ { n++; if (n == 2) exit; next } n == 1' "$1" 2>/dev/null \
    | sed -n "s/^$2:[[:space:]]*//p" | head -n 1 | sed 's/[[:space:]]#.*$//' | tr -d "\"' "
}

mark() { # <task-doc>...
  local f s n out=""
  for f; do
    s="$(fmval "$f" session)"
    n="$(grep -cE '^\* DISPATCH |(woke|resumed) [0-9a-f]{8}|resume launched|dispatched [0-9a-f-]{8,} for hand-off |spawned; session id unresolved' "$f" 2>/dev/null)"
    out="${out:+$out,}${s%%-*}.${n:-0}"
  done
  printf '%s' "${out:--}" | tr -c 'A-Za-z0-9.,-' '-'
}

mode="${1:-}"; [ $# -gt 0 ] && shift
task=""; tasks=(); head=""; inst=""; record=""; repo=""; pr=""
while [ $# -gt 0 ]; do
  case "$1" in
    --record) record=yes; shift ;;
    --head|--instance|--bundle|--repo|--pr)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      case "$1" in --head) head="$2" ;; --instance|--bundle) inst="$2" ;; --repo) repo="$2" ;; --pr) pr="$2" ;; esac
      shift 2 ;;
    -*) usage ;;
    *) tasks+=("$1"); shift ;;
  esac
done
[ -n "$head" ] && [ "${#tasks[@]}" -ge 1 ] || usage

if [ "$mode" = verify ]; then
  [ -n "$inst" ] && [ -n "$repo" ] && [ -n "$pr" ] || usage
  rf="$("$HERE/clearance-receipt.sh" path --bundle "$inst" --repo "$repo" --pr "$pr" --head "$head" 2>/dev/null)"
  line="$(awk '$2 == "merge-hold.sh"' "$rf" 2>/dev/null | tail -n 1)"
  [ -n "$line" ] || { echo "no merge-hold.sh line for $repo#$pr at $head: run merge-hold.sh check --record first"; exit 1; }
  read -r verdict _ stamp got <<<"$line"
  [ "$verdict" = clear ] || { echo "merge held at $head: $verdict (merge-hold.sh)"; exit 1; }
  cutoff="$(python3 -c 'import datetime as d, sys; print((d.datetime.now(d.timezone.utc) - d.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$FRESH_MINUTES" 2>/dev/null)"
  [ -n "$cutoff" ] && [ ! "$stamp" \< "$cutoff" ] || { echo "the merge-hold.sh line at $head is older than ${FRESH_MINUTES}m: re-run check --record"; exit 1; }
  [ "${got:-}" = "$(mark "${tasks[@]}")" ] || { echo "the task's round moved since the merge-hold.sh line at $head: re-run check --record"; exit 1; }
  exit 0
fi
[ "$mode" = check ] && [ "${#tasks[@]}" = 1 ] || usage
task="${tasks[0]}"
[ -z "$record" ] || { [ -n "$repo" ] && [ -n "$pr" ]; } || usage
case "$task" in /*) ;; *) [ -f "$task" ] || [ -z "$inst" ] || task="$inst/$task" ;; esac
[ -f "$task" ] && [ -r "$task" ] || { echo "merge-hold: no readable task document: $task" >&2; exit 2; }
[ -n "$inst" ] || inst="$(cd "$(dirname "$task")/../../.." 2>/dev/null && pwd)"

say() { # <verdict word> <line> <exit>
  [ -z "$record" ] || "$HERE/clearance-receipt.sh" record merge-hold.sh --hold "$1" --mark "$(mark "$task")" \
    --bundle "$inst" --repo "$repo" --pr "$pr" --head "$head" >/dev/null 2>&1
  echo "$2"; exit "$3"
}

# --- the role session ---
sid="$(fmval "$task" session)"
if [ -z "$sid" ]; then
  grep -qE 'spawned; session id unresolved|resume launched; session id unresolved' "$task" \
    && say unknown "session unknown" 2
else
  saved="$inst/$AB_SESSIONS_SAVED"
  [ -f "$saved" ] && [ -z "$(find "$saved" -mmin +"$FRESH_MINUTES" 2>/dev/null)" ] || say unknown "session unknown" 2
  st="$(AB_SESSIONS_LISTING="$saved" bash "$HERE/agent-sessions.sh" states "$sid" 2>/dev/null)" || say unknown "session unknown" 2
  read -r _ st _ <<<"$st"
  case "$st" in
    working|blocked) say live "role session live" 1 ;;
    *) case "$TERMINAL" in *" $st "*) ;; *) say unknown "session unknown" 2 ;; esac ;;
  esac
fi

# --- an open hand-off at this head ---
open="$(bash "$HERE/fold-answers.sh" --list "$task" open_questions 2>/dev/null)" \
  || { echo "merge-hold: open_questions unreadable in $task" >&2; exit 2; }
while IFS= read -r e; do
  case "$e" in *' --- '*|Q[0-9]*': do: deploy '*) continue ;; Q[0-9]*': do: '*'hand-off '*) ;; *) continue ;; esac
  id="$(printf '%s' "$e" | grep -oE 'hand-off [0-9a-f]{8}-[0-9a-f]{8}' | head -n 1)"; id="${id#hand-off }"
  [ -n "$id" ] || continue
  hs=" $(grep -F "· hand-off $id ·" "$task" | sed -n 's/.* · heads \(.*\)$/\1/p' | tail -n 1) "
  case "$hs" in *" merged "*|'  ') continue ;; *" unknown "*|*" $head "*) say hand-off "hand-off open" 1 ;; esac
done <<<"$open"
say clear clear 0
