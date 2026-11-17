#!/usr/bin/env bash
# pr-size.sh — report a diff past maxPrLoc (500), maxPrFiles (100) or ~150 added harness
# lines (plugin/**/*.sh) whose PR body has no `⚠️` line naming that figure.
#   pr-size.sh --body-file <f> [-C <repo>] [--base <ref>] [--instance <bundle>]
# Counts as plugin/seed/CONVENTIONS.md → "PR size is a heuristic, never a gate" does, against
# origin/<default>. Thresholds from --instance, else the repo's .git/loopd-bundle marker.
# Report-only, never a gate: exit 0 (reported or silent) · 2 unknown.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
dir=.; base=; body=; inst=
unknown() { echo "pr-size: UNKNOWN — $1"; exit 2; }
usage="usage: pr-size.sh --body-file <f> [-C <repo>] [--base <ref>] [--instance <bundle>]"
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || unknown "$usage"
  case "$1" in
    --body-file) body="$2" ;; -C) dir="$2" ;; --base) base="$2" ;; --instance) inst="$2" ;;
    *) unknown "$usage" ;;
  esac
  shift 2
done
[ -n "$body" ] || unknown "$usage"
[ -f "$body" ] && [ -r "$body" ] || unknown "cannot read body file $body"
if [ -z "$base" ]; then
  base="$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" ||
    unknown "origin/HEAD is not set in $dir; pass --base <ref>"
fi
if [ -z "$inst" ]; then
  cd_="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" &&
    [ -f "$cd_/loopd-bundle" ] && IFS= read -r inst < "$cd_/loopd-bundle"
fi
cfg() { # <key> <default>
  local v=""
  [ -n "$inst" ] && [ -f "$inst/instance.config.json" ] &&
    v="$(bash "$HERE/resolve-config.sh" --instance "$inst" "$1" 2>/dev/null)"
  case "$v" in ''|*[!0-9]*|0) printf '%s' "$2" ;; *) printf '%s' "$v" ;; esac
}

stat="$(git -C "$dir" diff --shortstat "$base" 2>/dev/null)" || unknown "git diff $base failed in $dir"
num="$(git -C "$dir" diff --numstat "$base" 2>/dev/null)" || unknown "git diff $base failed in $dir"
hnum="$(git -C "$dir" diff --numstat "$base" -- 'plugin/**/*.sh' 2>/dev/null)" ||
  unknown "git diff $base failed in $dir"
loc="$(printf '%s\n' "$stat" | awk '{for (i = 2; i <= NF; i++) if ($i ~ /^(insertion|deletion)/) n += $(i-1)} END {print n+0}')"
files="$(printf '%s' "$num" | grep -c .)"
harness="$(printf '%s\n' "$hnum" | awk '{a += $1} END {print a+0}')"

named() { # <figure>
  tr -d ',' < "$body" | grep -F '⚠' | grep -qE "(^|[^0-9])$1([^0-9]|$)"
}
report() { # <what> <figure> <limit>
  named "$2" || echo "pr-size: $1 $2 is past $3 and no ⚠️ line in the body names $2 (report only; open the PR anyway)"
}
max_loc="$(cfg maxPrLoc 500)"; max_files="$(cfg maxPrFiles 100)"
[ "$loc" -gt "$max_loc" ] && report "lines changed" "$loc" "maxPrLoc $max_loc"
[ "$files" -gt "$max_files" ] && report "files changed" "$files" "maxPrFiles $max_files"
[ "$harness" -ge 150 ] && report "harness lines added" "$harness" "~150"
exit 0
