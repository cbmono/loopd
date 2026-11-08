#!/usr/bin/env bash
#
# read-the-error-text-first.test.sh — the two clauses of the cheapest rule on the
# `launcher-verification-contract` list survive in BOTH files that carry them, and each
# one keeps THE COST that is the only reason anybody follows it.
#
# WHY THIS EXISTS. Retrospective of 2026-09-08 (`alteos`): the failing check's own error
# text already named both the RBAC problem and the wrong ArgoCD project. Both were guessed
# instead, in that order, wrongly, and each guess was probed with a full CI cycle — every
# stage through to testing — which is the direct cause of the "hours, and many builds" the
# owner reported. The fix is pure prose, and prose with no reader rots: see the control
# panel's knowledge/findings/a-rule-with-no-reader-is-not-a-rule.md, and the 2026-08-23
# fix for this same class that had no test and was gone within weeks. Modelled on
# tests/local-vs-ci-testing.test.sh, which pins a CONVENTIONS rule the same way.
#
# THE TWO FAILURE MODES IT PINS AGAINST, because "shorten it" arrives as one of these:
#
#   THE COST IS CUT AS PADDING. The instruction alone — "read the log", "test locally" —
#   is already believed by everyone who skipped it, so a clause reduced to its instruction
#   is a clause that changes nothing while looking present. MUTATIONS B and E delete
#   exactly the cost sentences and require every cost assertion to flip.
#
#   CLAUSE 1 IS DEMOTED OUT OF FIRST PLACE in failure-analyst.md. A diagnostician that has
#   reached a hypothesis before it opens the log has nothing left for the evidence to do,
#   so ORDER is the rule and position is asserted POSITIONALLY — the first `1. ` item of
#   the `## Diagnosis` section, not merely somewhere in the file. MUTATION D keeps the
#   clause and moves it to the end; the ordering assertion must notice.
#
# Matching is done on a NEWLINE-SQUEEZED copy of each document, so a phrase that reflows
# across a line break still matches and a re-wrap does not turn this red for no change.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# The rule moved verbatim to the testing detail of CONVENTIONS.md (leaner-prompts/task-002).
CONV="$REPO/plugin/seed/conventions/testing.md"
FA="$REPO/plugin/agents/failure-analyst.md"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/read-the-error-text-first.XXXXXX")" || {
  echo "read-the-error-text-first.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# One line, single-spaced: phrase matching survives a re-wrap.
flatten() { tr '\n' ' ' < "$1" | tr -s ' '; }

# Here-string, never a pipe: `grep -q` exits early and under `pipefail` a pipe into it
# reports a MATCH as a failure (knowledge: grep-q-under-pipefail-reports-a-match-as-a-failure).
saw() { # <haystack> <fixed string> -> yes|no
  grep -qF -- "$2" <<<"$1" && echo yes || echo no
}

# Delete the top-level bullet starting at <marker>, to the line before the next `- `.
strip_bullet() { # <file> <marker>
  awk -v m="$2" '
    index($0, m) && /^- / { skip=1; next }
    skip && /^(- |#)/          { skip=0 }
    !skip                  { print }
  ' "$1"
}

# Delete from the line containing <from> up to (not including) the line containing <to>.
strip_range() { # <file> <from> <to>
  awk -v a="$2" -v b="$3" '
    index($0, a) && !skip { skip=1 }
    skip && index($0, b)  { skip=0 }
    !skip                 { print }
  ' "$1"
}

# The `1. …` item of the `## Diagnosis` section, flattened — POSITION, not presence.
# Both bounds are needed: the section AND the next numbered item, or a demoted clause
# pasted after the section still reads as step 1 (it did, until it didn't).
diagnosis_step1() { # <file> -> flattened text of step 1
  awk '
    /^## Diagnosis/                     { insec=1; next }
    insec && /^## /                     { insec=0; instep=0 }
    !insec                              { next }
    /^1\. /                             { instep=1 }
    instep && /^[0-9]+\. / && !/^1\. /  { instep=0 }
    instep                              { print }
  ' "$1" | tr '\n' ' ' | tr -s ' '
}

# Move the clause-1 block out of first place and renumber — present, but no longer first.
demote_step1() { # <file>
  awk -v m1="$2" -v m2="$3" '
    index($0, m1) == 1        { grab=1 }
    grab && index($0, m2) == 1 { grab=0 }
    grab                      { buf = buf $0 "\n"; next }
    index($0, m2) == 1        { sub(/^2\./, "1."); print; next }
                              { print }
    END                       { printf "%s", buf }
  ' "$1"
}

for f in "$CONV" "$FA"; do
  [ -f "$f" ] || { echo "read-the-error-text-first.test: $f not found" >&2; exit 2; }
done

CONV_FLAT="$(flatten "$CONV")"
FA_FLAT="$(flatten "$FA")"

# ---- CONVENTIONS.md ----
BULLET="**A red check is EVIDENCE, and it is already written down: read the failing check's own error text BEFORE you form a hypothesis, and falsify locally BEFORE you push.**"
# strip_bullet() matches ONE line, so the mutation needs the marker as it is wrapped.
BULLET_LINE="**A red check is EVIDENCE, and it is already written down: read the failing check's own"
C1='**1. THE ERROR TEXT FIRST, BEFORE ANY HYPOTHESIS EXISTS.**'
C1COST='**The cost, measured on the day this rule comes from (`alteos`, 2026-09-08):**'
RBAC='already named both** the RBAC problem and the wrong ArgoCD project'
WRONGLY='Both were guessed instead, in that order, wrongly.'
ORDER='**Order is the whole rule**'
C2='**2. FALSIFY LOCALLY BEFORE YOU PUSH — A FULL CI CYCLE IS NOT A PROBE.**'
C2COST='a CI run takes **every stage through to testing**'
PIPELINE='costs a **whole pipeline** and not the one step you doubted'
HOURS='the "hours, and many builds" the owner reported'
META='because the instruction on its own is already believed by everyone who skipped it'
GAP='say **which clause you could not satisfy**'
READER='`tests/read-the-error-text-first.test.sh` in `cbmono/loopd` pins both clauses and both costs'

# ---- failure-analyst.md ----
FA_C1="1. **READ THE FAILING CHECK'S OWN ERROR TEXT — FIRST, BEFORE ANY HYPOTHESIS EXISTS.**"
FA_C1_HEAD="**READ THE FAILING CHECK'S OWN ERROR TEXT — FIRST, BEFORE ANY HYPOTHESIS EXISTS.**"
FA_C1COST='**The cost, measured (`alteos`, 2026-09-08):**'
FA_QUOTE='Quote the failing lines verbatim in your report'
FA_GATHER='2. **Gather context**'
FA_SYSTEMATIC="**never before you have read the failing check's own error text**"
FA_C2='FALSIFYING LOCALLY BEFORE A PUSH IS THE OTHER HALF OF THIS RULE. A full CI cycle is not a probe.**'
FA_C2COST='a CI run takes every stage through to testing, so a wrong guess costs a **whole pipeline**'
FA_PUSHSEE='A step whose only check is "push it and see" is not a next step'

echo "== 1. CONVENTIONS.md clause 1: the error text FIRST, with the cost of skipping it =="
ok "the bullet exists"                     "$(saw "$CONV_FLAT" "$BULLET")" yes
ok "clause 1 is stated"                    "$(saw "$CONV_FLAT" "$C1")" yes
ok "…names the command to read it with"    "$(saw "$CONV_FLAT" 'gh run view <run-id> --log-failed')" yes
ok "…ORDER is the rule, not the reading"   "$(saw "$CONV_FLAT" "$ORDER")" yes
ok "COST: dated to the measured day"       "$(saw "$CONV_FLAT" "$C1COST")" yes
ok "COST: the text already named both"     "$(saw "$CONV_FLAT" "$RBAC")" yes
ok "COST: both guessed, in order, wrongly" "$(saw "$CONV_FLAT" "$WRONGLY")" yes

echo
echo "== 2. CONVENTIONS.md clause 2: falsify locally, with the cost of skipping it =="
ok "clause 2 is stated"                    "$(saw "$CONV_FLAT" "$C2")" yes
ok "…a push confirms, it never tests"      "$(saw "$CONV_FLAT" 'it is never how you test one')" yes
ok "COST: every stage through to testing"  "$(saw "$CONV_FLAT" "$C2COST")" yes
ok "COST: a whole pipeline per guess"      "$(saw "$CONV_FLAT" "$PIPELINE")" yes
ok "COST: the hours-and-many-builds report" "$(saw "$CONV_FLAT" "$HOURS")" yes
ok "…and the no-local-run route is given"  "$(saw "$CONV_FLAT" "$GAP")" yes

echo
echo "== 3. the COST is stated as required, not as decoration, and it names its reader =="
ok "why the cost ships with the clause"    "$(saw "$CONV_FLAT" "$META")" yes
ok "…each clause ships with its cost"      "$(saw "$CONV_FLAT" '**the cost of skipping it**')" yes
ok "the harness is named in the prose"     "$(saw "$CONV_FLAT" "$READER")" yes
ok "…and so is the agent that leads on it" "$(saw "$CONV_FLAT" 'carries clause 1 as its **first** diagnosis step')" yes

echo
echo "== 4. failure-analyst.md: clause 1 is THE FIRST DIAGNOSIS STEP, positionally =="
STEP1="$(diagnosis_step1 "$FA")"
ok "a step 1 was found in ## Diagnosis"    "$([ -n "$STEP1" ] && echo yes || echo no)" yes
ok "step 1 IS the error-text clause"       "$(saw "$STEP1" "$FA_C1_HEAD")" yes
ok "…with the cost inside that same step"  "$(saw "$STEP1" "$FA_C1COST")" yes
ok "…the measured naming, in step 1"       "$(saw "$STEP1" "$RBAC")" yes
ok "…ORDER stated where it is executed"    "$(saw "$STEP1" "$ORDER")" yes
ok "…and the log is quoted onward"         "$(saw "$STEP1" "$FA_QUOTE")" yes
ok "the systematic line defers to step 1"  "$(saw "$FA_FLAT" "$FA_SYSTEMATIC")" yes

echo
echo "== 5. failure-analyst.md clause 2: the ranked steps must be locally falsifiable =="
ok "clause 2 is stated"                    "$(saw "$FA_FLAT" "$FA_C2")" yes
ok "…and it binds a read-only agent"       "$(saw "$FA_FLAT" 'your report is what somebody else pushes')" yes
ok "COST: every stage through to testing"  "$(saw "$FA_FLAT" "$FA_C2COST")" yes
ok "COST: the hours-and-many-builds report" "$(saw "$FA_FLAT" "$HOURS")" yes
ok "…push-it-and-see is not a next step"   "$(saw "$FA_FLAT" "$FA_PUSHSEE")" yes

echo
echo "== 6. the insertion renumbered the steps it displaced, references included =="
ok "Gather context is now step 2"          "$(saw "$FA_FLAT" "$FA_GATHER")" yes
ok "recent changes is now step 3"          "$(saw "$FA_FLAT" '3. **Check recent changes**')" yes
ok "classification is now step 4"          "$(saw "$FA_FLAT" '4. **Classify the failure**')" yes
ok "the base ref is kept by step 2"        "$(saw "$FA_FLAT" 'the ref step 2 kept')" yes
ok "…and diffed by step 3"                 "$(saw "$FA_FLAT" 'because step 3 diffs against it')" yes
ok "no stale 'step 1 kept' reference"      "$(saw "$FA_FLAT" 'the ref step 1 kept')" no

echo
echo "== 7. MUTATION A: cut the whole CONVENTIONS bullet — every clause assertion flips =="
strip_bullet "$CONV" "$BULLET_LINE" > "$TMP/conv-no-rule.md"
A_FLAT="$(flatten "$TMP/conv-no-rule.md")"
ok "the mutation removed something"        "$([ "$(wc -c < "$TMP/conv-no-rule.md")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no)" yes
ok "CONTROL: the UNKNOWN bullet survives" "$(saw "$A_FLAT" '**A read that could not have established the answer returns UNKNOWN')" yes
ok "CONTROL: the CI-suite bullet survives" "$(saw "$A_FLAT" '**The full suite belongs to CI — locally, run the tests your change touches.**')" yes
ok "mutant: clause 1 is gone"              "$(saw "$A_FLAT" "$C1")" no
ok "mutant: clause 2 is gone"              "$(saw "$A_FLAT" "$C2")" no
ok "mutant: the measured cost is gone"     "$(saw "$A_FLAT" "$RBAC")" no
ok "mutant: the pipeline cost is gone"     "$(saw "$A_FLAT" "$PIPELINE")" no

echo
echo "== 8. MUTATION B: keep both instructions, cut both COSTS — the shortening shape =="
# The likeliest bad edit: the instruction reads fine on its own, so the measured cost
# looks like history. What is left is the sentence everyone who skipped it already agreed
# with, which is the entire reason this file exists.
strip_range "$CONV" "$C1COST" "$C2" > "$TMP/conv-b1.md"
strip_range "$TMP/conv-b1.md" '**The cost, measured:**' '**When you genuinely cannot run it locally**' > "$TMP/conv-no-cost.md"
B_FLAT="$(flatten "$TMP/conv-no-cost.md")"
ok "the mutation removed something"        "$([ "$(wc -c < "$TMP/conv-no-cost.md")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no)" yes
ok "CONTROL: clause 1 instruction remains" "$(saw "$B_FLAT" "$C1")" yes
ok "CONTROL: clause 2 instruction remains" "$(saw "$B_FLAT" "$C2")" yes
ok "mutant: clause 1's cost is gone"       "$(saw "$B_FLAT" "$C1COST")" no
ok "mutant: the RBAC/ArgoCD naming is gone" "$(saw "$B_FLAT" "$RBAC")" no
ok "mutant: clause 2's cost is gone"       "$(saw "$B_FLAT" "$C2COST")" no
ok "mutant: the whole-pipeline cost is gone" "$(saw "$B_FLAT" "$PIPELINE")" no

echo
echo "== 9. MUTATION C: keep clause 1, drop clause 2 — half the rule is not the rule =="
strip_range "$CONV" "$C2" '- **A read that could not have established' > "$TMP/conv-half.md"
C_FLAT="$(flatten "$TMP/conv-half.md")"
ok "the mutation removed something"        "$([ "$(wc -c < "$TMP/conv-half.md")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no)" yes
ok "CONTROL: clause 1 survives"            "$(saw "$C_FLAT" "$C1")" yes
ok "CONTROL: clause 1's cost survives"     "$(saw "$C_FLAT" "$RBAC")" yes
ok "mutant: clause 2 is gone"              "$(saw "$C_FLAT" "$C2")" no
ok "mutant: clause 2's cost is gone"       "$(saw "$C_FLAT" "$C2COST")" no

echo
echo "== 10. MUTATION D: demote clause 1 out of first place — PRESENT, but no longer first =="
# The presence check cannot see this edit at all; only the positional one can.
demote_step1 "$FA" "$FA_C1" "$FA_GATHER" > "$TMP/fa-demoted.md"
D_STEP1="$(diagnosis_step1 "$TMP/fa-demoted.md")"
D_FLAT="$(flatten "$TMP/fa-demoted.md")"
ok "the mutation kept the file's size"     "$([ "$(wc -c < "$TMP/fa-demoted.md")" -eq "$(wc -c < "$FA")" ] && echo yes || echo no)" yes
ok "CONTROL: the clause is still present"  "$(saw "$D_FLAT" "$FA_C1_HEAD")" yes
ok "CONTROL: its cost is still present"    "$(saw "$D_FLAT" "$FA_C1COST")" yes
ok "mutant: step 1 is no longer the clause" "$(saw "$D_STEP1" "$FA_C1_HEAD")" no
ok "mutant: step 1 is Gather context now"  "$(saw "$D_STEP1" 'Gather context')" yes

echo
echo "== 11. MUTATION E: cut the COST out of failure-analyst's two clauses =="
strip_range "$FA" "$FA_C1COST" '   Quote the failing lines verbatim' > "$TMP/fa-e1.md"
strip_range "$TMP/fa-e1.md" '**The cost, measured:**' '   is "push it and see"' > "$TMP/fa-no-cost.md"
E_FLAT="$(flatten "$TMP/fa-no-cost.md")"
ok "the mutation removed something"        "$([ "$(wc -c < "$TMP/fa-no-cost.md")" -lt "$(wc -c < "$FA")" ] && echo yes || echo no)" yes
ok "CONTROL: clause 1 still leads"         "$(saw "$E_FLAT" "$FA_C1_HEAD")" yes
ok "CONTROL: clause 2 instruction remains" "$(saw "$E_FLAT" "$FA_C2")" yes
ok "mutant: clause 1's cost is gone"       "$(saw "$E_FLAT" "$FA_C1COST")" no
ok "mutant: the RBAC/ArgoCD naming is gone" "$(saw "$E_FLAT" "$RBAC")" no
ok "mutant: clause 2's cost is gone"       "$(saw "$E_FLAT" "$FA_C2COST")" no

echo
# A suite can LOSE assertions without going red — an unterminated string once swallowed
# nine of them elsewhere in this directory and the file still reported fail=0. Pin the
# count so a block that stops executing shows up here rather than as silence.
total=$((pass + fail))
ok "exactly 65 assertions ran"             "$total" 65

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
