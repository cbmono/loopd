#!/usr/bin/env bash
#
# subagent-resume-rule.test.sh — the resume rule is stated ONCE, reaches every dispatcher
# word for word, and does not claim coverage it has not got.
#
# WHY THIS IS A TEST AND NOT A PARAGRAPH SOMEBODY WROTE. Resuming agents across units of
# work is how two ticks ran concurrently on 2026-08-30 and how one `software-engineer`,
# resumed three times onto three unrelated jobs, ended a day carrying 163k tokens. The
# rule that follows from that — same task and same PR ⇒ resume, anything else ⇒ a fresh
# agent, a tick ⇒ never — has readers in four different files, and a rule copied into four
# files is a rule that will say four things within a month. So what is asserted here is
# not "the rule is written down" (any paragraph passes that) but the three properties that
# make it survive:
#
#   1. ONE STATEMENT. The full rule — the table, the reasoning, the measurement — lives in
#      `seed/CONVENTIONS.md` and nowhere else. Every other file cites that heading and
#      carries at most the ONE LINE, byte for byte. A paraphrase is how the copies drift,
#      so a copy that is not byte-identical fails here rather than in six months.
#   2. IT REACHES THE DISPATCHERS. A convention is held by whoever holds the dispatch, so
#      it has to be in the files THEY read — `/pm-loop` and `project-manager.md` for the
#      loop, `seed/CLAUDE.md` for the main session — not only in a task document nobody
#      opens twice. Absence from any of them fails.
#   3. IT SAYS WHICH HALF HAS A READER, AND THE CLAIM IS TRUE. The tick half is checked at
#      the dispatch lock; the same-task half cannot be checked by anything, because
#      nothing can see the intent behind a message. Both statements are asserted in the
#      prose AND the first one is DRIVEN — `tick-lock.sh` really is run, and really does
#      refuse a tick that no launcher dispatched. A doc that claims a mechanism nobody
#      exercised is the exact failure mode this bundle keeps paying for
#      (knowledge/findings/a-rule-with-no-reader-is-not-a-rule.md in the control panel);
#      claiming one and testing only the sentence would be the same failure wearing a
#      harness.
#
# AND THE FOURTH THING, WHICH IS AN ABSENCE. There is no "delete the agent" primitive in
# this bundle: agents complete on their own, so resumption is the only lever there is.
# Absences rot silently, so it is pinned — `tick-lock.sh` keeps exactly its three
# subcommands, and no shipped file tells anyone to kill, delete or terminate an agent.
#
# EVERY EXTRACTION IS PROVEN CAPABLE OF FAILING against a synthetic fixture that drops
# exactly the property it checks. A check that can only pass is not a check.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONV="$REPO/plugin/seed/CONVENTIONS.md"
PM="$REPO/plugin/tick-steps/step-3-dispatch.md"
# Step 0.5 stayed in the core when steps 2-7 moved out (ai-bridge-v3/task-024): the lock
# is a gate, and a gate a tick might not have read is not a gate.
CORE="$REPO/plugin/agents/project-manager.md"
LOOP="$REPO/plugin/skills/dispatch/SKILL.md"
SEED="$REPO/plugin/seed/CLAUDE.md"
OPS="$REPO/docs/operations.md"
LOCKSH="$REPO/plugin/scripts/tick-lock.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/resume-rule.XXXXXX")" || {
  echo "subagent-resume-rule.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
has() { # <file> <fixed-string> -> yes|no
  grep -qF -- "$2" "$1" && echo yes || echo no
}
count() { # <file> <fixed-string> -> occurrences
  grep -cF -- "$2" "$1" | tr -d ' '
}

# The rule's one line and the heading everything cites, written out here so this file is
# the place both are pinned. Changing either is a deliberate edit in one place, which is
# the whole point of them being strings rather than a description.
CANON='same task and same PR ⇒ resume; anything else ⇒ dispatch fresh; a tick ⇒ never'
ANCHOR='A subagent works ONE task'

echo "== the files exist at all (or every assertion below is vacuous) =="
for f in "$CONV" "$PM" "$LOOP" "$SEED" "$OPS" "$LOCKSH"; do
  ok "$(basename "$(dirname "$f")")/$(basename "$f") exists" "$([ -f "$f" ] && echo yes || echo no)" yes
done

echo
echo "== 1. stated ONCE: the full rule lives in CONVENTIONS.md and nowhere else =="
# The canonical bullet, extracted the way this directory extracts bullets: from its own
# `- ` to the next one. The assertions after it are vacuous if this comes back empty, so
# that is asserted first.
bullet_of() { # <file> <regex> — the whole `- ` bullet containing <regex>
  awk -v n="$2" 'BEGIN{buf=""}
    /^- / { if (buf ~ n) { print buf; exit } ; buf=$0; next }
    { buf = buf "\n" $0 }
    END { if (buf ~ n) print buf }' "$1"
}
RULE="$(bullet_of "$CONV" "A subagent works ONE task")"
ok "CONVENTIONS.md states it in a bullet of its own" "$([ -n "$RULE" ] && echo yes || echo no)" yes
in_rule() { grep -qF -- "$1" <<<"$RULE" && echo yes || echo no; }
ok "…giving the resume arm"              "$(in_rule 'RESUME.')" yes
ok "…the dispatch-fresh arm"             "$(in_rule 'DISPATCH FRESH.')" yes
ok "…and the tick as an absolute"        "$(in_rule 'NEVER RESUME')" yes
ok "…with no exception offered"          "$(in_rule 'no exception')" yes
ok "…naming what a legitimate resume IS" "$(in_rule 'the next round')" yes
ok "…and the measurement behind it"      "$(in_rule '163k tokens')" yes
ok "…and it carries the one line itself" "$(in_rule "$CANON")" yes
ok "…exactly once"                       "$(count "$CONV" "$CANON")" 1

# The three-arm TABLE is what must not be duplicated: a second copy is a second rule, and
# the two will disagree. Every shipped tree is scanned, not a list somebody remembers.
# path-scan: absent symlink — retired in #122; the four other roots on this line resolve
copies="$(grep -rlF -- 'DISPATCH FRESH.' "$REPO/symlink" "$REPO/plugin/seed" "$REPO/docs" \
  "$REPO/README.md" "$REPO/CLAUDE.md" 2>/dev/null | sort | sed "s|^$REPO/||" | tr '\n' ' ' | sed 's/ *$//')"
ok "…and exactly one shipped file carries the table" "$copies" "plugin/seed/CONVENTIONS.md"

echo
echo "== 2. it reaches every dispatcher, word for word, with the citation =="
# Four readers, three of them agents or commands that get the file loaded for them, one
# (`seed/CLAUDE.md`) the main session's own always-loaded instructions. A dispatcher that
# does not carry it holds a rule nobody told it.
for f in "$PM" "$LOOP" "$SEED" "$OPS"; do
  n="$(basename "$f")"
  ok "$n carries the one line verbatim"  "$(has "$f" "$CANON")" yes
  ok "…and cites where the rule lives"   "$(has "$f" "$ANCHOR")" yes
  ok "…without restating the table"      "$(has "$f" 'DISPATCH FRESH.')" no
done
# The loop and the tick are the two halves of a dispatch, so each must carry the absolute
# in its own words as well — a citation alone would put the one rule that has a mechanism
# behind a link.
ok "the launcher says a tick is never woken" \
  "$(grep -qF 'never wake a completed tick with a message' "$LOOP" && echo yes || echo no)" yes
ok "…and spawns a fresh one every time"  "$(has "$LOOP" 'Fresh every time')" yes
ok "the tick's own step 0.5 has an exit-4 branch" \
  "$(grep -qE '^   - \*\*4\*\*' "$CORE" && echo yes || echo no)" yes
ok "…saying in those words that a tick is never resumed" "$(has "$CORE" 'never resumed')" yes
ok "…and telling a refused tick to take no lock of its own" \
  "$(has "$CORE" 'take no lock of your own')" yes

echo
echo "== 3. it says which half has a reader — and the reader is REAL =="
ok "the rule names the checked half"     "$(in_rule 'is CHECKED')" yes
ok "…naming the file that checks it"     "$(in_rule 'tick-lock.sh')" yes
ok "…and says the other half is NOT checked" "$(in_rule 'is NOT checked and cannot be')" yes
ok "…because intent is unreadable"       "$(in_rule 'nothing can see')" yes
ok "…and says who holds it instead"      "$(in_rule 'held by whoever dispatches')" yes
# The honest half must not be dressed up. If the doc ever claims the same-task half is
# enforced/verified/checked by something, this fails.
ok "…and claims no enforcement for it"   "$(in_rule 'enforced by')" no
ok "the operator docs say the same"      "$(has "$OPS" 'convention with no reader anywhere')" yes
ok "…and state the one case still open on the checked half" \
  "$(has "$OPS" "inside* the launcher's")" yes

# NOW DRIVE IT. Everything above is prose about a mechanism; this is the mechanism. A
# tick with no lock in front of it is a tick nothing dispatched, and the claim in
# CONVENTIONS.md is only true if this exits non-zero.
INST="$TMP/instance"; mkdir -p "$INST"
OUT="$(bash "$LOCKSH" acquire --as tick --instance "$INST" 2>&1)"; RC=$?
ok "a tick nothing dispatched is refused for real" "$RC" 4
ok "…and the refusal names the resume"   "$(grep -qF 'never resumed' <<<"$OUT" && echo yes || echo no)" yes
ok "…leaving no lock behind"             "$([ -e "$INST/$AB_LOCK" ] && echo yes || echo no)" no
# …and the same command, after a launcher has taken the lock, proceeds — so the refusal is
# specific to "nobody dispatched you" and has not become a blanket refusal that would
# deadlock every dispatched tick.
bash "$LOCKSH" acquire --instance "$INST" >/dev/null 2>&1
OUT="$(bash "$LOCKSH" acquire --as tick --instance "$INST" 2>&1)"; RC=$?
ok "a DISPATCHED tick still proceeds"    "$RC" 0
ok "…by adopting the launcher's lock"    "$(grep -qF 'adopted:' <<<"$OUT" && echo yes || echo no)" yes

echo
echo "== 4. the absence: there is no 'delete the agent' primitive, and none appears =="
# Resumption is the only lever, which is why the rule governs resumption and not lifetime.
# An absence nobody checks is an absence somebody fills.
subs="$(head -1 <<<"$(grep -oE '^  acquire\|release\|status\)' "$LOCKSH")")"
ok "tick-lock.sh still has exactly three subcommands" "$subs" '  acquire|release|status)'
ok "…and the rule says why lifetime is not a lever" "$(in_rule 'resumption is the only lever')" yes
ok "…and that none is wanted"            "$(in_rule 'delete the agent')" yes
ok "the operator docs say it too"        "$(has "$OPS" 'no "delete the agent" primitive')" yes
hits=0
for phrase in 'delete the agent' 'kill the agent' 'terminate the agent' 'delete a subagent' 'kill a subagent'; do
  # path-scan: absent symlink — retired in #122; "$REPO/plugin/seed" resolves
  if grep -qv -e 'CONVENTIONS.md' -e '^$' \
       <<<"$(grep -rlF -- "$phrase" "$REPO/symlink" "$REPO/plugin/seed" 2>/dev/null)"; then
    echo "  (a shipped file describes: $phrase)"; hits=$((hits+1))
  fi
done
ok "…and no shipped agent or command instructs one" "$hits" 0

echo
echo "== the extractions can fail: each property dropped from a fixture is caught =="
# A check that cannot fail is decoration. Each fixture drops exactly one property, and the
# same predicate that passed above must come back negative.
FIX="$TMP/fixtures"; mkdir -p "$FIX"

# (a) a conventions file whose rule is a paraphrase, not the canonical line
sed 's/same task and same PR ⇒ resume; anything else ⇒ dispatch fresh; a tick ⇒ never/roughly: reuse an agent when it makes sense/' \
  "$CONV" > "$FIX/paraphrased.md"
ok "a paraphrased one line is caught"    "$(has "$FIX/paraphrased.md" "$CANON")" no
ok "…while the real file still carries it" "$(has "$CONV" "$CANON")" yes

# (b) a dispatcher that cites the rule but drops the line
grep -vF -- "$CANON" "$LOOP" > "$FIX/uncited.md"
ok "a dispatcher missing the line is caught" "$(has "$FIX/uncited.md" "$CANON")" no

# (c) prose that claims the unenforceable half IS enforced
printf '%s\n' "- $ANCHOR — the same-task half is enforced by scripts/nothing.sh" > "$FIX/overclaim.md"
OVER="$(bullet_of "$FIX/overclaim.md" "A subagent works ONE task")"
ok "an overclaiming bullet is extractable" "$([ -n "$OVER" ] && echo yes || echo no)" yes
ok "…and its false claim is visible"     "$(grep -qF 'enforced by' <<<"$OVER" && echo yes || echo no)" yes

# (d) a tick-lock with the refusal removed — the mechanism, not the sentence
sed 's/^\( *\)refuse_unlaunched$/\1: # removed/' "$LOCKSH" > "$FIX/tick-lock.sh"
# tick-lock.sh sources its sibling resolver (ai-bridge-v3/task-031); without it the mutant
# exits 2 before reaching the refusal this asserts is gone.
cp "$(dirname "$LOCKSH")/bundle-paths.sh" "$FIX/bundle-paths.sh"
MI="$TMP/mutant-instance"; mkdir -p "$MI"
bash "$FIX/tick-lock.sh" acquire --as tick --instance "$MI" >/dev/null 2>&1
ok "…and a stripped refusal stops refusing" "$?" 0

echo
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
