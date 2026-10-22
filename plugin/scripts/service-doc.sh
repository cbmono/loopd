#!/usr/bin/env bash
# service-doc.sh — the ONE matcher from a task to its Service doc; dispatch-brief.sh and any
# other resolver call it rather than keep a second one.
#   service-doc.sh <task-doc> [--instance <bundle>]   prints knowledge/services/<slug>.md
#   service-doc.sh --repo <task-doc>                  prints the resolved target repo
#   service-doc.sh --ties <task-doc>                  every equally-ranked doc, one per line
# Repo: the task's target_repo:, else its project.md's. Candidates: repo: equal, status: not
# deprecated. Several ⇒ a literal path the task names (longest first), then
# <repo-basename>.md, then the lexically first slug. Exit: 0 printed · 1 no match · 2
# unreadable task, usage, or (--ties) an unreadable services doc that may be the match.
# Reasoning: kb-retrieval-and-papercut-fixes/task-003.
set -uo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/kb-words.sh" || exit 2

usage() { sed -n '2,11p' "$0" >&2; exit 2; }
TASK=""; INSTANCE=""; MODE=doc
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || usage; INSTANCE="$2"; shift 2 ;;
    --repo) MODE=repo; shift ;;
    --ties) MODE=ties; shift ;;
    -h|--help) usage ;;
    -*) echo "service-doc: unexpected option '$1'" >&2; usage ;;
    *) [ -z "$TASK" ] || usage; TASK="$1"; shift ;;
  esac
done
[ -n "$TASK" ] || usage
{ [ -f "$TASK" ] && [ -r "$TASK" ] && [ "$(head -n 1 "$TASK")" = --- ]; } ||
  { echo "service-doc: cannot read a task document at $TASK" >&2; exit 2; }
TASK_DIR="$(cd "$(dirname "$TASK")" && pwd)"

fm_value() { # <key> <file> — first occurrence in the frontmatter, unquoted
  awk -v key="$1" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, key ":") == 1 {
      v = $0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+#.*/, "", v); sub(/[ \t]+$/, "", v)
      if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
      print v; exit
    }' "$2"
}

REPO="$(fm_value target_repo "$TASK")"
if [ -z "$REPO" ] && [ "${TASK_DIR##*/}" = tasks ] && [ -f "$TASK_DIR/../project.md" ]; then
  REPO="$(fm_value target_repo "$TASK_DIR/../project.md")"
fi
[ -n "$REPO" ] || exit 1
[ "$MODE" = repo ] && { printf '%s\n' "$REPO"; exit 0; }

if [ -z "$INSTANCE" ]; then
  d="$TASK_DIR"
  while [ "$d" != "/" ]; do
    [ -f "$d/instance.config.json" ] && { INSTANCE="$d"; break; }
    d="$(dirname "$d")"
  done
fi
[ -n "$INSTANCE" ] || exit 1

CANDS=(); UNREAD=""
for f in "$INSTANCE"/knowledge/services/*.md; do
  [ -f "$f" ] || continue
  [ -r "$f" ] || { UNREAD="$f"; continue; }
  [ "$(fm_value repo "$f")" = "$REPO" ] && [ "$(fm_value status "$f")" != deprecated ] && CANDS+=("$f")
done
[ "$MODE" = ties ] && [ -n "$UNREAD" ] && { echo "service-doc: cannot read $UNREAD" >&2; exit 2; }
[ "${#CANDS[@]}" -gt 0 ] || exit 1
[ "${#CANDS[@]}" -eq 1 ] && { printf '%s\n' "${CANDS[0]}"; exit 0; }

TEXT="$(kb_task_text "$TASK")"; TIES=(); bestlen=0
for f in "${CANDS[@]}"; do
  p="$(fm_value path "$f")"; p="${p%/}"
  case "$p" in ""|"("*) continue ;; esac
  case "$TEXT" in *"$p"*)
    if [ "${#p}" -gt "$bestlen" ]; then TIES=("$f"); bestlen="${#p}"
    elif [ "${#p}" -eq "$bestlen" ]; then TIES+=("$f"); fi ;;
  esac
done
if [ "${#TIES[@]}" -eq 0 ]; then
  for f in "${CANDS[@]}"; do [ "${f##*/}" = "${REPO##*/}.md" ] && { TIES=("$f"); break; }; done
fi
[ "${#TIES[@]}" -gt 0 ] || TIES=("${CANDS[@]}")
if [ "$MODE" = ties ]; then printf '%s\n' "${TIES[@]}"; else printf '%s\n' "${TIES[0]}"; fi
