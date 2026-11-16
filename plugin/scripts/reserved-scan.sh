#!/usr/bin/env bash
# reserved-scan.sh — list every line a range adds or removes in code or CI config that carries a
# reserved decision 1–3 token, per plugin/seed/CONVENTIONS.md → "Reserved decisions".
#   reserved-scan.sh [-C <repo>] [<range>]   (default origin/<default>...HEAD)
# Exit 0 none · 1 hits · 2 unknown. Report-only: whether a hit is pre-approved by a criterion,
# an answered question or a D<n> stays the reader's call. Prose files are not scanned.
set -u
dir=.; range=
usage="usage: reserved-scan.sh [-C <repo>] [<range>]"
unknown() { echo "reserved-scan: UNKNOWN — $1"; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    -C) [ $# -ge 2 ] || unknown "$usage"; dir="$2"; shift 2 ;;
    -*) unknown "$usage" ;;
    *) [ -z "$range" ] || unknown "$usage"; range="$1"; shift ;;
  esac
done
if [ -z "$range" ]; then
  def="$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" ||
    unknown "origin/HEAD is not set in $dir; pass a <range>"
  range="$def...HEAD"
fi
diff="$(git -C "$dir" -c core.quotePath=false diff --no-color --no-ext-diff -U0 "$range" -- 2>/dev/null)" ||
  unknown "git diff $range failed in $dir"

printf '%s\n' "$diff" | LC_ALL=C awk -v range="$range" '
function prose(p) { return p ~ /\.(md|markdown|mdx|txt|rst|adoc|asciidoc)$/ }
function reserved(s, p) {
  if (s ~ /eslint-disable|@ts-ignore|@ts-expect-error|continue-on-error/) return 1
  if (s ~ /#[ \t]*shellcheck[ \t]+disable=/) return 1
  if (s ~ /(^|[^A-Za-z0-9_$])(it|test|describe|context|suite|bench|this|mark|unittest|pytest)\.skip(If|if|Unless)?([^A-Za-z0-9_]|$)/) return 1
  if (s ~ /(^|[^A-Za-z0-9_$.])(xit|xdescribe|xtest|xcontext)[ \t]*\(/) return 1
  if (s ~ /mark\.xfail|@Disabled|@Ignore([^A-Za-z0-9_]|$)|#\[ignore\]|(^|[^A-Za-z0-9_])t\.Skip(Now|f)?\(/) return 1
  return p ~ /\.bats$/ && s ~ /^[ \t]*skip([ \t]|$)/
}
function hit(sign, p, n, s) { sub(/^[ \t]+/, "", s); out[++nout] = p ":" n ": " sign s }
/^diff --git / { hdr = 1; op = np = ""; next }
hdr && /^--- / { op = substr($0, 5); sub(/^a\//, "", op); next }
hdr && /^\+\+\+ / { np = substr($0, 5); sub(/^b\//, "", np); next }
/^@@ / {
  hdr = 0
  match($0, /-[0-9]+/); ol = substr($0, RSTART + 1, RLENGTH - 1) + 0
  match($0, /\+[0-9]+/); nl = substr($0, RSTART + 1, RLENGTH - 1) + 0
  next
}
hdr { next }
/^\+/ { s = substr($0, 2); if (!prose(np) && reserved(s, np)) hit("+", np, nl, s); nl++; next }
/^-/ { s = substr($0, 2); if (!prose(op) && reserved(s, op)) hit("-", op, ol, s); ol++; next }
END {
  printf "reserved-scan: %d added (+) or removed (-) line(s) carrying a reserved decision token in %s (report only)\n", nout, range
  for (i = 1; i <= nout; i++) print out[i]
  exit nout > 0
}'
rc=$?
[ "$rc" -le 1 ] || unknown "awk exited $rc"
exit "$rc"
