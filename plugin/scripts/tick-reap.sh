#!/usr/bin/env bash
# tick-reap.sh — the launcher's one read: has the bg tick tick-spawn.sh recorded on the lock
# finished? Run before every `tick-lock.sh acquire`. Releases the lock only on a COMMITTED
# ledger close for the lock's minted id, or after closing the entry itself when the session
# ended without one; then prints that close line, Needs-you from AWAITING.md and a COST: line.
#
#   tick-reap.sh [--instance DIR] [--wait]   (--wait: poll until the tick is not live)
#
# Exit: 0 nothing held, or reaped and released · 1 live, drop this fire (--wait: past budget)
#       2 cannot tell, lock kept · 3 usage · 4 BLOCKED, lock kept · 5 --wait slice over, rerun
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 3

inst="."; wait=no
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || { echo "tick-reap: --instance needs a directory" >&2; exit 3; }
                inst="$2"; shift 2 ;;
    --wait) wait=yes; shift ;;
    *) echo "Usage: $(basename "$0") [--instance DIR] [--wait]" >&2; exit 3 ;;
  esac
done
[ -d "$inst" ] || { echo "tick-reap: no such instance directory: $inst" >&2; exit 3; }
LOCK="$inst/$AB_LOCK"; LOG="$inst/$AB_LEDGER"
TERMINAL=" done gone stopped completed cancelled failed error exited "

field() { awk -v k="$1" '!/^#/ && index($0, k ":") == 1 { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }' "$LOCK" 2>/dev/null; }

# <ledger text on stdin> -> "closed <line>" | "open <ts>" | "none". A line carrying the id
# whose first marker is not ` open: ` (the idle line, a close) is already closed.
scan() {
  ID="$tick" awk '
    /^\* TICK / {
      o = index($0, " open: "); c = index($0, " close: ")
      if (c > 0 && (o == 0 || c < o)) { cl[$3] = $0 }
      if (index($0, ENVIRON["ID"]) == 0) next
      if (o > 0 && (c == 0 || o < c)) ots = $3; else done = $0
    }
    END {
      if (done != "") print "closed " done
      else if (ots != "" && (ots in cl)) print "closed " cl[ots]
      else if (ots != "") print "open " ots
      else print "none"
    }'
}

needs_you() {
  [ -r "$inst/$AB_AWAITING" ] || return 0
  echo "Needs you:"
  awk '/^## 🔴 Awaiting you/ { p = 1; next } p && /^## / { exit } p && NF' "$inst/$AB_AWAITING"
}

cost() {
  local u t n m
  u="$(bash "$HERE/session-usage.sh" "$session" 2>/dev/null)" || return 0
  t="$(sed -n 's/.* tokens=\([0-9]*\).*/\1/p' <<<"$u")"
  n="$(sed -n 's/.* tools=\([0-9]*\).*/\1/p' <<<"$u")"
  m="$(sed -n 's/.* ms=\([0-9]*\).*/\1/p' <<<"$u")"
  u="$(bash "$HERE/agent-usage.sh" fmt --tokens "$t" --tools "$n" --duration-ms "$m")" || return 0
  [ "$u" = "usage UNKNOWN" ] || echo "COST: $u"
}

release() { # <verdict> <close line>
  bash "$HERE/tick-lock.sh" release --instance "$inst" || { echo "tick-reap: could not release $LOCK" >&2; exit 2; }
  case "$state" in blocked|idle-after-close) claude stop "$short" >/dev/null 2>&1 </dev/null ;; esac
  echo "reaped: $tick · $1 · session $short $state"
  printf '%s\n' "$2"
  needs_you
  cost
  exit 0
}

# <- the row's `status` ("idle" once the session's turn is over); empty when unreadable
turn_status() {
  bash "$HERE/agent-sessions.sh" row "$session" 2>/dev/null \
    | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
}

# -> exits on every outcome but "live" (returns 1) and "finishing" (returns 2)
assess() {
  [ -e "$LOCK" ] || exit 0
  session="$(field session)"; tick="$(field claimant)"
  [ -n "$session" ] || exit 0
  [ -n "$tick" ] || { echo "tick-reap: $LOCK records a session and no claimant — leaving it for a human" >&2; exit 2; }
  short="${session%%-*}"
  state="$(bash "$HERE/agent-sessions.sh" state "$session" 2>/dev/null)" || state=unknown
  disk="$(scan < "$LOG" 2>/dev/null)" || disk=none
  head="$(git -C "$inst" show "HEAD:$AB_LEDGER" 2>/dev/null | scan)" || head=none
  case "$head" in
    closed\ *)
      # A bg session does not exit after its turn: the daemon retires it after ~60m idle,
      # and `state` reads `working` all that while (measured 2026-10-31: 40m past a
      # committed close, three fires dropped). `status: idle` is the turn over, so stop it
      # as for `blocked` rather than hold the lock an hour. Anything else is still finishing.
      if [ "$state" = working ]; then
        [ "$(turn_status)" = idle ] || return 2
        state=idle-after-close
      fi
      release closed "${head#closed }" ;;
  esac
  case "$state" in
    working|idle) return 1 ;;
    blocked)
      echo "BLOCKED: tick $tick (session $short) is blocked before a committed close — claude attach $short to answer it, or claude stop $short; the next fire then closes it." >&2
      exit 4 ;;
    unknown)
      echo "UNKNOWN: cannot read session $short for tick $tick (agent-sessions.sh) — the lock stays; nothing dispatched." >&2
      exit 2 ;;
  esac
  case "$TERMINAL" in *" $state "*) ;; *) return 1 ;; esac
  case "$disk" in
    closed\ *) release "closed, uncommitted" "${disk#closed }" ;;
    open\ *)
      ts="${disk#open }"
      bash "$HERE/tick-delta.sh" record --instance "$inst" --tick "$ts" \
        --close "dead — $tick session $short $state with its entry open (tick-reap)" >/dev/null \
        || { echo "tick-reap: could not close the dead tick's entry at $ts — the lock stays." >&2; exit 2; }
      release dead "$(scan < "$LOG" | sed 's/^closed //')" ;;
  esac
  login="$(cd "$inst" && bash "$HERE/decision-stamp.sh" --self 2>/dev/null)" || login="<unknown>"
  line="* TICK $(date -u +%Y-%m-%dT%H:%M:%SZ) by ${login:-<unknown>} close: $tick ended with no ledger entry — session $short $state (tick-reap)"
  printf '%s\n' "$line" >> "$LOG" || { echo "tick-reap: cannot append to $LOG — the lock stays." >&2; exit 2; }
  release ended "$line"
}

if [ "$wait" = no ]; then
  assess; rc=$?
  [ "$rc" -eq 2 ] && msg="closed its entry and is still finishing" || msg="in progress (session $short, $state)"
  echo "tick $tick $msg — nothing to dispatch this pass."
  exit 1
fi

budget="$(bash "$HERE/resolve-config.sh" --instance "$inst" roleMinutes project-manager 2>/dev/null)" \
  || budget="$(bash "$HERE/resolve-config.sh" --instance "$inst" maxAgentMinutes 2>/dev/null)" || budget=45
case "$budget" in ''|0|*[!0-9]*) budget=45 ;; esac
poll="${TICK_REAP_POLL:-15}"; slice_end=$(( $(date +%s) + ${TICK_REAP_SLICE:-540} ))
while :; do
  assess
  started="$(field spawned)"; case "$started" in ''|*[!0-9]*) started="$(field epoch)" ;; esac
  if [ $(( $(date +%s) - ${started:-0} )) -ge $(( budget * 60 )) ]; then
    echo "tick $tick still running past its ${budget}m budget — not waiting longer; the next /${PLUGIN_NAME:-loopd}:dispatch reaps it."
    exit 1
  fi
  [ "$(date +%s)" -lt "$slice_end" ] || { echo "waiting: tick $tick is still running — run this again."; exit 5; }
  sleep "$poll"
done
