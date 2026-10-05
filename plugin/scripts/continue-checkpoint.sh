#!/usr/bin/env bash
#
# continue-checkpoint.sh — which active projects are due the "should this continue?" question.
#
#   Usage: continue-checkpoint.sh [--instance DIR]
#   Prints one line per due project: <project path>\t<who decides>\t<why>\t<continued: value>
#
# Exit: 0 (nothing due prints nothing, and so does an unconfigured bundle) · 2 usage · 3 unreadable.
# REPORT-ONLY: it writes nothing. Read by build-awaiting.sh and tick-delta.sh; the keys and the
# record are in SCHEMA.md → "The continue checkpoint". CHECKPOINT_TODAY=YYYY-MM-DD pins the date.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 2

inst="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || exit 2; inst="$2"; shift 2 ;;
    *) echo "Usage: $(basename "$0") [--instance DIR]" >&2; exit 2 ;;
  esac
done
inst="$(cd "$inst" 2>/dev/null && pwd)" || { echo "continue-checkpoint: no such instance directory" >&2; exit 3; }

posint() { printf '%s' "$1" | grep -qE '^[1-9][0-9]*$'; }
cfg() { local v; v="$(bash "$HERE/resolve-config.sh" --instance "$inst" "$1" 2>/dev/null)" || return 0
        posint "$v" && printf '%s' "$v"; }
after_tasks="$(cfg continueAfterTasks)"; after_days="$(cfg continueAfterDays)"
[ -n "$after_tasks$after_days" ] || exit 0

fmfirst() { sed -n "s/^$2:[[:space:]]*\([^[:space:]].*\)/\1/p" "$1" | head -n1 | sed -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/'; }
# Civil date -> day number (Howard Hinnant's days_from_civil): no GNU/BSD `date` split.
daynum() { printf '%s\n' "$1" | awk -F- 'NF==3 { y=$1+0; m=$2+0; d=$3+0; if (m<=2) y--; era=int(y/400)
  yoe=y-era*400; mp=(m+9)%12; doy=int((153*mp+2)/5)+d-1; print era*146097+yoe*365+int(yoe/4)-int(yoe/100)+doy }'; }
today="${CHECKPOINT_TODAY:-$(date -u +%Y-%m-%d)}"
tnum="$(daynum "$today")"; [ -n "$tnum" ] || exit 3

ledger="$inst/$AB_LEDGER"; [ -f "$ledger" ] || ledger="$inst/log.md"
# The `by <login>` stamped on the project's creation entry in the root log.
creator() { # <slug>
  [ -f "$ledger" ] || return 0
  awk -v s="$1" '
    !on && /Project added/ && (index($0, ": " s) || index($0, "/projects/" s "/") || index($0, "`" s "`")) { on=1; print; next }
    on && (/^## / || /^\* /) { exit }
    on { print }' "$ledger" \
  | grep -oE '(Added|added|[0-9]Z)(\*\*)? by [A-Za-z0-9]+(-[A-Za-z0-9]+)*' | head -n1 | sed 's/.* by //'
}
default_owner="$(sed -n 's/.*"defaultOwner"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9-]*\)".*/\1/p' "$inst/instance.config.json" 2>/dev/null | head -n1)"

for pm in "$inst"/projects/*/project.md; do
  [ -f "$pm" ] || continue
  [ -r "$pm" ] || exit 3
  case "$(fmfirst "$pm" status)" in done|paused) continue ;; esac
  slug="$(basename "$(dirname "$pm")")"
  ntask=0; nterm=0; ndone=0
  for f in "$(dirname "$pm")"/tasks/*.md; do
    [ -f "$f" ] || continue
    [ -r "$f" ] || exit 3
    st="$(fmfirst "$f" status)"; ntask=$((ntask + 1))
    case "${st%% *}" in done) ndone=$((ndone + 1)); nterm=$((nterm + 1)) ;; cancelled) nterm=$((nterm + 1)) ;; esac
  done
  # Every task terminal is the `close` row's question, not this one.
  [ "$ntask" -gt 0 ] && [ "$ntask" = "$nterm" ] && continue

  anchor="$(fmfirst "$pm" timestamp | cut -c1-10)"; base=0; since="started"
  cont="$(fmfirst "$pm" continued)"
  if printf '%s' "$cont" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]+$'; then
    anchor="${cont%% *}"; base="${cont#* }"; since="continued"
  fi
  anum="$(daynum "$anchor")"
  age=""; [ -n "$anum" ] && age=$((tnum - anum))
  tb="$(fmfirst "$pm" timebox)"; tbd=""
  if printf '%s' "$tb" | grep -qE '^[1-9][0-9]*[dw]$'; then
    tbd="${tb%?}"; [ "${tb#"$tbd"}" = w ] && tbd=$((tbd * 7))
  fi

  why=""
  [ -n "$after_tasks" ] && [ $((ndone - base)) -ge "$after_tasks" ] && why="$((ndone - base)) tasks done since $since"
  [ -z "$why" ] && [ -n "$tbd" ] && [ -n "$age" ] && [ "$age" -ge "$tbd" ] && why="its $tb time-box ran out ($age days since $since)"
  [ -z "$why" ] && [ -n "$after_days" ] && [ -n "$age" ] && [ "$age" -ge "$after_days" ] && why="$age days since $since"
  [ -n "$why" ] || continue

  who="$(fmfirst "$pm" no_owner)"
  [ -n "$who" ] || who="$(creator "$slug")"
  [ -n "$who" ] || who="$default_owner"
  [ -n "$who" ] || who="nobody named"
  printf '%s\t%s\t%s\t%s %s\n' "${pm#"$inst"}" "$(printf '%s' "$who" | tr -d '\t')" "$why" "$today" "$ndone"
done
exit 0
