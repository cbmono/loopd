#!/usr/bin/env bash
# commit-shape.sh — report each commit in a range that breaks plugin/seed/CONVENTIONS.md →
# "Write less": a subject over 72 characters, a body over 5 non-blank lines above the trailer
# block, a subject that is not `<type>(<scope>)!: <subject>`, or a `Co-Authored-By: Claude`
# trailer that disagrees with `commitAttribution` (bundle read from <repo>/.git/loopd-bundle).
#   commit-shape.sh [-C <repo>] [--range <base>..<head>]   (default origin/<default>..HEAD)
# Merge, `Revert` and `fixup!` commits are skipped. Report-only (D2): always exits 0; prints
# UNKNOWN when it cannot read the range. Hook: plugin/hooks/commit-shape.sh.
set -u
dir=.; range=
usage="usage: commit-shape.sh [-C <repo>] [--range <base>..<head>]"
unknown() { echo "commit-shape: UNKNOWN — $1"; exit 0; }
while [ $# -gt 0 ]; do
  case "$1" in
    -C) [ $# -ge 2 ] || unknown "$usage"; dir="$2"; shift 2 ;;
    --range) [ $# -ge 2 ] || unknown "$usage"; range="$2"; shift 2 ;;
    *) unknown "$usage" ;;
  esac
done
if [ -z "$range" ]; then
  def="$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" ||
    unknown "origin/HEAD is not set in $dir; pass --range <base>..<head>"
  range="$def..HEAD"
fi
git -C "$dir" rev-list --count "$range" -- >/dev/null 2>&1 || unknown "git log $range failed in $dir"

attr=unknown
common="$(cd "$dir" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
if [ -n "$common" ] && [ -f "$common/loopd-bundle" ]; then
  bundle=""; IFS= read -r bundle < "$common/loopd-bundle" 2>/dev/null || bundle=""
  if [ -n "$bundle" ] && [ -f "$bundle/instance.config.json" ]; then
    v=""
    command -v python3 >/dev/null 2>&1 &&
      v="$(bash "$(dirname "$0")/resolve-config.sh" --instance "$bundle" commitAttribution 2>/dev/null)"
    [ "$v" = none ] && attr=none || attr=claude
  fi
fi

git -C "$dir" log -z --no-merges --format='%h%x1f%s%x1f%b' "$range" -- 2>/dev/null |
  while IFS= read -r -d '' rec || [ -n "$rec" ]; do printf '%s\036' "${rec//$'\036'/}"; done |
  LC_ALL=C awk -v range="$range" -v attr="$attr" '
BEGIN { RS = "\036"; FS = "\037" }
function chars(s,   t) { t = s; return length(s) - gsub(/[\200-\277]/, "", t) }
function trailer(l) { return l ~ /^[A-Za-z0-9][A-Za-z0-9-]*: / || l ~ /^[ \t]/ }
NF >= 2 && $1 ~ /^[0-9a-f]+$/ {
  sha = $1; subj = $2; body = $3
  if (subj ~ /^(Revert |fixup! |squash! |amend! )/) next
  why = ""
  if (chars(subj) > 72) why = why "; subject " chars(subj) " chars > 72"
  if (subj !~ /^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([^()]+\))?!?: [^ ]/)
    why = why "; subject is not <type>(<scope>)!: <subject>"
  n = split(body, L, "\n"); while (n > 0 && L[n] ~ /^[ \t]*$/) n--
  end = n; for (i = n; i > 0 && L[i] !~ /^[ \t]*$/; i--) if (!trailer(L[i])) break
  if (i == 0 || L[i] ~ /^[ \t]*$/) end = i
  co = 0; for (j = end + 1; j <= n; j++) if (tolower(L[j]) ~ /^co-authored-by: claude/) co = 1
  b = 0; for (j = 1; j <= end; j++) if (L[j] !~ /^[ \t]*$/) b++
  if (b > 5) why = why "; body " b " lines > 5"
  if (attr == "claude" && !co) why = why "; no Co-Authored-By: Claude trailer (commitAttribution: claude)"
  if (attr == "none" && co) why = why "; Co-Authored-By: Claude trailer (commitAttribution: none)"
  if (why == "") next
  gsub(/[\001-\037\177]/, "", subj)
  if (length(subj) > 100) { subj = substr(subj, 1, 100); sub(/[\300-\377][\200-\277]*$/, "", subj); subj = subj "…" }
  out[++nout] = sha " " subj " — " substr(why, 3)
}
END {
  printf "commit-shape: %d commit(s) off the commit shape in %s (attribution: %s; report only)\n", nout, range, attr
  for (i = 1; i <= nout && i <= 20; i++) print out[i]
  if (nout > 20) printf "… and %d more\n", nout - 20
}'
exit 0
