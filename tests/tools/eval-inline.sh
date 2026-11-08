#!/usr/bin/env bash
# eval-inline.sh — rewrite (or --check) every `<!-- inline: <repo path> -->` … `<!-- /inline -->`
# block of an eval prompt.md so each carries its file's current text in a 5-backtick fence.
#   eval-inline.sh <prompt.md> [--check]
# Exit: 0 written/current · 1 stale (--check) or no block · 3 usage.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
p="${1:-}"; [ -f "$p" ] || { echo "usage: eval-inline.sh <prompt.md> [--check]" >&2; exit 3; }
paths="$(sed -n 's/^<!-- inline: \([^ ]*\) -->$/\1/p' "$p")"
[ -n "$paths" ] || { echo "eval-inline: $p names no inline file that exists" >&2; exit 1; }
while IFS= read -r path; do
  [ -f "$REPO/$path" ] || { echo "eval-inline: $p names no inline file that exists ($path)" >&2; exit 1; }
  grep -q '`````' "$REPO/$path" && { echo "eval-inline: $path carries a 5-backtick run" >&2; exit 1; }
done <<<"$paths"
out="$(awk -v repo="$REPO" '
  /^<!-- inline: / { f = repo "/" $3; print; print "`````md"; while ((getline l < f) > 0) print l; close(f); print "`````"; skip = 1; next }
  /^<!-- \/inline -->$/ { skip = 0 }
  !skip { print }' "$p")"
if [ "${2:-}" = "--check" ]; then
  [ "$out" = "$(cat "$p")" ] && exit 0
  echo "eval-inline: $p is stale against $(echo $paths) — run tests/tools/eval-inline.sh $p" >&2; exit 1
fi
printf '%s\n' "$out" > "$p"
