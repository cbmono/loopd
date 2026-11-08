#!/usr/bin/env bash
#
# browser-default-off-disclosure.test.sh — `browser:` stays OFF by default, the same fact
# is written in three files, the DISCLOSURE of what granting it means ships, and the write
# gate is not part of the change.
#
# WHY THREE FILES. The default is stated in `seed/SCHEMA.md` (the field), in
# `skills/new-project/SKILL.md` (the question a human answers) and in
# `seed/CONVENTIONS.md` (the only browser text a dispatched role agent reads at run time).
# One fact written three times is how a default drifts: change two and the third still
# governs somebody's behaviour.
#
# WHY THE WRITE GATE IS PINNED WHOLE RATHER THAN GREPPED. A grep for the gate's opening
# and closing strings still passes when a loosening sentence is inserted BETWEEN them — so
# the assertion below is on the region, and the CONTROL MUTANT section is exactly that
# insertion, following tests/blocked-vs-own-tools.test.sh:284-290. The mutant is shown to
# defeat the two-grep check and to be caught by the pinned region.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
SKILL="$REPO/plugin/skills/new-project/SKILL.md"
# The rule moved verbatim to the product-repo detail of CONVENTIONS.md (leaner-prompts/task-002).
CONV="$REPO/plugin/seed/conventions/repos.md"
YOLO="$REPO/plugin-yolo/companion/AUTONOMY.md"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/browser-default-off.XXXXXX")" || {
  echo "browser-default-off-disclosure.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
saw() { grep -qF -- "$2" "$1" && echo yes || echo no; }
# The whitespace-flattened copy, for a clause the file wraps across two lines: reflowing a
# paragraph must not turn a rule's assertion red.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
saw_flat() { grep -qF -- "$2" <<<"$(flat "$1")" && echo yes || echo no; }

for f in "$SCHEMA" "$SKILL" "$CONV" "$YOLO"; do
  [ -f "$f" ] || { echo "browser-default-off-disclosure.test: no $f" >&2; exit 2; }
done

echo "== 1. all three files state the same default: OFF, opt in per project =="
ok "SCHEMA: the field's default is off" \
   "$(saw "$SCHEMA" 'browser: off | claude-for-chrome      # optional (default off).')" yes
ok "SCHEMA: § Browser access says opt IN" \
   "$(saw_flat "$SCHEMA" 'Opt in per project with `browser: claude-for-chrome` on `project.md` (default `off`).')" yes
ok "SKILL: the question is asked off-first" \
   "$(saw "$SKILL" '- **browser** — off (default) / claude-for-chrome.')" yes
ok "SKILL: it is asked on BOTH kinds"              "$(saw_flat "$SKILL" '**Asked on both kinds**')" yes
ok "SKILL: the flag line names the default off"    \
   "$(saw_flat "$SKILL" 'browser via the claude-in-chrome MCP when present (default `off`).')" yes
ok "CONV: the agent-facing rule is opt-in" \
   "$(saw "$CONV" '- **Browser (only if the project opts in):**')" yes
ok "CONV: …and keys on the project SETTING it"     \
   "$(saw_flat "$CONV" "when the task's project sets \`browser: claude-for-chrome\`")" yes

echo
echo "== 2. no file claims an absent key grants the browser =="
# The drift this section exists for: a document left behind saying the capability arrives
# by default, which would grant it to every project that never answered the question.
for pair in "SCHEMA:$SCHEMA" "SKILL:$SKILL" "CONV:$CONV" "README:$REPO/README.md"; do
  name="${pair%%:*}"; file="${pair#*:}"
  ok "$name: no \"default claude-for-chrome\" claim" \
     "$(grep -qiE 'default \x60?claude-for-chrome|absent[^.]{0,60}means (on|claude-for-chrome)' "$file" && echo no || echo yes)" yes
done

echo
echo "== 3. the DISCLOSURE ships: what GRANTING it means, in the field and the scaffold =="
# A human answering the question needs to know what the grant costs, and the reassurance
# that makes it defensible carries its own exception inline — § 7 is where that is graded.
ok "SCHEMA field: the grant is disclosed inline"   \
   "$(saw "$SCHEMA" 'GRANTING IT GIVES AGENTS READ ACCESS TO EVERY SITE THIS HUMAN IS LOGGED INTO')" yes
ok "SCHEMA field: …and the writes clause is qualified" \
   "$(saw "$SCHEMA" "browser WRITES ask first unless the project's autonomy delegates them, which is what makes granting it defensible")" yes
ok "SCHEMA § Browser access discloses read access" \
   "$(saw_flat "$SCHEMA" '**read access to every site this human is logged into in that browser**')" yes
ok "…and says why the grant is defensible"         \
   "$(saw_flat "$SCHEMA" "defensible because **browser writes ask first unless the project's \`autonomy\` delegates them** (rule 4)")" yes
ok "SKILL: the question is put as the opt-IN"      \
   "$(saw_flat "$SKILL" 'Ask it as the opt-IN it is ("grant browser access to this project?")')" yes
ok "SKILL: it discloses before the human answers"  \
   "$(saw_flat "$SKILL" 'agents get **read access to every site this human is logged into** in their browser')" yes
ok "SKILL: the writes clause carries its exception" \
   "$(saw_flat "$SKILL" 'browser **writes** ask first unless the chosen `autonomy` mode delegates them (below)')" yes
ok "SKILL: and the grant records its WHY"          \
   "$(saw_flat "$SKILL" 'Where the answer is `claude-for-chrome`, record **why** in `# Context`')" yes

echo
echo "== 4. nothing retroactive, and no script writes browser: into a project =="
# No existing project may gain the capability on upgrade, and no sweep may decide the
# question on the human's behalf in either direction.
for pair in "SCHEMA:$SCHEMA" "SKILL:$SKILL" "CONV:$CONV"; do
  name="${pair%%:*}"; file="${pair#*:}"
  ok "$name: no retroactive/migration story" \
     "$(grep -qiE 'retroactiv|migration script' "$file" && echo no || echo yes)" yes
done
ok "no plugin script writes a browser: key"        \
   "$(grep -rqE '^[^#]*browser: *(off|claude-for-chrome)' "$REPO/plugin/scripts" && echo no || echo yes)" yes

echo
echo "== 5. the verbatim strings other harnesses grep survive the edit =="
# tests/blocked-vs-own-tools.test.sh:258,271,286 read these. A rewrite of the browser
# paragraph that drops one of them turns that file red for a reason nobody would connect
# to this change, so they are asserted here too, next to the edit that could break them.
ok "the rung-1 deferral is verbatim"               "$(saw "$CONV" '**rung 1 above applies to the browser like any other tool**')" yes
ok "…and the one-statement clause with it"         "$(saw_flat "$CONV" 'it is the general one now, stated once, so the two cannot drift')" yes
ok "…and the missing-browser capability gap"       "$(saw_flat "$CONV" 'that is a capability gap, so take the non-browser route, say so, and carry on')" yes
ok "no lowercase browser-first was introduced"     \
   "$(grep -rqF 'browser-first' "$REPO/plugin/seed" "$REPO/docs" "$REPO/README.md" && echo no || echo yes)" yes

echo
echo "== 6. THE WRITE GATE, PINNED WHOLE =="
# Anchor to anchor, the closing anchor dropped: the region between them is what a two-grep
# check cannot see. Both regions are the text that shipped before this change.
gate_schema() { awk '/^4\. \*\*Writes follow the project.s `autonomy`, like every other gate\.\*\* /,/^5\. \*\*The usual data rules still apply\.\*\*/' "$1" | sed '$d'; }
gate_skill()  { awk '/^   If \*\*browser = claude-for-chrome\*\* and the chosen mode \*\*delegates browser writes\*\*,$/,/^   If the chosen mode \*\*delegates merging\*\*/' "$1" | sed '$d'; }

cat > "$TMP/gate-schema.expected" <<'GATE'
4. **Writes follow the project's `autonomy`, like every other gate.** **Ask first before
   any browser write** — that is the default and the only behaviour unless the project's
   `autonomy` delegates writes (see `AUTONOMY.md`; absent that file, always ask).
   Read-only navigation and screenshots never need permission.
   Two limits are *not* autonomy-specific and hold in **every** mode: an agent
   **doesn't redefine scope**, so a write nobody asked for is never licensed (the same
   rule that stops it inventing code changes); and irreversible actions well outside the
   task — a payment, deleting an account, mailing a customer — are worth one confirmation
   on cost grounds, not permission grounds. When in genuine doubt about blast radius, say
   what you're about to do and continue unless told otherwise.
GATE

sed "s/__PN__/$PN/g" > "$TMP/gate-skill.expected" <<'GATE'
   If **browser = claude-for-chrome** and the chosen mode **delegates browser writes**,
   don't block it — that combination is supported and deliberate. State once what it means
   so the choice is informed: agents may **write** in the human's logged-in browser
   (submit forms, change settings) without asking, including from background `/__PN__:dispatch`
   dispatches, and the extension's **per-site permissions** are then the effective
   boundary. Record that in `# Context` and continue. Otherwise browser writes ask first
   (see `SCHEMA.md` → "Browser access").
GATE

gate_schema "$SCHEMA" > "$TMP/gate-schema.actual"
gate_skill  "$SKILL"  > "$TMP/gate-skill.actual"
ok "the SCHEMA gate region is non-empty"           "$([ -s "$TMP/gate-schema.actual" ] && echo yes || echo no)" yes
ok "the SKILL gate region is non-empty"            "$([ -s "$TMP/gate-skill.actual" ] && echo yes || echo no)" yes
ok "SCHEMA rule 4 is the pinned text, whole"       "$(diff -u "$TMP/gate-schema.expected" "$TMP/gate-schema.actual" >/dev/null && echo yes || echo no)" yes
ok "SKILL's write-delegation warning, whole"       "$(diff -u "$TMP/gate-skill.expected" "$TMP/gate-skill.actual" >/dev/null && echo yes || echo no)" yes
ok "yolo's Browser writes row is byte-identical"   \
   "$(saw "$YOLO" '| Browser writes | Ask first | Permitted without asking | The task itself — a write nobody asked for is still out of scope |')" yes

echo
echo "== 7. THE DISCLOSURE'S CLAIM, GRADED IN BOTH AUTONOMY MODES =="
# Sections 1-3 ask whether a phrase is PRESENT. This one asks whether what it says is
# TRUE — and a claim about browser writes has two answers, because there are two modes.
# Each mode's own answer comes from `resolve-autonomy.sh` and the mode table it names,
# never from the disclosure under test.
RESOLVE="$REPO/plugin/scripts/resolve-autonomy.sh"
mkdir -p "$TMP/gated/projects/p" "$TMP/delegating/projects/p" "$TMP/no-plugins"
printf 'autonomy: gated\nbrowser: claude-for-chrome\n' > "$TMP/gated/projects/p/project.md"
printf 'autonomy: yolo\nbrowser: claude-for-chrome\n'  > "$TMP/delegating/projects/p/project.md"
# A root AUTONOMY.md is what arms the delegating fixture, and it wins outright — so this
# needs no plugin registry. `CLAUDE_CONFIG_DIR` points the gated one at an empty config,
# or a companion installed on THIS machine would arm it too.
cp "$YOLO" "$TMP/delegating/AUTONOMY.md"
resolver() { CLAUDE_CONFIG_DIR="$TMP/no-plugins" bash "$RESOLVE" --bundle "$1"; }

# What a mode actually does about browser writes, read out of the mode table by the
# mode's own column. No capability file ⇒ every project is gated ⇒ ask.
mode_writes() { # <bundle> <mode>
  local cap; cap="$(resolver "$1" 2>/dev/null)" || { echo ask; return; }
  [ -f "$cap" ] || { echo unreadable; return; }
  local cell
  cell="$(awk -v mode="$2" -F' *\\| *' '
    /^\| Gate \|/ { for (i = 2; i <= NF; i++) if ($i ~ mode) col = i; next }
    col && /^\| Browser writes \|/ { print $col; exit }' "$cap")"
  case "$cell" in
    "Ask first")                echo ask ;;
    "Permitted without asking") echo may-not-ask ;;
    *)                          echo unreadable ;;
  esac
}

# What a disclosure sentence PROMISES in a mode. Its base claim is "ask"; an inline
# exception naming autonomy delegation is the only thing that changes the delegating
# mode's answer, so a sentence carrying none promises "ask" in both.
promises() { # <sentence> <mode>
  local exc=no
  grep -qE -- 'unless the (project.s|chosen)[^.]*delegat' <<<"$1" && exc=yes
  if [ "$2" = delegating ] && [ "$exc" = yes ]; then echo may-not-ask; else echo ask; fi
}
accurate() { # <sentence> <mode> <what that mode actually does>
  [ "$(promises "$1" "$2")" = "$3" ] && echo yes || echo no
}
claim_of() { grep -oE -- "$2" "$1"; }           # <flat file> <ERE for the sentence>
SCHEMA_CLAIM_RE='it is defensible because [^.]*\.'
SKILL_CLAIM_RE='and browser \*\*writes\*\* [^.]*\.'
# The field comment at `SCHEMA.md:80` is a THIRD disclosure, and the two REs above cannot
# see it — so it is graded here as its own claim, in both modes, like the other two.
SCHEMA_FIELD_RE='browser WRITES [^.]*\.'
flat "$SCHEMA" > "$TMP/schema.flat"
flat "$SKILL"  > "$TMP/skill.flat"

# `-ef` and not a string compare: the resolver canonicalises through `cd`/`pwd`, so a
# TMPDIR with a trailing slash makes the two paths differ by a byte and name one file.
ok "gated fixture: the resolver finds no mode file" \
   "$(resolver "$TMP/gated" >/dev/null 2>&1; echo $?)" 1
ok "delegating fixture: the resolver names its file" \
   "$([ "$(resolver "$TMP/delegating" 2>/dev/null)" -ef "$TMP/delegating/AUTONOMY.md" ] && echo yes || echo no)" yes
GATED_WRITES="$(mode_writes "$TMP/delegating" gated)"
UNARMED_WRITES="$(mode_writes "$TMP/gated" gated)"
DELEG_WRITES="$(mode_writes "$TMP/delegating" yolo)"
ok "gated mode: the table says writes ASK"         "$GATED_WRITES" ask
ok "no mode file at all: writes ASK too"           "$UNARMED_WRITES" ask
ok "delegating mode: writes are PERMITTED"         "$DELEG_WRITES" may-not-ask

SCHEMA_CLAIM="$(claim_of "$TMP/schema.flat" "$SCHEMA_CLAIM_RE")"
SCHEMA_FIELD_CLAIM="$(claim_of "$TMP/schema.flat" "$SCHEMA_FIELD_RE")"
SKILL_CLAIM="$(claim_of "$TMP/skill.flat" "$SKILL_CLAIM_RE")"
# Vacuity guard: an extraction that found nothing would grade an empty string.
ok "the SCHEMA claim extracts, exactly one sentence" "$(grep -c . <<<"$SCHEMA_CLAIM")" 1
ok "the SCHEMA FIELD claim extracts, one sentence"   "$(grep -c . <<<"$SCHEMA_FIELD_CLAIM")" 1
ok "the SKILL claim extracts, exactly one sentence"  "$(grep -c . <<<"$SKILL_CLAIM")" 1
ok "SCHEMA claim is accurate under gated"          "$(accurate "$SCHEMA_CLAIM" gated "$GATED_WRITES")" yes
ok "SCHEMA claim is accurate when writes ARE delegated" \
   "$(accurate "$SCHEMA_CLAIM" delegating "$DELEG_WRITES")" yes
ok "SCHEMA field claim is accurate under gated"    "$(accurate "$SCHEMA_FIELD_CLAIM" gated "$GATED_WRITES")" yes
ok "SCHEMA field claim is accurate when delegated" \
   "$(accurate "$SCHEMA_FIELD_CLAIM" delegating "$DELEG_WRITES")" yes
ok "SKILL claim is accurate under gated"           "$(accurate "$SKILL_CLAIM" gated "$GATED_WRITES")" yes
ok "SKILL claim is accurate when writes ARE delegated"  \
   "$(accurate "$SKILL_CLAIM" delegating "$DELEG_WRITES")" yes

echo
echo "== MUTATION: the CONTROL MUTANT is a LOOSENING SENTENCE INSERTED BETWEEN THE ANCHORS =="
# Named, so what this file fails on is a fact and not a claim. The mutant is NOT a deletion
# — any grep catches that. It is one sentence that flips the gate while leaving both
# anchors in place, which is the edit a PR touching this area could plausibly smuggle in.
MUTANT='   Granting browser access also grants writes, so they no longer ask.'
awk -v m="$MUTANT" '{ print } /^4\. \*\*Writes follow the project.s `autonomy`, like every other gate\.\*\* / { print m }' \
  "$SCHEMA" > "$TMP/schema-mutant.md"
awk -v m="$MUTANT" '{ print } /^   If \*\*browser = claude-for-chrome\*\* and the chosen mode \*\*delegates browser writes\*\*,$/ { print m }' \
  "$SKILL" > "$TMP/skill-mutant.md"

ok "the mutation added something"                  \
   "$([ "$(wc -c < "$TMP/schema-mutant.md")" -gt "$(wc -c < "$SCHEMA")" ] && echo yes || echo no)" yes
# THE MEASURING STICK: the two-grep check a reviewer would have written passes on the
# mutant. That gap is exactly what pinning the region buys, and stating it here is what
# stops someone "simplifying" this section back into two greps.
ok "CREDULOUS: the opening anchor still greps"     "$(saw "$TMP/schema-mutant.md" '**Ask first before')" yes
ok "CREDULOUS: the closing anchor still greps"     "$(saw_flat "$TMP/schema-mutant.md" "what you're about to do and continue unless told otherwise")" yes
ok "CREDULOUS: the SKILL anchors still grep too"   \
   "$([ "$(saw "$TMP/skill-mutant.md" 'delegates browser writes')" = yes ] && saw_flat "$TMP/skill-mutant.md" 'Otherwise browser writes ask first')" yes
# …and the pinned region does not.
ok "mutant: SCHEMA rule 4 no longer matches"       "$(diff -u "$TMP/gate-schema.expected" <(gate_schema "$TMP/schema-mutant.md") >/dev/null && echo yes || echo no)" no
ok "mutant: the SKILL warning no longer matches"   "$(diff -u "$TMP/gate-skill.expected" <(gate_skill "$TMP/skill-mutant.md") >/dev/null && echo yes || echo no)" no
# CONTROL: the mutation is surgical — it touches the gate and nothing this file asserts
# about the default or the disclosure, so a red gate row can never be blamed on those.
ok "CONTROL: the default survives the mutation"    \
   "$(saw "$TMP/schema-mutant.md" 'browser: off | claude-for-chrome      # optional (default off).')" yes
ok "CONTROL: the disclosure survives it too"       \
   "$(saw_flat "$TMP/schema-mutant.md" '**read access to every site this human is logged into in that browser**')" yes

echo
echo "== MUTATION 2: THE WORDING REVERTED — THE EXCEPTION DROPPED, THE POINTER KEPT =="
# The pre-task text put back into the real files and driven through § 7. Flattened,
# because both clauses wrap across two source lines; substituted literally, so no regex
# escaping stands between the mutant and the words that actually shipped before.
# `awk` and not `${v//"$lit"/…}`: bash's substitution on the 77KB single line these files
# flatten to takes minutes, and it is the whole reason this section once hung.
lit_sub() { # <flat file> <literal to find> <literal to put there>
  awk -v f="$2" -v r="$3" \
    '{ while ((i = index($0, f)) > 0) $0 = substr($0, 1, i-1) r substr($0, i + length(f)); print }' "$1"
}
SCHEMA_NEW='**browser writes ask first unless the project'\''s `autonomy` delegates them** (rule 4)'
SCHEMA_OLD='**browser writes still ask first** (rule 4)'
SKILL_NEW='browser **writes** ask first unless the chosen `autonomy` mode delegates them (below)'
SKILL_OLD='browser **writes** still ask first (below)'
lit_sub "$TMP/schema.flat" "$SCHEMA_NEW" "$SCHEMA_OLD" > "$TMP/schema-reverted.flat"
lit_sub "$TMP/skill.flat"  "$SKILL_NEW"  "$SKILL_OLD"  > "$TMP/skill-reverted.flat"
# On the literals, never `cmp`: `lit_sub` prints a trailing newline the flattened file has
# not got, so a byte compare reads as "replaced" even when it substituted nothing.
replaced() { # <flat> <reverted> <new literal> <old literal>
  grep -qF -- "$3" "$1" && ! grep -qF -- "$3" "$2" && grep -qF -- "$4" "$2" && echo yes || echo no
}
ok "the SCHEMA reversion actually replaced text"   \
   "$(replaced "$TMP/schema.flat" "$TMP/schema-reverted.flat" "$SCHEMA_NEW" "$SCHEMA_OLD")" yes
ok "the SKILL reversion actually replaced text"    \
   "$(replaced "$TMP/skill.flat" "$TMP/skill-reverted.flat" "$SKILL_NEW" "$SKILL_OLD")" yes

# THE MEASURING STICK: the presence check this file carried before § 7 is GREEN on the
# reverted text. That is the gap two modes buy, and stating it is what stops someone
# collapsing § 7 back into a grep.
ok "CREDULOUS: the pre-task presence check passes"  \
   "$(grep -qF -- "defensible because $SCHEMA_OLD" "$TMP/schema-reverted.flat" && echo yes || echo no)" yes

REV_SCHEMA_CLAIM="$(claim_of "$TMP/schema-reverted.flat" "$SCHEMA_CLAIM_RE")"
REV_SKILL_CLAIM="$(claim_of "$TMP/skill-reverted.flat" "$SKILL_CLAIM_RE")"
ok "reverted SCHEMA claim: extracts one sentence"  "$(grep -c . <<<"$REV_SCHEMA_CLAIM")" 1
ok "reverted SKILL claim: extracts one sentence"   "$(grep -c . <<<"$REV_SKILL_CLAIM")" 1
ok "reverted SCHEMA claim: accurate under gated"   "$(accurate "$REV_SCHEMA_CLAIM" gated "$GATED_WRITES")" yes
ok "reverted SCHEMA claim: INACCURATE when delegated" \
   "$(accurate "$REV_SCHEMA_CLAIM" delegating "$DELEG_WRITES")" no
ok "reverted SKILL claim: accurate under gated"    "$(accurate "$REV_SKILL_CLAIM" gated "$GATED_WRITES")" yes
ok "reverted SKILL claim: INACCURATE when delegated"  \
   "$(accurate "$REV_SKILL_CLAIM" delegating "$DELEG_WRITES")" no
# CONTROL: the reversion is surgical — it touches the writes clause and nothing else this
# file asserts, so a red row above can never be blamed on the read-access disclosure.
ok "CONTROL: read access survives the reversion"   \
   "$(grep -qF -- '**read access to every site this human is logged into in that browser**' "$TMP/schema-reverted.flat" && echo yes || echo no)" yes
ok "CONTROL: the FIELD claim survives this reversion" \
   "$(accurate "$(claim_of "$TMP/schema-reverted.flat" "$SCHEMA_FIELD_RE")" delegating "$DELEG_WRITES")" yes

echo
echo "== MUTATION 3: THE FIELD TEXT AT :80 UNQUALIFIED, ALONE =="
# The half the rationale RE above cannot see: only `SCHEMA.md:80` goes back to its pre-task
# words, and the § 998 sentence stays qualified. Red here with green above is what proves
# the two disclosures are graded separately rather than one standing in for the other.
SCHEMA_FIELD_NEW="browser WRITES ask first unless the project's autonomy delegates them, which is what makes granting it defensible"
SCHEMA_FIELD_OLD='browser WRITES still ask first, which is what makes granting it defensible'
lit_sub "$TMP/schema.flat" "$SCHEMA_FIELD_NEW" "$SCHEMA_FIELD_OLD" > "$TMP/schema-field-reverted.flat"
ok "the FIELD reversion actually replaced text"    \
   "$(replaced "$TMP/schema.flat" "$TMP/schema-field-reverted.flat" "$SCHEMA_FIELD_NEW" "$SCHEMA_FIELD_OLD")" yes
# THE MEASURING STICK, again: § 3's presence check is a plain grep, so it is GREEN on the
# unqualified field text. That is exactly how this line survived three passes.
ok "CREDULOUS: § 3's presence check passes on it"  \
   "$(grep -qF -- "$SCHEMA_FIELD_OLD" "$TMP/schema-field-reverted.flat" && echo yes || echo no)" yes

REV_FIELD_CLAIM="$(claim_of "$TMP/schema-field-reverted.flat" "$SCHEMA_FIELD_RE")"
ok "reverted FIELD claim: extracts one sentence"   "$(grep -c . <<<"$REV_FIELD_CLAIM")" 1
ok "reverted FIELD claim: accurate under gated"    "$(accurate "$REV_FIELD_CLAIM" gated "$GATED_WRITES")" yes
ok "reverted FIELD claim: INACCURATE when delegated" \
   "$(accurate "$REV_FIELD_CLAIM" delegating "$DELEG_WRITES")" no
# CONTROL: the § 998 rationale is untouched here, so it is still accurate in both modes —
# the field-only mutant is invisible to it, which is the gap this section closes.
ok "CONTROL: the :998 rationale survives it"       \
   "$(accurate "$(claim_of "$TMP/schema-field-reverted.flat" "$SCHEMA_CLAIM_RE")" delegating "$DELEG_WRITES")" yes

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
