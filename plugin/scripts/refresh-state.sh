#!/usr/bin/env bash
#
# refresh-state.sh — bring a bundle's .loopd/counts.json and .loopd/SNAPSHOT.json up to date
# now, between ticks, so /pane follows a session's turn.   Usage: refresh-state.sh <root>
#
# counts.json: every run, through counts.sh (CNT_FRESH skips its `claude agents` cache).
# SNAPSHOT.json: through write-snapshot.sh, its one writer, only while ab_snapshot_stale says
# a document moved since the snapshot and the last attempt (the stamp).
# Started detached by hooks/refresh-state.sh and status-line.sh. One run per root (a mkdir
# lock, a dead run's taken over after 2 min); a burst coalesces in REFRESH_STATE_DEBOUNCE (2 s).
# Prints nothing, exits 0; no network, no model, no tracked file.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)" || exit 0
. "$here/bundle-paths.sh" 2>/dev/null || exit 0
. "$here/counts.sh" 2>/dev/null || exit 0

root="${1:-}"
[ -n "$root" ] && ab_is_bundle "$root" && cd "$root" 2>/dev/null || exit 0
stamp="$(ab_refresh_stamp "$root")"
lock="$stamp.lock"
mkdir -p "${stamp%/*}" 2>/dev/null || exit 0
wait_s="${REFRESH_STATE_DEBOUNCE:-2}"
case "$wait_s" in ''|*[!0-9]*) wait_s=2 ;; esac

for _ in 1 2 3; do
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
    bash "$here/write-snapshot.sh" --quiet </dev/null >/dev/null 2>&1
    pass=$((pass + 1))
  done
  rmdir "$lock" 2>/dev/null
  ab_snapshot_stale "$root" "$stamp" || exit 0
done
exit 0
