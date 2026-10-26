#!/usr/bin/env bash
#
# resolve-effort.sh — print the reasoning effort a given agent should be spawned at.
#
#   Usage: resolve-effort.sh <agent-name> [--instance DIR]
#          resolve-effort.sh --all        [--instance DIR]
#
# Reads `roleEffort[<agent>]` through resolve-config.sh (local file first, tracked second).
# Absent key or map: prints nothing, exit 0 — the caller passes no effort. An unknown level:
# prints nothing, exit 1, one stderr line naming role and value. `--all`: one row per
# `roleEffort` entry, `<role> TAB <from> TAB <level>`, level empty when unknown. Exit 2: usage.
set -uo pipefail

LEVELS="low medium high xhigh max"
agent=""; inst="."; all=0
while [ $# -gt 0 ]; do
  case "$1" in
    --instance)
      [ $# -ge 2 ] || { echo "resolve-effort: --instance needs a directory" >&2; exit 2; }
      inst="$2"; shift 2 ;;
    --all) all=1; shift ;;
    -h|--help) sed -n '3,6p' "$0"; exit 0 ;;
    -*) echo "resolve-effort: unknown flag $1" >&2; exit 2 ;;
    *) agent="$1"; shift ;;
  esac
done
if [ "$all" -eq 1 ]; then
  [ -z "$agent" ] || { echo "resolve-effort: --all takes no agent name (got '$agent')" >&2; exit 2; }
else
  [ -n "$agent" ] || {
    echo "Usage: resolve-effort.sh <agent-name> [--instance DIR]" >&2
    echo "       resolve-effort.sh --all        [--instance DIR]" >&2; exit 2; }
fi

self="${BASH_SOURCE[0]:-$0}"
[ -L "$self" ] && self="$(readlink "$self" 2>/dev/null || printf '%s' "$self")"
here="$(cd "$(dirname "$self")" 2>/dev/null && pwd)" || here=""
resolver="$here/resolve-config.sh"
[ -n "$here" ] && [ -f "$resolver" ] || {
  echo "resolve-effort: resolve-config.sh not found beside this script" >&2; exit 2; }

dump="$(bash "$resolver" --instance "$inst" --dump)" || dump=""
tab=$'\t'

# check_one <role> <value> — 0 for a known level; else the one stderr line and 1.
check_one() {
  local l
  for l in $LEVELS; do [ "$2" = "$l" ] && return 0; done
  echo "resolve-effort: unknown effort '$2' for '$1' in roleEffort — expected one of: $LEVELS" >&2
  return 1
}

rc=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  from="${line%%"$tab"*}"; rest="${line#*"$tab"}"; k="${rest%%"$tab"*}"
  rest="${rest#*"$tab"}"; role="${rest%%"$tab"*}"; value="${rest#*"$tab"}"
  [ "$k" = roleEffort ] && [ -n "$role" ] || continue
  if [ "$all" -eq 1 ]; then
    check_one "$role" "$value" || { rc=1; value=""; }
    printf '%s\t%s\t%s\n' "$role" "$from" "$value"
  elif [ "$role" = "$agent" ]; then
    check_one "$role" "$value" || exit 1
    printf '%s\n' "$value"
    break
  fi
done <<EOF2
$dump
EOF2
exit "$rc"
