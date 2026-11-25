#!/usr/bin/env bash
#
# close-delay.sh — when did a project's last task go terminal, and has `closeAfterDays` passed?
#
#   Usage: close-delay.sh [--instance DIR] <slug>...
#   Prints one line per slug: <slug>\t<YYYY-MM-DD, or - when there is no readable history>\t<due|held>
#
# Exit: 0 · 2 usage · 3 no such instance. REPORT-ONLY. It answers the day and the delay and
# nothing else: whether a project is closable is each caller's own test. CHECKPOINT_TODAY pins
# the date. SCHEMA.md → "Closing a finished project after a delay" has the rules.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

inst="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || exit 2; inst="$2"; shift 2 ;;
    -*) echo "Usage: $(basename "$0") [--instance DIR] <slug>..." >&2; exit 2 ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || { echo "Usage: $(basename "$0") [--instance DIR] <slug>..." >&2; exit 2; }
inst="$(cd "$inst" 2>/dev/null && pwd)" || { echo "close-delay: no such instance directory" >&2; exit 3; }

# Absent, null or not a whole number => 5; a config read that FAILS => 0, today's behaviour.
delay="$(bash "$HERE/resolve-config.sh" --instance "$inst" closeAfterDays 2>/dev/null)"
case $? in
  0) printf '%s' "$delay" | grep -qE '^[0-9]+$' || delay=5 ;;
  1) delay=5 ;;
  *) delay=0 ;;
esac

# Days since 1970-01-01 (Howard Hinnant's days_from_civil), and back.
daynum() { printf '%s\n' "$1" | awk -F- 'NF==3 { y=$1+0; m=$2+0; d=$3+0; if (m<=2) y--; era=int(y/400)
  yoe=y-era*400; mp=(m+9)%12; doy=int((153*mp+2)/5)+d-1; print era*146097+yoe*365+int(yoe/4)-int(yoe/100)+doy-719468 }'; }
civil() { awk -v z="$1" 'BEGIN { z+=719468; era=int(z/146097); doe=z-era*146097
  yoe=int((doe-int(doe/1460)+int(doe/36524)-int(doe/146096))/365); y=yoe+era*400
  doy=doe-(365*yoe+int(yoe/4)-int(yoe/100)); mp=int((5*doy+2)/153); d=doy-int((153*mp+2)/5)+1
  m=mp<10?mp+3:mp-9; if (m<=2) y++; printf "%04d-%02d-%02d\n", y, m, d }'; }
today="$(daynum "${CHECKPOINT_TODAY:-$(date -u +%Y-%m-%d)}")"
[ -n "$today" ] || { echo "close-delay: unreadable CHECKPOINT_TODAY" >&2; exit 2; }

terminal() { sed -n 's/^status:[[:space:]]*//p' | head -n1 | tr -d "\"'" | grep -qE '^(done|cancelled)([[:space:]]|$)'; }

# Not the top of its own work tree, no commit or a shallow clone: no history to read, so the
# row shows at once.
history=0
if [ "$(git -C "$inst" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$inst" && pwd -P)" ] \
   && git -C "$inst" rev-parse --verify -q HEAD >/dev/null 2>&1 \
   && [ "$(git -C "$inst" rev-parse --is-shallow-repository 2>/dev/null)" = false ]; then
  history=1
fi

# The day a task went terminal: the newest commit whose version is terminal and whose
# predecessor's is not. Not at HEAD, or not terminal there (untracked, uncommitted) => today.
# A read git cannot answer prints `-`: no history, so the row shows (fail open).
task_day() { # <instance-relative path>
  local t v c ct prev="" log
  t="$(git -C "$inst" ls-tree HEAD -- "$1" 2>/dev/null)" || { echo -; return; }
  [ -n "$t" ] || { echo "$today"; return; }
  v="$(git -C "$inst" show "HEAD:./$1" 2>/dev/null)" || { echo -; return; }
  printf '%s\n' "$v" | terminal || { echo "$today"; return; }
  log="$(git -C "$inst" log --format='%H %ct' -- "$1" 2>/dev/null)" || { echo -; return; }
  while read -r c ct; do
    [ -n "$c" ] || continue
    t="$(git -C "$inst" ls-tree "$c" -- "$1" 2>/dev/null)" || { echo -; return; }
    [ -n "$t" ] || break
    v="$(git -C "$inst" show "$c:./$1" 2>/dev/null)" || { echo -; return; }
    printf '%s\n' "$v" | terminal || break
    prev="$ct"
  done <<EOF
$log
EOF
  [ -n "$prev" ] && echo $((prev / 86400)) || echo -
}

for slug in "$@"; do
  day=""
  if [ "$history" = 1 ]; then
    for f in "$inst/projects/$slug/tasks"/*.md; do
      [ -f "$f" ] || continue
      d="$(task_day "${f#"$inst"/}")"
      [ "$d" = - ] && { day=-; break; }
      { [ -z "$day" ] || [ "$d" -gt "$day" ]; } && day="$d"
    done
  fi
  if [ -z "$day" ] || [ "$day" = - ]; then
    printf '%s\t-\tdue\n' "$slug"
  else
    { [ "$delay" = 0 ] || [ $((today - day)) -ge "$delay" ]; } && v=due || v=held
    printf '%s\t%s\t%s\n' "$slug" "$(civil "$day")" "$v"
  fi
done
exit 0
