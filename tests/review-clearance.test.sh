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
# to clear no longer does (`prose no longer clears anything`). Text matching is left with
# one job, detecting a refusal, where a false positive fails closed.
#
# `gh` and `jq` are replaced by stubs on PATH, so the whole matrix runs offline; the jq
# stub delegates to the real one unless a fixture asks it to break.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/review-clearance.sh"
SCRIPTS="$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$(cd "$(dirname "$0")" && pwd)/fixtures/reviewer"
CLEAN="$FIXTURES/clean-review.pr29.md"
REFUSAL="$FIXTURES/rate-limit-refusal.pr30.md"
ACK="$FIXTURES/ack-invocation.pr227.md"
ACK_PROSE="$FIXTURES/ack-prose.quoted-in-a-review.md"
SKIP="$FIXTURES/skip-notice.pr229.md"
SKIP_REVIEWED="$FIXTURES/skip-beside-review.pr215.md"
SKIP_REVIEWED_HEAD="3e83817779c0cc00b0e7e8f7cc352bd120670444"
CLEAN_HEAD="8f40f2ed565a31e141f5ae54a6935ad0810314c4"
REFUSAL_HEAD="88c106a8dd2b9ae14e001918022d4909e5357460"
OTHER_SHA="0123456789abcdef0123456789abcdef01234567"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/review-clearance.XXXXXX")" || {
  echo "review-clearance.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
# The mutants run from $TMP, and the script sources its sibling resolver
# (ai-bridge-v3/task-031) — without it they exit 2 before reaching their subject.
cp "$(dirname "$SCRIPT")/bundle-paths.sh" "$TMP/bundle-paths.sh"
pass=0; fail=0

command -v jq >/dev/null 2>&1 || { echo "jq is required to run this test"; exit 2; }
REAL_JQ="$(command -v jq)"
export FIX="$TMP/fix"
mkdir -p "$TMP/bin"

# --- stubs -------------------------------------------------------------------
cat > "$TMP/bin/gh" <<STUB
#!/usr/bin/env bash
REAL_JQ="$REAL_JQ"
STUB
cat >> "$TMP/bin/gh" <<'STUB'
# Minimal `gh` for review-clearance.sh. THREE sources, because the script reads three:
# the PR's own facts from $FIX/pr_json (`gh pr view`), the REVIEW OBJECTS from
# $FIX/reviews_json (only that endpoint carries a review's state AND its commit_id), and
# the ISSUE COMMENTS from $FIX/comments_json. The comments used to ride along inside
# `gh pr view --json comments`, which answers ONE page: a PR with more comments than that
# loses the refusal, and a lost refusal is a clearance. Both lists are paginated now, so
# both arrive through `gh api` and the stub has to tell them apart by path.
case "${1:-} ${2:-}" in
  "pr view")
    [ -f "$FIX/gh_broken" ] && { echo "could not resolve to a PullRequest" >&2; exit 1; }
    [ -f "$FIX/pr_json" ] || { echo "could not resolve to a PullRequest" >&2; exit 1; }
    cat "$FIX/pr_json"; exit 0 ;;
esac
# THE FOURTH SOURCE: review THREADS, which exist only in GraphQL. `isResolved` is on no
# REST endpoint — not a review, not a review comment, not the PR — so SCHEMA.md clause 9
# has to come through here. Routed FIRST, because `gh api graphql ...` also matches the
# `api` arm below and would otherwise be answered with the review list: valid JSON of the
# wrong shape, which the script reads as unreadable thread state and refuses at exit 2 —
# every clearing case in this file going red for a reason none of them is about.
if [ "${1:-} ${2:-}" = "api graphql" ]; then
  [ -f "$FIX/threads_broken" ] && { echo "gh: Bad gateway (HTTP 502)" >&2; exit 1; }
  [ -f "$FIX/threads_json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
  cat "$FIX/threads_json"; exit 0
fi
if [ "${1:-}" = "api" ]; then
  src="$FIX/reviews_json"; broken="$FIX/reviews_broken"
  case "${2:-}" in
    */issues/*/comments*) src="$FIX/comments_json"; broken="$FIX/comments_broken" ;;
  esac
  [ -f "$broken" ] && { echo "gh: Bad gateway (HTTP 502)" >&2; exit 1; }
  [ -f "$src" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
  filter=""; prev=""
  for a in "$@"; do
    [ "$prev" = "--jq" ] && { filter="$a"; break; }
    prev="$a"
  done
  if [ -n "$filter" ]; then "$REAL_JQ" -r "$filter" "$src"
  else cat "$src"; fi
  exit 0
fi
echo "stub: unhandled gh $*" >&2; exit 99
STUB
cat > "$TMP/bin/jq" <<STUB
#!/usr/bin/env bash
# The real jq, unless a case asks for a reader that cannot answer.
[ -f "\$FIX/jq_broken" ] && { echo "jq: broken pipe of a parser" >&2; exit 5; }
exec "$REAL_JQ" "\$@"
STUB
chmod +x "$TMP/bin/gh" "$TMP/bin/jq"
export PATH="$TMP/bin:$PATH"

# --- fixture builders ---------------------------------------------------------
HEAD=""; AUTHOR=""; REVIEWS=""; COMMENTS=""; THREADS=""; THREADS_MORE=""
MERGEABLE=""; MERGE_STATE=""; HEAD_DATE=""

setup() { # start from: a readable PR at <head> [pushed at <date>], authored by "dev"
  rm -rf "$FIX"; mkdir -p "$FIX"
  HEAD="${1:-$CLEAN_HEAD}"; AUTHOR="dev"; REVIEWS='[]'; COMMENTS='[]'
  # No commit date by default — the PR's commit list is read only to bound the exit-8 ask,
  # so every case written before that bound existed asks exactly what it was written to ask.
  HEAD_DATE="${2:-}"
  # A MERGEABLE/CLEAN PR is the default, so every case written before the mergeability
  # check existed keeps asking exactly the question it was written to ask. UNKNOWN holds
  # at exit 2, so a fixture that simply omitted these would refuse the whole file.
  MERGEABLE="MERGEABLE"; MERGE_STATE="CLEAN"
  # NO THREADS AND NO FURTHER PAGE is the default, so every case written before clause 9
  # existed keeps asking exactly the question it was written to ask.
  THREADS='[]'; THREADS_MORE=false
}

body_file() { # <text...> -> a file holding it, so every artifact arrives the same way
  local f; f="$(mktemp "$TMP/body.XXXXXX")"; printf '%s\n' "$@" > "$f"; printf '%s' "$f"
}

add_comment() { # <login> <body-file>
  COMMENTS="$("$REAL_JQ" --arg l "$1" --rawfile b "$2" \
              '. + [{user:{login:$l}, body:$b}]' <<<"$COMMENTS")"
}

# The same comment, with the host's own `created_at` on it — which is what says whether it
# was written at the current head when its body names no commit.
add_comment_at() { # <login> <created_at> <body-file>
  COMMENTS="$("$REAL_JQ" --arg l "$1" --arg t "$2" --rawfile b "$3" \
              '. + [{user:{login:$l}, body:$b, created_at:$t}]' <<<"$COMMENTS")"
}

# The host reports no author at all for an artifact from a deleted account, and `gh` passes
# that through as `null`. It is not a login the script can compare against anything.
add_null_comment() { # <body-file>
  COMMENTS="$("$REAL_JQ" --rawfile b "$1" '. + [{user:null, body:$b}]' <<<"$COMMENTS")"
}

# A review object as the REST API publishes one: a state, a commit_id and a body. The
# first two are what clears it now; the body is read only for a refusal.
add_review() { # <login> <state> <commit_id> <body-file>
  REVIEWS="$("$REAL_JQ" --arg l "$1" --arg s "$2" --arg c "$3" --rawfile b "$4" \
             '. + [{user:{login:$l}, state:$s, commit_id:$c, body:$b}]' <<<"$REVIEWS")"
}

# A review thread as GraphQL publishes one. `line` is a number or null (a file-level
# thread), `author` may be null (a deleted account) — both shapes are real and both are
# driven below.
add_thread() { # <isResolved> <path> <line|null> <login|null> <url> <first-line-of-body>
  THREADS="$("$REAL_JQ" --argjson r "$1" --arg p "$2" --argjson l "$3" \
             --arg who "$4" --arg u "$5" --arg b "$6" \
    '. + [{ isResolved:$r, path:$p, line:$l,
            comments:{nodes:[{ author:(if $who=="" then null else {login:$who} end),
                               url:$u, body:$b }]} }]' <<<"$THREADS")"
}

write_pr() {
  "$REAL_JQ" -n --arg h "$HEAD" --arg a "$AUTHOR" \
              --arg m "$MERGEABLE" --arg s "$MERGE_STATE" --arg hd "$HEAD_DATE" \
    '{url:"https://github.com/acme/widgets/pull/42", number:42, headRefOid:$h,
      author:{login:$a}, mergeable:$m, mergeStateStatus:$s,
      commits:(if $hd == "" then [] else [{oid:$h, committedDate:$hd}] end)}' > "$FIX/pr_json"
  printf '%s' "$REVIEWS"  > "$FIX/reviews_json"
  printf '%s' "$COMMENTS" > "$FIX/comments_json"
  "$REAL_JQ" -n --argjson t "$THREADS" --argjson more "$THREADS_MORE" \
    '{data:{repository:{pullRequest:{reviewThreads:
       {pageInfo:{hasNextPage:$more}, nodes:$t}}}}}' > "$FIX/threads_json"
}

# A WHOLE PR AS THE HOST SERVED IT, rather than assembled from the builders above: the
# three endpoints come out of one recorded file (tests/fixtures/reviewer/*.api.json). No
# threads, because clause 9 is asked only on the clearing path and these do not clear.
load_recorded() { # <fixture.api.json>
  rm -rf "$FIX"; mkdir -p "$FIX"
  "$REAL_JQ" '.pr'       "$1" > "$FIX/pr_json"
  "$REAL_JQ" '.reviews'  "$1" > "$FIX/reviews_json"
  "$REAL_JQ" '.comments' "$1" > "$FIX/comments_json"
  "$REAL_JQ" -n '{data:{repository:{pullRequest:{reviewThreads:
                  {pageInfo:{hasNextPage:false}, nodes:[]}}}}}' > "$FIX/threads_json"
}

# --- assertions ---------------------------------------------------------------
expect() { # <name> <expected-rc> [args to the script...]
  write_pr
  local name="$1" want="$2"; shift 2
  local out rc
  out="$("$SCRIPT" 42 "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq "$want" ]; then
    printf '  PASS  %-58s (rc=%s)\n' "$name" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-58s expected rc=%s got rc=%s\n' "$name" "$want" "$rc"
    printf '        output: %s\n' "$(head -3 <<<"$out" | tr '\n' '|')"
    fail=$((fail+1))
  fi
  LAST_OUT="$out"
}

# The same assertion over a load_recorded() fixture: no write_pr, and the PR's own number.
expect_recorded() { # <name> <expected-rc> <pr-number> [args to the script...]
  local name="$1" want="$2" num="$3"; shift 3
  local out rc
  out="$("$SCRIPT" "$num" "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq "$want" ]; then
    printf '  PASS  %-58s (rc=%s)\n' "$name" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-58s expected rc=%s got rc=%s\n' "$name" "$want" "$rc"
    printf '        output: %s\n' "$(head -3 <<<"$out" | tr '\n' '|')"
    fail=$((fail+1))
  fi
  LAST_OUT="$out"
}

says() { # <name> <substring> — against the previous expect()'s output
  if grep -Fq "$2" <<<"$LAST_OUT"; then
    printf '  PASS  %-58s\n' "$1"; pass=$((pass+1))
  else
    printf '  FAIL  %-58s missing %s in: %s\n' "$1" "$2" "$(head -2 <<<"$LAST_OUT" | tr '\n' '|')"
    fail=$((fail+1))
  fi
}

assert() { # <name> <rc-of-a-condition>
  if [ "$2" = 0 ]; then printf '  PASS  %-58s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %-58s\n' "$1"; fail=$((fail+1)); fi
}
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }

EMPTY_BODY="$(body_file '')"

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

echo
echo "== an UNBALANCED fence must fail closed, not blank the body =="
# The bypass this section pins: strip_fences used to toggle on every marker with no END
# check, so an ODD count left everything after the marker "inside a fence" and the
# stripped body came back empty — no refusal matched, and the raw text still named the
# head, so the recorded refusal CLEARED. One character, typed into a comment.
#
# The control is the assertion above this line: with BALANCED fences the strip still
# happens, so these cases fail for the unbalance and not because fencing stopped working.
fenced_refusal="$TMP/refusal-one-fence.md"
{ printf '```\n'; cat "$REFUSAL"; } > "$fenced_refusal"
assert "the fenced copy still names the head verbatim (so it COULD clear)" \
  "$(yes_if grep -Fq "$REFUSAL_HEAD" "$fenced_refusal")"
assert "…and carries exactly one fence marker" \
  "$([ "$(grep -c '^```' "$fenced_refusal")" -eq 1 ] && echo 0 || echo 1)"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$fenced_refusal"
expect "one prepended fence on the recorded refusal -> still refuses" 1
says   "  ...still quoting the reviewer's own words" "Review limit reached"

trailing_refusal="$TMP/refusal-trailing-fence.md"
{ cat "$REFUSAL"; printf '```\n'; } > "$trailing_refusal"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$trailing_refusal"
expect "an unclosed fence AFTER the refusal -> still refuses" 1

setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '~~~' 'Review limit reached.' "at $REFUSAL_HEAD")"
expect "an unbalanced tilde fence refuses just the same" 1

# The opening marker's type is carried, so a backtick fence inside a tilde block is
# content rather than a close — otherwise a nested pair drifts the count odd and the case
# above fires on an ordinary review that quotes one fence style inside another.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file \
  "Reviewed $CLEAN_HEAD." \
  '<!-- walkthrough_start -->' \
  '~~~' \
  '```' \
  'review limit reached' \
  '```' \
  '~~~' \
  'No further comments.')"
expect "a backtick pair nested in a tilde block stays balanced -> review" 0
# The same rule where getting it wrong is visible: with the UNCONDITIONAL sentinel between
# the nested markers, a ``` that closed a ~~~ would leave the sentinel outside every block
# (rc=1). The case above cannot show that, because the prose tier it uses is outranked by
# the review marker in the same body whichever side of the fence it lands on.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file \
  "Reviewed $CLEAN_HEAD." \
  '<!-- walkthrough_start -->' \
  '~~~' \
  '```' \
  'rate limited by coderabbit.ai' \
  '```' \
  '~~~')"
expect "…and the opener's TYPE is what closes it, so the sentinel stays quoted" 0

# ...and the CLEARING side of an unbalanced body is not "read it raw", which is what the
# refusal side does. A body whose fences do not balance cannot be rendered, so it
# evidences nothing: the strict rendering is empty and the marker in it is unreachable.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '```' '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD.")"
expect "an unbalanced fence around a review marker -> evidences nothing" 4
# ...and with the marker BEFORE the stray fence, which is the case a stripper that merely
# drops the unterminated tail still clears. "Empty" is the answer, not "everything outside
# the fence": a body that cannot be rendered is a body nothing can be read out of.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." '```' 'and then nothing closes it')"
expect "…and with the marker BEFORE the stray fence, still nothing" 4

echo
echo "== the two renderings must agree on what a FENCE is =="
# A FOURTH DOOR INTO THE SAME BYPASS, and this one needed no unbalanced anything.
# `strip_fences` (the refusal side) stripped any leading whitespace before testing for a
# fence; `strict_body` (the clearing side) treated a line indented four spaces or a tab as
# an INDENTED CODE BLOCK and therefore not a fence. So an INDENTED ``` opened a fence on
# one side and nothing on the other: the unconditional rate-limit sentinel between two such
# markers disappeared from the text the refusal tables read, while the review marker outside
# them survived on the side that clears — and the file's own stated asymmetry (strict is a
# SUBSET of stripped) ran backwards.
#
# The host renders `    ``` ` as three literal backticks, not as a fence, so a human reading
# these bodies SEES the refusal. Each case below hides the sentinel from the refusal tables
# in exactly that way and leaves a review marker in the clear; each was rc=0 before.
marker_and_head=( '<!-- walkthrough_start -->' )
hidden_sentinel() { # <indent-prefix> — the sentinel wrapped in a fence indented by it
  local p="$1"
  body_file "${marker_and_head[@]}" "Reviewed $CLEAN_HEAD." \
    "$p"'```' "$p"'rate limited by coderabbit.ai' "$p"'```'
}
setup "$CLEAN_HEAD"; add_comment coderabbitai "$(hidden_sentinel '    ')"
expect "a FOUR-SPACE indented fence cannot hide the sentinel" 1
says   "  ...and it is the unconditional tier that fired" "DECLINED to review"
setup "$CLEAN_HEAD"; add_comment coderabbitai "$(hidden_sentinel "$(printf '\t')")"
expect "…nor a TAB-indented one" 1
setup "$CLEAN_HEAD"; add_comment coderabbitai "$(hidden_sentinel '>     ')"
expect "…nor a BLOCKQUOTED one indented inside the quote" 1
# The NOT_YET tier is unconditional for the same reason and was reachable the same way.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '    ```' '    Currently processing new changes in this PR.' '    ```')"
expect "…and an indented fence cannot hide the placeholder either" 1

# THE CONTROL, and it is what stops the four above from passing on a script that simply
# stopped stripping fences: the same indentation, with NO refusal in it, still clears.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '    ```' '    make test' '    ```')"
expect "…while the same indented block with no refusal in it still clears" 0

# THE BOUNDARY, asserted rather than left to be rediscovered as a bug. Up to THREE spaces
# is a real fence to the host, and a fenced refusal has always been read here as a
# DISCUSSION of one (the fenced-refusal case above) — so these two stay rc=0 by design,
# and they are the reason the fix is "agree with the renderer", not "never strip".
setup "$CLEAN_HEAD"; add_comment coderabbitai "$(hidden_sentinel '   ')"
expect "a THREE-space fence is a real fence, so its content is quotation" 0
setup "$CLEAN_HEAD"; add_comment coderabbitai "$(hidden_sentinel '  > ')"
expect "…as is a fence inside a blockquote indented at most three" 0

echo
echo "== …and agreeing with each other is not agreeing with the HOST =="
# THE ROUND AFTER THE ONE ABOVE. The two renderings were made to agree, and the rule they
# agreed on still was not the host's, three ways — each of which strips text a human can
# read, and each of which therefore fails OPEN. Every case here was rc=0 before.
TAB="$(printf '\t')"

# 1. BLOCKQUOTE CONTAINMENT. A fence opens inside the blockquote it is written in, and the
# host closes it where that quote ends: an opener at depth 1 is not paired with a closer at
# depth 0. This is the reviewer's NATIVE IDIOM rather than a construction — its notices
# arrive inside a `> [!WARNING]` blockquote — so the payload is the RECORDED refusal,
# unaltered, and the only edit is the wrapper.
quoted_fence_refusal="$TMP/refusal-quote-opened-fence.md"
{ printf '<!-- walkthrough_start -->\nReviewed %s.\n> ```\n' "$REFUSAL_HEAD"
  cat "$REFUSAL"; printf '```\n'; } > "$quoted_fence_refusal"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$quoted_fence_refusal"
expect "a fence OPENED inside a blockquote does not close outside it" 1
says   "  ...quoting the reviewer's own words" "Review limit reached"
# THE CONTROL: the identical body with both markers at the same depth is a real fence, so
# its content is quotation and the marker outside it clears — the boundary above, again.
same_depth_fence="$TMP/refusal-depth0-fence.md"
{ printf '<!-- walkthrough_start -->\nReviewed %s.\n```\n' "$REFUSAL_HEAD"
  cat "$REFUSAL"; printf '```\n'; } > "$same_depth_fence"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$same_depth_fence"
expect "…while both markers at the same depth ARE a pair, so that clears" 0
# The other half of the same rule, and the half the case above cannot see: the block ENDS
# where the quote ends, so what follows is ordinary text rather than swallowed. Without
# that, this body has an unclosed fence and evidences nothing (rc=4).
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '> ```' '> make test' \
  '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD.")"
expect "…and the quote ending ENDS the block, rather than swallowing the rest" 0
# The third direction of the same rule, and the only one that shows the depths being
# COMPARED rather than just ordered: inside a code block there is no block structure at
# all, so a `> ```' DEEPER than the opener is literal content and closes nothing. Read as
# a close, the real closer below it opens a new block, the body is unbalanced, and the
# sentinel this one quotes leaves the fence.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '```' 'rate limited by coderabbit.ai' '> ```' '```')"
expect "…and a closer DEEPER than its opener is content, not a close" 0

# 2. TABS ARE COLUMNS. The host expands a tab to the next four-column stop, so 1-3 spaces
# then a tab is indented code. This one reaches ROUTE B, which outranks every refusal
# tier: a comment that merely QUOTES the trailer format validated as a real verdict.
quoted_trailer() { # <indent> — the verdict trailer, indented by it
  body_file 'Quoting the format for the docs:' \
    "$1"'<!-- okf-verdict v1' "$1"'verdict: pass' "$1"'reviewer: qa' \
    "$1""head_sha: $CLEAN_HEAD" "$1"'-->'
}
setup "$CLEAN_HEAD"; add_comment some-new-reviewer "$(quoted_trailer "   $TAB")"
expect "3 spaces + a TAB is column 4, so a quoted trailer stays quoted" 4 \
  --reviewer some-new-reviewer
setup "$CLEAN_HEAD"; add_comment some-new-reviewer "$(quoted_trailer '    ')"
expect "…the four-space control, which was already literal" 4 --reviewer some-new-reviewer
# THE CONTROL that keeps this about INDENTATION: unindented, the same block validates.
setup "$CLEAN_HEAD"; add_comment some-new-reviewer "$(quoted_trailer '')"
expect "…while the same trailer unindented is a real verdict" 0 --reviewer some-new-reviewer
# And the tab that the blockquote marker eats: one column of it belongs to the marker, so
# `>` TAB SPACE is three columns of indentation (a fence) and `>` TAB SPACE SPACE is four
# (literal text, and the sentinel in it must be read).
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  ">$TAB "'```' ">$TAB "'rate limited by coderabbit.ai' ">$TAB "'```')"
expect "a blockquote marker eats ONE column of the tab after it" 0
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  ">$TAB  "'```' ">$TAB  "'rate limited by coderabbit.ai' ">$TAB  "'```')"
expect "…so one more space is column 4, and the sentinel is literal text" 1
# The other consumer of the same measurement: four columns in, a `>` is not a quote marker
# at all, it is a literal `>` inside an indented code block — so a review marker written
# there is quoted text and evidences nothing.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '    > <!-- walkthrough_start -->' \
  "    > Reviewed $CLEAN_HEAD.")"
expect "a > four columns in is literal text, not a blockquote marker" 4
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '> <!-- walkthrough_start -->' \
  "> Reviewed $CLEAN_HEAD.")"
expect "…while the same lines merely QUOTED are a review, and clear" 0

# 3. THE CLOSING MARKER IS NOT JUST A MARKER. A closer may be no shorter than its opener
# and may carry no info string; reading either as a close also turns an odd number of
# markers into an even one, which is how it slipped past the unbalanced-fence net too.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '````' 'rate limited by coderabbit.ai' '```')"
expect "a four-backtick fence is not closed by three" 1
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '```' 'rate limited by coderabbit.ai' '```js')"
expect "…nor by a closing fence carrying an info string" 1
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '```a`b' 'rate limited by coderabbit.ai' '```')"
expect "…and a backtick opener whose info string holds a backtick opens nothing" 1
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '``' 'rate limited by coderabbit.ai' '``')"
expect "…and two backticks are not a fence at all" 1
# THE CONTROLS, so none of the four passes on a script that stopped pairing fences: a
# longer closer, and an opener that legitimately carries an info string, both still pair.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '````' 'rate limited by coderabbit.ai' '`````')"
expect "…while a LONGER closer does close it, so that stays quotation" 0
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '```js' 'rate limited by coderabbit.ai' '```')"
expect "…as does an OPENER carrying an info string, which is legal" 0

echo
echo "== the CONTAINERS a fence lives in, which the machine did not model =="
# THE SAME DEFECT A SIXTH TIME, and this is the round it stopped being a list. The fence
# rules were exact for what they modelled and modelled no CONTAINERS, so a construct that
# changes what ``` MEANS put the recorded refusal back behind a fence the host does not
# see. Inside a raw-HTML block the content is HTML: ``` is three backticks a reader can
# see, and the refusal between them is on the page. `<details>`/`<summary>` is the shape
# the recorded fixture is itself built from, so this is the vendor's idiom, not a
# construction. Each case is answered by the SECOND reading of the block structure, and
# the refusal side takes the union of the two.
for tag in details pre div table section blockquote-ish-unknown-tag; do
  setup "$CLEAN_HEAD"
  add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' \
    "Reviewed $CLEAN_HEAD." '' "<$tag>" '```' 'rate limited by coderabbit.ai' '```' "</$tag>")"
  expect "a refusal inside a <$tag> block -> refuse, it is on the page" 1
done
says   "  ...and it is the unconditional tier that fired" "DECLINED to review"
# …and the whole recorded refusal, unaltered, inside the vendor's own <details> idiom.
setup "$REFUSAL_HEAD"
{ printf '<!-- walkthrough_start -->\nReviewed %s.\n\n<details>\n<summary>d</summary>\n```\n' \
    "$REFUSAL_HEAD"; cat "$REFUSAL"; printf '```\n</details>\n'; } > "$TMP/details.md"
add_comment coderabbitai "$TMP/details.md"
expect "the RECORDED refusal inside <details> -> refuse" 1
says   "  ...quoting the reviewer's own words" "Review limit reached"
# THE CONTROL, and it is the one that keeps this from being "never strip a fence": with no
# HTML block around it the same three lines ARE a fenced quotation and still clear.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '' '```' 'rate limited by coderabbit.ai' '```')"
expect "…while the same fence with no HTML block around it is quotation" 0
# …and a raw-HTML block ends at a blank line, so a fence after one is a fence again.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '' '<div>' 'x' '' '```' 'rate limited by coderabbit.ai' '```')"
expect "…and a blank line ends the HTML block, so the next fence quotes again" 0

# A LIST ITEM IS A CONTAINER TOO: the fence dies with the item. The host closes the block
# at the end of the item, so the text after it is a paragraph a human reads; a machine that
# carries the fence past the item's end pairs it with a LATER marker and swallows that
# paragraph — and an odd number of markers becomes even, which slips the unbalanced net.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '' '- item' '  ```' '  x' '' 'rate limited by coderabbit.ai' '' '  ```')"
expect "a fence closed by the END of its list item -> refuse" 1
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '' '- item' '  ```' '  rate limited by coderabbit.ai' '  ```')"
expect "…while a fence that opens and closes INSIDE the item is quotation" 0
# The opener may be behind the marker itself, which used to be no fence at all — so a
# review marker inside a block the host renders as CODE was read as the vendor's claim.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '- ```' '  <!-- walkthrough_start -->' \
  "  Reviewed $CLEAN_HEAD." '  ```')"
expect "a marker inside a fence opened BEHIND a list marker -> not evidence" 4
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '1. ```' '   <!-- walkthrough_start -->' \
  "   Reviewed $CLEAN_HEAD." '   ```')"
expect "…and behind an ORDERED list marker too" 4

echo
echo "== an inline code SPAN is text a human reads, so it is not evidence =="
# THIS ROUND'S REVIEW DEMONSTRATED IT ON ITS OWN DRAFT: spelling the vendor's marker
# between backticks to describe it cleared route C, and the verdict had to be mangled
# before it could be posted. Two things stop it, because one construct is invisible to
# each: the table rows are anchored to a WHOLE line, which a span inside a line breaks;
# and the strict rendering drops lines inside a span that opened on an earlier line, which
# an anchor cannot see.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file 'The marker `<!-- walkthrough_start -->` is emitted' \
  "by the vendor. Reviewed $CLEAN_HEAD.")"
expect "the marker inside a span, in a sentence -> not evidence" 4
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '`<!-- walkthrough_start -->`' "Reviewed $CLEAN_HEAD.")"
expect "…nor a span holding nothing else, alone on its line" 4
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file 'the marker is `' '<!-- walkthrough_start -->' \
  '` as emitted' "Reviewed $CLEAN_HEAD.")"
expect "…nor a marker on its own line inside a MULTI-LINE span" 4
# THE CONTROLS: the marker as the vendor actually emits it, alone on its line, still
# clears — including inside the blockquote its notices arrive in.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD.")"
expect "…while the marker alone on its line IS the vendor's claim" 0
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '> <!-- walkthrough_start -->' "> Reviewed $CLEAN_HEAD.")"
expect "…and so is one inside the blockquote its notices arrive in" 0

echo
echo "== the six branches a per-branch mutant sweep found unguarded =="
# EACH OF THESE WAS A MUTANT THAT SURVIVED, and a survivor is the sweep working: removing
# the branch left both suites green, so nothing here was asserting it. Two are gaps that
# would clear an unreviewed PR, two are OVER-correction guards (the refusal side may not
# start eating quotations), and two are the union/intersection halves themselves.
#
# 1. A LIST MARKER'S WIDTH. `1.` and `1)` are two columns, so a fence behind one opens at a
#    different container column than a fence behind `-`. Spelled with TILDES on purpose: a
#    backtick version is caught by the code-span parity rule instead, which would make this
#    a test of the wrong branch.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '1. ~~~' '   <!-- walkthrough_start -->' \
  "   Reviewed $CLEAN_HEAD." '1. ~~~')"
expect "an ORDERED marker is as wide as it is written -> not evidence" 4

# 2. A LIST MARKER IS NOT A QUOTE LEVEL. Counting it as one would close a fence at the first
#    line that is not itself a marker — so a fenced quotation inside one item would leak its
#    contents to the refusal tables. An OVER-correction guard: this body must still clear.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '- ```' '  rate limited by coderabbit.ai' '  ```' \
  '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD.")"
expect "a fence opened BEHIND a marker and closed in the item is quotation" 0

# 3. A LIST ITEM ENDS. If it never did, every later top-level fence would be treated as
#    living in the last item seen and closed by the first line at column 0 — turning a
#    perfectly ordinary quotation back into a refusal. The other OVER-correction guard.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '- item' '' '<!-- walkthrough_start -->' \
  "Reviewed $CLEAN_HEAD." '' '```' 'rate limited by coderabbit.ai' '```')"
expect "a quotation AFTER a list ends is still a quotation" 0

# 4. A CLOSING TAG OPENS A RAW-HTML BLOCK TOO — CommonMark counts `</x>` as a block start,
#    and reading it as ordinary text puts the refusal back behind a fence the host does not
#    render as one.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '' '</div>' '```' 'rate limited by coderabbit.ai' '```')"
expect "a CLOSING tag opens a raw-HTML block -> refuse" 1

# 5. EITHER READING BEING UNBALANCED IS ENOUGH. Reading B closes the fence at the end of the
#    list item, which leaves its closing marker to open a block nothing closes — so B cannot
#    read this body even though A can. An unreadable body clears NOTHING; taking only A's
#    word for it clears this one.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD." \
  '' '- item' '  ```' '  x' 'y' '  ```')"
expect "reading B unbalanced, reading A not -> clears nothing" 4

# 6. THE CLEARING SIDE IS THE INTERSECTION, and this is the shape that proves it is not just
#    reading A with extra steps. Two raw-HTML blocks each swallow one fence marker, so the
#    two readings PAIR THE REMAINING MARKERS DIFFERENTLY: the marker and the head sit
#    OUTSIDE every block in reading A and INSIDE one in reading B. The host agrees with B —
#    the first block ends at its blank line, so the next ``` really does open a fence and
#    the marker under it is literal text a human reads.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<div>' '```' '' '```' '<!-- walkthrough_start -->' \
  "Reviewed $CLEAN_HEAD." '```' '<div>' '```' '' '```' 'z' '```')"
expect "a marker only reading A calls markup -> not evidence" 4

echo
echo "== CRLF: the host does not see the carriage return, and neither may this =="
# A BODY FROM A WINDOWS CLIENT ARRIVES WITH \r ON EVERY LINE, and awk's record is split on
# \n alone, so the \r is the last character of every line the machine reads. Two rules
# nearly regressed on it in this round's rewrite, both toward FALSE REFUSALS rather than
# false clearances — an over-correction is still a defect, and this is where it hides.
# `\r` is whitespace to a POSIX character class and is not `[ \t]`, which is the difference.
crlf() { local f; f="$(mktemp "$TMP/crlf.XXXXXX")"; printf "$1" > "$f"; printf '%s' "$f"; }
setup "$CLEAN_HEAD"
add_comment coderabbitai \
  "$(crlf "<!-- walkthrough_start -->\r\nReviewed $CLEAN_HEAD.\r\n\r\n\`\`\`\r\nrate limited by coderabbit.ai\r\n\`\`\`\r\n")"
expect "a CRLF fence PAIRS, so its refusal is quotation" 0
setup "$CLEAN_HEAD"
add_comment coderabbitai \
  "$(crlf "<!-- walkthrough_start -->\r\nReviewed $CLEAN_HEAD.\r\n\r\n<div>\r\nx\r\n\r\n\`\`\`\r\nrate limited by coderabbit.ai\r\n\`\`\`\r\n")"
expect "…and a CRLF blank line ENDS a raw-HTML block" 0
# The other direction is unchanged: CRLF does not weaken any of it.
setup "$CLEAN_HEAD"
add_comment coderabbitai \
  "$(crlf "<!-- walkthrough_start -->\r\nReviewed $CLEAN_HEAD.\r\n\r\n<details>\r\n\`\`\`\r\nrate limited by coderabbit.ai\r\n\`\`\`\r\n</details>\r\n")"
expect "…while a CRLF refusal inside <details> still refuses" 1
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(crlf "<!-- walkthrough_start -->\r\nReviewed $CLEAN_HEAD.\r\n")"
expect "…and a CRLF clean review still clears" 0

echo
echo "== the union is an AND-gate, and both readings were wrong the same way =="
# THE ROUTE THAT FALSIFIED THE WHOLE CONSTRUCTION. The refusal side keeps a line either
# reading keeps, which was argued to make a crude reading cost at most a FALSE refusal.
# It does not: the readings can be wrong together, and then their union is wrong too.
#
#     - ```
#     - Review limit reached...
#     - ```
#
# Reading A does not model list items at all, so its fence stays open. Reading B did model
# them but ended an item only on a DEDENT, and a sibling marker does not dedent — so B
# agreed, the union agreed, and the refusal was gone. GitHub closes the fence at the end of
# the item and renders the middle line as an ordinary bullet, which `host-rendering.txt`
# records. Every bullet spelling and both ways an item ends:
SIB_REFUSAL='Review limit reached. Next included review available in 44 minutes.'
for m in '-:a dash' '*:a star' '+:a plus' '1.:an ordered marker' '10.:a two-digit marker'; do
  setup "$REFUSAL_HEAD"
  add_comment coderabbitai "$(body_file "${m%%:*} \`\`\`" "${m%%:*} $SIB_REFUSAL" "${m%%:*} \`\`\`")"
  expect "a refusal in sibling list items -> refusal (${m#*:})" 1
done
# …and the same shape reaching a CLEARANCE, which is what it cost: the refusal vanished, so
# a contentless approval at that head had nothing to lose to.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '- ```' "- $SIB_REFUSAL" '- ```')"
add_review coderabbitai APPROVED "$REFUSAL_HEAD" "$EMPTY_BODY"
expect "…so a held approval no longer clears past it" 1
# The list item also ends by DEDENT, which is the branch that was already there — asserted
# so removing either one is red, not just the new one.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '- ```' '  quoted' "$SIB_REFUSAL")"
expect "…and a dedent out of the item ends it too" 1
# A blank line does not end a list, so the fence still dies at the next marker.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '- ```' '' "- $SIB_REFUSAL" '- ```')"
expect "…and a blank line between the bullets changes nothing" 1
# THE TWO OVER-CORRECTION CONTROLS, because a rule that ends every list item ends the ones
# the host does not. A DEEPER marker opens a nested item and ends nothing, and a plain
# continuation line is still inside the fence — the host quotes both, so this file reads
# both as a discussion of a refusal rather than as one.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '- ```' "  - $SIB_REFUSAL" '  ```')"
expect "a DEEPER marker nests rather than ending the item -> quoted" 4
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '- ```' "  $SIB_REFUSAL" '  ```')"
expect "…and a continuation line is still inside the fence -> quoted" 4
# …and the top-level fence this file has always read as a quotation is untouched.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '```' "$SIB_REFUSAL" '```')"
expect "…and a plain fenced refusal is still a discussion of one" 4

echo
echo "== a raw-HTML block ends where its container does =="
# The other block that outlives its container. `<details>` inside a blockquote opened a
# raw-HTML block that ended only at a blank line, so it ran to the end of the body — and a
# raw-HTML block is the one state in reading B that makes it KEEP a line reading A drops,
# which is the direction that lets something clear.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '> <details>' '- ```' "- $SIB_REFUSAL" '- ```')"
expect "an HTML block opened in a quote does not outlive the quote" 1
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '- <details>' '- ```' "- $SIB_REFUSAL" '- ```')"
expect "…nor one opened in a list item outlive the item" 1
# The control: with no container to leave, it still ends at a blank line and nowhere else.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '<details>' '```' "$SIB_REFUSAL" '```' '</details>')"
expect "…and inside one that never ends, the fence is still literal HTML" 1

echo
echo "== the over-correction guards: a container the host does NOT end =="
# EVERY RULE ADDED THIS ROUND ENDS SOMETHING EARLIER, and a rule that ends a container the
# host keeps open turns a quotation into a refusal. That is not a merge, so the battery
# above does not assert on it — which is exactly why these cases are here by name. Each
# body is one the host puts in a code block (recorded in `host-rendering.txt` as `quoted`),
# so the answer must be 4, "an artifact carrying no evidence", and not 1.
#
# THEY ARE ALSO WHAT READING B'S TIGHTENING RULES BUY, and the honest accounting is worth
# stating: reading B keeping a line only reaches the CLEARING side when reading A keeps it
# too, and A already reads every fence these rules reveal. So bounding a raw-HTML block
# closes no route — it removes false refusals, and these assert that it does.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '- ```' '' "  $SIB_REFUSAL" '  ```')"
expect "a blank line does not end a list item -> still quoted" 4
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '> <details>' '```' "$SIB_REFUSAL" '```')"
expect "…leaving the quote ends its HTML block, so the fence is a fence" 4
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '- <details>' '- ```' "  $SIB_REFUSAL" '  ```')"
expect "…and leaving the list item ends its HTML block too" 4
# The control for all three: the same HTML block with nothing to leave still swallows the
# fence, so the words really are on the page and this is a refusal.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file '<details>' '```' "$SIB_REFUSAL" '```')"
expect "…while an HTML block nobody leaves still makes the fence literal" 1

echo
echo "== what RENDERS is the host's answer, including where it surprises =="
# Three constructs where the rule "remove the markup, require a letter" needs the host to
# say where markup ends, and got a different answer than the specification would give.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$(body_file '<https://example.com/a>')"
expect "an autolink is a claim: the page shows the URL" 0
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$(body_file '<![CDATA[a > b]]>')"
expect "…and so is what the host leaves after a CDATA it does not honour" 0
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$(body_file '<!-- a > b -->')"
expect "…while a comment really does run to its own terminator" 1
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$(body_file '[][r]' '' '[r]: /x')"
expect "…and a reference link with an empty label draws nothing" 1
# A reference definition is SKIPPED, scanner state and all, and reasoning says that is a
# bug: the line could also open a multi-line construct, which would then never close. The
# host says otherwise — given `   [a]: /b<!--` the destination swallows the opener and the
# following lines are VISIBLE — so skipping is what the host does, and preserving the state
# would read a body the host draws as a blank page. Recorded as `c-link-ref-def-swallows-open`.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" \
  "$(body_file '   [a]: /b<!--' 'lgtm' '-->')"
expect "…and the destination swallows an opener, as it does on the host" 0

echo "== a run of hex is not a commit unless the whole token is one =="
# `refusal_concerns_head` demotes a refusal that names some OTHER commit, so that a PR
# refused once can recover. It read any 7-40 character hex run as a commit — and the
# reviewer stamps its own refusals with a UUID run id, whose fields are hex runs of 8 and
# 12. The recorded fixture carries one. So any refusal with a run id read as being about
# another commit and was dropped before it was weighed.
UUID_LINE='**Run ID**: `f4981ca2-1bc7-4edf-9bb4-fd2f74e3693a`'
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file 'Currently processing new changes in this PR.' '' "$UUID_LINE")"
add_review coderabbitai APPROVED "$REFUSAL_HEAD" "$EMPTY_BODY"
expect "a UUID does not make a refusal be about another commit" 1
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file 'Review limit reached.' '' "$UUID_LINE")"
add_review coderabbitai APPROVED "$REFUSAL_HEAD" "$EMPTY_BODY"
expect "…for the declined tier as well as the placeholder" 1
# THE CONTROL, and it is the property the demotion exists for: a refusal that really does
# name another commit still loses to an approval at this head, so a PR can recover.
setup "$REFUSAL_HEAD"
add_comment coderabbitai "$(body_file 'Review limit reached.' "Reviewing $OTHER_SHA." )"
add_review coderabbitai APPROVED "$REFUSAL_HEAD" "$EMPTY_BODY"
expect "…while a refusal naming a REAL other commit still loses" 0
# …and the same tokenisation is route C's pin, where losing a token costs a clearance and
# never grants one. A head spelled as one field of a longer identifier is not the head.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "run-$CLEAN_HEAD-2")"
expect "…and a head embedded in a longer identifier does not pin route C" 4
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "reviewed $CLEAN_HEAD.")"
expect "…while the head as a token of its own still does" 0

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

echo "== prose no longer clears anything =="
# ROUTE 3 OF THE FOURTH REVIEW ROUND. The evidence table used to hold PROSE, matched as an
# unanchored substring: `i (have )?reviewed`, `(lgtm|looks good to me)`,
# `(changes requested|requesting changes)`, `(no )?actionable comments`. That is the exact
# defect this same file had already fixed for the verdict trailer. Quoted approvals
# cleared, NEGATED sentences matched, and because refusal prose lost to it, a quota
# refusal carrying one such phrase cleared. Every row of prose is gone; what is left is
# the vendor's own machine-emitted HTML marker.
while IFS= read -r prose; do
  [ -n "$prose" ] || continue
  setup "$CLEAN_HEAD"; add_comment coderabbitai "$(body_file "$prose")"
  expect "prose: '$(printf '%.32s' "$prose")…' -> not evidence" 4
done <<PROSE
I have reviewed $CLEAN_HEAD and it is fine.
LGTM — looks good to me, $CLEAN_HEAD.
Approved this pull request at $CLEAN_HEAD.
Reviewed $CLEAN_HEAD — nothing to flag.
No actionable comments were generated in the review of $CLEAN_HEAD.
Changes requested on $CLEAN_HEAD.
Review complete for $CLEAN_HEAD.
> Approved. Reviewed $CLEAN_HEAD.
Unreviewed $CLEAN_HEAD — nobody has looked at this.
No changes requested, because nothing was read ($CLEAN_HEAD).
PROSE
# THE CONTROL for all ten: the same account, the same head, the reviewer's own marker.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD.")"
expect "…while the reviewer's own machine marker clears" 0

# Every row of the marker table, one at a time. Three of the nine prose rows it replaced
# were ever exercised, which is how the negated sentences above went unnoticed.
for marker in walkthrough_start recent_review_start final_review_risk_start; do
  setup "$CLEAN_HEAD"
  add_comment coderabbitai "$(body_file "<!-- $marker -->" "between 6fca618a and $CLEAN_HEAD")"
  expect "the '$marker' marker is a review" 0
done

# THE FOURTH ROW IS GONE, AND THIS IS WHAT KEEPS IT GONE. `review_stack_entry_start` wraps
# a "Review Change Stack" image and a utm_campaign link — a PROMOTIONAL BANNER the vendor
# emits around a review rather than evidence that one happened, which is precisely what
# this table's own admission rule excludes ("nothing that a placeholder or a banner could
# carry"). Measured over all 35 PRs here, removing the row changed 0 outcomes.
assert "the banner marker really is in the recorded clean review" \
  "$(yes_if grep -Fq '<!-- review_stack_entry_start -->' "$CLEAN")"
assert "…and what it wraps really is a promotion, not a review section" \
  "$(yes_if grep -q 'utm_campaign' <<<"$(grep -A3 -F '<!-- review_stack_entry_start -->' "$CLEAN")")"
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- review_stack_entry_start -->' \
  "between 6fca618a and $CLEAN_HEAD")"
expect "the vendor's BANNER marker alone is not a review" 4
# ...and the control, which is why deleting the row cost nothing: the recorded review that
# carries that banner carries three real markers as well, and still clears.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "…while the recorded review carrying it still clears on the others" 0
# ...and a marker the vendor does not emit is not one, so the table is not a catch-all.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_end -->' "at $CLEAN_HEAD")"
expect "a closing marker is not a review marker" 4
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- pre_merge_checks_walkthrough_start -->' "at $CLEAN_HEAD")"
expect "a different marker ending the same way is not one" 4

echo
echo "== a marker is not a pin: route C still has to name THIS head =="
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' "Reviewed $OTHER_SHA.")"
expect "the reviewer's marker naming another commit -> stale" 4
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' 'Looks fine to me.')"
expect "the reviewer's marker naming no commit -> unpinnable" 4

# A SHA inside a URL is a link, not the artifact claiming to have read that commit. It
# used to pin, which is how an artifact quoting a compare range passed.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' \
  "See https://github.com/acme/widgets/commit/$CLEAN_HEAD for context.")"
expect "the head appearing only inside a URL does not pin" 4
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' \
  "See https://github.com/acme/widgets/commit/$CLEAN_HEAD — reviewed $CLEAN_HEAD.")"
expect "…while the same SHA as a bare token does" 0

echo
echo "== shape 2b: an artifact that is NEITHER a review nor a refusal clears nothing =="
# THE DEFAULT-ALLOW THIS SECTION EXISTS TO PIN, and it needed no attacker: positive review
# evidence was never REQUIRED, so the classifier asked only "is this a refusal" and cleared
# everything else that named the head. The reviewer publishes exactly such an artifact on
# essentially every PR, minutes before it has read anything.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file \
  '<!-- This is an auto-generated comment: summarize by coderabbit.ai -->' \
  '> [!NOTE]' \
  '> Currently processing new changes in this PR. This may take a few minutes, please wait...' \
  '>' \
  "> Reviewing files that changed from the base of the PR and between 6fca618a and $CLEAN_HEAD.")"
expect "the 'currently processing' placeholder -> NOT a review" 1
says   "  ...and says the reviewer has not finished" "has NOT FINISHED reviewing"

setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "I have not reviewed $CLEAN_HEAD yet.")"
expect "a bot saying it has not reviewed it yet -> NOT a review" 1

setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "Thanks for the ping — $CLEAN_HEAD is on my list. 🐰")"
expect "a reviewer artifact with no evidence of a review -> refuse" 4
says   "  ...saying what is missing, not that nothing is there" "no evidence"

setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "Thanks for the ping — $CLEAN_HEAD is on my list." \
  '<!-- walkthrough_start -->')"
expect "…and the same artifact WITH the review marker still clears" 0

# "I am still working" is a claim about COMPLETION, so it outranks a marker sitting
# elsewhere in the same body rather than losing to it — unlike refusal PROSE, which loses
# (the section on the auto-incremental notice, below).
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "Currently processing new changes in this PR." \
  '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD.")"
expect "…but a placeholder outranks a review marker beside it" 1

echo
echo "== shape 3: no reviewer signal at all =="
setup "$CLEAN_HEAD"
expect "nothing on the PR -> no review, and no clearance" 3
says   "  ...and says an absent review is not a pass" "NOT a pass"

setup "$CLEAN_HEAD"; add_comment teammate "$(body_file "lgtm, ship it $CLEAN_HEAD")"
expect "only a bystander's approval -> no review" 3

setup "$CLEAN_HEAD"; AUTHOR="coderabbitai"; add_comment coderabbitai "$CLEAN"
expect "the PR's own author cannot review it" 3

setup "$CLEAN_HEAD"; AUTHOR="coderabbitai"
add_review coderabbitai APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "…nor by approving its own PR through the API" 3

setup "$CLEAN_HEAD"; add_comment dev "$CLEAN"
expect "the implementing author's own artifact -> not independent" 3

# AND A MISSING AUTHOR LOGIN MUST NOT SILENTLY SWITCH THAT RULE OFF. The meta guard
# required url / head_sha / pr_number and not the author, so an absent or empty login left
# both author comparisons testing against "" — which no login equals, so the two `continue`s
# that enforce SCHEMA.md clause 8 never fired and the reviewer cleared its own PR. A PR
# always has an author; not being told who it is is unknown state, not a green light.
setup "$CLEAN_HEAD"; AUTHOR=""; add_comment coderabbitai "$CLEAN"
expect "an EMPTY author login -> refuse, never clearance" 2
says   "  ...naming the rule it cannot apply" "SCHEMA.md, clause 8"
setup "$CLEAN_HEAD"; AUTHOR=""; add_review coderabbitai APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "…and the same through the API route" 2
# The author field absent altogether (a deleted account), not merely empty.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"; write_pr
"$REAL_JQ" '.author = null' "$FIX/pr_json" > "$FIX/pr_json.n" && mv "$FIX/pr_json.n" "$FIX/pr_json"
LAST_OUT="$("$SCRIPT" 42 2>&1)"; rc=$?
assert "a null author object -> refuse, never clearance" \
  "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"
# THE CONTROL: the identical fixture with an author who is not the reviewer clears, so the
# three above fail for the missing login and not because the fixture stopped working.
setup "$CLEAN_HEAD"; AUTHOR="dev"; add_comment coderabbitai "$CLEAN"
expect "…while the same PR with a real author clears" 0

echo
echo "== the REVIEWERS login column, which had no assertions at all =="
# Column 1 used to hold `greptile.*` and `(qodo|codium).*` — matched whole-string, but
# ending in `.*`, so any login STARTING with the vendor's name passed as the vendor. The
# column is now a list of exact logins, and these cases are what says so: each stranger
# below publishes a review object that would otherwise clear outright.
for stranger in greptile-evil qodo-attacker codiumsquatter coderabbitai-evil \
                sourcery-ai-not random-person; do
  setup "$CLEAN_HEAD"; add_review "$stranger" APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
  expect "a stranger's account ('$stranger') is not the vendor" 3
done
# THE CONTROL: every login the table really does carry, same fixture, clears. Without
# this, the six above would pass just as well if the table matched nobody at all.
for vendor in coderabbitai sourcery-ai greptile-apps qodo-merge-pro \
              codiumai-pr-agent-pro ellipsis-dev; do
  setup "$CLEAN_HEAD"; add_review "$vendor" APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
  expect "…while '$vendor' is a reviewer this table knows" 0
done
# The host's "[bot]" suffix is the same account under a different endpoint's spelling.
setup "$CLEAN_HEAD"; add_review 'coderabbitai[bot]' APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "…and the [bot] spelling is the same account" 0

echo
echo "== a review must be pinned to the CURRENT head =="
setup "0000000000000000000000000000000000000000"; add_comment coderabbitai "$CLEAN"
expect "a review of an earlier commit -> stale, not clear" 4

setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "the caller's verified head still matches -> clear" 0 --head "$CLEAN_HEAD"
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "the head moved since verification -> refuse" 4 --head "0000000000000000000000000000000000000000"
says   "  ...and says the head moved" "head moved"

# An abbreviated SHA is how a reviewer often names the commit; it must pin just as well,
# and a DIFFERENT commit that merely shares no prefix must not.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' \
  "Reviewed ${CLEAN_HEAD:0:8} — nothing to flag.")"
expect "an abbreviated head SHA still pins" 0
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file '<!-- walkthrough_start -->' \
  "Reviewed deadbeefdeadbeef — nothing to flag.")"
expect "some other commit does not pin" 4

echo
echo "== a later real review outranks an earlier refusal =="
# The quota resets and the reviewer comes back. Both artifacts sit on the PR; the review
# is the one that decides, or a PR could never recover from having been skipped once.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$REFUSAL"; add_comment coderabbitai "$CLEAN"
expect "refusal then review -> clear" 0
setup "$CLEAN_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "…and a later review OBJECT outranks it too" 0
# The boundary of that rule is the section on empty review objects above: a refusal naming
# THIS head is not an old refusal, and nothing contentless outranks it.

echo
echo "== a refusal must be WEIGHED, not dropped before anything reads it =="
# THE RANKING IS ONLY AS GOOD AS THE SET OF REFUSALS THAT REACH IT. Three ways a refusal
# never reached it, each ending in the same rc=0 over a contentless approval at the head.
#
# 1. THE REFUSAL THAT NAMES NO COMMIT. Deciding "does this refusal concern the head" by
# whether it NAMES the head reads a refusal that pins to nothing as a refusal of some other
# commit. The reviewer's own placeholder is exactly that: it says it is still working and,
# in its shortest form, names nothing at all.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file 'Currently processing new changes in this PR.')"
add_review coderabbitai APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "a placeholder naming no commit is not an OLD refusal" 1
says   "  ...and it is the not-yet tier that fired" "NOT FINISHED"
# THE CONTROL, and it is the recovery property this whole ordering exists for: a refusal
# that names a DIFFERENT commit still loses to the empty approval at this head.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "…while a refusal naming ANOTHER commit still loses to it" 0

# 2. THE REFUSAL PUBLISHED IN A STATE THAT CANNOT CLEAR. The submitted-state filter ran
# BEFORE the refusal tables, so a refusal filed as a `DISMISSED` or `PENDING` review object
# was discarded unread. A state that cannot CLEAR is not a state that cannot REFUSE.
for st in DISMISSED PENDING pending; do
  setup "$REFUSAL_HEAD"; add_review coderabbitai "$st" "$REFUSAL_HEAD" "$REFUSAL"
  add_review coderabbitai APPROVED "$REFUSAL_HEAD" "$EMPTY_BODY"
  expect "a refusal filed as a '$st' review object is still a refusal" 1
done
# THE CONTROL: the same non-submitted state carrying a REAL review body still evidences
# nothing, which is the rule that section pins — it must not have become a clearing state.
setup "$CLEAN_HEAD"; add_review coderabbitai DISMISSED "$CLEAN_HEAD" "$CLEAN"
expect "…while a DISMISSED review object still clears nothing" 3

# 3. THE ARTIFACT NOBODY CAN ATTRIBUTE. An artifact whose author the API reported as `null`
# was skipped before TEST 1, so a refusal posted by one was never weighed — and "skip it"
# is also the wrong answer for the question the login decides, which is both whether it
# counts AND whether clause 8 excludes it. Unreadable state, not irrelevant state.
setup "$CLEAN_HEAD"; add_null_comment "$REFUSAL"
add_review coderabbitai APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "an artifact with no author login is unreadable state" 2
says   "  ...saying what could not be answered about it" "no author login"
# THE CONTROL: the identical body from a named account that is NOT the reviewer is merely
# ignored, so this is about the missing field and not about the body.
setup "$CLEAN_HEAD"; add_comment teammate "$REFUSAL"
add_review coderabbitai APPROVED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "…while the same body from a named stranger is just ignored" 0

echo
echo "== nothing clears until every artifact has been read =="
# WHY THERE IS NO `exit 0` IN THE CLASSIFIER LOOP. Ranking inside it ranked by the order
# the host streamed the artifacts in — review objects, then comments — so the file's claim
# that a refusal is weighed before a clearance held only for the shapes that were read last.
# Both orders of the same two artifacts must give the same answer.
setup "$REFUSAL_HEAD"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$REFUSAL"
add_review coderabbitai APPROVED  "$REFUSAL_HEAD" "$EMPTY_BODY"
expect "refusal first, then the empty approval -> refuse" 1
setup "$REFUSAL_HEAD"
add_review coderabbitai APPROVED  "$REFUSAL_HEAD" "$EMPTY_BODY"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$REFUSAL"
expect "…and the same two in the other order -> the same answer" 1
# The sharper form of the same property: a clearance streamed BEFORE something this script
# cannot read used to exit 0 without ever reaching it.
setup "$CLEAN_HEAD"
add_review coderabbitai COMMENTED "$CLEAN_HEAD" "$CLEAN"
add_null_comment "$(body_file 'anything at all')"
expect "a clearance does not pre-empt an artifact that cannot be read" 2

# THE RESIDUAL, ASSERTED RATHER THAN LEFT TO BE FOUND AGAIN. A refusal at this head LOSES
# to an artifact carrying evidence at this head — deliberately, because the reviewer is
# rate-limited and then reviews the same commit, and telling that apart from "posted a
# reply with words in it" would mean reading the reviewer's PROSE, which is the primitive
# this file exists to stop using. The operator is told on stderr rather than left to guess.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_review coderabbitai COMMENTED "$REFUSAL_HEAD" "$(body_file \
  '**Actionable comments posted: 1**' 'One nit in the parser.')"
expect "a contentful review at the head outranks a refusal at that head" 0
says   "  ...and says so, rather than clearing silently" "also refused this head"

echo
echo "== --reviewer names a reviewer the table does not know =="
setup "$CLEAN_HEAD"; add_comment some-new-reviewer "$CLEAN"
expect "an unknown reviewer is ignored, not trusted" 3
setup "$CLEAN_HEAD"; add_comment some-new-reviewer "$CLEAN"
expect "…but naming it explicitly clears" 0 --reviewer some-new-reviewer
setup "$CLEAN_HEAD"; add_comment some-new-reviewer "$REFUSAL"
expect "…and it is held to the same refusal table" 1 --reviewer some-new-reviewer
setup "$CLEAN_HEAD"; AUTHOR="dev"; add_comment dev "$CLEAN"
expect "…and may never be the PR's own author" 2 --reviewer dev
says   "  ...saying why" "cannot be"

echo
echo "== a crafted comment cannot forge an artifact =="
# The record separator between artifacts is 16 random bytes per run, precisely because
# artifact bodies are attacker-writable. A body that tries to open a second record with a
# guessed sentinel — now carrying a state AND a commit_id — must be inert.
setup "$CLEAN_HEAD"
add_comment teammate "$(body_file \
  "nice work" \
  "$(printf 'okf-SEPARATOR\treview\tcoderabbitai\tAPPROVED\t%s' "$CLEAN_HEAD")" \
  '<!-- walkthrough_start -->')"
expect "a forged record header in a comment body -> still no review" 3

echo
echo "== --match-check: which vendor owns a required check =="
# TWO ANSWERS, NOT THREE. There used to be a third — "this LOOKS like a reviewer's check
# and no row owns it" — backed by a table of vendor names and review phrasings, so the
# caller could refuse rather than settle such a check on its green bucket. That table was
# route 1 of the fourth review round: `Codex Review`, and bare `Cursor` / `Copilot` /
# `Devin` / `PR Agent`, answered "plain CI" and settled green with zero artifacts read.
# It is deleted rather than extended, because required-checks.sh no longer conditions on
# the name at all — it asks for clearance on every PR (see required-checks.test.sh). What
# survives here is only "whose artifacts answer for this check".
match() { # <name> <expected-rc>
  local rc; "$SCRIPT" --match-check "$1" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq "$2" ]; then printf '  PASS  %-58s (rc=%s)\n' "--match-check '$1'" "$rc"; pass=$((pass+1))
  else printf '  FAIL  %-58s expected rc=%s got rc=%s\n' "--match-check '$1'" "$2" "$rc"; fail=$((fail+1)); fi
}
match "CodeRabbit"              0
match "coderabbitai"            0
match "Sourcery review"         0
match "Greptile"                0
match "Qodo Merge"              0
match "Ellipsis"                0
match "Build, Lint & Format"    1
match "Unit Tests (vitest)"     1
match "review"                  1
match "Cursor Bugbot"           1   # no row owns it — and the caller no longer cares
match "Codex Review"            1
match "review-app deploy"       1
match "Review Docs"             1

echo
echo "== --self-test proves the script RUNS, which the executable bit does not =="
# required-checks.sh cannot trust `[ -x ]`: a dead shebang, a syntax error, a zero-byte
# file and a truncated copy all carry the mode bit and then fail every call, which reads
# as "no required check is a reviewer's" and clears an unreviewed PR. So it asks for this
# proof instead. The exact string is the contract between the two files.
st_out="$("$SCRIPT" --self-test 2>&1)"; st_rc=$?
assert "--self-test exits 0"                    "$([ "$st_rc" -eq 0 ] && echo 0 || echo 1)"
assert "…and prints the agreed sentinel"        "$([ "$st_out" = "review-clearance: self-test ok" ] && echo 0 || echo 1)"
"$SCRIPT" --self-test extra >/dev/null 2>&1; st_rc=$?
assert "…and takes no arguments"                "$([ "$st_rc" -eq 2 ] && echo 0 || echo 1)"

echo
echo "== ...and that it is COMPLETE, which running does not prove =="
# THE HOLE THIS SECTION EXISTS TO PIN, and it was found by sweeping rather than by
# reading: the self-test sits near the TOP of the script, so a copy truncated anywhere
# BELOW it still parses, still reaches that exit, and still prints the sentinel while
# every table and the whole classifier are missing. Swept over the version before the
# sentinel, 112 of its 606 truncation points passed the self-test and 109 of those went on
# to CLEAR an unreviewed PR. The old truncation case cut at `head -c 400` — inside the
# header comment — so it could not see the class at all.
SELFTEST_LINE="$(head -1 <<<"$(grep -n -- '--self-test" \]; then' "$SCRIPT")" | cut -d: -f1)"
TOTAL_LINES="$(wc -l < "$SCRIPT" | tr -d ' ')"
assert "the self-test block is found, and is not the whole file" \
  "$([ -n "$SELFTEST_LINE" ] && [ "$SELFTEST_LINE" -lt "$TOTAL_LINES" ] && echo 0 || echo 1)"

TRUNC="$TMP/trunc.sh"; survivors=0; swept=0
cut_at="$SELFTEST_LINE"
while [ "$cut_at" -lt "$TOTAL_LINES" ]; do
  head -n "$cut_at" "$SCRIPT" > "$TRUNC"; chmod +x "$TRUNC"
  swept=$((swept + 1))
  out="$("$TRUNC" --self-test </dev/null 2>/dev/null)"
  [ "$?" -eq 0 ] && [ "$out" = "review-clearance: self-test ok" ] && {
    survivors=$((survivors + 1)); [ "$survivors" -le 3 ] && printf '        survived cut at line %s\n' "$cut_at"; }
  cut_at=$((cut_at + 1))
done
printf '  ..... swept %s truncation points from line %s to %s\n' "$swept" "$SELFTEST_LINE" "$TOTAL_LINES"
assert "the sweep actually cut somewhere (>= 100 points)" \
  "$([ "$swept" -ge 100 ] && echo 0 || echo 1)"
assert "NO truncated copy passes --self-test"             "$([ "$survivors" -eq 0 ] && echo 0 || echo 1)"

# Byte-level cuts too: a copy interrupted mid-line is the shape a half-written install or
# a full disk actually produces, and it can leave a syntactically valid file.
BYTES="$(wc -c < "$SCRIPT" | tr -d ' ')"
byte_survivors=0
for frac in 55 65 70 75 80 85 90 95 99; do
  head -c "$((BYTES * frac / 100))" "$SCRIPT" > "$TRUNC"; chmod +x "$TRUNC"
  out="$("$TRUNC" --self-test </dev/null 2>/dev/null)"
  [ "$?" -eq 0 ] && [ "$out" = "review-clearance: self-test ok" ] && byte_survivors=$((byte_survivors + 1))
done
assert "nor does a copy cut mid-line at nine byte offsets" \
  "$([ "$byte_survivors" -eq 0 ] && echo 0 || echo 1)"

# THE CONTROL, and the reason the sweep is not vacuous: a BYTE-FOR-BYTE copy of the same
# file, at the same path shape, self-tests fine. So the refusals above are the truncation.
cp "$SCRIPT" "$TRUNC"; chmod +x "$TRUNC"
out="$("$TRUNC" --self-test 2>&1)"; st_rc=$?
assert "…while a whole copy of the same file passes" \
  "$([ "$st_rc" -eq 0 ] && [ "$out" = "review-clearance: self-test ok" ] && echo 0 || echo 1)"

echo
echo "== one malformed pattern must not silently disable a whole table =="
# `hits()` read grep's OUTPUT and never its STATUS, and grep says 1 for "nothing matched"
# and 2 for "that is not a regular expression". Conflated, one typo'd row turned the
# entire refusal table off — every refusal then read as a review. Each case corrupts ONE
# row of one table in a copy of the script and asserts the copy REFUSES rather than
# proceeding with a table that cannot fire.
break_row() { # <name> <sed expression that corrupts a row> [args to the script...]
  local name="$1" expr="$2"; shift 2
  local broken="$TMP/broken.$((b_n = ${b_n:-0} + 1)).sh"
  sed "$expr" "$SCRIPT" > "$broken"; chmod +x "$broken"
  setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"; write_pr
  local out rc
  out="$("$broken" 42 "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq 2 ] && grep -Fq "not valid POSIX ERE" <<<"$out"; then
    printf '  PASS  %-58s (rc=%s)\n' "$name" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-58s expected rc=2 + the ERE complaint, got rc=%s: %s\n' \
      "$name" "$rc" "$(head -2 <<<"$out" | tr '\n' '|')"
    fail=$((fail+1))
  fi
}
break_row "a broken REFUSALS row -> refuse, never read it as a review" \
  's/^review limit reached$/review limit reache[d/'
break_row "a broken sentinel row -> refuse"        's/^rate\.limited by .*$/rate.limited by [a-z/'
break_row "a broken REVIEW_SENTINEL row -> refuse" 's/walkthrough_start/walkthrough_start(/'
break_row "a broken NOT_YET row -> refuse"         's/^queued for review$/queued for review[/'
break_row "a broken REVIEWERS login -> refuse"     's/^coderabbitai  /coderabbitai[   /'
break_row "a broken REVIEWERS check column -> refuse" \
  's/^sourcery-ai .*$/sourcery-ai             sourcery[/'

# ...and the same corruption is caught by the two table-only modes, so a caller that only
# ever runs those still refuses rather than silently unscoping every clearance call.
BROKEN_TBL="$TMP/broken-table.sh"
sed 's/^review limit reached$/review limit reache[d/' "$SCRIPT" > "$BROKEN_TBL"
chmod +x "$BROKEN_TBL"
"$BROKEN_TBL" --match-check "Build" >/dev/null 2>&1; rc=$?
assert "--match-check on a broken table -> 2, not 'no row owns it'" \
  "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"
"$BROKEN_TBL" --self-test >/dev/null 2>&1; rc=$?
assert "--self-test on a broken table -> 2, so the caller refuses" \
  "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"
# The control: the identical sed with a VALID replacement leaves everything working.
OK_TBL="$TMP/ok-table.sh"
sed 's/^review limit reached$/review limits? reached/' "$SCRIPT" > "$OK_TBL"; chmod +x "$OK_TBL"
"$OK_TBL" --self-test >/dev/null 2>&1; rc=$?
assert "…while a valid edit to the same row still self-tests" \
  "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

echo
echo "== --for-check: one vendor's review may not clear another's check =="
# Two reviewers on one repo, one of them rate-limited. Unscoped, "is there a review on
# this PR" is answered by whichever reviewer did look — so the refusing vendor's required
# check clears on the other vendor's work. --for-check resolves the check name to the
# reviewer that owns it and reads only that account.
two_reviewers() {
  setup "$CLEAN_HEAD"
  add_comment coderabbitai "$REFUSAL"      # the rate-limited one
  add_comment sourcery-ai  "$CLEAN"        # the one that actually reviewed
}
two_reviewers; expect "unscoped, ANY reviewer's review answers (the bypass)" 0
two_reviewers; expect "…but the refusing vendor's own check does not clear" 1 --for-check "CodeRabbit"
says   "  ...quoting the vendor that refused" "coderabbitai"
two_reviewers; expect "…while the vendor that reviewed clears its own"     0 --for-check "Sourcery review"

setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "a check no reviewer owns -> refuse, never widen to everybody" 2 --for-check "Build"
says   "  ...saying whose review would clear it is unknown" "is unknown"
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "--for-check and --reviewer both name a reviewer -> usage error" 2 \
  --for-check "CodeRabbit" --reviewer coderabbitai

echo
echo "== a notice about what was NOT done does not unmake a review that was =="
# Measured on this repository: half of its reviewed PRs carry a real review comment whose
# header says "Review skipped — Auto incremental reviews are disabled", because
# .coderabbit.yaml sets auto_incremental_review: false here. Matching refusal prose over
# the whole body reads those as refusals and quotes the wrong reason at the operator.
skip_notice=(
  '> [!IMPORTANT]'
  '> ## Review skipped'
  '>'
  '> Auto incremental reviews are disabled on this repository.'
  ''
  '<!-- walkthrough_start -->'
  '## Walkthrough'
  ''
)
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "${skip_notice[@]}" \
  "Reviewed between 6fca618a and $CLEAN_HEAD. **Actionable comments posted: 3**")"
expect "refusal prose beside a real review marker -> a review" 0

# ...and the same notice with NOTHING evidencing a review is still a refusal. This is the
# control: the narrowing keys on the machine marker, not on the word "skipped". It is
# exit 8 rather than exit 1 since the skip tier — a refusal either way, and the remedy for
# this one is to ask (see "a SKIP NOTICE is not a quota refusal").
setup "$CLEAN_HEAD"
add_comment coderabbitai "$(body_file "${skip_notice[@]:0:4}" "at $CLEAN_HEAD")"
expect "…the same notice with no review marker -> still a refusal" 8

# THE ASYMMETRY THIS FIXES, AND THE ONE IT DOES NOT — corrected from an earlier claim in
# this file that "every vendor now gets the same answer", which is half true. The
# tie-breaker used to be PROSE, so for a vendor with no row in the unconditional sentinel
# tier a quota refusal carrying any approving-sounding phrase cleared. With prose gone,
# what rescues a refusal is a MACHINE MARKER — and that much IS the same for all six, as
# the six cases below assert. What is NOT the same: every row of the marker table is one
# vendor's spelling and the table is not scoped to the account that posted the body. The
# other five have no marker of their own to be rescued by (their real reviews clear through
# a review object instead), and a body from any of them that QUOTES a row is rescued by a
# marker its author does not emit. Both halves are asserted below the loop.
for vendor in coderabbitai sourcery-ai greptile-apps qodo-merge-pro \
              codiumai-pr-agent-pro ellipsis-dev; do
  setup "$CLEAN_HEAD"
  add_comment "$vendor" "$(body_file \
    "Monthly review limit reached for this repository." \
    "No changes requested; I have reviewed nothing." \
    "Reviewed $CLEAN_HEAD is what I would have done.")"
  expect "a prose quota refusal from '$vendor' -> refuse" 1
done

# The half that IS vendor-neutral: the unconditional tier's second row is the generic HTML
# rate-limit marker, so a vendor with no named row of its own still refuses unconditionally
# — even beside a review marker, which is what "unconditional" means.
setup "$CLEAN_HEAD"
add_comment sourcery-ai "$(body_file '<!-- sourcery: rate-limited -->' \
  '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD.")"
expect "another vendor's own HTML rate-limit marker refuses unconditionally" 1
# The half that is NOT, stated as a test so it cannot quietly become untrue: the marker
# table holds ONE vendor's spellings and is not scoped to the poster, so quoting a row
# rescues a prose refusal from any account. Scoping the table per vendor is the fix if this
# ever matters; it is recorded here rather than claimed away.
setup "$CLEAN_HEAD"
add_comment sourcery-ai "$(body_file 'Monthly review limit reached for this repository.' \
  '<!-- walkthrough_start -->' "Reviewed $CLEAN_HEAD.")"
expect "…but another vendor's PROSE refusal is rescued by a marker it never emits" 0

# The hole this narrowing must not open, asserted on the evidence rather than trusted:
# the recorded refusal quotes the PR head, so if a review marker could outrank the machine
# sentinel, #30 would clear. It carries none, and the sentinel outranks anyway.
assert "the recorded refusal carries NO review marker" \
  "$(yes_if bash -c '! grep -Eq "walkthrough_start|recent_review_start|final_review_risk_start" "$1"' _ "$REFUSAL")"
assert "…and does carry the machine-readable rate-limit sentinel" \
  "$(yes_if grep -Fq "rate limited by coderabbit.ai" "$REFUSAL")"
setup "$REFUSAL_HEAD"
{ cat "$REFUSAL"; printf '\n<!-- walkthrough_start -->\nActionable comments posted: 2\n'; } \
  > "$TMP/refusal-with-evidence.md"
add_comment coderabbitai "$TMP/refusal-with-evidence.md"
expect "the sentinel outranks a review marker -> still a refusal" 1

echo
echo "== a verdict that QUOTES refusal language is not itself a refusal =="
# The fallback reviewer's job on a rate-limited PR is to SAY the hosted reviewer refused
# — quoting the words, and the sentinel. Prose alone classifies that verdict as a refusal,
# which is the reviewer disqualifying its own review. The okf-verdict trailer (SCHEMA.md)
# is the structured self-declaration that settles it, and it outranks every refusal row.
VERDICT_PROSE=(
  "CodeRabbit published a green check whose body reads Review limit reached, and the"
  "comment carries the rate limited by coderabbit.ai sentinel — so no review happened."
)
trailer() { # [head_sha to claim] — the trailer SCHEMA.md defines
  printf '%s\n' '<!-- okf-verdict v1' 'verdict: changes-requested' 'reviewer: qa-reviewer' \
    "head_sha: ${1:-$CLEAN_HEAD}" 'lenses: correctness=done security=done repro=done' \
    'unverified_criteria: none' 'caveats: none' '-->'
}
setup "$CLEAN_HEAD"
add_comment qa-bot "$(body_file "${VERDICT_PROSE[@]}" "$(trailer)")"
expect "a verdict quoting a refusal in prose -> a review" 0 --reviewer qa-bot

# The control, and it is the whole reason the guard is a TRAILER rather than a mood: the
# identical prose WITHOUT the trailer is still read as a refusal.
setup "$CLEAN_HEAD"
add_comment qa-bot "$(body_file "${VERDICT_PROSE[@]}" "I reviewed $CLEAN_HEAD myself.")"
expect "…the same prose with no trailer -> classified as a refusal" 1 --reviewer qa-bot

echo
echo "== the trailer is PARSED, not grepped: a substring must not outrank anything =="
one_liner="$TMP/refusal-plus-trailer-substring.md"
{ cat "$REFUSAL"; printf '\n<!-- okf-verdict v1 -->\n'; } > "$one_liner"
assert "the crafted body still names the head verbatim (so it COULD clear)" \
  "$(yes_if grep -Fq "$REFUSAL_HEAD" "$one_liner")"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$one_liner"
expect "one appended okf-verdict substring on the recorded refusal -> still refuses" 1
says   "  ...still quoting the reviewer's own words" "Review limit reached"

# A WELL-FORMED trailer, from the vendor's own account, must not clear either: the tier is
# scoped to an explicitly named NON-VENDOR account, which is how the fallback reviewer is
# reached and is never how a hosted vendor is.
full="$TMP/refusal-plus-full-trailer.md"
{ cat "$REFUSAL"; printf '\n'; trailer "$REFUSAL_HEAD"; } > "$full"
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$full"
expect "a well-formed trailer from a TABLE-matched vendor -> still refuses" 1

# AND NAMING THAT VENDOR WITH --reviewer MUST NOT RE-ARM IT. `--reviewer coderabbitai` used
# to hand the highest tier in the file to the account whose comments quote diffs, against
# that same account's own machine-readable refusal.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$full"
expect "…nor when the vendor is named with --reviewer" 1 --reviewer coderabbitai
setup "$REFUSAL_HEAD"; add_comment 'coderabbitai[bot]' "$full"
expect "…nor under the vendor's [bot] spelling" 1 --reviewer 'coderabbitai[bot]'

# ...and the control for all of them: the same well-formed trailer, at this head, from the
# non-vendor reviewer the caller named, is a review.
setup "$REFUSAL_HEAD"; add_comment qa-bot "$full"
expect "…while the named fallback reviewer's own trailer clears" 0 --reviewer qa-bot

# Each required field, one at a time. A trailer missing any of them cannot be evaluated
# against SCHEMA.md's predicate at all, so it is not a structured claim — it is a comment.
malformed() { # <name> <sed expression applied to the trailer>
  local body; body="$TMP/verdict.$((v_n = ${v_n:-0} + 1)).md"
  { printf '%s\n' "${VERDICT_PROSE[@]}"; trailer | sed "$2"; } > "$body"
  setup "$CLEAN_HEAD"; add_comment qa-bot "$body"
  expect "$1" 1 --reviewer qa-bot
}
malformed "a trailer with no head_sha -> not a verdict"        '/^head_sha:/d'
malformed "a trailer for a DIFFERENT head -> not this head's"  "s/^head_sha: .*/head_sha: $OTHER_SHA/"
malformed "a trailer with no verdict field -> not a verdict"   '/^verdict:/d'
malformed "a trailer with no reviewer field -> not a verdict"  '/^reviewer:/d'
malformed "a trailer nobody closed -> not a block"             '/^-->/d'
malformed "a verdict value nobody defines -> not a verdict"    's/^verdict: .*/verdict: fine-i-guess/'
malformed "the marker buried in a sentence -> not a block"     's/^<!-- okf-verdict v1$/as in <!-- okf-verdict v1 -- see SCHEMA.md/'

echo
echo "== the parser was sound; the TEXT fed to it was not =="
# THREE DOORS THAT REOPENED THE SAME BYPASS. The trailer parse now reads the STRICT
# rendering — fenced AND indented blocks removed, empty when the fences do not balance —
# and refuses a block nested in another HTML comment or one nobody closed.
indented="$TMP/verdict-indented.md"
{ printf '%s\n' "${VERDICT_PROSE[@]}"; printf 'For example:\n\n'; trailer | sed 's/^/    /'; } > "$indented"
assert "the indented copy carries a well-formed trailer, just indented" \
  "$(yes_if grep -Eq '^    <!-- okf-verdict v1$' "$indented")"
setup "$CLEAN_HEAD"; add_comment qa-bot "$indented"
expect "a trailer in an INDENTED code block -> not a trailer" 1 --reviewer qa-bot

nested="$TMP/verdict-nested.md"
{ printf '%s\n' "${VERDICT_PROSE[@]}"; printf '<!-- an outer comment GitHub renders blank\n'
  trailer; printf -- '-->\n'; } > "$nested"
setup "$CLEAN_HEAD"; add_comment qa-bot "$nested"
expect "a trailer NESTED in an outer HTML comment -> not a trailer" 1 --reviewer qa-bot

unbalanced="$TMP/verdict-unbalanced.md"
{ printf '%s\n' "${VERDICT_PROSE[@]}"; printf '```\n'; trailer; } > "$unbalanced"
setup "$CLEAN_HEAD"; add_comment qa-bot "$unbalanced"
expect "a trailer after an unbalanced fence -> unreadable body, no trailer" 1 --reviewer qa-bot

# State must not leak from a block nobody closed into the fields of the next one, which is
# how two half-trailers used to add up to one whole one.
leak="$TMP/verdict-leak.md"
{ printf '%s\n' "${VERDICT_PROSE[@]}"
  printf '%s\n' '<!-- okf-verdict v1' 'verdict: pass' 'reviewer: qa-reviewer'
  printf '%s\n' '<!-- okf-verdict v1' "head_sha: $CLEAN_HEAD" '-->'; } > "$leak"
setup "$CLEAN_HEAD"; add_comment qa-bot "$leak"
expect "fields from an unclosed block do not complete the next one" 1 --reviewer qa-bot

# THE CONTROL for all four: the same trailer, unindented, unnested, balanced, one block.
setup "$CLEAN_HEAD"
add_comment qa-bot "$(body_file "${VERDICT_PROSE[@]}" "$(trailer)")"
expect "…while the same trailer as a plain block clears" 0 --reviewer qa-bot

echo
echo "== the environment failing is never a clearance =="
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"; : > "$FIX/gh_broken"
expect "PR unreadable -> refuse, and not as 'no review'" 2
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
write_pr; : > "$FIX/reviews_broken"
LAST_OUT="$("$SCRIPT" 42 2>&1)"; rc=$?
assert "the review list unreadable -> refuse, not 'no reviews'" \
  "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"
says   "  ...saying the reviewer state is unknown" "unknown fails closed"
# AND THE COMMENT LIST IS THE ONE THAT MATTERS MORE, which is why it is fetched the same
# way. A lost REVIEW costs a refusal; a lost REFUSAL — and the refusal is a comment — is a
# merge. The recorded refusal is on this PR and the reviewer's clean review is not, so a
# comment list that silently answered "nothing here" would clear it.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
write_pr; : > "$FIX/comments_broken"
LAST_OUT="$("$SCRIPT" 42 2>&1)"; rc=$?
assert "the comment list unreadable -> refuse, not 'no comments'" \
  "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"
says   "  ...saying a refusal it cannot see is a merge" "that is a merge"
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"; : > "$FIX/jq_broken"
expect "the JSON reader cannot answer -> refuse" 2
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "unknown option -> usage error" 2 --nope
rc=0; "$SCRIPT" >/dev/null 2>&1 || rc=$?
assert "no arguments -> usage error" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

echo
echo "== SCHEMA.md clause 9: a review at the head does not clear over an open thread =="
# THE CLAUSE THAT HAD NO READER. `qa-reviewer.md` and `auditor.md` state clause 9 in prose
# and nothing checked it, so the 2026-09-05 audit of seven PRs found FOUR failing on
# clauses 3 and 9 — three of those had a reviewer that ANSWERED and were merged anyway.
# Not quota. Every case below starts from the recorded clean review, so the only thing
# under test is the thread state: a resolver that refused everything would fail the
# clearing cases here rather than passing three in four.
CR_URL="https://github.com/acme/widgets/pull/42#discussion_r1"

setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
add_thread false 'plugin/scripts/run.sh' 42 coderabbitai "$CR_URL" '`$dir` is unquoted here.'
expect "a real review + one UNRESOLVED reviewer thread -> 6" 6
says   "  ...naming the clause"                    "clause 9"
says   "  ...naming the file and line"             "plugin/scripts/run.sh:42"
says   "  ...naming who opened it"                 "coderabbitai"
says   "  ...linking the thread"                   "$CR_URL"
says   "  ...quoting its opening line"             '`$dir` is unquoted here.'
# THE ADVICE IS THE POINT OF THE SEPARATE CODE. Exit 4 means ask for a review; exit 6 means
# do not — you have one. Folding 6 into 4 would send an agent to buy a review session to be
# told what the threads already say.
says   "  ...and telling the caller NOT to re-request" "DO NOT REQUEST ANOTHER REVIEW"

setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
add_thread true 'plugin/scripts/run.sh' 42 coderabbitai "$CR_URL" '`$dir` is unquoted here.'
expect "the same thread, RESOLVED -> clear" 0

# CLAUSE 8 STILL EXCLUDES THE AUTHOR, HERE TOO. A thread the PR author opened on its own PR
# is a note to itself, and reading it as a reviewer finding would refuse every PR whose
# implementer left itself a marker.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
add_thread false 'a.sh' 1 dev "$CR_URL" 'note to self'
expect "an unresolved thread opened by the PR AUTHOR -> clear" 0

# AND A TEAMMATE'S THREAD IS NOT THE INDEPENDENT GATE. Whose thread counts is decided by
# the same REVIEWERS table that decides whose review counts — one authority, not two.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
add_thread false 'a.sh' 1 some-colleague "$CR_URL" 'drive-by question'
expect "an unresolved thread from an account in no table -> clear" 0

# ...unless that account is the one named with --reviewer, which is how a repo whose
# reviewer has no table row uses this at all.
setup "$CLEAN_HEAD"; add_comment some-colleague "$CLEAN"
add_thread false 'a.sh' 1 some-colleague "$CR_URL" 'drive-by question'
expect "...but it DOES count when named with --reviewer" 6 --reviewer some-colleague

# A NULL AUTHOR (a deleted account) MUST NOT ABORT THE FILTER AND TAKE EVERY OTHER THREAD
# WITH IT. It is skipped; the reviewer thread beside it still refuses.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
add_thread false 'a.sh' 1 "" "$CR_URL" 'from a deleted account'
add_thread false 'b.sh' 7 coderabbitai "$CR_URL" 'and this one is the reviewer'
expect "a null-author thread beside a reviewer's -> still 6" 6
says   "  ...and it is the reviewer's thread that is named" "b.sh:7"

# A FILE-LEVEL THREAD HAS NO LINE, and a null there used to be the shape that killed the
# whole jq filter. It renders as `-` rather than disappearing.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
add_thread false 'c.sh' null coderabbitai "$CR_URL" 'whole-file concern'
expect "a file-level thread (line: null) -> 6" 6
says   "  ...rendered with no line rather than dropped" "c.sh:-"

# EVERY open thread is named, not just the first: a reader fixing one and finding another
# is a second round nobody needed.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
add_thread false 'x.sh' 3 coderabbitai "$CR_URL" 'first'
add_thread false 'y.sh' 9 coderabbitai "$CR_URL" 'second'
expect "two unresolved threads -> 6" 6
says   "  ...naming the first"  "x.sh:3"
says   "  ...and the second"    "y.sh:9"

# UNTRUSTED TEXT. A thread body is written by anyone who can comment. Control characters
# are stripped before this reaches a terminal, exactly as the refusal quotes are.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
add_thread false 'z.sh' 1 coderabbitai "$CR_URL" "$(printf 'esc\033[2Jhere')"
expect "a thread body carrying an escape sequence -> 6" 6
assert "  ...and the escape byte never reaches the terminal" \
  "$(grep -q "$(printf '\033')" <<<"$LAST_OUT" && echo 1 || echo 0)"

echo
echo "== clause 9 is the LAST question, and it fails closed on what it cannot read =="
# ORDER MATTERS. A PR with no review at all is refused for THAT, at 3. Reporting an open
# thread on top of it would bury the answer the caller needs — ask for a review — under one
# it cannot act on yet.
setup "$CLEAN_HEAD"
add_thread false 'a.sh' 1 coderabbitai "$CR_URL" 'open'
expect "no review at all + an open thread -> 3, not 6" 3

# ...and the same for a refusal: exit 1 is still exit 1.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
add_thread false 'a.sh' 1 coderabbitai "$CR_URL" 'open'
expect "a rate-limit refusal + an open thread -> 1, not 6" 1

# THE THREAD READ FAILING IS UNKNOWN STATE, NEVER A PASS. `gh pr view` and the REST reads
# have already succeeded by this point, so a GraphQL failure is an anomaly — and a clause
# that cannot be applied is not a clause that passes.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
write_pr; : > "$FIX/threads_broken"
LAST_OUT="$("$SCRIPT" 42 2>&1)"; rc=$?
assert "the thread list unreadable -> 2, not a clearance" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"
says   "  ...saying which clause cannot be applied" "clause 9"

# MORE THAN ONE PAGE OF THREADS, AND NONE OF THE FIRST 100 OPEN. "No unresolved thread in
# the threads I could see" is not "no unresolved thread", and a 101-thread PR is exactly
# the large PR where an unanswered finding hides. Unknown, so 2.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
add_thread true 'a.sh' 1 coderabbitai "$CR_URL" 'resolved'
THREADS_MORE=true
expect "a second page of threads, none of page 1 open -> 2" 2
says   "  ...saying it is unknown rather than satisfied" "UNKNOWN"

# ...but an OPEN thread on page 1 still refuses at 6: that answer does not depend on the
# pages nobody read, so falling back to "unknown" would lose a fact already established.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
add_thread false 'a.sh' 1 coderabbitai "$CR_URL" 'open on page one'
THREADS_MORE=true
expect "a second page, but page 1 HAS an open thread -> 6" 6

echo
echo "== the third part of the three-part change: the callers know codes 6 and 8 =="
# ADDING AN EXIT CODE IS A THREE-PART CHANGE AND THE THIRD PART IS THE ONE THAT BREAKS.
# `review-rounds.sh` lists the sibling's refusals as `1|3|4|5` over a FATAL `*` default, so
# a new code lands in the default and turns "there is an open thread" into "the round count
# is unknown" on every PR that has one. Asserted on the source, because driving it needs a
# PR: these are the two arms, and both must count 6 as a ROUND — a review DID complete.
ROUNDS="$SCRIPTS/review-rounds.sh"
assert "review-rounds.sh has no un-updated 1|3|4|5 arm left" \
  "$([ "$(grep -cE '^\s*1\|3\|4\|5\)' "$ROUNDS")" = 0 ] && echo 0 || echo 1)"
assert "...and both non-counting arms list 8 — a skip notice is not a round" \
  "$(grep -qx 2 <<<"$(grep -cE '^\s*1\|3\|4\|5\|8\)' "$ROUNDS")" && echo 0 || echo 1)"
assert "...and both of its counting arms accept 6 as a completed round" \
  "$(grep -qx 2 <<<"$(grep -cE '^\s*0\|6\)' "$ROUNDS")" && echo 0 || echo 1)"
assert "required-checks.sh tells a 6 not to request another review" \
  "$(grep -q 'do NOT request another one' "$SCRIPTS/required-checks.sh" && echo 0 || echo 1)"
# The code is documented where a caller reads it, not only where it is raised.
assert "the exit-code table documents 6" \
  "$(grep -q '^#   6  a review artifact DOES evidence' "$SCRIPT" && echo 0 || echo 1)"
assert "...and documents 8" \
  "$(grep -q '^#   8  the reviewer SKIPPED this PR' "$SCRIPT" && echo 0 || echo 1)"
# Both prose readers of exit 1 gained 8 with its remedy, in this same change: a tick that
# reads an 8 its own table does not define falls through to a standing HOLD, silently.
# `project-manager.md` is NOT one of them any more — #229 moved step 4's refusal table out
# of it into the tick-step file, and the agent file only points at it now.
for reader in "$REPO_ROOT/plugin/tick-steps/step-4-advance.md" \
              "$REPO_ROOT/plugin-yolo/companion/AUTONOMY.md"; do
  assert "$(basename "$reader") documents exit 8 and its remedy" \
    "$(grep -q '@coderabbitai review' "$reader" && grep -qi 'nobody ever asked' "$reader" \
       && echo 0 || echo 1)"
done

echo
echo "== a PR that cannot merge is refused BEFORE anything else is read =="
# 2026-09-13: #206, #209 and #211 were presented as merge rows — review at head, CI green —
# while the host reported all three CONFLICTING / DIRTY. Four sibling merges had moved the
# base underneath them, with no commit on any of the three. A verdict about a review was
# being read as a verdict about a merge.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"; MERGEABLE=CONFLICTING; MERGE_STATE=DIRTY
expect "a real review at the head, but the PR CONFLICTS -> 7" 7
says   "  ...naming the state the host reported" "mergeable=CONFLICTING"
says   "  ...and sending the caller to a rebase, not to a review" "do NOT request a review"

# THE TWO FIELDS ARE READ INDEPENDENTLY. They are computed by different parts of the host
# and disagree in practice; either one saying "conflict" is a conflict.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"; MERGEABLE=CONFLICTING; MERGE_STATE=CLEAN
expect "mergeable=CONFLICTING alone -> 7" 7
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"; MERGEABLE=MERGEABLE; MERGE_STATE=DIRTY
expect "mergeStateStatus=DIRTY alone -> 7" 7
says   "  ...and says which field answered" "mergeStateStatus=DIRTY"

# FIRST means first: ahead of the artifact reads and ahead of the `--head` staleness test.
# A conflicting PR with no artifacts at all is 7, not 3, and a conflicting PR at a moved
# head is 7, not 4 — one rebase re-answers both, and 3 or 4 would send the caller to a
# reviewer instead.
setup "$CLEAN_HEAD"; MERGEABLE=CONFLICTING; MERGE_STATE=DIRTY
expect "no artifacts at all, but conflicting -> 7, not 3" 7
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"; MERGEABLE=CONFLICTING; MERGE_STATE=DIRTY
expect "a stale --head on a conflicting PR -> 7, not 4" 7 --head "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

echo
echo "== UNKNOWN is a HOLD (exit 2), never a pass =="
# The host computes mergeStateStatus lazily and answers UNKNOWN for seconds after the base
# moves — which is exactly the window the incident happened in. Reading UNKNOWN as clean
# would re-open the hole with a smaller race.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"; MERGEABLE=UNKNOWN; MERGE_STATE=UNKNOWN
expect "both fields UNKNOWN -> 2, not 0 and not 7" 2
says   "  ...and says to ask again next tick" "Ask again next tick"
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"; MERGEABLE=MERGEABLE; MERGE_STATE=UNKNOWN
expect "mergeStateStatus UNKNOWN alone -> 2" 2
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"; MERGEABLE=UNKNOWN; MERGE_STATE=CLEAN
expect "mergeable UNKNOWN alone -> 2" 2
# A host that answers neither field — an old `gh`, a token without push access, a shape
# change. Absent is unknown, and unknown fails closed like every other one here.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"; MERGEABLE=""; MERGE_STATE=""
expect "neither field reported at all -> 2" 2
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"; MERGEABLE=MERGEABLE; MERGE_STATE=SOMETHING_NEW
expect "a mergeStateStatus this script has not been taught -> 2" 2

echo
echo "== a MERGEABLE PR still clears, and the states that are not this file's question =="
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "MERGEABLE/CLEAN with a real review -> still clears" 0
# BLOCKED is a failing or missing required check and UNSTABLE is a red one; both are
# `required-checks.sh`'s question, not this one. BEHIND matters only under strict
# up-to-date, which is the merge gate's. None of the three is a conflict.
for st in BLOCKED UNSTABLE BEHIND HAS_HOOKS DRAFT; do
  setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"; MERGE_STATE="$st"
  expect "MERGEABLE/$st is not a conflict -> clears on review grounds" 0
done

echo
echo "== --no-merge-check suppresses it, for the round counter only =="
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"; MERGEABLE=CONFLICTING; MERGE_STATE=DIRTY
expect "a conflicting PR with --no-merge-check -> the review answer" 0 --no-merge-check
setup "$CLEAN_HEAD"; MERGEABLE=CONFLICTING; MERGE_STATE=DIRTY
expect "…and it suppresses the check, not the rest of the file" 3 --no-merge-check

echo
echo "== the third part of the three-part change: the callers know code 7 =="
# Same rule as code 6 below: a new code lands in `review-rounds.sh`'s fatal `*` arm. Here
# the fix is not a new arm but the opt-out — that file asks about the PAST, where a
# conflict today is not an answer. Both of its call sites must pass it or every
# conflicting PR reports "the round count is unknown".
assert "review-rounds.sh passes --no-merge-check at both call sites" \
  "$(grep -qx 2 <<<"$(grep -vE '^[[:space:]]*#' "$ROUNDS" | grep -c -- '--no-merge-check')" \
     && echo 0 || echo 1)"
assert "required-checks.sh tells a 7 to rebase, not to request a review" \
  "$(grep -q 'CONFLICTS with its base' "$SCRIPTS/required-checks.sh" && echo 0 || echo 1)"
assert "the exit-code table documents 7" \
  "$(grep -q '^#   7  the PR CANNOT MERGE' "$SCRIPT" && echo 0 || echo 1)"

# The tick's step 4 carries this, not the core prompt: the exit-7 procedure lives with the
# rest of the review-clearance reading, which moved out of project-manager.md whole.
PM="$SCRIPTS/../tick-steps/step-4-advance.md"
assert "the tick's step 4 routes a 7 to a rebase round, not a merge row" \
  "$(grep -q 'EXIT 7 IS NOT ABOUT THE REVIEWER AT ALL' "$PM" && echo 0 || echo 1)"
assert "…and records it as a conflict blocker" \
  "$(grep -q 'stall-counter.sh record <task-doc>' "$PM" && echo 0 || echo 1)"
# THE ESCALATION criterion 3 PROMISES IS ONLY REACHABLE IF --progress STAYS OFF. The
# counter resets on PR activity the tick observed, and a rebase push IS that activity, so
# a conflict round that passed --progress would reset the count it exists to accumulate
# and two rebases in a row would never reach the cap.
assert "…and forbids --progress on a conflict round, or the cap is unreachable" \
  "$(grep -q 'Never pass `--progress` on this round' "$PM" && echo 0 || echo 1)"

echo
echo "== the answer is re-read every run, never cached =="
# The 2026-09-13 failure was a verdict computed against the PREVIOUS default-branch head.
# Mergeability changes with no commit on the PR, so the same PR at the same head must be
# free to answer differently on the next call — back-to-back here, because `watch-board`
# and the tick both re-enter this file rather than reading a stored answer.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "tick 1: the base has not moved -> clear" 0
MERGEABLE=CONFLICTING; MERGE_STATE=DIRTY
expect "tick 2: same PR, same head, base moved -> 7" 7
MERGEABLE=MERGEABLE; MERGE_STATE=CLEAN
expect "tick 3: rebased -> clears again, from the host each time" 0
# --- --record: the persist half, which is what the OFFLINE renderers read -------------
# `write-snapshot.sh` cannot ask the host, so without a record the board minted a merge
# verb from `status: in-review` plus a PR link — the 2026-09-13 failure itself. The value
# is written in the call that made the read, so the two cannot disagree.
echo
echo "== --record persists the read where write-snapshot.sh can see it =="
DOC="$TMP/task-042.md"
mkdoc() { printf -- '---\ntype: Task\nstatus: in-review\npr: [ x ]\n---\n# Notes\n' > "$DOC"; }
recorded() { sed -n 's/^pr_mergeable: //p' "$DOC"; }

setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
MERGEABLE=MERGEABLE; MERGE_STATE=CLEAN; mkdoc
expect "a clearing PR still clears with --record" 0 --record "$DOC"
assert "…and the doc carries MERGEABLE"    "$([ "$(recorded)" = MERGEABLE ] && echo 0 || echo 1)"
MERGEABLE=CONFLICTING; MERGE_STATE=DIRTY
expect "a conflicting PR still answers 7" 7 --record "$DOC"
assert "…and the SAME doc is overwritten, never appended to" \
  "$([ "$(recorded)" = CONFLICTING ] && [ "$(grep -c '^pr_mergeable:' "$DOC")" = 1 ] && echo 0 || echo 1)"
MERGEABLE=MERGEABLE; MERGE_STATE=DIRTY; mkdoc
expect "mergeable=MERGEABLE with mergeStateStatus=DIRTY is still 7" 7 --record "$DOC"
assert "…and DIRTY is recorded as CONFLICTING, not as MERGEABLE" \
  "$([ "$(recorded)" = CONFLICTING ] && echo 0 || echo 1)"
MERGEABLE=UNKNOWN; MERGE_STATE=UNKNOWN; mkdoc
expect "an UNKNOWN read holds at 2" 2 --record "$DOC"
assert "…and records UNKNOWN, which is not MERGEABLE" \
  "$([ "$(recorded)" = UNKNOWN ] && echo 0 || echo 1)"
assert "…and the task body is untouched" "$(grep -q '^# Notes' "$DOC" && echo 0 || echo 1)"
MERGEABLE=MERGEABLE; MERGE_STATE=CLEAN
expect "a --record naming no file is not a refusal" 0 --record "$TMP/no-such-task.md"
assert "…and creates nothing" "$([ ! -e "$TMP/no-such-task.md" ] && echo 0 || echo 1)"
assert "the PM prompt is told --record is not optional" \
  "$(grep -q -- '--record` is not optional here' "$PM" && echo 0 || echo 1)"
assert "the PM prompt tries rebase-pr.sh before it spends an agent" \
  "$(grep -q 'TRY THE SCRIPT BEFORE YOU SPEND AN AGENT' "$PM" && echo 0 || echo 1)"
assert "…and dispatches only on its exit 3" \
  "$(grep -q 'Exit 3 is the only one that earns an agent round' "$PM" && echo 0 || echo 1)"

assert "nothing in the script stores a mergeability answer" \
  "$(grep -qE 'mergeab|mergeState' "$SCRIPT" && \
     ! grep -qE '(cache|CACHE)[^)]*merge' <<<"$(grep -vE '^[[:space:]]*#' "$SCRIPT")" && echo 0 || echo 1)"

echo
echo "== an ACKNOWLEDGEMENT is not a review =="
# `@coderabbitai review` is answered immediately by an auto-generated reply that names the
# head it was invoked at — "✅ Action performed / Review finished" — and is posted whether
# or not a review follows. ACK is that reply, verbatim from #227 at 2026-09-14T11:03:30Z.
assert "the recorded acknowledgement exists" "$(yes_if test -s "$ACK")"
assert "…and carries the invocation marker a real review never does" \
  "$(yes_if grep -Fq '<!-- CodeRabbit review command invocation:' "$ACK")"

setup "$CLEAN_HEAD"; add_comment coderabbitai "$ACK"
expect "the acknowledgement alone -> refuse, not clear" 4
says   "  ...and says what it is" "AUTO-GENERATED REPLY"
says   "  ...and names the command that can review this head" "@coderabbitai full review"

# At ANY head: the reply's whole content is that a command was received, so the head the PR
# happens to be at cannot make it evidence. (The #227 clearance itself came through the
# vendor's edited-in-place SUMMARY comment, which is the marker-plus-stale-object case.)
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$ACK"
expect "…and at another head too" 4

# The ack does not outrank a real refusal, so a rate limit quoted inside one still reports
# exit 1 — the acknowledgement tier is consulted only after every refusal tier.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$(body_file \
  '<!-- CodeRabbit review command invocation: v2:abc -->' \
  '⚠️ Action not completed' 'Review limit reached.')"
expect "an acknowledgement quoting a rate limit is still the refusal" 1

# THE INVERSE DEFECT, and the reason this tier is one machine marker rather than four rows.
# `hits` treats rows as independent alternatives, so prose rows — `Action performed`, a
# whole-line `Review finished` — classified as an ACK any review body that happened to
# contain them, and a skipped comment never reaches the evidence tests below it. A review
# quoting an acknowledgement is an ordinary thing on a PR that touches this file: the ack
# fixture one directory up is in this branch's own diff.
assert "the quoted prose carries neither machine marker" \
  "$(yes_if bash -c '! grep -qiE "coderabbit review command invocation:|auto-generated reply" "$1"' _ "$ACK_PROSE")"
assert "…and is the acknowledgement's own wording, verbatim" \
  "$(yes_if bash -c 'grep -Fqx "Review finished." "$1" && grep -Fq "Action performed" "$1"' _ "$ACK_PROSE")"
setup "$CLEAN_HEAD"; add_comment coderabbitai "$(cat "$CLEAN" "$ACK_PROSE" > "$TMP/review-plus-ack"; printf '%s' "$TMP/review-plus-ack")"
expect "a real review that also quotes the ack prose -> still a review" 0
says   "  ...pinned to the head, not skipped as a receipt" "$CLEAN_HEAD"

echo
echo "== a SKIP NOTICE is not a quota refusal =="
# Two refusals with opposite remedies shared exit 1 until now: a rate limit reopens by
# itself, and "Auto reviews are disabled … invoke the `@coderabbitai review` command" never
# does. Measured 2026-09-15: four PRs held for three ticks on exit 1 while one comment
# would have got a review in 4 seconds.
assert "the recorded skip notice exists" "$(yes_if test -s "$SKIP")"
assert "…and carries the vendor's own skip marker" \
  "$(yes_if grep -Fq 'auto-generated comment: skip review by coderabbit.ai' "$SKIP")"
assert "…and carries NO rate-limit sentinel, so 8 is not rescuing a quota refusal" \
  "$(yes_if bash -c '! grep -qiE "rate.limited by|limit reached" "$1"' _ "$SKIP")"

setup "$CLEAN_HEAD"; add_comment coderabbitai "$SKIP"
expect "the recorded skip notice -> exit 8, not exit 1" 8
says   "  ...saying nobody ever asked" "NOBODY HAS ASKED"
says   "  ...and naming the command that asks" "@coderabbitai review"
says   "  ...and which PR to spend a one-per-window quota on" "criteria table"

# The other three machine notices keep the codes they already had. This is the whole
# contract in four lines: one notice, one code.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"
expect "…while the recorded rate-limit notice stays exit 1" 1
setup "$CLEAN_HEAD"; add_comment coderabbitai "$ACK"
expect "…and the acknowledgement stays exit 4" 4

# THE TIER PLACEMENT, WHICH IS THE CORRECTNESS QUESTION. The vendor edits ONE summary
# comment in place, so the skip marker and a completed review's walkthrough sit in the same
# body — #215 carries the marker and 2 review objects, #213 the marker and 1. Exit 8 is
# reached only through table 2b, which the review marker outranks, so a PR that HAS been
# reviewed can never be told to ask again.
assert "the coexistence fixture exists" "$(yes_if test -s "$SKIP_REVIEWED")"
assert "…and carries the vendor's skip marker" \
  "$(yes_if grep -Fq "skip review by coderabbit.ai" "$SKIP_REVIEWED")"
assert "…and the completed review's walkthrough marker, in that same body" \
  "$(yes_if grep -Fqx "<!-- walkthrough_start -->" "$SKIP_REVIEWED")"
setup "$SKIP_REVIEWED_HEAD"; add_comment coderabbitai "$SKIP_REVIEWED"
expect "a skip marker BESIDE a real review -> the review, never 8" 0
setup "$OTHER_SHA"; add_comment coderabbitai "$SKIP_REVIEWED"
expect "…and at another head it is STALE, still never 8" 4

# ANY OTHER REFUSAL ON THE PR MEANS SOMEBODY DID ASK. A rate limit is the ordinary answer
# to the very request exit 8 asks for, so it puts the PR back on exit 1 — wait, do not ask
# again — whatever order the host streamed the two comments in.
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$SKIP"; add_comment coderabbitai "$REFUSAL"
expect "a skip notice beside a rate limit -> exit 1, the quota answer" 1
setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL"; add_comment coderabbitai "$SKIP"
expect "…and the same two in the other order" 1

# WHAT BOUNDS THE ASK TO ONCE PER HEAD. The remedy is otherwise stateless, and four PRs at
# 8 would produce four requests every tick. An acknowledgement naming THIS head is the
# record that the ask has already been made.
ACK_AT_HEAD="$(body_file \
  '<!-- CodeRabbit review command invocation: v2:abc -->' \
  '✅ Action performed' "Review triggered for $CLEAN_HEAD.")"
setup "$CLEAN_HEAD"; add_comment coderabbitai "$SKIP"; add_comment coderabbitai "$ACK_AT_HEAD"
expect "a skip notice already asked at this head -> hold, not ask again" 1
says   "  ...and says the ask has been made" "ALREADY been asked"

# AND THE HOLD NAMES THE FORM THAT CAN STILL REVIEW THIS HEAD. The ack is the record that
# the one-per-window quota was spent on bare `review`, and the reviewer's own disclaimer —
# carried by every ack it posts, see the fixture — says that form will not re-review. A
# hold that withholds `full review` is the loop this exit was meant to end.
ACK_AT_HEAD_REAL="$(body_file "$(cat "$ACK")" "Review triggered for $CLEAN_HEAD.")"
setup "$CLEAN_HEAD"; add_comment coderabbitai "$SKIP"; add_comment coderabbitai "$ACK_AT_HEAD_REAL"
expect "…the recorded ack at this head -> hold too" 1
says   "  ...and names the command that can review this head" "@coderabbitai full review"

setup "$CLEAN_HEAD"; add_comment coderabbitai "$SKIP"
add_comment coderabbitai "$(body_file \
  '<!-- CodeRabbit review command invocation: v2:abc -->' \
  '✅ Action performed' "Review triggered for $OTHER_SHA.")"
expect "…while an ack for an EARLIER head still asks at this one" 8

# AND THE REAL ACKNOWLEDGEMENT NAMES NO COMMIT AT ALL, so a pin on the body alone is a
# bound that never fires: measured over five real ones (#227 and four on #234), the only
# hex token is a 64-character invocation hash, which `names_head` rejects by design. Left
# there, the skip notice answers 8 on every tick and the caller re-spends the quota every
# tick. The comment's own created_at against the head commit's date is what binds it.
assert "the recorded acknowledgement names no commit at all" \
  "$(yes_if bash -c '! grep -Eqx "[0-9a-fA-F]{7,40}" <<<"$(tr -c "0-9A-Za-z_-" "\n" < "$1")"' _ "$ACK")"
setup "$CLEAN_HEAD" 2026-09-15T00:10:00Z
add_comment coderabbitai "$SKIP"; add_comment_at coderabbitai 2026-09-15T00:11:44Z "$ACK"
expect "a SHA-LESS ack posted at this head -> hold, not ask again every tick" 1
says   "  ...and says the ask has been made" "ALREADY been asked"
setup "$CLEAN_HEAD" 2026-09-15T00:10:00Z
add_comment coderabbitai "$SKIP"; add_comment_at coderabbitai 2026-09-14T23:00:00Z "$ACK"
expect "…while the same ack posted BEFORE this head still asks" 8
# Unknown fails toward the ask, which costs one comment and no round — the PR's commit
# list is not always readable, and a comment the host gave no timestamp is not evidence.
setup "$CLEAN_HEAD"
add_comment coderabbitai "$SKIP"; add_comment_at coderabbitai 2026-09-15T00:11:44Z "$ACK"
expect "…and with no readable head date, the ask stays open" 8
setup "$CLEAN_HEAD" 2026-09-15T00:10:00Z
add_comment coderabbitai "$SKIP"; add_comment_at coderabbitai "not a timestamp" "$ACK"
expect "…as it does for a timestamp that is not one" 8

echo
echo "== the REVIEW OBJECT is preferred over a comment marker =="
# A review object carries `user.login` and `commit_id`; the comment is a single body the
# vendor EDITS in place across rounds, so it names the current head whatever it last read.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
add_review coderabbitai COMMENTED "$OTHER_SHA" "$(body_file '**Actionable comments posted: 1**')"
expect "a marker comment at the head + a review object elsewhere -> stale" 4
says   "  ...naming the commit the review object was made at" "$OTHER_SHA"
says   "  ...and saying the comment was not consulted" "not consulted"

# THE CARVE-OUT THAT MUST SURVIVE: a review with nothing to say creates no review object at
# all (knowledge/findings/a-clean-coderabbit-review-leaves-no-entry-in-the-reviews-api.md),
# so with no object from that account the comment marker is still the evidence.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
expect "…while with no review object at all the marker still clears" 0

# Scoped to the ACCOUNT, not to the PR: another reviewer's object says nothing about this
# one's channel.
setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
add_review sourcery-ai COMMENTED "$OTHER_SHA" "$(body_file 'Sourcery had a look.')"
expect "…and another account's review object does not disarm it" 0

echo
echo "== the AUTHOR's own login never clears, and is now named =="
setup "$CLEAN_HEAD"; AUTHOR="dev"
add_review dev APPROVED "$CLEAN_HEAD" "$(body_file 'Looks good to me.')"
add_review dev COMMENTED "$CLEAN_HEAD" "$EMPTY_BODY"
expect "two of the author's own review objects at the head -> no review" 3
says   "  ...refusing them by name rather than ignoring them" "the PR's OWN"
says   "  ...and citing the clause" "clause 8"

# The same, when the author IS a reviewer account: neither table rescues it.
setup "$CLEAN_HEAD"; AUTHOR="coderabbitai"
add_review coderabbitai APPROVED "$CLEAN_HEAD" "$(body_file 'Fine by me.')"
expect "…and a reviewer account reviewing its own PR clears nothing" 3

echo
echo "== the two recorded PRs: #227 and #228, from the host's own payloads =="
# Recorded API fixtures (tests/fixtures/reviewer/README.md) — the whole of what the host
# served for each PR, so this needs no network. Both cleared at exit 0 before this change,
# and #227's clearance is what produced a MERGE-CLEAR on an unreviewed head.
for rec in 227 228; do
  load_recorded "$FIXTURES/pr$rec.api.json"
  expect_recorded "#$rec at its recorded head -> stale review, not clearance" 4 "$rec"
  says "  ...#$rec: the reviewer's only review object is at an older commit" "is stale"
  says "  ...#$rec: and the incremental-review note is surfaced" "@coderabbitai full review"
done

echo
echo "== NO WIDENING: nothing that refused before now clears =="
# `was` is not a claim about history, it is MEASURED: every row below is run twice, once
# against this script and once against the script as it stood at BASE_SHA, and the two must
# agree about `was`. The rule is one-directional — a shape that refused may never now clear
# — and every shape whose answer DID change must be named in CHANGED, so a widening cannot
# arrive as a quiet edit.
#
# PINNED TO A COMMIT, NOT TO `origin/main`. Once this merges, origin/main IS this script,
# and a baseline that measures itself asserts nothing at all.
BASE_SHA="b6f0901a0a8b55b1b66120c0db785765765b46e1"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BASE=""
if git -C "$REPO" cat-file -e "$BASE_SHA:plugin/scripts/review-clearance.sh" 2>/dev/null; then
  mkdir -p "$TMP/base"
  git -C "$REPO" show "$BASE_SHA:plugin/scripts/review-clearance.sh" > "$TMP/base/review-clearance.sh"
  git -C "$REPO" show "$BASE_SHA:plugin/scripts/bundle-paths.sh"     > "$TMP/base/bundle-paths.sh"
  chmod +x "$TMP/base/review-clearance.sh"
  BASE="$TMP/base/review-clearance.sh"
else
  printf '  SKIP  %-58s\n' "the was column is measured — ${BASE_SHA:0:7} not in this clone"
fi
CHANGED="marker-plus-stale-object ack-plus-marker-plus-stale-object"
build_shape() { # <id> — each leaves the builders holding one input shape
  case "$1" in
    clean-marker-comment) setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN" ;;
    review-object-at-head) setup "$CLEAN_HEAD"
      add_review coderabbitai COMMENTED "$CLEAN_HEAD" "$(body_file 'One nit.')" ;;
    stale-review-object) setup "$CLEAN_HEAD"
      add_review coderabbitai COMMENTED "$OTHER_SHA" "$(body_file 'One nit.')" ;;
    refusal-comment) setup "$REFUSAL_HEAD"; add_comment coderabbitai "$REFUSAL" ;;
    terminal-refusal) setup "$CLEAN_HEAD"
      add_comment coderabbitai "$(body_file 'No credits remaining on this account.')" ;;
    not-yet-placeholder) setup "$CLEAN_HEAD"
      add_comment coderabbitai "$(body_file 'Currently processing new changes in this PR.')" ;;
    empty-commented-at-head) setup "$CLEAN_HEAD"
      add_review coderabbitai COMMENTED "$CLEAN_HEAD" "$EMPTY_BODY" ;;
    no-artifacts) setup "$CLEAN_HEAD" ;;
    ack-only) setup "$CLEAN_HEAD"; add_comment coderabbitai "$ACK" ;;
    author-own-review-at-head) setup "$CLEAN_HEAD"; AUTHOR="dev"
      add_review dev APPROVED "$CLEAN_HEAD" "$(body_file 'Looks good to me.')" ;;
    marker-plus-stale-object) setup "$CLEAN_HEAD"; add_comment coderabbitai "$CLEAN"
      add_review coderabbitai COMMENTED "$OTHER_SHA" "$(body_file 'One nit.')" ;;
    ack-plus-marker-plus-stale-object) setup "$CLEAN_HEAD"
      add_comment coderabbitai "$CLEAN"; add_comment coderabbitai "$ACK"
      add_review coderabbitai COMMENTED "$OTHER_SHA" "$(body_file 'One nit.')" ;;
    *) echo "  FAIL  unknown shape $1"; fail=$((fail+1)); return 1 ;;
  esac
}
# id was now
while read -r id was now; do
  [ -n "$id" ] || continue
  build_shape "$id" || continue
  write_pr
  if [ -n "$BASE" ]; then
    "$BASE" 42 >/dev/null 2>&1; base_rc=$?
    if [ "$base_rc" != "$was" ]; then
      printf '  FAIL  %-58s was=%s claimed, %s measured %s\n' \
        "$id" "$was" "${BASE_SHA:0:7}" "$base_rc"; fail=$((fail+1)); continue
    fi
  fi
  out="$("$SCRIPT" 42 2>&1)"; rc=$?
  if [ "$rc" != "$now" ]; then
    printf '  FAIL  %-58s expected rc=%s got rc=%s\n' "$id" "$now" "$rc"; fail=$((fail+1))
    continue
  fi
  if [ "$was" != 0 ] && [ "$rc" = 0 ]; then
    printf '  FAIL  %-58s refused before (rc=%s) and clears now\n' "$id" "$was"; fail=$((fail+1))
    continue
  fi
  if [ "$was" = 0 ] && [ "$rc" != 0 ] \
     && ! grep -Fq " $id " <<<"$(printf ' %s ' "$CHANGED")"; then
    printf '  FAIL  %-58s cleared before and refuses now, unannounced\n' "$id"; fail=$((fail+1))
    continue
  fi
  printf '  PASS  %-58s (was=%s now=%s)\n' "$id" "$was" "$rc"; pass=$((pass+1))
done <<'SHAPES'
clean-marker-comment              0 0
review-object-at-head             0 0
stale-review-object               4 4
refusal-comment                   1 1
terminal-refusal                  5 5
not-yet-placeholder               1 1
empty-commented-at-head           4 4
no-artifacts                      3 3
ack-only                          4 4
author-own-review-at-head         3 3
marker-plus-stale-object          0 4
ack-plus-marker-plus-stale-object 0 4
SHAPES

# The two REAL inputs, measured the same way. The synthetic shapes above are a model of
# #227 and #228; these are the payloads themselves, and exit 0 here at BASE_SHA is the
# false MERGE-CLEAR the 10:59Z tick acted on. They refuse at exit 4 above.
if [ -n "$BASE" ]; then
  for rec in 227 228; do
    load_recorded "$FIXTURES/pr$rec.api.json"
    "$BASE" "$rec" >/dev/null 2>&1; base_rc=$?
    assert "#$rec did clear at ${BASE_SHA:0:7} (rc=0), so the refusal above is a change" \
      "$([ "$base_rc" -eq 0 ] && echo 0 || echo "1 — measured rc=$base_rc")"
  done
fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
