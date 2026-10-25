#!/usr/bin/env bash
#
# review-clearance-qa.test.sh — what plugin/scripts/review-clearance.sh tells the QA fallback:
# the `class:` line that splits CodeRabbit's processing placeholder from a real refusal, the
# refusal outranking the placeholder whatever the stream order, and a PR author's own QA
# verdict counting only against a qa-dispatch.sh record (SCHEMA.md clause 8).
. "$(dirname "$0")/review-clearance.lib.sh"

QA_DISPATCH="$SCRIPTS/qa-dispatch.sh"
export CLAUDE_PROJECT_DIR="$TMP/bundle"
mkdir -p "$CLAUDE_PROJECT_DIR"; printf '{}\n' > "$CLAUDE_PROJECT_DIR/instance.config.json"
LATER="2099-01-01T00:00:00Z"

class_is() { # <name> <expected class>
  local got; got="$(sed -n 's/^class: //p' <<<"$LAST_OUT")"; got="${got%%$'\n'*}"
  if [ "$got" = "$2" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$got"; pass=$((pass+1))
  else printf '  FAIL  %-58s got class %s, want %s\n' "$1" "${got:-<none>}" "$2"; fail=$((fail+1)); fi
}

PLACEHOLDER="$(body_file 'Currently processing new changes in this PR. This may take a few minutes, please wait...' \
                         "Commits: files that changed from the base of the PR and between 6fca618 and $CLEAN_HEAD.")"

echo "== the placeholder holds; every refusal row reads declined =="
setup; add_comment "coderabbitai[bot]" "$PLACEHOLDER"
expect "the processing placeholder -> exit 1" 1
class_is "…class: placeholder" placeholder

while IFS= read -r phrase; do
  [ -n "$phrase" ] || continue
  setup; add_comment "coderabbitai[bot]" "$(body_file "$phrase")"
  expect "refusal '$phrase' -> exit 1" 1
  class_is "…class: declined" declined
done <<'ROWS'
Rate limited by coderabbit.ai
<!-- This is an auto-generated comment: rate limited by coderabbit.ai -->
Review limit reached
Next included review available in 44 minutes.
API limit exceeded for this organization.
Quota exceeded for this repository.
Daily review limit hit.
No reviews left this month.
You have used all of your free reviews.
Reviews were not performed on this PR.
Skipping this review.
Review declined.
Unable to complete the review.
ROWS

while IFS= read -r phrase; do
  [ -n "$phrase" ] || continue
  setup; add_comment "coderabbitai[bot]" "$(body_file "Review limit reached. $phrase")"
  expect "terminal '$phrase' -> exit 5" 5
  class_is "…class: declined" declined
done <<'ROWS'
You are out of credits.
Payment failed for this organization.
ROWS

echo "== a real refusal outranks the placeholder, whatever the stream order =="
setup; add_comment "coderabbitai[bot]" "$PLACEHOLDER"; add_comment "coderabbitai[bot]" "$REFUSAL"
expect "placeholder first, then the recorded rate limit -> exit 1" 1
class_is "…class: declined" declined
says "…and the quote is the refusal, not the placeholder" "DECLINED"
setup; add_comment "coderabbitai[bot]" "$REFUSAL"; add_comment "coderabbitai[bot]" "$PLACEHOLDER"
expect "rate limit first, then the placeholder -> exit 1" 1
class_is "…class: declined" declined
setup; add_comment "coderabbitai[bot]" "$SKIP"
expect "the recorded skip notice is still exit 8, not a refusal" 8

echo "== a PR author's own QA verdict counts only against a dispatch record =="
trailer() { # <nonce|-> [signature]
  body_file 'Verified against the criteria.' '' "${2:-— dev-qa}" '' '<!-- okf-verdict v1' 'verdict: pass' \
            "head_sha: $CLEAN_HEAD" 'reviewer: qa-reviewer' \
            'lenses: correctness=done security=done repro=done' 'unverified_criteria: none' \
            'caveats: none' "dispatch: $1" '-->'
}
mint() { "$QA_DISPATCH" mint --repo acme/widgets --pr 42 --head "${1:-$CLEAN_HEAD}"; }
fresh() { rm -rf "$CLAUDE_PROJECT_DIR/.loopd"; setup; }

fresh; add_comment_at dev "$LATER" "$(trailer 0123456789abcdef0123456789abcdef)"
expect "forged trailer + '— dev-qa' signature, no record -> refused (2)" 2 --reviewer dev
says "…naming the missing dispatch" "no qa-reviewer dispatch is recorded"

fresh; n="$(mint)"; add_comment_at dev "$LATER" "$(trailer "$n")"
expect "the recorded dispatch's nonce, posted after it -> clears" 0 --reviewer dev
says "…and says it matched the record" "matching a recorded qa-reviewer dispatch"

fresh; n="$(mint)"; add_review dev COMMENTED "$CLEAN_HEAD" "$(trailer "$n")"
REVIEWS="$("$REAL_JQ" --arg t "$LATER" '.[0].submitted_at = $t' <<<"$REVIEWS")"
expect "…the same verdict as a review object -> no review (edits are invisible)" 3 --reviewer dev

fresh; n="$(mint)"; add_comment_at dev "$LATER" "$(trailer "$n")"
add_comment_at dev "$LATER" "$(trailer "$n" '— dev-qa (copied)')"
expect "the nonce replayed in a second comment -> neither counts (3)" 3 --reviewer dev
says "…and says why" "only"

fresh; n="$(mint)"; add_comment_edited dev "$LATER" "2099-01-02T00:00:00Z" "$(trailer "$n")"
expect "the recorded verdict comment, edited afterwards -> no review (3)" 3 --reviewer dev

fresh; mint >/dev/null; add_comment_at dev "$LATER" "$(trailer 0123456789abcdef0123456789abcdef)"
expect "a record, but the trailer's nonce is wrong -> no review (3)" 3 --reviewer dev

fresh; mint >/dev/null; add_comment_at dev "$LATER" "$(trailer -)"
expect "a record, but no nonce in the trailer -> no review (3)" 3 --reviewer dev

fresh; n="$(mint)"; add_comment_at dev "2000-01-01T00:00:00Z" "$(trailer "$n")"
expect "the right nonce, posted BEFORE the record -> no review (3)" 3 --reviewer dev

fresh; n="$(mint "$OTHER_SHA")"; add_comment_at dev "$LATER" "$(trailer "$n")"
expect "a record at another head -> refused (2)" 2 --reviewer dev

fresh; n="$(mint)"; add_comment_at dev "$LATER" "$(trailer "$n")"
expect "without --reviewer the author's verdict never counts (3)" 3

fresh; n="$(mint)"; add_comment_at dev "$LATER" "$(trailer "$n")"
add_thread false src/a.sh 3 dev https://example.com/t1 "the guard is off by one"
expect "self-QA: the reviewer's own open thread still refuses (6)" 6 --reviewer dev

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
