#!/usr/bin/env bash
#
# KEPT (v2 audit, 2026-08): GitHub-native auto-merge is the first-party equivalent,
# but a private repo on the free plan answers 403 from both the branch-protection
# and rulesets APIs, so the native path cannot be exercised there at all. This is a
# documented workaround, not architecture — delete it the day every target repo can
# enforce protection.
#
# required-checks.sh — resolve the REQUIRED-check set for a pull request and verify
# every member is green. This is precondition 1 of the delegated merge gate
# (`AUTONOMY.md` → "Merge under `yolo`"); nothing else in the bundle may merge a PR
# without it exiting 0.
#
#   Usage: required-checks.sh <pr> [--repo <owner>/<name>] [--head <sha>]
#
# Exit codes — 0 is the ONLY clearance; every other code is a refusal:
#
#   0  a non-empty required set resolved, every member passed, an independent review
#      artifact clears the current head, AND the PR body carries the shape
#      `CONVENTIONS.md` requires
#   1  a required check is not green — failing, pending, or never reported; no review
#      cleared this head (see below); or the PR body is missing its TL;DR line or its
#      acceptance-criteria table
#   2  usage error, or the environment can't answer (no `gh` or `jq` — the siblings
#      need both — an unreadable PR, `review-clearance.sh` or `pr-body-clearance.sh`
#      missing/unrunnable, an unreadable reviewer state, or an unreadable PR body)
#   3  no required set could be resolved — the merge authority is NOT exercisable
#      here (this is the signal AUTONOMY.md's preflight surfaces to the human)
#   4  this PR edits the declared list itself — changing the gate is a human call
#
# TWO SOURCES, IN ORDER
#
#   1. PLATFORM — branch protection / rulesets, read via `gh pr checks --required`.
#      Authoritative wherever it exists, because the host enforces it for humans and
#      for the loop alike; the loop is then a second lock, not the only one.
#   2. DECLARED — `.github/required-checks.txt` on the PR's BASE branch, one check
#      name per line. Used ONLY when the platform reports no required set at all.
#      It exists for hosts where protection is unavailable — notably private repos on
#      a free plan, where the branch-protection AND rulesets APIs both answer 403.
#
#      PLATFORM-ENFORCED IS STRICTLY BETTER. Upgrading the plan and configuring
#      protection needs no change here: source 1 starts resolving and automatically
#      wins, the declared file becomes dead weight, and the gate also starts applying
#      to human merges and to anything else pushing at the branch.
#
# GENERIC PLUGIN FILE — ships inside the `loopd` plugin; nothing to edit per
# instance. It takes no org, repo, or check names: those live in the target repo.
#
# A REVIEWER'S CHECK IS NOT A REVIEW, AND A CHECK'S NAME NEVER SETTLES THAT. `pass`
# settles a CI job, because a CI job that ran and succeeded is the whole of what it
# claims. It does not settle a hosted REVIEWER's check: a reviewer that declines to review
# (rate-limited, out of quota) exits successfully and publishes exactly the same green.
#
# THIS USED TO BE DECIDED BY THE CHECK'S NAME, and that was the original incident with a
# newer vendor's name on it. `review-clearance.sh` carried a table of vendor names and
# review phrasings; a required check called `Codex Review`, or bare `Cursor`, `Copilot`,
# `Devin` or `PR Agent`, matched no row, was read as plain CI and settled on its green
# bucket with zero artifacts read. A name table has to enumerate every vendor and every
# phrasing that will ever exist, so it is never finished.
#
# SO THE NAME IS NO LONGER ASKED. This script requires a review artifact on EVERY pull
# request it is about to clear, whatever its checks are called: `review-clearance.sh`
# reads the reviewer's artifacts from the API and only a clean answer there clears. The
# check-name table survives for one narrower job — resolving WHICH vendor owns a required
# check, so that vendor's own artifacts (and not another's) answer for it. A vendor the
# table does not know now costs nothing, because the unscoped call still has to clear.
#
# FAILS CLOSED. An empty set, an unparseable answer, a declared name that no check
# reports (a rename), a skipped check, a pending check, an absent review, a reviewer state
# that cannot be read — all refuse. A required check the loop cannot see green is a
# required check that did not pass, and a review the loop cannot see is a review that did
# not happen.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

DECLARED_PATH=".github/required-checks.txt"

usage() {
  echo "Usage: $(basename "$0") <pr> [--repo <owner>/<name>] [--head <sha>]" >&2
  exit 2
}

pr=""; repo=""; want_head=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:-}"; [ -n "$repo" ] || usage; shift 2 ;;
    --head) want_head="${2:-}"; [ -n "$want_head" ] || usage; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) [ -z "$pr" ] || { echo "error: unexpected argument '$1'" >&2; usage; }
       pr="$1"; shift ;;
  esac
done
[ -n "$pr" ] || usage

command -v gh >/dev/null 2>&1 || {
  echo "error: gh not found — cannot verify required checks" >&2
  exit 2
}

# bash 3.2 (the macOS default) errors on "${arr[@]}" when arr is empty under `set -u`,
# hence the ${arr[@]+...} guard at every expansion.
R=()
[ -n "$repo" ] && R=(--repo "$repo")

# --- PR facts ---------------------------------------------------------------
meta="$(gh pr view "$pr" ${R[@]+"${R[@]}"} \
        --json url,baseRefName,headRefOid \
        --jq '[.url, .baseRefName, .headRefOid] | @tsv' 2>/dev/null)" || {
  echo "error: could not read PR $pr${repo:+ in $repo}" >&2
  exit 2
}
url="$(printf '%s' "$meta" | cut -f1)"
base="$(printf '%s' "$meta" | cut -f2)"
head_sha="$(printf '%s' "$meta" | cut -f3)"
nwo="$(printf '%s' "$url" | sed -E 's#^https?://[^/]+/([^/]+/[^/]+)/pull/[0-9]+.*#\1#')"

[ -n "$base" ] && [ -n "$head_sha" ] && [ "$nwo" != "$url" ] || {
  echo "error: could not resolve base branch / head SHA / repo for PR $pr" >&2
  exit 2
}

# Pin to the SHA the reviewer actually cleared, when the caller knows it. Checks are
# reported against the head, so a moved head invalidates this whole answer.
if [ -n "$want_head" ] && [ "$want_head" != "$head_sha" ]; then
  echo "refuse: head moved — verified $want_head, PR is now at $head_sha" >&2
  exit 1
fi

# --- source 1: platform-required set ----------------------------------------
# Classify on the PAYLOAD, not the exit code: `gh pr checks --required` exits
# non-zero both when a required check FAILS and when no protection exists, and those
# two must never be confused. Three answers are recognised, and ONLY three:
#
#   JSON array         -> protection answered. An empty array means it requires
#                         nothing, which legitimately falls through to source 2.
#   the "no required
#   checks" message    -> no protection on this branch; source 2 may answer.
#   anything else      -> we do NOT know what the platform requires. Refuse (exit 2).
#
# That last arm is the point. A transient 5xx, an expired token or a rate limit all
# produce some other text, and silently reading them as "nothing is required" would
# hand the decision to a declared list that may be weaker than the protection we
# just failed to read — failing open at exactly the moment we are least informed.
#
# The message lands on STDERR, while the JSON lands on stdout — so both streams are
# captured, separately. Merging them would let a stray gh warning prefix the payload
# and turn a good JSON answer into an unrecognised one.
required=""
source="platform"
probe_err="$(mktemp)"
trap 'rm -f "$probe_err"' EXIT
platform_raw="$(gh pr checks "$pr" ${R[@]+"${R[@]}"} --required --json name,bucket 2>"$probe_err" || true)"
platform_msg="$(cat "$probe_err")"
case "$platform_raw$platform_msg" in
  '['*)
    # Enumerate separately so a failure here is also an error, not an empty set.
    if ! required="$(gh pr checks "$pr" ${R[@]+"${R[@]}"} --required --json name \
                     --jq '.[].name' 2>/dev/null)"; then
      echo "error: protection reported a required set but it could not be read —" >&2
      echo "       refusing rather than falling back to the declared list." >&2
      exit 2
    fi
    ;;
  *"no required checks"*) required="" ;;
  *)
    echo "error: unrecognised answer from 'gh pr checks --required' for PR $pr." >&2
    echo "       Cannot tell 'nothing is required' from 'the query failed', so the" >&2
    echo "       required set is unknown and this refuses (fail closed)." >&2
    echo "       Got: ${platform_raw:-}${platform_msg:+ }${platform_msg:-}" >&2
    [ -n "$platform_raw$platform_msg" ] || echo "       (no output on either stream)" >&2
    exit 2 ;;
esac

# --- source 2: declared list on the base branch ------------------------------
if [ -z "$required" ]; then
  source="declared"
  # `gh api` prints the error BODY to stdout on a 404, so take the output only on a
  # clean exit — otherwise `{"message":"Not Found"...}` becomes a "required check".
  if ! declared_raw="$(gh api -H "Accept: application/vnd.github.raw" \
                       "/repos/$nwo/contents/$DECLARED_PATH?ref=$base" 2>/dev/null)"; then
    declared_raw=""
  fi
  # Comments are whole-line only (`#` in column 1 after optional spaces) — a check
  # name may legitimately contain '#', so nothing is stripped mid-line.
  required="$(printf '%s\n' "$declared_raw" \
              | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
              | grep -v '^#' | grep -v '^$' || true)"

  if [ -n "$required" ]; then
    # A PR that rewrites the gate must not be cleared by the gate it rewrites. The
    # list is read from BASE, so an open PR cannot weaken its own merge — but merging
    # it would weaken every later one, and that is the human's decision to take.
    changed="$(gh pr diff "$pr" ${R[@]+"${R[@]}"} --name-only 2>/dev/null)" || {
      echo "error: could not list the files PR $pr changes — refusing (fail closed)" >&2
      exit 2
    }
    if printf '%s\n' "$changed" | grep -Fxq "$DECLARED_PATH"; then
      echo "refuse: PR $pr edits $DECLARED_PATH — a change to the merge gate itself is" >&2
      echo "        a human decision. Surface it; do not auto-merge." >&2
      exit 4
    fi
  fi
fi

if [ -z "$required" ]; then
  echo "not-exercisable: no required checks for $nwo ($base)." >&2
  echo "        No branch protection reports a required set, and $DECLARED_PATH is" >&2
  echo "        absent or empty on the base branch. Surface the PR for the human." >&2
  exit 3
fi

# --- verify every required name is green at the current head -----------------
checks="$(gh pr checks "$pr" ${R[@]+"${R[@]}"} --json name,bucket \
          --jq '.[] | "\(.bucket)\t\(.name)"' 2>/dev/null || true)"

problems=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  buckets="$(printf '%s\n' "$checks" | awk -F'\t' -v n="$name" '$2 == n { print $1 }')"
  if [ -z "$buckets" ]; then
    problems="${problems}  - ${name}: not reported on this PR (renamed, or never ran)
"
  elif printf '%s\n' "$buckets" | grep -qv '^pass$'; then
    problems="${problems}  - ${name}: $(printf '%s' "$buckets" | tr '\n' ',' | sed 's/,$//')
"
  fi
done <<EOF
$required
EOF

if [ -n "$problems" ]; then
  echo "refuse: required checks not green on PR $pr (source: $source, head $head_sha):" >&2
  printf '%s' "$problems" >&2
  echo "        Only 'pass' clears — pending, skipped and missing all count as not passed." >&2
  echo "        Pending: wait and ask again next tick. Failing or missing: surface the PR to" >&2
  echo "        the human with the list above. Do NOT merge around this gate." >&2
  exit 1
fi

# --- a green check is never a review -----------------------------------------
# The one green check that means nothing. A hosted reviewer that declines to review —
# rate-limited, out of quota — still exits successfully, so its status check reports
# success and lands in the loop above as `pass`. Three PRs in one tick proved it: all
# three green, one reviewed, two carrying "Review limit reached" and merged unlooked-at.
#
# So no bucket settles it, for any check. review-clearance.sh reads the reviewer's
# ARTIFACTS — review objects from the API, with their state and their commit_id — and
# anything but a clean answer is not-green. The reviewer facts live there, not here: one
# place per vendor, so changing reviewers is one file.
#
# MISSING SIBLING ⇒ EXIT 2, not a pass. Without it this script cannot tell a reviewer's
# check from a CI job, so it cannot know whether the set it just cleared contained one.
# That is an unknown reviewer state, and unknown fails closed. The two files ship
# together as one unit; a missing one is a broken install, and it should be loud.
#
# A PRESENT-BUT-BROKEN SIBLING IS THE WORSE CASE, and `[ -x ]` cannot see it: the
# executable bit says nothing about whether the file RUNS. A dead shebang, a syntax
# error, a zero-byte file or a copy truncated half-way through an install all pass
# `[ -x ]` and then fail every invocation below — at which point "not a reviewer's check"
# is the answer to every name, no clearance is ever consulted, and this script reports
# `ok: N required check(s) pass` on a completely unreviewed PR. The gate does not fail;
# it disappears. So the sibling is asked to PROVE it runs, and its two table-driven
# controls make that proof non-vacuous — see `--self-test` there. The expected string is
# spelled out here rather than sourced from the sibling, because sourcing the file is
# exactly what cannot be trusted when the file is the thing under suspicion.
CLEARANCE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)/review-clearance.sh"
# selftest_ok <script> <expected-line> — does <script> --self-test answer <expected-line>?
# THE SELF-TEST STILL DECIDES; it is only not re-run for bytes it has already passed. A
# self-test reads nothing but the script's own file (no network, no PR), so its answer is a
# property of those bytes. Measured 2026-10-05: pr-body-clearance.sh's takes 2-4 s, and it
# ran on EVERY call of this script — every gate evaluation in a tick, and 100 s of one
# harness. The key is the file's checksum and byte count, so a truncated, edited or swapped
# copy never inherits an earlier verdict. ONLY A PASS IS RECORDED: a failure is re-measured
# every time, and an unreadable, unwritable or mismatching record just means the self-test
# runs, exactly as it always did. Fail closed is unchanged — anything but the expected
# line is a refusal in the caller below.
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
  echo "       Without it, a reviewer's own status check cannot be told from a CI job," >&2
  echo "       so the reviewer state is unknown and this refuses (fail closed)." >&2
  exit 2
fi
if ! selftest_ok "$CLEARANCE" "$CLEARANCE_SELFTEST_OK"; then
  echo "error: review-clearance.sh is present but does not run ($CLEARANCE)." >&2
  echo "       Its --self-test did not answer '$CLEARANCE_SELFTEST_OK'. A reviewer's" >&2
  echo "       check cannot be told from a CI job by a script that cannot execute, and" >&2
  echo "       every invocation failing would look exactly like 'no reviewer is" >&2
  echo "       required' — so the reviewer state is unknown and this refuses." >&2
  exit 2
fi

# Which required names a reviewer in the sibling's table OWNS. `--match-check` answers in
# two codes and ONLY two; anything else is a sibling behaving unexpectedly, which is
# unknown state. This no longer decides WHETHER clearance is asked for — it is always
# asked for — only WHOSE artifacts answer for a given required check.
reviewer_checks=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  if "$CLEARANCE" --match-check "$name" >/dev/null 2>&1; then mrc=0; else mrc=$?; fi
  case "$mrc" in
    0) reviewer_checks="${reviewer_checks}${name}
" ;;
    1) : ;;  # no reviewer in the table owns this name
    *) echo "error: '$CLEARANCE --match-check $name' exited $mrc, which is not one of" >&2
       echo "       its two answers (0 a reviewer's, 1 not). Whose artifacts answer for" >&2
       echo "       this required check is unreadable — refusing." >&2
       exit 2 ;;
  esac
done <<EOF
$required
EOF

# CLEARED PER CHECK WHERE A VENDOR OWNS ONE, AND ALWAYS AT LEAST ONCE. Two reviewers on
# one repo, one of them rate-limited, and a single unscoped call lets the other one's
# review clear the refusing one's required check — the same "a green thing stood in for
# the reviewer" substitution one level up. `--for-check` resolves the name to the reviewer
# that owns it and considers only that account's artifacts. Where NO required check is a
# known vendor's — which is every repo whose reviewer the table has never heard of, and
# the whole of route 1 above — one unscoped call still has to clear, so a green check
# called anything at all can never be the last word.
clearance_err="$(mktemp)"
trap 'rm -f "$probe_err" "$clearance_err"' EXIT

clearance_for() { # [--for-check <name>] — 0, or the sibling's refusal code
  # `set -e` is on: capture the exit code through an `if`, never off a bare `$?`, or a
  # refusing sibling would kill this script before it could report why.
  if "$CLEARANCE" "$pr" ${R[@]+"${R[@]}"} --head "$head_sha" "$@" \
     >/dev/null 2>"$clearance_err"
  then return 0; else return $?; fi
}

refuse_clearance() { # <the whole first clause> <exit code of the sibling>
  echo "refuse: $1 (review-clearance.sh exit $2). A green check" >&2
  echo "        means the integration ran, never that a review happened:" >&2
  sed 's/^/        /' "$clearance_err" >&2
  [ -n "$reviewer_checks" ] && \
    printf '%s' "$reviewer_checks" | sed 's/^/          required, and reviewer-owned: /' >&2
  # THE SIBLING'S EXIT 5 REFUSES EXACTLY AS ITS EXIT 1 DOES, and is said out loud rather
  # than folded in silently. It is the one refusal that is not about this PR: the reviewer
  # says its ACCOUNT is empty, unpaid or unauthenticated, so waiting clears nothing and
  # every later PR gets the same answer. The merge gate is unmoved — 0 is still the only
  # clearance — but a human reading this needs to know they are looking at a broken
  # reviewer, not a busy one.
  if [ "$2" -eq 5 ]; then
    echo "        This refusal is TERMINAL: the reviewer needs fixing (credits, billing," >&2
    echo "        the token or the app installation). Re-running this will not change it." >&2
  fi
  # THE SIBLING'S EXIT 6 IS THE ONE REFUSAL THAT MEANS "STOP ASKING FOR A REVIEW", and it
  # is said out loud for the same reason exit 5 is: the merge gate is unmoved (0 is still
  # the only clearance) and the human's next move is the opposite of the usual one. 6 means
  # a review DID complete at this head and SCHEMA.md clause 9 refused it — a
  # reviewer-authored thread is still unresolved, and the sibling has already NAMED each
  # one in the block above. Requesting another review here spends a session to be told the
  # same thing. It stays folded into this function's exit 1 (a refusal is a refusal); only
  # the advice differs.
  if [ "$2" -eq 6 ]; then
    echo "        A review EXISTS at this head — do NOT request another one. The threads" >&2
    echo "        named above are unanswered: reply to or fix each, resolve it, and push." >&2
  fi
  # THE SIBLING'S EXIT 7 IS NOT ABOUT THE REVIEW AT ALL. The host says the PR cannot merge
  # — CONFLICTING / DIRTY — so no review, no check and no green run changes the answer.
  # This is the refusal that made three PRs read "merge, verified, CLEAN" on 2026-09-13.
  if [ "$2" -eq 7 ]; then
    echo "        This PR CONFLICTS with its base — no review changes that. Rebase it onto" >&2
    echo "        the default branch, push, and ask again; do NOT request a review." >&2
  fi
  # An unreadable reviewer state (exit 2) is a different refusal from a reviewer that
  # answered and declined — keep the caller's two codes distinguishable. Spelled as an
  # `if` rather than `[ … ] && exit 2`, whose fall-through under `set -e` is a subtlety
  # nobody should have to re-derive while reading a merge gate.
  if [ "$2" -eq 2 ]; then exit 2; fi
  exit 1
}

if [ -n "$reviewer_checks" ]; then
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if clearance_for --for-check "$name"; then crc=0; else crc=$?; fi
    [ "$crc" -eq 0 ] || refuse_clearance \
      "required check '$name' is a reviewer's own, and that reviewer did not clear PR $pr" "$crc"
  done <<EOF
$reviewer_checks
EOF
else
  if clearance_for; then crc=0; else crc=$?; fi
  [ "$crc" -eq 0 ] || refuse_clearance "no independent review clears PR $pr" "$crc"
fi

# --- and a body nobody can read is not a merge anybody can decide ------------
# THE THIRD PRECONDITION, AND IT IS HERE FOR THE SAME REASON THE SECOND ONE IS.
# `CONVENTIONS.md` requires a PR body of a specific shape — a TL;DR line and the task's
# acceptance criteria as a `✓`/`✗` table — and that table is not decoration: it is the
# artifact `SCHEMA.md` clause 7 and `AUTONOMY.md` precondition 3 read to decide whether
# every criterion was verified. Five hours after that rule merged, an agent that had it
# opened a 14,673-character description, because the rule's only reader was a test
# asserting THE RULE IS NAMED IN THE DOCUMENT. `pr-body-clearance.sh` is the reader for
# the thing the rule governs, and this is the gate that consults it — a predicate no gate
# calls would repeat the defect one level down.
#
# IT REFUSES ON MISSING STRUCTURE (1), ON AN UNBOUNDED CRITERIA ROW (3) AND, SINCE
# 2026-09-06, ON LENGTH (4) — 2,500 characters, 3 `## Notes` bullets. Any non-zero code
# is a refusal here, so the new one needed no wiring; see CONVENTIONS.md -> "Write less".
#
# SAME MISSING/BROKEN-SIBLING CONTRACT as review-clearance.sh above, for the same reason:
# `[ -x ]` cannot tell a working script from a truncated one, and a sibling that fails
# every invocation would be indistinguishable from a body that is fine. The expected
# self-test string is spelled out here rather than sourced, because sourcing the file is
# exactly what cannot be trusted when the file is the thing under suspicion.
BODYGATE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)/pr-body-clearance.sh"
BODYGATE_SELFTEST_OK="pr-body-clearance: self-test ok"
if [ ! -f "$BODYGATE" ]; then
  echo "error: pr-body-clearance.sh not found beside this script ($BODYGATE)." >&2
  echo "       Without it nothing reads the PR body, so whether the acceptance-criteria" >&2
  echo "       table the merge decision rests on is even present is unknown — and" >&2
  echo "       unknown is never clearance. Refusing (fail closed)." >&2
  exit 2
fi
if ! selftest_ok "$BODYGATE" "$BODYGATE_SELFTEST_OK"; then
  echo "error: pr-body-clearance.sh is present but does not run ($BODYGATE)." >&2
  echo "       Its --self-test did not answer '$BODYGATE_SELFTEST_OK'. A script that" >&2
  echo "       fails every invocation reads exactly like a gate doing its job, so the" >&2
  echo "       body shape is unknown state and this refuses." >&2
  exit 2
fi

body_err="$(mktemp)"
trap 'rm -f "$probe_err" "$clearance_err" "$body_err"' EXIT
if "$BODYGATE" "$pr" ${R[@]+"${R[@]}"} --head "$head_sha" >/dev/null 2>"$body_err"
then brc=0; else brc=$?; fi
if [ "$brc" -ne 0 ]; then
  echo "refuse: the body of PR $pr does not carry the shape $AB_CONVENTIONS requires" >&2
  echo "        (pr-body-clearance.sh exit $brc):" >&2
  sed 's/^/        /' "$body_err" >&2
  # Unreadable (exit 2) is a different answer from readable-and-malformed (exit 1) —
  # keep the sibling's two codes distinguishable, exactly as refuse_clearance does.
  if [ "$brc" -eq 2 ]; then exit 2; fi
  exit 1
fi
# The character count the sibling reports is INFORMATION, and information nobody sees is
# not information — so it is surfaced on the clearing path too, not only in a refusal.
sed 's/^/  /' "$body_err" >&2

count="$(printf '%s\n' "$required" | grep -c '^' || true)"
echo "ok: $count required check(s) pass, a review clears PR $pr, and its body carries the required shape (source: $source, head $head_sha)"

# The clearance record the PreToolUse hook reads offline (ai-bridge-v3/task-044). Written
# after the answer is decided, and silent on any failure: it cannot change that answer.
"$(dirname "${BASH_SOURCE[0]:-$0}")/clearance-receipt.sh" record required-checks.sh \
  --repo "$nwo" --pr "$(printf '%s' "$url" | sed -E 's#^https?://[^/]+/[^/]+/[^/]+/pull/([0-9]+).*#\1#')" --head "$head_sha" >/dev/null 2>&1 || true
