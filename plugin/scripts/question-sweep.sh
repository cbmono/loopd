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
pr_merged() { # <url>
  [[ "$1" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+$ ]] || { echo "refused	not a pull request URL"; return; }
  case "$(gh pr view "$1" --json state --jq .state 2>/dev/null)" in
    MERGED) echo "true	$1" ;; OPEN|CLOSED) echo "false	$1 not merged" ;; *) echo "unknown	gh pr view failed" ;;
  esac
}
file_on_default() { # <owner>/<repo>:<path>[=<value>]
  [[ "$1" =~ ^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+):([^=]+)(=(.*))?$ ]] || { echo "refused	not <owner>/<repo>:<path>[=<value>]"; return; }
  local repo="${BASH_REMATCH[1]}" path="${BASH_REMATCH[2]}" has="${BASH_REMATCH[3]}" value="${BASH_REMATCH[4]}" def sha enc
  def="$(gh api "repos/$repo" --jq .default_branch 2>/dev/null)" && [ -n "$def" ] || { echo "unknown	no default branch for $repo"; return; }
  sha="$(gh api "repos/$repo/commits/$def" --jq .sha 2>/dev/null)"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "unknown	no head sha for $repo"; return; }
  enc="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$path")" || { echo "unknown	cannot encode path"; return; }
  if ! gh api -H 'Accept: application/vnd.github.raw' "repos/$repo/contents/$enc?ref=$sha" >"$TMP/body" 2>"$TMP/err"; then
    grep -q 'HTTP 404' "$TMP/err" && echo "false	$repo@$sha:$path absent" || echo "unknown	contents read failed"
    return
  fi
  if [ -n "$has" ] && ! grep -qF -- "$value" "$TMP/body"; then echo "false	$repo@$sha:$path lacks the value"; return; fi
  echo "true	$repo@$sha:$path"
}
# Only the COMMITTED copy counts, and only an ack whose stamp is a GitHub login: `<unknown>`
# and `loopd:…` are not a human, and the working tree is agent-writable.
decision() { # <D<n>> <task-doc>
  [[ "$1" =~ ^D[0-9]+$ ]] || { echo "refused	not D<n>"; return; }
  local pm rel origin slug sha line login
  pm="$(cd "$(dirname "$(dirname "$2")")" && pwd -P)/project.md"; rel="${pm#"$inst"/}"
  sha="$(git -C "$inst" rev-parse HEAD 2>/dev/null)" && git -C "$inst" show "HEAD:$rel" >"$TMP/pm" 2>/dev/null \
    || { echo "unknown	$rel not committed"; return; }
  origin="$(git -C "$inst" remote get-url origin 2>/dev/null)"
  slug="$(printf '%s' "$origin" | sed -nE 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+)$#\2#p')"; slug="${slug%.git}"
  [ -n "$slug" ] || { echo "unknown	bundle has no GitHub origin"; return; }
  line="$(bash "$FOLD" --list "$TMP/pm" acknowledged_decisions 2>/dev/null | grep -E "^[0-9TZ:-]+ by [^ ]+ · $1: " | head -1)"
  [ -n "$line" ] || { echo "false	$1 not acknowledged"; return; }
  login="${line#* by }"; login="${login%% *}"
  [[ "$login" =~ $GH_LOGIN ]] || { echo "refused	$1 stamped by $login, not a human login"; return; }
  case "$line" in *' --- ok'|*' --- ack') echo "true	$slug@$sha:$rel" ;; *) echo "false	$1 overturned" ;; esac
}

ntrue=0; nwait=0; rc=0
for doc in ${docs[@]+"${docs[@]}"}; do
  [ -f "$doc" ] || usage
  rel="${doc#"$inst"/}"
  list="$(bash "$FOLD" --list "$doc" open_questions 2>/dev/null)" || { printf 'unknown\t%s\t-\topen_questions unreadable\n' "$rel"; continue; }
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    case "$e" in *' --- '*) continue ;; esac
    nwait=$((nwait + 1))
    case "$e" in Q[0-9]*': do: '*|*' · sweep: '*) continue ;; esac
    case "$e" in *' check: '*) ;; *) continue ;; esac
    pred="${e##* check: }"; kind="${pred%% *}"; arg="${pred#* }"
    [ "$arg" = "$pred" ] && arg=""
    case "$kind" in
      pr-merged) res="$(pr_merged "$arg")" ;;
      file) res="$(file_on_default "$arg")" ;;
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
