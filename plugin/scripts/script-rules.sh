#!/usr/bin/env bash
# script-rules.sh <plugin-root> — the allow rules init-bundle.sh 1e writes for a plugin root with
# whitespace: one exact-version rule per read-only script of data/script-classes.txt, on the root's
# space-free real path. Reads allow rules on stdin and names the ones 1e replaces or keeps.
# Out: `root<TAB><real path>` (exit 0 and 5), then `want|stale|newer<TAB><rule>`; `bad<TAB><path>` on 3.
# Exit: 0 printed · 1 the root has no whitespace · 2 usage · 3 the real path cannot be named in a
# rule · 4 not a plugin cache install · 5 the list is missing, empty, unparseable or names a
# script that is not there. Read by init-bundle.sh and welcome.sh check; docs/operations.md ->
# "Per-instance settings".
set -uo pipefail

root="${1:-}"
[ -n "$root" ] && [ -d "$root" ] || { echo "usage: script-rules.sh <plugin-root>  (rules on stdin)" >&2; exit 2; }
case "$root" in *[[:space:]]*) ;; *) exit 1 ;; esac
real="$(cd "$root" 2>/dev/null && pwd -P)"; root="$(cd "$root" 2>/dev/null && pwd)"
case "$real" in ""|*[[:space:]]*|*[\'\$\&\;\#\*\?\[]*) printf 'bad\t%s\n' "${real:-$root}"; exit 3 ;; esac

. "$(dirname "${BASH_SOURCE[0]:-$0}")/plugin-name.sh"
ab_plugin_name "$real" || exit 4
mk="${real%/*}"
case "${mk##*/}|${mk%/*/*}|$real" in
  *'"'*|*'\'*|*'('*|*')'*) exit 4 ;;
  "$PLUGIN_NAME"\|*/plugins/cache\|*) ;;
  *) exit 4 ;;
esac

printf 'root\t%s\n' "$real"
list="$real/data/script-classes.txt"
ro="$(bash "$real/scripts/script-classes.sh" read-only "$list" 2>/dev/null)" &&
  wr="$(bash "$real/scripts/script-classes.sh" writing "$list" 2>/dev/null)" &&
  [ -n "$ro" ] &&
  [ "$(printf '%s\n' "$ro" "$wr" | grep -c .)" = "$(grep -c '[^[:space:]]' "$list")" ] || exit 5
while IFS= read -r n; do
  case "$n" in "") ;; *[!A-Za-z0-9_.-]*|.*) exit 5 ;; *) [ -f "$real/scripts/$n" ] || exit 5 ;; esac
done <<EOF
$ro
$wr
EOF

printf '%s\n' "$ro" | while IFS= read -r n; do printf 'want\tBash(%s/scripts/%s *)\n' "$real" "$n"; done
[ -t 0 ] && exit 0
P="$mk/" L="${root%/*}/" V="${real##*/}" awk '
  function newer(a, b,   x, y, i, n, m) {
    n = split(a, x, "."); m = split(b, y, "."); if (m > n) n = m
    for (i = 1; i <= n; i++) if (x[i] + 0 != y[i] + 0) return x[i] + 0 > y[i] + 0
    return 0 }
  BEGIN { P = ENVIRON["P"]; L = ENVIRON["L"]; V = ENVIRON["V"] }
  $0 == "Bash(" P "*/scripts/*)" || $0 == "Bash(bash " P "*/scripts/*)" ||
  $0 == "Bash(" L "*/scripts/*)" || $0 == "Bash(bash " L "*/scripts/*)" { print "stale\t" $0; next }
  index($0, "Bash(" P) == 1 {
    r = substr($0, length(P) + 6)
    if (r !~ /^[^\/*]+\/scripts\/[A-Za-z0-9_.-]+\.sh \*\)$/) next
    v = substr(r, 1, index(r, "/") - 1)
    if (v != V) print (newer(v, V) ? "newer" : "stale") "\t" $0 }'
