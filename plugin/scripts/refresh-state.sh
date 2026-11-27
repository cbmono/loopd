#!/usr/bin/env bash
#
# refresh-state.sh — bring a bundle's .loopd/counts.json, SNAPSHOT.json and METRICS.json up to
# date now, between ticks, so /pane follows a session's turn.   Usage: refresh-state.sh <root>
# counts.json: every run, through counts.sh (CNT_FRESH skips its `claude agents` cache).
# SNAPSHOT.json: through write-snapshot.sh, its one writer, only while ab_snapshot_stale says
# a document moved since the snapshot and the last attempt (the stamp).
# METRICS.json: one detached metrics.sh run, reading no PR, when the file is absent or older
# than the newest full tick; one attempt per tick, killed after REFRESH_STATE_METRICS_MAX
# seconds (600 when unset). Rules: docs/metrics.md → "When it is written".
# Started detached by hooks/refresh-state.sh and status-line.sh. One run per root (a mkdir lock,
# a dead run's taken over after 2 min); a burst coalesces in REFRESH_STATE_DEBOUNCE (2 s). Prints
# nothing, exits 0; no network, no model, no tracked file.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)" || exit 0
. "$here/bundle-paths.sh" 2>/dev/null || exit 0
. "$here/counts.sh" 2>/dev/null || exit 0

root="$(ab_board_root "${1:-}")" && cd "$root" 2>/dev/null || exit 0   # never a raw argv
stamp="$(ab_refresh_stamp "$root")"
# status-line.sh asks ab_snapshot_stale under ITS spelling of the root, uncanonicalised; a
# stamp only under this one left a failing writer restarted on every redraw via a symlink.
astamp="$(ab_refresh_stamp "$1")"
lock="$stamp.lock"
mkdir -p "${stamp%/*}" 2>/dev/null || exit 0
wait_s="${REFRESH_STATE_DEBOUNCE:-2}"
case "$wait_s" in ''|*[!0-9]*) wait_s=2 ;; esac
max_s="${REFRESH_STATE_METRICS_MAX:-600}"
case "$max_s" in ''|*[!0-9]*) max_s=600 ;; esac

metrics_run() { # <full tick> <deadline, epoch seconds>
  local m rc
  trap '' HUP
  METRICS_GH_MAX_PRS=0 METRICS_LOCK_WAIT=0 bash "$here/metrics.sh" "$root" & m=$!
  while kill -0 "$m" 2>/dev/null && [ "$(date +%s)" -lt "$2" ]; do sleep 0.2; done
  kill "$m" 2>/dev/null; wait "$m"; rc=$?
  [ "$rc" -eq 0 ] || [ -L "$AB_METRICS_RUN" ] || printf 'exit %s close %s\n' "$rc" "$1" > "$AB_METRICS_RUN/failed"
}
metrics_refresh() {
  local run="$AB_METRICS_RUN" last gen
  command -v jq >/dev/null 2>&1 || return 0
  [ -f "$AB_SNAPSHOT" ] && [ "$(jq -r '.board == false' instance.config.json 2>/dev/null)" = false ] || return 0
  [ ! -L "$run" ] || return 0
  if [ -d "$run/lock" ]; then
    [ -n "$(find "$run/lock" -maxdepth 0 -mmin +10 2>/dev/null)" ] || return 0
    rmdir "$run/lock" 2>/dev/null || return 0
  fi
  last="$(ab_last_full_tick "$AB_LEDGER")"
  case "$last" in *[!0-9TZ:.+-]*) return 0 ;; esac
  if [ -f "$AB_METRICS" ]; then
    gen="$(jq -r '.generated_at // empty | strings' "$AB_METRICS" 2>/dev/null)"
    [ -n "$last" ] && [[ "$gen" < "$last" ]] || return 0
  fi
  last="${last:-none}"
  [ "$(cat "$run/attempt" 2>/dev/null)" != "$last" ] || return 0
  mkdir -p "$run" 2>/dev/null && [ ! -L "$run" ] && { [ -e "$run/.gitignore" ] || printf '*\n' > "$run/.gitignore"; } || return 0
  printf '%s\n' "$last" > "$run/attempt" 2>/dev/null || return 0
  metrics_run "$last" "$(( $(date +%s) + max_s ))" </dev/null >/dev/null 2>&1 &
}

for i in 1 2 3; do
  if ! mkdir "$lock" 2>/dev/null; then
    [ -n "$(find "$lock" -maxdepth 0 -mmin +2 2>/dev/null)" ] || exit 0
    rm -rf "$lock" 2>/dev/null; mkdir "$lock" 2>/dev/null || exit 0
  fi
  [ "$wait_s" -gt 0 ] && sleep "$wait_s"
  CNT_FRESH=1 ab_counts "$root"
  ab_write_counts "$root"
  pass=0
  while [ "$pass" -lt 3 ] && ab_snapshot_stale "$root" "$stamp"; do
    : > "$stamp" 2>/dev/null || break   # stamped first: an edit during the write is newer
    # Backdated to the stamp: an edit made during the write must stay newer than the snapshot.
    bash "$here/write-snapshot.sh" --quiet </dev/null >/dev/null 2>&1 && touch -r "$stamp" "$AB_SNAPSHOT" 2>/dev/null
    pass=$((pass + 1))
  done
  [ "$i" -gt 1 ] || metrics_refresh
  rmdir "$lock" 2>/dev/null
  ab_snapshot_stale "$root" "$stamp" || { [ "$astamp" = "$stamp" ] || : > "$astamp" 2>/dev/null; exit 0; }
done
exit 0
