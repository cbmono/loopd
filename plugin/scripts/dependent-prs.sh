#!/usr/bin/env bash
#
# dependent-prs.sh — will merging this PR retarget an open PR based on its head branch?
#
#   dependent-prs.sh check <pr> --repo O/R --head SHA [--record [--bundle DIR]]
#       -> `dependent PR <link> will be retargeted on merge` per dependent · `dependent PRs: unknown (<why>)` · nothing
#   dependent-prs.sh verify --bundle DIR --repo O/R --pr N --head SHA   (merge-permit.sh)
#
# Exit 0 none · 1 dependents, or verify refuses · 2 unknown, or usage. Reasoning: docs/pm-design.md#step-4.
# Verified by tests/awaiting-render.test.sh, tests/subagent-merge-yolo.test.sh.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)" || exit 2
FRESH_MINUTES=30
usage() { sed -n '5,7p' "$0" >&2; exit 2; }

mode="${1:-}"; [ $# -gt 0 ] && shift
pr=""; repo=""; head=""; bundle=""; record=""
while [ $# -gt 0 ]; do
  case "$1" in
    --record) record=yes; shift ;;
    --repo|--head|--bundle|--pr)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      case "$1" in --repo) repo="$2" ;; --head) head="$2" ;; --bundle) bundle="$2" ;; --pr) pr="$2" ;; esac
      shift 2 ;;
    -*) usage ;;
    *) [ "$mode" = check ] && [ -z "$pr" ] || usage; pr="$1"; shift ;;
  esac
done
case "$repo" in ?*/?*) ;; *) usage ;; esac
case "$pr" in ''|*[!0-9]*) usage ;; esac
[ -n "$head" ] || usage
B=(); [ -n "$bundle" ] && B=(--bundle "$bundle")

if [ "$mode" = verify ]; then
  [ -n "$bundle" ] || usage
  rf="$("$HERE/clearance-receipt.sh" path --bundle "$bundle" --repo "$repo" --pr "$pr" --head "$head" 2>/dev/null)"
  line="$(awk '$2 == "dependent-prs.sh" { l = $0 } END { print l }' "$rf" 2>/dev/null)"
  [ -n "$line" ] || { echo "no dependent-prs.sh line for $repo#$pr at $head: run dependent-prs.sh check --record first"; exit 1; }
  read -r verdict _ stamp _ <<<"$line"
  case "$verdict" in
    clear) ;;
    dependent) echo "merge held at $head: an open PR is based on its head branch and would be retargeted (dependent-prs.sh)"; exit 1 ;;
    *) echo "merge held at $head: dependent PRs unknown (dependent-prs.sh)"; exit 1 ;;
  esac
  cutoff="$(python3 -c 'import datetime as d, sys; print((d.datetime.now(d.timezone.utc) - d.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$FRESH_MINUTES" 2>/dev/null)"
  [ -n "$cutoff" ] && [ ! "$stamp" \< "$cutoff" ] || { echo "the dependent-prs.sh line at $head is older than ${FRESH_MINUTES}m: re-run check --record"; exit 1; }
  exit 0
fi
[ "$mode" = check ] || usage

finish() { # <clear|dependent|unknown> <exit>
  [ -z "$record" ] || "$HERE/clearance-receipt.sh" record dependent-prs.sh --dependents "$1" ${B[@]+"${B[@]}"} \
    --repo "$repo" --pr "$pr" --head "$head" >/dev/null 2>&1
  exit "$2"
}
unknown() { echo "dependent PRs: unknown ($1)"; finish unknown 2; }

meta="$(gh pr view "$pr" --repo "$repo" --json headRefName,isCrossRepository \
        --jq '[(.headRefName // ""), (.isCrossRepository | tostring)] | @tsv' 2>/dev/null)" || unknown "PR $pr is unreadable"
ref="$(printf '%s' "$meta" | cut -f1)"; cross="$(printf '%s' "$meta" | cut -f2)"
case "$cross" in true) finish clear 0 ;; false) ;; *) unknown "whether PR $pr comes from a fork is unreadable" ;; esac
[ -n "$ref" ] || unknown "the head branch of PR $pr is unreadable"

dbm="$(gh api "repos/$repo" --jq '.delete_branch_on_merge' 2>/dev/null)" || unknown "delete_branch_on_merge is unreadable"
case "$dbm" in true) ;; false) finish clear 0 ;; *) unknown "delete_branch_on_merge is unreadable" ;; esac

q="$(jq -rn --arg r "$ref" '$r | @uri')" || unknown "the head branch name cannot be encoded"
list="$(gh api "repos/$repo/pulls?state=open&base=$q&per_page=100" --paginate \
        --jq '.[] | [(.number | tostring), (.html_url // ""), (.base.ref // ""), (.base.repo.full_name // "")] | @tsv' 2>/dev/null)" \
  || unknown "the open PRs based on its head branch are unreadable"
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
lrepo="$(lc "$repo")"; n=0
while IFS=$'\t' read -r num url base brepo; do
  [ -n "$num" ] && [ "$base" = "$ref" ] && [ "$(lc "$brepo")" = "$lrepo" ] && [ "$num" != "$pr" ] || continue
  case "$num" in *[!0-9]*) continue ;; esac
  case "$(lc "$url")" in "https://"*"/$lrepo/pull/$num") ;; *) unknown "PR $num lists no URL in $repo" ;; esac
  echo "dependent PR [${repo##*/}#$num]($url) will be retargeted on merge"; n=$((n + 1))
done <<<"$list"
[ "$n" -eq 0 ] && finish clear 0
finish dependent 1
