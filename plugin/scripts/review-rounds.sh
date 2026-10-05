#!/usr/bin/env bash
#
# review-rounds.sh — how many verification rounds has this pull request already had, and
# may another verifier be dispatched against it?
#
#   Usage: review-rounds.sh <pr> [--repo <owner>/<name>]
#
# This is the mechanism behind `CONVENTIONS.md` → "TWO ROUNDS, THEN THE HUMAN DECIDES".
# That cap answers the most expensive failure this bundle has recorded — one pull request
# ran EIGHT review rounds, was closed unmerged, and with its siblings consumed roughly 70%
# of a week's account budget — and until this file existed the cap lived in two markdown
# paragraphs and nothing counted anything. An agent that did not follow it was not stopped;
# it was merely out of compliance with a document. Prose without a mechanism has failed
# three times in this bundle's own history, which is why the rule now has a number a
# dispatcher can read.
#
# WHAT A ROUND IS. One completed verification of one commit of this PR. Not "an artifact":
# a single review run routinely leaves two artifacts (a review object AND a summary
# comment), and counting artifacts would refuse the second dispatch after the first review.
# So rounds are counted as DISTINCT COMMITS at which a verification completed, which is
# also what the cap means operationally — the implementer pushes, a verifier reads that
# push, and that is one round.
#
# WHAT IT ANCHORS ON, AND WHY A REVIEWER THAT DID NOT REVIEW CANNOT ADD TO IT. Two halves,
# and neither is this file's own opinion:
#
#   1. THE CANDIDATE COMMITS COME FROM THE HOST. `/repos/{o}/{r}/pulls/{n}/commits` (the
#      commits GitHub says are on this PR) and the `commit_id` GitHub stamps on every
#      review object. Nothing an artifact's TEXT says can add a candidate — which matters
#      because the recorded rate-limit refusal names a commit SHA in its own body, at the
#      PR's own head (see `review-clearance.sh`, "THE TRAP"). A body cannot nominate the
#      commit it is then counted at.
#   2. WHETHER A CANDIDATE COUNTS IS DECIDED BY `review-clearance.sh`, UNMODIFIED. That
#      file is this bundle's answer to "is this a real review or a refusal" — four refusal
#      tiers classified BEFORE any pin is consulted, evidence taken from the reviews API,
#      pinned by `state`+`commit_id`, and a recorded corpus of the two real bodies that
#      look alike. Re-deriving that judgement here would mean shipping a second, weaker
#      copy of it, which is precisely the bug the cap exists to bound: a refusal and a
#      clean review were INDISTINGUISHABLE to automation, and eight rounds followed.
#
# So: an ABSENT reviewer publishes no artifact and adds no round. A RATE-LIMITED reviewer
# publishes a refusal — a green check and a comment saying it skipped — and that artifact
# is classified as a refusal by the sibling's TEST 1 before any commit is pinned, so it
# adds no round either. A round can only be added by an artifact carrying the reviewer's
# own machine-emitted review evidence, a submitted review object the HOST pinned to a
# commit, or a parsed `okf-verdict v1` block. None of those is something a reviewer that
# did not review emits.
#
# HOW THE SIBLING IS ASKED ABOUT A COMMIT THAT IS NOT THE HEAD. `review-clearance.sh`
# answers one question — "is there a completed review of THIS PR's CURRENT HEAD" — and it
# is right to: a merge gate must never clear on a review of an older commit. Counting is
# the other question, over the same evidence, so this script REPLAYS the sibling once per
# candidate commit: every artifact is fetched ONCE, and the sibling then runs offline
# against that fixed snapshot with the PR's head field set to the candidate. The injection
# point is the `gh` boundary — the same boundary `tests/review-clearance.test.sh` already
# drives the sibling through, with the same shape of stub. Nothing about the classifier,
# the tables, the renderers or the ranking is touched or re-implemented, and if the sibling
# gets stricter tomorrow this file gets stricter with it.
#
# WHOSE ROUNDS ARE COUNTED — the two verifiers this loop actually pays for:
#
#   * THE EXTERNAL REVIEWER, via a plain `review-clearance.sh <pr>` run per candidate,
#     which scopes to the vendor accounts in the sibling's own REVIEWERS table.
#   * THE FALLBACK VERIFIER (`qa-reviewer`), which SCHEMA.md requires to end its verdict
#     with an `okf-verdict v1` trailer, via `review-clearance.sh <pr> --reviewer <login>`
#     per candidate — the sibling's route B. The candidate logins are the accounts that
#     published an artifact whose raw body contains the literal `okf-verdict`. THAT
#     PRE-FILTER ONLY EVER NARROWS: containing the string is a NECESSARY condition for a
#     trailer and nowhere near a sufficient one (this repository's own diffs contain it,
#     and reviewers quote diffs), so the string can skip an account that provably has no
#     trailer and can never turn a quotation into a round. The sufficient judgement stays
#     where it is — the sibling parses the block from a STRICT rendering with fenced and
#     indented blocks removed, which is what stops a quoted trailer counting.
#
# THE COUNT IS A FLOOR, AND HERE IS EXACTLY WHERE IT LOSES A ROUND. A round evidenced ONLY
# by an issue comment (route C) has no host-assigned pin — there is no `commit_id` on a
# comment anywhere in the API — so it is attributed through the commit its body names, and
# it is countable only while that commit is still one the host lists. Three things erode
# that: a force-push can orphan the commit; the vendor keeps ONE summary comment per PR and
# EDITS it, naming only the latest range it read; and the sibling consults route C only for
# an account with NO review object, so one object silences that account's comment. Each
# costs the SAME one round — route C is worth at most one, ever — so the floor is unchanged.
#
# NEITHER IS FIXABLE FROM WHAT THE HOST PUBLISHES, and this was measured rather than
# assumed, on ai-bridge#34 (29 commits, 2 recorded force-pushes): the REST timeline's
# `head_ref_force_pushed` events carry only the commit AFTER each push — both were still
# in the commit list — and its `committed` events reproduce the current commit list exactly
# (29 and 29, zero extra). There is no record of the orphaned commit to recover.
#
# AND THE OBVIOUS WORKAROUND IS THE FORGERY THIS FILE EXISTS TO REFUSE. Adding
# body-mentioned SHAs as candidates would recover the orphan — and would also add the BASE
# commit, which every one of the vendor's review comments names in its `between <base> and
# <head>` line. Measured against the recorded corpus, that turns #29 from one round into
# two: a phantom round on every reviewed PR, from text anyone can write. So the residual
# stays, stated: the count can be one LOW, which costs one extra dispatch, and it cannot be
# one HIGH from anything an artifact says. Under-counting is not free — it is simply the
# only direction available here, and it is the cheaper one.
#
# An ordinary human comment is not a round and is not counted: the cap bounds what the loop
# DISPATCHES, and a colleague reading the PR costs that budget nothing. The honest edge is
# that a human who QUOTES an `okf-verdict` block passes the pre-filter, and a contentful
# review object from that account at a candidate commit then counts. That is an over-count
# by one, it takes a human deliberately pasting the marker, and it errs toward asking the
# human — which is where the cap sends everything anyway.
#
# CLAUSE 8 IS MASKED FOR THE FALLBACK RUNS, DELIBERATELY, AND ONLY FOR THOSE. SCHEMA.md
# clause 8 — an author is never its own independent reviewer — makes `review-clearance.sh`
# refuse outright when `--reviewer` names the PR's own author. That is correct for
# CLEARANCE and wrong for COUNTING: in a single-login instance the fallback verifier posts
# under the same account that opened the PR (`qa-reviewer.md` says so in as many words),
# so honouring clause 8 here would make the fallback verifier's rounds INVISIBLE — missing
# exactly the rounds this cap exists to bound. So the replayed PR record carries an author
# login no account can hold, for the `--reviewer` runs only. The vendor run keeps clause 8
# untouched.
#
# THE MASK'S BLAST RADIUS IS ONE CASE, not "clause 8 is off". A `--reviewer` run already
# considers only artifacts from that one login, so the author-exclusion it disables can
# only ever have applied when the named account IS the author. Every other run is
# unaffected by construction, not by care.
#
#   THIS SCRIPT CLEARS NOTHING AND MUST NEVER BE READ AS CLEARANCE. Exit 0 here means "the
#   cap has room", never "this PR was reviewed". The merge gate is `required-checks.sh` +
#   `review-clearance.sh`, unchanged and unaffected by anything in this file.
#
# THE CAP IS NOT CONFIGURABLE, and that is the point of it being a hard number:
# `CONVENTIONS.md` calls it "a hard cap", and a `--cap` flag is how a hard cap becomes a
# default. Two.
#
# BROKEN OR ABSENT FAILS CLOSED BY CONSTRUCTION. Both callers (`project-manager.md`'s
# verification step and `qa-reviewer.md` mode B) are told to refuse on ANY non-zero exit,
# never on exit 1 alone, so a missing file (exit 127), an unreadable
# PR, an unauthenticated `gh` or a sibling that does not run all reach the dispatcher as
# "do not dispatch". The expensive direction is a third round nobody stopped; the cheap one
# is a human being asked.
#
# GENERIC PLUGIN FILE — ships inside the `loopd` plugin; nothing to edit per
# instance. It takes no org, repo or reviewer identity: those come from the arguments and
# from the sibling's tables.
#
# Exit codes:
#
#   0  UNDER THE CAP — fewer than 2 rounds. The count is on stdout. Dispatch away.
#   1  AT OR PAST THE CAP — 2 or more rounds. The count is on stdout. Do NOT dispatch a
#      third verifier: stop, and put both positions in front of the human.
#   2  cannot answer — usage, no `gh`/`jq`, a sibling that is missing or does not run, an
#      unreadable PR, or an artifact list that did not come back. Unknown is never "fine".
#
# WHAT IT PRINTS. stdout is the round count and nothing else, so a caller can read it with
# `$(...)`. Everything a human reads is on stderr. No PR text is echoed — the sibling
# already quotes untrusted bodies where that is useful, and this file has no reason to.
#
# Verified by tests/review-rounds.test.sh.
#
# No `set -e`: a `grep` that finds nothing and a sibling that exits 4 are both ANSWERS
# here, not faults. Every failure path is explicit.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

CAP=2

usage() {
  echo "Usage: $(basename "$0") <pr> [--repo <owner>/<name>]" >&2
  echo "       exit 0 under the cap, 1 at or past it, 2 cannot answer" >&2
  exit 2
}

pr=""; repo=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)    repo="${2:-}"; [ -n "$repo" ] || usage; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) [ -z "$pr" ] || { echo "error: unexpected argument '$1'" >&2; usage; }
       pr="$1"; shift ;;
  esac
done
[ -n "$pr" ] || usage

for tool in gh jq; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "error: $tool not found — the rounds already spent cannot be read, and an" >&2
    echo "       unknown count is not permission to dispatch. Refusing." >&2
    exit 2
  }
done

# --- the sibling, and the proof that it runs ---------------------------------
# Same contract `required-checks.sh` uses on the same file, for the same reason and with
# the expected string spelled out rather than sourced: a present-but-broken sibling would
# answer "not a review" to every candidate, every PR would read as zero rounds, and the cap
# would not fail — it would DISAPPEAR. `[ -x ]` cannot see that; `--self-test` can.
CLEARANCE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)/review-clearance.sh"
# selftest_ok — see required-checks.sh, where this function is explained; the two copies are
# kept identical, because a shared file would have to be sourced before anything proved it runs.
selftest_ok() {
  local s="$1" want="$2" key dir got
  dir="${TMPDIR:-/tmp}/loopd-selftest.$(id -u)"
  key="$(cksum < "$s" 2>/dev/null)"; key="${key// /-}"
  if [ -n "$key" ] && [ -f "$dir/${s##*/}.$key" ]; then
    got=""; IFS= read -r got < "$dir/${s##*/}.$key" 2>/dev/null || true
    [ "$got" = "$want" ] && return 0
  fi
  if got="$("$s" --self-test 2>/dev/null)"; then :; else got=""; fi
  [ "$got" = "$want" ] || return 1
  [ -n "$key" ] && mkdir -p "$dir" 2>/dev/null && chmod 700 "$dir" 2>/dev/null \
    && printf '%s\n' "$want" > "$dir/${s##*/}.$key" 2>/dev/null
  return 0
}
CLEARANCE_SELFTEST_OK="review-clearance: self-test ok"
if [ ! -f "$CLEARANCE" ]; then
  echo "error: review-clearance.sh not found beside this script ($CLEARANCE)." >&2
  echo "       It is what decides whether an artifact is a review or a refusal, so" >&2
  echo "       without it no round can be counted. Refusing (fail closed)." >&2
  exit 2
fi
if ! selftest_ok "$CLEARANCE" "$CLEARANCE_SELFTEST_OK"; then
  echo "error: review-clearance.sh is present but does not run ($CLEARANCE)." >&2
  echo "       Its --self-test did not answer '$CLEARANCE_SELFTEST_OK'. A sibling that" >&2
  echo "       fails every invocation reports every PR as zero rounds, which reads as" >&2
  echo "       'dispatch another one' forever. Refusing (fail closed)." >&2
  exit 2
fi

TMPD="$(mktemp -d)" || {
  echo "error: could not create a temp dir — refusing (fail closed)" >&2
  exit 2
}
trap 'rm -rf "$TMPD"' EXIT

R=()
[ -n "$repo" ] && R=(--repo "$repo")

# --- the PR, once -------------------------------------------------------------
raw="$(gh pr view "$pr" ${R[@]+"${R[@]}"} \
       --json url,number,headRefOid,author 2>/dev/null)" || {
  echo "error: could not read PR $pr${repo:+ in $repo} — refusing (fail closed)" >&2
  exit 2
}
meta="$(printf '%s' "$raw" \
        | jq -r '[.url, (.number // "" | tostring)] | @tsv' 2>/dev/null)" || meta=""
url="$(printf '%s' "$meta" | cut -f1)"
num="$(printf '%s' "$meta" | cut -f2)"
nwo="$(printf '%s' "$url" | sed -E 's#^https?://[^/]+/([^/]+/[^/]+)/pull/[0-9]+.*#\1#')"
[ -n "$url" ] && [ -n "$num" ] && [ "$nwo" != "$url" ] || {
  echo "error: could not resolve the repo / number of PR $pr — refusing (fail closed)" >&2
  exit 2
}

# --- the candidate commits, from the host and only from the host --------------
# The PR's own commits, plus the commit each review object was stamped against. The second
# source is not redundancy: a force-push rewrites the branch, and a commit an earlier round
# WAS reviewed at can leave the commit list entirely. Dropping it would under-count exactly
# the PRs that have been through the most rounds. Both are host-assigned; neither is
# anything a body says. (The commits endpoint answers at most 250 for a very long PR —
# under-counting there is a host limit, not a judgement, and it is stated rather than
# hidden.)
gh api "/repos/$nwo/pulls/$num/commits?per_page=100" --paginate \
  --jq '.[].sha // empty' > "$TMPD/candidates" 2>/dev/null || {
  echo "error: could not read the commits of PR $pr ($nwo) — refusing. Which commits" >&2
  echo "       could have been reviewed is unknown, and unknown is not zero rounds." >&2
  exit 2
}
gh api "/repos/$nwo/pulls/$num/reviews?per_page=100" --paginate \
  --jq '.[].commit_id // empty' >> "$TMPD/candidates" 2>/dev/null || {
  echo "error: could not read the review objects of PR $pr ($nwo) — refusing." >&2
  exit 2
}
grep -Ex '[0-9a-f]{40}' "$TMPD/candidates" | sort -u > "$TMPD/commits"
[ -s "$TMPD/commits" ] || {
  echo "error: PR $pr ($nwo) reports no commits at all, so there is nothing a review" >&2
  echo "       could have been of. That is not an answer — refusing (fail closed)." >&2
  exit 2
}

# --- which accounts could hold a fallback verdict -----------------------------
# Narrowing only — see the header. An account whose every artifact lacks the literal
# `okf-verdict` cannot own a parseable trailer, so it need not be replayed; an account that
# has the literal still has to get its block past the sibling's parser.
{
  gh api "/repos/$nwo/pulls/$num/reviews?per_page=100" --paginate \
    --jq '.[] | select((.body // "") | contains("okf-verdict")) | .user.login // empty' \
    2>/dev/null || echo "__unreadable__"
  gh api "/repos/$nwo/issues/$num/comments?per_page=100" --paginate \
    --jq '.[] | select((.body // "") | contains("okf-verdict")) | .user.login // empty' \
    2>/dev/null || echo "__unreadable__"
} > "$TMPD/verdict-logins-raw"
if grep -qx '__unreadable__' "$TMPD/verdict-logins-raw"; then
  echo "error: could not read the artifacts on PR $pr ($nwo) — refusing. A verdict this" >&2
  echo "       script cannot see is a round it does not count, and an uncounted round" >&2
  echo "       is the third dispatch the cap exists to stop." >&2
  exit 2
fi
# A login is one token by GitHub's own rules (alphanumerics and hyphens); anything else is
# not a login this script will hand to `--reviewer`.
grep -Ex '[A-Za-z0-9][A-Za-z0-9-]{0,38}(\[bot\])?' "$TMPD/verdict-logins-raw" \
  | sort -u > "$TMPD/verdict-logins"

# --- the replay boundary ------------------------------------------------------
# A `gh` that answers from a snapshot instead of the network, so the sibling can be run
# once per candidate commit without re-fetching anything and without seeing a moving PR.
#
# IT IS A CACHE KEYED ON THE EXACT ARGV, NOT A SIMULATOR. The first call with a given
# argument vector goes to the real `gh` and its stdout is stored; every later call with
# the SAME vector is served from that store. So this makes no assumptions about which
# endpoints the sibling reads or how it reads them — a sibling that starts asking for
# something new simply gets a live answer for it. Comparison is byte-exact over the
# NUL-joined vector: no hashing, so no collision can serve one call another's answer.
#
# ONE FIELD IS REWRITTEN, AND ONLY ON THE PR RECORD: `headRefOid`, to the candidate commit
# this replay is about (`OKF_ROUNDS_HEAD`), and `author.login` to an impossible value when
# `OKF_ROUNDS_MASK_AUTHOR` is set (see the clause-8 note in the header). Artifact bodies,
# review states and commit ids are served untouched — the evidence is never edited, only
# the question is.
#
# A REAL `gh` THAT FAILS IS NOT CACHED and its status is passed straight through, so a 502
# on the first candidate reaches the sibling as a failed fetch (its exit 2) and this script
# refuses, rather than every later candidate being served an empty file as though the PR
# had no artifacts.
BIN="$TMPD/bin"; mkdir -p "$BIN" "$TMPD/cache"
GH_REAL="$(command -v gh)"
cat > "$BIN/gh" <<EOF
#!/usr/bin/env bash
GH_REAL="$GH_REAL"
JQ_REAL="$(command -v jq)"
CACHE="$TMPD/cache"
EOF
cat >> "$BIN/gh" <<'EOF'
set -uo pipefail
want="$CACHE/want.$$"
printf '%s\0' "$@" > "$want"
hit=""; n=0
while [ -f "$CACHE/argv.$n" ]; do
  if cmp -s "$CACHE/argv.$n" "$want"; then hit="$n"; break; fi
  n=$((n + 1))
done
if [ -z "$hit" ]; then
  if "$GH_REAL" "$@" > "$CACHE/out.$n" 2>"$CACHE/err.$n"; then
    mv "$want" "$CACHE/argv.$n"; hit="$n"
  else
    rc=$?; cat "$CACHE/err.$n" >&2; rm -f "$want" "$CACHE/out.$n" "$CACHE/err.$n"
    exit "$rc"
  fi
else
  rm -f "$want"
fi
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  filter='.headRefOid = $h'
  [ -n "${OKF_ROUNDS_MASK_AUTHOR:-}" ] && filter="$filter | .author = {login: \$m}"
  "$JQ_REAL" --arg h "${OKF_ROUNDS_HEAD:-}" \
             --arg m "${OKF_ROUNDS_MASK_AUTHOR:-}" "$filter" "$CACHE/out.$hit"
  exit $?
fi
cat "$CACHE/out.$hit"
EOF
chmod +x "$BIN/gh" || {
  echo "error: could not prepare the replay boundary — refusing (fail closed)" >&2
  exit 2
}

# The impossible author: GitHub logins are alphanumerics and hyphens, so nothing with a
# slash in it can ever equal one, and the sibling's own guard (an empty author refuses)
# still sees a non-empty value.
MASK="okf-rounds/not-an-account"

# --- count -------------------------------------------------------------------
# One replay per (candidate commit x verifier identity). Nothing is decided here: each
# answer is the sibling's own exit code, and only its exit 0 adds a round. Its exit 2 is
# UNKNOWN REVIEWER STATE and stops the count outright — a PR whose artifacts cannot be
# classified has an unknown number of rounds, and unknown is not permission to spend
# another one.
rounds=0
: > "$TMPD/counted"
while IFS= read -r sha; do
  [ -n "$sha" ] || continue
  counted=""

  # `--no-merge-check`: a conflict today does not un-happen a review at commit X. Left on,
  # exit 7 lands in the `*` arm and "this PR conflicts" becomes "the rounds are unknown".
  OKF_ROUNDS_HEAD="$sha" PATH="$BIN:$PATH" \
    "$CLEARANCE" "$pr" ${R[@]+"${R[@]}"} --no-merge-check >/dev/null 2>&1
  rc=$?
  # 5 AND 8 ARE REFUSALS, LISTED HERE BESIDE THE OTHERS BECAUSE OMITTING EITHER IS A LIVE
  # BUG, NOT A CONSERVATIVE DEFAULT. The sibling splits its refusal into transient (1),
  # terminal (5) and skipped-because-nobody-asked (8); NO round happened at that commit in
  # any of them, which is exactly what 1, 3 and 4 already mean here. Left off this list, a
  # reviewer out of credits — or the skip notice every PR carries where auto reviews are
  # disabled — lands in the `*` arm, and "the reviewer did not review" reads as "the round
  # count is unknown", refusing the count and unenforcing the cap on every one of them.
  # 6 IS A ROUND, AND IT IS THE ONE CODE ON THIS LIST THAT COUNTS AS ONE. The sibling
  # answers 6 when a review DID complete at that commit and SCHEMA.md clause 9 then refused
  # it — a reviewer-authored thread is still unresolved. A round happened; what is
  # outstanding is the implementer's reply to it. Counting it as 0 would report "no review
  # yet" for a PR that has one, and this file's callers answer that by dispatching a
  # verifier: the exact deep-tier session the two-round cap exists to stop. And omitting 6
  # from this list entirely is worse than either, because it lands in the `*` arm below and
  # turns "there is an open thread" into "the round count is unknown" on every PR that has
  # one. This is why adding an exit code to the sibling is a three-part change.
  case "$rc" in
    0|6) counted=yes ;;
    1|3|4|5|8) ;;
    *) echo "error: review-clearance.sh exited $rc for PR $pr at $sha, which is neither" >&2
       echo "       a clearance nor one of its refusals. The reviewer state is unknown," >&2
       echo "       so the number of rounds is unknown. Refusing (fail closed)." >&2
       exit 2 ;;
  esac

  if [ -z "$counted" ]; then
    while IFS= read -r login; do
      [ -n "$login" ] || continue
      OKF_ROUNDS_HEAD="$sha" OKF_ROUNDS_MASK_AUTHOR="$MASK" PATH="$BIN:$PATH" \
        "$CLEARANCE" "$pr" ${R[@]+"${R[@]}"} --reviewer "$login" --no-merge-check \
          >/dev/null 2>&1
      rc=$?
      case "$rc" in
        0|6) counted=yes; break ;;   # a completed round, clause 9 notwithstanding — above
        1|3|4|5|8) ;;                # every refusal, 8 (nobody asked) included — above
        # Fatal here for the same reason it is fatal above, and spelled out because the
        # temptation is to shrug it off as "that one account just did not answer": exit 2
        # is UNREADABLE reviewer state, and unreadable is indistinguishable from empty to
        # everything downstream. Swallowing it counts zero rounds for that account, and
        # zero rounds reads as "dispatch another one".
        *) echo "error: review-clearance.sh exited $rc for PR $pr at $sha as '$login'," >&2
           echo "       so whether that account verified this commit is unreadable, and" >&2
           echo "       the number of rounds is therefore unknown. Refusing (fail closed)." >&2
           exit 2 ;;
      esac
    done < "$TMPD/verdict-logins"
  fi

  [ -n "$counted" ] && { rounds=$((rounds + 1)); printf '%s\n' "$sha" >> "$TMPD/counted"; }
done < "$TMPD/commits"

printf '%s\n' "$rounds"

if [ "$rounds" -lt "$CAP" ]; then
  echo "ok: PR $pr ($nwo) has had $rounds verification round(s); the cap is $CAP." >&2
  exit 0
fi

echo "refuse: PR $pr ($nwo) has already had $rounds verification round(s), and the cap" >&2
echo "        is $CAP — $AB_CONVENTIONS, \"TWO ROUNDS, THEN THE HUMAN DECIDES\". Do NOT" >&2
echo "        dispatch another verifier. Rounds 3-8 on the pull request this rule comes" >&2
echo "        from produced adversary-shaped findings against a change that already met" >&2
echo "        its criteria, because nothing told the reviewer to stop." >&2
echo "        Stop here and put ONE block in front of the human: what the reviewer" >&2
echo "        wants, what the implementer says, and what the acceptance criterion" >&2
echo "        actually asks for. The human decides; the agents do not converge on it." >&2
echo "        Counted at: $(tr '\n' ' ' < "$TMPD/counted")" >&2
exit 1
