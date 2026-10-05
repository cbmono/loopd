#!/usr/bin/env bash
#
# reviewer-fallback-spend.test.sh — an unavailable external reviewer is FOUR conditions,
# and only one of them may spend a deep-tier `qa-reviewer` session.
#
# WHY THIS EXISTS, WITH THE MEASUREMENT. Both surfaces that route around an unavailable
# reviewer used to treat every failure as one condition and fall through to `qa-reviewer`
# automatically. On 2026-08-31 the reviewer was rate-limited on four pull requests
# (#85-#88) and reviewed all four properly within the hour; under an automatic fallback the
# panel would have bought four deep-tier sessions for nothing. The rule that fixes it is
# one sentence — **the loop never needs permission to WAIT, it needs permission to SPEND** —
# and it is worth exactly nothing as prose, because the collapse back to "no reviewer ⇒
# dispatch the fallback" is one deleted paragraph and reads perfectly afterwards.
#
# THE ASSERTIONS ARE PER FILE, WHICH IS THE WHOLE POINT OF SECTION 5. The task's criterion 1
# fails a one-surface change, so a single mutation set would let the OTHER file collapse
# back to auto-fallback in silence. There are therefore two independent mutants — one per
# instruction file — and each one's CONTROL is the other file's markers, still green. That
# pairing is what proves the two sets are not accidentally the same assertions twice.
#
# WHAT IS DRIVEN RATHER THAN READ. The classifier itself is not asserted here — exit 1 vs
# exit 5 is driven end-to-end against real bodies in tests/review-clearance.test.sh, which
# owns the `gh` stub (tests/review-clearance.lib.sh, shared with its two sibling harnesses).
# What this file adds is the half that file cannot see: that the READERS of those codes
# route them differently, and that no caller silently mis-reads the new one (section 4,
# paired with a mutant in 6c).
#
# EVERY MUTATION IS GUARDED. A mutation whose anchor has moved prints SKIP and is never
# counted as caught: a check that has silently stopped checking is worse than no check.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
PM="$REPO/plugin/tick-steps/step-4-advance.md"
NP="$REPO/plugin/skills/new-project/SKILL.md"
AUT="$REPO/plugin-yolo/companion/AUTONOMY.md"
CLEAR="$REPO/plugin/scripts/review-clearance.sh"
ROUNDS="$REPO/plugin/scripts/review-rounds.sh"
REQ="$REPO/plugin/scripts/required-checks.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/fallback-spend.XXXXXX")" || {
  echo "reviewer-fallback-spend.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0; skip=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
skipped() { printf '  SKIP  %s\n' "$1"; skip=$((skip+1)); }

# `grep -c`, never `printf … | grep -q`: under `set -o pipefail` a `-q` exits at the first
# match and the writer's EPIPE becomes the pipeline's status, so the assertion inverts
# exactly when it is true. (Same reasoning as tests/approach-critique-trigger.test.sh.)
saw() { # <haystack> <fixed string> -> yes|no
  [ "$(printf '%s\n' "$1" | grep -cF -- "$2")" -gt 0 ] && echo yes || echo no
}
hasf() { # <file> <fixed string> -> yes|no
  [ "$(grep -cF -- "$2" "$1")" -gt 0 ] && echo yes || echo no
}
# Instruction prose is hard-wrapped, so every sentence-level needle below is matched
# against a FLATTENED copy. Grepping the raw file for a phrase that happens to straddle a
# line break fails while the rule is perfectly intact — a false red nobody trusts twice.
flat_of() { tr '\n' ' ' < "$1" | tr -s ' '; }

echo "== the files exist at all (or every assertion below is vacuous) =="
for f in "$PM" "$NP" "$AUT" "$CLEAR" "$ROUNDS" "$REQ"; do
  ok "$(basename "$f") exists" "$([ -f "$f" ] && echo yes || echo no)" yes
done

PM_FLAT="$(flat_of "$PM")"
NP_FLAT="$(flat_of "$NP")"
AUT_FLAT="$(flat_of "$AUT")"

# ============================================ 1. the PM tick: hold on 1, ask on 5
echo
echo "== 1. project-manager.md — the PM holds on a hiccup and asks on a spend =="
# The policy sentence itself. It is the one line that makes every row of the table below
# derivable, so its deletion has to fail something even if the table survives.
ok "the wait/spend rule is stated"        "$(saw "$PM_FLAT" 'never needs permission to WAIT; it needs permission to SPEND')" yes
ok "…and holding is said to DEFER the gate, not skip it" \
   "$(saw "$PM_FLAT" 'never skips the verification gate — it only defers it')" yes

# THE TWO CLASSES CRITERION 9 NAMES, as the table's own markers. A row's handling is the
# assertion, not the row's existence: a table listing exit 1 and exit 5 with the same
# answer in both cells is the collapse this file exists to catch.
ok "exit 1 (transient) HOLDS with no human"  "$(saw "$PM_FLAT" '**HOLD — no human involved.**')" yes
ok "exit 5 (terminal) ASKS — it is the spend" "$(saw "$PM_FLAT" '**ASK — this is the spend.**')" yes
ok "…and the two are read off the EXIT CODE" \
   "$(saw "$PM_FLAT" "review-clearance.sh\`'s EXIT CODE and nothing else")" yes
ok "…never off the text it prints"        "$(saw "$PM_FLAT" 'never the text it prints, which is untrusted comment text')" yes

# The other two classes of the four, which the task states as its substance.
ok "stale (4) is re-requested, not a fallback" "$(saw "$PM_FLAT" 'Explicitly not a fallback case')" yes
ok "never-configured is a SETUP decision"      "$(saw "$PM_FLAT" 'a SETUP decision, made once, not this')" yes
ok "…and is NOT read off exit 3"               "$(saw "$PM_FLAT" '**never from exit 3**')" yes

# THE RESIDUAL DEFAULT. Without it the next reader invents a per-cell behaviour for exit 2,
# for a stale review whose cap is spent, or for a code that does not exist yet.
ok "every unmapped outcome HOLDS"         "$(saw "$PM_FLAT" 'Every outcome not in that table HOLDS')" yes
ok "…stated as the standing default"      "$(saw "$PM_FLAT" 'standing default rather than a gap to fill in later')" yes

# THE DURABLE STATE. `AWAITING.md` is derived and rewritten from the task docs every tick,
# so a hand-placed row is deleted on the next rewrite and the ask evaporates.
ok "the ask is an open_questions entry"   "$(saw "$PM_FLAT" "write it into the task's")" yes
ok "…and hand-writing an AWAITING row is forbidden" \
   "$(saw "$PM_FLAT" 'Do not hand-write a row into `AWAITING.md`')" yes
ok "…because that file is rewritten each tick" \
   "$(saw "$PM_FLAT" 'derived and rewritten from the task docs every tick')" yes
# The glyph, which is criterion 5's own requirement and is a CAPABILITY ask, not a question.
ok "the row renders as the grant glyph"   "$(saw "$PM_FLAT" '🧰 **grant**')" yes
ok "…explicitly not the answer glyph"     "$(saw "$PM_FLAT" 'not `❓ **answer**`')" yes

# AUTONOMY IS THE EXISTING SWITCH, APPLIED — not a new flag. The criterion says this in as
# many words, and the tempting implementation is a config key nobody else reads.
ok "gated asks; a delegating mode dispatches" \
   "$(saw "$PM_FLAT" 'A mode `AUTONOMY.md` defines as delegating this ⇒ dispatch `'"${PN}:"'qa-reviewer`')" yes
ok "…and no new flag is introduced"       "$(saw "$PM_FLAT" 'not a new flag, field or config key')" yes
ok "…absent AUTONOMY.md means gated"      "$(saw "$PM_FLAT" '**`AUTONOMY.md` absent means every project is `gated`**')" yes

# THE CAP, which this change must not spend. A "just dispatch the fallback" branch that
# skipped review-rounds.sh would create the third round CONVENTIONS.md forbids.
ok "the cap is counted before the spend"  "$(saw "$PM_FLAT" 'count with `${CLAUDE_PLUGIN_ROOT}/scripts/review-rounds.sh` **before** dispatching')" yes
ok "…and nothing here creates a third round" "$(saw "$PM_FLAT" 'Nothing here creates a third')" yes

# ============================================ 2. the scaffold surface: same policy, one-shot
echo
echo "== 2. new-project.md step 8 — the same policy where nothing ever retries =="
ok "the ask fires on the spend"           "$(saw "$NP_FLAT" 'the ask fires on the SPEND, never on the hiccup')" yes
# The two classes, distinguished where the answer is knowable — at reviewer resolution.
ok "resolution splits the two classes"    "$(saw "$NP_FLAT" '**none configured**')" yes
ok "…and says so is not one condition"    "$(saw "$NP_FLAT" '"No usable reviewer" is NOT one condition')" yes
ok "none configured ⇒ dispatch, no ask"   "$(saw "$NP_FLAT" '**None configured ⇒ dispatch it, no ask.**')" yes
ok "configured but refusing ⇒ ASK"        "$(saw "$NP_FLAT" '**Configured but refusing ⇒ ASK, in this session')" yes
ok "…in the MAIN THREAD, unlike the tick" "$(saw "$NP_FLAT" 'main thread and the human is right here')" yes
ok "…and yolo dispatches automatically"   "$(saw "$NP_FLAT" 'defines as delegating this is in force ⇒ dispatch it')" yes

# THE HALF THAT IS ONLY TRUE HERE. A PM tick may hold because a later tick re-asks; step 8
# is one-shot, so "hold" means the advisory review silently never happens. The fix is not
# to hold — it is to RECORD.
ok "the step is named ONE-SHOT"           "$(saw "$NP_FLAT" 'this step is ONE-SHOT and nothing re-runs it')" yes
ok "…and holding is ruled out by name"    "$(saw "$NP_FLAT" "does not exist here")" yes
ok "an unrun review is RECORDED in log.md" "$(saw "$NP_FLAT" 'the scaffold got no second')" yes
ok "…and never silent"                    "$(saw "$NP_FLAT" 'an unrun advisory review nobody knows about is not')" yes

# ================================================ 3. AUTONOMY.md is where the mode is defined
echo
echo "== 3. AUTONOMY.md defines the delegation, because it says it is the only file that does =="
ok "the yolo table carries the spend row"  "$(saw "$AUT_FLAT" 'Spend the `qa-reviewer` fallback')" yes
ok "…anchored on exit 5, a machine signal" "$(saw "$AUT_FLAT" 'exit **5**')" yes
ok "…and gated still asks first"           "$(saw "$AUT_FLAT" '| Ask first | The loop may dispatch it without asking |')" yes
ok "the section it points at exists"       "$(hasf "$AUT" '## Spending the fallback reviewer under `yolo`')" yes
# CRITERION 6, on the file that would be the one to break it: delegating the SPEND must not
# delegate the GATE. A verdict is still required; only its author changes.
ok "what is delegated is WHO, never WHETHER" "$(saw "$AUT_FLAT" 'delegated is WHO reviews, never WHETHER anybody does')" yes
ok "exit 1 is not this decision, in either mode" "$(saw "$AUT_FLAT" '**Exit 1 is NOT this decision, in either mode.**')" yes
ok "…and the two-round cap is untouched"   "$(saw "$AUT_FLAT" 'The two-round cap is untouched')" yes

# ========================================= 4. no caller silently mis-reads the new code
echo
echo "== 4. the new exit code has readers, and they were all updated =="
# The header table is the contract every caller reads instead of the script's body.
ok "review-clearance.sh documents exit 5"  "$(hasf "$CLEAR" 'the refusal is TERMINAL')" yes
ok "…and exit 1 as the transient half"     "$(hasf "$CLEAR" 'the refusal is TRANSIENT')" yes
ok "…and keeps the do-not-parse rule"      "$(hasf "$CLEAR" 'Do not parse the quote.')" yes
# Matched on one line rather than flattened: `flat_of` keeps the `#` that opens each
# comment line, so a needle spanning two lines of a SHELL file carries a stray `#` and
# never matches. (The instruction files above have no such prefix, which is why they are
# flattened and this is not.)
ok "…stating callers read only the code"   "$(hasf "$CLEAR" 'THAT RULE IS UNCHANGED BY THE 1/5 SPLIT')" yes
# review-rounds.sh is the caller a missing code would BREAK rather than merely confuse: its
# `*` arm is fatal, so an unlisted 5 turns a broken reviewer into "the round count is
# unknown" on every PR. Both of its case lists, not one.
ok "review-rounds.sh accepts 5 as a refusal" \
   "$(grep -cE '^[[:space:]]*1\|3\|4\|5\|8\)' "$ROUNDS")" 2
ok "…and no stale 1|3|4 arm survives"      "$(grep -cE '^[[:space:]]*1\|3\|4\)' "$ROUNDS")" 0
# required-checks.sh already refuses on any non-zero, so the risk there is silence, not
# breakage: a human reading "the reviewer did not clear" needs to know it is broken, not busy.
ok "required-checks.sh names the terminal case" "$(hasf "$REQ" 'This refusal is TERMINAL')" yes
ok "…and says a re-run will not change it"      "$(hasf "$REQ" 'will not change it')" yes

# The classifier's own two directions are driven by its --self-test, which every caller
# runs before believing anything it says — so this is a real execution, not a grep.
st="$("$CLEAR" --self-test 2>&1)"; st_rc=$?
ok "review-clearance.sh --self-test passes" "$st_rc" 0
ok "…printing its agreed sentinel"          "$st" "review-clearance: self-test ok"

# ================================================= 5. THE MUTANTS, one per instruction file
echo
echo "== 5. collapsing either file back to auto-fallback goes RED =="

# --- MUTATION A: project-manager.md loses the classification -------------------
# The collapse, exactly as it would arrive: the two new bullets deleted, leaving the
# unconditional "dispatch the qa-reviewer" that was there before. Prose-perfect, and the
# reason a reviewer would not catch it by reading.
ANCHOR_A='- **A refusal is FIVE classes'
if [ "$(grep -cF -- "$ANCHOR_A" "$PM")" -ne 1 ]; then
  skipped "MUTATION A: the PM classification lead-in has moved — its deletion is not asserted"
else
  MUT_A="$TMP/pm-collapsed.md"
  awk '/^   - \*\*A refusal is FIVE classes/ { drop = 1 }
       drop && /^   - \*\*Fallback when none is configured/ { drop = 0 }
       !drop { print }' "$PM" > "$MUT_A"
  A_FLAT="$(flat_of "$MUT_A")"
  ok "MUTATION A removed something" \
     "$([ "$(wc -c < "$MUT_A")" -lt "$(wc -c < "$PM")" ] && echo yes || echo no)" yes
  ok "mutant: the wait/spend rule is gone"  "$(saw "$A_FLAT" 'never needs permission to WAIT; it needs permission to SPEND')" no
  ok "mutant: the HOLD class is gone"       "$(saw "$A_FLAT" '**HOLD — no human involved.**')" no
  ok "mutant: the ASK class is gone"        "$(saw "$A_FLAT" '**ASK — this is the spend.**')" no
  ok "mutant: the residual default is gone" "$(saw "$A_FLAT" 'Every outcome not in that table HOLDS')" no
  # The ask's DURABLE STATE, not the glyph itself: `🧰 **grant**` also appears in this
  # file's `AWAITING.md` layout hundreds of lines away, so a glyph-presence assertion would
  # survive the collapse and read as a pass. Anchor on the sentence that only the routing
  # block carries.
  ok "mutant: the durable-state rule is gone" "$(saw "$A_FLAT" 'Do not hand-write a row into `AWAITING.md`')" no
  # CONTROLS. The first is what makes the mutant a COLLAPSE and not a deletion of the whole
  # step; the second and third are the per-file independence criterion 9 turns on.
  ok "CONTROL: the fallback dispatch survives" "$(saw "$A_FLAT" 'Dispatch the `qa-reviewer` (its')" yes
  ok "CONTROL: the two-round cap bullet survives" "$(saw "$A_FLAT" 'TWO ROUNDS, THEN THE HUMAN DECIDES')" yes
  ok "CONTROL: new-project.md is UNAFFECTED"   "$(saw "$NP_FLAT" '**None configured ⇒ dispatch it, no ask.**')" yes
  ok "CONTROL: …and so is AUTONOMY.md"         "$(saw "$AUT_FLAT" 'Spend the `qa-reviewer` fallback')" yes
  ok "CONTROL: the real PM file still classifies" "$(saw "$PM_FLAT" '**ASK — this is the spend.**')" yes
fi

# --- MUTATION B: new-project.md loses it, and ONLY new-project.md --------------
# The mutant criterion 9 exists for. A mutation set on the PM alone would pass this file
# while step 8 quietly went back to dispatching the fallback on any hiccup.
ANCHOR_B='**None configured ⇒ dispatch it, no ask.**'
ANCHOR_B_END='   When it does run, brief it with'
if [ "$(grep -cF -- "$ANCHOR_B" "$NP")" -ne 1 ] || [ "$(grep -cF -- "$ANCHOR_B_END" "$NP")" -ne 1 ]; then
  skipped "MUTATION B: the scaffold class split has moved — its deletion is not asserted"
else
  MUT_B="$TMP/np-collapsed.md"
  awk '/^   \* \*\*None configured ⇒ dispatch it, no ask\.\*\*/ { drop = 1 }
       drop && /^   When it does run, brief it with/ { drop = 0 }
       !drop { print }' "$NP" > "$MUT_B"
  B_FLAT="$(flat_of "$MUT_B")"
  ok "MUTATION B removed something" \
     "$([ "$(wc -c < "$MUT_B")" -lt "$(wc -c < "$NP")" ] && echo yes || echo no)" yes
  ok "mutant: the no-ask/ask split is gone"  "$(saw "$B_FLAT" '**None configured ⇒ dispatch it, no ask.**')" no
  ok "mutant: the in-session ask is gone"    "$(saw "$B_FLAT" '**Configured but refusing ⇒ ASK, in this session')" no
  ok "mutant: the ONE-SHOT record rule is gone" "$(saw "$B_FLAT" 'this step is ONE-SHOT and nothing re-runs it')" no
  ok "mutant: the unrun-review record is gone"  "$(saw "$B_FLAT" 'the scaffold got no second')" no
  # CONTROLS, mirroring MUTATION A's.
  ok "CONTROL: the mode-C dispatch survives"  "$(saw "$B_FLAT" 'ask for **mode C**')" yes
  ok "CONTROL: project-manager.md is UNAFFECTED" "$(saw "$PM_FLAT" '**HOLD — no human involved.**')" yes
  ok "CONTROL: …and so is AUTONOMY.md"           "$(saw "$AUT_FLAT" 'exit **5**')" yes
  ok "CONTROL: the real NP file still splits"    "$(saw "$NP_FLAT" '**Configured but refusing ⇒ ASK, in this session')" yes
fi

# ================================================== 6. non-vacuity: the matchers can fail
echo
echo "== 6. the matchers bite =="
# 6a. flat_of must join a hard-wrapped sentence, or every needle above is testing the
# wrapping rather than the rule. Driven both ways: joined matches, unjoined does not.
WRAP="$TMP/wrapped.md"
printf 'the ask fires on the SPEND,\nnever on the hiccup.\n' > "$WRAP"
ok "flat_of joins a wrapped sentence"     "$(saw "$(flat_of "$WRAP")" 'the ask fires on the SPEND, never on the hiccup')" yes
ok "…and the raw file does NOT match it"  "$(hasf "$WRAP" 'the ask fires on the SPEND, never on the hiccup')" no

# 6b. saw() rejects absent text rather than always answering yes — the failure that would
# make every `yes` above meaningless.
ok "saw() rejects text that is not there" "$(saw "$PM_FLAT" 'dispatch the fallback on any refusal')" no

# 6c. THE CALLER MUTANT. Section 4's `1|3|4|5` count is only a check if the old form fails
# it, so the pre-change arm is reconstructed and measured.
MUT_C="$TMP/rounds-old.sh"
sed -e 's/^\([[:space:]]*\)1|3|4|5|8)/\11|3|4)/' "$ROUNDS" > "$MUT_C"
ok "MUTATION C: the old arm is restored"  "$(grep -cE '^[[:space:]]*1\|3\|4\)' "$MUT_C")" 2
ok "…and the new-arm count goes to zero"  "$(grep -cE '^[[:space:]]*1\|3\|4\|5\|8\)' "$MUT_C")" 0
ok "CONTROL: the shipped file is unchanged" "$(grep -cE '^[[:space:]]*1\|3\|4\|5\|8\)' "$ROUNDS")" 2

# 6d. the block extractors must actually extract. An awk range that matched nothing would
# make both mutants byte-identical to their sources, and every `no` above would be a lie —
# which is exactly what "MUTATION x removed something" guards, driven here in reverse.
NOOP="$TMP/noop.md"
awk '/^   - \*\*A marker that is not in this file/ { drop = 1 } !drop { print }' "$PM" > "$NOOP"
ok "a non-matching range removes nothing" \
   "$([ "$(wc -c < "$NOOP")" -eq "$(wc -c < "$PM")" ] && echo yes || echo no)" yes

# 6e. the mutation GUARDS themselves, driven rather than trusted. Each is
# `grep -cF <anchor> … -ne 1`, and a guard that never fires would let a moved anchor be
# silently counted as caught — the one failure mode a SKIP line exists to make visible.
: > "$TMP/no-anchor.md"
ok "a moved anchor counts zero (⇒ SKIP)"  "$(grep -cF -- "$ANCHOR_A" "$TMP/no-anchor.md")" 0
ok "…and the shipped PM counts exactly one" "$(grep -cF -- "$ANCHOR_A" "$PM")" 1
ok "…and the shipped NP counts exactly one" "$(grep -cF -- "$ANCHOR_B" "$NP")" 1
# The END anchor is guarded too: an unmatched one makes the awk range run to EOF, which
# eats the rest of step 8 and turns every `no` in MUTATION B into a vacuous pass. It was a
# live failure once — the control below is what caught it.
ok "…and NP's mutation END anchor is unique" "$(grep -cF -- "$ANCHOR_B_END" "$NP")" 1

# NOT PAIRED, stated rather than implied: the plain `hasf` presence greps in section 4 have
# no fixture — they fail on absent text by construction, so a fixture would only re-test
# `grep`. The classifier's own exit-1-vs-exit-5 behaviour is driven end-to-end in
# tests/review-clearance.test.sh (section "shape 2c"), which is its right home.

echo
printf 'pass=%d fail=%d skip=%d\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
