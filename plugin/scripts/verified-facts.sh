#!/usr/bin/env bash
# verified-facts.sh — is a build task's `## Verified facts` section there, and still true?
#   verified-facts.sh [--instance DIR] [--presence] <task-doc>
# Prints one word and exits on it: verified 0 · missing 1 · stale 3 (a path the section names
# changed on origin/<default> since its sha) · unknown 4 (no clone, failed fetch, sha absent)
# · research 5 (no check owed) · 2 usage. Exit 0 is the only clearance. --presence reads the
# document alone (0 present · 1 missing · 5 research) and never touches git. Otherwise one
# bounded fetch of the default branch in <reposRoot>/<repo>; never writes the bundle.
# Grammar: SCHEMA.md → "Verified facts". Why: plugin/tick-steps/step-2-refine-drafts.md.
set -uo pipefail
export LC_ALL=C GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 GIT_LITERAL_PATHSPECS=1

inst="$PWD"; presence=0; task=""
usage() { echo "usage: verified-facts.sh [--instance DIR] [--presence] <task-doc>" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || usage; inst="$2"; shift 2 ;;
    --presence) presence=1; shift ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) [ -z "$task" ] || usage; task="$1"; shift ;;
  esac
done
[ -n "$task" ] && [ -f "$task" ] || usage
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FETCH_SECONDS=30

say() { echo "$1"; exit "$2"; }
fm() { # <file> <key>
  [ -f "$1" ] || return 0
  awk -v key="$2" 'NR == 1 { if ($0 != "---") exit; next } $0 == "---" { exit }
    index($0, key ":") == 1 { v = $0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+#.*/, "", v)
      gsub(/^["\047]|["\047][ \t]*$/, "", v); sub(/[ \t]+$/, "", v); print v; exit }' "$1"
}
pm="$(dirname "$(dirname "$task")")/project.md"
kind="$(fm "$task" kind)"; [ -n "$kind" ] || kind="$(fm "$pm" kind)"
[ "${kind%% *}" = research ] && say research 5
repo="$(fm "$task" target_repo)"; [ -n "$repo" ] || repo="$(fm "$pm" target_repo)"

# The first well-formed heading in the body, then its `- <path> · <claim>` lines.
parsed="$(awk '
  NR == 1 && $0 == "---" { fmo = 1; next }
  fmo { if ($0 == "---") fmo = 0; next }
  !seen && match($0, /^## Verified facts \(as of [A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+@[0-9a-f]+\)[ \t]*$/) {
    h = $0; sub(/^## Verified facts \(as of /, "", h); sub(/\)[ \t]*$/, "", h)
    split(h, p, "@"); if (length(p[2]) != 40) next
    print "H\t" p[1] "\t" p[2]; seen = inside = 1; next }
  inside && /^#/ { inside = 0 }
  inside && /^- [^ ]+ · / { f = substr($0, 3); sub(/ · .*/, "", f); gsub(/`/, "", f); print "P\t" f }
' "$task")"
head="$(printf '%s\n' "$parsed" | grep '^H' | head -1)"
IFS=$'\t' read -r _ hrepo sha <<EOF
$head
EOF
paths=(); while IFS=$'\t' read -r k p; do [ "$k" = P ] && paths+=("$p"); done <<EOF
$parsed
EOF
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
{ [ -n "$sha" ] && [ ${#paths[@]} -gt 0 ] && [ "$(lc "$hrepo")" = "$(lc "$repo")" ]; } || say missing 1
[ "$presence" = 1 ] && say present 0

rr="$(bash "$HERE/resolve-config.sh" --instance "$inst" reposRoot 2>/dev/null)" || rr=""
case "$rr" in "~"|"~/"*) rr="$HOME${rr#\~}" ;; esac
clone="$rr/${repo##*/}"
{ [ -n "$rr" ] && [ -e "$clone/.git" ]; } || say unknown 4
def="$(git -C "$clone" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; def="${def#origin/}"
[ -n "$def" ] || say unknown 4

bounded() { # <seconds> <command…> — no coreutils `timeout` on a stock macOS
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@" >/dev/null 2>&1; return; fi
  ( "$@" >/dev/null 2>&1 &
    local child=$! dog rc=0
    ( sleep "$secs"; kill "$child" ) >/dev/null 2>&1 &
    dog=$!
    wait "$child" || rc=1
    kill "$dog" >/dev/null 2>&1 || true
    exit "$rc" ) 2>/dev/null
}
bounded "$FETCH_SECONDS" git -C "$clone" fetch --quiet --no-tags origin "$def" || say unknown 4
git -C "$clone" cat-file -e "$sha^{commit}" 2>/dev/null || say unknown 4
git -C "$clone" diff --quiet "$sha" "origin/$def" -- "${paths[@]}" 2>/dev/null
case $? in 0) say verified 0 ;; 1) say stale 3 ;; *) say unknown 4 ;; esac
