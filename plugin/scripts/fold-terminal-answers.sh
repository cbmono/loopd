#!/usr/bin/env bash
# fold-terminal-answers.sh — fold the ` --- `-answered `open_questions` of every `done` or
# `cancelled` task, in any project, paused included, through fold-answers.sh.
#   Usage: fold-terminal-answers.sh [--instance DIR]
# Prints `folded <path>` per document rewritten and `skipped <path> <reason>` per document left
# untouched (fold-answers.sh exit 3/4, project-paused.sh exit 2); paths instance-relative.
# Exit: 0 ran · 2 usage or not an instance root. A writer, so never a tick-delta.sh mode.
# Live tasks keep the model fold: their answer is the step 2 / step 4 trigger.
# Verified by tests/fold-terminal-answers.test.sh.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)" || exit 2
. "$HERE/bundle-paths.sh" || exit 2

inst="."
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || { sed -n 4p "$0" >&2; exit 2; }; inst="$2"; shift 2 ;;
    *) sed -n 4p "$0" >&2; exit 2 ;;
  esac
done
cd "$inst" 2>/dev/null && ab_is_bundle . || { echo "fold-terminal-answers: not an instance root: $inst" >&2; exit 2; }
ERR="$(mktemp "${TMPDIR:-/tmp}/fold-terminal.XXXXXX")" || exit 2
trap 'rm -f "$ERR"' EXIT

why() { tr -d '\000-\037\177' < "$ERR" | sed 's/^fold-answers: //' | cut -c1-200; }

for f in projects/*/tasks/*.md; do
  [ -f "$f" ] || continue
  st="$(sed -n 's/^status:[[:space:]]*\([A-Za-z-]*\).*/\1/p' "$f" | head -n1)"
  case "$st" in done|cancelled) ;; *) continue ;; esac
  grep -qF -- ' --- ' "$f" || continue
  bash "$HERE/project-paused.sh" "$f" >/dev/null 2>"$ERR"
  [ $? = 2 ] && { echo "skipped $f project-paused: $(why)"; continue; }
  out="$(bash "$HERE/fold-answers.sh" --instance . "$f" 2>"$ERR")"; rc=$?
  case "$rc" in
    0) case "$out" in folded:*) echo "folded $f" ;; esac ;;
    *) echo "skipped $f fold-answers exit $rc: $(why)" ;;
  esac
done
exit 0
