#!/usr/bin/env bash
# kb-usage.sh — the citation store. From a bundle root.
#
#   kb-usage.sh [--instance DIR] record --source <id> --text-file <f> (--brief <a,b> | --brief-file <f>)
#                                     [--today YYYY-MM-DD]
#
# record: runs cite-check.sh, prints its report, exits with its code, and stores the
#   KEPT/UNREAD/ARCHIVED slugs as $AB_DIR/citations/<id>.txt — one file per text, so a
#   re-run rewrites the same file and two clones never append to one. Exit 2: nothing stored.
#   "Today" is --today, else KB_USAGE_TODAY, else the UTC date.
# Exit: 0 answered · 1-3 record: cite-check.sh's code · 2 usage, or nothing could be read.
# Reasoning: knowledge-base-reflector/task-005.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 2

INST="$PWD"; VERB=""; SOURCE=""; TEXT=""; BRIEF=""; BRIEF_FILE=""
TODAY="${KB_USAGE_TODAY:-$(date -u +%Y-%m-%d)}"
die() { echo "kb-usage: $2" >&2; exit "$1"; }
need2() { [ "$1" -ge 2 ] || die 2 "$2 needs a value"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --instance)      need2 $# "$1"; INST="$2"; shift 2 ;;
    record)          [ -z "$VERB" ] || die 2 "one verb at a time"; VERB="$1"; shift ;;
    --source)        need2 $# "$1"; SOURCE="$2"; shift 2 ;;
    --text-file)     need2 $# "$1"; TEXT="$2"; shift 2 ;;
    --brief)         need2 $# "$1"; BRIEF="${BRIEF:+$BRIEF,}$2"; shift 2 ;;
    --brief-file)    need2 $# "$1"; BRIEF_FILE="$2"; shift 2 ;;
    --today)         need2 $# "$1"; TODAY="$2"; shift 2 ;;
    -h|--help) sed -n '2,11p' "$0" >&2; exit 2 ;;
    *) die 2 "unknown argument '$1'" ;;
  esac
done
[ -n "$VERB" ] || die 2 "usage: kb-usage.sh [--instance DIR] record …"
[ -d "$INST/knowledge" ] || die 2 "no knowledge/ under $INST — run from a bundle root"
[[ "$TODAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die 2 "--today wants YYYY-MM-DD"
STORE="$INST/$AB_DIR/citations"

[[ "$SOURCE" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die 2 "--source wants an id of [A-Za-z0-9._-], e.g. <task-slug>.result or <repo>-pr-<n>"
[ -n "$TEXT" ] || die 2 "record needs --text-file"
args=(--text-file "$TEXT")
[ -z "$BRIEF" ] || args+=(--brief "$BRIEF")
[ -z "$BRIEF_FILE" ] || args+=(--brief-file "$BRIEF_FILE")
[ ! -r "$INST/knowledge/index.md" ] || args+=(--index "$INST/knowledge/index.md")
report="$(bash "$HERE/cite-check.sh" "${args[@]}")"; rc=$?
printf '%s\n' "$report"
[ "$rc" -ne 2 ] || die 2 "cite-check.sh could not classify every citation — nothing stored"
mkdir -p "$STORE" || die 2 "cannot create $STORE"
f="$STORE/$SOURCE.txt"
recorded="$(sed -n 's/^recorded: //p' "$f" 2>/dev/null | head -1)"
t="$(mktemp "$STORE/.$SOURCE.XXXXXX")" || die 2 "cannot write under $STORE"
{ printf 'recorded: %s\n' "${recorded:-$TODAY}"
  printf '%s\n' "$report" | awk '/^(KEPT|UNREAD|ARCHIVED) [A-Za-z0-9._-]+ / { print $1, $2 }' | LC_ALL=C sort -u
} >"$t" && mv "$t" "$f" || { rm -f "$t"; die 2 "could not write $f"; }
echo "kb-usage: stored $(($(grep -c '' "$f") - 1)) citation(s) from $SOURCE" >&2
exit "$rc"
