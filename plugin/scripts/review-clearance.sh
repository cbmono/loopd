#!/usr/bin/env bash
#
# review-clearance.sh — assert that an independent review ARTIFACT exists on a pull
# request, at its current head. This is precondition 2 of the delegated merge gate
# (`AUTONOMY.md` → "Merge under `yolo`"). `required-checks.sh` is precondition 1, and
# calls in here for every PR it is about to clear.
#
#   Usage: review-clearance.sh <pr> [--repo <owner>/<name>] [--head <sha>]
#                                           [--reviewer <login>] [--for-check <name>]
#                                           [--no-merge-check] [--record <task-doc>]
#          review-clearance.sh --match-check <check-name>
#          review-clearance.sh --self-test
#
# WHY THIS EXISTS — three pull requests in one tick. All three carried a GREEN reviewer
# status check. One had been reviewed; the other two carried a comment reading "Review
# limit reached. Next included review available in 44 minutes" and had been looked at by
# nothing. Both merged. One of them shipped a shell script at mode 100644 that no caller
# can execute. A hosted reviewer that DECLINES to review still exits successfully, so its
# integration reports success — correctly, on its own terms. A status check answers "did
# the integration run", never "did a review happen".
#
# So nothing here reads a check conclusion. It reads the reviewer's ARTIFACTS and asks
# whether any of them is a review OF THIS COMMIT.
#
# ENUMERATION IS THE DEFECT THIS FILE KEEPS COMING BACK TO, and every fix here is the same
# move away from one: a list of vendor names, a list of refusal wordings, a list of
# invisible characters and a list of block-level tags each looked finished and each was
# not. So EVIDENCE AND PINNING COME FROM THE STRUCTURED API —
# `/repos/{owner}/{repo}/pulls/{n}/reviews` publishes a review's `state` and its
# `commit_id`, and `gh` was already a hard dependency — rather than from "does the body
# happen to mention the head SHA", which is how review objects used to be pinned and is
# precisely the property THE TRAP below gives the REFUSAL too. TEXT MATCHING KEEPS EXACTLY
# ONE JOB, DETECTING A REFUSAL, where a false positive fails CLOSED (a human looks at a PR
# that was in fact reviewed): the unbounded matching problem sits on the side where being
# wrong is harmless, and nothing here clears a PR for its prose.
#
# THE TRAP, AND WHY THE ORDER OF THE TESTS BELOW IS LOAD-BEARING. The refusal comment ALSO
# enumerates the commit range it would have reviewed, and on the PR that merged unreviewed
# that range's head equalled the PR head exactly. "The artifact names the current head" is
# therefore TRUE OF THE REFUSAL. So: classify against the refusal tables FIRST, and
# consider clearance only for what survives. `tests/review-clearance.test.sh` drives that
# exact false positive against the recorded comment body.
#
# THAT ORDER IS PER ARTIFACT; THE RANKING ACROSS ARTIFACTS IS A SEPARATE THING, STATED
# WHERE IT IS APPLIED (see "the decision" after the classifier loop) rather than summarised
# here as an invariant this file does not keep. Nothing clears inside the loop, so the
# answer cannot depend on the order the host streamed the artifacts in.
#
# THE THREE ROUTES TO EXIT 0, AND THERE ARE NO OTHERS
#
#   A. a REVIEW OBJECT whose `state` is exactly `APPROVED`, `CHANGES_REQUESTED` or
#      `COMMENTED` — compared case-sensitively against the API's own spellings, because
#      `pending`/`dismissed` in another casing used to slip past a case-sensitive skip
#      list — and whose `commit_id` equals the head. Evidence and pin both structural.
#      WITH ONE CORRECTION THE PIN ITSELF FORCED: a review object that says NOTHING is not
#      evidence on its own. `COMMENTED` is not a claim (the host mints one for any inline
#      comment or thread reply), so an empty one evidences nothing at all; an empty
#      `APPROVED`/`CHANGES_REQUESTED` is a claim, but neither may outrank a refusal
#      published at the same head. The old body-SHA pin refused those cases as a side
#      effect of being wrong; see the note at TEST 2. SAYING NOTHING IS DECIDED BY WHAT
#      RENDERS (`renders_content`), measured against the host rather than argued.
#   B. a validated `okf-verdict` trailer whose `head_sha` equals the head, from an account
#      named with `--reviewer` that is NOT a vendor in REVIEWERS (see the tier-4 note).
#   C. a COMMENT carrying the reviewer's own MACHINE-EMITTED review marker
#      (REVIEW_SENTINEL) and naming the head. It exists because the reviewer this was
#      written against publishes a CLEAN review — "no actionable comments" — as an issue
#      comment and files no review object at all: FIVE OF THE SIX reviews that clear the
#      37 pull requests here are that shape, so dropping the route would not make the gate
#      stricter, it would make it structurally unable to say yes to a clean review.
#      IT IS ALSO THE ONLY ROUTE THAT READS PROSE, AND EVERY REMAINING WEAKNESS IN THIS
#      FILE IS DOWNSTREAM OF IT — kept or dropped is a policy call about how much
#      verification is required, not one this file can take. It is the narrowest form the
#      route has: a WHOLE LINE that is nothing but an HTML comment the vendor's own
#      renderer emits, read from a rendering with fenced blocks, indented blocks and
#      multi-line code spans removed, so anything a human can read on that line stops it
#      matching. ITS PIN IS THE RESIDUAL AND IS STATED RATHER THAN GLOSSED: the head named
#      as a bare token in that body is the only pin an issue comment has — there is no
#      `commit_id` on a comment anywhere in the API — so route C alone rests on what a body
#      happens to mention, which is the property THE TRAP below gives the refusal too. What
#      makes it survivable is that the pin cannot act alone: the refusal tiers run first,
#      and the machine marker must be there as well.
#      AND IT IS THE CHANNEL OF LAST RESORT, NOT A SECOND OPINION: it is consulted only
#      for an account with NO review object on the PR at all. The comment is one body the
#      vendor EDITS in place across rounds, so it names the current head whatever it last
#      reviewed — on #227 it named the head while the reviewer's only review object sat two
#      commits back, and that cleared. Where the structured channel has spoken for an
#      account, the structured channel decides.
#
# THE TABLES CAN NO LONGER CAUSE A CLEARANCE. Every vendor string lives in REVIEWERS
# (whose artifacts count, and what its check is called), REFUSALS_SENTINEL / NOT_YET /
# REFUSALS ("I did not review") and REVIEW_SENTINEL (the vendor's own review marker). A
# missing or wrong row in any of them costs a REFUSAL: an unknown account is ignored, an
# unmatched refusal phrasing still has to get past A/B/C, an unmatched review marker lands
# on exit 4. REVIEWERS column 1 is EXACT logins, because `greptile.*` matched
# `greptile-evil` too. AND A CHECK NAME NEVER SETTLES ANYTHING, HERE OR IN THE CALLER: the
# table of names that merely LOOKED like a reviewer's is DELETED rather than extended (a
# required check called `Codex Review` answered "plain CI" and settled green with zero
# artifacts read), because `required-checks.sh` now asks for clearance on every PR whatever
# its checks are called. `--match-check` keeps two answers and one job: which vendor owns a
# check, so one vendor's review cannot clear another's.
#
# A TABLE THAT DOES NOT COMPILE IS A TABLE THAT MATCHES NOTHING, which for the refusal
# tables means a refusal reads as a review. One typo'd ERE used to disable a whole table
# in silence, because the matcher read grep's OUTPUT and never its STATUS (1 is "no match",
# 2 is "your pattern is broken", and they are not the same answer). Every row of every
# table is now compiled up front by `validate_tables`, and every match checks grep's exit
# status — both refuse rather than proceeding with a table that cannot fire.
#
# WHAT THIS DOES NOT DO. It answers "did a review happen at this head", not "was the
# verdict good". Verdict adjudication is `SCHEMA.md` → "Independent verification gate"
# (the nine-clause predicate). A clean bill of health here means only that the reviewer
# looked; every other clause still applies.
#
# WITH ONE EXCEPTION, ADDED DELIBERATELY AND BOUNDED: CLAUSE 9. A review can only clear
# here once no reviewer-authored review thread is still unresolved, and the refusal NAMES
# the open threads. Clause 9 is in the predicate because a thread the reviewer opened and
# nobody answered is an unanswered finding whatever the review object says — and it was the
# one clause with no reader at all: `qa-reviewer.md` and `auditor.md` state it in prose, and
# the 2026-09-05 audit of seven PRs found FOUR failing on clauses 3 and 9, three of them
# merged with a reviewer that had answered. Not quota. A rule with no reader is not a rule.
#
# WHY HERE AND NOT IN THE CALLER. The alternative was a caller-side check, which is a
# second reader of the same signals reaching its own conclusion — the defect
# `--match-check` exists to avoid one level up. This file already holds the reviewer
# identity table (whose threads count) and already knows the PR; the caller holds neither.
#
# AND WHY IT IS ITS OWN EXIT CODE (6) RATHER THAN FOLDED INTO 4. The two answers send the
# caller somewhere different: exit 4 means ASK FOR A REVIEW, exit 6 means DO NOT — you have
# one, go and answer what it said. Folding clause 9 into 4 would tell an agent to spend a
# review session re-reading a diff whose findings it has not replied to yet, which is the
# most expensive wrong move available here.
#
# GENERIC PLUGIN FILE — ships inside the `loopd` plugin; nothing to edit per
# instance. It takes no org, repo or reviewer identity: those come from the arguments.
#
# Exit codes — 0 is the ONLY clearance; every other code is a refusal:
#
#   0  a review artifact from the reviewer EVIDENCES a completed review of the current
#      head, by route A, B or C above
#   1  the reviewer REFUSED to review and the refusal is TRANSIENT — a rate limit, an
#      exhausted included-review allowance, a skip, or a not-yet-reviewed placeholder. It
#      reopens with NOBODY doing anything. Quoted on stderr, with the reopen time when the
#      reviewer published one
#   2  usage error, or the environment cannot answer (no `gh`/`jq`, unreadable PR or
#      review list, NO AUTHOR LOGIN on the PR — which would switch off the rule that an
#      author is not its own reviewer rather than fail — NO AUTHOR LOGIN ON AN ARTIFACT,
#      which is an artifact nobody can attribute or exclude, the PR's own author named as
#      its reviewer, a pattern table that will not compile) — unknown, never clearance
#   3  no reviewer signal at all: nothing on this PR from a known reviewer
#   4  an artifact exists but does not evidence a completed review OF THE CURRENT HEAD —
#      a review object made at an earlier commit, an EMPTY `COMMENTED` review object at
#      the head (the host mints one for any inline comment or thread reply, so an empty
#      one claims nothing), an artifact carrying no evidence a review happened at all, or
#      a `--head` that no longer matches the PR
#   5  the reviewer REFUSED to review and the refusal is TERMINAL — it says the ACCOUNT is
#      out of credits, unpaid, expired or unauthenticated, so no amount of waiting reopens
#      it. Quoted on stderr, exactly as exit 1 is
#   6  a review artifact DOES evidence a completed review of the current head — routes A,
#      B or C all held — but SCHEMA.md CLAUSE 9 refuses it: a reviewer-authored review
#      thread is still unresolved. Every open thread is NAMED on stderr (path, line, the
#      reviewer, its URL and its opening line), because "clause 9 failed" that does not say
#      WHICH thread is an instruction to go and look rather than one to go and act.
#      DO NOT ANSWER THIS BY REQUESTING A REVIEW: there already is one
#   7  the PR CANNOT MERGE: the host reports `mergeable` CONFLICTING or
#      `mergeStateStatus` DIRTY at the current head. Nothing about the review was read.
#      ANSWER IT BY REBASING, never by requesting a review — see below
#   8  the reviewer SKIPPED this PR because reviews are not automatic here, and said so
#      in its own notice: "Review skipped / Auto reviews are disabled … invoke the
#      `@coderabbitai review` command". NOBODY EVER ASKED. ANSWER IT BY ASKING, at this
#      head, once — see table 2e
#
# WHY 8 IS NOT 1, WHICH IS THE WHOLE OF THIS CODE. Exit 1 says "wait, it reopens with
# nobody doing anything", and that is FALSE of a repository with auto reviews off: the
# notice is posted on every push and no event will ever clear it. Measured 2026-09-15:
# four PRs held for three consecutive ticks on exit 1, and one `@coderabbitai review`
# comment was answered "Review triggered" in 4 seconds. Two refusals, opposite remedies,
# and until now one code.
#
# MERGEABILITY IS THE FIRST CHECK, AND IT IS ITS OWN CODE (7). On 2026-09-13 three pull
# requests were presented as merge rows while the host reported all three CONFLICTING /
# DIRTY: they had been cleared against the PREVIOUS default-branch head, and four sibling
# merges moved it underneath them with no commit on any of the three. A verdict about a
# review is not a verdict about a merge, so this file now asks the host the merge question
# FIRST — before the artifact reads, and before the `--head` staleness test, because a
# rebase re-answers both. IT IS NOT EXIT 6: clause 9 means a review completed and you owe
# it a reply; 7 means nobody's review is the problem. The two send a caller to opposite
# places, which is the test a new code has to pass.
#
# UNKNOWN IS A HOLD (EXIT 2), NEVER A PASS. The host computes `mergeStateStatus` lazily and
# answers UNKNOWN for seconds after the base moves — exactly the window this exists for —
# so an unreadable, empty or unrecognised value is unknown state and fails closed like
# every other one here. THE TRAP: `mergeStateStatus` is only populated for a token with
# PUSH access, so a read-only token holds at 2 forever rather than clearing. That is the
# correct direction (the gate merges, so it needs that token anyway) and it is stated
# because a permanent 2 otherwise looks like a broken script.
#
# `--no-merge-check` SUPPRESSES IT, FOR ONE CALLER AND ONE REASON. `review-rounds.sh` asks
# "did a review happen at commit X", which is a question about the past and has no merge in
# it; left on, every conflicting PR would answer 7 there and land in its fatal `*` arm,
# turning "this PR has a conflict" into "the round count is unknown". The flag is opt-OUT
# rather than opt-in so a caller that forgets it gets a refusal, never a clearance.
#
# WHY 1 AND 5 ARE TWO CODES, WHICH IS THE ONLY REASON THIS SPLIT EXISTS. The caller's next
# action differs, and it differs by a whole review session. A transient refusal is answered
# by WAITING: measured 2026-08-31 on four pull requests (#85-#88), the reviewer was rate
# limited and returned within the hour and reviewed all four properly, so a caller that had
# spent its fallback reviewer on them would have bought four deep-tier sessions for nothing.
# A terminal refusal is answered by a HUMAN — buy credits, fix the token, or authorise the
# spend — and it is a fact about EVERY future pull request, not this one, so a caller that
# quietly works around it per PR hides a systemic failure. One authoritative reader draws
# that line, here, because a caller drawing it would be a second and weaker reader of the
# same signals.
#
# NEITHER 1 NOR 5 IS EVER CLEARANCE, and the split does not move one byte of the merge
# gate: 0 remains the only clearance, both codes refuse, and a caller that lumps them back
# together is no less safe — only more expensive. The split is about SPEND, never about the
# gate.
#
# WHERE THE LINE IS DRAWN. "Terminal" is not "serious": it is *does this reopen without a
# human*. A monthly quota that resets on its own is transient however long the wait; a
# five-minute auth failure is terminal because nothing but a human clears it. And a refusal
# that publishes a REOPEN TIME is transient whatever else it says (`reopen_line`), which is
# the reviewer's own claim that it will come back — it is what keeps a promotional "upgrade
# your plan" line inside an ordinary rate-limit notice from reading as an empty account.
# Unmatched refusal language stays exit 1, the cheaper wrong answer: a transient refusal
# misread as terminal spends a human, and this file does not get to spend one on a guess.
#
# WHAT IT PRINTS IS UNTRUSTED TEXT. The quoted refusal comes from a PR comment, which
# anyone able to comment can write. It is quoted for a human to read and is never an
# input to the decision — the decision is the exit code. Do not parse the quote.
# THAT RULE IS UNCHANGED BY THE 1/5 SPLIT, and the split is arranged so it stays that way:
# this script reads its own captured text against its own tables, in here, and publishes
# the answer as an EXIT CODE. What a caller must never do is what it never could — read the
# quote. A caller that grepped the stderr for "credits" would be exactly the second, weaker
# reader that adding a code avoids.
#
# FAILS CLOSED. Unknown, unreadable, unpinnable and unrecognised all refuse. A fetch that
# ERRORS refuses at exit 2 rather than reading as "nothing here"; a fetch that silently
# TRUNCATES is the more dangerous one, and is why both artifact lists are paginated — a
# lost review costs exit 3 or 4, but a lost REFUSAL is a clearance. A review this script
# cannot see is a review that did not happen; a refusal it cannot see is a merge.
#
# AND A TRUNCATED COPY OF THIS FILE IS UNKNOWN STATE TOO. `--self-test` proved this file
# RUNS, which is not proving it is COMPLETE: a copy cut off after the self-test block still
# runs, still prints the sentinel, and then classifies with half its tables — 112 of one
# version's truncation points passed the old self-test and 109 of those cleared an
# unreviewed PR. The last line of this file is therefore a completeness sentinel, which no
# cut short of the end can satisfy.
#
# EXIT 4 IS THE COMMON ANSWER, NOT AN EXOTIC ONE, wherever the reviewer does not re-review
# every push. Measured over the 37 pull requests on the repository this was written in: 18
# of THE REVIEWER'S review objects exist across 18 of them (62 exist in total — most are
# humans')
# and exactly ONE was made at its PR's final head, because `.coderabbit.yaml` here sets
# `auto_incremental_review: false`. Those are STALE reviews, not absent ones, and clause 3
# of SCHEMA.md's predicate says stale is not cleared — so wiring this into a merge gate
# means most PRs need a review requested at the FINAL head. A real operating cost, and the
# correct answer rather than a bug to tune out.
#
# No `set -e`: a `grep` that finds nothing is an ANSWER here, not a fault, and under `-e`
# the first such assignment would exit the script with a success-looking code. Every
# failure path below is therefore explicit.
set -uo pipefail
# This file's directory, resolved once. `${RC_SELF%/*}` is the text `dirname` prints
# whenever the path has a slash, no trailing one, no leading `-`, and a parent that does
# not itself end in a slash; every other spelling still asks `dirname`.
RC_SELF="${BASH_SOURCE[0]:-$0}"; RC_DIR="${RC_SELF%/*}"
case "$RC_SELF" in -*|*/) RC_DIR="" ;; esac
case "$RC_DIR" in ''|*/|"$RC_SELF") RC_DIR="$(dirname "$RC_SELF")" ;; esac
. "$RC_DIR/bundle-paths.sh" || exit 2

# --- table 1: who is a reviewer, and what its check is called ----------------
# Two whitespace-separated fields per row, so neither may contain a space:
#
#   1. the account login that publishes the artifacts — an EXACT login, case-folded,
#      after a trailing "[bot]" is stripped. No wildcards, deliberately: `greptile.*` was
#      matched whole-string but ended in `.*`, so `greptile-evil` read as the vendor and
#      any stranger who could comment could clear a PR. A login spelled wrongly here is
#      IGNORED, which is exit 3 — the safe direction.
#   2. a POSIX ERE for the name its status check reports under (substring, case-folded)
#
# Column 2 is what `--match-check` answers on, and it exists to tell the caller which
# vendor owns a required check so that vendor's own artifacts answer for it. It never
# decides whether a review is needed — `required-checks.sh` asks on every PR.
#
# ONLY `coderabbitai` IS MEASURED HERE. The other five are each vendor's best-known bot
# login taken from its documentation, and a login spelled wrongly costs exit 3 — so confirm
# one against a real PR before relying on it, or name it with `--reviewer`, which bypasses
# this table and is how the `qa-reviewer` fallback (a human account) is named.
REVIEWERS='
coderabbitai            coderabbit
sourcery-ai             sourcery
greptile-apps           greptile
qodo-merge-pro          (qodo|codium|pr-agent)
codiumai-pr-agent-pro   (qodo|codium|pr-agent)
ellipsis-dev            ellipsis
'

# --- table 2a: the reviewer's own machine-readable "I did not review" sentinel -
# One POSIX ERE per line, matched case-insensitively against an artifact body whose
# fenced code blocks have been removed (see render_body). Blank lines and whole-line
# `#` comments are ignored; a pattern may not carry a trailing comment, because the
# whole line is the pattern. Same reading rules for every table below.
#
# THIS TIER IS UNCONDITIONAL and nothing outranks it but table 4. Hosted reviewers stamp
# their own automated notices with an HTML sentinel — a machine-readable claim, by the
# reviewer, sitting in the comment body. Measured over every pull request on this
# repository: the sentinel appears on exactly the rate-limit notices and on no review.
# The second row is the same claim in the generic HTML-marker shape other vendors use, so
# this tier is not one vendor's spelling.
REFUSALS_SENTINEL='
rate.limited by [a-z0-9._-]+
<!--[^>]*(rate|usage|quota)[^a-z0-9]?limit(ed|s)?[^>]*-->
'

# --- table 2c: "I have not reviewed it YET" -----------------------------------
# The reviewer posts a placeholder the moment the PR opens — "Currently processing new
# changes in this PR", quoting the head it is about to look at — and edits that same
# comment into the review when it finishes. It is on essentially every pull request, and
# it is the exact shape a default-allow classifier clears: an artifact, from the reviewer,
# naming the head, saying nothing that reads as a refusal. It is not a refusal. It is not
# a review either, and this file's job is to say so.
#
# UNCONDITIONAL, like the sentinel and for the same reason: "I am still working" is a
# claim about COMPLETION, and a marker elsewhere in the same body does not refute it.
#
# NARROW ON PURPOSE, unlike table 2b. An over-broad row here mislabels a real review as
# unfinished, and nothing outranks this tier, so each row names a placeholder phrasing
# rather than any sentence about reviewing. The refusal fixture's "keep reviewing this
# public repository" is why the `(is|are|am)` anchors are not optional.
NOT_YET='
currently (processing|reviewing|analy(s|z)ing)
review (is )?in progress
(is|are|am) (still )?(processing|reviewing) (the|your|new|this)
(have|has|had) not (yet )?(been )?review(ed)?
review (is |was |has |had )?not (yet )?(been )?(started|complete|completed|finished)
queued for review
'

# --- table 2b: the human-visible language of "I did not review" ---------------
# Deliberately over-broad, because a false refusal costs a human glance while a missed
# refusal costs an unreviewed merge — but over-broad prose matched against a whole
# comment body is ALSO how a real review gets called a refusal, so this tier is
# outranked by table 3. See the note there; the split is measured, not stylistic.
REFUSALS='
# the human-visible headings, verbatim from the PRs this script was written for
review limit reached
next included review available
# generic quota/limit phrasings across hosted reviewers
(rate|usage|plan|api) limit (reached|exceeded|hit)
(quota|credits) (exceeded|exhausted|reached|depleted|used up)
(daily|hourly|monthly|weekly) (review )?limit
no (reviews?|credits) (left|remaining)
used all (of )?(your |the )?(free |included )?(oss )?reviews
# generic "I chose not to look" phrasings
reviews? (was |were |is |are |has been |have been )?(skipped|not performed|not run)
skipping (this |the )?review
review (skipped|declined|deferred|postponed)
unable to (complete|perform|run) (the |this )?review
'

# --- table 2d: which refusals NOTHING BUT A HUMAN reopens ---------------------
# A SUB-CLASSIFIER, not a fifth refusal tier. It is consulted only for a body the tables
# above have ALREADY called a refusal, and its whole effect is exit 5 instead of exit 1 —
# it can never turn a review into a refusal, and it can never clear anything. So a row here
# is read against a body somebody already lost the merge on; the only thing it decides is
# whether the caller waits or asks a human.
#
# NARROW ON PURPOSE, AND IN THE OPPOSITE DIRECTION FROM TABLE 2b. There, a false positive
# costs a human one glance, so breadth is cheap. Here a false positive costs a human an
# INTERRUPTION and a decision about spending a review session, on a reviewer that was going
# to come back by itself in forty minutes — which is the exact failure the split exists to
# prevent. So every row names the ACCOUNT'S OWN STATE ("no credits remaining", "payment
# failed", "invalid API key"), never a rate window and never a promotional invitation. An
# unmatched refusal is exit 1, and exit 1 is the answer that costs nothing.
#
# WHAT IS DELIBERATELY ABSENT, because each was drafted and cut:
#   * bare `unauthorized` / `forbidden` — a REVIEW of authorisation code says both, and a
#     review body reaches here whenever its prose trips table 2b without a review marker.
#   * `upgrade` / `subscribe` / `pro plan` — the recorded rate-limit fixture in
#     tests/fixtures/reviewer/ carries a plan name and a docs link inside an ordinary
#     40-minute wait. Vendors sell inside their refusals; the sales pitch is not the state.
#   * `(daily|monthly) limit` — it reopens on a clock. Long is not terminal.
REFUSALS_TERMINAL='
# the account has no balance left to spend, and only a purchase changes that
(out of|no) (review )?credits( (left|remaining))?
(zero|insufficient|not enough) (review )?credits
credits? (have |has )?(been )?(exhausted|depleted|run out)
(add|purchase|buy|top ?up) (more )?credits
# billing stopped, which is a person with a card, not a clock
payment (has )?(failed|declined|(is )?required|(is )?overdue)
billing (issue|problem|failure|error)
(subscription|licen[cs]e|trial|free trial) (has |was )?(expired|lapsed|ended|cancell?ed)
(account|organi[sz]ation) (is )?(suspended|disabled|deactivated)
# the credential is wrong, missing or dead — waiting never fixes a token
authenticat(e|ion) (has )?(failed|error)
authori[sz]ation (has )?(failed|error)
not authenticated
(invalid|expired|missing|revoked) (api |access |auth )?(key|token|credentials?)
(re-?install|re-?connect|re-?authori[sz]e) the (app|integration|github app)
(app|integration) is not installed
(repository|organi[sz]ation) is not (connected|authori[sz]ed|enabled)
'

# --- table 2e: which refusals NOBODY HAS ASKED OUT OF -------------------------
# A SUB-CLASSIFIER of table 2b, exactly as 2d is of the tiers above it, and its whole
# effect is exit 8 instead of exit 1. It cannot turn a review into a refusal and it cannot
# clear anything.
#
# IT IS REACHED ONLY THROUGH TABLE 2b, AND THAT PLACEMENT IS THE CORRECTNESS QUESTION.
# The vendor edits ONE summary comment in place, so this notice and a completed review's
# walkthrough sit in the SAME body — measured 2026-09-15: #215 carries the skip marker and
# 2 review objects, #213 the marker and 1. Table 2b is outranked by the review marker
# (table 3), so a body carrying both is never a refusal here and can never answer 8.
# Placing this beside the unconditional sentinel tier would tell the loop to ask again for
# a review it already has — the same wasted round this code exists to stop.
#
# THE ROWS ARE THE VENDOR'S OWN NOTICE AND NOTHING ELSE. A notice not matched here keeps
# exit 1: unknown stays the conservative answer, because 1 costs a tick and 8 costs a
# request out of a one-review-per-window quota.
SKIP_NOTICE='
<!--[^>]*skip review by coderabbit\.ai[^>]*-->
auto (incremental )?reviews? (are|is|have been) disabled
to trigger a (single|first) review, invoke
'

# --- table 3: the reviewer's own MACHINE-EMITTED review marker ----------------
# A row here outranks table 2b — never table 2a — and it is the evidence half of route C.
#
# WHY IT OUTRANKS 2b. A reviewer's REVIEW comment routinely carries a notice about
# something it did NOT do, and table 2b reads the whole body: "## Review skipped / Auto
# incremental reviews are disabled" sits at the top of the same comment that carries the
# walkthrough of a review that DID happen — on half of this repository's reviewed PRs,
# because `.coderabbit.yaml` here sets `auto_incremental_review: false` on purpose.
#
# EVERY ROW IS AN HTML COMMENT THE VENDOR'S RENDERER EMITS, and that is the design. This
# table used to hold PROSE — `i (have )?reviewed`, `(lgtm|looks good to me)` — matched as
# unanchored substrings, so quoted approvals cleared, negated sentences like "Unreviewed
# <sha>" matched, and a prose quota refusal carrying one such phrase outranked the refusal
# tier. Prose is gone. What is left is the same CLASS of signal as REFUSALS_SENTINEL: a
# machine-readable claim by the reviewer, invisible in the rendered page.
#
# WHAT THAT DID AND DID NOT MAKE SYMMETRIC, corrected from an earlier claim that all six
# vendors now get the same answer. What IS the same for all six: no vendor's prose clears
# anything, and refusal prose is only ever rescued by a MARKER. What is NOT: every row
# below is one vendor's spelling, and this table is not scoped to the vendor that posted
# the body — so the other five have no marker of their own to be rescued by (their real
# reviews reach exit 0 through a review object instead), while a body from any of them that
# QUOTES a row below is rescued by a marker its author does not emit. The unconditional
# tier above is the half that is genuinely vendor-neutral, through its second row.
#
# A MISSING ROW COSTS A REFUSAL: a vendor whose marker is not here files review objects or
# lands on exit 4, and `--reviewer` names it explicitly. A row that is too loose costs a
# CLEARANCE, so nothing belongs here that a placeholder or a BANNER could carry — which is
# why `review_stack_entry_start`, which wraps a promotional image and a `utm_campaign`
# link, was REMOVED rather than kept for symmetry (measured: 0 of 37 outcomes change).
#
# AND EVERY ROW IS ANCHORED TO A WHOLE LINE, which is the other half of "prose cannot reach
# the evidence half". Matched as a substring, a row was reachable from text a human READS:
# the marker spelled inside an inline code span renders as visible characters and matched
# anyway, so a comment merely TALKING about this file cleared a pull request — the review
# that found it had to break the marker to post its own verdict. A line that is nothing but
# one of these comments (blockquote markers aside) renders as nothing at all, which is what
# makes it the vendor's claim rather than anybody's prose. The anchor covers a code span the
# block machine cannot see; the block machine covers a marker alone on a line inside a code
# block; and the rendering it is matched against drops both.
REVIEW_SENTINEL='
^[[:space:]]*(>[[:space:]]*)*<!--[[:space:]]*walkthrough_start[[:space:]]*-->[[:space:]]*$
^[[:space:]]*(>[[:space:]]*)*<!--[[:space:]]*recent_review_start[[:space:]]*-->[[:space:]]*$
^[[:space:]]*(>[[:space:]]*)*<!--[[:space:]]*final_review_risk_start[[:space:]]*-->[[:space:]]*$
'

# --- table 3b: the reviewer ACKNOWLEDGING A COMMAND, which is not a review ----
# Matched against a COMMENT only (a review object carries its own state and commit_id, so
# it is never reached through here), and consulted after every refusal tier — a rate limit
# quoted inside an acknowledgement is still a refusal, and exit 1 says more than exit 4.
#
# WHAT THIS IS. `@coderabbitai review` is answered immediately by an auto-generated reply
# — "✅ Action performed / Review finished", or "⚠️ Action not completed" — which names the
# head it was invoked at and is posted whether or not a review follows. Measured on #227:
# the reply at 11:03:30Z is the whole of what that PR got at head 711c755c, while the
# reviewer's only review object sits at 6d954b42. An acknowledgement is a receipt for a
# command, so it is never evidence here, at any head.
#
# NEITHER A REFUSAL NOR A REVIEW, deliberately. Calling it a refusal would report exit 1
# ("DECLINED") over a PR whose real state is a real review at an older commit, which is
# exit 4 and a different instruction to the caller.
#
# ONE ROW, AND IT IS THE VENDOR'S OWN INVOCATION MARKER. This table started with two
# prose rows beside it — `Action performed`, a whole-line `Review finished` — on the
# reasoning that a tier which only ever REFUSES costs at most a human glance. That was
# wrong in a way that inverts this file's whole point: `hits` treats rows as independent
# alternatives, and a comment skipped here never reaches the evidence tests below, so any
# review whose body happened to quote an acknowledgement was itself read as one and
# reported exit 4. A review quoting an ack is ordinary on a PR that touches this file.
# The marker carries the same claim and no review body has ever carried it — measured on
# the receipts for `review` (#227) and `full review` (#233), both of which have it.
#
# `this is an auto-generated reply by coderabbit` was dropped with the prose: it heads
# EVERY reply the vendor posts, not just a review receipt, so it widens the same
# false-positive surface while catching no acknowledgement the marker misses.
INVOCATION_ACK='
^[[:space:]]*<!--[[:space:]]*coderabbit review command invocation:[^>]*-->[[:space:]]*$
'

# The reviewer explaining that a plain review request cannot produce a review at this head.
# Surfaced in the exit-4 message, with the command that can — see `incremental_note`.
INCREMENTAL_NOTE='
does not re-?review already reviewed commits
incremental review system
'

# --- tier 4: an artifact that declares itself a review, structurally ----------
# The `okf-verdict` trailer (`SCHEMA.md` → "A verdict is a structured claim, not prose")
# is the fallback reviewer's own machine-readable output, and it outranks EVERY refusal
# row — including the sentinel. Not a convenience: a `qa-reviewer` verdict on a
# rate-limited PR has to SAY the hosted reviewer refused, quoting the words and the
# sentinel, which classifies the verdict itself as a refusal. That happened to the verdict
# on the PR that introduced this script.
#
# SO IT IS PARSED, NOT GREPPED. As one row of substrings, the highest-ranking tier here
# was a nineteen-character string: one appended `<!-- okf-verdict v1 -->` line turned the
# recorded rate-limit refusal from exit 1 into exit 0, and "no hosted reviewer emits that
# string" is untrue of a reviewer QUOTING A DIFF that contains it — this file ships it.
# `verdict_trailer` requires a well-formed block: the marker alone on its line, `-->`
# closing it, and the three fields SCHEMA.md's predicate needs, one of which is a
# `head_sha` equal to the head being cleared.
#
# AND THE TEXT IT PARSES IS THE STRICT RENDERING (see render_body), because a sound parser
# fed unsound text is an unsound parser: an INDENTED code block the host renders as literal
# text validated as markup, and an unbalanced fence handed back the raw body. The parser
# additionally discards a block holding a nested `<!--` — the host renders a trailer inside
# another comment blank — and one nobody closed, so state cannot leak between blocks.
#
# IT IS ALSO SCOPED, AND NOT BY `--reviewer` ALONE: honoured only for an account named
# with `--reviewer` that is NOT a vendor in REVIEWERS. Naming the vendor's own login used
# to re-arm the tier against that vendor's own refusal sentinel — and that vendor is
# precisely the account whose comments quote diffs.
VERDICT_MARKER='^[[:space:]]*<!--[[:space:]]*okf-verdict[[:space:]]+v[0-9]+[[:space:]]*$'

# The three review states GitHub's API publishes for a SUBMITTED review. Compared
# case-sensitively against the API's own spellings: the old skip list named `DISMISSED`
# and `PENDING` in a case-sensitive `case`, so a `pending` or `dismissed` in any other
# casing fell straight through it and was then treated as evidence.
SUBMITTED_STATES="APPROVED CHANGES_REQUESTED COMMENTED"

usage() {
  echo "Usage: $(basename "$0") <pr> [--repo <owner>/<name>] [--head <sha>]" >&2
  echo "                       [--reviewer <login>] [--for-check <check-name>]" >&2
  echo "                       [--no-merge-check]   (round counting only, never a gate)" >&2
  echo "                       [--record <task-doc>] persist the mergeability read" >&2
  echo "       $(basename "$0") --match-check <check-name>   (0 a reviewer's, 1 not)" >&2
  echo "       $(basename "$0") --self-test                  (prove this script RUNS)" >&2
  exit 2
}

# --- table lookups (no network, no PR) ---------------------------------------
# `rows <table>` strips comments and blank lines; every table is read through it, so a
# malformed row is inert rather than silently matching everything.
# In the shell itself, not `sed | grep | grep`: every table is read through this several
# times per run, and the three processes were most of what a run spawned.
rows() {
  local l
  while IFS= read -r l; do
    l="${l#"${l%%[![:space:]]*}"}"; l="${l%"${l##*[![:space:]]}"}"
    case "$l" in ''|'#'*) ;; *) printf '%s\n' "$l" ;; esac
  done <<EOF
$1
EOF
}

# A string of nothing but these characters has no upper-case letter in any locale, so `tr`
# would hand it back unchanged; spelled out, never `a-z`, which collation may widen.
fold() {
  case "$1" in
    *[!abcdefghijklmnopqrstuvwxyz0123456789._-]*) printf '%s' "$1" | tr '[:upper:]' '[:lower:]' ;;
    *) printf '%s' "$1" ;;
  esac
}

# A login as every comparison here wants it: case-folded, with the host's "[bot]" suffix
# removed. `coderabbitai` and `coderabbitai[bot]` are one account, and the API returns
# both spellings depending on which endpoint answered.
norm() { fold "${1%\[bot\]}"; }

# hits <table> <file> — the matching lines of <file>, at most three, or nothing.
#
# GREP'S STATUS IS PART OF THE ANSWER, and ignoring it is how one typo disabled a whole
# table in silence: 1 means "no line matched" and 2 means "this pattern is not a regular
# expression", and reading only the (empty) OUTPUT turns the second into the first. For
# the refusal tables that reads a refusal as a review. Status 2 records that the table
# cannot fire and returns 2; `fatal_grep` turns that into exit 2 in the caller, because
# this function runs inside a command substitution and cannot exit the script itself.
# WHICH row is broken is `validate_tables`, which has already run over every table in the
# file before one artifact is read — naming it again from here would be a second copy of
# that loop, and a second copy is what drifts.
hits() {
  rows "$1" > "$TMPD/pat"
  grep -Ei -f "$TMPD/pat" "$2" > "$TMPD/hit" 2>/dev/null
  case "$?" in
    0) head -3 "$TMPD/hit"; return 0 ;;
    1) return 1 ;;
  esac
  cat "$TMPD/pat" >> "$TMPD/grep-fatal"
  return 2
}

# Turn a hits() status-2 into a refusal. Called after each group of hits() calls.
fatal_grep() {
  [ -s "$TMPD/grep-fatal" ] || return 0
  echo "error: a pattern table in this script is not a valid POSIX ERE, so the table" >&2
  echo "       holding it matches nothing and the classification it drives is silently" >&2
  echo "       disabled. Refusing (fail closed). Offending row(s):" >&2
  sort -u "$TMPD/grep-fatal" | sed 's/^/          /' >&2
  exit 2
}

# Every pattern in every table, as one row per line — the argument to validate_tables,
# and the reason a two-column table is split before it is compiled.
all_patterns() {
  rows "$REVIEWERS" | awk '{print $1; print $2}'
  rows "$REFUSALS_SENTINEL"; rows "$NOT_YET"
  rows "$REFUSALS";          rows "$REVIEW_SENTINEL"
  rows "$REFUSALS_TERMINAL"; rows "$INVOCATION_ACK"
  rows "$INCREMENTAL_NOTE";  rows "$SKIP_NOTICE"
}

# Compile every row before anything is classified with it. A table that will not compile
# is not a table that matches less — it is a table that matches NOTHING, and a refusal
# table that matches nothing turns every refusal into a review. Checked here (up front, so
# the whole file is known good before one artifact is read), in --self-test (so the caller
# refuses a sibling carrying a broken table), and again at every match through hits().
#
# ONE grep COMPILES THEM ALL FIRST, and the row-by-row loop below it is unchanged and still
# decides anything that grep does not pass: given every row as its own `-e`, grep compiles
# each one before it reads a byte, and exits above 1 if any of them will not — the same
# status `hits` already trusts from `-f`. A row that opens with `-` is never sent that way,
# because alone on a command line it is an option and here it would be a pattern.
validate_tables() {
  local bad="" r pats all=() optlike=""
  pats="$(all_patterns)"
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    all+=(-e "$r")
    case "$r" in -*) optlike=yes ;; esac
  done <<EOF
$pats
EOF
  if [ -z "$optlike" ] && [ "${#all[@]}" -gt 0 ]; then
    grep -Eq "${all[@]}" </dev/null 2>/dev/null
    case "$?" in 0|1) return 0 ;; esac
  fi
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    printf '' | grep -Eq "$r" 2>/dev/null || [ $? -eq 1 ] || bad="$bad          $r
"
  done <<EOF
$pats
EOF
  [ -n "$bad" ] || return 0
  echo "error: these rows in this script's pattern tables are not valid POSIX EREs, so" >&2
  echo "       the tables holding them match nothing and every decision they drive is" >&2
  echo "       silently disabled. Refusing (fail closed):" >&2
  printf '%s' "$bad" >&2
  return 2
}

# The col-1 login of every REVIEWERS row whose col-2 check pattern matches <check-name>.
# Empty when no row owns that check. Substring match, case-folded.
owners_of_check() {
  local needle login check; needle="$(fold "$1")"
  # `read` splits a row into its two fields without EXPANDING either, which `set -- $row`
  # would: column 2 is an ERE ending in `*` and would be pathname-expanded against the cwd.
  while read -r login check _; do
    [ -n "$login" ] && [ -n "$check" ] || continue
    printf '%s' "$needle" | grep -Eq "$check" 2>/dev/null && printf '%s\n' "$login"
  done <<EOF
$(rows "$REVIEWERS")
EOF
}

# Is <check-name> a reviewer's own status check?
#   0  yes, a table-1 row owns it (and owners_of_check names whose)
#   1  no row owns it
# There is no third answer any more, and no table of names that merely LOOK like a
# reviewer's: see the header. The caller does not use this to decide whether a review is
# required — only to decide whose artifacts answer for a given check.
match_check() { [ -n "$(owners_of_check "$1")" ]; }

# Does <login> match any of <newline-separated login patterns>? Whole-string,
# case-folded, "[bot]" stripped — the form every login test here takes.
match_patterns() {
  local login pat; login="$(norm "$1")"
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    printf '%s' "$login" | grep -Eqx "$pat" 2>/dev/null && return 0
  done <<EOF
$2
EOF
  return 1
}

# Is <login> a known reviewer account at all?
reviewer_logins=""; reviewer_logins_read=""
match_reviewer() {
  [ -n "$reviewer_logins_read" ] || {
    reviewer_logins="$(rows "$REVIEWERS" | awk '{print $1}')"; reviewer_logins_read=yes; }
  match_patterns "$1" "$reviewer_logins"
}

# --- the two table-only modes: no network, no PR ------------------------------
#
# --self-test PROVES THIS SCRIPT RUNS, which `[ -x ]` does not. A caller whose whole job
# is to fail closed cannot ask the filesystem whether this file works: a dead shebang, a
# syntax error, a zero-byte file and a copy truncated half-way through an install all
# carry the executable bit and then fail every invocation, which used to read as "no
# required check is a reviewer's" and clear an unreviewed PR. So `required-checks.sh` runs
# this first and refuses unless it exits 0 AND prints SELFTEST_OK verbatim — that string
# is the contract between the two files, duplicated there on purpose (a shared constant
# would have to be sourced, and sourcing a broken file is the failure being tested for).
#
# THE CONTROLS ARE THE POINT: a banner would pass for any stub that prints a banner. This
# drives the table lookup the caller depends on in both directions, then classifies two
# literal bodies through the real refusal and review tables.
#
# AND "IT RUNS" IS NOT "IT IS COMPLETE" — see the header. This block sits near the TOP of
# the file, so a copy truncated below it still reaches this exit and prints the sentinel
# with the tables it just vouched for gone. The last line of the file is asserted here.
SELFTEST_OK="review-clearance: self-test ok"
EOF_SENTINEL="#EOF: review-clearance.sh is complete to here"
if [ "${1:-}" = "--self-test" ]; then
  [ "$#" -eq 1 ] || usage
  [ -r "$0" ] || {
    echo "self-test: cannot read '$0' to prove it is complete — refusing" >&2; exit 2; }
  [ "$(tail -n 1 "$0")" = "$EOF_SENTINEL" ] || {
    echo "self-test: this file does not end with its completeness sentinel, so it is" >&2
    echo "           truncated or was cut short — the tables and the classifier below" >&2
    echo "           this line cannot be assumed to be here. Refusing." >&2; exit 2; }
  TMPD="$(mktemp -d)" || {
    echo "self-test: could not create a temp dir — refusing" >&2; exit 2; }
  trap 'rm -rf "$TMPD"' EXIT
  validate_tables || exit 2
  match_check "CodeRabbit" || {
    echo "self-test: the reviewer table no longer matches its own canary" >&2; exit 2; }
  if match_check "Build, Lint & Format"; then
    echo "self-test: the reviewer table matches a plain CI job" >&2; exit 2
  fi
  # The classifier's own two directions, driven through the tables rather than described:
  # a refusal must be found in a refusal body, and the review marker in a reviewed one.
  printf 'Review limit reached.\n' > "$TMPD/probe"
  [ -n "$(hits "$REFUSALS" "$TMPD/probe")" ] || {
    echo "self-test: the refusal table does not match a refusal" >&2; exit 2; }
  printf '<!-- walkthrough_start -->\n' > "$TMPD/probe"
  [ -n "$(hits "$REVIEW_SENTINEL" "$TMPD/probe")" ] || {
    echo "self-test: the review-marker table does not match a review" >&2; exit 2; }
  # The 1-vs-5 sub-classifier, in both directions, because a terminal table that matched
  # everything would ask a human on every rate limit and one that matched nothing would
  # hide an empty account forever — and both read as "it runs".
  printf 'No credits remaining on this account.\n' > "$TMPD/probe"
  [ -n "$(hits "$REFUSALS_TERMINAL" "$TMPD/probe")" ] || {
    echo "self-test: the terminal-refusal table does not match an empty account" >&2; exit 2; }
  printf 'Review limit reached. Next included review available in 44 minutes.\n' > "$TMPD/probe"
  if [ -n "$(hits "$REFUSALS_TERMINAL" "$TMPD/probe")" ]; then
    echo "self-test: the terminal-refusal table matches an ordinary rate limit, which" >&2
    echo "           would ask a human every time the reviewer pauses" >&2; exit 2
  fi
  # An acknowledgement must be recognised, and the review it is a receipt for must not be:
  # a table that matched the walkthrough would refuse every real review.
  printf '<!-- CodeRabbit review command invocation: v2:deadbeef -->\n' > "$TMPD/probe"
  [ -n "$(hits "$INVOCATION_ACK" "$TMPD/probe")" ] || {
    echo "self-test: the acknowledgement table does not match an invocation reply" >&2; exit 2; }
  printf '<!-- walkthrough_start -->\n' > "$TMPD/probe"
  if [ -n "$(hits "$INVOCATION_ACK" "$TMPD/probe")" ]; then
    echo "self-test: the acknowledgement table matches a review marker, which would" >&2
    echo "           refuse every review this reviewer publishes" >&2; exit 2
  fi
  [ -s "$TMPD/grep-fatal" ] && exit 2
  printf '%s\n' "$SELFTEST_OK"
  exit 0
fi

pr=""; repo=""; want_head=""; want_reviewer=""; for_check=""; skip_merge_check=""
record_doc=""
if [ "${1:-}" = "--match-check" ]; then
  [ -n "${2:-}" ] && [ "$#" -eq 2 ] || usage
  # A table that will not compile answers "not a reviewer's check" to every name, which
  # would silently unscope the caller's clearance calls.
  validate_tables || exit 2
  match_check "$2"; exit $?
fi

# --- argument parsing --------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)     repo="${2:-}";           [ -n "$repo" ] || usage; shift 2 ;;
    --head)     want_head="${2:-}";      [ -n "$want_head" ] || usage; shift 2 ;;
    --reviewer) want_reviewer="${2:-}";  [ -n "$want_reviewer" ] || usage; shift 2 ;;
    --for-check) for_check="${2:-}";     [ -n "$for_check" ] || usage; shift 2 ;;
    --no-merge-check) skip_merge_check=yes; shift ;;
    --record)   record_doc="${2:-}";     [ -n "$record_doc" ] || usage; shift 2 ;;
    -h|--help)  usage ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) [ -z "$pr" ] || { echo "error: unexpected argument '$1'" >&2; usage; }
       pr="$1"; shift ;;
  esac
done
[ -n "$pr" ] || usage

# --- --for-check: whose review clears THIS required check ---------------------
# Without it, "a review exists on this PR" is asked of every reviewer at once, so on a
# repo with two of them one vendor's review clears the other vendor's required check
# while that vendor was rate-limited. The check name resolves to the REVIEWERS rows that
# own it, and only those logins are considered below. A name no row owns is not a
# question this script can answer — it refuses rather than widening to everybody.
check_owners=""
if [ -n "$for_check" ]; then
  check_owners="$(owners_of_check "$for_check")"
  [ -n "$check_owners" ] || {
    echo "error: no reviewer in this script's table owns the check '$for_check', so" >&2
    echo "       whose review would clear it is unknown. Refusing (fail closed). Add a" >&2
    echo "       row to REVIEWERS, or name the account with --reviewer <login>." >&2
    exit 2
  }
  [ -n "$want_reviewer" ] && {
    echo "error: --for-check and --reviewer both name whose review counts; pass one." >&2
    exit 2
  }
fi

# The verdict trailer is honoured only for an explicitly named NON-VENDOR account. See
# the tier-4 note: `--reviewer coderabbitai` used to re-arm the highest tier in the file
# against that vendor's own machine-readable refusal.
trailer_armed=""
if [ -n "$want_reviewer" ] && ! match_reviewer "$want_reviewer"; then trailer_armed=yes; fi

for tool in gh jq; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "error: $tool not found — cannot read reviewer state, so this refuses" >&2
    exit 2
  }
done

TMPD="$(mktemp -d)" || {
  echo "error: could not create a temp dir — refusing (fail closed)" >&2
  exit 2
}
trap 'rm -rf "$TMPD"' EXIT

# Before a single artifact is read: every row of every table has to compile. See
# validate_tables — a broken refusal row reads a refusal as a review.
validate_tables || exit 2

# bash 3.2 (the macOS default) errors on "${arr[@]}" when arr is empty under `set -u`.
R=()
[ -n "$repo" ] && R=(--repo "$repo")

# --- the PR, and then its artifacts -------------------------------------------
# `gh pr view` answers the PR's own facts and nothing else here. It does NOT expose a
# review's `commit_id`, which is the whole reason this file used to pin a review by
# whether its body happened to mention the head SHA — the property the REFUSAL also has.
# `/repos/{owner}/{repo}/pulls/{n}/reviews` does expose it, alongside the review's
# `state`, so the two API calls below are what make routes A and B structural.
raw="$(gh pr view "$pr" ${R[@]+"${R[@]}"} \
       --json url,number,headRefOid,author,mergeable,mergeStateStatus,commits 2>/dev/null)" || {
  echo "error: could not read PR $pr${repo:+ in $repo} — refusing (fail closed)" >&2
  exit 2
}

# Every column is emitted unconditionally (`// ""`, never `// empty`): a jq array element
# that vanishes shifts every field after it one left, and `cut -f` reads the wrong one.
meta="$(printf '%s' "$raw" \
        | jq -r '. as $p
                 | [.url, .headRefOid, (.author.login // ""), (.number // "" | tostring),
                    (.mergeable // ""), (.mergeStateStatus // ""),
                    ([ (.commits // [])[]
                       | select(.oid == $p.headRefOid) | (.committedDate // "") ]
                     | last // "")] | @tsv' \
          2>/dev/null)" || meta=""
# ONE LINE WITH A TAB IN IT (or nothing at all) is split here, field by field, which is
# what `cut -f` prints for it: an empty field stays empty and a missing one is empty. Any
# other shape — several lines, or a line with no tab, which `cut` echoes whole into every
# field — still goes through `cut`, so no input reads differently than it did.
TAB=$'\t'; NL=$'\n'
case "$meta" in
  *"$NL"*)       meta_shape=other ;;
  ''|*"$TAB"*)   meta_shape=line ;;
  *)             meta_shape=other ;;
esac
if [ "$meta_shape" = line ]; then
  rest="$meta$TAB"
  url="${rest%%"$TAB"*}";         rest="${rest#*"$TAB"}"
  head_sha="${rest%%"$TAB"*}";    rest="${rest#*"$TAB"}"
  pr_author="${rest%%"$TAB"*}";   rest="${rest#*"$TAB"}"
  pr_number="${rest%%"$TAB"*}";   rest="${rest#*"$TAB"}"
  mergeable="${rest%%"$TAB"*}";   rest="${rest#*"$TAB"}"
  merge_state="${rest%%"$TAB"*}"; rest="${rest#*"$TAB"}"
  head_date="${rest%%"$TAB"*}"
else
  url="$(printf '%s' "$meta" | cut -f1)"
  head_sha="$(printf '%s' "$meta" | cut -f2)"
  pr_author="$(printf '%s' "$meta" | cut -f3)"
  pr_number="$(printf '%s' "$meta" | cut -f4)"
  mergeable="$(printf '%s' "$meta" | cut -f5)"
  merge_state="$(printf '%s' "$meta" | cut -f6)"
  head_date="$(printf '%s' "$meta" | cut -f7)"
fi
nwo="$(printf '%s' "$url" | sed -E 's#^https?://[^/]+/([^/]+/[^/]+)/pull/[0-9]+.*#\1#')"
[ -n "$url" ] && [ -n "$head_sha" ] && [ -n "$pr_number" ] && [ "$nwo" != "$url" ] || {
  echo "error: could not resolve the head SHA / repo of PR $pr — refusing (fail closed)" >&2
  exit 2
}

# The clearance record the PreToolUse hook reads offline (ai-bridge-v3/task-044) — exit 0
# here is precondition 2's FIRST HALF, so this line is one of four and never a merge permit
# on its own. Silent on any failure: it cannot change the answer this script gives.
mint_receipt() {
  "$RC_DIR/clearance-receipt.sh" record review-clearance.sh \
    --repo "$nwo" --pr "$pr_number" --head "$head_sha" >/dev/null 2>&1 || true
}

# AND THE AUTHOR LOGIN IS PART OF THAT GUARD, because a field that is missing here does
# not fail — it silently switches off a rule. SCHEMA.md clause 8 (an author is never its
# own independent reviewer) is enforced below by comparing logins against `$pr_author`, so
# an absent or empty one turns both comparisons into a test against the empty string,
# which nothing equals: the reviewer account then clears its own pull request, and the two
# `continue`s that exist to stop it never fire. Every PR has an author, so no author means
# the read did not answer — unknown state, and unknown fails closed.
[ -n "$pr_author" ] || {
  echo "error: PR $pr reports no author login, so the rule that an author is not its own" >&2
  echo "       independent reviewer ($AB_SCHEMA, clause 8) cannot be applied — and a rule" >&2
  echo "       that cannot be applied is not a rule that passes. Refusing (fail closed)." >&2
  exit 2
}

# --- THE FIRST CHECK: can this PR merge at all? -------------------------------
# Before any artifact is read, because no review makes a conflicting PR mergeable. See
# "MERGEABILITY IS THE FIRST CHECK" in the header for the incident and for why UNKNOWN
# holds. `mergeable` ∈ MERGEABLE|CONFLICTING|UNKNOWN; `mergeStateStatus` ∈ CLEAN|BLOCKED|
# DIRTY|UNSTABLE|BEHIND|HAS_HOOKS|DRAFT|UNKNOWN. Only DIRTY/CONFLICTING is a conflict;
# BEHIND matters only under strict up-to-date, which is the merge gate's question and not
# this one.
# `--record` PERSISTS THIS READ WHERE THE NO-NETWORK RENDERERS CAN SEE IT. `write-snapshot.sh`
# is deterministic and offline by contract, so without a record it minted a merge verb from
# `status: in-review` plus a PR link and nothing else. The value is written HERE, in the call
# that made the read, so the board cannot disagree with what the gate saw. It is the tick's
# LAST read, not a cache consulted instead of asking: every tick overwrites it, and a task
# carrying none is not MERGEABLE, so the verb fails closed.
if [ -n "$record_doc" ] && [ -f "$record_doc" ]; then
  rc_state="$mergeable"
  case "$merge_state" in DIRTY) rc_state=CONFLICTING ;; esac
  case "$rc_state" in MERGEABLE|CONFLICTING) ;; *) rc_state=UNKNOWN ;; esac
  # Beside the record document, so the `mv` is a rename and never a half-written doc, and
  # every step refuses: a stale `pr_mergeable:` is the board minting a merge verb the gate
  # never saw, which is the whole defect `--record` exists to close.
  rc_tmp="$(mktemp "$(dirname "$record_doc")/.review-clearance.XXXXXX")" || {
    echo "error: cannot create a temp file beside $record_doc to record the mergeability read" >&2
    exit 2
  }
  RC_VAL="$rc_state" awk '
    BEGIN { v = ENVIRON["RC_VAL"] }
    NR == 1 && $0 == "---" { n = 1; print; next }
    n == 1 && $0 == "---" { if (!done) { print "pr_mergeable: " v; done = 1 } n = 2; print; next }
    n == 1 && !done && index($0, "pr_mergeable:") == 1 { print "pr_mergeable: " v; done = 1; next }
    { print }
  ' "$record_doc" > "$rc_tmp" || {
    rm -f "$rc_tmp"
    echo "error: could not rewrite pr_mergeable: in $record_doc — refusing (fail closed)" >&2
    exit 2
  }
  mv -f "$rc_tmp" "$record_doc" || {
    rm -f "$rc_tmp"
    echo "error: could not write $record_doc with the mergeability read — refusing (fail closed)" >&2
    exit 2
  }
fi

if [ -z "$skip_merge_check" ]; then
  case "$mergeable" in
    CONFLICTING)
      echo "refuse: PR $pr cannot merge — the host reports mergeable=CONFLICTING at" >&2
      echo "        $head_sha (mergeStateStatus=${merge_state:-unreported}). Rebase it" >&2
      echo "        onto the default branch and push; do NOT request a review for this." >&2
      exit 7 ;;
  esac
  case "$merge_state" in
    DIRTY)
      echo "refuse: PR $pr cannot merge — the host reports mergeStateStatus=DIRTY at" >&2
      echo "        $head_sha (mergeable=${mergeable:-unreported}), which is conflicts." >&2
      echo "        Rebase it onto the default branch and push; do NOT request a review." >&2
      exit 7 ;;
  esac
  case "$mergeable" in
    MERGEABLE) ;;
    *)
      echo "error: PR $pr reports mergeable='${mergeable:-}' at $head_sha, which is not a" >&2
      echo "       usable answer. The host computes this lazily and says UNKNOWN for" >&2
      echo "       seconds after the base moves — so this is unknown state, and unknown" >&2
      echo "       fails closed. Ask again next tick." >&2
      exit 2 ;;
  esac
  case "$merge_state" in
    CLEAN|BLOCKED|UNSTABLE|BEHIND|HAS_HOOKS|DRAFT) ;;
    *)
      echo "error: PR $pr reports mergeStateStatus='${merge_state:-}' at $head_sha, which" >&2
      echo "       is not a usable answer — UNKNOWN while the host recomputes, empty for a" >&2
      echo "       token without push access, or a value this script has not been taught." >&2
      echo "       Unknown state, and unknown fails closed. Ask again next tick." >&2
      exit 2 ;;
  esac
fi

# AN ARTIFACT LIST THIS SCRIPT CANNOT READ IS UNKNOWN REVIEWER STATE, NOT AN EMPTY ONE:
# reading a transient 5xx as "no reviews" is a refusal today, and would be a clearance the
# moment anything downstream treated exit 3 as benign. Both lists refuse outright.
#
# AND BOTH ARE PAGINATED, which is not tidiness. `gh pr view --json comments` answers one
# page and says nothing about a second, and the artifact this file exists to find — the
# REFUSAL — is a COMMENT. A truncated review list loses a clearance and lands on exit 3 or
# 4; a truncated comment list loses the refusal and turns exit 1 into exit 0, which is the
# only direction that matters. So the comments come from the REST endpoint, `--paginate`d
# like the reviews, and the two sources are now read the same way.
gh api "/repos/$nwo/pulls/$pr_number/reviews?per_page=100" --paginate \
  --jq '.[] | {login: (.user.login // ""), state: (.state // ""),
               commit: (.commit_id // ""), body: (.body // "")}' \
  > "$TMPD/reviews.ndjson" 2>/dev/null || {
  echo "error: could not read the review objects on PR $pr ($nwo) — refusing." >&2
  echo "       Whether anybody reviewed this head is unknown, and unknown fails closed." >&2
  exit 2
}
gh api "/repos/$nwo/issues/$pr_number/comments?per_page=100" --paginate \
  --jq '.[] | {login: (.user.login // ""), body: (.body // ""),
               created: (.created_at // "")}' \
  > "$TMPD/comments.ndjson" 2>/dev/null || {
  echo "error: could not read the comments on PR $pr ($nwo) — refusing. A refusal this" >&2
  echo "       script cannot see is a refusal that did not happen, and that is a merge." >&2
  exit 2
}

# --- WHICH ACCOUNTS ANSWER THROUGH THE STRUCTURED CHANNEL --------------------
# Every login with at least one review object on this PR, in any state, at any commit.
# Route C (the vendor's review marker in a COMMENT) is consulted only for an account that
# appears nowhere in this list — see TEST 2. Read once, before the loop, so the answer
# does not depend on the order the host streamed the artifacts in.
jq -r '.login // empty' "$TMPD/reviews.ndjson" > "$TMPD/rlogins" 2>/dev/null || {
  echo "error: could not read who published the review objects on PR $pr — refusing." >&2
  echo "       An unreadable list would re-arm the comment route it is here to close." >&2
  exit 2
}
review_object_logins=""
[ -s "$TMPD/rlogins" ] && \
review_object_logins="$(while IFS= read -r l; do norm "$l"; echo; done < "$TMPD/rlogins" \
                        | sort -u)"

has_review_object() { # <login>
  printf '%s\n' "$review_object_logins" | grep -Fqx "$(norm "$1")"
}

# The verified head the caller pinned must still be the PR's head; if it is not, every
# answer below is about a different commit. Same rule as required-checks.sh, reported as
# staleness because that is what it is.
if [ -n "$want_head" ] && [ "$want_head" != "$head_sha" ]; then
  echo "refuse: head moved — verified $want_head, PR $pr is now at $head_sha" >&2
  exit 4
fi

# The implementing author is never its own independent reviewer (SCHEMA.md, clause 8).
if [ -n "$want_reviewer" ] && [ "$(norm "$want_reviewer")" = "$(norm "$pr_author")" ]; then
  echo "error: --reviewer $want_reviewer is the author of PR $pr — an author cannot be" >&2
  echo "       its own independent reviewer. Refusing." >&2
  exit 2
fi

# --- split the artifacts into files ------------------------------------------
# Bodies are multi-line markdown, so they cannot travel as TSV fields. jq emits a header
# line then the raw body; awk cuts on the header.
#
# THE SEPARATOR IS RANDOM PER RUN, and that is a security property rather than a style.
# Artifact bodies are attacker-writable — anyone who can comment on a PR can write
# anything into one — so a fixed sentinel could be typed into a comment to forge a record
# boundary and fabricate an artifact with an author, a state and a commit_id of the
# forger's choosing. Sixteen random bytes cannot be guessed by the text being parsed. The
# length is asserted EXACTLY (4 + 32 hex digits): a `>` test passes on a separator with
# six bytes of entropy in it, which is guessable.
SEP="okf-$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
[ "${#SEP}" -eq 36 ] || {
  echo "error: could not generate a record separator — refusing (fail closed)" >&2
  exit 2
}

jq -rn --arg s "$SEP" --slurpfile rv "$TMPD/reviews.ndjson" \
                       --slurpfile cm "$TMPD/comments.ndjson" '
    ( ($rv[] | {kind:"review",  login:(.login // ""), state:(.state // ""),
                commit:(.commit // ""), created:"",                body:(.body // "")}),
      ($cm[] | {kind:"comment", login:(.login // ""), state:"",
                commit:"",              created:(.created // ""), body:(.body // "")}) )
    | "\($s)\u001f\(.kind)\u001f\(.login)\u001f\(.state)\u001f\(.commit)\u001f\(.created)",
      .body
  ' 2>/dev/null > "$TMPD/stream" || {
  echo "error: could not parse the artifacts on PR $pr — refusing (fail closed)" >&2
  exit 2
}

: > "$TMPD/index"
awk -v s="$SEP" -v dir="$TMPD" '
  substr($0, 1, length(s) + 1) == s "\037" {
    if (f) close(f)
    n++
    print substr($0, length(s) + 2) >> (dir "/index")
    f = dir "/body." n
    printf "" > f
    next
  }
  f { print >> f }
' "$TMPD/stream"

# --- the block structure: ONE machine, read TWO ways --------------------------
#
# BOTH RENDERINGS BELOW ASK ONE QUESTION — which lines of this body does the host put on
# the page as MARKUP — and neither can answer it exactly, because the exact answer is the
# host's whole CommonMark implementation. Five rounds found the same defect five times: a
# construct the machine did not model made the two sides disagree, and every disagreement
# failed OPEN. Enumerating the constructs is what keeps repeating.
#
# SO THE MACHINE IS READ TWICE AND THE DISAGREEMENT IS THE ANSWER. Reading A is fences and
# blockquotes alone. Reading B additionally models the CONTAINERS a fence lives in: a
# raw-HTML block, inside which ``` is literal HTML and opens nothing, and a list item, with
# which a fence dies. Then
#
#   the REFUSAL side keeps a line EITHER reading keeps      (the union)
#   the CLEARING side keeps a line only if BOTH keep it     (the intersection)
#
# WHAT THAT CONSTRUCTION IS AND IS NOT, corrected from the claim it shipped with. It gives
# exactly one thing, structurally: `strict ⊆ stripped`, because an intersection is a subset
# of a union whatever either reading gets wrong. IT DOES NOT MAKE THE REFUSAL SIDE SAFE.
# The claim was that a crude reading can only cost a FALSE REFUSAL, because the other
# reading covers it. That is false, and the counter-example is three lines:
#
#     - ```
#     - Review limit reached...
#     - ```
#
# The union removes a line only when EVERY reading removes it — it is an AND-gate over the
# readings, not a safety net over the host. A mistake the readings SHARE is inherited by
# their union, and here they shared one: A does not model list items, and B ended an item
# only on a dedent, which a sibling marker is not. Both hid the refusal; the union hid it;
# the host puts it on the page as an ordinary bullet. A false CLEARANCE is reachable
# through the refusal side, which is the direction the whole construction was built to
# rule out.
#
# SO THE PROPERTY THAT MATTERS CANNOT BE DERIVED FROM THE READINGS, AND IS MEASURED
# INSTEAD. No relation between two models of a renderer bounds the distance from either to
# the renderer. The invariant this file now claims is stated against the host and checked
# against the host's own answers, recorded in `tests/fixtures/reviewer/host-rendering.txt`:
#
#   EVERY LINE GITHUB RENDERS AS READABLE PROSE REACHES THE REFUSAL TABLES, AND NO LINE
#   WHOSE CHARACTERS GITHUB PUTS ON THE PAGE CAN CLEAR A PULL REQUEST.
#
# 145 bodies, each answered by github.com itself and re-recordable by the script beside the
# fixture. Adding a reading is still how a new construct is covered, and the union still
# means a reading crude in one direction is covered by the other IN THE CASES WHERE THEY
# DIFFER — but "a reading was added, so it is safe" is not an argument any more. The case
# goes in the fixture and the host answers.
#
# WHICH IS ALSO WHY EACH READING IS KEPT AS EXACT AS IT IS CHEAP TO BE, rather than left
# deliberately crude: crude no longer costs only a false refusal.
#
# WHAT READING A ALREADY FOLLOWS, each of which cost a round to find: a fence may be
# indented at most three COLUMNS, tabs advancing to four-column stops; it opens inside the
# blockquote it is written in, and a line that has left that quote has left the block; a
# closer may be no shorter than its opener and may carry no info string; and a backtick
# opener whose info string contains a backtick opens nothing at all.
#
# WHICH WAY EACH MISTAKE FAILS IS THE POINT. Text the host renders as TEXT must reach the
# refusal tables — calling it a fence hides a refusal a human can plainly read. Text the
# host renders as CODE is a quotation, and a quoted refusal is read here as a discussion of
# one rather than as one: deliberate, tested, and unchanged.
FENCE_AWK='
# ws_scan(line, i, col) — advance over spaces and tabs from byte i at column col, into
# W_I / W_COL. A tab advances to the next FOUR-COLUMN STOP, which is how the host measures
# indentation: 1-3 spaces then a tab reaches column 4 and is literal code, not markup.
function ws_scan(line, i, col,   c, n) {
  n = length(line)
  while (i <= n) {
    c = substr(line, i, 1)
    if (c == " ") { col++; i++ }
    else if (c == "\t") { col += 4 - (col % 4); i++ }
    else break
  }
  W_I = i; W_COL = col
}
# scan_line(line) — peel the CONTAINER MARKERS this line opens, each of which may sit at
# most three columns inside the container before it, and report what is left: L_DEPTH
# blockquotes deep, L_BASE the column the content starts at, L_INDENT the columns of
# indentation past that, L_REST the text, L_BLANK whether there is any, and L_LIST the
# content column of a list item this line opened (-1 for none). A > or a - four columns
# past its container is literal text rather than a marker, so all of it is one pass.
function scan_line(line,   i, col, base, adv, s, k) {
  i = 1; col = 0; base = 0; L_DEPTH = 0; L_LIST = -1
  while (1) {
    ws_scan(line, i, col)
    if (W_COL - base > 3) break
    s = substr(line, W_I)
    if (substr(s, 1, 1) == ">") k = 1
    else if (s ~ /^([-+*]|[0-9]{1,9}[.)])([ \t]|$)/) k = match(s, /^[0-9]{1,9}[.)]/) ? RLENGTH : 1
    else break
    i = W_I + k; col = W_COL + k; base = col
    # The one space after a marker belongs to the marker. A TAB there is expanded and ONE
    # COLUMN of it is consumed, so what is left of it still counts as indentation.
    if (substr(line, i, 1) == " ") { i++; col++; base = col }
    else if (substr(line, i, 1) == "\t") {
      adv = 4 - (col % 4); col += adv; i++; base = col - adv + 1
    }
    if (substr(s, 1, 1) == ">") L_DEPTH++; else L_LIST = base
  }
  ws_scan(line, i, col)
  L_BASE = base; L_INDENT = W_COL - base; L_REST = substr(line, W_I); L_BLANK = (L_REST ~ /^[[:space:]]*$/)
}
# fence_of() — the fence marker on the line scan_line() just read, into F_CHAR (its
# character), F_LEN (the length of its RUN) and F_INFO (the info string after it). The last
# two are what decide whether a marker CLOSES anything.
function fence_of(   s, c, k, n) {
  F_CHAR = ""; F_LEN = 0; F_INFO = ""
  if (L_INDENT >= 4) return 0
  s = L_REST; c = substr(s, 1, 1)
  if (c != "`" && c != "~") return 0
  n = length(s); k = 0
  while (k < n && substr(s, k + 1, 1) == c) k++
  if (k < 3) return 0
  F_CHAR = c; F_LEN = k; F_INFO = substr(s, k + 1)
  return 1
}
# ended_item(base) — has the LIST ITEM whose content starts at column `base` ended on this
# line? Two ways, and only one of them used to be here. A line that DEDENTS past the item
# ends it, which was modelled. A SIBLING MARKER at or before that content column
# ends it too, which was not. That omission is how a refusal spelled as three sibling
# bullets — a fence marker, the words, a fence marker — disappeared from BOTH readings and
# therefore from their union: nothing dedents, so the fence opened in the first item stayed
# open across the second, while the host closes it at the end of that item and puts the
# refusal on the page as an ordinary bullet. A DEEPER marker (L_LIST > base) opens a nested
# item inside this one and ends nothing.
# A fence opened at TOP LEVEL records base 0 and this answers 0 for every line, which is
# why there is no guard for it: no list marker has a content column of 0, and no line
# indents to less than column 0. A guard nothing can make fire is a branch no test can
# reach, so it is arithmetic rather than a condition.
function ended_item(base) {
  if (L_LIST >= 0) return (L_LIST <= base)
  return (!L_BLANK && L_BASE + L_INDENT < base)
}
# step(m, containers) — that line through reading m: 0 outside every block, 1 a fence
# marker line, 2 inside a block. containers=1 adds reading B two rules, and only reading B
# keeps the HTML-block and list state (HB, LI). BC[m] is non-empty at EOF exactly when that
# reading cannot pair the fences.
function step(m, containers,   f) {
  f = fence_of()
  if (BC[m] != "") {
    if (L_DEPTH < BD[m]) BC[m] = ""
    else if (containers && ended_item(BI[m])) BC[m] = ""
    else if (f && F_CHAR == BC[m] && F_LEN >= BL[m] && L_DEPTH == BD[m] \
             && F_INFO ~ /^[[:space:]]*$/) { BC[m] = ""; return 1 }
    else return 2
  }
  if (containers) {
    # A LIST ITEM the fence would live in, and the line that ends it. A fence opened at
    # top level records no container (BI 0) and this rule never fires for it.
    if (L_LIST >= 0) LI = L_LIST
    else if (!L_BLANK && L_BASE + L_INDENT < LI) LI = 0
    # A RAW-HTML BLOCK: what is in it is HTML, so ``` in it is three backticks the reader
    # can see and not a fence. Any tag opens one and a blank line ends it — deliberately
    # not a list of tag names, because a name this did not know is how the last round
    # reopened. Wrong in either direction, the other reading covers it.
    # …and it ends the way every other container-bound block does: at a blank line, on
    # leaving the blockquote it opened in, or at the end of the list item that held it.
    # Ending only at a blank line left it open to the end of the body.
    #
    # WHAT BOUNDING IT BUYS, stated exactly rather than generously, because a header claim
    # the code does not keep is the recurring defect in this file. It buys ACCURACY, not a closed
    # clearing route: reading B keeping a line only matters to the CLEARING side if reading
    # A keeps it too, and A already reads every fence this rule reveals. What an unbounded
    # HTML block cost was FALSE REFUSALS — text the host quotes, read here as text a human
    # can see. The tests for these branches are therefore over-correction guards, and they
    # assert exit 4 where the host says the words are in a code block.
    if (HB && (L_BLANK || L_DEPTH < HBD || ended_item(HBI))) HB = 0
    if (HB) return 0
    if (L_INDENT <= 3 && L_REST ~ /^<\/?[A-Za-z]/) { HB = 1; HBD = L_DEPTH; HBI = LI + 0; return 0 }
  }
  # The info string of a BACKTICK opener may not contain a backtick: the host renders
  # ```a`b as inline code and opens no block at all.
  if (f && (F_CHAR != "`" || index(F_INFO, "`") == 0)) {
    BC[m] = F_CHAR; BL[m] = F_LEN; BD[m] = L_DEPTH; BI[m] = containers ? LI : 0
    return 1
  }
  return 0
}
# render(line) — both readings of one line, into S1 and S2. scan_line runs once: step()
# only reads what it left behind.
function render(line) { scan_line(line); S1 = step(1, 0); S2 = step(2, 1) }
'

# --- the two renderings, written in one pass ----------------------------------
#
# STRIPPED is what the REFUSAL tables read: the union above. Strip too much here and a
# refusal disappears, which is the failure this whole file exists to stop.
#
# STRICT is what the CLEARING side reads — the review marker, the verdict trailer, the head
# token, and the body `renders_content` is measured on. It is the intersection, minus two
# more things the host renders as literal text: an INDENTED code block, and a line inside a
# multi-line code SPAN. The span rule is how PROSE used to reach the evidence half — a body
# spelling the vendor marker between backticks matched it, which is how the review that
# found this had to break its own verdict to post it. Strip too little here and text a
# human reads as a quotation is read as markup.
#
# AN UNBALANCED READING IS NOT A READING. A body whose fences do not pair cannot be read as
# fenced markdown at all: one prepended ``` used to blank the body and every refusal in it.
# So that reading keeps EVERYTHING on the refusal side and NOTHING on the clearing side,
# and either reading being unbalanced is enough. Unsure fails closed on both sides.
render_body() { # <body-file> <stripped-out> <strict-out>
  : > "$2"; : > "$3"                 # awk writes nothing when it keeps nothing
  awk -v sw="$2" -v st="$3" "$FENCE_AWK"'
    { raw[NR] = $0
      render($0)
      inspan = (SPAN % 2)            # an odd running count of backtick RUNS: a span is open
      if (S1 == 0 && S2 == 0) { t = $0; SPAN += gsub(/`+/, "&", t) }
      if (S1 == 0 || S2 == 0) wide[NR] = 1
      if (S1 == 0 && S2 == 0 && !inspan && L_INDENT < 4) tight[NR] = 1
    }
    END {
      unbal = (BC[1] != "" || BC[2] != "")
      for (i = 1; i <= NR; i++) {
        if (unbal || wide[i]) print raw[i] > sw
        if (!unbal && tight[i]) print raw[i] > st
      }
    }
  ' "$1"
}

# renders_content <strict-body-file> — does this body put anything on the page a human can
# SEE? Used by route A, where "the object carries a claim" is the difference between a
# review and a thread reply the host minted a COMMENTED object for.
#
# IT ASKS WHAT IS LEFT, NOT WHAT TO TAKE AWAY, AND THAT IS THE FIX. Subtracting the
# invisible needs a complete list of everything invisible, which is the same never-finished
# enumeration the vendor tables were: the first cut removed six zero-width characters and
# the HTML comment; thirteen more code points walked through it; and then a cut that knew
# two markup SHAPES — the comment and the tag — was walked through by seven more
# (`[//]: # (a comment)`, `[x]: /y`, `[](url)`, `<a href="1>2"></a>`, `<!DOCTYPE html>`,
# `<![CDATA[x]]>`, `<?php ?>`). Each round the list got longer and the route stayed open.
#
# SO THE THING BEING REMOVED IS NOW A CLOSED SET RATHER THAN A GROWING ONE, and that is the
# whole difference between deciding and enumerating. CommonMark defines exactly SIX raw-HTML
# productions — an open tag, a closing tag, a comment, a processing instruction, a
# declaration and a CDATA section — and there is no seventh to be found next round; knowing
# two of them was the enumeration, knowing the specification is the decision. Beside them
# sit the two other places the source carries bytes the page never shows: a LINK REFERENCE
# DEFINITION, which renders nothing at all, and the DESTINATION of a link or an image
# (and an image is nothing but a destination, since its alt text is not on the page).
# Everything else is text, and the question asked of the text is unchanged: is there an
# ASCII letter or digit, the only thing this script can be certain a human sees.
#
# EVERY RULE HERE REMOVES, AND REMOVING FAILS CLOSED. Saying "blank" of a body that does
# render is exit 4 or a held claim — a human glance. Saying "content" of a blank one is a
# clearance for a review object that claims nothing, which is the route this function
# exists to shut. So where a rule is crude it is crude in the removing direction: a line
# whose bracketed label is followed by a colon is treated as a reference definition
# whatever else is on it.
#
# `print-board.sh` reaches the same conclusion from the other end, sanitising for a terminal
# by dropping every code point in Unicode general category C — "one rule rather than a
# blocklist of known-bad sequences". That implementation is not reused, for two reasons
# rather than by preference: it is python3 + unicodedata, and a merge gate that refuses
# whenever python3 is missing buys nothing here; and category C would not answer THIS
# question anyway — measured over the thirteen code points that defeated the second cut, it
# would have missed FIVE, because U+115F and U+3164 are LETTERS that render blank and
# U+FE00/U+FE0F/U+034F are MARKS. Requiring something visible subsumes all thirteen without
# naming any.
#
# AND IT IS NO LONGER ARGUED, IT IS MEASURED. `tests/fixtures/reviewer/host-rendering.txt`
# records what github.com itself puts on the page for each of these constructs, and the
# suite asserts that nothing the host renders blank is read here as a claim.
#
# WHAT IT COSTS: a body with no ASCII alphanumeric anywhere in it — written entirely in
# another script, or in emoji — is read as saying nothing, and pays the bill above.
renders_content() { # 0 when something renders, 1 when the page stays blank
  LC_ALL=C awk '
    # The terminator of the raw-HTML production starting at `line`, and how many bytes of
    # it to skip first. Returns "" when the < is just a less-than sign.
    function opens(line,   name) {
      if (substr(line, 1, 4) == "<!--")      { SKIP = 4; return "-->" }
      if (substr(line, 1, 2) == "<?")        { SKIP = 2; return "?>" }
      # CommonMark lists a CDATA SECTION as its own production, ending at ]]>. This does
      # not, because the host does not: asked for `<![CDATA[a > b]]>` github.com answers
      # ` b]]&gt;`, having ended the construct at the first > exactly as it ends a
      # declaration. Recorded as `c-cdata-with-gt`. Following the specification here would
      # remove text the page shows — safe, but wrong, and there is no reason to be wrong.
      if (substr(line, 1, 2) == "<!")        { SKIP = 2; return ">" }
      name = line; sub(/^<\//, "<", name)
      # A tag name is a letter then letters, digits and hyphens, and what follows it must
      # end the name: whitespace, a solidus or the closing bracket. Without that last test
      # an AUTOLINK — <https://example.com/a>, whose text the page DOES show — reads as a
      # tag called "https" and the visible URL is thrown away.
      if (name ~ /^<[A-Za-z][A-Za-z0-9-]*([[:space:]\/>]|$)/) {
        SKIP = 1; return ">"
      }
      return ""
    }
    {
      line = $0
      # A LINK REFERENCE DEFINITION is the whole line and none of it reaches the page, so
      # the line is SKIPPED — scanner state and all. That looks wrong (a line could both be
      # a definition and open a multi-line construct, and skipping it would leave the
      # construct open forever), and the host says it is right: given `   [a]: /b<!--` the
      # destination swallows the opener and github.com answers with the FOLLOWING lines
      # visible, no comment ever opened. Where the opener is instead separated from the
      # destination the line is not a definition at all and the host shows the whole of it,
      # which this drops — a false blank, which is the safe direction. Both are recorded.
      if (!inhtml && line ~ /^[[:space:]]{0,3}\[[^]]*\]:/) next
      out = ""
      while (length(line) > 0) {
        if (inhtml != "") {
          p = index(line, inhtml)
          if (p == 0) { line = ""; break }
          line = substr(line, p + length(inhtml)); inhtml = ""; continue
        }
        p = index(line, "<")
        if (p == 0) { out = out line; line = ""; break }
        out = out substr(line, 1, p - 1); line = substr(line, p)
        term = opens(line)
        if (term == "") { out = out "<"; line = substr(line, 2); continue }
        line = substr(line, SKIP + 1); inhtml = term
        # Inside an OPEN TAG the > that ends it may sit in a quoted attribute value, so the
        # quotes are honoured rather than the first > taken. <a href="1>2"></a> is one tag
        # and a blank page; read to the first > it is a tag plus the visible text 2".
        if (term == ">") {
          q = ""
          while (length(line) > 0) {
            c = substr(line, 1, 1); line = substr(line, 2)
            if (q != "") { if (c == q) q = "" }
            else if (c == "\"" || c == "'"'"'") q = c
            else if (c == ">") { inhtml = ""; break }
          }
        }
      }
      text = text "\n" out
    }
    END {
      # The DESTINATION of a link is an instruction; its label is the text. An IMAGE is
      # all destination, alt text included: the page shows a picture, not the words.
      gsub(/\]\([^)]*\)/, "]", text)          # [label](dest) -> [label]
      gsub(/\]\[[^]]*\]/, "]", text)          # [label][ref]  -> [label]
      gsub(/!\[[^]]*\]/, "", text)            # ![alt]        -> nothing
      gsub(/&#?[0-9A-Za-z]+;/, "", text)      # a character reference is one glyph or none
      exit(text ~ /[0-9A-Za-z]/ ? 0 : 1)
    }
  ' "$1" 2>/dev/null
}

# Every prefix of the head from 7 chars up, so an artifact may name the commit in full or
# abbreviated. Compared against the hex tokens in the body, never against a range syntax:
# the range is exactly what the refusal also carries.
awk -v h="$head_sha" 'BEGIN { for (i = 7; i <= length(h); i++) print substr(h, 1, i) }' \
  > "$TMPD/prefixes"

# names_head <strict-body-file> — does this artifact name the current head as a token of
# its own? URLs are removed first: a SHA inside a link (a compare view, a commit
# permalink, an avatar hash) is not the artifact claiming to have read that commit, and it
# used to count. This is route C's pin ONLY — routes A and B pin on `commit_id` and on the
# trailer's `head_sha` field, never on what the body happens to mention.
#
# A COMMIT HASH IS A WHOLE TOKEN, AND THAT IS NOT WHAT A SUBSTRING SEARCH FINDS. Scanning
# for a run of 7-40 hex characters finds one inside every UUID: the reviewer stamps its own
# refusal with `Run ID: f4981ca2-1bc7-4edf-9bb4-fd2f74e3693a`, whose first and last fields
# are hex runs of 8 and 12. That is the recorded fixture, not a construction — and it fed
# the one place this answer is consulted in the OPENING direction, `refusal_concerns_head`,
# where "it names some commit, and not this one" DEMOTES the refusal to an older one. Any
# refusal carrying a run id therefore read as being about another commit.
#
# So the body is cut into tokens FIRST, on everything a hash cannot contain, and a token
# counts only if the whole of it is hex. A field of a UUID is joined to the rest by `-`,
# so the token is `f4981ca2-1bc7-4edf-9bb4-fd2f74e3693a` and it is not hex. Both callers
# get safer: route C loses a pin (no clearance) and a refusal loses its demotion (it is
# weighed). A 32-hex identifier with no separators is still indistinguishable from a hash,
# and nothing here can tell them apart.
names_head() {
  sed -E "s#https?://[^[:space:])\"']*##g" "$1" 2>/dev/null \
    | tr -c '0-9A-Za-z_-' '\n' | grep -Ex '[0-9a-fA-F]{7,40}' \
    | tr '[:upper:]' '[:lower:]' > "$TMPD/toks"
  grep -qxF -f "$TMPD/prefixes" "$TMPD/toks"
}

# posted_at_head <artifact created_at> — was this COMMENT written after the current head
# was pushed? The second half of the exit-8 bound, and the only half that can ever fire
# against this vendor: CodeRabbit's acknowledgement names NO commit at all — its one hex
# token is a 64-character invocation hash, which `names_head` rejects by design — so a
# pin on what the body says would be a bound that reads as implemented and never holds.
# A comment created at or after the head commit's own date cannot be a receipt for an
# earlier head. Both timestamps must be the host's RFC 3339 UTC; anything else is unknown
# and unknown leaves the ask open, which is the cheap direction (one comment, no round).
stamp() { # <timestamp> -> comparable digits, or nothing at all
  [ -n "$1" ] || return 1
  printf '%s' "$1" | grep -Eqx '[0-9]{4}(-[0-9]{2}){2}T([0-9]{2}:){2}[0-9]{2}Z' || return 1
  printf '%s' "$1" | tr -cd '0-9'
}
head_stamp="$(stamp "$head_date")" || head_stamp=""
posted_at_head() {
  [ -n "$head_stamp" ] || return 1
  posted_stamp="$(stamp "$1")" || return 1
  [ "$posted_stamp" -ge "$head_stamp" ]
}

# refusal_concerns_head <stripped-body-file> — is this refusal about the commit being
# cleared? Consulted only to decide whether a CONTENTLESS review object at the head may
# outrank it, and only in the closing direction.
#
# A REFUSAL THAT NAMES NO COMMIT AT ALL IS A REFUSAL OF UNKNOWN SCOPE, AND UNKNOWN FAILS
# CLOSED. Requiring it to name THIS head let a refusal be dropped before it was weighed:
# the not-yet-reviewed placeholder names no SHA in its shortest form, so a placeholder plus
# an empty APPROVED object cleared. The recovery property this ordering exists for is
# unaffected, because it rests on a refusal that names a DIFFERENT commit — which still
# loses. `names_head` leaves the body's own hex tokens in $TMPD/toks, which is how "names
# no commit" is answered without reading the body twice.
refusal_concerns_head() {
  names_head "$1" && return 0        # it names this head
  [ -s "$TMPD/toks" ] || return 0    # it names no commit at all — scope unknown
  return 1                           # it names some other commit — an older refusal
}

# `hits` and `fatal_grep` are defined up with the tables, because --self-test drives them.

refusal_hits() { # <stripped-body-file> — the refusal lines, from any refusal tier
  { hits "$REFUSALS_TERMINAL" "$1"; hits "$REFUSALS_SENTINEL" "$1"
    hits "$NOT_YET" "$1";           hits "$REFUSALS" "$1"; } | head -3
}

# --- tier 4, parsed: is there a well-formed okf-verdict block for THIS head? ---
verdict_trailer() { # <strict-body-file>
  awk -v head="$head_sha" -v marker="$VERDICT_MARKER" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    {
      line = $0
      if (inblk) {
        if (line ~ /^[[:space:]]*-->[[:space:]]*$/) {
          inblk = 0
          if (verdict ~ /^(pass|changes-requested|inconclusive)$/ && reviewer != "" \
              && sha ~ /^[0-9a-f]{7,40}$/ && substr(head, 1, length(sha)) == sha) found = 1
          next
        }
        # A nested comment marker inside the block means this is not the flat, structured
        # trailer SCHEMA.md defines — discard it rather than carrying its fields onward.
        if (index(line, "<!--") > 0 || index(line, "-->") > 0) { inblk = 0; next }
        f = trim(line)
        if (f ~ /^[a-zA-Z_]+:/) {
          key = tolower(trim(substr(f, 1, index(f, ":") - 1)))
          val = tolower(trim(substr(f, index(f, ":") + 1)))
          if (key == "verdict")  verdict  = val
          if (key == "reviewer") reviewer = val
          if (key == "head_sha") sha      = val
        }
        next
      }
      # A trailer that opens INSIDE another HTML comment is rendered blank by the host and
      # is not a claim anybody can see — it is not a trailer.
      if (htmlopen == 0 && line ~ marker) {
        inblk = 1; verdict = ""; reviewer = ""; sha = ""; next
      }
      o = gsub(/<!--/, "&", line); c = gsub(/-->/, "&", line)
      htmlopen += o - c
      if (htmlopen < 0) htmlopen = 0
    }
    # A block nobody closed is not a block: dropping out of the loop inside one must not
    # leave its fields to be completed by the next one.
    END { exit(found ? 0 : 1) }
  ' "$1"
}

reopen_line() { # <stripped-body-file> — when the reviewer published a reopen time
  grep -Ei \
    -e 'next .{0,20}(review|run).{0,20}(available|in) ' \
    -e '(limit|quota|it) (will )?(reset|resets|resetting)' \
    -e 'try again (in|at|after) ' \
    -e 'available (again )?(in|at) ' \
    "$1" \
    | head -1 | sed -e 's/^[[:space:]]*\(>[[:space:]]*\)*//' -e 's/^[*#[:space:]]*//' \
                    -e 's/[*[:space:]]*$//'
}

# NOTHING CLEARS INSIDE THIS LOOP. Every artifact is classified, and the ranking is applied
# once, below, over what they all said — see "the decision" after the loop. An `exit 0` in
# here made the answer depend on the ORDER the host happened to stream the artifacts in,
# and review objects are streamed before comments, so it also made "a refusal is weighed
# before any clearance" true only of the cases that reached the bottom.
n=0; considered=0; refusal_body=""; refusal_from=""; refusal_kind=""
terminal_body=""; terminal_from=""
stale_from=""; stale_at=""; unproven_from=""
refusal_at_head=""; empty_from=""; empty_state=""; held_from=""; held_state=""
cleared_msg=""; ack_from=""; ack_at_head=""; incremental_from=""; marker_outranked=""
skip_from=""; other_refusal=""
self_reviews=0; self_at_head=0
# THE FIELDS ARE UNIT-SEPARATED, NOT TAB-SEPARATED, and that is not decoration: a tab is
# IFS WHITESPACE, so `read` collapses a run of them into one delimiter and every empty
# field shifts the rest left. A comment's empty state and commit used to sit at the end of
# the row where the loss was invisible; the moment a field followed them, it arrived in
# `state`. \037 is not whitespace, so an empty field stays an empty field.
while IFS=$'\037' read -r kind login state commit created; do
  n=$((n + 1))
  body="$TMPD/body.$n"
  [ -f "$body" ] || : > "$body"
  # AN ARTIFACT WITH NO AUTHOR IS UNREADABLE REVIEWER STATE, NOT AN IRRELEVANT ONE. This
  # used to `continue`, which drops it before TEST 1 has read it: a refusal published by an
  # account the API reported no login for was never weighed, so it could not stop a
  # contentless approval at the head from clearing. Whose artifact it is decides both
  # whether it counts and whether SCHEMA.md clause 8 excludes it, and neither question has
  # an answer here — the same reason a PR with no author login refuses above.
  [ -n "$login" ] || {
    echo "error: an artifact on PR $pr has no author login, so whether it is the" >&2
    echo "       reviewer's — and whether clause 8 excludes it — cannot be answered." >&2
    echo "       Unreadable reviewer state is not clearance. Refusing (fail closed)." >&2
    exit 2
  }

  # THE PR'S OWN AUTHOR IS NEVER ITS INDEPENDENT REVIEWER (SCHEMA.md clause 8), and this
  # is asked BEFORE the reviewer tables rather than after them. An author who is not a
  # vendor used to be dropped by the identity test as "not a reviewer", so its own review
  # objects at the head were invisible rather than refused: #227 carries two of them,
  # `COMMENTED` at the exact head, and nothing anywhere said why they did not count.
  if [ "$(norm "$login")" = "$(norm "$pr_author")" ]; then
    if [ "$kind" = "review" ]; then
      self_reviews=$((self_reviews + 1))
      [ "$commit" = "$head_sha" ] && self_at_head=$((self_at_head + 1))
    fi
    continue
  fi

  # Whose opinion counts, in three narrowing steps. --for-check restricts to the reviewer
  # that OWNS the required check being cleared, so one vendor's review cannot clear
  # another's; --reviewer names one account outright; with neither, the REVIEWERS table
  # decides. An account in none of them is ignored rather than trusted, so a teammate's
  # "lgtm" never stands in for the independent gate.
  if [ -n "$check_owners" ]; then
    match_patterns "$login" "$check_owners" || continue
  elif [ -n "$want_reviewer" ]; then
    [ "$(norm "$login")" = "$(norm "$want_reviewer")" ] || continue
  else
    match_reviewer "$login" || continue
  fi

  considered=$((considered + 1))
  render_body "$body" "$TMPD/stripped" "$TMPD/strict"

  # TEST 1 — did this artifact DECLINE to review? FIRST, for EVERY artifact from the
  # reviewer, because the refusal names the head too and a detector that pins first reads a
  # refusal as a review. Four tiers, highest first (see the tables): a structured verdict
  # from an explicitly named non-vendor reviewer is a review whatever it quotes; a machine
  # sentinel is a refusal whatever else it carries; so is a not-yet-reviewed placeholder;
  # refusal PROSE is a refusal unless the reviewer's own machine-emitted review marker is
  # in the same body.
  #
  # AND "EVERY ARTIFACT" INCLUDES THE ONES THAT CANNOT BE EVIDENCE. The submitted-state
  # filter below used to run before this, so a refusal published as a review object in any
  # other state — `PENDING`, `DISMISSED`, a casing variant — was dropped before it was ever
  # weighed. A state that cannot CLEAR is not a state that cannot REFUSE.
  verdict=""
  if [ -n "$trailer_armed" ] && verdict_trailer "$TMPD/strict"; then verdict=yes; fi
  refusal=""; kind_of_refusal=""
  if [ -z "$verdict" ]; then
    if [ -n "$(hits "$REFUSALS_SENTINEL" "$TMPD/stripped")" ]; then
      refusal=yes; kind_of_refusal=declined
    elif [ -n "$(hits "$NOT_YET" "$TMPD/stripped")" ]; then
      refusal=yes; kind_of_refusal=unfinished
    elif [ -n "$(hits "$REFUSALS" "$TMPD/stripped")" ] \
      && [ -z "$(hits "$REVIEW_SENTINEL" "$TMPD/strict")" ]; then
      refusal=yes; kind_of_refusal=declined
      [ -n "$(hits "$SKIP_NOTICE" "$TMPD/stripped")" ] && kind_of_refusal=skipped
    fi
  fi
  fatal_grep
  if [ -n "$refusal" ]; then
    # Does this refusal concern THE HEAD BEING CLEARED? Body text, deliberately, and only
    # in the CLOSING direction: a false positive here costs a human a glance at a PR that
    # was in fact reviewed, never a merge. It reads the wider (stripped) rendering for the
    # same reason. Nothing clears on this answer — it is consulted below only to stop a
    # CONTENTLESS review object from outranking a refusal published at the same commit.
    refusal_concerns_head "$TMPD/stripped" && refusal_at_head=yes
    # A SKIP NOTICE ONLY ANSWERS 8 WHERE IT IS THE WHOLE STORY. Any other refusal on the
    # PR means somebody DID ask and the reviewer answered — a rate limit is the ordinary
    # answer to the very request exit 8 asks for — so it demotes the PR back to exit 1,
    # whatever order the host streamed the two artifacts in.
    if [ "$kind_of_refusal" = skipped ]; then
      [ -n "$skip_from" ] || { skip_from="$login"; cp "$TMPD/stripped" "$TMPD/skip"; }
    else
      other_refusal=yes
    fi
    [ -n "$refusal_body" ] || { refusal_body="$TMPD/refusal"; refusal_from="$login"
                                refusal_kind="$kind_of_refusal"
                                cp "$TMPD/stripped" "$TMPD/refusal"; }
    # IS THIS ONE TERMINAL? (table 2d — exit 5 rather than exit 1.) Recorded SEPARATELY
    # from the first refusal above and NOT first-wins, because the two answers rank
    # differently: the first refusal is whichever the host streamed first, while "the
    # account is empty" is true of the PR however many placeholders precede it. So any
    # terminal artifact promotes the answer, and its own body is the one quoted.
    #
    # A PUBLISHED REOPEN TIME VETOES IT. The reviewer saying when it comes back is the
    # reviewer saying a human is not needed, and it outranks its own sales copy — which is
    # what stops "upgrade your plan" inside a 40-minute rate-limit notice from spending a
    # human. Read off the same stripped body as everything else here.
    if [ -z "$terminal_from" ] && [ "$kind_of_refusal" != unfinished ] \
       && [ -n "$(hits "$REFUSALS_TERMINAL" "$TMPD/stripped")" ] \
       && [ -z "$(reopen_line "$TMPD/stripped")" ]; then
      terminal_from="$login"; terminal_body="$TMPD/terminal"
      cp "$TMPD/stripped" "$TMPD/terminal"
    fi
    fatal_grep
    continue
  fi

  # TEST 1b — is this comment the reviewer's RECEIPT FOR A COMMAND rather than a review?
  # An acknowledgement names the head it was invoked at and says nothing about whether a
  # review followed, so it is dropped here: it reaches neither the evidence tests below
  # nor the refusal tiers above, and clears nothing at any head (table 3b).
  if [ "$kind" != "review" ] && [ -n "$(hits "$INVOCATION_ACK" "$TMPD/stripped")" ]; then
    [ -n "$ack_from" ] || ack_from="$login"
    # An ack made AT this head is the record that the exit-8 ask has already been made,
    # and it is what bounds that ask to once per head (see the exit-8 block). Two ways to
    # be at the head, because the real acknowledgement carries no SHA to name: the body
    # names it, or the comment was posted after the head commit's own date.
    { names_head "$TMPD/strict" || posted_at_head "$created"; } && ack_at_head=yes
    [ -n "$(hits "$INCREMENTAL_NOTE" "$TMPD/stripped")" ] && incremental_from="$login"
    fatal_grep
    continue
  fi
  fatal_grep

  # A review object is evidence only in one of the API's three SUBMITTED states, compared
  # against its own spellings. Anything else — PENDING, DISMISSED, a casing variant, a
  # state this script has never heard of — is not a submitted review, so it reaches TEST 1
  # above (a refusal is a refusal in any state) and stops here, before the evidence tests.
  if [ "$kind" = "review" ]; then
    case " $SUBMITTED_STATES " in *" $state "*) ;; *) continue ;; esac
  fi

  # TEST 2 — is this a review OF THIS COMMIT? The three routes of the header. Evidence and
  # pin travel together in each of them, and in A and B neither half is prose; route C's
  # pin is the one place a body-mentioned SHA still decides anything (see its note below).
  # Each records what it found and READS ON; the ranking is applied once, after the loop.
  #
  #   B. the validated trailer, pinned by its own head_sha field
  #   A. a submitted review object, pinned by the API's commit_id
  #   C. the vendor's machine-emitted review marker, pinned by the head named in the
  #      strict rendering of the body
  if [ -n "$verdict" ]; then
    [ -n "$cleared_msg" ] || cleared_msg="ok: a validated okf-verdict trailer from $login ($kind) names head $head_sha on PR $pr"
    continue
  fi
  if [ "$kind" = "review" ]; then
    if [ -n "$commit" ] && [ "$commit" = "$head_sha" ]; then
      # A REVIEW OBJECT AT THE HEAD WITH NOTHING IN IT IS NOT AUTOMATICALLY A REVIEW, and
      # this is what moving the pin to `commit_id` gave away: an empty body cannot name a
      # head, so the old body-SHA pin refused one as a side effect of being wrong. Once
      # `state` + `commit_id` became the pin, an empty-bodied COMMENTED object at the head
      # cleared OVER the reviewer's own verbatim rate-limit refusal at that same head.
      #
      # `COMMENTED` is not a claim. The host mints one for any inline comment and any thread
      # reply — twelve empty-bodied ones sit in this repository's own corpus, NINE at their
      # PR's final head — so for that state the claim, if there is one, is in the body.
      # `APPROVED` and `CHANGES_REQUESTED` ARE claims whatever the body says: the state IS
      # the verdict. Neither kind may outrank a refusal published at this same head, so a
      # contentless one is HELD and decided after every artifact has been read rather than
      # exiting here — and the refusal has to NAME this head to win rather than merely
      # exist, so a PR refused once can still recover.
      #
      # CONTENT IS MEASURED ON THE STRICT RENDERING, so a body that is nothing but a code
      # block — or nothing but an unbalanced fence — counts as contentless, which is the
      # safe direction. What counts as content is `renders_content` above.
      if renders_content "$TMPD/strict"; then
        [ -n "$cleared_msg" ] || cleared_msg="ok: a submitted review ($state) from $login was made at head $head_sha on PR $pr"
        continue
      fi
      if [ "$state" = "COMMENTED" ]; then
        [ -n "$empty_from" ] || { empty_from="$login"; empty_state="$state"; }
        continue
      fi
      [ -n "$held_from" ] || { held_from="$login"; held_state="$state"; }
      continue
    fi
    # A review object that is not at this head is stale in the API's own terms — no text
    # is consulted, and no body-mentioned SHA can rescue it.
    [ -n "$stale_from" ] || { stale_from="$login ($kind, $state)"
                              stale_at="${commit:-an unrecorded commit}"; }
    continue
  fi
  if [ -n "$(hits "$REVIEW_SENTINEL" "$TMPD/strict")" ]; then
    fatal_grep
    # ROUTE C IS THE FALLBACK CHANNEL, NOT A SECOND OPINION. Where this account has a
    # review object on the PR at all, the structured channel is live for it and decides:
    # `user.login` is the reviewer and `commit_id` is the head, neither of them prose.
    # The comment this would otherwise read is a SINGLE comment the vendor EDITS in place
    # across rounds, so it names the current head whatever it last reviewed — on #227 it
    # named 711c755c while the only review object sat at 6d954b42, and that cleared.
    #
    # THE COST, stated rather than hidden: a genuinely clean re-review at the new head
    # leaves no review object of its own (see the KB finding on that), so where an OLDER
    # object exists it now lands on exit 4 instead of clearing. That is a human glance.
    if has_review_object "$login"; then
      [ -n "$marker_outranked" ] || marker_outranked="$login"
      continue
    fi
    if names_head "$TMPD/strict"; then
      [ -n "$cleared_msg" ] || cleared_msg="ok: $login's own review marker in a comment names head $head_sha on PR $pr"
      continue
    fi
    [ -n "$stale_from" ] || { stale_from="$login ($kind)"; stale_at="no commit it names"; }
    continue
  fi
  fatal_grep
  [ -n "$unproven_from" ] || unproven_from="$login ($kind)"
done < "$TMPD/index"

# --- SCHEMA.md clause 9: no reviewer-authored thread is still unresolved ------
#
# Runs ONLY on the clearing path (see the decision block below) — a PR with no review to
# begin with is refused for that, and reporting an open thread on top of it would bury the
# answer the caller needs. So clause 9 is the LAST question asked, never the first.
#
# WHOSE THREADS COUNT. A thread whose FIRST comment was written by a known reviewer — a
# login in REVIEWERS, or the one named with `--reviewer` — and never by the PR's own
# author (SCHEMA clause 8: an author is not its own reviewer, and a thread it opened on
# its own PR is a note to itself). The identity test is the SAME THREE-STEP NARROWING the
# classifier loop uses, through the same `norm` — so a `[bot]` suffix or a casing
# difference cannot smuggle a thread past it, and there is no second answer here to "whose
# opinion counts".
#
# TABS AND NEWLINES CANNOT BREAK THE TSV, which matters because a thread body is arbitrary
# user text: jq's `@tsv` escapes tab, newline, carriage return and backslash itself, so
# every record below is exactly one line of exactly five fields.
#
# WHY GRAPHQL. `isResolved` exists nowhere in the REST API — not on a review, not on a
# review comment, not on the PR. This is the one fact here that has no structured REST
# source, and reading it is the whole point of the clause: "resolved" is exactly the state
# a human sets and a body of prose cannot claim.
#
# IT FAILS CLOSED, IN BOTH ITS FAILURE DIRECTIONS, and they are different:
#   * the query cannot be run or cannot be parsed  -> exit 2, unknown state, never
#     clearance. `gh pr view` and `gh api` have already succeeded by the time this runs, so
#     a GraphQL failure here is an anomaly and not a machine without network.
#   * MORE THAN ONE PAGE of threads and none of the first 100 is open -> also exit 2, and
#     this one is the subtle half. "No unresolved thread in the threads I could see" is not
#     "no unresolved thread", and a 101-thread PR is exactly the large PR where an
#     unanswered finding is most likely. An open thread found on page 1 still refuses at 6:
#     that answer does not depend on the pages nobody read.
clause9_threads=""      # one `path\tline\tlogin\turl\tfirst-line` record per open thread
clause9_state=""        # ok | unreadable | truncated

check_clause9() {
  local q json total open_n p_ l_ who url_ first_
  q='query($owner:String!,$name:String!,$number:Int!){
       repository(owner:$owner,name:$name){
         pullRequest(number:$number){
           reviewThreads(first:100){
             pageInfo{ hasNextPage }
             nodes{
               isResolved
               path
               line
               comments(first:1){ nodes{ author{login} url body } }
             }
           }
         }
       }
     }'
  json="$(gh api graphql -F owner="${nwo%%/*}" -F name="${nwo##*/}" \
            -F number="$pr_number" -f query="$q" 2>/dev/null)" || {
    clause9_state="unreadable"; return; }

  # EVERY COLUMN IS ALWAYS EMITTED, and `line` is why this is spelled out. A file-level
  # thread has `line: null`, and `(.line // empty)` emits NO ELEMENT for it — so `@tsv`
  # yields four fields instead of five and every field after it shifts one left. The login
  # column then holds a URL, the reviewer test rejects it, and the thread is silently
  # DROPPED: a file-level finding would clear the gate. Measured on the first run of
  # tests/review-clearance-gates.test.sh's clause-9 section. `// "-"` keeps the column, and a
  # null `author` (a deleted account) is likewise `""` rather than absent.
  clause9_threads="$(printf '%s' "$json" | jq -r '
      .data.repository.pullRequest.reviewThreads.nodes[]?
      | select(.isResolved == false)
      | [ (.path // "(file-level)"),
          ((.line // "-") | tostring),
          (.comments.nodes[0].author.login // ""),
          (.comments.nodes[0].url // ""),
          ((.comments.nodes[0].body // "") | split("\n") | map(select(length>0))[0] // "")
        ] | @tsv' 2>/dev/null)" || { clause9_state="unreadable"; return; }

  total="$(printf '%s' "$json" | jq -r '
      .data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage' 2>/dev/null)" || total=""
  case "$total" in true|false) ;; *) clause9_state="unreadable"; return ;; esac

  # WHOSE THREAD IT IS, DECIDED BY THE SAME THREE NARROWING STEPS THE CLASSIFIER LOOP USES
  # — `--for-check` owners, else `--reviewer`, else the REVIEWERS table — and then clause 8
  # on top. Copied in shape, not in authority: the tables and `norm` are the same objects,
  # so there is no second answer to "whose opinion counts" for this file to drift from.
  # A thread from an account in none of them is a teammate's, and a teammate's open thread
  # is not the independent gate.
  open_n=""
  while IFS="$(printf '\t')" read -r p_ l_ who url_ first_; do
    [ -n "$who" ] || continue
    if [ -n "$check_owners" ]; then
      match_patterns "$who" "$check_owners" || continue
    elif [ -n "$want_reviewer" ]; then
      [ "$(norm "$who")" = "$(norm "$want_reviewer")" ] || continue
    else
      match_reviewer "$who" || continue
    fi
    [ "$(norm "$who")" = "$(norm "$pr_author")" ] && continue
    open_n="${open_n}${p_}	${l_:--}	${who}	${url_}	${first_}
"
  done <<EOF
$clause9_threads
EOF
  clause9_threads="$open_n"

  if [ -n "$clause9_threads" ]; then clause9_state="ok"
  elif [ "$total" = "true" ]; then clause9_state="truncated"
  else clause9_state="ok"; fi
}

# `refuse_clause9` is called only where a clearance was otherwise about to be printed.
refuse_clause9() { # <the clearance message that is being withheld>
  if [ "$clause9_state" = "unreadable" ]; then
    echo "error: PR $pr has a review at head $head_sha, but its review THREADS could not be" >&2
    echo "       read, so $AB_SCHEMA clause 9 (no reviewer-authored thread still unresolved)" >&2
    echo "       cannot be applied. A clause that cannot be applied is not a clause that" >&2
    echo "       passes. Refusing (fail closed)." >&2
    exit 2
  fi
  if [ "$clause9_state" = "truncated" ]; then
    echo "error: PR $pr carries more review threads than one page, and none of the first" >&2
    echo "       100 is unresolved. That is not the same answer as 'none is unresolved'," >&2
    echo "       so clause 9 is UNKNOWN here rather than satisfied. Refusing (fail closed)." >&2
    exit 2
  fi
  echo "refuse: PR $pr WAS reviewed at head $head_sha (${1#ok: }) — but $AB_SCHEMA clause 9" >&2
  echo "        refuses it: the reviewer's own thread(s) below are still unresolved, so a" >&2
  echo "        finding it raised has not been answered. DO NOT REQUEST ANOTHER REVIEW;" >&2
  echo "        you already have one. Answer or fix each thread, resolve it, and push." >&2
  # UNTRUSTED TEXT, exactly as the refusal quotes above are: a thread body is written by
  # whoever can comment on the PR. Control characters are stripped before this reaches a
  # terminal so a body cannot repaint the screen or hide the lines under it, and the
  # opening line is cut to 120 characters so one thread cannot push the others off-screen.
  printf '%s' "$clause9_threads" | while IFS="$(printf '\t')" read -r p_ l_ who url_ first_; do
    [ -n "$p_" ] || continue
    printf '          | %s:%s  (%s)  %s\n' "$p_" "$l_" "$who" "$url_"
    printf '          |   %s\n' "$(printf '%s' "$first_" | tr -d '\000-\010\013-\037' | cut -c1-120)"
  done >&2
  exit 6
}

# --- the decision, taken once, over everything every artifact said ------------
#
# NOTHING ABOVE CLEARED ANYTHING, and this block is why. Ranking inside the loop ranked by
# whatever the host streamed first, so "a refusal is weighed before a clearance" held only
# for the shapes read last. Here every artifact has been read before anything is decided.
#
# WHAT OUTRANKS WHAT, AND THE ONE PLACE A REFUSAL LOSES — stated plainly, because the
# recurring defect on this file has been a claim the code did not keep:
#
#   * A refusal concerning THIS head beats a CONTENTLESS review object at this head. An
#     empty `COMMENTED` is not a claim at all; an empty `APPROVED`/`CHANGES_REQUESTED` is
#     one, but not one that outranks the reviewer saying it did not look.
#   * A refusal concerning ANOTHER commit loses to everything: a PR skipped once has to be
#     able to recover. A refusal naming NO commit is not that case — see
#     `refusal_concerns_head`.
#   * A refusal concerning this head LOSES to a review artifact that carries evidence at
#     this head (routes A with content, B, C). THIS IS THE RESIDUAL, and it is deliberate:
#     the reviewer routinely posts a rate-limit notice and then reviews the same commit,
#     and telling that from "posted a chat reply with words in it" needs the reviewer's
#     PROSE — the primitive this file exists to stop using.
#     The cost is stated rather than hidden: a contentful artifact from the reviewer at the
#     head beats its own refusal at that head, and the operator is told so on stderr.
if [ -z "$refusal_at_head" ] || [ -n "$cleared_msg" ]; then
  if [ -n "$cleared_msg" ]; then
    # CLAUSE 9 IS SETTLED BEFORE THE NOTE BELOW, not after. The note says "…so this
    # cleared"; printing it and then refusing at 6 tells the operator two opposite things
    # one line apart, and the second one is the answer.
    check_clause9
    [ -z "$clause9_threads" ] && [ "$clause9_state" = "ok" ] || refuse_clause9 "$cleared_msg"
    [ -n "$refusal_at_head" ] && {
      echo "note: $refusal_from also refused this head on PR $pr; a review artifact carrying" >&2
      echo "      evidence at the same commit outranks it, so this cleared. Look if unsure." >&2
    }
    printf '%s\n' "$cleared_msg"
    mint_receipt
    exit 0
  fi
  if [ -n "$held_from" ]; then
    check_clause9
    [ -z "$clause9_threads" ] && [ "$clause9_state" = "ok" ] || \
      refuse_clause9 "a submitted review ($held_state) from $held_from"
    echo "ok: a submitted review ($held_state) from $held_from was made at head $head_sha on PR $pr"
    mint_receipt
    exit 0
  fi
fi

# --- nothing cleared: say precisely which shape this PR is -------------------
#
# The quoted lines are UNTRUSTED TEXT from a PR comment (see the header). They are stripped
# of control characters before they reach a terminal, so a body cannot repaint the
# operator's screen or hide the rest of this message behind an escape sequence.
#
# WHAT WAS EXCLUDED IS SAID OUT LOUD, FIRST. Both of these are artifacts an operator can
# see in the browser, and a refusal that does not mention them reads as "the script did not
# look". Printed on every non-clearing path below, before the answer itself.
if [ "$self_reviews" -gt 0 ]; then
  echo "note: $self_reviews review object(s) on PR $pr are authored by $pr_author, the PR's OWN" >&2
  echo "      author, $self_at_head of them at this head. An author is never its" >&2
  echo "      own independent reviewer ($AB_SCHEMA, clause 8), so they are REFUSED as" >&2
  echo "      evidence whatever their state, not merely uncounted." >&2
fi
if [ -n "$marker_outranked" ]; then
  echo "note: $marker_outranked's review marker in a comment names this head, and did NOT" >&2
  echo "      clear: that account has review object(s) on this PR, so the structured" >&2
  echo "      channel decides and the comment is not consulted." >&2
fi

# WHICH COMMAND CAN STILL PRODUCE A REVIEW AT THIS HEAD. Printed on the exit-4 paths, where
# the answer is "ask again" and the obvious ask is the one that cannot work: the reviewer's
# own reply says it does not re-review commits it has already reviewed, so `@coderabbitai
# review` returns another acknowledgement. Two rounds of the 09-14 tick went that way.
incremental_note() {
  [ -n "$incremental_from" ] || return 0
  echo "        $incremental_from's own reply says it is an INCREMENTAL review system and does" >&2
  echo "        not re-review already reviewed commits — so \`@coderabbitai review\` will" >&2
  echo "        acknowledge and stop. Ask for \`@coderabbitai full review\` to get a review" >&2
  echo "        at this head." >&2
}

# THE TERMINAL REFUSAL IS REPORTED FIRST AND SEPARATELY, because it is the one refusal that
# is not about this pull request. Waiting cannot fix it and no other PR will fare better,
# so the message says so out loud rather than leaving a reader to infer it from a quote.
if [ -n "$terminal_from" ]; then
  echo "refuse: $terminal_from CANNOT review PR $pr until a HUMAN acts — this refusal is" >&2
  echo "        TERMINAL, not a rate limit: it names the account's own state, publishes no" >&2
  echo "        reopen time, and reads the same on every other PR. It said:" >&2
  refusal_hits "$terminal_body" | tr -d '\000-\010\013-\037' \
                                | sed -e 's/^[[:space:]]*\(>[[:space:]]*\)*//' \
                                      -e 's/^[*#[:space:]]*//' -e 's/[*[:space:]]*$//' \
                                      -e 's/^/          | /' >&2
  echo "        WAITING WILL NOT CLEAR THIS. Fix the reviewer (credits, billing, the token" >&2
  echo "        or the app installation), or decide once — not per PR — to spend the" >&2
  echo "        fallback reviewer instead. Either way it is a decision, and it is not this" >&2
  echo "        script's and not the caller's." >&2
  exit 5
fi

# NOBODY EVER ASKED. Reported before the transient refusal below and separately from it,
# because the remedy inverts: exit 1 is answered by waiting and this one never reopens on
# its own. An ack at this head means the ask has already been made, which is a wait after
# all — so it goes back to exit 1 and the PR is asked once per head, not once per tick.
if [ -n "$skip_from" ] && [ -z "$other_refusal" ]; then
  refusal_hits "$TMPD/skip" | tr -d '\000-\010\013-\037' \
                            | sed -e 's/^[[:space:]]*\(>[[:space:]]*\)*//' \
                                  -e 's/^[*#[:space:]]*//' -e 's/[*[:space:]]*$//' \
                                  -e 's/^/          | /' > "$TMPD/skip-quote"
  if [ -n "$ack_at_head" ]; then
    echo "refuse: $skip_from skipped PR $pr, and $ack_from has ALREADY been asked for a review" >&2
    echo "        at head $head_sha — its acknowledgement was posted here. Wait for" >&2
    echo "        that review; do not ask again at this head. It said:" >&2
    cat "$TMPD/skip-quote" >&2
    incremental_note
    exit 1
  fi
  echo "refuse: $skip_from SKIPPED PR $pr — reviews are not automatic on this repository, so" >&2
  echo "        NOBODY HAS ASKED for one at head $head_sha and nothing will ever ask. This" >&2
  echo "        does NOT reopen by itself, which is the whole difference from exit 1. It said:" >&2
  cat "$TMPD/skip-quote" >&2
  echo "        Request one review, at THIS head, by commenting \`@coderabbitai review\` on" >&2
  echo "        the PR. A request costs no review round. Where several PRs answer 8 and the" >&2
  echo "        quota is one review per window, spend it on the PR whose criteria table" >&2
  echo "        carries no \`✗\` — only that one can become merge-eligible." >&2
  incremental_note
  exit 8
fi

if [ -n "$refusal_body" ]; then
  if [ "$refusal_kind" = "unfinished" ]; then
    echo "refuse: $refusal_from has NOT FINISHED reviewing PR $pr — a placeholder is not a" >&2
    echo "        review, however green its status check is. It said:" >&2
  else
    echo "refuse: $refusal_from DECLINED to review PR $pr — this is not clearance, however" >&2
    echo "        green its status check is. It said:" >&2
  fi
  refusal_hits "$refusal_body" | tr -d '\000-\010\013-\037' \
                               | sed -e 's/^[[:space:]]*\(>[[:space:]]*\)*//' \
                                     -e 's/^[*#[:space:]]*//' -e 's/[*[:space:]]*$//' \
                                     -e 's/^/          | /' >&2
  when="$(reopen_line "$refusal_body" | tr -d '\000-\010\013-\037')"
  if [ -n "$when" ]; then
    echo "        Reopens: $when" >&2
  else
    echo "        No reopen time published — re-request a review once the quota resets." >&2
  fi
  echo "        A skipped PR is NOT re-reviewed automatically: nothing re-runs until a" >&2
  echo "        new commit lands or someone asks for a first review." >&2
  # Say so when a contentless review object sat at this same head, or the operator reads
  # "nobody reviewed it" while looking at a review object in the browser.
  contentless="${held_from:-$empty_from}"; contentless_state="${held_state:-$empty_state}"
  [ -n "$contentless" ] && {
    echo "        (A $contentless_state review object from $contentless sits at this same head" >&2
    echo "        with an EMPTY body. An empty review object does not outrank a refusal" >&2
    echo "        published at that commit — see the note at TEST 2.)" >&2
  }
  exit 1
fi

# A review object at the head that says nothing. Its own shape rather than "no evidence",
# because the operator can see it in the browser and needs to be told why it did not count.
if [ -n "$empty_from" ]; then
  echo "refuse: the review object on PR $pr from $empty_from is at head $head_sha but its" >&2
  echo "        body is EMPTY, and an empty $empty_state review is not a claim that anybody" >&2
  echo "        read anything: the host mints one for any inline comment or thread reply, so" >&2
  echo "        the claim, where there is one, is the body. Ask for a review at this head," >&2
  echo "        or look." >&2
  incremental_note
  exit 4
fi

if [ -n "$stale_from" ]; then
  echo "refuse: the review on PR $pr is from $stale_from and was made at $stale_at," >&2
  echo "        not at head $head_sha. A verdict for a commit that is no longer the head" >&2
  echo "        is stale. This is the ORDINARY outcome where the reviewer does not" >&2
  echo "        re-review on every push (CodeRabbit's \`auto_incremental_review: false\`):" >&2
  echo "        the review is real and it is not of this commit. Ask for a review at this" >&2
  echo "        head, or look." >&2
  incremental_note
  exit 4
fi

# The reviewer answered a command and nothing else. Its own shape, because the operator is
# looking at "✅ Action performed / Review finished" in the browser and has every reason to
# read it as a review having happened.
if [ -n "$ack_from" ]; then
  echo "refuse: the only artifact on PR $pr from $ack_from is its AUTO-GENERATED REPLY to a" >&2
  echo "        review command — \"Action performed / Review finished\" — which it posts" >&2
  echo "        whether or not a review follows, and which names the head it was invoked" >&2
  echo "        at. A receipt for a command is not a review. Ask at this head, or look." >&2
  incremental_note
  exit 4
fi

# An artifact from the reviewer that evidences no completed review. Its own shape, not
# folded into "no reviewer signal": something IS there, and saying "nothing on this PR"
# about a comment the operator can see in the browser gets this script disbelieved rather
# than the PR looked at. The placeholder the reviewer posts before it reads anything is
# the common case, and it used to clear.
if [ -n "$unproven_from" ]; then
  echo "refuse: the only artifact on PR $pr is from $unproven_from and carries no evidence" >&2
  echo "        that a review was COMPLETED — it is not a submitted review object at this" >&2
  echo "        head, it carries no verdict trailer, and it carries none of the reviewer's" >&2
  echo "        own review markers. A reviewer posting on a PR is not a reviewer having" >&2
  echo "        read it (the 'currently processing' placeholder is on nearly every PR)." >&2
  echo "        Ask for a review at this head, or look." >&2
  incremental_note
  exit 4
fi

echo "no-review: nothing on PR $pr from a known reviewer${want_reviewer:+ ($want_reviewer)}${for_check:+ (owner of '$for_check')}." >&2
echo "        $n artifact(s) on the PR, $considered from a reviewer. An absent review is" >&2
echo "        NOT a pass — surface the PR for a human, or dispatch the fallback reviewer." >&2
[ -n "$want_reviewer" ] || echo "        Pass --reviewer <login> if this repo uses a reviewer with no table row." >&2
exit 3

# --- completeness sentinel — THIS MUST REMAIN THE LAST LINE OF THIS FILE ------
# `--self-test` asserts that the last line of this file is exactly the line below, which
# is the only cheap thing a file can say about itself that a TRUNCATED copy cannot. The
# self-test block sits hundreds of lines above, so "it runs" was true of copies missing
# every table under it; 112 truncation points passed it and 109 then cleared an unreviewed
# PR. Do not add anything after it, and do not restate it anywhere else in the file.
#EOF: review-clearance.sh is complete to here
