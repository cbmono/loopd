#!/usr/bin/env bash
#
# design-inputs.sh — fingerprint of what a project's design.md was drawn from.
#
#   Usage: design-inputs.sh <project-dir>
#
# Prints 16 hex: SHA-256 over the decisions and, per refined non-cancelled task, its
# criteria and ANSWERED questions. Step 2 writes it as `inputs_hash:`; tick-delta.sh
# reports a `redraw stale` DELTA on a mismatch. A fold's stamp is stripped and lists are
# sorted, so folding changes nothing; unanswered questions and a decision's reply are
# left out (an overturn rewrites the D<n> text, which counts).
# Exit: 0 printed · 1 unreadable input, never a guessed hash · 2 usage.
set -uo pipefail

[ $# -eq 1 ] && [ -d "$1" ] || { sed -n 5p "$0" >&2; exit 2; }
d="${1%/}"
FOLD="$(dirname "${BASH_SOURCE[0]}")/fold-answers.sh"
STAMP='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z by .*? · '

lst() { bash "$FOLD" --list "$1" "$2" 2>/dev/null || exit 1; }
unstamp() { perl -pe "s/$STAMP//"; }
answered() { perl -ne 'chomp; print "$_\n" if / --- (.*)$/ && $1 =~ /\S/'; }
sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi | cut -c1-16; }

# Gathered first: a failure piped into `sha` would still hash the partial input.
gather() {
  local p="$d/project.md" f st crit dec qs
  if [ -f "$p" ]; then
    [ -r "$p" ] || return 1
    dec="$(lst "$p" decisions && lst "$p" acknowledged_decisions)" || return 1
    printf 'P\n'; printf '%s\n' "$dec" | unstamp | perl -pe 's/ --- .*$//' | LC_ALL=C sort
  fi
  for f in "$d"/tasks/task-*.md; do
    [ -f "$f" ] || continue
    [ -r "$f" ] || return 1
    st="$(sed -n 's/^status:[[:space:]]*\([A-Za-z-]*\).*/\1/p' "$f" | head -n1)"
    [ "$st" = cancelled ] && continue
    crit="$(lst "$f" acceptance_criteria)" || return 1
    [ -n "$crit" ] || continue
    qs="$(lst "$f" open_questions | answered && lst "$f" answered_questions)" || return 1
    printf 'T %s\n%s\n' "$(basename "$f" | grep -oE '^task-[0-9]+')" "$crit"
    printf '%s\n' "$qs" | unstamp | LC_ALL=C sort
  done
}
body="$(gather)" || exit 1
printf '%s\n' "$body" | sha
