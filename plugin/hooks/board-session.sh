#!/usr/bin/env bash
#
# board-session.sh — ties an auto-started board server to the Claude sessions on a bundle.
#
#   Usage: board-session.sh start|end    (hook JSON on stdin; always exit 0, print nothing)
#          board-session.sh alive        (exit 0 while a recorded session lives, else 1)
#          board-session.sh enabled      (exit 0 when `boardServe` and `board` are on)
#
# start records the session and starts `board-serve.sh --detach --auto` if nothing serves;
# end drops its record, prunes dead ones and nudges the server, which alone decides to stop.
# Why: docs/operations.md § 5, "The server starts with the session".
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$here/../scripts/bundle-paths.sh" 2>/dev/null || exit 0
cmd="${1:-}"
root="${CLAUDE_PROJECT_DIR:-$PWD}"
if ! ab_is_bundle "$root"; then [ "$cmd" = alive ] && exit 1; exit 0; fi
dir="$root/$AB_BOARD_DIR"
sessions="$dir/sessions"

# The tracked file only, flattened, testing `false` alone — the banner's `board` reader.
enabled() {
  ! tr '\n' ' ' < "$root/instance.config.json" 2>/dev/null \
    | grep -q -e '"board"[[:space:]]*:[[:space:]]*false' -e '"boardServe"[[:space:]]*:[[:space:]]*false'
}

session_id() {
  local input=""
  [ -t 0 ] && return 1
  IFS= read -r -d '' -t 1 input || true
  printf '%s' "$input" | tr '\n' ' ' \
    | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9][A-Za-z0-9._-]\{0,127\}\)".*/\1/p' | grep .
}

started() { ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//'; }

# The hook runs under `sh -c`, so $PPID dies with the hook. A Node install shows as
# `node …/claude`, a native one as `claude`: either of the first two words counts.
claude_pid() {
  local p=$$ a b _ i=0
  while [ "$i" -lt 40 ]; do
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
    case "$p" in ''|*[!0-9]*|0|1) return 1 ;; esac
    read -r a b _ <<<"$(ps -o args= -p "$p" 2>/dev/null)"
    if [ "${a##*/}" = claude ] || [ "${b##*/}" = claude ]; then echo "$p"; return 0; fi
    i=$((i + 1))
  done
  return 1
}

record_alive() { # <record file>
  local pid="" start=""
  { read -r pid; read -r start; } 2>/dev/null < "$1"
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null && [ -n "$start" ] && [ "$(started "$pid")" = "$start" ]
}

prune() { # exit 0 when a live record remains
  local f rc=1
  for f in "$sessions"/*; do
    [ -f "$f" ] || continue
    if record_alive "$f"; then rc=0; else rm -f "$f"; fi
  done
  return "$rc"
}

SPORT="" SPID="" SOWNER=""
serving() {
  local r=""
  { read -r SPORT; read -r SPID; read -r r; read -r SOWNER; } 2>/dev/null < "$dir/.serve"
  case "$SPORT$SPID" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$SPID" 2>/dev/null
}

case "$cmd" in
  enabled) enabled; exit ;;
  alive) prune; exit ;;
  start)
    enabled || exit 0
    sid="$(session_id)" || exit 0
    command -v python3 >/dev/null 2>&1 || exit 0
    cpid="$(claude_pid)" || exit 0
    mkdir -p "$sessions" 2>/dev/null || exit 0
    # Written aside and moved, so `alive` never reads half a record and prunes it.
    printf '%s\n%s\n' "$cpid" "$(started "$cpid")" > "$sessions/.$sid.$$" \
      && mv -f "$sessions/.$sid.$$" "$sessions/$sid"
    serving && exit 0
    ( cd "$root" && bash "$here/../scripts/board-serve.sh" --detach --auto ) </dev/null >/dev/null 2>&1
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
      serving && break
      sleep 0.1
    done
    exit 0 ;;
  end)
    if sid="$(session_id)"; then rm -f "$sessions/$sid"; fi
    prune
    if serving && [ "$SOWNER" = auto ]; then kill -USR1 "$SPID" 2>/dev/null; fi
    exit 0 ;;
  *) echo "board-session: usage: board-session.sh start|end|alive|enabled" >&2; exit 2 ;;
esac
