#!/usr/bin/env bash
#
# status-line.sh — one line for Claude Code's `statusLine`: what is in progress and in
# review, how many bg sessions are working, idle or dead, what waits on the human, a held
# lock, when the last tick was. Each run also writes those numbers to AB_COUNTS (counts.sh).
#
#   status-line.sh [--instance DIR] [--color auto|always|never]
#
# A script, never a model: file reads plus one cached `claude agents --json`, no `gh`, no
# network, no `jq`. Session JSON on stdin is drained and only read for its directory.
# Exit: 0 always (a status line never fails a session), 3 usage.
# Reasoning: ai-bridge-v3/task-025.
set -uo pipefail
# `|| exit 0`, not the house `|| exit 2`: the exit contract above wins — a status line
# never fails a session, even when its own resolver is gone.
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 0

INST=""; COLOR=auto
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) shift; INST="${1:-}"; shift || true ;;
    --instance=*) INST="${1#--instance=}"; shift ;;
    --color) shift; COLOR="${1:-auto}"; shift || true ;;
    --color=*) COLOR="${1#--color=}"; shift ;;
    -h|--help) sed -n '2,10p' "$0" >&2; exit 3 ;;
    *) echo "status-line: unknown option: $1" >&2; exit 3 ;;
  esac
done
case "$COLOR" in auto|always|never) ;; *) echo "status-line: --color takes auto|always|never" >&2; exit 3 ;; esac

# Claude Code writes the session JSON here. Draining it is not optional — an unread pipe
# is a SIGPIPE on the writer's next line.
STDIN=""
[ -t 0 ] || STDIN="$(cat 2>/dev/null || true)"

json_str() { printf '%s' "$STDIN" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1; }

if [ -z "$INST" ]; then
  INST="${CLAUDE_PROJECT_DIR:-}"
  [ -n "$INST" ] || INST="$(json_str current_dir)"
  [ -n "$INST" ] || INST="$(json_str cwd)"
  [ -n "$INST" ] || INST="$PWD"
fi

# The bundle marker is `instance.config.json`, the same one session-banner.sh keys on.
# Walked up from the session's directory, because a session is as often in a subdirectory.
root=""
d="$INST"
for _ in 1 2 3 4 5 6 7 8; do
  [ -n "$d" ] && [ "$d" != "/" ] || break
  if [ -f "$d/instance.config.json" ]; then root="$d"; break; fi
  d="$(dirname "$d")"
done
# Outside a bundle this prints nothing at all rather than an error or an empty frame.
[ -n "$root" ] || exit 0

# COLOUR IS ON UNDER A BARE NON-TTY, AND THAT IS THE WHOLE POINT OF THIS BLOCK. A
# `statusLine` command's stdout is ALWAYS a pipe into Claude Code, which renders the SGR
# itself — so `[ -t 1 ]` would strip the colour off the one surface that must carry it.
# `NO_COLOR` and `--color never` are the opt-outs, exactly as everywhere else here.
# 3/4-bit, so `cli-theme.sh`'s `basic` tier is ASKED FOR BY NAME and nothing is probed:
# `COLORTERM` and `tput colors` are not reliably inherited by a process Claude Code spawns.
# One exception: working agents take the TRUECOLOR green, because basic 92 is whatever green
# the terminal's palette holds and the owner chose the brand's (cli-theme.sh's header).
use_color=0
case "$COLOR" in
  always) use_color=1 ;;
  never)  use_color=0 ;;
  *)      [ -z "${NO_COLOR:-}" ] && use_color=1 ;;
esac
# shellcheck source=cli-theme.sh
. "$(dirname "${BASH_SOURCE[0]:-$0}")/cli-theme.sh" 2>/dev/null
command -v ab_theme >/dev/null 2>&1 || ab_theme() { :; }
ab_theme "$use_color" truecolor
C_GREEN="${T_GREEN:-}"
ab_theme "$use_color" basic
C_B="${T_BOLD:-}"; C_DIM="${T_DIM:-}"; C_DIMI="${T_DIMI:-}"
C_BLUE="${T_BLUE:-}"; C_PINK="${T_PINK:-}"; C_OFF="${T_OFF:-}"
paint() { printf '%s%s%s' "$1" "$2" "$C_OFF"; }

UNKNOWN='?'

# Every number comes from counts.sh, which also writes them to AB_COUNTS for the pane. Not
# SNAPSHOT.json: its absence is the BOARD's off switch, and no redraw writes it — a tick,
# /loopd:board, the in-session writers and refresh-state.sh do (the last started below).
# shellcheck source=counts.sh
. "$(dirname "${BASH_SOURCE[0]:-$0}")/counts.sh" || exit 0
ab_counts "$root"
ab_write_counts "$root"
# A snapshot behind its documents — a task doc edited by hand, with no turn whose hook would
# refresh it — is rewritten by refresh-state.sh, detached. The check is `-nt` alone.
if ab_snapshot_stale "$root"; then
  nohup bash "$(dirname "${BASH_SOURCE[0]:-$0}")/refresh-state.sh" "$root" </dev/null >/dev/null 2>&1 &
fi

# --- the lock: one `[ -f ]`, never a call into tick-lock.sh ------------------------------
lock=free
[ -f "$root/$AB_LOCK" ] && lock=held

# --- last tick: log.md's last `* TICK` line ---------------------------------------------
# NOT `.tick-state`: tick-delta.sh refuses to stamp it while any task is in-progress, so it
# is guaranteed stale exactly while `in progress` is non-zero. An `open:` line counts — a tick
# that started and has not closed is still the last tick.
last="$UNKNOWN"
if [ -r "$root/$AB_LEDGER" ]; then
  ts="$(awk '/^\* TICK [0-9][0-9][0-9][0-9]-[0-9][0-9]-/ { t = $3 } END { print t }' \
        "$root/$AB_LEDGER" 2>/dev/null)"
  if [ -n "$ts" ]; then
    # The stamp is UTC and the reader is not. BSD first — it needs `-u` on the PARSE and a
    # second call to print local, and GNU `date` has no `-j` to be confused by.
    ep="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$ts" '+%s' 2>/dev/null)" || ep=""
    if [ -n "$ep" ]; then hm="$(date -r "$ep" '+%H:%M' 2>/dev/null)" || hm=""
    else                  hm="$(date -d "$ts" '+%H:%M' 2>/dev/null)" || hm=""; fi
    [ -n "$hm" ] && last="$hm"
  fi
fi

n_colour() { case "$1" in "$UNKNOWN") printf '%s' "$C_PINK" ;; 0) printf '%s' "$C_DIM" ;; *) printf '%s' "$2" ;; esac; }
SEP="$(paint "$C_DIM" ' · ')"

printf '%s' "$(paint "$C_B" 'loopd')"
printf '%s%s' "$SEP" "$(paint "$(n_colour "$CNT_IN_PROGRESS" "$C_BLUE")" "$CNT_IN_PROGRESS in progress")"
[ "$CNT_IN_REVIEW" = 0 ] || \
  printf '%s%s' "$SEP" "$(paint "$(n_colour "$CNT_IN_REVIEW" "$C_BLUE")" "$CNT_IN_REVIEW in review")"
if [ "$CNT_WORKING" = "$UNKNOWN" ]; then
  printf '%s%s' "$SEP" "$(paint "$C_PINK" "$UNKNOWN working · $UNKNOWN idle · $UNKNOWN dead")"
else
  printf '%s%s' "$SEP" "$(paint "$(n_colour "$CNT_WORKING" "$C_GREEN")" "$CNT_WORKING working")"
  printf '%s%s' "$SEP" "$(paint "$(n_colour "$CNT_IDLE" "")" "$CNT_IDLE idle")"
  printf '%s%s' "$SEP" "$(paint "$(n_colour "$CNT_DEAD" "$C_PINK")" "$CNT_DEAD dead")"
fi
case "$CNT_QUEUE" in
  on)         printf '%s%s' "$SEP" "$(paint "$(n_colour "$CNT_NEED_YOU" "$C_PINK")" "$CNT_NEED_YOU need you")" ;;
  unreadable) printf '%s%s' "$SEP" \
                "$(paint "$C_PINK" "${AB_AWAITING##*/} unreadable — chmod +r $AB_AWAITING")" ;;
esac
# A free lock is the resting state, so it says nothing; only a held one is news.
[ "$lock" = held ] && printf '%s%s' "$SEP" "$(paint "$C_BLUE" 'lock held')"
if [ "$last" = "$UNKNOWN" ]; then printf '%s%s\n' "$SEP" "$(paint "$C_PINK" "last tick $UNKNOWN")"
else                              printf '%s%s\n' "$SEP" "$(paint "$C_DIMI" "last tick $last")"; fi
exit 0
