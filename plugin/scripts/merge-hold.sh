#!/usr/bin/env bash
#
# merge-hold.sh — does the task's role session or an open hand-off hold its PR's merge?
#
#   merge-hold.sh check <task-doc> --head <sha> [--instance DIR] [--record --repo O/R --pr N]
#                       -> clear · role session live · hand-off open · session unknown
#   merge-hold.sh verify --bundle DIR --repo O/R --pr N --head SHA   (merge-permit.sh)
#   merge-hold.sh marks <bundle>   -> `<task> <mark>` per task (agent-sessions.sh save)
#
# Exit 0 clear · 1 held, or verify refuses · 2 unknown, or usage. The session is read from the
# listing step 4 saves, stale past FRESH_MINUTES or past a resume since. Reasoning:
# docs/pm-design.md#step-4. Verified by tests/awaiting-render.test.sh, tests/subagent-merge-yolo.test.sh.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)" || exit 2
. "$HERE/bundle-paths.sh" || exit 2
FRESH_MINUTES=30
TERMINAL=" done gone stopped completed cancelled failed error exited "
usage() { sed -n '5,8p' "$0" >&2; exit 2; }

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

key() { printf 'projects/%s' "${1##*/projects/}"; }

owners() { # <bundle> <repo> <pr> — every task whose frontmatter `pr:` names the PR, as merge-permit.sh reads it
  local re f fm
  re="$(printf '%s' "$2" | sed 's/[.+*?^$|]/\\&/g')"
  for f in "$1"/projects/*/tasks/*.md; do
    [ -f "$f" ] || continue
    fm="$(awk '/^---[[:space:]]*$/ { fm++; if (fm == 2) exit; next }
         fm == 1 && /^[A-Za-z_][A-Za-z0-9_-]*:/ { inpr = ($0 ~ /^pr:/) }
         fm == 1 && inpr { print }' "$f" 2>/dev/null)"
    grep -Eq "/$re/pull/$3([^0-9]|\$)" <<<"$fm" && printf '%s\n' "$f"
  done
}

session_of() { # <task> -> clear | live | unknown
  local sid saved st want
  sid="$(fmval "$1" session)"
  if [ -z "$sid" ]; then
    grep -qE 'spawned; session id unresolved|resume launched; session id unresolved' "$1" && { echo unknown; return; }
    echo clear; return
  fi
  saved="$inst/$AB_SESSIONS_SAVED"
  [ -f "$saved" ] && [ -z "$(find "$saved" -mmin +"$FRESH_MINUTES" 2>/dev/null)" ] || { echo unknown; return; }
  want="$(awk -v k="$(key "$1")" '$1 == k { print $2; exit }' "$(dirname "$saved")/marks" 2>/dev/null)"
  [ -n "$want" ] && [ "$want" = "$(mark "$1")" ] || { echo unknown; return; }
  st="$(AB_SESSIONS_LISTING="$saved" bash "$HERE/agent-sessions.sh" states "$sid" 2>/dev/null)" || { echo unknown; return; }
  read -r _ st _ <<<"$st"
  case "$st" in working|blocked) echo live ;; *) case "$TERMINAL" in *" $st "*) echo clear ;; *) echo unknown ;; esac ;; esac
}

handoff_of() { # <task> -> clear | hand-off; exit 2 unreadable
  local open e id hs t
  open="$(bash "$HERE/fold-answers.sh" --list "$1" open_questions 2>/dev/null)" || return 2
  while IFS= read -r e; do
    case "$e" in *' --- '*|Q[0-9]*': do: deploy '*) continue ;; Q[0-9]*': do: '*'hand-off '*) ;; *) continue ;; esac
    id="$(printf '%s' "$e" | grep -oE 'hand-off [0-9a-f]{8}-[0-9a-f]{8}')"; id="${id%%$'\n'*}"; id="${id#hand-off }"
    [ -n "$id" ] || continue
    hs="$(grep -F "· hand-off $id ·" "$1" | sed -n 's/.* · heads \(.*\)$/\1/p')"; hs="${hs##*$'\n'}"
    for t in $hs; do
      case "$t" in unknown|"$head") echo hand-off; return 0 ;; esac
    done
  done <<<"$open"
  echo clear
}

judge() { # <task>... -> the first hold among them: live, hand-off, unknown, else clear
  local f s h worst=clear
  for f; do
    s="$(session_of "$f")"; h="$(handoff_of "$f")" || h=unknown
    [ "$s" = live ] && { echo live; return; }
    [ "$h" = hand-off ] && worst=hand-off
    [ "$worst" = clear ] && [ "$s$h" != clearclear ] && worst=unknown
  done
  echo "$worst"
}

mode="${1:-}"; [ $# -gt 0 ] && shift
tasks=(); head=""; inst=""; record=""; repo=""; pr=""
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

if [ "$mode" = marks ]; then
  [ "${#tasks[@]}" = 1 ] && [ -d "${tasks[0]}" ] || usage
  for f in "${tasks[0]}"/projects/*/tasks/*.md; do [ -f "$f" ] && printf '%s %s\n' "$(key "$f")" "$(mark "$f")"; done
  exit 0
fi
[ -n "$head" ] || usage
if ! [[ "$head" =~ ^[0-9a-f]{40}$ ]]; then
  badhead="merge-hold: --head $(printf '%s' "$head" | tr -d '[:cntrl:]') is not a 40-character lowercase hex sha"
  if [ "$mode" = verify ]; then echo "$badhead"; else echo "$badhead" >&2; fi
  exit 2
fi

if [ "$mode" = verify ]; then
  [ -n "$inst" ] && [ -n "$repo" ] && [ -n "$pr" ] || usage
  docs=(); while IFS= read -r f; do [ -n "$f" ] && docs+=("$f"); done <<<"$(owners "$inst" "$repo" "$pr")"
  [ "${#docs[@]}" -ge 1 ] || { echo "no task document names $repo#$pr"; exit 1; }
  rf="$("$HERE/clearance-receipt.sh" path --bundle "$inst" --repo "$repo" --pr "$pr" --head "$head" 2>/dev/null)"
  line="$(awk '$2 == "merge-hold.sh" { l = $0 } END { print l }' "$rf" 2>/dev/null)"
  [ -n "$line" ] || { echo "no merge-hold.sh line for $repo#$pr at $head: run merge-hold.sh check --record first"; exit 1; }
  read -r verdict _ stamp got <<<"$line"
  [ "$verdict" = clear ] || { echo "merge held at $head: $verdict (merge-hold.sh)"; exit 1; }
  cutoff="$(python3 -c 'import datetime as d, sys; print((d.datetime.now(d.timezone.utc) - d.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$FRESH_MINUTES" 2>/dev/null)"
  [ -n "$cutoff" ] && [ ! "$stamp" \< "$cutoff" ] || { echo "the merge-hold.sh line at $head is older than ${FRESH_MINUTES}m: re-run check --record"; exit 1; }
  [ "${got:-}" = "$(mark "${docs[@]}")" ] || { echo "the task's round moved since the merge-hold.sh line at $head: re-run check --record"; exit 1; }
  for f in "${docs[@]}"; do
    h="$(handoff_of "$f")" || { echo "open_questions unreadable in $f"; exit 1; }
    [ "$h" = clear ] || { echo "a hand-off is open at $head in $f"; exit 1; }
  done
  exit 0
fi

[ "$mode" = check ] && [ "${#tasks[@]}" = 1 ] || usage
task="${tasks[0]}"
[ -z "$record" ] || { [ -n "$repo" ] && [ -n "$pr" ]; } || usage
case "$task" in /*) ;; *) [ -f "$task" ] || [ -z "$inst" ] || task="$inst/$task" ;; esac
[ -f "$task" ] && [ -r "$task" ] || { echo "merge-hold: no readable task document: $task" >&2; exit 2; }
if [ -z "$inst" ]; then
  case "$task" in */projects/*/tasks/*) inst="${task%/projects/*}" ;; *) inst="$PWD" ;; esac
fi

docs=("$task")
if [ -n "$record" ]; then
  docs=(); while IFS= read -r f; do [ -n "$f" ] && docs+=("$f"); done <<<"$(owners "$inst" "$repo" "$pr")"
  [ "${#docs[@]}" -ge 1 ] || docs=("$task")
fi
v="$(judge "${docs[@]}")"
[ -z "$record" ] || "$HERE/clearance-receipt.sh" record merge-hold.sh --hold "$v" --mark "$(mark "${docs[@]}")" \
  --bundle "$inst" --repo "$repo" --pr "$pr" --head "$head" >/dev/null 2>&1
case "$v" in
  live) echo "role session live"; exit 1 ;;
  hand-off) echo "hand-off open"; exit 1 ;;
  unknown) echo "session unknown"; exit 2 ;;
esac
echo clear
