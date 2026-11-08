#!/usr/bin/env bash
# question-sweep.sh — evaluate each open question's trailing ` check: <kind> <arg>` predicate.
#   question-sweep.sh [--instance DIR] [--apply] [<task-doc>...]   (default: every live task)
# One line per predicate: `<verdict>\t<task>\t<Q label>\t<evidence or reason>`, verdict one of
# true · false · unknown · refused; then `sweep: <n> true, <n> waiting on the human`. --apply
# appends ` · sweep: <kind> <arg> true @ <evidence>` to each true entry through
# fold-answers.sh --sweep; it never answers. Evidence is only what GitHub or git records.
# Exit: 0 ran · 2 usage · 3 a write failed. Grammar: SCHEMA.md → "Evidence sweep".
set -uo pipefail
export LC_ALL=C GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0

inst="$PWD"; apply=0; docs=()
usage() { sed -n '3p' "$0" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || usage; inst="$2"; shift 2 ;;
    --apply) apply=1; shift ;;
    -*) usage ;;
    *) docs+=("$1"); shift ;;
  esac
done
inst="$(cd "$inst" 2>/dev/null && pwd -P)" || usage
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOLD="$HERE/fold-answers.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/question-sweep.XXXXXX")" || exit 3
trap 'rm -rf "$TMP"' EXIT

fm() { awk -v key="$2" 'NR == 1 { if ($0 != "---") exit; next } $0 == "---" { exit }
  index($0, key ":") == 1 { v = $0; sub(/^[^:]*:[ \t]*/, "", v); gsub(/^["\047]|["\047][ \t]*$/, "", v)
    sub(/[ \t]+$/, "", v); print v; exit }' "$1" 2>/dev/null; }
if [ ${#docs[@]} = 0 ]; then
  for pm in "$inst"/projects/*/project.md; do
    [ -f "$pm" ] && [ "$(fm "$pm" status)" != done ] || continue
    for f in "$(dirname "$pm")"/tasks/*.md; do
      [ -f "$f" ] || continue
      case "$(fm "$f" status)" in done*|cancelled*) ;; *) docs+=("$f") ;; esac
    done
  done
fi

GH_LOGIN='^[A-Za-z0-9]([A-Za-z0-9-]{0,38})$'
gh_slug() { git -C "$1" remote get-url origin 2>/dev/null \
  | sed -nE 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+)$#\2#p' | sed 's/\.git$//'; }
BUNDLE_SLUG="$(gh_slug "$inst")"
KB_SLUG="$(gh_slug "$inst/knowledge")"
# <repo> <path> → `<sha>` on stdout and the file in $TMP/body; or the verdict line, exit 1.
read_on_default() {
  local def sha enc
  def="$(gh api "repos/$1" --jq .default_branch 2>/dev/null)" && [ -n "$def" ] || { echo "unknown	no default branch for $1"; return 1; }
  sha="$(gh api "repos/$1/commits/$def" --jq .sha 2>/dev/null)"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "unknown	no head sha for $1"; return 1; }
  enc="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$2")" || { echo "unknown	cannot encode path"; return 1; }
  if ! gh api -H 'Accept: application/vnd.github.raw' "repos/$1/contents/$enc?ref=$sha" >"$TMP/body" 2>"$TMP/err"; then
    grep -q 'HTTP 404' "$TMP/err" && echo "false	$1@$sha:$2 absent" || echo "unknown	contents read failed"
    return 1
  fi
  echo "$sha"
}
pr_merged() { # <url>
  [[ "$1" =~ ^https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/[0-9]+$ ]] || { echo "refused	not a pull request URL"; return; }
  local repo="${BASH_REMATCH[1]}" st def
  st="$(gh pr view "$1" --json state,baseRefName --jq '.state + " " + .baseRefName' 2>/dev/null)"
  def="$(gh api "repos/$repo" --jq .default_branch 2>/dev/null)"
  case "$st" in MERGED\ ?*|OPEN\ ?*|CLOSED\ ?*) ;; *) echo "unknown	gh pr view failed"; return ;; esac
  [ -n "$def" ] || { echo "unknown	no default branch for $repo"; return; }
  # A PR into a side branch "merges" by a push to that branch; only the default branch is evidence.
  case "$st" in "MERGED $def") echo "true	$1" ;; MERGED\ *) echo "false	$1 merged into ${st#* }, not $def" ;; *) echo "false	$1 not merged" ;; esac
}
file_on_default() { # <owner>/<repo>:<path>[=<value>] <target_repo>
  [[ "$1" =~ ^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+):([^=]+)(=(.*))?$ ]] || { echo "refused	not <owner>/<repo>:<path>[=<value>]"; return; }
  local repo="${BASH_REMATCH[1]}" path="${BASH_REMATCH[2]}" has="${BASH_REMATCH[3]}" value="${BASH_REMATCH[4]}" sha
  # Agents push the bundle and the KB every tick, so only the task's product repo is evidence.
  { [ "$repo" != "$BUNDLE_SLUG" ] && [ "$repo" != "$KB_SLUG" ] && [ "$repo" = "$2" ]; } \
    || { echo "refused	$repo is not this task's target_repo"; return; }
  [ -z "$has" ] || [ -n "$value" ] || { echo "refused	an empty =<value> matches anything"; return; }
  sha="$(read_on_default "$repo" "$path")" || { echo "$sha"; return; }
  if [ -n "$has" ] && ! grep -qF -- "$value" "$TMP/body"; then echo "false	$repo@$sha:$path lacks the value"; return; fi
  echo "true	$repo@$sha:$path"
}
# Only the copy on the bundle's remote default branch counts — a local commit may be the
# PM's and unpushed — and only an ack whose stamp is a GitHub login: `<unknown>` and
# `loopd:…` are not a human.
decision() { # <D<n>> <task-doc>
  [[ "$1" =~ ^D[0-9]+$ ]] || { echo "refused	not D<n>"; return; }
  local pm rel sha acks line login
  pm="$(cd "$(dirname "$(dirname "$2")")" && pwd -P)/project.md"; rel="${pm#"$inst"/}"
  [ -n "$BUNDLE_SLUG" ] || { echo "unknown	bundle has no GitHub origin"; return; }
  sha="$(read_on_default "$BUNDLE_SLUG" "$rel")" || { echo "$sha"; return; }
  acks="$(bash "$FOLD" --list "$TMP/body" acknowledged_decisions 2>/dev/null)" \
    || { echo "unknown	acknowledged_decisions unreadable"; return; }
  line="$(printf '%s\n' "$acks" | grep -E "^[0-9TZ:-]+ by [^ ]+ · $1: " | head -1)"
  [ -n "$line" ] || { echo "false	$1 not acknowledged"; return; }
  login="${line#* by }"; login="${login%% *}"
  [[ "$login" =~ $GH_LOGIN ]] || { echo "refused	$1 stamped by $login, not a human login"; return; }
  case "$line" in *' --- ok'|*' --- ack') echo "true	$BUNDLE_SLUG@$sha:$rel" ;; *) echo "false	$1 overturned" ;; esac
}

ntrue=0; nwait=0; rc=0
for doc in ${docs[@]+"${docs[@]}"}; do
  [ -f "$doc" ] || usage
  rel="${doc#"$inst"/}"
  target="$(fm "$doc" target_repo)"; [ -n "$target" ] || target="$(fm "$(dirname "$(dirname "$doc")")/project.md" target_repo)"
  list="$(bash "$FOLD" --list "$doc" open_questions 2>/dev/null)" || { printf 'unknown\t%s\t-\topen_questions unreadable\n' "$rel"; continue; }
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    # fold-answers.sh's rule: answered only when the LAST ` --- ` has text after it.
    q="$e"; case "$q" in *' --- '*) [[ "${q##* --- }" =~ ^[[:space:]]*$ ]] || continue; q="${q% --- *}" ;; esac
    nwait=$((nwait + 1))
    case "$q" in Q[0-9]*': do: '*|*' · sweep: '*) continue ;; esac
    case "$q" in *' check: '*) ;; *) continue ;; esac
    pred="${q##* check: }"; kind="${pred%% *}"; arg="${pred#* }"
    [ "$arg" = "$pred" ] && arg=""
    case "$kind" in
      pr-merged) res="$(pr_merged "$arg")" ;;
      file) res="$(file_on_default "$arg" "$target")" ;;
      decision) res="$(decision "$arg" "$doc")" ;;
      *) res="refused	kind $kind is not pr-merged, file or decision" ;;
    esac
    printf '%s\t%s\t%s\t%s\n' "${res%%	*}" "$rel" "${e%%:*}" "${res#*	}"
    [ "${res%%	*}" = true ] || continue
    ntrue=$((ntrue + 1))
    [ "$apply" = 1 ] || continue
    bash "$FOLD" --sweep "$e" "$pred true @ ${res#*	}" "$doc" >/dev/null || rc=3
  done <<EOF
$list
EOF
done
echo "sweep: $ntrue true, $nwait waiting on the human"
exit "$rc"
