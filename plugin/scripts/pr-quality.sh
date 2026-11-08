#!/usr/bin/env bash
# pr-quality.sh — three quality metrics over the last merged PRs of a repo, in two
# consecutive windows, and the band between them: ✗ criteria rows per PR body; reviewer
# findings per PR — CodeRabbit's inline review comments and a qa-reviewer verdict's FAIL
# rows, counted apart, `-` where that reviewer never reviewed; stall escalations from the
# tick ledger (TICK close lines naming ESCALATE) inside each window's merge span.
#
#   pr-quality.sh --repo <owner/name> [--limit 40] [--window 20] [--ledger <log.md>] [--rows]
#
# Exit: 0 printed · 1 the host could not answer · 3 usage. Reasoning: leaner-prompts/task-001.
set -uo pipefail
usage() { sed -n '2,10p' "$0" >&2; exit 3; }
repo=""; limit=40; window=20; ledger=""; rows=no
while [ $# -gt 0 ]; do
  case "$1" in --repo|--limit|--window|--ledger) [ $# -ge 2 ] || usage ;; esac
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --limit) limit="$2"; shift 2 ;;
    --window) window="$2"; shift 2 ;;
    --ledger) ledger="$2"; shift 2 ;;
    --rows) rows=yes; shift ;;
    *) usage ;;
  esac
done
case "$repo" in */*) ;; *) usage ;; esac
case "$limit$window" in *[!0-9]*|'') usage ;; esac
[ "$limit" -ge 1 ] && [ "$window" -ge 1 ] || usage
[ -z "$ledger" ] || [ -r "$ledger" ] || usage
{ command -v gh && command -v jq; } >/dev/null 2>&1 || { echo "pr-quality: gh and jq are required" >&2; exit 1; }

prs="$(gh pr list -R "$repo" --state merged --limit "$limit" --json number,mergedAt 2>/dev/null \
  | jq -r 'sort_by(.mergedAt) | reverse | .[] | "\(.number)\t\(.mergedAt)"')" || prs=""
[ -n "$prs" ] || { echo "pr-quality: no merged PR read from $repo" >&2; exit 1; }

# One line per PR: number mergedAt x_rows cr_findings qa_fail — a `-` is "never reviewed by
# that reviewer". CodeRabbit reviewed when it left a review object; qa-reviewer when an
# non-bot issue comment carries an okf-verdict block (the one reviewer that posts one).
table="$(printf '%s\n' "$prs" | while IFS=$'\t' read -r n at; do
  body="$(gh pr view "$n" -R "$repo" --json body --jq .body 2>/dev/null)" || exit 1
  x="$(printf '%s\n' "$body" | grep -c -E '^\|[^|]*\|[[:space:]]*✗[[:space:]]*\|')"
  # `--paginate` prints one array per page, so the count is taken after `jq -s` joins them.
  cr_rev="$(gh api --paginate "repos/$repo/pulls/$n/reviews" 2>/dev/null | jq -rs '[.[][] | select(.user.login | test("coderabbit"))] | length')" || exit 1
  [ -n "$cr_rev" ] || exit 1
  if [ "$cr_rev" -gt 0 ]; then
    cr="$(gh api --paginate "repos/$repo/pulls/$n/comments" 2>/dev/null | jq -rs '[.[][] | select(.user.login | test("coderabbit"))] | length')" || exit 1
    [ -n "$cr" ] || exit 1
  else cr="-"; fi
  qa="$(gh api --paginate "repos/$repo/issues/$n/comments" 2>/dev/null | jq -rs '
      [.[][] | select(.user.type != "Bot") | .body | select(contains("<!-- okf-verdict"))]
      | if length == 0 then "-" else map([scan("\\|[^|\\n]*\\|[[:space:]]*FAIL[[:space:]]*\\|")] | length) | add end')" || exit 1
  [ -n "$qa" ] || exit 1
  printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$at" "$x" "$cr" "${qa:--}"
done)" || { echo "pr-quality: the host did not answer for every PR" >&2; exit 1; }
[ "$(printf '%s\n' "$table" | grep -c .)" -eq "$(printf '%s\n' "$prs" | grep -c .)" ] || { echo "pr-quality: the host did not answer for every PR" >&2; exit 1; }

esc() { # <from-ISO> <to-ISO> — ESCALATE close lines in the ledger between them, `-` without one
  [ -n "$ledger" ] || { echo "-"; return; }
  awk -v a="$1" -v b="$2" '/^\* TICK [0-9]/ && /close:/ && /ESCALAT/ { t = $3; if (t >= a && t <= b) n++ } END { print n + 0 }' "$ledger"
}

[ "$rows" = yes ] && { printf 'pr\tmerged\tx_rows\tcr_findings\tqa_fail\n%s\n\n' "$table"; }
printf '%-8s %-5s %-6s %-9s %-7s %-7s %-10s %-9s %-7s %-9s\n' window prs x_rows cr_find/pr cr_prs qa_fail qa_prs unreviewed escal span
w=0; total="$(printf '%s\n' "$table" | grep -c .)"
while [ $((w * window)) -lt "$total" ]; do
  w=$((w + 1))
  chunk="$(printf '%s\n' "$table" | sed -n "$(( (w - 1) * window + 1 )),$(( w * window ))p")"
  from="$(printf '%s\n' "$chunk" | tail -1 | cut -f2)"; to="$(printf '%s\n' "$chunk" | head -1 | cut -f2)"
  printf '%s\n' "$chunk" | awk -F'\t' -v w="$w" -v e="$(esc "$from" "$to")" -v span="${from%T*}..${to%T*}" '
    { n++; x += $3; if ($4 != "-") { cr += $4; crp++ }; if ($5 != "-") { qa += $5; qap++ }; if ($4 == "-" && $5 == "-") un++ }
    END { printf "%-8s %-5d %-6.2f %-9s %-7d %-7s %-10d %-9d %-7s %-9s\n", w, n, x / n,
          (crp ? sprintf("%.2f", cr / crp) : "-"), crp, (qap ? sprintf("%.2f", qa / qap) : "-"), qap, un, e, span }'
done
printf '%s\n' "$table" | awk -F'\t' -v window="$window" -v l="$ledger" '
  { i = int((NR - 1) / window) + 1; if (i > 2) next; n[i]++; x[i] += $3; if ($4 != "-") { cr[i] += $4; crp[i]++ }; if ($5 != "-") { qa[i] += $5; qap[i]++ }; if ($4 == "-" && $5 == "-") un[i]++ }
  function abs(v) { return v < 0 ? -v : v }
  # A reviewer with no reviewed PR in a window has no mean there, so that band is `-`, not 0.
  END { if (n[2] != window) { print "band: needs two full windows"; exit }
        printf "band (|window 1 - window 2|): x_rows/pr %.2f · cr_findings/pr %s · qa_fail/pr %s · unreviewed %d\n", abs(x[1] / n[1] - x[2] / n[2]),
          (crp[1] && crp[2] ? sprintf("%.2f", abs(cr[1] / crp[1] - cr[2] / crp[2])) : "-"),
          (qap[1] && qap[2] ? sprintf("%.2f", abs(qa[1] / qap[1] - qa[2] / qap[2])) : "-"), abs(un[1] - un[2]) }'
