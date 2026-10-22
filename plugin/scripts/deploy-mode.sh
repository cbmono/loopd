#!/usr/bin/env bash
# deploy-mode.sh — does merging this task ship it, or does a human still deploy it? Prints
# exactly one of `manual`, `auto`, `n/a` (a research task) or `UNKNOWN` (stderr says why).
#   deploy-mode.sh <task-doc> [--instance <bundle>]
# Order: the task's `deploy:`, else the Service docs `service-doc.sh --ties` matches (any of
# them `manual` ⇒ manual, never a slug-order pick), else `auto` — `deploy:` is opt-in. A
# value other than manual|auto, or a matched doc it cannot read, is UNKNOWN.
# Exit: 0 manual/auto/n/a · 2 usage · 3 UNKNOWN. Reasoning: kb-retrieval-and-papercut-fixes/task-008.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
usage() { sed -n '2,8p' "$0" >&2; exit 2; }
unknown() { echo "deploy-mode: $1" >&2; echo UNKNOWN; exit 3; }
TASK=""; INSTANCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || usage; INSTANCE="$2"; shift 2 ;;
    -h|--help|-*) usage ;;
    *) [ -z "$TASK" ] || usage; TASK="$1"; shift ;;
  esac
done
[ -n "$TASK" ] || usage

fm() { # <file> -> its frontmatter; exit 1 unless opened and closed by ---
  [ -r "$1" ] || return 1
  awk 'NR == 1 { if ($0 != "---") exit; next } $0 == "---" { ok = 1; exit } { print }
       END { exit !ok }' "$1"
}
val() { # <key> <frontmatter> -> every value of <key>, one per line, unquoted
  printf '%s\n' "$2" | sed -n "s/^$1:[[:space:]]*//p" |
    sed "s/[[:space:]]#.*//; s/[[:space:]]*\$//; s/^\"\\(.*\\)\"\$/\\1/; s/^'\\(.*\\)'\$/\\1/"
}
mode_of() { # <doc> -> manual | auto | nothing (absent); exit 1 unreadable or not one value
  local f v
  f="$(fm "$1")" || return 1
  v="$(val deploy "$f" | grep . | sort -u)"
  case "$v" in ""|manual|auto) printf '%s' "$v" ;; *) return 1 ;; esac
}

TFM="$(fm "$TASK")" || unknown "cannot read a task document at $TASK"
kind="$(val kind "$TFM" | head -n 1)"
PM="$(dirname "$TASK")/../project.md"
[ -n "$kind" ] || { [ -f "$PM" ] && kind="$(val kind "$(fm "$PM")" | head -n 1)"; }
[ "$kind" = research ] && { echo n/a; exit 0; }

own="$(mode_of "$TASK")" || unknown "deploy: in $TASK is not one of manual, auto"
[ -n "$own" ] && { echo "$own"; exit 0; }

bash "$HERE/service-doc.sh" --repo "$TASK" >/dev/null 2>&1 || unknown "no target_repo on $TASK or its project"
docs="$(bash "$HERE/service-doc.sh" --ties "$TASK" ${INSTANCE:+--instance "$INSTANCE"})"
case $? in 0) ;; 1) echo auto; exit 0 ;; *) unknown "service-doc.sh could not match $TASK" ;; esac
out=auto
while IFS= read -r d; do
  [ -n "$d" ] || continue
  m="$(mode_of "$d")" || unknown "cannot read one deploy: value in $d"
  [ "$m" = manual ] && out=manual
done <<EOF
$docs
EOF
echo "$out"
