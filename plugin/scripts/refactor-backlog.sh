#!/usr/bin/env bash
# refactor-backlog.sh — out-of-scope refactors, one line each, in knowledge/backlog/<repo>.md.
#
#   refactor-backlog.sh add --repo <org>/<name> --path <p> --what <t> --why <t> --by <role>
#   refactor-backlog.sh done --repo <org>/<name> <id> | list [--repo <r>] | count [--repo <r>]
#
# Run at the bundle root. `add` only appends (the tick commits); entry `- [ ] DATE | WHERE |
# WHAT | WHY | FOUND BY`, id `rb-<djb2 of repo+path+what>`. Exit: 0 ok · 1 refused, named
# on stderr (bad field, duplicate, bound, unknown id) · 2 usage / not a bundle / lock held.
# Why: SCHEMA.md → "type: Backlog"; all-code-is-slop-lessons/task-005.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

MAX_OPEN=200
FIELD_MAX=200
DIR="knowledge/backlog"

CMD="${1:-}"; [ $# -gt 0 ] && shift
usage() { sed -n '2,9p' "$0" >&2; }
die() { echo "refactor-backlog: $2" >&2; exit "$1"; }
need2() { [ "$1" -ge 2 ] || die 2 "$2 needs a value"; }

REPO=""; WHERE=""; WHAT=""; WHY=""; BY=""; ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) need2 $# "$1"; REPO="$2";  shift 2 ;;
    --path) need2 $# "$1"; WHERE="$2"; shift 2 ;;
    --what) need2 $# "$1"; WHAT="$2";  shift 2 ;;
    --why)  need2 $# "$1"; WHY="$2";   shift 2 ;;
    --by)   need2 $# "$1"; BY="$2";    shift 2 ;;
    -h|--help) usage; exit 2 ;;
    -*) usage; die 2 "unknown argument '$1'" ;;
    *) [ -z "$ID" ] || die 2 "one id only"; ID="$1"; shift ;;
  esac
done
ab_is_bundle . || die 2 "run from a control-panel instance root (instance.config.json)"

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

# The dedup key and the id, in one awk: repo + where + what, lowercased, whitespace collapsed.
KEY_AWK='
function n(s) { s = tolower(s); gsub(/[ \t]+/, " ", s); gsub(/^ | $/, "", s); return s }
function hid(s,   h, i) { h = 5381; for (i = 1; i <= length(s); i++) h = (h * 33 + ord[substr(s, i, 1)]) % 4294967296; return sprintf("rb-%.0f", h) }
BEGIN { for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i }'
# ENVIRON, not -v: -v expands backslash escapes, and `entries` reads the file literally.
id_of() { R="$1" W="$2" T="$3" LC_ALL=C awk "$KEY_AWK"' BEGIN { print hid(n(ENVIRON["R"]) "|" n(ENVIRON["W"]) "|" n(ENVIRON["T"])) }'; }

repo_ok() {
  REPO="$(printf '%s' "$REPO" | tr '[:upper:]' '[:lower:]')"
  [[ "$REPO" =~ ^[a-z0-9._-]+/[a-z0-9._-]+$ ]] || die 1 "refused — --repo wants <org>/<name>, got '$REPO'"
  FILE="$DIR/${REPO#*/}.md"
  owner_ok
}
owner_ok() {
  if [ -f "$FILE" ]; then
    local have; have="$(sed -n '2,/^---$/s/^repo:[[:space:]]*//p' "$FILE" | head -1)"
    [ "$have" = "$REPO" ] || die 1 "refused — $FILE belongs to '$have', not '$REPO'"
  fi
}

# Every entry of <file> (repo <r>), open or closed: `<state>\t<id>\t<where>\t<what>`.
entries() { # <file> <repo>
  [ -f "$1" ] || return 0
  LC_ALL=C awk -F'|' -v r="$2" "$KEY_AWK"'
    /^- \[[ x]\] / {
      st = (substr($0, 4, 1) == "x") ? "done" : "open"
      w = $2; t = $3; gsub(/^[ \t]+|[ \t]+$/, "", w); gsub(/^[ \t]+|[ \t]+$/, "", t)
      print st "\t" hid(n(r) "|" n(w) "|" n(t)) "\t" w "\t" t }' "$1"
}
open_count() { local n=0; [ -f "$1" ] && n="$(grep -c '^- \[ \] ' "$1")"; echo "${n:-0}"; }

LOCK=""
lock() {
  mkdir -p "$DIR" || exit 2
  LOCK="$DIR/.${REPO#*/}.lock"
  local i=0
  until mkdir "$LOCK" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -lt 100 ] || die 2 "lock held: $LOCK — remove it if no add is running"
    sleep 0.1
  done
  trap 'rmdir "$LOCK" 2>/dev/null' EXIT
}

case "$CMD" in
  add)
    for f in REPO WHERE WHAT WHY BY; do
      v="$(trim "${!f}")"; printf -v "$f" '%s' "$v"
      case "$f" in REPO) flag=--repo ;; WHERE) flag=--path ;; WHAT) flag=--what ;; WHY) flag=--why ;; *) flag=--by ;; esac
      [ -n "$v" ] || die 1 "refused — $flag is empty"
      case "$v" in *$'\n'*|*$'\r'*) die 1 "refused — $flag is more than one line" ;; esac
      case "$v" in *'|'*) die 1 "refused — a \"|\" in $flag breaks the entry" ;; esac
      [ "${#v}" -le "$FIELD_MAX" ] || die 1 "refused — $flag is ${#v} characters, over $FIELD_MAX"
    done
    repo_ok
    lock
    owner_ok
    id="$(id_of "$REPO" "$WHERE" "$WHAT")"
    dup="$(entries "$FILE" "$REPO" | awk -F'\t' -v id="$id" '$2 == id { print $1; exit }')"
    [ -z "$dup" ] || die 1 "refused — duplicate of $id ($dup)"
    n="$(open_count "$FILE")"
    [ "$n" -lt "$MAX_OPEN" ] || die 1 "refused — $FILE holds $n open entries, the bound is $MAX_OPEN: close some with 'done' or turn them into a project"
    if [ ! -e "$FILE" ]; then
      printf -- '---\ntype: Backlog\nrepo: %s\ntimestamp: %s\n---\n\n# Refactor backlog — %s\n\nOne line per out-of-scope refactor: `- [ ] DATE | WHERE | WHAT | WHY | FOUND BY`.\nAppend with `refactor-backlog.sh add`, close with `refactor-backlog.sh done`; turn one into a project with `/loopd:new-project`.\n\n## Entries\n\n' \
        "$REPO" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$REPO" > "$FILE" || exit 2
    fi
    [ -z "$(tail -c 1 "$FILE")" ] || printf '\n' >> "$FILE"
    printf -- '- [ ] %s | %s | %s | %s | %s\n' "$(date -u +%Y-%m-%d)" "$WHERE" "$WHAT" "$WHY" "$BY" >> "$FILE" || exit 2
    echo "refactor-backlog: added $id to $FILE ($((n + 1)) open)"
    ;;
  done)
    [ -n "$REPO" ] && [ -n "$ID" ] || { usage; die 2 "done wants --repo and an id"; }
    repo_ok
    [ -f "$FILE" ] || die 1 "no backlog at $FILE"
    lock
    hit="$(entries "$FILE" "$REPO" | awk -F'\t' -v id="$ID" '$2 == id { print NR " " $1; exit }')"
    [ -n "$hit" ] || die 1 "no entry $ID in $FILE"
    [ "${hit#* }" = open ] || die 1 "$ID is already closed"
    hit="${hit%% *}"
    tmp="$FILE.tmp.$$"
    awk -v n="$hit" '/^- \[[ x]\] / && ++k == n { sub(/^- \[ \]/, "- [x]") } { print }' "$FILE" > "$tmp" && mv "$tmp" "$FILE" || { rm -f "$tmp"; exit 2; }
    echo "refactor-backlog: closed $ID in $FILE"
    ;;
  list|count)
    files=()
    if [ -n "$REPO" ]; then repo_ok; files=("$FILE")
    else for f in "$DIR"/*.md; do [ -f "$f" ] && files+=("$f"); done; fi
    total=0
    for f in ${files[@]+"${files[@]}"}; do
      [ -e "$f" ] || continue
      [ -r "$f" ] || die 2 "cannot read $f"
      r="$(sed -n '2,/^---$/s/^repo:[[:space:]]*//p' "$f" | head -1)"
      if [ "$CMD" = count ]; then total=$((total + $(open_count "$f"))); continue; fi
      entries "$f" "$r" | awk -F'\t' -v r="$r" '$1 == "open" { printf "%s  %s  %s — %s\n", $2, r, $3, $4 }'
    done
    [ "$CMD" = count ] && echo "$total"
    ;;
  *) usage; exit 2 ;;
esac
exit 0
