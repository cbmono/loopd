#!/usr/bin/env bash
#
# pr-quality.test.sh — `plugin/scripts/pr-quality.sh`: ✗ criteria rows, CodeRabbit inline
# comments and qa-reviewer FAIL rows per merged PR, in two windows, against a fake `gh`.
#
# THE PROPERTIES:
#   * A reviewer that never reviewed is `-`, never 0 — an unreviewed PR is marked, not scored.
#   * CodeRabbit is counted from its review comments only when it left a review object;
#     qa-reviewer from FAIL rows of a non-bot okf-verdict comment.
#   * Windows are consecutive slices of the merge-ordered list; escalations are ledger TICK
#     close lines naming ESCALATE inside the window's merge span; the band is |w1 - w2|.
#   * A metric no PR in a window carries is `-` in the band too, never 0; a short second
#     window prints no band; `--paginate` pages are joined before anything is counted.
#   * A host that cannot answer is exit 1, never a shorter table.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PQ="$REPO/plugin/scripts/pr-quality.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/prquality.XXXXXX")" || { echo "pr-quality.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

# The fake host: `gh pr list` reads $FX/list.json (honouring --limit), `gh pr view`
# $FX/body-<n>.txt; `gh api --paginate <path>` prints $FX/<path with / as _>.json raw, so a
# file holding two arrays is two pages, as the real host prints them. A missing file is the
# host failing.
FX="$TMP/fx"; BIN="$TMP/bin"; mkdir -p "$FX" "$BIN"
cat > "$BIN/gh" <<'EOS'
#!/usr/bin/env bash
case "$1 $2" in
  "pr list") n=""; while [ $# -gt 0 ]; do [ "$1" = --limit ] && n="$2"; shift; done; jq ".[:${n:-100}]" "$FX/list.json" ;;
  "pr view") cat "$FX/body-$3.txt" 2>/dev/null || exit 1 ;;
  "api --paginate") p="${3//\//_}"; f="$FX/$p.json"; [ -f "$f" ] || exit 1; cat "$f" ;;
  *) exit 1 ;;
esac
EOS
chmod +x "$BIN/gh"; export FX
body() { # <n> <x-rows>
  { printf '## Description\n\n| Criterion | ✓ | Verified by |\n|---|---|---|\n| a | ✓ | `t` 1/0 |\n'
    i=0; while [ "$i" -lt "$2" ]; do printf '| b | ✗ | needs a host |\n'; i=$((i+1)); done; } > "$FX/body-$1.txt"; }
reviews() { printf '[%s]\n' "$2" > "$FX/repos_o_r_pulls_$1_reviews.json"; }
rcomments() { printf '[%s]\n' "$2" > "$FX/repos_o_r_pulls_$1_comments.json"; }
icomments() { printf '[%s]\n' "$2" > "$FX/repos_o_r_issues_$1_comments.json"; }
CR='{"user":{"login":"coderabbitai[bot]","type":"Bot"}}'
QA='{"user":{"login":"alice","type":"User"},"body":"| c | PASS | x |\n| d | FAIL | y |\n| e | FAIL | z |\n<!-- okf-verdict v1\nverdict: changes-requested\n-->"}'
BOT_VERDICT='{"user":{"login":"somebot[bot]","type":"Bot"},"body":"| d | FAIL | y |\n<!-- okf-verdict v1 -->"}'

# Four PRs, newest first: 4 CR-reviewed with 2 inline comments (one per page) and 1 ✗; 3
# qa-reviewed with 2 FAIL rows; 2 both, no findings; 1 unreviewed (a bot's verdict is not a
# qa verdict).
printf '[{"number":1,"mergedAt":"2026-01-01T00:00:00Z"},{"number":4,"mergedAt":"2026-01-04T00:00:00Z"},{"number":2,"mergedAt":"2026-01-02T00:00:00Z"},{"number":3,"mergedAt":"2026-01-03T00:00:00Z"}]\n' > "$FX/list.json"
body 4 1; reviews 4 "$CR"; printf '[%s]\n[%s]\n' "$CR" "$CR" > "$FX/repos_o_r_pulls_4_comments.json"; icomments 4 ""
body 3 0; reviews 3 ""; rcomments 3 "$CR"; icomments 3 "$QA"
body 2 0; reviews 2 "$CR"; rcomments 2 ""; icomments 2 "$QA"; icomments 2 '{"user":{"login":"alice","type":"User"},"body":"| c | PASS | x |\n<!-- okf-verdict v1 -->"}'
body 1 0; reviews 1 ""; rcomments 1 ""; icomments 1 "$BOT_VERDICT"
printf '* TICK 2026-01-01T12:00:00Z by alice close: ESCALATE 2/2\n* TICK 2026-01-03T12:00:00Z by alice close: fine\n* TICK 2026-01-03T13:00:00Z by alice close: ESCALATED one\n* TICK 2026-01-09T00:00:00Z by alice open: ESCALATE\n' > "$TMP/log.md"

run() { PATH="$BIN:$PATH" bash "$PQ" --repo o/r "$@" 2>&1; }
OUT="$(run --limit 4 --window 2 --ledger "$TMP/log.md" --rows)"; rc=$?
echo "== 1. per-PR rows =="
ok "exit 0" "$rc" 0
ok "rows are merge-ordered, newest first"            "$(printf '%s\n' "$OUT" | awk -F'\t' '$1 ~ /^[0-9]+$/ {printf "%s ", $1}')" "4 3 2 1 "
ok "PR 4: 1 ✗ row, 2 CodeRabbit comments across 2 pages, no qa verdict" "$(printf '%s\n' "$OUT" | awk -F'\t' '$1 == 4 {print $3, $4, $5}')" "1 2 -"
ok "PR 3: CodeRabbit comments without a review object are not a review" "$(printf '%s\n' "$OUT" | awk -F'\t' '$1 == 3 {print $4, $5}')" "- 2"
ok "PR 2: reviewed by both, 0 findings each (not -)"   "$(printf '%s\n' "$OUT" | awk -F'\t' '$1 == 2 {print $4, $5}')" "0 0"
ok "PR 1: a bot's okf-verdict is not a qa review"      "$(printf '%s\n' "$OUT" | awk -F'\t' '$1 == 1 {print $4, $5}')" "- -"
echo "== 2. windows and the band =="
w1="$(printf '%s\n' "$OUT" | awk '$1 == "1" && $2 == "2"')"; w2="$(printf '%s\n' "$OUT" | awk '$1 == "2" && $2 == "2"')"
ok "window 1 = PRs 4,3: x 0.50, cr 2.00 over 1, qa 2.00 over 1, 0 unreviewed" "$(printf '%s\n' "$w1" | awk '{print $3, $4, $5, $6, $7, $8}')" "0.50 2.00 1 2.00 1 0"
ok "…1 escalation in its span (the open line and 01-01 excluded)" "$(printf '%s\n' "$w1" | awk '{print $9, $10}')" "1 2026-01-03..2026-01-04"
ok "window 2 = PRs 2,1: 1 unreviewed, cr 0.00, qa 0.00"   "$(printf '%s\n' "$w2" | awk '{print $3, $4, $6, $8, $9}')" "0.00 0.00 0.00 1 1"
ok "the band is the absolute difference per metric"       "$(printf '%s\n' "$OUT" | grep '^band')" "band (|window 1 - window 2|): x_rows/pr 0.50 · cr_findings/pr 2.00 · qa_fail/pr 2.00 · unreviewed 1"
ok "without --ledger escalations are -"                   "$(run --limit 4 --window 2 | awk '$1 == "1" && $2 == "2" {print $9}')" "-"
ok "without --rows no per-PR line prints"                 "$(run --limit 4 --window 2 | grep -c -E '^[0-9]+	')" 0
echo "== 3. no data is -, a short window has no band =="
OUT3="$(run --limit 3 --window 2)"
ok "--limit 3 --window 2: window 2 is one PR short, so no band prints" "$(printf '%s\n' "$OUT3" | grep -c '^band (')" 0
ok "…and the table says so"                               "$(printf '%s\n' "$OUT3" | grep -c '^band: needs two full windows')" 1
# PR 5 is unreviewed; the list now orders 4,3 | 1,5 — window 2 has no reviewed PR at all.
body 5 0; reviews 5 ""; rcomments 5 ""; icomments 5 ""
printf '[{"number":5,"mergedAt":"2025-12-31T00:00:00Z"},{"number":1,"mergedAt":"2026-01-01T00:00:00Z"},{"number":4,"mergedAt":"2026-01-04T00:00:00Z"},{"number":3,"mergedAt":"2026-01-03T00:00:00Z"}]\n' > "$FX/list.json"
OUT4="$(run --limit 4 --window 2)"
ok "a window with no reviewed PR is - in the band for that reviewer, never 0" "$(printf '%s\n' "$OUT4" | grep '^band (')" "band (|window 1 - window 2|): x_rows/pr 0.50 · cr_findings/pr - · qa_fail/pr - · unreviewed 2"
echo "== 4. refusals =="
PATH="$BIN:$PATH" perl -e 'alarm 10; exec @ARGV' bash "$PQ" --repo o/r --window 0 >/dev/null 2>&1; ok "--window 0 is usage (exit 3), not a hang" "$?" 3
PATH="$BIN:$PATH" bash "$PQ" --repo o/r --limit 0 >/dev/null 2>&1; ok "--limit 0 is usage" "$?" 3
rm "$FX/repos_o_r_pulls_3_reviews.json"; run --limit 4 --window 2 >/dev/null; ok "a host that cannot answer one PR is exit 1" "$?" 1
PATH="$BIN:$PATH" bash "$PQ" >/dev/null 2>&1; ok "no --repo is usage (exit 3)" "$?" 3
PATH="$BIN:$PATH" bash "$PQ" --repo o/r --limit x >/dev/null 2>&1; ok "a non-numeric --limit is usage" "$?" 3
printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
