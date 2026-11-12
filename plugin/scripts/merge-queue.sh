#!/usr/bin/env bash
#
# merge-queue.sh — would a push to <branch> join a GitHub Actions concurrency group that already
# has a queued, waiting, pending or in_progress run? Merging then cancels or replaces that run.
#
#   Usage: merge-queue.sh <owner>/<repo> <branch> [--pr <n> --head <sha>] [--instance <bundle>]
#
# Exit: 0 clear · 1 hold (names the group and run) · 2 unknown (names the reason) · 3 with --pr,
# unknown for the MQ_BOUND-th time at this head: the merge is the human's · 4 usage.
# With --pr, 1-3 keep a mark under AB_MERGE_HOLDS (tick-delta.sh reports 1 and 2 as a DELTA); 0
# drops it. The mark is `head n status repo pr`, tab-separated, plus the reason on 2 and 3.
# Why: AUTONOMY.md → "Merge under `yolo`", precondition 5.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 4

MQ_BOUND=3
usage() { sed -n '6p' "$0" | sed 's/^# *//' >&2; exit 4; }

repo="${1:-}"; branch="${2:-}"; [ $# -ge 2 ] && shift 2 || usage
pr=""; head=""; inst=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pr|--head|--instance)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      case "$1" in --pr) pr="$2" ;; --head) head="$2" ;; --instance) inst="$2" ;; esac
      shift 2 ;;
    *) usage ;;
  esac
done
printf '%s' "$repo" | grep -Eqx '[A-Za-z0-9._-]+/[A-Za-z0-9._-]+' || usage
[ -n "$branch" ] && [ "${branch#-}" = "$branch" ] || usage
if [ -n "$pr$head" ]; then
  printf '%s' "$pr" | grep -Eqx '[0-9]+' && printf '%s' "$head" | grep -Eqx '[0-9a-f]{40}' || usage
  if [ -z "$inst" ]; then
    inst="${CLAUDE_PROJECT_DIR:-$PWD}"
    while [ "$inst" != / ] && [ ! -f "$inst/instance.config.json" ]; do inst="$(dirname "$inst")"; done
  fi
  [ -f "$inst/instance.config.json" ] || { echo "merge-queue: no bundle (instance.config.json) for --pr" >&2; exit 4; }
fi

TMP="$(mktemp -d)" || { echo "unknown: mktemp failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
US=$'\037'; UNK=$'\001'

# Keeps the D2 count per PR and head; a new head starts again at 0.
finish() { # <exit> <merge-row token> [<reason>]
  local rc="$1" dir m h="" n=0 st=""
  if [ -n "$pr" ]; then
    dir="$inst/$AB_MERGE_HOLDS"; m="$dir/$(printf '%s' "$repo" | tr '/' '_')_$pr"
    [ -f "$m" ] && IFS=$'\t' read -r h n st _ < "$m"
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    [ "$h" = "$head" ] || { n=0; st=""; }
    if [ "$rc" = 0 ]; then rm -f "$m"
    else
      if [ "$rc" = 2 ]; then
        [ "$st" = human ] || n=$((n + 1))
        if [ "$st" = human ] || [ "$n" -ge "$MQ_BOUND" ]; then
          rc=3; st=human; echo "bound: unknown $n time(s) at $head — the merge is the human's (D2)"
        else st=unknown; fi
      else st=hold; fi
      mkdir -p "$dir" && { [ -e "$dir/.gitignore" ] || printf '*\n' > "$dir/.gitignore"; } \
        && printf '%s\t%s\t%s\t%s\t%s%s\n' "$head" "$n" "$st" "$repo" "$pr" "${3:+$'\t'$3}" > "$m" \
        || { echo "unknown: cannot write $m"; rc=2; }
    fi
  fi
  [ -n "${2:-}" ] && echo "merge-row: $2"
  exit "$rc"
}
# The reason embeds workflow text the PR author controls, and it reaches the mark, AWAITING.md
# and the tick's close line: one line, no control characters, 200 characters.
unknown() {
  local r; r="$(printf '%s' "$1" | LC_ALL=C tr '\t\n' '  ' | LC_ALL=C tr -d '[:cntrl:]')"; r="${r:0:200}"
  echo "unknown: $r"; finish 2 "##mq2 $r" "$r"
}

# One `path<TAB>value` per scalar of a block-style YAML file; a list item is `path[]`. What this
# cannot read (a block scalar, a flow mapping, an unclosed `[` or quote, an anchor, alias or tag)
# is UNK-prefixed, so nothing reads it as a value.
flatten() {
  awk '
    function unq(v) { if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2); return v }
    function trim(v) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); return v }
    function scal(v) {
      v = trim(v)
      if (v ~ /^[&*!]/) return "\001anchor"
      if (v ~ /^\[/ && v !~ /\]$/) return "\001flow"
      v = unq(v); if (v ~ /^["\047]/) return "\001quote"
      return v
    }
    function nocomment(t,   i, c, q, p) {
      q = ""; p = " "
      for (i = 1; i <= length(t); i++) {
        c = substr(t, i, 1)
        if (q != "") { if (c == q) q = "" }
        else if ((c == "\"" || c == "\047") && p ~ /[ \t\[,]/) q = c
        else if (c == "#" && p ~ /[ \t]/) return substr(t, 1, i - 1)
        p = c
      }
      return t
    }
    BEGIN { skip = -1; n = 0 }
    {
      sub(/\r$/, "")
      if (skip >= 0) { if ($0 ~ /^[ \t]*$/) next; match($0, /^ */); if (RLENGTH > skip) next; skip = -1 }
      if ($0 ~ /^[ \t]*(#|$)/ || $0 ~ /^(---|\.\.\.)/) next
      match($0, /^ */); ind = RLENGTH; t = substr($0, ind + 1)
      t = trim(nocomment(t))
      if (t ~ /^-( |$)/) {
        while (n > 0 && ind_[n] > ind) n--
        lp = (n ? path_[n] : "") "[]"; t = trim(substr(t, 2))
        if (index(t, ": ") == 0 && t !~ /:$/) { print lp "\t" scal(t); next }
        n++; ind_[n] = ind + 1; path_[n] = lp; ind += 2
      } else while (n > 0 && ind_[n] >= ind) n--
      ci = index(t, ": "); if (ci == 0 && t ~ /:$/) ci = length(t)
      if (ci == 0) next
      p = (n ? path_[n] "." : "") unq(substr(t, 1, ci - 1)); v = trim(substr(t, ci + 1))
      if (v == "" || v == "{}" || v == "~" || v == "null") { print p "\t"; n++; ind_[n] = ind; path_[n] = p; next }
      if (v ~ /^[|>]/) { print p "\t\001block"; skip = ind; next }
      if (v ~ /^\{/) { print p "\t\001flow"; next }
      if (v ~ /^\[.*\]$/) {
        print p "\t"; c = split(substr(v, 2, length(v) - 2), a, ",")
        for (i = 1; i <= c; i++) { x = scal(a[i]); if (x != "") print p "[]\t" x }
        next
      }
      print p "\t" scal(v)
    }'
}
sel() { awk -F'\t' -v k="$2" '$1 == k { print substr($0, length(k) + 2) }' "$1"; }
has() { awk -F'\t' -v k="$2" '$1 == k || index($1, k ".") == 1 || index($1, k "[]") == 1 { f = 1 } END { exit !f }' "$1"; }

# shellcheck disable=SC2053  # branch filters are globs
triggers() { # <flat> -> 0 a push to $branch starts it · 1 it does not · 2 cannot tell
  local f="$1" p m=0
  awk -F'\t' '($1 == "on" || $1 ~ /^on[.[]/) && index($2, "\001") == 1 { f = 1 }
    $1 ~ /^on\.push\.(branches|branches-ignore|tags|tags-ignore)$/ && $2 != "" { f = 1 }
    END { exit !f }' "$f" && return 2
  [ "$(sel "$f" on)" = push ] && return 0
  sel "$f" 'on[]' | grep -qx push && return 0
  has "$f" on.push || return 1
  if has "$f" on.push.branches; then
    while IFS= read -r p; do
      case "$p" in '!'*) [[ "$branch" == ${p#!} ]] && m=0 ;; *) [[ "$branch" == $p ]] && m=1 ;; esac
    done < <(sel "$f" 'on.push.branches[]')
    [ "$m" = 1 ]; return
  fi
  if has "$f" on.push.branches-ignore; then
    while IFS= read -r p; do [[ "$branch" == $p ]] && return 1; done < <(sel "$f" 'on.push.branches-ignore[]')
    return 0
  fi
  has "$f" on.push.tags || has "$f" on.push.tags-ignore && return 1
  return 0
}

groups() { # <flat> -> each concurrency group expression; UNK-prefixed when none can be read
  awk -F'\t' '
    $1 == "concurrency" || $1 ~ /^jobs\.[^.]+\.concurrency$/ { k[$1] = $2; o[++n] = $1 }
    $1 ~ /(^|\.)concurrency\.group$/ { g[substr($1, 1, length($1) - 6)] = $2 }
    END { for (i = 1; i <= n; i++) { c = o[i]; print (c in g) ? g[c] : (k[c] == "" ? "\001no group key" : k[c]) } }' "$1"
}

# Run context: X_WF X_EVENT X_REF X_REFNAME X_HEADREF X_BASEREF X_PRNUM X_RUN; UNK = not known.
ctx() {
  local v
  case "$1" in
    github.workflow) v="$X_WF" ;;            github.event_name) v="$X_EVENT" ;;
    github.ref) v="$X_REF" ;;                github.ref_name) v="$X_REFNAME" ;;
    github.head_ref) v="$X_HEADREF" ;;       github.base_ref) v="$X_BASEREF" ;;
    github.repository) v="$repo" ;;          github.repository_owner) v="${repo%%/*}" ;;
    github.event.pull_request.number|github.event.number) v="$X_PRNUM" ;;
    github.run_id|github.run_number|github.run_attempt|github.sha) v="$X_RUN" ;;
    *) return 1 ;;
  esac
  [ "$v" = "$UNK" ] && return 1
  printf '%s' "$v"
}
seg() { # one ${{ }} body: `a || b || 'lit'` over ctx() names
  local s="$1" op v
  case "$s" in *'&&'*|*'('*|*'='*|*'!'*|*'<'*|*'>'*|*'['*) return 1 ;; esac
  while :; do
    op="${s%%||*}"; op="${op#"${op%%[! ]*}"}"; op="${op%"${op##*[! ]}"}"
    case "$op" in
      \'*\') v="${op#\'}"; v="${v%\'}" ;;
      *) v="$(ctx "$op")" || return 1 ;;
    esac
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
    [ "$s" = "${s#*||}" ] && return 0
    s="${s#*||}"
  done
}
evalg() { # <expr> -> the group string; 1 when bash cannot evaluate it
  local s="$1" out="" body v o='${{' c='}}'
  case "$s" in "$UNK"*|'') return 1 ;; esac
  while [ "$s" != "${s#*"$o"}" ]; do
    out="$out${s%%"$o"*}"; s="${s#*"$o"}"
    [ "$s" != "${s#*"$c"}" ] || return 1
    body="${s%%"$c"*}"; s="${s#*"$c"}"
    v="$(seg "$body")" || return 1; out="$out$v"
  done
  printf '%s' "$out$s"
}

gh_api() { # <out> <args...> -> 0 · 1 HTTP 404 · 2 anything else
  local out="$1"; shift
  gh api "$@" < /dev/null > "$out" 2> "$TMP/err" && return 0
  grep -q 'HTTP 404' "$TMP/err" && return 1
  return 2
}

command -v gh >/dev/null 2>&1 || unknown "gh not found"
gh_api "$TMP/wfs" --paginate "repos/$repo/actions/workflows" \
  --jq '.workflows[] | select(.state == "active") | .path' || unknown "gh could not list the workflows of $repo"

gh_api "$TMP/b" "repos/$repo/branches/$branch"
case $? in 1) unknown "branch $branch not found in $repo" ;; 2) unknown "gh could not read branch $branch of $repo" ;; esac
i=0; gone=0; : > "$TMP/index"
while IFS= read -r path; do
  [ -n "$path" ] || continue
  i=$((i + 1))
  gh_api "$TMP/raw.$i" -H 'Accept: application/vnd.github.raw' "repos/$repo/contents/$path?ref=$branch"
  case $? in 1) gone=$((gone + 1)); continue ;; 2) unknown "gh could not read $path at $branch" ;; esac
  flatten < "$TMP/raw.$i" > "$TMP/flat.$i"
  wf="$(sel "$TMP/flat.$i" name | head -n1)"
  printf '%s\t%s\t%s\n' "$i" "$path" "${wf:-$path}" >> "$TMP/index"
done < "$TMP/wfs"
[ "$i" = 0 ] || [ "$gone" != "$i" ] || unknown "none of the $i workflow file(s) of $repo is readable at $branch"
uses() { awk -F'\t' '$1 ~ /^jobs\.[^.]+\.uses$/ { print $2; exit }' "$1"; }

: > "$TMP/pushg"
while IFS=$'\t' read -r i path wf; do
  triggers "$TMP/flat.$i"
  case $? in 1) continue ;; 2) unknown "$path: its push trigger cannot be read" ;; esac
  u="$(uses "$TMP/flat.$i")"
  [ -z "$u" ] || unknown "$path: a job calls $u, whose concurrency bash does not read"
  X_WF="$wf" X_EVENT=push X_REF="refs/heads/$branch" X_REFNAME="$branch" X_HEADREF="" X_BASEREF="" \
    X_PRNUM="" X_RUN="$UNK.new-run"
  while IFS= read -r e; do
    g="$(evalg "$e")" || unknown "$path: concurrency group '${e#"$UNK"}' — bash cannot evaluate it"
    printf '%s\n' "$g" >> "$TMP/pushg"
  done < <(groups "$TMP/flat.$i")
done < "$TMP/index"
[ -s "$TMP/pushg" ] || { echo "clear: no workflow a push to $branch triggers sets a concurrency group"; finish 0; }

: > "$TMP/runs"
for st in requested queued waiting pending in_progress; do
  gh_api "$TMP/r" --paginate "repos/$repo/actions/runs?status=$st&per_page=100" \
    --jq '.workflow_runs[] | [.id, .path, .event, .head_branch, .head_sha, (.pull_requests[0].number // ""), (.pull_requests[0].base.ref // ""), .status, .html_url] | map(tostring) | join("\u001f")' \
    || unknown "gh could not list $st runs of $repo"
  cat "$TMP/r" >> "$TMP/runs"
done

why=""
while IFS="$US" read -r id path ev hb sha prn base st url; do
  [ -n "$id" ] || continue
  rf="${path%%@*}"; f="$TMP/run.$(printf '%s@%s' "$rf" "$sha" | cksum | cut -d' ' -f1)"
  if [ ! -e "$f" ]; then
    gh_api "$f.raw" -H 'Accept: application/vnd.github.raw' "repos/$repo/contents/$rf?ref=$sha"
    case $? in 0) flatten < "$f.raw" > "$f" ;; 1) : > "$f"; : > "$f.404" ;; 2) unknown "gh could not read $rf at $sha" ;; esac
  fi
  if [ -e "$f.404" ]; then why="${why:-run $id ($rf, $st): its workflow file is not readable at $sha}"; continue; fi
  u="$(uses "$f")"
  if [ -n "$u" ]; then why="${why:-run $id ($rf, $st): a job calls $u, whose concurrency bash does not read}"; continue; fi
  X_WF="$(sel "$f" name | head -n1)"; X_WF="${X_WF:-$rf}"
  X_EVENT="$ev"; X_RUN="run.$id"; X_HEADREF=""; X_BASEREF=""; X_PRNUM=""
  X_REF="refs/heads/$hb"; X_REFNAME="$hb"
  case "$ev" in pull_request*)
    X_HEADREF="$hb"; X_BASEREF="${base:-$UNK}"; X_PRNUM="${prn:-$UNK}"
    if [ "$ev" = pull_request ]; then
      X_REF="refs/pull/${prn:-$UNK}/merge"; X_REFNAME="${prn:-$UNK}/merge"
      [ -n "$prn" ] || { X_REF="$UNK"; X_REFNAME="$UNK"; }
    else X_REF="refs/heads/${base:-$UNK}"; X_REFNAME="${base:-$UNK}"; [ -n "$base" ] || { X_REF="$UNK"; X_REFNAME="$UNK"; }
    fi ;;
  esac
  while IFS= read -r e; do
    if ! g="$(evalg "$e")"; then why="${why:-run $id ($rf, $st): its group '${e#"$UNK"}' cannot be evaluated}"; continue; fi
    if grep -Fxqi -- "$g" "$TMP/pushg"; then
      echo "hold: group '$g' has run $id ($X_WF, $st, $ev on $hb) $url"
      finish 1 "##mq1 $branch $g"
    fi
  done < <(groups "$f")
done < "$TMP/runs"
[ -z "$why" ] || unknown "$why"
echo "clear: $(sort -u "$TMP/pushg" | grep -c .) group(s) a push to $branch joins, none with a pending run"
finish 0
