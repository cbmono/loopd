#!/usr/bin/env bash
#
# review-clearance-gates.test.sh — the modes, the tables and the gates AROUND the
# classifier in plugin/scripts/review-clearance.sh: `--match-check`, `--self-test` and the
# completeness sentinel, a table that does not compile, `--for-check`, a failing
# environment, SCHEMA.md clause 9, mergeability and `--record`, acknowledgements and skip
# notices, the two recorded PRs, and the no-widening sweep against a pinned base.
#
# ONE OF THREE. tests/review-clearance.test.sh holds the recorded evidence and the header
# that says what all three exist to pin; tests/review-clearance-bodies.test.sh holds the
# hand-built bodies. The stubs, the fixture builders and the assertion helpers are sourced
# from tests/review-clearance.lib.sh.
. "$(dirname "$0")/review-clearance.lib.sh"

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
