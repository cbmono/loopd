#!/usr/bin/env bash
# kb-stale.sh — report-only: which Service and Runbook docs has their code moved past?
#   kb-stale.sh [--instance DIR]
# An active Service is listed when <reposRoot>/<repo basename> has >= kbStaleCommits (absent
# => 20) commits since its timestamp: on the ref origin/HEAD names — on path:, or the whole
# repo with no path:. A Runbook's applies_to: resolves by exact Service slug or title: and is
# counted from its own timestamp:. What cannot be measured prints UNKNOWN, never 0.
# Never fetches, never writes. Exit: 0 something listed · 1 nothing listed · 2 usage.
# Why: plugin/tick-steps/step-7-knowledge-base.md (kb-retrieval-and-papercut-fixes/task-006).
set -uo pipefail
export LC_ALL=C GIT_OPTIONAL_LOCKS=0

inst="."
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || { echo "kb-stale: --instance needs a directory" >&2; exit 2; }
                inst="$2"; shift 2 ;;
    -h|--help) sed -n '2,8p' "$0" >&2; exit 2 ;;
    *) echo "kb-stale: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -d "$inst/knowledge" ] || { echo "kb-stale: no knowledge/ under $inst" >&2; exit 2; }

self="${BASH_SOURCE[0]:-$0}"
[ -L "$self" ] && self="$(readlink "$self" 2>/dev/null || printf '%s' "$self")"
here="$(cd "$(dirname "$self")" && pwd)" || exit 2

N="$(bash "$here/resolve-config.sh" --instance "$inst" kbStaleCommits 2>/dev/null)" || N=""
case "$N" in
  "") N=20 ;;
  *[!0-9]*|0*) echo "kb-stale: kbStaleCommits '$N' is not a positive integer; using 20" >&2; N=20 ;;
esac
rr="$(bash "$here/resolve-config.sh" --instance "$inst" reposRoot 2>/dev/null)" || rr=""
case "$rr" in "~"|"~/"*) rr="$HOME${rr#\~}" ;; esac

fm_value() { # <key> <file>
  awk -v key="$1" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, key ":") == 1 {
      v = $0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+#.*/, "", v); sub(/[ \t]+$/, "", v)
      if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
      print v; exit
    }' "$2"
}
list_value() { # <key> <file> — flow `[ a, b ]` or block `- a` form, one entry per line
  awk -v key="$1" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    inb && /^[ \t]*-([ \t]|$)/ { v = $0; sub(/^[ \t]*-[ \t]*/, "", v); sub(/[ \t]+#.*/, "", v); print v; next }
    inb && /^[ \t]*$/ { next }
    inb { exit }
    index($0, key ":") == 1 {
      v = $0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+#.*/, "", v)
      if (v ~ /^\[/) { sub(/^\[/, "", v); sub(/\][ \t]*$/, "", v); n = split(v, a, ","); for (i = 1; i <= n; i++) print a[i]; exit }
      if (v != "") { print v; exit }
      inb = 1
    }' "$2" | sed "s/^[[:space:]]*//; s/[[:space:]]*\$//; s/^\"\(.*\)\"\$/\1/; s/^'\(.*\)'\$/\1/" | grep -v '^$'
}

# git silently remaps an impossible date (2026-02-30 counts from March), so check the calendar.
TS_RE='^([0-9]{4})-([0-9]{2})-([0-9]{2})([T ]([0-9]{2}):([0-9]{2})(:([0-9]{2}))?)?'
valid_ts() { # <timestamp>
  local y m d dim
  [[ "$1" =~ $TS_RE ]] || return 1
  y=$((10#${BASH_REMATCH[1]})); m=$((10#${BASH_REMATCH[2]})); d=$((10#${BASH_REMATCH[3]}))
  case "$m" in 1|3|5|7|8|10|12) dim=31 ;; 4|6|9|11) dim=30 ;;
    2) if [ $((y % 4)) -eq 0 ] && { [ $((y % 100)) -ne 0 ] || [ $((y % 400)) -eq 0 ]; }; then dim=29; else dim=28; fi ;;
    *) return 1 ;; esac
  [ "$d" -ge 1 ] && [ "$d" -le "$dim" ] || return 1
  [ -z "${BASH_REMATCH[4]}" ] && return 0
  [ $((10#${BASH_REMATCH[5]})) -le 23 ] && [ $((10#${BASH_REMATCH[6]})) -le 59 ] &&
    [ $((10#${BASH_REMATCH[8]:-0})) -le 59 ]
}

CNT=""; WHY=""; REF=""
count() { # <repo> <path> <since> — sets CNT, or WHY when it cannot be measured
  local repo="$1" p="$2" since="$3" clone ref
  CNT=""; WHY=""; REF=""
  [ -n "$since" ] || { WHY="no ISO 8601 timestamp:"; return; }
  valid_ts "$since" || { WHY="timestamp: $since is not a valid date"; return; }
  [ -n "$repo" ] || { WHY="no repo:"; return; }
  [ -n "$rr" ] || { WHY="no reposRoot configured"; return; }
  clone="$rr/${repo##*/}"
  [ -e "$clone/.git" ] || { WHY="no clone at $clone"; return; }
  # symbolic-ref succeeds on a dangling origin/HEAD; only rev-parse --verify proves the target.
  ref="$(git -C "$clone" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null)" ||
    { WHY="no origin/HEAD in $clone"; return; }
  git -C "$clone" rev-parse -q --verify "$ref^{commit}" >/dev/null 2>&1 ||
    { WHY="origin/HEAD names $ref, which does not resolve"; return; }
  [ "$(git -C "$clone" rev-parse --is-shallow-repository 2>/dev/null)" = false ] ||
    { WHY="shallow clone at $clone would under-count"; return; }
  REF="${ref#refs/remotes/}"
  p="${p#./}"; p="${p%/}"
  if [ -z "$p" ]; then
    CNT="$(git -C "$clone" rev-list --count --since="$since" "$ref" 2>/dev/null)"
  elif git -C "$clone" cat-file -e "$ref:$p" 2>/dev/null; then
    CNT="$(git -C "$clone" rev-list --count --since="$since" "$ref" -- ":(literal)$p" 2>/dev/null)"
  else
    WHY="path not in clone: $p"; return
  fi
  case "$CNT" in ""|*[!0-9]*) CNT=""; WHY="git log failed in $clone" ;; esac
}

listed=0
say() { printf '%-8s %-8s %s — %s\n' "$1" "$2" "$3" "$4"; listed=$((listed+1)); }

FS=$'\037'; ACTIVE=""; deprecated=0
for f in "$inst"/knowledge/services/*.md; do
  [ -e "$f" ] || continue
  slug="${f##*/}"; slug="${slug%.md}"; rel="knowledge/services/$slug.md"
  [ -r "$f" ] || { say UNKNOWN service "$rel" "unreadable"; continue; }
  st="$(fm_value status "$f")"
  case "$st" in
    deprecated) deprecated=$((deprecated+1)); continue ;;
    active) ;;
    *) say UNKNOWN service "$rel" "status: ${st:-(none)} is neither active nor deprecated"; continue ;;
  esac
  repo="$(fm_value repo "$f")"; p="$(fm_value path "$f")"; ts="$(fm_value timestamp "$f")"
  ACTIVE="$ACTIVE$slug$FS$(fm_value title "$f")$FS$repo$FS$p"$'\n'
  count "$repo" "$p" "$ts"
  if [ -n "$WHY" ]; then say UNKNOWN service "$rel" "$WHY"
  elif [ "$CNT" -ge "$N" ]; then
    say STALE service "$rel" "$CNT commits on $REF since $ts in ${p:-the whole repo}"
  fi
done

unchecked=""; nunchecked=0
for f in "$inst"/knowledge/runbooks/*.md; do
  [ -e "$f" ] || continue
  slug="${f##*/}"; slug="${slug%.md}"; rel="knowledge/runbooks/$slug.md"
  [ -r "$f" ] || { say UNKNOWN runbook "$rel" "unreadable"; continue; }
  ts="$(fm_value timestamp "$f")"; entries="$(list_value applies_to "$f")"
  seen=" "; stale=""; unk=""
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    while IFS="$FS" read -r s t r p; do
      [ -n "$s" ] && { [ "$entry" = "$s" ] || [ "$entry" = "$t" ]; } || continue
      case "$seen" in *" $s "*) continue ;; esac
      seen="$seen$s "
      count "$r" "$p" "$ts"
      if [ -n "$WHY" ]; then unk="$unk, $s UNKNOWN ($WHY)"
      elif [ "$CNT" -ge "$N" ]; then stale="$stale, $s $CNT"; fi
    done <<< "$ACTIVE"
  done <<< "$entries"
  if [ "$seen" = " " ]; then unchecked="$unchecked $slug"; nunchecked=$((nunchecked+1))
  elif [ -n "$stale" ]; then say STALE runbook "$rel" "commits since its $ts: ${stale#, }${unk}"
  elif [ -n "$unk" ]; then say UNKNOWN runbook "$rel" "${unk#, }"; fi
done

[ "$deprecated" -eq 0 ] || echo "skipped (deprecated): $deprecated Service(s)"
[ "$nunchecked" -eq 0 ] || echo "unchecked: $nunchecked Runbook(s) resolve to no active Service —$unchecked"
echo "kb-stale: $listed listed at kbStaleCommits $N"
[ "$listed" -gt 0 ]
