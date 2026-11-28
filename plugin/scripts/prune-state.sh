#!/usr/bin/env bash
#
# prune-state.sh <bundle-root> [--apply] [--offline] — age out gitignored per-machine state under .loopd/.
#
# Dry run by default: `would remove <path> <bytes>`, `kept <path>`, `unowned <path> <bytes>`, then
# `prune: <n> files, <bytes> bytes`; `--apply` removes and prints `removed`. Only AGES rows are
# removed; never a tracked file, a `.gitignore`, an open hand-off, a live session's file, a
# receipt for a PR not closed or merged (none under --offline), or a seed's newest backup.
# Exit: 0 done · 2 usage, no .loopd, or tracked files unreadable. Reasoning: bound-loopd-dir-growth/task-005.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 2

AGES=".scratch:14 tmp:14 .tick-receipts:14 .handoffs:14 refresh:30"
KEPT="kb.git kb-src seed-base citations log .qa-dispatch .new-project .queue .sessions
counts.json.* METRICS.json.* .METRICS.json.* upstream-proposals.md.*"
TERMINAL=" done gone stopped completed cancelled failed error exited dead "

usage() { sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
root=""; apply=0; offline=0
for a in "$@"; do
  case "$a" in --apply) apply=1 ;; --offline) offline=1 ;; -*) usage ;; *) [ -z "$root" ] || usage; root="$a" ;; esac
done
[ -n "$root" ] && [ -d "$root/$AB_DIR" ] && [ ! -L "$root/$AB_DIR" ] || usage
root="$(cd "$root" && pwd -P)" || exit 2
work="$(mktemp -d "${TMPDIR:-/tmp}/prune-state.XXXXXX")" && [ -d "$work" ] || exit 2
trap 'rm -rf "$work"' EXIT

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
git -C "$root" ls-files -- "$AB_DIR" > "$work/tracked" 2>/dev/null \
  || { echo "prune-state: cannot read tracked files in $root — nothing removed" >&2; exit 2; }
bytes() { find -P "$1" -type f -exec wc -c {} \; 2>/dev/null | awk '{ s += $1 } END { print s + 0 }'; }
age_of() { local r; for r in $AGES; do [ "${r%%:*}" = "$1" ] && { echo "${r##*:}"; return 0; }; done; return 1; }

for p in $(bash "$HERE/bundle-paths.sh" | sed -n "s#^AB_[A-Z_]*=$AB_DIR/\([^/]*\).*#\1#p"); do KEPT="$KEPT $p"; done
known() { local k r=1; set -f; for k in $KEPT; do case "$1" in $k) r=0; break ;; esac; done; set +f; return $r; }

: > "$work/cand"
for p in "$root/$AB_DIR"/* "$root/$AB_DIR"/.[!.]* "$root/$AB_DIR"/..?*; do
  [ -e "$p" ] || [ -L "$p" ] || continue
  n="${p##*/}"; rel="$AB_DIR/$n"
  if age_of "$n" >/dev/null && [ -d "$p" ] && [ ! -L "$p" ]; then
    (cd "$root" && find -P "$rel" -type f ! -name .gitignore -mtime "+$(age_of "$n")" -print 2>/dev/null) \
      | awk -v d="$n" '{ print d "\t" $0 }' >> "$work/cand"
  elif known "$n" || grep -q "^$rel\(/\|$\)" "$work/tracked"; then
    echo "kept $rel"
  else
    echo "unowned $rel $(bytes "$p")"
  fi
done

keep() { printf '%s\n' "$1" >> "$work/keep"; }
: > "$work/keep"
awk -F'\t' 'NR == FNR { t[$0] = 1; next } ($2 in t) { print $2 }' "$work/tracked" "$work/cand" >> "$work/keep"

if [ -d "$root/projects" ]; then
  grep -rhoE 'hand-off [0-9a-f]{8}-[0-9a-f]{8}' --include='*.md' "$root/projects" > "$work/open" 2>/dev/null
  [ $? -le 1 ] || { echo "prune-state: cannot read the task docs — every hand-off kept" >&2; echo 'hand-off *' > "$work/open"; }
else : > "$work/open"; fi
awk -F'\t' '$1 == ".handoffs" { print $2 }' "$work/cand" | while IFS= read -r f; do
  id="${f##*/}"; id="${id%.txt}"
  if grep -qxF "hand-off $id" "$work/open" || grep -qxF 'hand-off *' "$work/open"; then keep "$f"; fi
done

cut -f2 "$work/cand" | while IFS= read -r f; do
  printf '%s\n' "${f##*/}" | grep -oE '(^|[^0-9A-Za-z])[0-9a-f]{8}([^0-9A-Za-z]|$)' | grep -oE '[0-9a-f]{8}'
done | sort -u > "$work/ids"
if [ -s "$work/ids" ]; then
  if bash "$HERE/agent-sessions.sh" states $(cat "$work/ids") > "$work/states" 2>/dev/null; then
    awk -v t="$TERMINAL" 'index(t, " " $2 " ") == 0 { print $1 }' "$work/states" > "$work/live"
  else
    echo "prune-state: session states unreadable — every file naming a session id kept" >&2
    cp "$work/ids" "$work/live"
  fi
  cut -f2 "$work/cand" | while IFS= read -r f; do
    for id in $(printf '%s\n' "${f##*/}" | grep -oE '(^|[^0-9A-Za-z])[0-9a-f]{8}([^0-9A-Za-z]|$)' | grep -oE '[0-9a-f]{8}'); do
      grep -qxF "$id" "$work/live" && { keep "$f"; break; }
    done
  done
fi

awk -F'\t' '$1 == ".tick-receipts" { print $2 }' "$work/cand" | while IFS= read -r f; do
  r="$(awk '$1 == "repo" { print $2; exit }' "$root/$f")"; n="$(awk '$1 == "pr" { print $2; exit }' "$root/$f")"
  s=""
  if [ "$offline" -eq 0 ] && [[ "$r" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ && "$n" =~ ^[0-9]+$ ]]; then
    s="$(awk -v k="$r#$n" '$1 == k { print $2; exit }' "$work/prs" 2>/dev/null)"
    [ -n "$s" ] || { s="$(gh pr view "$n" -R "$r" --json state -q .state 2>/dev/null </dev/null)" || s=UNKNOWN
                     printf '%s#%s %s\n' "$r" "$n" "${s:-UNKNOWN}" >> "$work/prs"; }
  fi
  case "$s" in CLOSED|MERGED) ;; *) keep "$f" ;; esac
done

[ -L "$root/$AB_DIR/refresh" ] || (cd "$root" && find -P "$AB_DIR/refresh" -type f ! -name .gitignore 2>/dev/null) \
  | sed -nE 's#^(.*)\.([0-9]+)$#\1	\2	&#p' | sort -t'	' -k1,1 -k2,2nr \
  | awk -F'\t' '!seen[$1]++ { print $3 }' >> "$work/keep"

total=0; count=0
while IFS='	' read -r d f; do
  grep -qxF "$f" "$work/keep" && continue
  case "$f" in "$AB_DIR/$d/"*) ;; *) continue ;; esac
  case "/$f/" in */../*|*/./*) continue ;; esac
  [ -f "$root/$f" ] && [ ! -L "$root/$f" ] || continue
  case "$(cd -P "$(dirname "$root/$f")" 2>/dev/null && pwd -P)/" in "$root/$AB_DIR/$d/"*) ;; *) continue ;; esac
  b="$(wc -c < "$root/$f" | tr -d ' ')"
  if [ "$apply" -eq 0 ]; then echo "would remove $f $b"
  else
    [ -n "$(find -P "$root/$f" -maxdepth 0 -type f -mtime "+$(age_of "$d")" 2>/dev/null)" ] || continue
    rm -f -- "$root/$f" || continue
    echo "removed $f $b"
    p="$(dirname "$root/$f")"
    while [ "$p" != "$root/$AB_DIR/$d" ] && rmdir "$p" 2>/dev/null; do p="$(dirname "$p")"; done
  fi
  total=$((total + b)); count=$((count + 1))
done < "$work/cand"
echo "prune: $count files, $total bytes"
