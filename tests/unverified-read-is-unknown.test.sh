#!/usr/bin/env bash
#
# unverified-read-is-unknown.test.sh — the UNKNOWN rule survives in `seed/CONVENTIONS.md`
# WITH its four measured examples, and stays referenced from the three places that make
# the claims: the launcher, the tick, and the rule it generalises.
#
# WHY THIS EXISTS. Four of the twelve symptoms of 2026-09-08 (`alteos`) were one defect —
# the read returned something and the something was treated as the answer — and every one
# of them was made in the main session. The fix is prose, and prose with no reader rots:
# the previous fix for this class shipped 2026-08-23 and was gone within weeks (control
# panel: knowledge/findings/a-rule-with-no-reader-is-not-a-rule.md). Modelled on
# tests/read-the-error-text-first.test.sh, which pins its sibling rule the same way.
#
# THE TWO FAILURE MODES IT PINS AGAINST, because a thinning edit arrives as one of these:
#
#   THE EXAMPLES ARE CUT AS DECORATION. The rule reads complete without them — which is
#   the whole problem, since its abstract form is already believed by everyone who then
#   breaks it. MUTATION B deletes exactly the table and requires all eight halves to flip.
#
#   THE SEED ARGUMENT IS CUT AS HISTORY. Why this is seed prose and not one bundle's rule
#   is the independent reinvention, and a later tidy-up reads that as backstory.
#   MUTATION C deletes it with the rule left standing.
#
# Matching is done on a NEWLINE-SQUEEZED copy of each document, so a phrase that reflows
# across a line break still matches and a re-wrap does not turn this red for no change.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONV="$REPO/plugin/seed/CONVENTIONS.md"
SEED="$REPO/plugin/seed/CLAUDE.md"
PM="$REPO/plugin/agents/project-manager.md"
SKILL="$REPO/plugin/skills/dispatch/SKILL.md"
EVALS="$REPO/plugin/evals/README.md"
EVALCASE="$REPO/plugin/evals/unverified-state-is-unknown"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/unverified-read-is-unknown.XXXXXX")" || {
  echo "unverified-read-is-unknown.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
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
    skip && /^- /          { skip=0 }
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

for f in "$CONV" "$SEED" "$PM" "$SKILL" "$EVALS"; do
  [ -f "$f" ] || { echo "unverified-read-is-unknown.test: $f not found" >&2; exit 2; }
done

CONV_FLAT="$(flatten "$CONV")"
SEED_FLAT="$(flatten "$SEED")"
PM_FLAT="$(flatten "$PM")"
SKILL_FLAT="$(flatten "$SKILL")"
EVALS_FLAT="$(flatten "$EVALS")"

# ---- the rule ----
NAME='A read that could not have established the answer returns UNKNOWN'
HEAD="**$NAME — and UNKNOWN is reported as UNKNOWN, never as a conclusion.**"
BULLET_LINE="- **$NAME — and UNKNOWN is"
TEST='The test is **what the read could have established**, and it is **NOT whether the read errored**'
EXIT0='all four failures below returned something, exit 0, no error, and the something was taken for the answer'
CROSSED='That is the distinction every one of them crossed.'
FALSIFY='could this command, run exactly like this, have come back DIFFERENT if the claim I am about to make were false?'
REPORT='what you report is `UNKNOWN` plus the read that would settle it'
MEASURED='**The four, measured in one day (`alteos`, 2026-09-08), each a claim made to a human**'
BELIEVED='**The abstract form of this rule is already believed by everyone who then breaks it**'
TABLE='| The read returned | It could not have established |'

# ---- the four examples: what came back, and what it could not have shown ----
E1R='a mid-rollout image digest compared against the **empty string** — no digest, no error, exit 0'
E1C='that the new build is not live anywhere: an empty digest is what "nothing is there" and "I could not look" both print'
E2R='a check run whose conclusion is failure — but the run was **superseded**'
E2C="that the head's checks are failing: a superseded run is a verdict on a commit that has already been replaced"
E3R='**`200`** from a region with **no pod behind it**'
E3C='that the region is serving: an edge that answers in front of the pods reports on itself, not on them'
E4R='a **matcher** read out of a workflow config, asserted as a 20-workflow regression'
E4C='that 20 workflows regressed when **no other workflow had run**: a pattern says what would match, never what did'

# ---- why the seed, and who reads it ----
LAUNCHER='**This rule belongs to the LAUNCHER as much as to the tick, which is why it is here and not in one agent.**'
NOADJ='the launcher (`skills/dispatch/SKILL.md`) has none at all — and the launcher is what made all four of those claims'
SEEDPLACE='**It ships in the SEED because an installation had already reinvented it**'
REINVENT="one stamped bundle wrote *\"never manufacture a decision out of a side effect that isn't live yet\"* into its own \`CLAUDE.md\` by hand"
TWOINST='A rule two installations write independently belongs in the seed rather than in a bundle.'
ROT='prose alone already rotted once — on 2026-08-23'
EVALREF='`plugin/evals/unverified-state-is-unknown` in `cbmono/loopd` grades the behaviour'
TESTREF='`tests/unverified-read-is-unknown.test.sh` pins this rule, all four examples and the references to it'

# ---- the references, both ways ----
PMREF='it binds every state claim a tick writes'
SKILLREF='is a launcher rule before it is anyone else'
SEEDBACK="It is the narrow case of \`CONVENTIONS.md\` → \"$NAME\"."
EVALSBACK="\`unverified-state-is-unknown\` is the behavioural reader for \`seed/CONVENTIONS.md\` → \"$NAME\""

echo "== 1. CONVENTIONS.md: the rule, and the distinction all four failures crossed =="
ok "the bullet exists"                      "$(saw "$CONV_FLAT" "$HEAD")" yes
ok "…the test is what the read ESTABLISHED" "$(saw "$CONV_FLAT" "$TEST")" yes
ok "…not whether it errored: exit 0, twice over" "$(saw "$CONV_FLAT" "$EXIT0")" yes
ok "…and that is named as the distinction"  "$(saw "$CONV_FLAT" "$CROSSED")" yes
ok "…the falsification question is given"   "$(saw "$CONV_FLAT" "$FALSIFY")" yes
ok "…UNKNOWN is reported, with the read that would settle it" "$(saw "$CONV_FLAT" "$REPORT")" yes

echo
echo "== 2. all four measured corollaries ship as its examples =="
ok "the examples are dated and measured"    "$(saw "$CONV_FLAT" "$MEASURED")" yes
ok "…and say why they ship at all"          "$(saw "$CONV_FLAT" "$BELIEVED")" yes
ok "1. the EMPTY STRING digest, returned"   "$(saw "$CONV_FLAT" "$E1R")" yes
ok "…and what it could not have shown"      "$(saw "$CONV_FLAT" "$E1C")" yes
ok "2. the SUPERSEDED check run, returned"  "$(saw "$CONV_FLAT" "$E2R")" yes
ok "…and what it could not have shown"      "$(saw "$CONV_FLAT" "$E2C")" yes
ok "3. the 200 with NO POD, returned"       "$(saw "$CONV_FLAT" "$E3R")" yes
ok "…and what it could not have shown"      "$(saw "$CONV_FLAT" "$E3C")" yes
ok "4. the MATCHER regression, returned"    "$(saw "$CONV_FLAT" "$E4R")" yes
ok "…and what it could not have shown"      "$(saw "$CONV_FLAT" "$E4C")" yes

echo
echo "== 3. the seed placement is argued in the shipped text, not left to the task doc =="
ok "the launcher owns it as much as the tick" "$(saw "$CONV_FLAT" "$LAUNCHER")" yes
ok "…because it has no adjacent discipline" "$(saw "$CONV_FLAT" "$NOADJ")" yes
ok "the seed is justified by reinvention"   "$(saw "$CONV_FLAT" "$SEEDPLACE")" yes
ok "…naming the rule an installation wrote" "$(saw "$CONV_FLAT" "$REINVENT")" yes
ok "…and the general form of that argument" "$(saw "$CONV_FLAT" "$TWOINST")" yes
ok "the 2026-08-23 rot is why it has readers" "$(saw "$CONV_FLAT" "$ROT")" yes
ok "…the eval case is named"                "$(saw "$CONV_FLAT" "$EVALREF")" yes
ok "…and so is this harness"                "$(saw "$CONV_FLAT" "$TESTREF")" yes

echo
echo "== 4. referenced from the three contexts that made the claims =="
ok "the tick names the rule"                "$(saw "$PM_FLAT" "\"$NAME\"")" yes
ok "…and says what it binds there"          "$(saw "$PM_FLAT" "$PMREF")" yes
ok "the launcher names the rule"            "$(saw "$SKILL_FLAT" "\"$NAME\"")" yes
ok "…and that it is a launcher rule first"  "$(saw "$SKILL_FLAT" "$SKILLREF")" yes
ok "the role-agent contract carries the rule itself" "$(saw "$CONV_FLAT" "$HEAD")" yes

echo
echo "== 5. cross-referenced BOTH WAYS to the eval case and to the rule it generalises =="
ok "seed/CLAUDE.md's rule points back up"   "$(saw "$SEED_FLAT" "$SEEDBACK")" yes
ok "…and the rule it hangs off still stands" \
   "$(saw "$SEED_FLAT" '**Never manufacture a decision out of a side effect that isn'"'"'t live yet.**')" yes
ok "the eval README points back at the rule" "$(saw "$EVALS_FLAT" "$EVALSBACK")" yes
ok "the eval case named by both exists"     "$([ -f "$EVALCASE/prompt.md" ] && echo yes || echo no)" yes
ok "…and it is the empty-digest instance"   "$(saw "$(flatten "$EVALCASE/prompt.md")" 'the command printed an empty string')" yes
ok "…graded, not merely present"            \
   "$([ -n "$(find "$EVALCASE/graders" -name '*.md' 2>/dev/null)" ] && echo yes || echo no)" yes

echo
echo "== 6. MUTATION A: cut the whole bullet — every assertion above CONVENTIONS flips =="
strip_bullet "$CONV" "$BULLET_LINE" > "$TMP/conv-no-rule.md"
A_FLAT="$(flatten "$TMP/conv-no-rule.md")"
ok "the mutation removed something"         "$([ "$(wc -c < "$TMP/conv-no-rule.md")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no)" yes
ok "CONTROL: the PR-size bullet survives"   "$(saw "$A_FLAT" '**PR size is a heuristic that suggests a split, never a gate.**')" yes
ok "CONTROL: the error-text bullet survives" "$(saw "$A_FLAT" '**1. THE ERROR TEXT FIRST, BEFORE ANY HYPOTHESIS EXISTS.**')" yes
ok "mutant: the rule is gone"               "$(saw "$A_FLAT" "$HEAD")" no
ok "mutant: the distinction is gone"        "$(saw "$A_FLAT" "$TEST")" no
ok "mutant: the four examples are gone"     "$(saw "$A_FLAT" "$E1R")" no
ok "mutant: the seed argument is gone"      "$(saw "$A_FLAT" "$SEEDPLACE")" no

echo
echo "== 7. MUTATION B: keep the rule, cut the EXAMPLES — the thinning shape =="
# The likeliest bad edit: the rule reads complete without them, so the table looks like
# padding. What is left is the abstract form, which is the one everybody already agreed
# with on the day they broke it.
strip_range "$CONV" "$TABLE" '**This rule belongs to the LAUNCHER' > "$TMP/conv-no-examples.md"
B_FLAT="$(flatten "$TMP/conv-no-examples.md")"
ok "the mutation removed something"         "$([ "$(wc -c < "$TMP/conv-no-examples.md")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no)" yes
ok "CONTROL: the rule itself remains"       "$(saw "$B_FLAT" "$HEAD")" yes
ok "CONTROL: the falsification question remains" "$(saw "$B_FLAT" "$FALSIFY")" yes
ok "mutant: the empty-string digest is gone" "$(saw "$B_FLAT" "$E1R")" no
ok "mutant: the superseded check run is gone" "$(saw "$B_FLAT" "$E2R")" no
ok "mutant: the 200 with no pod is gone"    "$(saw "$B_FLAT" "$E3R")" no
ok "mutant: the matcher regression is gone" "$(saw "$B_FLAT" "$E4R")" no
ok "mutant: and so is every could-not-have half" \
   "$(saw "$B_FLAT" "$E4C")" no

echo
echo "== 8. MUTATION C: cut the SEED argument as history, rule and examples left standing =="
strip_range "$CONV" '**This rule belongs to the LAUNCHER' '**Its two readers, because prose alone' > "$TMP/conv-no-seed.md"
C_FLAT="$(flatten "$TMP/conv-no-seed.md")"
ok "the mutation removed something"         "$([ "$(wc -c < "$TMP/conv-no-seed.md")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no)" yes
ok "CONTROL: the rule survives"             "$(saw "$C_FLAT" "$HEAD")" yes
ok "CONTROL: the four examples survive"     "$(saw "$C_FLAT" "$E2C")" yes
ok "mutant: the reinvention evidence is gone" "$(saw "$C_FLAT" "$REINVENT")" no
ok "mutant: the two-installations argument is gone" "$(saw "$C_FLAT" "$TWOINST")" no
ok "mutant: the launcher's ownership is gone" "$(saw "$C_FLAT" "$NOADJ")" no

echo
echo "== 9. MUTATION D: drop the launcher's reference — the context that made all four =="
strip_range "$SKILL" '**And what the four you DO have establish is bounded' 'Why: every byte read here lands' > "$TMP/skill-no-ref.md"
D_FLAT="$(flatten "$TMP/skill-no-ref.md")"
ok "the mutation removed something"         "$([ "$(wc -c < "$TMP/skill-no-ref.md")" -lt "$(wc -c < "$SKILL")" ] && echo yes || echo no)" yes
ok "CONTROL: the allowlist of four survives" "$(saw "$D_FLAT" 'an ALLOWLIST of four')" yes
ok "CONTROL: its other CONVENTIONS reference survives" "$(saw "$D_FLAT" '`CONVENTIONS.md` → "A subagent works ONE task"')" yes
ok "mutant: the launcher no longer names the rule" "$(saw "$D_FLAT" "\"$NAME\"")" no

echo
echo "== 10. MUTATION E: drop the back-reference — the cross-reference goes one way only =="
grep -vF -- "\"$NAME\"." "$SEED" > "$TMP/seed-no-back.md"
E_FLAT="$(flatten "$TMP/seed-no-back.md")"
ok "the mutation removed something"         "$([ "$(wc -c < "$TMP/seed-no-back.md")" -lt "$(wc -c < "$SEED")" ] && echo yes || echo no)" yes
ok "CONTROL: the rule it generalises survives" \
   "$(saw "$E_FLAT" '**Never manufacture a decision out of a side effect that isn'"'"'t live yet.**')" yes
ok "CONTROL: the forward reference is untouched" "$(saw "$CONV_FLAT" "$REINVENT")" yes
ok "mutant: seed/CLAUDE.md no longer points up" "$(saw "$E_FLAT" "$SEEDBACK")" no

echo
# A suite can LOSE assertions without going red — an unterminated string once swallowed
# nine of them elsewhere in this directory and the file still reported fail=0. Pin the
# count so a block that stops executing shows up here rather than as silence.
# 64 and not 65: `total` is read BEFORE this assertion — itself the 65th `ok` — runs.
total=$((pass + fail))
ok "exactly 64 assertions ran"              "$total" 64

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
