#!/usr/bin/env bash
#
# review-rounds.test.sh — the two-round cap, at its boundary.
#
# `CONVENTIONS.md` → "TWO ROUNDS, THEN THE HUMAN DECIDES" is the rule that answers this
# bundle's most expensive recorded failure (one pull request, eight review rounds, closed
# unmerged, ~70% of a week's account budget with its siblings). Until `review-rounds.sh`
# it lived in two markdown paragraphs and no code. So what this file has to pin is not
# "the script runs" — it is the ONE transition the cap is:
#
#   0 rounds -> dispatch      1 round -> dispatch      2 rounds -> REFUSE
#
# THE TWO-ROUND CASE WAS RED BEFORE THE GUARD EXISTED, AND THAT IS RECORDED ON PURPOSE.
# A counter that has never refused anything is not known to refuse: this harness was
# committed and run first against no script at all, and then against a counting-only
# script with the cap comparison removed, which counted 2 and exited 0 — this file's
# `2 rounds REFUSES` assertion is the one that failed, alone, while the two counting
# assertions passed. That is the evidence the refusal is what turned it green. This
# repository has shipped tests that passed for the wrong reason; showing red first is
# how this one is not another.
#
# THE FIXTURES ARE THE RECORDED CORPUS, NOT HAND-WRITTEN LOOKALIKES. Both artifact bodies
# come verbatim from tests/fixtures/reviewer/ — the clean review from ai-bridge#29 and the
# rate-limit refusal from #30, the two real bodies that a status check could not tell
# apart. That matters most for the counter: THE REFUSAL NAMES A COMMIT SHA IN ITS OWN
# BODY, at what was its PR's head. A round counter that counts what the artifacts say
# would count it. The `refusal` cases below build a PR whose commit list CONTAINS the
# commit the refusal names, so "count the commits somebody mentioned" and "count the
# commits somebody reviewed" give different answers here, and only the second passes.
#
# WHAT IS ASSERTED, BEYOND THE THREE BOUNDARY CASES:
#   * a refusal, alone, is ZERO rounds — not one (criterion 4's forgery direction);
#   * a refusal alongside a real review of another commit is ONE round, not two;
#   * an EMPTY `COMMENTED` review object is not a round (the host mints one for any
#     inline reply, so counting them would count typing);
#   * an `okf-verdict` trailer inside a FENCED BLOCK is not a round — this repository's
#     own diffs contain that marker and reviewers quote diffs, so a quotation must not be
#     able to spend somebody's rounds;
#   * a real `okf-verdict` trailer from THE PR'S OWN AUTHOR IS a round, because in a
#     single-login instance the fallback verifier posts under the account that opened the
#     PR, and the rounds it spends are exactly the ones this cap is about;
#   * every unreadable input refuses (exit 2), including a missing or non-running
#     `review-clearance.sh` — a sibling that fails every call would otherwise report every
#     PR as zero rounds, which reads as "dispatch another" forever.
#
# `gh` is replaced by a stub on PATH, so the matrix runs offline. `review-rounds.sh` puts
# its own replay shim in front of that stub, which is the point: the stub is the network,
# the shim is the snapshot, and the sibling under both is unmodified.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/plugin/scripts/review-rounds.sh"
FIXTURES="$REPO/tests/fixtures/reviewer"
CLEAN_BODY="$FIXTURES/clean-review.pr29.md"
REFUSAL_BODY="$FIXTURES/rate-limit-refusal.pr30.md"
SKIP_BODY="$FIXTURES/skip-notice.pr229.md"
ACK_BODY="$FIXTURES/ack-invocation.pr227.md"

# The two commits the recorded bodies name as the head they concern, and a third that
# neither mentions. The base SHA the two bodies also name (6fca618…) is deliberately NOT a
# commit of the fixture PR — a base is not something anybody reviewed.
CLEAN_HEAD="8f40f2ed565a31e141f5ae54a6935ad0810314c4"
REFUSAL_HEAD="88c106a8dd2b9ae14e001918022d4909e5357460"
THIRD="1f2e3d4c5b6a798877665544332211aabbccddee"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/review-rounds.XXXXXX")" || {
  echo "review-rounds.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

command -v jq >/dev/null 2>&1 || { echo "jq is required to run this test"; exit 2; }
REAL_JQ="$(command -v jq)"
export FIX="$TMP/fix"
mkdir -p "$TMP/bin"

ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# --- the network -------------------------------------------------------------
# One stub for the four reads the pair makes: the PR record, the PR's commits, the review
# objects and the issue comments. `--jq` is honoured with the real jq, exactly as
# tests/review-clearance.lib.sh does it, so the filters under test are the real ones.
cat > "$TMP/bin/gh" <<STUB
#!/usr/bin/env bash
REAL_JQ="$REAL_JQ"
STUB
cat >> "$TMP/bin/gh" <<'STUB'
case "${1:-} ${2:-}" in
  "pr view")
    [ -f "$FIX/pr_broken" ] && { echo "could not resolve to a PullRequest" >&2; exit 1; }
    cat "$FIX/pr_json"; exit 0 ;;
esac
# THE FIFTH READ: review THREADS, which the sibling asks for over GraphQL because
# `isResolved` exists on no REST endpoint. Routed FIRST — `gh api graphql …` also matches
# the `api` arm below, which would answer it with the COMMITS list and make the sibling
# refuse every commit at exit 2. Default is no threads and no further page, so every case
# written before clause 9 existed keeps asking exactly the question it was written to ask.
if [ "${1:-} ${2:-}" = "api graphql" ]; then
  [ -f "$FIX/threads_json" ] || {
    printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}}\n'
    exit 0; }
  cat "$FIX/threads_json"; exit 0
fi
if [ "${1:-}" = "api" ]; then
  case "${2:-}" in
    */pulls/*/commits*)   src="$FIX/commits_json"; broken="$FIX/commits_broken" ;;
    */pulls/*/reviews*)   src="$FIX/reviews_json"; broken="$FIX/reviews_broken" ;;
    */issues/*/comments*) src="$FIX/comments_json"; broken="$FIX/comments_broken" ;;
    *) echo "stub: unhandled endpoint $2" >&2; exit 99 ;;
  esac
  [ -f "$broken" ] && { echo "gh: Bad gateway (HTTP 502)" >&2; exit 1; }
  filter=""; prev=""
  for a in "$@"; do
    [ "$prev" = "--jq" ] && { filter="$a"; break; }
    prev="$a"
  done
  if [ -n "$filter" ]; then "$REAL_JQ" -r "$filter" "$src"; else cat "$src"; fi
  exit 0
fi
echo "stub: unhandled gh $*" >&2; exit 99
STUB
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

# --- fixture builders ---------------------------------------------------------
COMMITS=""; REVIEWS=""; COMMENTS=""

setup() { # a readable PR 7 in octo/demo, authored by "dev", with no artifacts
  rm -rf "$FIX"; mkdir -p "$FIX"
  COMMITS='[]'; REVIEWS='[]'; COMMENTS='[]'
  printf '%s\n' '{"url":"https://github.com/octo/demo/pull/7","number":7,
                  "headRefOid":"'"$CLEAN_HEAD"'","author":{"login":"dev"}}' \
    > "$FIX/pr_json"
}

commit() { COMMITS="$("$REAL_JQ" --arg s "$1" '. + [{sha:$s}]' <<<"$COMMITS")"; }

comment() { # <login> <body-file>
  COMMENTS="$("$REAL_JQ" --arg l "$1" --rawfile b "$2" \
              '. + [{user:{login:$l}, body:$b}]' <<<"$COMMENTS")"
}

review() { # <login> <state> <commit> <body-file>
  REVIEWS="$("$REAL_JQ" --arg l "$1" --arg s "$2" --arg c "$3" --rawfile b "$4" \
             '. + [{user:{login:$l}, state:$s, commit_id:$c, body:$b}]' <<<"$REVIEWS")"
}

body() { local f; f="$(mktemp "$TMP/body.XXXXXX")"; printf '%s\n' "$@" > "$f"; printf '%s' "$f"; }

commit_fixtures() {
  printf '%s\n' "$COMMITS"  > "$FIX/commits_json"
  printf '%s\n' "$REVIEWS"  > "$FIX/reviews_json"
  printf '%s\n' "$COMMENTS" > "$FIX/comments_json"
}

# run — echoes "<exit> <stdout>" so a case can assert the code and the count together.
run() {
  commit_fixtures
  local out rc
  out="$("$SCRIPT" 7 --repo octo/demo 2>"$TMP/err")"; rc=$?
  printf '%s %s' "$rc" "${out:-<none>}"
}

# A well-formed okf-verdict trailer for <sha>, per SCHEMA.md.
verdict_body() { # <sha> [fenced]
  if [ "${2:-}" = "fenced" ]; then
    body 'Quoting the block this repo ships, in a fenced diff:' \
         '```' \
         '<!-- okf-verdict v1' \
         'verdict: pass' \
         "head_sha: $1" \
         'reviewer: qa-reviewer' \
         'lenses: correctness=done security=done repro=done' \
         'unverified_criteria: none' \
         'caveats: none' \
         '-->' \
         '```'
  else
    body 'Verified against the acceptance criteria; all three lenses ran.' \
         '' \
         '<!-- okf-verdict v1' \
         'verdict: pass' \
         "head_sha: $1" \
         'reviewer: qa-reviewer' \
         'lenses: correctness=done security=done repro=done' \
         'unverified_criteria: none' \
         'caveats: none' \
         '-->'
  fi
}

echo "== the boundary: 0 dispatches, 1 dispatches, 2 REFUSES =="

# 0 — nothing on the PR at all.
setup; commit "$CLEAN_HEAD"; commit "$REFUSAL_HEAD"
ok "0 rounds: an unreviewed PR counts 0 and dispatches" "$(run)" "0 0"

# 0 — a rate-limit REFUSAL, verbatim, on a PR whose commit list contains the very commit
# the refusal's own body names. Counting what artifacts MENTION would say 1 here.
setup; commit "$CLEAN_HEAD"; commit "$REFUSAL_HEAD"
comment "coderabbitai[bot]" "$REFUSAL_BODY"
ok "0 rounds: a recorded refusal is not a round, at the head it names" "$(run)" "0 0"

# 0 — the recorded SKIP NOTICE, which the sibling answers with its new exit 8. Listed
# beside its other refusals there and here: unlisted, 8 lands in the fatal `*` arm and this
# would be "2 <error>" — the round count unreadable and the cap unenforceable on every PR
# of a repo with auto reviews disabled, which is every PR of this one.
setup; commit "$CLEAN_HEAD"; commit "$REFUSAL_HEAD"
comment "coderabbitai[bot]" "$SKIP_BODY"
ok "0 rounds: a skip notice is a refusal, not a round (exit 8)" "$(run)" "0 0"

# 0 — AND THE REMEDY FOR AN 8 IS NOT A ROUND EITHER. `@coderabbitai review` leaves an
# acknowledgement, and a quota-closed window answers it with the rate-limit notice; both
# were on #230 and #232 at 2026-09-15T00:13Z with the count still 0. Asserted here against
# the recorded bodies rather than by re-running that measurement.
setup; commit "$CLEAN_HEAD"; commit "$REFUSAL_HEAD"
comment "coderabbitai[bot]" "$SKIP_BODY"
comment "coderabbitai[bot]" "$ACK_BODY"
comment "coderabbitai[bot]" "$REFUSAL_BODY"
ok "0 rounds: asking, and being rate limited, costs no round" "$(run)" "0 0"

# 1 — the recorded clean review of CLEAN_HEAD, with that same refusal still present.
setup; commit "$CLEAN_HEAD"; commit "$REFUSAL_HEAD"
comment "coderabbitai[bot]" "$REFUSAL_BODY"
comment "coderabbitai[bot]" "$CLEAN_BODY"
ok "1 round: a real review + a refusal of another commit counts 1" "$(run)" "0 1"

# 2 — two reviews the HOST itself pinned, against two different commits, with that same
# refusal still present. Two distinct commits verified ⇒ the cap is reached.
#
# BOTH ROUNDS ARE REVIEW OBJECTS, deliberately: the sibling consults a comment marker only
# for an account with no review object at all, so a route-C round here would be counted or
# not depending on the OTHER round's channel. The cap's own assertion must not turn on that.
setup; commit "$CLEAN_HEAD"; commit "$REFUSAL_HEAD"; commit "$THIRD"
comment "coderabbitai[bot]" "$REFUSAL_BODY"
review "coderabbitai[bot]" "COMMENTED" "$CLEAN_HEAD" \
  "$(body 'One nit on the helper.')"
review "coderabbitai[bot]" "CHANGES_REQUESTED" "$THIRD" \
  "$(body 'Two findings on the new guard; see the inline comments.')"
ok "2 rounds REFUSES — the cap, and the whole point of this file" "$(run)" "1 2"

# THE FLOOR, NAMED. The same two rounds where the newer one arrived as the vendor's edited
# summary comment count ONE, because that account has a review object and the sibling then
# decides from the structured channel alone. One low, one extra dispatch — the direction
# the header commits to, pinned here so it cannot drift to one HIGH unnoticed.
setup; commit "$CLEAN_HEAD"; commit "$REFUSAL_HEAD"; commit "$THIRD"
comment "coderabbitai[bot]" "$CLEAN_BODY"
review "coderabbitai[bot]" "CHANGES_REQUESTED" "$THIRD" \
  "$(body 'Two findings on the new guard; see the inline comments.')"
ok "a route-C round is invisible once that account has a review object" "$(run)" "0 1"

echo
echo "== what may not become a round =="

# One review, two artifacts. A single review run routinely leaves a summary comment AND a
# review object; counting artifacts would refuse the second dispatch after the first
# review. Rounds are distinct COMMITS.
setup; commit "$CLEAN_HEAD"; commit "$REFUSAL_HEAD"
comment "coderabbitai[bot]" "$CLEAN_BODY"
review "coderabbitai[bot]" "COMMENTED" "$CLEAN_HEAD" \
  "$(body 'No actionable comments; details in the summary above.')"
ok "two artifacts for ONE commit are one round, not two" "$(run)" "0 1"

# An empty COMMENTED object is what the host mints for any inline reply. The round it must
# not become a second of is a review object too, for the reason given at the cap above.
setup; commit "$CLEAN_HEAD"; commit "$REFUSAL_HEAD"; commit "$THIRD"
review "coderabbitai[bot]" "COMMENTED" "$CLEAN_HEAD" "$(body 'One nit on the helper.')"
review "coderabbitai[bot]" "COMMENTED" "$THIRD" "$(body '')"
ok "an empty COMMENTED review object is not a round" "$(run)" "0 1"

# A stale review of a commit that is no longer the head is still a round that HAPPENED.
setup; commit "$CLEAN_HEAD"; commit "$REFUSAL_HEAD"
comment "coderabbitai[bot]" "$CLEAN_BODY"
ok "a round at an older commit still counts (the head has moved on)" "$(run)" "0 1"

# THE FLOOR, PINNED IN BOTH DIRECTIONS. A round evidenced only by an issue comment is
# attributed through the commit its body names, so a force-push that orphans that commit
# loses it — the count reads one LOW. That is a stated limit, not an oversight: the REST
# timeline publishes no record of the orphaned commit (measured on ai-bridge#34), and the
# one workaround available — treating body-mentioned SHAs as candidates — would also admit
# the BASE commit that every review comment names in its `between <base> and <head>` line.
# The second case here is the one that makes that concrete: it is the recorded clean
# review, and if body-mentioned SHAs ever became candidates it would count TWO.
setup; commit "$REFUSAL_HEAD"   # CLEAN_HEAD force-pushed away; the comment survives
comment "coderabbitai[bot]" "$CLEAN_BODY"
ok "a comment-only round at an orphaned commit reads one LOW (stated floor)" "$(run)" "0 0"

setup; commit "$CLEAN_HEAD"
comment "coderabbitai[bot]" "$CLEAN_BODY"
ok "…and the base SHA that same body names is never a second round" "$(run)" "0 1"

echo
echo "== the fallback verifier, and its trailer =="

# The qa-reviewer posts under the account that opened the PR in a single-login instance.
# SCHEMA.md clause 8 makes that invisible to a CLEARANCE check, correctly; a round counter
# that inherited it would miss the rounds the cap is mostly about.
setup; commit "$CLEAN_HEAD"; commit "$THIRD"
comment "dev" "$(verdict_body "$THIRD")"
ok "an okf-verdict trailer from the PR author IS a round" "$(run)" "0 1"

# …and it is a SECOND round on top of an external review of another commit.
setup; commit "$CLEAN_HEAD"; commit "$THIRD"
comment "coderabbitai[bot]" "$CLEAN_BODY"
comment "dev" "$(verdict_body "$THIRD")"
ok "external round + fallback verdict = 2 rounds, and REFUSES" "$(run)" "1 2"

# The marker is in this repository's own diffs, and reviewers quote diffs. A quotation
# must not be able to spend somebody's rounds — the sibling parses the STRICT rendering,
# with fenced blocks removed, which is what stops this.
setup; commit "$CLEAN_HEAD"; commit "$THIRD"
comment "dev" "$(verdict_body "$THIRD" fenced)"
ok "a trailer quoted inside a fenced block is not a round" "$(run)" "0 0"

# A trailer naming a commit that is not on this PR pins nothing the host vouched for.
setup; commit "$CLEAN_HEAD"; commit "$THIRD"
comment "dev" "$(verdict_body "0000000000000000000000000000000000000000")"
ok "a trailer naming a commit not on the PR is not a round" "$(run)" "0 0"

echo
echo "== unknown never reads as 'go ahead' =="

setup; commit "$CLEAN_HEAD"; commit_fixtures; : > "$FIX/pr_broken"
out="$("$SCRIPT" 7 --repo octo/demo 2>/dev/null)"; rc=$?
ok "an unreadable PR refuses (exit 2)" "$rc" "2"

setup; commit "$CLEAN_HEAD"; commit_fixtures; : > "$FIX/commits_broken"
out="$("$SCRIPT" 7 --repo octo/demo 2>/dev/null)"; rc=$?
ok "an unreadable commit list refuses (exit 2)" "$rc" "2"

setup; commit "$CLEAN_HEAD"; commit_fixtures; : > "$FIX/comments_broken"
out="$("$SCRIPT" 7 --repo octo/demo 2>/dev/null)"; rc=$?
ok "an unreadable comment list refuses (exit 2)" "$rc" "2"

out="$("$SCRIPT" 2>/dev/null)"; rc=$?
ok "no PR argument refuses (exit 2)" "$rc" "2"

# A sibling that is absent, and one that is present but does not run. Both would otherwise
# answer 'not a review' to every candidate — every PR zero rounds, the cap gone rather
# than failing.
ALONE="$TMP/alone"; mkdir -p "$ALONE"
cp "$SCRIPT" "$ALONE/review-rounds.sh" 2>/dev/null
setup; commit "$CLEAN_HEAD"; commit_fixtures
if [ -f "$ALONE/review-rounds.sh" ]; then
  out="$("$ALONE/review-rounds.sh" 7 --repo octo/demo 2>"$TMP/err2")"; rc=$?
else rc="no-script"; fi
ok "a missing review-clearance.sh refuses (exit 2)" "$rc" "2"

printf '#!/usr/bin/env bash\nexit 1\n' > "$ALONE/review-clearance.sh"
chmod +x "$ALONE/review-clearance.sh"
if [ -f "$ALONE/review-rounds.sh" ]; then
  out="$("$ALONE/review-rounds.sh" 7 --repo octo/demo 2>"$TMP/err2")"; rc=$?
else rc="no-script"; fi
ok "a review-clearance.sh that does not run refuses (exit 2)" "$rc" "2"

echo
echo "== the sibling's exit 6 is a ROUND, and this is the arm that would have been fatal =="
# ADDING AN EXIT CODE TO THE SIBLING IS A THREE-PART CHANGE AND THIS IS THE THIRD PART.
# `review-clearance.sh` answers 6 when a review DID complete at that commit and SCHEMA.md
# clause 9 then refused it — a reviewer-authored thread is still unresolved. Two things had
# to be got right here and both fail silently:
#
#   * 6 MUST BE ON THE LIST AT ALL. The `case` below it ends in a FATAL `*`, so an
#     unlisted code turns "there is an open thread" into "the number of rounds is unknown"
#     and refuses on every PR that has one.
#   * 6 MUST COUNT AS A ROUND, not be listed beside the refusals. A round happened; what is
#     outstanding is the implementer's reply. Counting it 0 reports "no review yet" for a
#     PR that has one, and this file's callers answer that by dispatching a verifier — the
#     deep-tier session the two-round cap exists to stop.
#
# Same fixture as the "1 round" case above, so the ONLY difference is the open thread.
threads() { # <isResolved>
  "$REAL_JQ" -n --argjson r "$1" \
    '{data:{repository:{pullRequest:{reviewThreads:{pageInfo:{hasNextPage:false},
       nodes:[{isResolved:$r, path:"a.sh", line:1,
               comments:{nodes:[{author:{login:"coderabbitai"},
                                 url:"https://example.invalid/t/1", body:"open"}]}}]}}}}}' \
    > "$FIX/threads_json"
}
setup; commit "$CLEAN_HEAD"; commit "$REFUSAL_HEAD"
comment "coderabbitai[bot]" "$REFUSAL_BODY"
comment "coderabbitai[bot]" "$CLEAN_BODY"
commit_fixtures; threads false
ok "a completed review with an UNRESOLVED thread still counts as 1 round" "$(run)" "0 1"
# The control: the identical fixture with the thread resolved counts the same 1. Without
# this the assertion above would also pass on a file that ignored thread state entirely.
setup; commit "$CLEAN_HEAD"; commit "$REFUSAL_HEAD"
comment "coderabbitai[bot]" "$REFUSAL_BODY"
comment "coderabbitai[bot]" "$CLEAN_BODY"
commit_fixtures; threads true
ok "...and the same fixture with it RESOLVED counts the same 1" "$(run)" "0 1"

echo
echo "== the wiring, so refusing is mechanical rather than remembered =="

# The cap is prose in CONVENTIONS.md and in two agent documents. What this pins is that
# the two dispatch paths NAME the script: an agent that is merely told a rule follows it
# when it remembers to, which is the failure this whole task exists to close.
has() { grep -q "review-rounds.sh" "$1" && echo 0 || echo 1; }
ok "CONVENTIONS.md names the script"  "$(has "$REPO/plugin/seed/CONVENTIONS.md")" "0"
ok "qa-reviewer.md names the script"  "$(has "$REPO/plugin/agents/qa-reviewer.md")" "0"
ok "the tick's step 4 names it"       "$(has "$REPO/plugin/tick-steps/step-4-advance.md")" "0"

# The cap is a HARD number: CONVENTIONS.md says so, and a flag is how a hard cap becomes a
# default. If someone adds one, this fails and they have to argue for it in review. Comment
# lines are excluded — the script's header discusses the flag it deliberately does not have,
# and a scanner that could not tell prose from code would forbid saying so.
ok "the cap is not configurable from the command line" \
   "$(grep -qE -- '--cap' <<<"$(grep -vE '^[[:space:]]*#' "$SCRIPT")" && echo 1 || echo 0)" "0"


# A ROUND COUNT IS A QUESTION ABOUT THE PAST, so the sibling's mergeability check is
# suppressed here. The guard is the FIXTURE above, which reports no `mergeable` at all:
# drop `--no-merge-check` from either call site and the sibling answers exit 2 (unknown
# state) for every candidate, which is its fatal `*` arm — so every counting case in this
# file goes red rather than one assertion. This pins the call sites as well, because the
# reason is not visible from a passing count.
ok "both call sites suppress the sibling's merge check" \
   "$(grep -vE '^[[:space:]]*#' "$SCRIPT" | grep -c -- '--no-merge-check')" "2"
ok "…and the fixture PR reports no mergeability, so it is the guard" \
   "$(grep -c 'mergeable' "$FIX/pr_json")" "0"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
