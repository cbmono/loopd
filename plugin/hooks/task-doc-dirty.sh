#!/usr/bin/env bash
#
# task-doc-dirty.sh — Stop hook (loopd PLUGIN). In a role session rooted in a linked worktree
# whose `<common dir>/loopd-bundle` marker names a bundle that links the repo back (`repos/`),
# finds the task whose `worktree:` is that path and, when `git status --porcelain` on its doc
# in the bundle is non-empty, prints a systemMessage naming it. Report-only: never commits,
# stages or edits. Outside a marked worktree: no output. Always exit 0.
# Rule: seed/CONVENTIONS.md → "Commit your task-doc edit immediately after each write".
set -uo pipefail

dir="$(cd -P -- "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null && pwd -P)" || exit 0
[ -f "$dir/.git" ] || exit 0
gd=""; IFS= read -r gd < "$dir/.git" 2>/dev/null || gd=""
gd="${gd#gitdir:}"; gd="${gd# }"
case "$gd" in ""|/*) ;; *) gd="$dir/$gd" ;; esac
cd_="$gd"
if [ -n "$gd" ] && [ -f "$gd/commondir" ]; then
  c=""; IFS= read -r c < "$gd/commondir" 2>/dev/null || c=""
  case "$c" in "") ;; /*) cd_="$c" ;; *) cd_="$gd/$c" ;; esac
fi
b=""; [ -n "$cd_" ] && [ -f "$cd_/loopd-bundle" ] && { IFS= read -r b < "$cd_/loopd-bundle" 2>/dev/null || b=""; }
[ -n "$b" ] || exit 0
b="$(cd -P -- "$b" 2>/dev/null && pwd -P)" && [ -f "$b/instance.config.json" ] || exit 0
clone="$(cd -P -- "$cd_/.." 2>/dev/null && pwd -P)" || exit 0
linked=""
for l in "$b"/repos/*; do
  [ -L "$l" ] && [ "$(cd -P -- "$l" 2>/dev/null && pwd -P)" = "$clone" ] && { linked=1; break; }
done
[ -n "$linked" ] || exit 0

set -- "$b"/projects/*/tasks/*.md
[ -e "$1" ] || exit 0
dirty=""
while IFS=$'\t' read -r wt doc; do
  [ "$(cd -P -- "$wt" 2>/dev/null && pwd -P)" = "$dir" ] || continue
  rel="${doc#"$b"/}"
  # --no-optional-locks: a plain `git status` may rewrite the bundle's index, and this hook
  # must write nothing.
  [ -n "$(git -C "$b" --no-optional-locks status --porcelain -- "$rel" 2>/dev/null)" ] \
    && dirty="${dirty:+$dirty, }$rel"
done <<EOF
$(awk '
  FNR == 1 { fm = 0; hit = 0; if ($0 == "---") { fm = 1; next } }
  fm && $0 == "---" { fm = 0; next }
  fm && !hit && /^worktree:/ {
    hit = 1; v = $0
    sub(/^worktree:[[:space:]]*/, "", v); sub(/[[:space:]]+#.*$/, "", v); gsub(/["\047\r]/, "", v)
    if (v != "") print v "\t" FILENAME
  }' "$@" 2>/dev/null)
EOF
[ -n "$dirty" ] || exit 0
msg="loopd: task doc left uncommitted in $b: $dirty. Commit it now with commit-as.sh (CONVENTIONS.md → \"Commit your task-doc edit immediately after each write\")."
msg="${msg//\\/\\\\}"; msg="${msg//\"/\\\"}"
printf '{"systemMessage": "%s"}\n' "$msg"
exit 0
