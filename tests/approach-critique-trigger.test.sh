#!/usr/bin/env bash
#
# approach-critique-trigger.test.sh — the PM's `plan-architect` approach critique is
# MANDATORY ON ITS TRIGGER and ADVISORY IN WHAT IT MAY DECIDE, and neither half is
# allowed to drift into the other.
#
# WHY THIS IS A TEST AND NOT A PARAGRAPH SOMEBODY WROTE. The clause shipped as
# "you MAY dispatch … don't run it on every draft (cost)". Discretionary, non-binding
# and cost-suppressed together mean it ran on nothing, while `acceptance_criteria` —
# the artifact that becomes the PR body's checklist and whose unverified rows block
# clearance — went to the merge gate with no adversarial read at all. Measured
# 2026-08-31: an under-specified criterion took THREE rounds of external review to
# converge on what one such read would have caught before any code existed.
#
# Making it mandatory is one word. The three things that make it survive being one word
# are what is asserted here:
#
#   1. THE TRIGGER DID NOT MOVE, AND NEITHER DID THE AUTHORITY. What changed is WHEN the
#      critique runs; what it may DECIDE is untouched. So the trigger's own words are
#      pinned, and so is every "this is not a gate" clause — findings to `advisor_notes`
#      and nowhere else, no status, no `draft → ready`, `kind: research` still excluded.
#      A future edit that quietly hands the critique a veto fails here.
#   2. IT IS IDEMPOTENT, AND THE MARKER IS NAMED. Mandatory-on-trigger with no recorded
#      marker turns every tick into a fresh APEX-tier session on the same draft — the
#      most expensive failure this change could introduce. The instruction has to name
#      the receipt a tick reads before dispatching, and it does: an `advisor_notes`
#      entry per concern, or one `advisor_notes` line for a critique that raised none.
#      BOTH receipts live in `advisor_notes` because only `fold-answers.sh` writes
#      `answered_questions`, and it writes only what an answered `open_questions` entry
#      gave it — which a no-concerns critique never produces.
#   3. A MISSING OPTIONAL AGENT IS STILL NOT A FAILURE. Mandatory-on-trigger must not
#      become mandatory-to-exist: absent `~/.claude/agents/plan-architect.md` the PM
#      skips SILENTLY. And `plan-architect` stays OUT of `roles` while staying in
#      `roleTiers` at `apex` (SCHEMA.md's worked example of an agent no task is ever
#      assigned to), with the dispatch resolving its model through
#      `scripts/resolve-model.sh` rather than a hard-coded alias.
#
# TWO CLAIMS ARE DRIVEN, NOT READ. "`advisor_notes` is not a gate" is a claim about
# machinery, so the machinery is run: `validate-bundle.sh` against a bundle whose task
# carries advisor notes (it must pass and say nothing about them), and
# `write-snapshot.sh` over the same task (advisor notes must produce NO awaiting verb,
# while an open question on a sibling task still produces one — the control that keeps
# the first assertion non-vacuous).
#
# EVERY MUTATION IS GUARDED. A mutation whose anchor has moved prints SKIP and is never
# counted as caught: a check that silently stopped checking is worse than no check.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"   # PN: the plugin namespace a dispatch string carries
PM="$REPO/plugin/tick-steps/step-2-refine-drafts.md"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
SEED_CFG="$REPO/plugin/seed/instance.config.json"
VALIDATOR="$REPO/plugin/scripts/validate-bundle.sh"
WRITER="$REPO/plugin/scripts/write-snapshot.sh"
RESOLVE="$REPO/plugin/scripts/resolve-model.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/approach-critique.XXXXXX")" || {
  echo "approach-critique-trigger.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0; skip=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
skipped() { printf '  SKIP  %s\n' "$1"; skip=$((skip+1)); }
# `grep -c`, never `printf … | grep -q`: under `set -o pipefail` a `-q` exits at the first
# match and the writer's EPIPE becomes the pipeline's status, so the assertion inverts
# exactly when it is true.
saw() { # <haystack> <fixed string> -> yes|no
  [ "$(printf '%s\n' "$1" | grep -cF -- "$2")" -gt 0 ] && echo yes || echo no
}
hasf() { # <file> <fixed string> -> yes|no
  [ "$(grep -cF -- "$2" "$1")" -gt 0 ] && echo yes || echo no
}
flatten() { printf '%s' "$1" | tr '\n' ' ' | tr -s ' '; }

echo "== the files exist at all (or every assertion below is vacuous) =="
for f in "$PM" "$SCHEMA" "$SEED_CFG" "$VALIDATOR" "$WRITER" "$RESOLVE"; do
  ok "$(basename "$f") exists" "$([ -f "$f" ] && echo yes || echo no)" yes
done
command -v jq >/dev/null 2>&1 || { echo "approach-critique-trigger.test: jq required" >&2; exit 2; }

# The critique's own block: from its bold lead-in to the next numbered step. Extracted
# rather than grepped file-wide so an assertion cannot be satisfied by some other
# paragraph that happens to use the same words.
block_of() { # <file>
  awk '/^   \*\*Approach critique/ { inb = 1 }
       inb && (/^[0-9]+\. \*\*/ || /^<!-- end of step /) { inb = 0 }
       inb { print }' "$1"
}
BLOCK="$(block_of "$PM")"
FLAT="$(flatten "$BLOCK")"
ok "the critique block is extractable"  "$([ -n "$BLOCK" ] && echo yes || echo no)" yes
in_block() { saw "$FLAT" "$1"; }

echo
echo "== 1. MANDATORY on its trigger — the wording, and the licence to skip, are gone =="
ok "the lead-in says MANDATORY on its trigger" "$(in_block 'MANDATORY on its trigger')" yes
ok "…and the dispatch itself is a must"       "$(in_block 'you **must** dispatch the')" yes
ok "…stated as not a judgement call"          "$(in_block 'not a judgement call, not a budget call')" yes
ok "…and running BEFORE the promotion ask"    "$(in_block 'before the human is asked to')" yes
# The two forms that made it optional, asserted absent FILE-WIDE: rewording the block
# while leaving the old sentence three paragraphs down would leave the licence intact.
ok "the discretionary form is gone"           "$(hasf "$PM" 'you may dispatch the `plan-architect`')" no
ok "the cost-suppressing sentence is gone"     "$(hasf "$PM" "Don't run it on every")" no
ok "…and the 'Optional approach critique' heading with it" \
   "$(hasf "$PM" 'Optional approach critique')" no
# Nothing else shipped may still describe it as optional, or the instruction and the
# documentation disagree about whether the PM has a choice.
# path-scan: absent symlink — retired in #122; the four other roots on this line resolve
stale="$(grep -rlF -- "PM's optional critique" "$REPO/symlink" "$REPO/plugin/seed" "$REPO/docs" \
  "$REPO/README.md" "$REPO/CLAUDE.md" 2>/dev/null | wc -l | tr -d ' ')"
ok "no shipped file still calls the critique optional" "$stale" 0

echo
echo "== 2. the TRIGGER did not move =="
# Word for word what it triggered on before. This is the assertion that keeps the change
# honest: it is about WHEN the critique runs, never about what it may decide.
ok '…still kind: build only'                "$(in_block '**`kind: build`**')" yes
ok "…still multi-file/service"          "$(in_block 'spans multiple files/services')" yes
ok "…still heavily-inferred criteria"   "$(in_block '`acceptance_criteria` had to be heavily inferred')" yes
ok "…and says so explicitly"            "$(in_block 'The trigger itself is unchanged')" yes
ok "…naming WHEN as the thing that changed" "$(in_block 'WHEN the critique runs, never WHAT it may decide')" yes
# The model-routing step keys on the SAME signal, so the two must not drift apart.
# Model routing is step 3's, a different file since ai-bridge-v3/task-024 — the drift this
# guards against is now a cross-file one, which is exactly what it always meant.
ok "model routing names the same signal" \
   "$(hasf "$REPO/plugin/tick-steps/step-3-dispatch.md" 'the same signal that makes the `plan-architect` approach')" yes

echo
echo "== 3. ADVISORY in authority — findings go to advisor_notes and nowhere else =="
ok "findings land in advisor_notes"      "$(in_block '`advisor_notes`')" yes
ok "…only there"                         "$(in_block 'only there: never `open_questions`, never `# Notes`')" yes
ok "…in the field's defined shape"       "$(in_block '<ISO 8601> · <the concern, as a question>')" yes
ok "…triaged on a later tick"            "$(in_block 'triage the list on a later tick')" yes
ok "…never blocking promotion"           "$(in_block 'does not block promotion')" yes
ok "…never a row in AWAITING.md"         "$(in_block 'puts no row in `AWAITING.md`')" yes
ok "…and no validator reads it"          "$(in_block 'no validator reads it')" yes
ok "the critique sets no status"         "$(in_block 'sets no status')" yes
ok "…gates no promotion"                 "$(in_block 'gates no `draft → ready`')" yes
ok "…and is an aid, not a new authority" "$(in_block 'an aid, not a new authority')" yes
ok 'the old # Notes routing is gone'   "$(hasf "$PM" 'its findings in `# Notes`')" no
ok "research tasks stay excluded"        "$(in_block 'on `kind: research` tasks')" yes
ok "SCHEMA still calls the field not a gate" "$(hasf "$SCHEMA" 'DELIBERATELY NOT A GATE')" yes
ok "…and now names the critique as a writer" \
   "$(hasf "$SCHEMA" 'the `plan-architect` approach critique the PM runs at refine time')" yes

echo
echo "== 4. idempotent across ticks, and the marker is NAMED =="
ok "it runs once per task"                "$(in_block 'Once per task')" yes
ok "…and says a tick can tell"            "$(in_block 'a tick can tell that it already ran')" yes
ok "…refusing to lean on refine-once alone" "$(in_block 'do not lean on that alone')" yes
ok "…naming the cost of no marker"        "$(in_block 'a fresh apex-tier session on the same draft')" yes
ok "the receipt is read BEFORE dispatching" "$(in_block 'read BEFORE dispatching')" yes
ok "…concerns ⇒ advisor_notes entries"    "$(in_block 'concerns raised ⇒ one `advisor_notes` entry each')" yes
ok '…none ⇒ an advisor: advisor_notes line' \
   "$(in_block 'none raised ⇒ one `advisor_notes` line')" yes
ok "…and the receipt is NOT sent to answered_questions" \
   "$(in_block 'not `answered_questions`')" yes
ok "…and the check is stated as an instruction" \
   "$(in_block 'means the critique has run: do not dispatch it again')" yes
ok "…while the receipt is not made a gate" "$(in_block 'they are a receipt')" yes

echo
echo "== 5. mandatory-on-trigger is not mandatory-to-EXIST =="
ok "an absent plan-architect is skipped silently" "$(in_block 'skip silently if absent')" yes
# The property, not a phrase nobody would write: nothing in this block may ever park a
# task. A missing optional agent that produced a `blocked` status would be exactly
# mandatory-to-exist wearing a different word.
ok "…and nothing in the block blocks a task"  "$(in_block 'blocked')" no
# Since 2026-10-28 the critic ships in the plugin, so the block dispatches it NAMESPACED
# (a bare name does not resolve) and names no `~/.claude/agents/` path at all.
ok "…the agent is the plugin's, namespaced"   "$(in_block "${PN}:plan-architect")" yes
ok "…and no user-level path is named"        "$(in_block '~/.claude/agents/')" no
ok "…while the plugin ships it"              "$([ -f "$REPO/plugin/agents/plan-architect.md" ] && echo yes || echo no)" yes

echo
echo "== 6. the model comes from roleTiers, and plan-architect stays out of roles =="
ok "the block resolves via resolve-model.sh" "$(in_block 'scripts/resolve-model.sh plan-architect')" yes
ok "…naming the apex tier it resolves through" "$(in_block '(`apex`) through `models`')" yes
ok "…and forbidding a hard-coded alias"      "$(in_block 'never a hard-coded')" yes
ok "…so no raw alias appears in the block"   "$(in_block 'fable')" no
ok '…and it stays out of roles'                      "$(in_block 'stays out of `roles`')" yes

ROLES="$(jq -c '.roles' "$SEED_CFG")"
TIERS="$(jq -c '.roleTiers' "$SEED_CFG")"
in_roles() { jq -e --arg v plan-architect '(index($v)) != null' <<<"$1" >/dev/null && echo yes || echo no; }
ok "seed config: plan-architect is ABSENT from roles" "$(in_roles "$ROLES")" no
ok "seed config: …and present in roleTiers"           \
   "$(jq -e '.["plan-architect"] != null' <<<"$TIERS" >/dev/null && echo yes || echo no)" yes
ok "seed config: …at the apex tier"                   "$(jq -r '.["plan-architect"]' <<<"$TIERS")" apex
ok "seed config: apex is a defined model tier"        \
   "$(jq -e '.models.apex != null' "$SEED_CFG" >/dev/null && echo yes || echo no)" yes
# And the resolver really answers for it, so "resolve it with the script" is not advice
# pointing at a lookup that returns nothing.
RM_OUT="$(cd "$TMP" && cp "$SEED_CFG" instance.config.json && bash "$RESOLVE" plan-architect 2>/dev/null)"
ok "resolve-model.sh answers for plan-architect"      "$RM_OUT" "$(jq -r '.models.apex' "$SEED_CFG")"

echo
echo "== 7. DRIVEN: advisor_notes is not a gate anywhere in the machinery =="
ok "validate-bundle.sh mentions advisor_notes nowhere" \
   "$(grep -cF -- 'advisor_notes' "$VALIDATOR" | tr -d ' ')" 0

# A real bundle: one task carrying advisor notes, one carrying an open question. The
# second is the CONTROL — it proves the fixture is capable of producing an awaiting verb,
# so "advisor notes produce none" is a fact about advisor notes and not about the fixture.
BUNDLE="$TMP/bundle"
mkdir -p "$BUNDLE/objectives" "$BUNDLE/projects/ci/tasks" "$BUNDLE/$AB_DIR"
cp "$SEED_CFG" "$BUNDLE/instance.config.json"
printf '# Schema\n' > "$BUNDLE/$AB_SCHEMA"
: > "$BUNDLE/$AB_SNAPSHOT"
TS="2026-01-01T00:00:00Z"
{ echo '---'; echo 'type: Objective'; echo 'title: Live'; echo 'status: active'
  echo "timestamp: $TS"; echo '---'; echo 'body'; } > "$BUNDLE/objectives/live.md"
{ echo '---'; echo 'type: Project'; echo 'title: CI'; echo 'description: one line'
  echo 'kind: build'; echo 'status: active'; echo 'objective: /objectives/live.md'
  echo "timestamp: $TS"; echo '---'; echo 'body'; } > "$BUNDLE/projects/ci/project.md"
{ echo '---'; echo 'type: Task'; echo 'title: Critiqued draft'; echo 'kind: build'
  echo 'status: draft'; echo 'objective: /objectives/live.md'
  echo 'acceptance_criteria: []'; echo 'open_questions: []'
  echo 'advisor_notes: [ "2026-01-01T00:00:00Z · Should the retry budget be per host?", "2026-01-01T00:00:01Z · Is the migration reversible?" ]'
  echo "timestamp: $TS"; echo '---'; echo 'body'; } > "$BUNDLE/projects/ci/tasks/task-001.md"
{ echo '---'; echo 'type: Task'; echo 'title: Draft with a question'; echo 'kind: build'
  echo 'status: draft'; echo 'objective: /objectives/live.md'
  echo 'acceptance_criteria: []'; echo 'open_questions: [ "Q1: which region?" ]'
  echo "timestamp: $TS"; echo '---'; echo 'body'; } > "$BUNDLE/projects/ci/tasks/task-002.md"

VOUT="$(cd "$BUNDLE" && bash "$VALIDATOR" 2>&1)"; VRC=$?
ok "a task carrying advisor_notes VALIDATES"   "$VRC" 0
ok "…with zero errors"                         "$(saw "$VOUT" '0 errors')" yes
ok "…and the validator says nothing about it"  "$(saw "$VOUT" 'advisor')" no

SOUT="$(cd "$BUNDLE" && bash "$WRITER" --quiet 2>&1)"; SRC=$?
ok "write-snapshot.sh ran"                     "$SRC" 0
ok "…quietly"                                  "$([ -z "$SOUT" ] && echo yes || echo no)" yes
SNAP="$BUNDLE/$AB_SNAPSHOT"
jqt() { jq -r --arg id "$1" '.projects[0].tasks[] | select(.id == $id) | '"$2" "$SNAP"; }
ok "the advisor-note task is counted, 2 notes"  "$(jqt task-001 '.advisor_notes')" 2
ok "…and awaits NOTHING"                        "$(jqt task-001 '.awaiting')" ""
ok "CONTROL: the open-question task awaits"     "$(jqt task-002 '.awaiting')" answer
ok "…so the instance's awaiting count is 1, not 2" "$(jq -r '.counts.awaiting' "$SNAP")" 1
ok "…and no note TEXT reached the snapshot"     "$(saw "$(cat "$SNAP")" 'retry budget')" no

echo
echo "== 8. MUTATIONS — each assertion above is proved capable of going RED =="

# MUTATION A — the discretionary wording comes back. This is the exact revert the change
# guards against: `must` → `may`, plus the cost sentence reinstated.
ANCHOR_A='you **must** dispatch the'
if [ "$(grep -cF -- "$ANCHOR_A" "$PM")" -eq 0 ]; then
  skipped "MUTATION A: the mandatory phrase has moved — the revert is not asserted"
else
  MUT_A="$TMP/pm-discretionary.md"
  sed -e 's/MANDATORY on its trigger/optional (advisory)/' \
      -e 's/you \*\*must\*\* dispatch the/you may dispatch the/' \
      -e "s/On that trigger it runs: not a judgement call, not a budget call./Don't run it on every draft (cost)./" \
      "$PM" > "$MUT_A"
  M_BLOCK="$(flatten "$(block_of "$MUT_A")")"
  ok "MUTATION A: the mutant still has a block"   "$([ -n "$M_BLOCK" ] && echo yes || echo no)" yes
  ok "mutant: MANDATORY is gone"                  "$(saw "$M_BLOCK" 'MANDATORY on its trigger')" no
  ok "mutant: the must is gone"                   "$(saw "$M_BLOCK" 'you **must** dispatch the')" no
  ok "mutant: the cost licence is back"           "$(hasf "$MUT_A" "Don't run it on every")" yes
  ok "CONTROL: the trigger text is untouched"     "$(saw "$M_BLOCK" 'spans multiple files/services')" yes
  ok "CONTROL: the real file is still mandatory"  "$(in_block 'you **must** dispatch the')" yes
fi

# MUTATION B — `plan-architect` added to `roles`, the "fix" SCHEMA.md warns against.
if [ "$(jq -e 'has("roles") and has("roleTiers")' "$SEED_CFG" >/dev/null && echo 1 || echo 0)" -eq 0 ]; then
  skipped "MUTATION B: seed config has no roles/roleTiers pair — the addition is not asserted"
else
  MUT_B="$TMP/config-plan-architect-in-roles.json"
  jq '.roles += ["plan-architect"]' "$SEED_CFG" > "$MUT_B"
  M_ROLES="$(jq -c '.roles' "$MUT_B")"
  ok "MUTATION B: the mutant is still valid JSON" "$(jq -e . "$MUT_B" >/dev/null && echo yes || echo no)" yes
  ok "mutant: plan-architect is now IN roles"     "$(in_roles "$M_ROLES")" yes
  ok "…so the absence assertion goes red"         "$([ "$(in_roles "$M_ROLES")" = no ] && echo yes || echo no)" no
  ok "CONTROL: roleTiers is untouched"            "$(jq -r '.roleTiers["plan-architect"]' "$MUT_B")" apex
  ok "CONTROL: the shipped config still omits it" "$(in_roles "$ROLES")" no
fi

# MUTATION C — the idempotence receipt deleted. Mandatory with no marker is the
# re-dispatch-every-tick failure, and it must not pass silently.
ANCHOR_C='Once per task'
if [ "$(grep -cF -- "$ANCHOR_C" "$PM")" -eq 0 ]; then
  skipped "MUTATION C: the idempotence lead-in has moved — its deletion is not asserted"
else
  MUT_C="$TMP/pm-no-receipt.md"
  awk '/^   \*\*Once per task/ { drop = 1 } drop && /^   \*\*Its model comes from/ { drop = 0 } !drop { print }' \
    "$PM" > "$MUT_C"
  C_BLOCK="$(flatten "$(block_of "$MUT_C")")"
  ok "MUTATION C removed something" \
     "$([ "$(wc -c < "$MUT_C")" -lt "$(wc -c < "$PM")" ] && echo yes || echo no)" yes
  ok "mutant: the receipt is gone"               "$(saw "$C_BLOCK" 'do not dispatch it again')" no
  ok "mutant: …and so is the once-per-task rule" "$(saw "$C_BLOCK" 'Once per task')" no
  ok "CONTROL: the advisor_notes routing survives" "$(saw "$C_BLOCK" 'only there: never `open_questions`')" yes
  ok "CONTROL: the mandatory form survives"        "$(saw "$C_BLOCK" 'you **must** dispatch the')" yes
fi

# MUTATION D — the authority clause deleted. The half that must NOT change, proved
# breakable too: an edit that hands the critique a gate has to fail something.
ANCHOR_D='not a new authority'
if [ "$(grep -cF -- "$ANCHOR_D" "$PM")" -eq 0 ]; then
  skipped "MUTATION D: the authority clause has moved — its deletion is not asserted"
else
  MUT_D="$TMP/pm-gated.md"
  sed -e 's/an aid,/a gate,/' -e 's/sets no status/sets the status/' "$PM" > "$MUT_D"
  D_BLOCK="$(flatten "$(block_of "$MUT_D")")"
  ok "mutant: 'not a new authority' no longer reads that way" \
     "$(saw "$D_BLOCK" 'an aid, not a new authority')" no
  ok "mutant: the no-status promise is gone"     "$(saw "$D_BLOCK" 'sets no status')" no
  ok "CONTROL: the trigger is untouched"         "$(saw "$D_BLOCK" 'spans multiple files/services')" yes
fi

echo
printf 'pass=%d fail=%d skip=%d\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
