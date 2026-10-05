#!/usr/bin/env bash
#
# review-clearance.test.sh — exercises precondition 2 of the delegated merge gate,
# plugin/scripts/review-clearance.sh.
#
# THE THREE SHAPES, and only one of them clears:
#
#   1. a real review        → exit 0    (tests/fixtures/reviewer/clean-review.pr29.md)
#   2. a REFUSAL behind a green check → exit 1
#                              (tests/fixtures/reviewer/rate-limit-refusal.pr30.md)
#   3. no reviewer signal at all      → exit 3
#
# Shapes 1 and 2 are RECORDED, verbatim, from the two pull requests where this went
# wrong: #29 was reviewed, #30 and #31 were refused behind an identically green check
# and merged unreviewed, one of them shipping a shell script at mode 100644. Handwritten
# samples would prove nothing here — the whole difficulty is that the two real bodies
# look alike, and only a real one can show how alike.
#
# THE FALSE POSITIVE THIS FILE EXISTS TO PIN. The refusal comment carries the same
# "between <base> and <head>" range a real review carries, and on #30 that head WAS the
# PR head. So the obvious detector — "does an artifact name the current head" — returns
# TRUE for the refusal. `the trap` section below asserts that property of the fixture
# first (so the test fails if the evidence ever changes) and then asserts the script
# refuses anyway. Get the order of the two classifications wrong and this file goes red.
#
# WHAT CHANGED, AND WHAT THIS FILE NOW HAS TO PROVE. Evidence and pinning moved to the
# STRUCTURED API: a review object's `state` and its `commit_id`, read from
# `/repos/{o}/{r}/pulls/{n}/reviews`. So there are two new obligations here — that a
# review object clears on its commit_id and NOT on what its body happens to mention (the
# `the API decides` section drives exactly that separation), and that the prose which used
# to clear no longer does (`prose no longer clears anything`, which lives in
# tests/review-clearance-bodies.test.sh). Text matching is left with one job, detecting a
# refusal, where a false positive fails closed.
#
# `gh` and `jq` are replaced by stubs on PATH, so the whole matrix runs offline; the jq
# stub delegates to the real one unless a fixture asks it to break.
#
# ONE OF THREE. The stubs, the fixture builders and the assertion helpers are sourced from
# tests/review-clearance.lib.sh; the hand-built bodies are in
# tests/review-clearance-bodies.test.sh and the modes, tables and gates around the
# classifier in tests/review-clearance-gates.test.sh. This file keeps what is RECORDED: the
# real comment bodies, and github.com's own rendering of every case in
# tests/fixtures/reviewer/host-rendering.txt.
. "$(dirname "$0")/review-clearance.lib.sh"

echo "== the fixtures are the real thing =="
assert "the recorded refusal exists"     "$(yes_if test -s "$REFUSAL")"
assert "the recorded clean review exists" "$(yes_if test -s "$CLEAN")"

echo
echo "== shape 1: a real review clears =="
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "the recorded clean review -> clear" 0
says   "  ...naming the reviewer that produced the artifact" "coderabbitai"
says   "  ...and the head it is pinned to" "$CLEAN_HEAD"

# The reviewer publishes its verdict as a plain issue comment on this repo, but a review
# OBJECT is the other half of the contract and clears through the API instead.
setup "$CLEAN_HEAD"; add_review coderabbitai COMMENTED "$CLEAN_HEAD" "$CLEAN"
expect "the same body as a review object at the head -> clear" 0
says   "  ...and says the API state is what cleared it" "a submitted review (COMMENTED)"

echo
echo "== the API decides a review object, not the prose in it =="
# THE FALSE LIMITATION THIS SECTION KILLS. This script used to claim an APPROVED review
# could not be pinned, "because gh pr view does not expose a review's commit_id" — so
# EVERY review object was pinned by whether its body happened to mention the head SHA,
# which is exactly the property that makes a refusal indistinguishable from a review.
# `gh api /repos/{o}/{r}/pulls/{n}/reviews` does expose it, and `gh` was already required.
setup "$CLEAN_HEAD"; add_review coderabbitai APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "an EMPTY-bodied APPROVED review at the head -> clear" 0
setup "$CLEAN_HEAD"; add_review coderabbitai CHANGES_REQUESTED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "…and CHANGES_REQUESTED is a review that happened too" 0

# The other direction, and it is the load-bearing one: a review object made at a DIFFERENT
# commit does not clear even though its body names the current head verbatim. Under
# body-SHA pinning this cleared; under commit_id pinning the body is not consulted at all.
assert "the clean review's body really does name the head" \
  "$(yes_if grep -Fq "$CLEAN_HEAD" "$CLEAN")"
setup "$CLEAN_HEAD"; add_review coderabbitai APPROVED "$OTHER_SHA" "$CLEAN"
expect "a review of an EARLIER commit whose body names this head -> stale" 4
says   "  ...naming the commit it was actually made at" "$OTHER_SHA"

setup "$CLEAN_HEAD"; add_review coderabbitai APPROVED "" "$CLEAN"
expect "a review object the API gives no commit_id for -> stale, not clear" 4

# A refusal is still a refusal when it arrives as a review OBJECT at the head. The
# structural evidence never outranks the refusal tiers — TEST 1 runs first, always.
setup "$REFUSAL_HEAD"; add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$REFUSAL"
expect "the recorded refusal AS a review object at the head -> refuse" 1
says   "  ...quoting the reviewer's own words" "Review limit reached"

echo
echo "== a review object that says NOTHING is not a review =="
# WHAT MOVING THE PIN TO commit_id GAVE AWAY, and the reason a corpus rescore could not
# see it. The old body-SHA pin was wrong for every reason the script's header gives, but in
# ONE respect it failed closed: an empty body cannot name a head, so an empty review object
# could not clear. With `state` + `commit_id` as the pin, an EMPTY-BODIED `COMMENTED`
# object at the head cleared OVER the reviewer's own verbatim recorded refusal at that same
# head — and review objects are streamed before comments, so it exited 0 before the refusal
# was ever read. No PR in the 35-PR corpus carries both shapes, so the paired rescore
# proves nothing here: this case is CONSTRUCTED, which is the only way to see it.
#
# `COMMENTED` is not a claim. The host mints one for any inline comment and any thread
# reply — twelve empty-bodied ones already exist in this repository's corpus — so for that
# state the claim, if there is one, is the body.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$EMPTY_BODY"
expect "an EMPTY COMMENTED object at the head loses to a refusal at that head" 1
says   "  ...quoting the refusal rather than the empty object" "Review limit reached"
says   "  ...and saying the empty object did not outrank it" "does not outrank"

# THE CONTROL, and it is what keeps the rule about CONTENT rather than about review
# objects: the identical object at the identical head, WITH a body, still clears past the
# same refusal. This is #15's shape, the one PR in the corpus that clears through route A.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$(body_file \
  '**Actionable comments posted: 1**' 'One nit in the parser.')"
expect "…while the same object WITH a body clears past that refusal" 0

# An APPROVED/CHANGES_REQUESTED state IS a claim whatever the body says — but not one that
# outranks a refusal at the same commit either.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai APPROVED "$REFUSAL_HEAD" "$EMPTY_BODY"
expect "an EMPTY APPROVED at the head loses to a refusal at that head too" 1

# THE PROPERTY THIS MUST NOT BREAK, and the reason the refusal has to NAME the head rather
# than merely exist: a PR that was skipped once has to be able to recover. The recorded
# refusal names #30's head, so against a different head it is an OLD refusal — and the
# empty approval at THIS head wins, exactly as it did before this change.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "…while an OLD refusal at another commit still loses to it" 0
assert "…because the recorded refusal names #30's head, not this one" \
  "$(yes_if bash -c 'grep -Fq "$2" "$1" && ! grep -Fq "$3" "$1"' _ "$REFUSAL" "$REFUSAL_HEAD" "$CLEAN_HEAD")"

# And with no refusal anywhere, an empty COMMENTED object is still not evidence — it is
# not ranked below a refusal, it evidences nothing at all.
setup "$CLEAN_HEAD"; add_review coderabbitai COMMENTED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "an EMPTY COMMENTED object on its own evidences nothing" 4
says   "  ...saying why an empty COMMENTED is not a claim" "inline comment or thread reply"
# ...where a body of nothing but whitespace is a body of nothing.
setup "$CLEAN_HEAD"; add_review coderabbitai COMMENTED "$CLEAN_HEAD" "$(body_file '   ' '' '  ')"
expect "…and neither does one holding only whitespace" 4
# ...nor one whose only content is unreadable: an unbalanced fence renders to nothing.
setup "$CLEAN_HEAD"
add_review coderabbitai COMMENTED "$CLEAN_HEAD" "$(body_file '```' 'Reviewed.')"
expect "…nor one whose content is behind an unbalanced fence" 4

echo
echo "== …and 'says nothing' means the PAGE is blank, not that the bytes are =="
# THE NARROWEST WAY BACK IN, and it restored the pre-fix behaviour exactly. "Content" was
# any non-whitespace byte, so a body of one ZERO-WIDTH SPACE — or of one empty HTML
# COMMENT, which is the very shape every machine marker in this file takes — was a claim,
# and an empty review object cleared over the recorded refusal at that head again.
#
# THE BATTERY THAT USED TO SIT HERE IS GONE, AND ITS ABSENCE IS THE POINT. It was 22 rows
# naming a zero-width space, a variation selector, a Hangul filler and so on: the list the
# script had stopped removing, kept as a test. It could only ever assert that the
# characters somebody already thought of are handled, which is the enumeration the fix
# deleted, and it said nothing about the constructs that walked through the fix after it —
# `[x]: /y`, `[](url)`, `<!DOCTYPE html>`, `<![CDATA[x]]>`, `<?php ?>`, `<a href="1>2">`.
# All 22 rows and all six of those are now in `host-rendering.txt` as the `content` family,
# where the verdict is GITHUB'S, not this repository's opinion of what renders — see the
# host-renderer section below. What stays here is the shape of the route itself, driven
# end to end, so the reason those cases matter is visible where the behaviour is.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$(body_file '<!-- -->')"
expect "a review object whose body renders blank -> not a claim" 1
says   "  ...and the refusal is what the operator is shown" "DECLINED to review"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$(body_file '<!--' 'hidden' '-->')"
expect "…including a comment spanning lines, which a line-at-a-time reader misses" 1
# THE CONTROL, and it is what keeps this a rule about what is LEFT rather than a longer
# list of what is taken away: one visible word beside the same markup IS a claim.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$(body_file '<!-- x -->ok')"
expect "…while one visible word beside it IS a claim" 0

echo "== a review state must be one the API publishes, case and all =="
# PENDING was never submitted and DISMISSED has been withdrawn; neither is evidence that
# anybody looked. They were skipped by a case-SENSITIVE shell `case`, so any other casing
# fell straight through the skip and was then treated as a submitted review.
for st in PENDING DISMISSED pending dismissed Pending Dismissed APPROVED_MAYBE; do
  setup "$CLEAN_HEAD"; add_review coderabbitai "$st" "$CLEAN_HEAD" "$CLEAN"
  expect "state '$st' is not a submitted review -> no review" 3
done
# The control for all seven: the identical fixture in a state the API does publish.
setup "$CLEAN_HEAD"; add_review coderabbitai APPROVED "$CLEAN_HEAD" "$CLEAN"
expect "…while APPROVED, spelled as the API spells it, clears" 0

echo
echo "== shape 2: a refusal behind a green check is NOT clearance =="
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
expect "the recorded rate-limit refusal -> refuse" 1
says   "  ...quoting the reviewer's own words" "Review limit reached"
says   "  ...and saying when the quota reopens" "44 minutes"
says   "  ...and saying plainly this is not clearance" "not clearance"
says   "  ...and that nothing re-reviews it automatically" "NOT re-reviewed automatically"

echo
echo "== shape 2c: TRANSIENT (1) and TERMINAL (5) are different refusals =="
# WHY THIS SPLIT IS DRIVEN AND NOT DESCRIBED. Both exits refuse, so no merge gate can tell
# them apart and no assertion elsewhere would notice them collapsing. What differs is the
# CALLER'S NEXT MOVE, and it differs by a whole deep-tier review session: exit 1 is waited
# out (measured 2026-08-31: the reviewer was rate-limited on four PRs and reviewed all four
# within the hour), exit 5 needs a human to buy credits or fix a token. Collapse the two
# and either every rate limit spends a session, or an empty account is waited on forever.
#
# THE RECORDED FIXTURE IS THE CONTROL, and it is the one that matters most: it is a REAL
# CodeRabbit rate-limit notice, it names a plan and carries a docs link, and it must stay
# exit 1. A terminal table loose enough to match a vendor's sales copy would ask a human
# every time the reviewer paused.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
expect "the recorded rate-limit notice stays TRANSIENT" 1

TERMINAL="$(body_file \
  'Review skipped.' \
  '' \
  'No credits remaining on this organization. Add credits to continue reviewing.')"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$TERMINAL"
expect "an out-of-credits refusal -> TERMINAL" 5
says   "  ...saying only a human reopens it"      "until a HUMAN acts"
says   "  ...and that waiting will not do it"     "WAITING WILL NOT CLEAR THIS"
says   "  ...quoting the reviewer's own words"    "No credits remaining"

AUTHFAIL="$(body_file \
  'Review skipped.' \
  '' \
  'Authentication failed: the installation token is invalid.')"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$AUTHFAIL"
expect "an auth failure -> TERMINAL too" 5

# THE REOPEN-TIME VETO, which is what keeps the promotional half of a real rate-limit
# notice from reading as an empty account. The reviewer saying when it comes back is the
# reviewer saying no human is needed, and it outranks its own sales copy.
SALESY="$(body_file \
  'Review limit reached.' \
  '' \
  'Next included review available in 44 minutes.' \
  'Out of credits? Add credits or upgrade your plan for unlimited reviews.')"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$SALESY"
expect "a reopen time vetoes terminal language" 1
says   "  ...and still reports the reopen time"   "44 minutes"

# A PLACEHOLDER IS NEVER TERMINAL. "Currently processing" is table 2c's tier and means the
# reviewer has not finished; promoting it to "a human must act" would ask for money over a
# reviewer that is mid-run.
NOTYET="$(body_file \
  'Currently processing new changes in this PR.' \
  'Add credits to your account for faster reviews.')"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$NOTYET"
expect "a not-yet-reviewed placeholder stays exit 1" 1

# A TERMINAL REFUSAL ANYWHERE PROMOTES THE ANSWER, whichever artifact the host streamed
# first. The first refusal recorded is first-wins; "the account is empty" is a fact about
# the PR however many placeholders precede it, so it is NOT.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$NOTYET"
add_comment coderabbitai "$TERMINAL"
expect "a terminal refusal behind a placeholder still -> 5" 5

# ...and the terminal table can never CLEAR anything, nor turn a review into a refusal.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "a real review is untouched by the new tier" 0

echo
echo "== the trap: the refusal CONTAINS the PR's head, and must still refuse =="
# Assert the property of the evidence first. If this ever stops holding, the test below
# is no longer testing anything and should fail loudly rather than pass vacuously.
assert "the refusal comment names the PR head verbatim" \
  "$(yes_if grep -Fq "$REFUSAL_HEAD" "$REFUSAL")"
assert "…so a head-range detector cannot tell them apart" \
  "$(yes_if bash -c 'grep -Fq "between" "$1" && grep -Fq "between" "$2"' _ "$REFUSAL" "$CLEAN")"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
expect "…and the refusal at its own head still refuses" 1

# The other side of the same ordering: refusal LANGUAGE quoted inside a fenced code block
# is a review discussing a refusal, not a refusal. Without this, a review of this very
# script's pattern table would classify as the thing it describes.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file \
  "Reviewed at $CLEAN_HEAD — one nit." \
  '<!-- walkthrough_start -->' \
  '```' \
  'review limit reached' \
  'rate limited by some-reviewer.example' \
  '```' \
  'Otherwise looks good.')"
expect "refusal language inside a code fence -> still a review" 0

echo "== the block reader against the HOST'S OWN RENDERER =="
# WHAT USED TO BE HERE, AND WHY IT WENT. A sweep over 400 generated bodies asserted that
# every line the STRICT rendering keeps is a line the STRIPPED one kept. That property is
# true BY CONSTRUCTION — strict is an intersection of two readings and stripped is their
# union, and an intersection is a subset of a union whatever either reading gets wrong — so
# the sweep could only ever confirm that the code still has a shape you can read in four
# lines. It survived every destructive mutant applied to it, which is the definition of an
# assertion that cannot fail, and it was green on the day a refusal spelled as three
# sibling bullets was removed by BOTH readings and therefore by their union too.
#
# THAT IS THE LESSON THIS SECTION REPLACES IT WITH. The union removes a line only when
# EVERY reading removes it; it is an AND-gate over the readings and it says nothing about
# the host. A mistake the readings SHARE is inherited by the union, so no property relating
# the readings to each other can bound the error — only the renderer being modelled can.
# `tests/fixtures/reviewer/host-rendering.txt` is github.com's own answer for each of these
# bodies, recorded by the script checked in beside it, and these are the two directions
# that cost something:
#
#   the host renders the refusal as READABLE PROSE  ->  the gate must refuse (rc 1)
#   the host puts the marker's characters ON THE PAGE  ->  the gate must not clear (rc 0)
#
# Neither is asserted in the other direction, and deliberately: a refusal the host puts in
# a code block is read here as a DISCUSSION of one, and a rendering that is too cautious
# costs a human glance. That asymmetry is also how this battery could pass vacuously — by
# refusing everything, or by clearing nothing — so the three counters at the end assert
# that it does not.
ORACLE="$FIXTURES/host-rendering.txt"
assert "the recorded host rendering exists" "$(yes_if test -s "$ORACLE")"
mkdir -p "$TMP/oracle"
awk -v dir="$TMP/oracle" '
  /^@@@ end$/ { close(f); f = ""; next }
  /^@@@ / { n++; f = sprintf("%s/%03d.body", dir, n); printf "" > f
            printf "%s %s %s %s\n", $2, $3, $4, f; next }
  f { print >> f }
' "$ORACLE" > "$TMP/oracle/index"
assert "…and it holds at least 100 recorded cases" \
  "$([ "$(wc -l < "$TMP/oracle/index")" -ge 100 ] && echo 0 || echo 1)"
assert "…in all three families" \
  "$(yes_if bash -c 'for f in refusal marker content; do grep -q "^$f " "$1" || exit 1; done' _ "$TMP/oracle/index")"

# The counters are the non-vacuity guard, asserted below rather than printed and forgotten.
o_quoted_kept=0; o_marker_cleared=0; o_glyph_cleared=0
while read -r family verdict name bodyfile; do
  case "$family" in
    refusal)
      setup "$REFUSAL_HEAD"; add_comment coderabbitai "$bodyfile" ;;
    marker)
      setup "$REFUSAL_HEAD"; add_comment coderabbitai "$bodyfile" ;;
    content)
      # A review object at the head whose body is the case, with the recorded refusal
      # beside it: the object clears only if its body is read as carrying a claim.
      setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
      add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$bodyfile" ;;
  esac
  write_pr
  rc=0; "$SCRIPT" 42 >/dev/null 2>&1 || rc=$?
  case "$family/$verdict" in
    refusal/prose)
      assert "host renders it as prose, so the gate refuses: $name" \
        "$([ "$rc" -eq 1 ] && echo 0 || echo 1)" ;;
    refusal/quoted|refusal/hidden)
      [ "$rc" -ne 1 ] && o_quoted_kept=$((o_quoted_kept + 1)) ;;
    marker/visible)
      assert "host shows the marker, so it cannot clear: $name" \
        "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" ;;
    marker/hidden)
      [ "$rc" -eq 0 ] && o_marker_cleared=$((o_marker_cleared + 1)) ;;
    content/blank)
      assert "host draws nothing, so it is not a claim: $name" \
        "$([ "$rc" -eq 1 ] && echo 0 || echo 1)" ;;
    content/glyph)
      [ "$rc" -eq 0 ] && o_glyph_cleared=$((o_glyph_cleared + 1)) ;;
  esac
done < "$TMP/oracle/index"

# THE THREE WAYS THE BATTERY ABOVE COULD BE GREEN AND WORTHLESS, each closed by a count.
# Refuse every body and all the `prose` rows pass; clear nothing and all the `visible` and
# `blank` rows pass. So the opposite answers have to appear too, on cases the host says
# they belong on.
assert "…and a refusal the host QUOTES is not read as one ($o_quoted_kept cases)" \
  "$([ "$o_quoted_kept" -ge 5 ] && echo 0 || echo 1)"
assert "…and the marker the host HIDES does clear ($o_marker_cleared cases)" \
  "$([ "$o_marker_cleared" -ge 5 ] && echo 0 || echo 1)"
assert "…and a body the host DRAWS is a claim ($o_glyph_cleared cases)" \
  "$([ "$o_glyph_cleared" -ge 5 ] && echo 0 || echo 1)"

# THE ONE STRUCTURAL FACT STILL WORTH ASSERTING, and it is asserted on a real case rather
# than as a theorem: the shipped script really does hold TWO readings, and on the body that
# defeated their union the wider one keeps the refusal while the narrower one drops it.
# Sliced out of the script, so it cannot drift from what ships.
RENDER="$TMP/render.sh"
{ printf '#!/usr/bin/env bash\nset -u\n'
  sed -n "/^FENCE_AWK='/,/^'\$/p" "$SCRIPT"
  sed -n '/^render_body() {/,/^}$/p' "$SCRIPT"
  printf 'render_body "$1" "$2" "$3"\n'
} > "$RENDER"
chmod +x "$RENDER"
assert "both renderings could be sliced out of the script" \
  "$(yes_if bash -c 'grep -q "function step(" "$1" && grep -q "render_body() {" "$1"' _ "$RENDER")"
SIBLING="$(body_file '- ```' '- Review limit reached' '- ```')"
"$RENDER" "$SIBLING" "$TMP/sib.stripped" "$TMP/sib.strict"
assert "the wider reading keeps a refusal spelled as sibling bullets" \
  "$(yes_if grep -Fq 'Review limit reached' "$TMP/sib.stripped")"
assert "…and the narrower one does not, so nothing clears on it" \
  "$(yes_if bash -c '! grep -Fq "Review limit reached" "$1"' _ "$TMP/sib.strict")"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
