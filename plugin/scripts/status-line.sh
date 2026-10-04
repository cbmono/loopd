#!/usr/bin/env bash
#
# status-line.sh — one line for Claude Code's `statusLine`: what is in flight, which agent
# sessions have a process, what waits on the human, the lock, when the last tick was.
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
# 3/4-bit only, so `cli-theme.sh`'s `basic` tier is ASKED FOR BY NAME and nothing is probed:
# `COLORTERM` and `tput colors` are not reliably inherited by a process Claude Code spawns.
use_color=0
case "$COLOR" in
  always) use_color=1 ;;
  never)  use_color=0 ;;
  *)      [ -z "${NO_COLOR:-}" ] && use_color=1 ;;
esac
# shellcheck source=cli-theme.sh
. "$(dirname "${BASH_SOURCE[0]:-$0}")/cli-theme.sh" 2>/dev/null
command -v ab_theme >/dev/null 2>&1 || ab_theme() { :; }
ab_theme "$use_color" basic
C_B="${T_BOLD:-}"; C_DIM="${T_DIM:-}"; C_DIMI="${T_DIMI:-}"
C_BLUE="${T_BLUE:-}"; C_PINK="${T_PINK:-}"; C_OFF="${T_OFF:-}"
paint() { printf '%s%s%s' "$1" "$2" "$C_OFF"; }

UNKNOWN='?'

# --- in flight: the task frontmatter, directly ------------------------------------------
# Not SNAPSHOT.json: its absence is the BOARD's off switch, and it carries in-flight only
# as a per-task boolean. One awk pass, first frontmatter block of each task document.
inflight="$UNKNOWN"
if [ -d "$root/projects" ]; then
  set -- "$root"/projects/*/tasks/*.md
  if [ -e "$1" ]; then
    inflight="$(awk '
      FNR == 1 { fm = 0; hit = 0; if ($0 == "---") { fm = 1; next } }
      fm && $0 == "---" { fm = 0; next }
      fm && !hit && $0 ~ /^status:[[:space:]]*in-progress[[:space:]]*$/ { n++; hit = 1 }
      END { print n + 0 }
    ' "$@" 2>/dev/null)" || inflight="$UNKNOWN"
    [ -n "$inflight" ] || inflight="$UNKNOWN"
  else
    inflight=0
  fi
fi

# --- agents: PROCESSES behind this bundle's background sessions, not the registry's word ---
# The one segment that is not a file read: `agent-sessions.sh view --summary` runs
# `claude agents --json` (~150 ms), so its answer is cached per bundle for AGENTS_TTL
# seconds and every open session shares it. A failed read caches `?`, never `0 running`.
AGENTS_TTL=10
agents="$UNKNOWN"
a_cache="${XDG_CACHE_HOME:-$HOME/.cache}/loopd/agents-$(printf '%s' "$root" | cksum | cut -d' ' -f1)"
now="$(date +%s)"
a_ep=""; a_run=""; a_none=""
[ -r "$a_cache" ] && read -r a_ep a_run a_none < "$a_cache" 2>/dev/null
case "$a_ep" in ''|*[!0-9]*) a_ep=0 ;; esac
if [ $((now - a_ep)) -ge 0 ] && [ $((now - a_ep)) -lt "$AGENTS_TTL" ]; then
  agents="$a_run $a_none"
else
  agents="$(bash "$(dirname "${BASH_SOURCE[0]:-$0}")/agent-sessions.sh" view "$root" --summary \
            </dev/null 2>/dev/null)" || agents="$UNKNOWN"
  if mkdir -p "${a_cache%/*}" 2>/dev/null; then
    printf '%s %s\n' "$now" "$agents" > "$a_cache.$$" 2>/dev/null && mv -f "$a_cache.$$" "$a_cache" 2>/dev/null
    rm -f "$a_cache.$$" 2>/dev/null
  fi
fi
# Anything but two counts — a stale format, a truncated write — is unknown.
case "$agents" in
  [0-9]*' '[0-9]*) a_run="${agents%% *}"; a_none="${agents#* }"
                   case "$a_run$a_none" in *[!0-9]*) agents="$UNKNOWN" ;; esac ;;
  *) agents="$UNKNOWN" ;;
esac

# --- need you: AWAITING.md's own items, counted the way the banner counts them -----------
# THREE STATES, THREE RENDERINGS, and `[ -r ]` alone cannot tell the first two apart.
# ABSENT IS CHOSEN — build-awaiting.sh never recreates the file, so deleting it is how the
# queue is switched off, and a state the human typed is not an error: the segment goes.
# UNREADABLE IS ARRIVED AT, so it speaks, and it names its own repair in the line.
awaiting=""
queue=off
if [ -e "$root/$AB_AWAITING" ]; then
  queue=unreadable
  if [ -r "$root/$AB_AWAITING" ]; then
    queue=on
    awaiting="$(awk '
      /^##[[:space:]].*Awaiting you/ { inblk = 1; next }
      inblk && /^##[[:space:]]/      { exit }
      inblk && /^[[:space:]]*\* /    { n++ }
      END { print n + 0 }
    ' "$root/$AB_AWAITING" 2>/dev/null)" || awaiting="$UNKNOWN"
    [ -n "$awaiting" ] || awaiting="$UNKNOWN"
  fi
fi

# --- the lock: one `[ -f ]`, never a call into tick-lock.sh ------------------------------
lock=free
[ -f "$root/$AB_LOCK" ] && lock=held

# --- last tick: log.md's last `* TICK` line ---------------------------------------------
# NOT `.tick-state`: tick-delta.sh refuses to stamp it while any task is in-progress, so it
# is guaranteed stale exactly while `in flight` is non-zero. An `open:` line counts — a tick
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

printf '%s' "$(paint "$C_B" 'AI Bridge')"
printf '%s%s' "$SEP" "$(paint "$(n_colour "$inflight" "$C_BLUE")" "$inflight in flight")"
if [ "$agents" = "$UNKNOWN" ]; then
  printf '%s%s' "$SEP" "$(paint "$C_PINK" "agents $UNKNOWN")"
elif [ "$a_none" -gt 0 ]; then
  printf '%s%s' "$SEP" "$(paint "$C_PINK" "agents $a_run running, $a_none no process")"
else
  printf '%s%s' "$SEP" "$(paint "$(n_colour "$a_run" "$C_BLUE")" "agents $a_run running")"
fi
case "$queue" in
  on)         printf '%s%s' "$SEP" "$(paint "$(n_colour "$awaiting" "$C_PINK")" "$awaiting need you")" ;;
  unreadable) printf '%s%s' "$SEP" \
                "$(paint "$C_PINK" "${AB_AWAITING##*/} unreadable — chmod +r $AB_AWAITING")" ;;
esac
if [ "$lock" = held ]; then printf '%s%s' "$SEP" "$(paint "$C_BLUE" 'lock held')"
else                        printf '%s%s' "$SEP" "$(paint "$C_DIM" 'lock free')"; fi
if [ "$last" = "$UNKNOWN" ]; then printf '%s%s\n' "$SEP" "$(paint "$C_PINK" "last tick $UNKNOWN")"
else                              printf '%s%s\n' "$SEP" "$(paint "$C_DIMI" "last tick $last")"; fi
exit 0
