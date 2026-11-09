#!/usr/bin/env bash
# memory-stale.sh — list Claude Code auto-memory notes of this bundle that name something
# no longer true: a done/cancelled task, a closed project, a loopd version older than ours.
# Prints `<file> · <reason>` per stale note — names and reasons, never note content. Writes nothing.
#
#   memory-stale.sh [--instance DIR]      (default: $CLAUDE_PROJECT_DIR, else $PWD)
#
# Memory dir: ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<pwd -P, every non-[A-Za-z0-9] -> ->/memory.
# Exit: 0 dir read (listed or not) · 2 UNKNOWN, dir unresolvable or missing · 3 usage.
# Reasoning: article-batch-8-hygiene/task-004, project.md D2/D3/D7.
set -uo pipefail
shopt -s nullglob

root="${CLAUDE_PROJECT_DIR:-$PWD}"
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || { sed -n '6p' "$0" >&2; exit 3; }; root="$2"; shift 2 ;;
    --instance=*) root="${1#--instance=}"; shift ;;
    *) sed -n '6p' "$0" >&2; exit 3 ;;
  esac
done

real="$(cd "$root" 2>/dev/null && pwd -P)" || { echo "UNKNOWN: bundle root $root does not resolve"; exit 2; }
mem="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(printf '%s' "$real" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')/memory"
[ -d "$mem" ] || { echo "UNKNOWN: no memory dir at $mem"; exit 2; }

ver="$(tr -d '[:space:]' < "$(dirname "${BASH_SOURCE[0]:-$0}")/../VERSION" 2>/dev/null)"

add() { reasons="${reasons:+$reasons; }$1"; }
for f in "$mem"/*.md; do
  [ -f "$f" ] || continue
  reasons=""

  while IFS='/' read -r slug id; do
    for doc in "$real/projects/$slug/tasks/$id".md "$real/projects/$slug/tasks/$id"-*.md; do
      [ -f "$doc" ] || continue
      st="$(awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} /^status:/ {sub(/^status:[ \t]*/,""); gsub(/["\047 \t]/,""); print; exit}' "$doc")"
      case "$st" in done|cancelled) add "task $slug/$id is $st" ;; esac
      break
    done
  done < <(LC_ALL=C grep -oE '([a-z0-9][a-z0-9_-]*/tasks/|[A-Za-z0-9][A-Za-z0-9_-]*/)task-[0-9]+' "$f" | sed 's#/tasks/#/#' | sort -u)

  while IFS= read -r p; do
    [ -d "$real/$p" ] || add "$p has no folder (closed)"
  done < <(LC_ALL=C grep -oE '(^|[^A-Za-z0-9_./~-])/?projects/[a-z0-9][a-z0-9_-]*' "$f" | sed 's#^.*projects/#projects/#' | sort -u)

  # D2/D7: a version right after one of these words is history, not a claim about now.
  [ -n "$ver" ] && while IFS= read -r v; do
    add "names loopd $v, older than $ver"
  done < <(LC_ALL=C awk -v cur="$ver" '
    function older(a, b,   x, y, i) {
      split(a, x, "."); split(b, y, ".")
      for (i = 1; i <= 3; i++) if (x[i] + 0 != y[i] + 0) return x[i] + 0 < y[i] + 0
      return 0
    }
    {
      line = $0
      while (match(line, /(^|[^A-Za-z0-9])([Ll][Oo][Oo][Pp][Dd][ \t]+[vV]?|v)[0-9]+\.[0-9]+\.[0-9]+/)) {
        tok = substr(line, RSTART, RLENGTH); pre = tolower(substr(line, 1, RSTART))
        line = substr(line, RSTART + RLENGTH)
        sub(/^[^0-9]*/, "", tok)
        sub(/[ \t]+$/, "", pre)
        if (pre ~ /(^|[^a-z])(since|from|before|until|as of|measured on|fixed by|fixed in|on)$/) continue
        if (older(tok, cur)) print tok
      }
    }' "$f" | sort -u)

  [ -z "$reasons" ] || printf '%s · %s\n' "$(basename "$f")" "$reasons"
done
exit 0
