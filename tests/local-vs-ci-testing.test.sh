#!/usr/bin/env bash
#
# local-vs-ci-testing.test.sh — the rule "the full suite belongs to CI; locally run the
# tests your change touches" keeps every clause that makes it survivable, so it can be
# shortened into NEITHER A BAN NOR NOTHING.
#
# WHY THIS EXISTS. On 2026-08-29 an agent spent 39m 47s and 269.4k tokens running all 45
# harnesses locally to learn what the required `harness suite` check reports on a clean
# runner in about 9 minutes and no tokens. Nothing told it not to — `CONVENTIONS.md` told
# it the opposite ("Run the repo's build, lint, and tests green before opening a PR"),
# which on a repo whose test suite IS the 45-harness run instructs exactly that spend.
# The fix is prose, and prose is invisible when it fails: see the control panel's
# knowledge/findings/a-rule-with-no-reader-is-not-a-rule.md, six instances in one month.
# So the rule gets a reader in the same change, following the pattern
# `tests/pr-body-shape.test.sh` already uses for CONVENTIONS rules.
#
# THE RULE HAS TWO OPPOSITE FAILURE MODES, AND THIS FILE PINS AGAINST BOTH.
#
#   Shortened into A BAN. Keep "don't run the full suite" and drop the reasons, and the
#   next reader gets "stop testing locally" — which is not what it says and would cost the
#   thing the rule deliberately keeps: a PER-BRANCH signal before a push. Batching several
#   agents' work through CI tells you THE BATCH is broken without telling you WHOSE change
#   broke it. That sentence is load-bearing, so it is asserted by name, and MUTATION B
#   below deletes exactly it and requires this file to notice.
#
#   Shortened into NOTHING. Drop the bullet and the repo is back where it started, with
#   the reconciled verification bullet above it no longer pointing at anything. MUTATION A
#   deletes the whole bullet; every clause assertion must flip.
#
# THE FOUR CLAUSES THAT GET THEIR OWN MUTATION, because each is individually droppable by
# an editor who thinks it is redundant:
#   * the per-branch-signal justification (B) — reads as padding around a clear rule;
#   * the no-polling prohibition (C) — reads as a restatement of "don't run the full
#     suite", and is not: you can obey that and still park on some other long job. It is
#     the parked-watcher failure `check-dispatch.sh` exists for, with a pulse;
#   * the measured trade (D) — reads as trivia, and is the only thing that lets a future
#     reader decide the rule has stopped applying rather than argue with it;
#   * the escape hatch (E) — reads as a loophole, and is what stops the rule being a ban:
#     a change to shared machinery every test loads may be run in full, and the PR body
#     says why.
#
# AND IT PINS THE RECONCILIATION IN BOTH DIRECTIONS. The old sentence "Run the repo's
# build, lint, and tests green before opening a PR" is asserted ABSENT — the contradiction
# criterion 8 of the task exists to remove — and that assertion is proved non-vacuous by a
# mutant with the sentence pasted back in, which must flip it. Two repo-local documents
# carried the same contradiction (`CLAUDE.md` and `.claude/rules/tests.md`, the latter
# loading for every agent that opens anything under `tests/`) and are pinned too.
#
# AND THAT THE RULE IS NOT COPIED INTO THE ROLE AGENTS. `CONVENTIONS.md` is the stated
# single source of truth for shared role-agent behaviour and says so in its own first
# paragraph; the agents reach it by the reference they already carry. A future edit that
# "helpfully" pastes the rule into software-engineer.md is the drift that keep-in-sync
# rule exists to prevent, so the distinctive phrases are asserted absent there.
#
# Matching is done on a NEWLINE-SQUEEZED copy of each document, so a phrase that reflows
# across a line break still matches and a future re-wrap does not turn this red for a
# change nobody made.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONV="$REPO/plugin/seed/CONVENTIONS.md"
CLAUDEMD="$REPO/CLAUDE.md"
TESTRULE="$REPO/.claude/rules/tests.md"
AGENTS="$REPO/plugin/agents"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/local-vs-ci-testing.XXXXXX")" || {
  echo "local-vs-ci-testing.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# One line, single-spaced: phrase matching survives a re-wrap.
flatten() { tr '\n' ' ' < "$1" | tr -s ' '; }

saw() { # <haystack> <fixed string> -> yes|no
  printf '%s' "$1" | grep -qF -- "$2" && echo yes || echo no
}

# Delete the bullet that starts with <marker> — from that line to the line before the
# next top-level `- ` bullet. This is the "just make it shorter" edit.
strip_bullet() { # <file> <marker>
  awk -v m="$2" '
    index($0, m) && /^- / { skip=1; next }
    skip && /^- /          { skip=0 }
    !skip                  { print }
  ' "$1"
}

# Delete from the line containing <from> up to (not including) the line containing <to>.
# This is the finer edit: dropping ONE clause out of a bullet that survives.
strip_range() { # <file> <from> <to>
  awk -v a="$2" -v b="$3" '
    index($0, a) && !skip { skip=1 }
    skip && index($0, b)  { skip=0 }
    !skip                 { print }
  ' "$1"
}

for f in "$CONV" "$CLAUDEMD" "$TESTRULE"; do
  [ -f "$f" ] || { echo "local-vs-ci-testing.test: $f not found" >&2; exit 2; }
done
[ -d "$AGENTS" ] || { echo "local-vs-ci-testing.test: $AGENTS not found" >&2; exit 2; }

CONV_FLAT="$(flatten "$CONV")"
CLAUDE_FLAT="$(flatten "$CLAUDEMD")"
RULE_FLAT="$(flatten "$TESTRULE")"

# The bullet marker every mutation below keys off, and the phrases the rule is made of.
BULLET='**The full suite belongs to CI — locally, run the tests your change touches.**'
TOUCH='**run the tests your change touches, plus anything that exercises the file you edited**'
NOFULL='**do not run the full suite locally as a matter of course**'
RERUN='**This is a rule about RE-RUNNING, not about testing.**'
SIGNAL='**Keep the per-branch signal, and this is why:**'
BATCH='batching several agents'
HATCH='**The escape hatch exists and is bounded.**'
SHARED='**shared machinery every test loads**'
SAYWHY='**the PR body must state why the full run was needed**'
POLL='**Do not poll a long-running local run.**'
NOTRESTATE='This is its own prohibition, not a restatement'
PARKED='**parked-watcher failure `check-dispatch.sh` exists for, with a pulse**'
CI_COST='**about 20 minutes of wall clock and no tokens**'
LOCAL_COST='**39m 47s and 269.4k tokens**'
NOTBAN='**proportion argument, not a ban**'
REQUIRED='the `harness suite` job is a **required check** on every PR'
STRICT='**`strict=true`**'
MERGEDBASE='against the merged base'
OLD_CONTRADICTION="Run the repo's build, lint, and tests green before opening a PR."

echo "== 1. run what you touch, and do not run the full suite as a matter of course =="
ok "the bullet exists and names CI"        "$(saw "$CONV_FLAT" "$BULLET")" yes
ok "run the tests your change touches"     "$(saw "$CONV_FLAT" "$TOUCH")" yes
ok "…plus what exercises the file edited"  "$(saw "$CONV_FLAT" 'anything that exercises the file you edited')" yes
ok "not the full suite, as a matter of course" "$(saw "$CONV_FLAT" "$NOFULL")" yes
ok "the scope is RE-RUNNING, not testing"  "$(saw "$CONV_FLAT" "$RERUN")" yes
ok "…and following it still means testing" "$(saw "$CONV_FLAT" 'you still test before every push')" yes

echo
echo "== 2. THE REASON the local signal is kept — without it the rule reads as a ban =="
ok "the per-branch signal is kept by name" "$(saw "$CONV_FLAT" "$SIGNAL")" yes
ok "…for its own branch, before it pushes" "$(saw "$CONV_FLAT" '**for its own branch, before it pushes**')" yes
ok "…because batching hides whose change"  "$(saw "$CONV_FLAT" "$BATCH")" yes
ok "…the batch vs whose change is spelled" "$(saw "$CONV_FLAT" 'is broken without telling you *whose change* broke it')" yes
ok "…and the misreading is named"          "$(saw "$CONV_FLAT" 'reads as "stop testing locally"')" yes

echo
echo "== 3. the escape hatch exists, is bounded, and costs a line in the PR body =="
ok "the escape hatch is named"             "$(saw "$CONV_FLAT" "$HATCH")" yes
ok "…bounded to shared machinery"          "$(saw "$CONV_FLAT" "$SHARED")" yes
ok "…and the PR body must say why"         "$(saw "$CONV_FLAT" "$SAYWHY")" yes
ok "…an exception with a stated cost"      "$(saw "$CONV_FLAT" 'exception carrying a stated cost, not a free choice')" yes

echo
echo "== 4. polling is its OWN prohibition, not a restatement of the one above =="
ok "do not poll a long local run"          "$(saw "$CONV_FLAT" "$POLL")" yes
ok "…stated to be its own prohibition"     "$(saw "$CONV_FLAT" "$NOTRESTATE")" yes
ok "…the parked-watcher failure is cited"  "$(saw "$CONV_FLAT" "$PARKED")" yes
ok "…and why it is not redundant is given" "$(saw "$CONV_FLAT" 'still burn an hour watching some *other* long job')" yes

echo
echo "== 5. the trade is NAMED WITH THE NUMBERS, so a reader can tell when it inverts =="
ok "one CI round-trip: ~20 min, no tokens"  "$(saw "$CONV_FLAT" "$CI_COST")" yes
ok "the local run: 39m 47s / 269.4k"       "$(saw "$CONV_FLAT" "$LOCAL_COST")" yes
ok "…dated to the measurement"             "$(saw "$CONV_FLAT" 'measured **2026-08-29**')" yes
ok "it is a proportion argument, not a ban" "$(saw "$CONV_FLAT" "$NOTBAN")" yes
ok "…a red local run would have saved one" "$(saw "$CONV_FLAT" 'a *red* local run would have saved a CI round-trip')" yes
ok "…and the condition to invert is stated" "$(saw "$CONV_FLAT" 'this rule inverts')" yes

echo
echo "== 6. the authority is named: a required check under strict=true =="
ok "harness suite is a required check"     "$(saw "$CONV_FLAT" "$REQUIRED")" yes
ok "…cited to the PR that made it one"     "$(saw "$CONV_FLAT" 'https://github.com/cbmono/ai-bridge/pull/42')" yes
ok "branch protection sets strict=true"    "$(saw "$CONV_FLAT" "$STRICT")" yes
ok "…forcing a run on the merged base"     "$(saw "$CONV_FLAT" "$MERGEDBASE")" yes
ok "the local run never was the gate"      "$(saw "$CONV_FLAT" '**The local run never was the gate.**')" yes
ok "…so it is not less verification"       "$(saw "$CONV_FLAT" 'asks nobody to trust **less** verification')" yes

echo
echo "== 7. RECONCILED: the bullet that instructed the full local run is gone =="
ok "the old contradicting sentence is out" "$(saw "$CONV_FLAT" "$OLD_CONTRADICTION")" no
ok "build and lint are still required"     "$(saw "$CONV_FLAT" "**Get the repo's build and lint green before opening a PR")" yes
ok "…and 'tests' now means what you touch" "$(saw "$CONV_FLAT" '**the ones your change touches, not the whole suite**')" yes
ok "…deferring to the bullet that follows" "$(saw "$CONV_FLAT" 'where the scope of "tests" is settled')" yes
ok "report-rather-than-open survives"      "$(saw "$CONV_FLAT" "report rather than open the PR")" yes

echo
echo "== 8. the two repo-local docs no longer instruct the routine full local run =="
ok "CLAUDE.md: the suite must pass in CI"  "$(saw "$CLAUDE_FLAT" '**There is a test suite and it must pass — in CI.**')" yes
ok "CLAUDE.md: run what you touch locally" "$(saw "$CLAUDE_FLAT" '**Locally, run only the harnesses your change touches**')" yes
ok "CLAUDE.md: points at CONVENTIONS.md"   "$(saw "$CLAUDE_FLAT" 'See `plugin/seed/CONVENTIONS.md` → "The full suite belongs to CI"')" yes
ok "tests rule: not all of them"           "$(saw "$RULE_FLAT" '**Run the harnesses your change touches before pushing — not all of them:**')" yes
ok "tests rule: no longer 'run them all'"  "$(saw "$RULE_FLAT" 'Run them all before pushing')" no
ok "tests rule: defers to CONVENTIONS.md"  "$(saw "$RULE_FLAT" 'is the rule this defers to')" yes

echo
echo "== 9. the rule is NOT copied into the role agents — they carry the reference =="
# CONVENTIONS.md says so about itself; a paste into an agent file is the drift that
# keep-in-sync rule exists to prevent. Assert the two most quotable phrases are absent.
# A missing file is counted SEPARATELY from a pasted rule: an absence check over a file
# that is not there passes for the wrong reason, which is the one thing this section
# cannot afford. Both counts are asserted.
copies=0; missing=0
for a in software-engineer devops-engineer qa-reviewer; do
  f="$AGENTS/$a.md"
  if [ ! -f "$f" ]; then missing=$((missing+1)); continue; fi
  af="$(flatten "$f")"
  [ "$(saw "$af" "$BULLET")" = yes ] && copies=$((copies+1))
  [ "$(saw "$af" "$NOFULL")" = yes ] && copies=$((copies+1))
done
ok "all 3 role-agent files were read"      "$missing" 0
ok "no role agent restates the rule"       "$copies" 0
ok "CONVENTIONS is the single source"      "$(saw "$CONV_FLAT" '**This is the single source of truth for shared role-agent behaviour.**')" yes
ok "…with its keep-in-sync instruction"    "$(saw "$CONV_FLAT" '**keep them in sync**')" yes

echo
echo "== 10. MUTATION A: cut the whole bullet — every clause assertion flips =="
strip_bullet "$CONV" "$BULLET" > "$TMP/conv-no-rule.md"
A_FLAT="$(flatten "$TMP/conv-no-rule.md")"
ok "the mutation removed something"        "$([ "$(wc -c < "$TMP/conv-no-rule.md")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no)" yes
ok "CONTROL: build/lint bullet survives"   "$(saw "$A_FLAT" "**Get the repo's build and lint green before opening a PR")" yes
ok "CONTROL: the PR-size bullet survives"  "$(saw "$A_FLAT" '**PR size is a heuristic that suggests a split, never a gate.**')" yes
ok "mutant: run-what-you-touch is gone"    "$(saw "$A_FLAT" "$TOUCH")" no
ok "mutant: not-the-full-suite is gone"    "$(saw "$A_FLAT" "$NOFULL")" no
ok "mutant: the per-branch signal is gone" "$(saw "$A_FLAT" "$SIGNAL")" no
ok "mutant: the escape hatch is gone"      "$(saw "$A_FLAT" "$HATCH")" no
ok "mutant: the no-polling clause is gone" "$(saw "$A_FLAT" "$POLL")" no
ok "mutant: the measured numbers are gone" "$(saw "$A_FLAT" "$LOCAL_COST")" no
ok "mutant: the authority is gone"         "$(saw "$A_FLAT" "$REQUIRED")" no

echo
echo "== 11. MUTATION B: keep the behaviour, cut the reason — the ban shape =="
# The likeliest bad edit: "the rule is clear, the justification is padding". What is left
# reads as "stop testing locally", which is the misreading this rule exists to prevent.
strip_range "$CONV" "$RERUN" "$HATCH" > "$TMP/conv-ban.md"
B_FLAT="$(flatten "$TMP/conv-ban.md")"
ok "the mutation removed something"        "$([ "$(wc -c < "$TMP/conv-ban.md")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no)" yes
ok "CONTROL: the behaviour clause remains" "$(saw "$B_FLAT" "$NOFULL")" yes
ok "CONTROL: the escape hatch remains"     "$(saw "$B_FLAT" "$HATCH")" yes
ok "CONTROL: the numbers remain"           "$(saw "$B_FLAT" "$LOCAL_COST")" yes
ok "mutant: RE-RUNNING-not-testing gone"   "$(saw "$B_FLAT" "$RERUN")" no
ok "mutant: the per-branch signal is gone" "$(saw "$B_FLAT" "$SIGNAL")" no
ok "mutant: the batching reason is gone"   "$(saw "$B_FLAT" "$BATCH")" no

echo
echo "== 12. MUTATION C: cut the no-polling clause as 'redundant' =="
strip_range "$CONV" "$POLL" '**The trade, with the measured numbers' > "$TMP/conv-no-poll.md"
C_FLAT="$(flatten "$TMP/conv-no-poll.md")"
ok "the mutation removed something"        "$([ "$(wc -c < "$TMP/conv-no-poll.md")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no)" yes
ok "CONTROL: not-the-full-suite remains"   "$(saw "$C_FLAT" "$NOFULL")" yes
ok "CONTROL: the numbers remain"           "$(saw "$C_FLAT" "$CI_COST")" yes
ok "mutant: do-not-poll is gone"           "$(saw "$C_FLAT" "$POLL")" no
ok "mutant: its own-prohibition note gone" "$(saw "$C_FLAT" "$NOTRESTATE")" no
ok "mutant: the parked-watcher cite gone"  "$(saw "$C_FLAT" "$PARKED")" no

echo
echo "== 13. MUTATION D: cut the measured trade — the rule becomes an assertion =="
strip_range "$CONV" '**The trade, with the measured numbers' '**The local run never was the gate.**' > "$TMP/conv-no-cost.md"
D_FLAT="$(flatten "$TMP/conv-no-cost.md")"
ok "the mutation removed something"        "$([ "$(wc -c < "$TMP/conv-no-cost.md")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no)" yes
ok "CONTROL: the authority remains"        "$(saw "$D_FLAT" "$REQUIRED")" yes
ok "CONTROL: the per-branch signal remains" "$(saw "$D_FLAT" "$SIGNAL")" yes
ok "mutant: the CI cost is gone"           "$(saw "$D_FLAT" "$CI_COST")" no
ok "mutant: the local cost is gone"        "$(saw "$D_FLAT" "$LOCAL_COST")" no
ok "mutant: not-a-ban is gone"             "$(saw "$D_FLAT" "$NOTBAN")" no

echo
echo "== 14. MUTATION E: cut the escape hatch — the rule becomes absolute =="
strip_range "$CONV" "$HATCH" "$POLL" > "$TMP/conv-no-hatch.md"
E_FLAT="$(flatten "$TMP/conv-no-hatch.md")"
ok "the mutation removed something"        "$([ "$(wc -c < "$TMP/conv-no-hatch.md")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no)" yes
ok "CONTROL: the no-polling clause remains" "$(saw "$E_FLAT" "$POLL")" yes
ok "CONTROL: run-what-you-touch remains"   "$(saw "$E_FLAT" "$TOUCH")" yes
ok "mutant: the escape hatch is gone"      "$(saw "$E_FLAT" "$HATCH")" no
ok "mutant: the PR-body cost is gone"      "$(saw "$E_FLAT" "$SAYWHY")" no

echo
echo "== 15. MUTATION F: paste the old contradiction back — section 7 must notice =="
# Non-vacuity for an ABSENCE assertion: an absence check passes against a document with
# nothing in it, so prove it fails against the document it is meant to reject.
{ cat "$CONV"; printf '\n- %s If you can\047t get them green, report rather than open the PR.\n' "$OLD_CONTRADICTION"; } > "$TMP/conv-readded.md"
F_FLAT="$(flatten "$TMP/conv-readded.md")"
ok "CONTROL: the new rule still stands"    "$(saw "$F_FLAT" "$BULLET")" yes
ok "re-added: the contradiction is seen"   "$(saw "$F_FLAT" "$OLD_CONTRADICTION")" yes

# Same, for the `.claude/rules/tests.md` absence assertion in section 8.
{ cat "$TESTRULE"; printf '\nRun them all before pushing:\n'; } > "$TMP/rule-readded.md"
G_FLAT="$(flatten "$TMP/rule-readded.md")"
ok "CONTROL: run-what-you-touch stands"    "$(saw "$G_FLAT" '**Run the harnesses your change touches before pushing — not all of them:**')" yes
ok "re-added: 'run them all' is seen"      "$(saw "$G_FLAT" 'Run them all before pushing')" yes

# Same, for section 9's "not copied into the role agents" absence assertion.
cp "$AGENTS/software-engineer.md" "$TMP/agent-copy.md"
printf '\n%s\n' "$BULLET" >> "$TMP/agent-copy.md"
ok "re-added: a pasted rule is seen"       "$(saw "$(flatten "$TMP/agent-copy.md")" "$BULLET")" yes

echo
# A suite can LOSE assertions without going red — an unterminated string once swallowed
# nine of them and the file still reported fail=0. Pin the count so a block that stops
# executing shows up here rather than as silence.
total=$((pass + fail))
ok "exactly 85 assertions ran"             "$total" 85

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
