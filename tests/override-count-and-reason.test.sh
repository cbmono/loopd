#!/usr/bin/env bash
#
# override-count-and-reason.test.sh — the override count is a QUERY, and the override
# comment's reason is READ OFF THE PR.
#
# Two defects found by the 2026-09-06 audit, both of which a grep cannot tell from correct
# prose: `docs/autonomy.md` said "Eleven PRs have now merged this way" while the live count
# was 47, and every override comment on #139–#166 said "fair-usage limit reached" while
# CodeRabbit's own comment on those PRs said auto reviews are disabled by `.coderabbit.yaml`
# — a different refusal with a different fix. Reasoning: ai-bridge-next/task-030.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
AUT="$REPO/docs/autonomy.md"
OPS="$REPO/docs/operations.md"

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
# Here-string, never a pipe: under `set -o pipefail` a pipe into `grep -q` reports a MATCH
# as a failure whenever the reader exits first (grep-q-under-pipefail-reports-a-match-as-a-failure).
saw() { grep -qE -- "$2" <<<"$1" && echo yes || echo no; }
# The sentence that went stale wrapped across two lines, and grep is line-based — so a
# line-by-line assertion would have passed the very file it was written to refuse.
flat() { printf '%s' "$1" | tr '\n' ' ' | tr -s ' '; }

# The section under test, and the template inside it: everything is scoped to these, so a
# quoted counter-example elsewhere in the file is not mistaken for the thing it warns about.
SECTION="$(awk '/^### Merging on the override/{f=1} f && /^### Cutting a release/{exit} f' "$OPS")"
TEMPLATE="$(awk '/^```md$/{f=1;next} f && /^```$/{exit} f' <<<"$SECTION")"
MARKER="$(head -1 <<<"$TEMPLATE")"

echo "1. docs/autonomy.md hand-types no count of override merges"
# The grammar is "<a number> PRs have merged", in words or digits, however it is emphasised
# — the shape of the sentence that went stale, not the one sentence that did.
COUNT_RE='(\*\*)?([0-9]+|[Oo]ne|[Tt]wo|[Tt]hree|[Ff]our|[Ff]ive|[Ss]ix|[Ss]even|[Ee]ight|[Nn]ine|[Tt]en|[Ee]leven|[Tt]welve|[Nn]ineteen|[Tt]wenty)[ *]+(more +)?(PRs|pull requests)( have)?( now)? merged'
ok "no 'N PRs have now merged' sentence"   "$(saw "$(flat "$(cat "$AUT")")" "$COUNT_RE")" no
ok "…(the grammar can see it: control)"    "$(saw "$(flat $'**Eleven PRs have\nnow merged this way**')" "$COUNT_RE")" yes
ok "…and it reads digits too"              "$(saw '47 PRs have now merged this way' "$COUNT_RE")" yes
# A Finding's filename carries a number and is a CITATION, never a claim about today.
ok "…but not the cited Finding's slug"     "$(saw 'nineteen-consecutive-prs-merged-on-the-override' "$COUNT_RE")" no

echo
echo "2. …it names the query that produces the count, and the Finding behind it"
ok "autonomy.md gives a gh search"          "$(saw "$(cat "$AUT")" 'gh search prs .*--repo')" yes
ok "…over COMMENTS, not titles or bodies"   "$(saw "$(cat "$AUT")" '\-\-match comments')" yes
ok "…and cites the override Finding"        "$(saw "$(cat "$AUT")" 'nineteen-consecutive-prs-merged-on-the-override-so-the-verification-gate-is-a-report')" yes
# The query counts the marker line, so a template whose first line drifts silently zeroes
# the count. Compare the two strings rather than pinning either one.
ok "the query greps the template's marker"  "$(saw "$(cat "$AUT")" "\"${MARKER%% —*}\"")" yes
ok "…(the marker was actually extracted)"   "$(saw "$MARKER" '^Merged on the owner override')" yes

echo
echo "3. the override comment template reads its reason off the PR"
ok "operations.md has the override section" "$(saw "$SECTION" '^### Merging on the override')" yes
ok "…the template asks what the reviewer said" "$(saw "$TEMPLATE" 'Reviewer said:')" yes
ok "…naming CodeRabbit's own comment"       "$(saw "$TEMPLATE" 'Review skipped|coderabbit')" yes
ok "…as a placeholder, to be pasted"        "$(saw "$TEMPLATE" 'Reviewer said: *"?<')" yes
ok "…and the section prints how to fetch it" "$(saw "$SECTION" 'gh pr view <n> .*--json comments')" yes
# The defect was a REASON typed from memory. The section may quote it as history — the
# template may not carry it, because whatever is in the template is what gets pasted.
ok "the template fixes no reason phrase"    "$(saw "$TEMPLATE" 'fair-usage|rate limit reached|limit reached')" no
ok "…(the section still records it: control)" "$(saw "$SECTION" 'fair-usage limit reached')" yes

echo
# A suite can LOSE assertions without going red. Pin the count so a block that stops
# executing shows up here rather than as silence.
total=$((pass + fail))
ok "exactly 16 assertions ran"              "$total" 16

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
