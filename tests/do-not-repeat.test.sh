#!/usr/bin/env bash
#
# do-not-repeat.test.sh — a failed round's dead end reaches the NEXT dispatch's brief,
# verbatim.
#
# WHAT IS PINNED, AND WHY IT IS THE BRIEF TEXT. The feature is worth nothing unless the
# line an agent wrote at the end of round 1 is in front of the agent dispatched for round
# 2, so the measurement is the generated BRIEF, on a fixture: append one entry, then assert
# the second dispatch's brief carries the heading and that entry character for character.
# Deliberately NOT a test of what a model does with the brief — that is unmeasurable here,
# and a harness that asserted it would be asserting nothing.
#
# NON-VACUOUS BY CONSTRUCTION. The same task's brief is captured BEFORE the append (empty,
# and not carrying the line) and after, so a `brief` that stopped reading the field would
# flip a verdict rather than print a different shape.
#
# THE HEADING IS PINNED IN TWO PLACES ON PURPOSE — here as a literal, and against
# `project-manager.md`, which tells the PM to paste the block unchanged. A rename that
# lands in the script alone leaves the PM instructing agents to look for a heading nothing
# emits (knowledge/findings/renaming-a-string-a-gate-greps-for-needs-a-second-narrower-
# table.md is the same class).
#
# `assert()` uses exit-code semantics: 0 is a PASS, matching the other harnesses.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/plugin/scripts/do-not-repeat.sh"
PM_DOC="$REPO/plugin/tick-steps/step-3-dispatch.md"
CONV="$REPO/plugin/seed/CONVENTIONS.md"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
for f in "$SCRIPT" "$PM_DOC" "$CONV" "$SCHEMA"; do
  [ -f "$f" ] || { echo "do-not-repeat.test: missing $f" >&2; exit 2; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/do-not-repeat-fixture.XXXXXX")" || {
  echo "do-not-repeat.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
assert() { if [ "$2" = 0 ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
has()  { grep -qF -e "$1" <<<"$2" && echo 0 || echo 1; }   # here-string: a pipe + grep -q dies of SIGPIPE on a long doc under pipefail
hasnt(){ grep -qF -e "$1" <<<"$2" && echo 1 || echo 0; }
eq()   { [ "$1" = "$2" ] && echo 0 || echo 1; }

HEADING='## Do not repeat (earlier rounds of this task)'
DOC="$TMP/projects/demo/tasks/task-001.md"

reset() {
  rm -rf "$TMP/projects"; mkdir -p "$TMP/projects/demo/tasks"
  { printf -- '---\ntype: Task\ntitle: "Ship the widget"\nkind: build\n'
    printf 'status: in-progress\nassignee: software-engineer\npr: [ ]\n'
    printf 'timestamp: 2026-01-01T00:00:00Z\n---\n\n# Context\n\nSomething.\n'
  } > "$DOC"
}
run() { bash "$SCRIPT" "$@" 2>&1; }
rc()  { bash "$SCRIPT" "$@" >/dev/null 2>&1; echo $?; }
fm()  { grep -m1 '^do_not_repeat:' "$DOC" | sed 's/^do_not_repeat:[[:space:]]*//'; }

ONE='widened the ERE to allow closed ATX — pr-body-shape.test.sh 40/2, rows 3 and 7 still refused'

echo "== a round records ONE line, folded and bounded =="

reset
assert "a fresh task carries no field"          "$(eq "$(fm)" "")"
assert "append exits 0"                         "$(rc append "$DOC" --line "$ONE")"
assert "…and the entry is stored as one scalar" "$(eq "$(fm)" "[ \"$ONE\" ]")"
assert "…and it says what it recorded"          "$(has "RECORDED  1/10 — $ONE" "$(reset; run append "$DOC" --line "$ONE")")"

reset
run append "$DOC" --line "$(printf 'line one\n\tline   two')" >/dev/null
assert "newlines and tabs fold to single spaces" "$(eq "$(fm)" '[ "line one line two" ]')"

reset
LONG="$(printf 'x%.0s' $(seq 1 260))"
run append "$DOC" --line "$LONG" >/dev/null
assert "a 260-char line is truncated to 200"    "$(eq "$(fm | tr -cd 'x' | wc -c | tr -d ' ')" 200)"

reset
ODD='ran `foo --flag "bar"` \ twice'
run append "$DOC" --line "$ODD" >/dev/null
assert "quotes and backslashes are escaped"     "$(eq "$(fm)" '[ "ran `foo --flag \"bar\"` \\ twice" ]')"
assert "…and read back out as written"          "$(has "- $ODD" "$(run brief "$DOC")")"

reset
run append "$DOC" --line "$ONE" >/dev/null
run append "$DOC" --line "$ONE" >/dev/null
assert "the same line twice is not two entries" "$(eq "$(fm)" "[ \"$ONE\" ]")"
assert "…and the second call still exits 0"     "$(rc append "$DOC" --line "$ONE")"
assert "…saying it was already recorded"        "$(has 'already recorded' "$(run append "$DOC" --line "$ONE")")"

echo
echo "== a SECOND dispatch receives the first round's line, in its brief =="

# THE MEASUREMENT criterion 4 asks for, on a fixture, against the generated text. Round 1
# ends on a failed check and appends; round 2's brief is built from the same document.
reset
BEFORE="$(run brief "$DOC")"
assert "before any round, the brief is EMPTY"       "$(eq "$BEFORE" "")"
assert "…and exits 0 — nothing to say is not a failure" "$(rc brief "$DOC")"
assert "…and does not carry the line, obviously"    "$(hasnt "$ONE" "$BEFORE")"

run append "$DOC" --line "$ONE" >/dev/null          # round 1 ends without a green PR
AFTER="$(run brief "$DOC")"
assert "the second dispatch's brief carries it VERBATIM" "$(has "- $ONE" "$AFTER")"
assert "…under the fixed heading"                   "$(has "$HEADING" "$AFTER")"
assert "…the heading is the FIRST line of the block" "$(eq "$(printf '%s\n' "$AFTER" | sed -n 1p)" "$HEADING")"
assert "…one bullet per entry, and only one here"   "$(eq "$(printf '%s\n' "$AFTER" | grep -c '^- ')" 1)"
assert "…and the block says what the lines are"     "$(has 'Do not retry one' "$AFTER")"

run append "$DOC" --line 'reran the suite with TMPDIR unset — same 2 failures' >/dev/null
THIRD="$(run brief "$DOC")"
assert "a third dispatch carries BOTH lines"        "$(eq "$(printf '%s\n' "$THIRD" | grep -c '^- ')" 2)"
assert "…oldest first, in the order they happened"  "$(has "- $ONE" "$(printf '%s\n' "$THIRD" | sed -n 3p)")"
assert "…still under ONE heading"                   "$(eq "$(printf '%s\n' "$THIRD" | grep -c '^## ')" 1)"

# The PM is told to paste that block unchanged, so it has to name the same heading.
assert "project-manager.md names the same heading"  "$(has "$HEADING" "$(cat "$PM_DOC")")"
assert "…and says to paste it unchanged"            "$(has 'unchanged, heading and all' "$(cat "$PM_DOC")")"
assert "…and calls the script by name"              "$(has 'do-not-repeat.sh brief' "$(cat "$PM_DOC")")"

echo
echo "== the cap is 10, and the refusal says what to do about it =="

reset
worst=0
for i in $(seq 1 10); do r="$(rc append "$DOC" --line "approach $i")"; [ "$r" -gt "$worst" ] && worst="$r"; done
assert "ten entries all record"                 "$(eq "$worst" 0)"
assert "…and the brief carries all ten"         "$(eq "$(run brief "$DOC" | grep -c '^- ')" 10)"
OVER="$(run append "$DOC" --line 'an eleventh approach')"
assert "the eleventh is refused with exit 1"    "$(eq "$(rc append "$DOC" --line 'an eleventh approach')" 1)"
assert "…naming the cap"                        "$(has 'cap of 10' "$OVER")"
assert "…and the fold that clears it"           "$(has "'# Notes'" "$OVER")"
assert "…and nothing was written"               "$(hasnt 'an eleventh approach' "$(cat "$DOC")")"
assert "…while a line already there still no-ops" "$(rc append "$DOC" --line 'approach 4')"

echo
echo "== a BLOCK-form list is read, appended to and reread — never orphaned =="

block_doc() { # <entry>... — each a quoted YAML scalar, written as a block item
  rm -rf "$TMP/projects"; mkdir -p "$TMP/projects/demo/tasks"
  { printf -- '---\ntype: Task\ntitle: "Ship the widget"\nstatus: in-progress\ndo_not_repeat:\n'
    for e in "$@"; do printf '  - %s\n' "$e"; done
    printf '\ntimestamp: 2026-01-01T00:00:00Z\n---\n\n# Context\n\nSomething.\n'
  } > "$DOC"
}
yaml_list() { # the independent reader: PyYAML, one entry per line
  python3 -c 'import sys, yaml
t = open(sys.argv[1]).read().split("\n---\n")[0][4:]
print("\n".join(yaml.safe_load(t)["do_not_repeat"]))' "$DOC" 2>&1
}

block_doc '"tried A"' '"tried \"B\""'
BB="$(run brief "$DOC")"
assert "brief reads both block entries"         "$(eq "$(printf '%s\n' "$BB" | grep -c '^- ')" 2)"
assert "…under the fixed heading"               "$(eq "$(printf '%s\n' "$BB" | sed -n 1p)" "$HEADING")"
assert "…unescaped, in order"                   "$(eq "$(printf '%s\n' "$BB" | sed -n '3,4p')" "$(printf -- '- tried A\n- tried "B"')")"
assert "append to a block list exits 0"         "$(rc append "$DOC" --line 'tried C')"
assert "…leaving three items"                   "$(eq "$(grep -c '^  - ' "$DOC")" 3)"
assert "…still a block list"                    "$(eq "$(grep -c '^do_not_repeat:$' "$DOC")" 1)"
assert "…keeping the blank line and the next key" "$(has "$(printf '  - "tried C"\n\ntimestamp:')" "$(cat "$DOC")")"
assert "brief now carries all three, in order"  "$(eq "$(run brief "$DOC" | grep '^- ')" "$(printf -- '- tried A\n- tried "B"\n- tried C')")"
if python3 -c 'import yaml' >/dev/null 2>&1; then
  assert "PyYAML parses exactly the three, in order" "$(eq "$(yaml_list)" "$(printf 'tried A\ntried "B"\ntried C')")"
else
  echo "  SKIP  PyYAML not importable — the brief assertion above is the reader"
fi

block_doc "'single ''quoted'''" 'bare entry  # a comment'
assert "single-quoted and bare items read as YAML does" \
       "$(eq "$(run brief "$DOC" | grep '^- ')" "$(printf -- "- single 'quoted'\n- bare entry")")"

# shellcheck disable=SC2046 # one word per entry, on purpose
block_doc $(for i in $(seq 1 10); do printf '"approach-%s" ' "$i"; done)
cp "$DOC" "$TMP/cap.before"
assert "a block list of 10 is at the cap: exit 1" "$(eq "$(rc append "$DOC" --line 'an eleventh')" 1)"
assert "…and nothing was written"               "$(cmp -s "$DOC" "$TMP/cap.before" && echo 0 || echo 1)"

# A hand-typed entry the writer cannot reproduce (it folds and truncates) forces the reread
# to disagree with the intended list.
block_doc '"tried A"' "\"$(printf 'y%.0s' $(seq 1 250))\""
cp "$DOC" "$TMP/mm.before"
MM="$(run append "$DOC" --line 'tried C')"
assert "a reread mismatch exits 3"              "$(eq "$(rc append "$DOC" --line 'tried C')" 3)"
assert "…saying nothing was written"            "$(has 'nothing written' "$MM")"
assert "…and the file is byte-identical"        "$(cmp -s "$DOC" "$TMP/mm.before" && echo 0 || echo 1)"

block_doc '"tried A' '"tried B"'
cp "$DOC" "$TMP/uq.before"
assert "an unterminated quote is refused: exit 2" "$(eq "$(rc append "$DOC" --line 'tried C')" 2)"
assert "…and nothing was written"               "$(cmp -s "$DOC" "$TMP/uq.before" && echo 0 || echo 1)"

echo
echo "== validate-bundle accepts the field, and reports a list over the cap =="

VB="$REPO/plugin/scripts/validate-bundle.sh"
B="$TMP/bundle"; mkdir -p "$B/projects/demo/tasks"
echo '{ "org": "x" }' > "$B/instance.config.json"; echo '# Schema' > "$B/SCHEMA.md"
list() { local n=$1 out="" i; for i in $(seq 1 "$n"); do out="$out\"entry $i\", "; done; printf '[ %s ]' "${out%, }"; }
task() { # <name> <do_not_repeat value>
  { printf -- '---\ntype: Task\ntitle: T\nstatus: in-progress\n'
    printf 'do_not_repeat: %s\n' "$2"
    printf 'timestamp: 2026-01-01T00:00:00Z\n---\nbody\n'
  } > "$B/projects/demo/tasks/$1.md"
}
task task-under "$(list 10)"
task task-over  "$(list 11)"
task task-escaped '[ "an entry with a \", comma inside" ]'
# The two YAML shapes, same content: block form read as ZERO entries until the counter
# was made one splitter, so a list over the cap passed the gate by being written `- a`.
block() { local n=$1 out="" i; for i in $(seq 1 "$n"); do out="$out
  - \"entry $i\""; done; printf '%s' "$out"; }
task task-block-under "$(block 10)"
task task-block-over  "$(block 11)"
VBOUT="$(cd "$B" && bash "$VB" 2>&1)"
assert "a list of 10 is accepted in silence"    "$(hasnt 'task-under' "$VBOUT")"
assert "…and an escaped quote does not miscount" "$(hasnt 'task-escaped' "$VBOUT")"
assert "a list of 11 is reported"               "$(has 'do_not_repeat carries 11 entries' "$VBOUT")"
assert "…as a WARN, not an ERROR"               "$(has 'WARN   projects/demo/tasks/task-over.md' "$VBOUT")"
assert "…naming the cap and the fold"           "$(has "caps it at 10 — the project-manager folds the oldest into '# Notes'" "$VBOUT")"
assert "block form of 10 is accepted too"       "$(hasnt 'task-block-under' "$VBOUT")"
assert "block form of 11 is reported too"       "$(has 'WARN   projects/demo/tasks/task-block-over.md' "$VBOUT")"
assert "…with the SAME count as the flow form"  "$(eq "$(printf '%s\n' "$VBOUT" | grep -c 'do_not_repeat carries 11 entries')" 2)"
assert "…and the bundle still exits 0"          "$(cd "$B" && bash "$VB" >/dev/null 2>&1; echo $?)"

echo
echo "== the rule and the field are documented where agents read them =="

CONV_TXT="$(cat "$CONV")"
assert "CONVENTIONS.md names the field"         "$(has 'do_not_repeat' "$CONV_TXT")"
assert "…triggered by a failed check or a reviewer refusal" \
       "$(has 'A round that ends on a failed check or a reviewer refusal appends ONE line' "$CONV_TXT")"
assert "…before the agent stops"                "$(has 'BEFORE you stop' "$CONV_TXT")"
assert "…bounded at 200 characters"             "$(has 'at most 200 characters' "$CONV_TXT")"
assert "…naming the approach AND the evidence"  "$(has '<approach> — <evidence>' "$CONV_TXT")"
assert "…and the command that does it"          "$(has 'do-not-repeat.sh append' "$CONV_TXT")"
assert "SCHEMA.md documents the frontmatter field" "$(has 'do_not_repeat: [' "$(cat "$SCHEMA")")"
assert "…and its cap"                           "$(has 'capped at 10' "$(cat "$SCHEMA")")"

echo
echo "== refusals: unknown is never reported as fine =="

reset
assert "a task document that does not exist -> 2"    "$(eq "$(rc append "$TMP/nope.md" --line x)" 2)"
printf 'no frontmatter here\n' > "$TMP/bad.md"
assert "unreadable frontmatter -> 2, nothing written" "$(eq "$(rc append "$TMP/bad.md" --line x)" 2)"
assert "…and that document is untouched"             "$(eq "$(cat "$TMP/bad.md")" 'no frontmatter here')"
assert "brief on the same document -> 2"             "$(eq "$(rc brief "$TMP/bad.md")" 2)"
assert "an unknown command -> 2"                     "$(eq "$(rc bogus "$DOC")" 2)"
assert "append without --line -> 2"                  "$(eq "$(rc append "$DOC")" 2)"
assert "a --line that folds to nothing -> 2"         "$(eq "$(rc append "$DOC" --line '   ')" 2)"
assert "…and the field was never created"            "$(eq "$(fm)" "")"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
