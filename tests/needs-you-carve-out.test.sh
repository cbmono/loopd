#!/usr/bin/env bash
#
# needs-you-carve-out.test.sh — plugin/seed/CLAUDE.md's `Needs you:` reply vocabulary
# carries the rule that promote and merge are never inferred from a glyph, and that a lone
# merge or close carries no Recommend: while a choice keeps one; an answer is an answer.sh call,
# a grant is answer.sh --grant, and the answer skill cannot Edit a task doc.
#
# Pins the CARVE-OUT, the superseded- and done-list rules and one-at-a-time questions,
# never the verb list: a glossary that cannot grow without a red harness is one nobody
# extends. Matching is on a flattened copy so a re-wrap does not turn this red. ok()
# compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SEED="$REPO/plugin/seed/CLAUDE.md"
[ -f "$SEED" ] || { echo "needs-you-carve-out.test: $SEED not found" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/needs-you-carve-out.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

flatten() { tr '\n' ' ' | tr -s ' '; }
saw() { grep -qF -- "$2" <<<"$1" && echo yes || echo no; }
section() { # <file> — the `## Reporting progress` body, flattened
  awk '/^## Reporting progress/ { insec=1; next } insec && /^## / { insec=0 } insec' "$1" | flatten
}

CARVE='**Promote and merge are never inferred: act on either only when the reply types `prom` or `mrg`; a bare number whose glyph is promote or merge gets a one-line confirmation and no action**'
STALE='reprinted, numbered, before you act on a number.'
CONFIRM='could fit an earlier list whose items are done: confirm the mapping in one line before acting.**'
ONEBYONE='**Agent-raised questions go to the owner one at a time**, the `### Q<n>` recommendation as option 1 — **never answered on the owner'"'"'s behalf.**'
RECOMMEND='one line per item, ending `Recommend: <answer> — <reason>`'
ANSWERSH='**Record each `open_questions` answer with its own `answer.sh` call**, never by hand-editing a task doc (perl, sed or Edit)'
GRANT='**A conditional grant** ("wait, then promote") **is `answer.sh --grant <task> <text>`**, never auto-memory'
SKILL="$REPO/plugin/skills/answer/SKILL.md"
tools() { sed -n 's/^allowed-tools: //p' "$1" | tr ',' '\n' | sed 's/^ *//' | grep -cx Edit; }
EXEMPT='A lone merge or close whose verb is the advice carries none; a choice, or advice other than the verb (wait), keeps it.'

S="$(section "$SEED")"
ok "the vocabulary is in § Reporting progress"   "$(saw "$S" 'Replies to a `Needs you:` list are shorthand.')" yes
ok "promote and merge are never inferred"        "$(saw "$S" "$CARVE")" yes
ok "a superseded list is reprinted first"        "$(saw "$S" "$STALE")" yes
ok "a reply fitting a done list is confirmed"    "$(saw "$S" "$CONFIRM")" yes
ok "agent questions go one at a time, never self-answered" "$(saw "$S" "$ONEBYONE")" yes
ok "each decision line ends in its Recommend:"   "$(saw "$S" "$RECOMMEND")" yes
ok "a lone merge or close carries none; a choice keeps it" "$(saw "$S" "$EXEMPT")" yes
ok "an answer is one answer.sh call, never a hand edit"  "$(saw "$S" "$ANSWERSH")" yes
ok "a conditional grant is answer.sh --grant, never memory" "$(saw "$S" "$GRANT")" yes
ok "the answer skill may not Edit"               "$(tools "$SKILL")" 0

grep -vF '**Promote and merge are never inferred' "$SEED" > "$TMP/mutant.md"
ok "mutant: carve-out deleted -> check FAILS"    "$(saw "$(section "$TMP/mutant.md")" "$CARVE")" no

grep -vF 'Agent-raised questions go to the owner' "$SEED" > "$TMP/mutant2.md"
ok "mutant: one-at-a-time rule deleted -> check FAILS" "$(saw "$(section "$TMP/mutant2.md")" "$ONEBYONE")" no

grep -vF 'Record each `open_questions` answer' "$SEED" > "$TMP/mutant3.md"
ok "mutant: answer.sh rule deleted -> check FAILS" "$(saw "$(section "$TMP/mutant3.md")" "$ANSWERSH")" no
sed 's/never auto-memory/in auto-memory/' "$SEED" > "$TMP/mutant4.md"
ok "mutant: grant sent to memory -> check FAILS"  "$(saw "$(section "$TMP/mutant4.md")" "$GRANT")" no
sed 's/^allowed-tools: \(.*\), Read, /allowed-tools: \1, Read, Edit, /' "$SKILL" > "$TMP/skill-mutant.md"
ok "mutant: Edit back in allowed-tools -> check FAILS" "$(tools "$TMP/skill-mutant.md")" 1

ok "mutant: exemption deleted -> check FAILS"    "$(saw "${S//"$EXEMPT"/}" "$EXEMPT")" no

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
