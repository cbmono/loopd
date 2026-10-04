#!/usr/bin/env bash
# fold-answers.sh — the mechanical `open_questions → answered_questions` move.
#
# WHY IT IS NOT BASH OR AWK, and why that is asserted here. These are quoted YAML flow
# lists carrying backticks, commas, square brackets and ` --- ` — the exact shape a
# hand-rolled split was measured mis-parsing on 2026-09-12. The cases below drive one
# entry of each kind through and assert it survives WHOLE; the refusal cases assert the
# file is left byte-identical, because a half-written list is worse than no fold.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SH="$REPO/plugin/scripts/fold-answers.sh"
command -v python3 >/dev/null 2>&1 || { echo "fold-answers.test: python3 required" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/fold-answers.XXXXXX")" || {
  echo "fold-answers.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi }

ok "the script exists" "$([ -f "$SH" ] && echo yes || echo no)" yes

doc() { # <path> <criteria> <open> <answered>
  printf -- '---\ntype: Task\ntitle: "T"\nstatus: draft\nacceptance_criteria: [ %s ]\nopen_questions: [ %s ]\nanswered_questions: [ %s ]\n---\n\n# Context\n\nbody\n' \
    "$2" "$3" "$4" > "$1"
}
field() { sed -n "s/^$2: //p" "$1" | head -n1; }

echo "== the move: every answered entry out, none left in both lists =="
A="$TMP/a.md"
doc "$A" '"c1"' '"Q1: colour? --- blue", "Q2: open", "Q3: moot? --- moot: superseded"' '"2020-01-01T00:00:00Z by x · Q0: old --- ok"'
OUT="$(bash "$SH" "$A" 2>&1)"; RC=$?
ok "it exits 0"                     "$RC" 0
ok "…and says how many it moved"    "$(printf '%s' "$OUT" | grep -c '^folded: 2 entries' | tr -d ' ')" 1
ok "the answered entries left open" "$(bash "$SH" --list "$A" open_questions | grep -c . | tr -d ' ')" 1
ok "…and the unanswered one stayed" "$(bash "$SH" --list "$A" open_questions)" "Q2: open"
ok "answered_questions grew by two" "$(bash "$SH" --list "$A" answered_questions | grep -c . | tr -d ' ')" 3
ok "the pre-existing entry is untouched" \
   "$(bash "$SH" --list "$A" answered_questions | head -n1)" "2020-01-01T00:00:00Z by x · Q0: old --- ok"
ok "NO entry is in both lists" \
   "$(comm -12 <(bash "$SH" --list "$A" open_questions | sort) \
               <(bash "$SH" --list "$A" answered_questions | sed 's/^[^·]*· //' | sort) | grep -c . | tr -d ' ')" 0

echo
echo "== the stamp: <ISO> by <login> · <entry VERBATIM> =="
ok "the moved entry carries an ISO stamp" \
   "$(bash "$SH" --list "$A" answered_questions | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z by .+ · ' | tr -d ' ')" 3
ok "…and the entry text verbatim after the separator" \
   "$(bash "$SH" --list "$A" answered_questions | grep -c '· Q1: colour? --- blue$' | tr -d ' ')" 1
# The login is resolved by decision-stamp.sh, never composed here — an unattributable one
# is written as `<unknown>` rather than skipped.
ok "the resolver is the source of the login" "$(grep -c 'decision-stamp.sh' "$SH" | tr -d ' ' | awk '{print ($1>0)?"yes":"no"}')" yes
ok "…and it is never bash's own guess"       "$(grep -c 'git log.*--format=%ae' "$SH" | tr -d ' ')" 0

echo
echo "== idempotent: nothing answered ⇒ exit 0, file byte-identical =="
B="$TMP/b.md"; doc "$B" '"c1"' '"Q1: still open"' ''
cp "$B" "$TMP/b.before"
ok "it exits 0"                "$(bash "$SH" "$B" >/dev/null 2>&1; echo $?)" 0
ok "…and wrote nothing"        "$(cmp -s "$B" "$TMP/b.before" && echo yes || echo no)" yes
cp "$A" "$TMP/a.before"
bash "$SH" "$A" >/dev/null 2>&1
ok "a second run over a folded doc changes nothing" "$(cmp -s "$A" "$TMP/a.before" && echo yes || echo no)" yes

echo
echo '== a REAL parser: backticks, commas, brackets and the --- separator survive whole =='
C="$TMP/c.md"
doc "$C" '"a `[<repo>#<n>](<url>)` row, with a comma"' \
         '"Q1: is `[ ]`, a comma and a ] fine? --- yes, all three"' ''
bash "$SH" "$C" >/dev/null 2>&1
ok "the criteria list is untouched" \
   "$(bash "$SH" --list "$C" acceptance_criteria)" 'a `[<repo>#<n>](<url>)` row, with a comma'
ok "…and the entry moved whole, separator and all" \
   "$(bash "$SH" --list "$C" answered_questions | sed 's/^[^·]*· //')" \
   'Q1: is `[ ]`, a comma and a ] fine? --- yes, all three'
# The whole point of the parser, asserted as a COUNT: one entry carrying a `, ` is one
# entry. A naive split on the comma returns two, and both halves are then quoted back into
# the document as separate criteria — which is the 2026-09-12 defect, silently.
ok "one entry carrying a comma is ONE entry" \
   "$(bash "$SH" --list "$C" acceptance_criteria | grep -c . | tr -d ' ')" 1
ok "…where a naive comma split would say two" \
   "$(sed -n 's/^acceptance_criteria: //p' "$C" | tr ',' '\n' | grep -c . | tr -d ' ')" 2

echo
echo "== the refusals: it would rather write NOTHING =="
D="$TMP/d.md"; doc "$D" '"c1"' '"Q1: a --- b"' ''
python3 - "$D" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().replace("answered_questions: [  ]\n", "")
open(p, "w").write(s)
PY
cp "$D" "$TMP/d.before"
bash "$SH" "$D" >/dev/null 2>&1; RC=$?
ok "no answered_questions: key ⇒ exit 3" "$RC" 3
ok "…and the file is untouched"          "$(cmp -s "$D" "$TMP/d.before" && echo yes || echo no)" yes

E="$TMP/e.md"; printf 'no frontmatter here\n' > "$E"; cp "$E" "$TMP/e.before"
bash "$SH" "$E" >/dev/null 2>&1
ok "no frontmatter ⇒ exit 3"             "$(bash "$SH" "$E" >/dev/null 2>&1; echo $?)" 3
ok "…and the file is untouched"          "$(cmp -s "$E" "$TMP/e.before" && echo yes || echo no)" yes

F="$TMP/f.md"; doc "$F" '"c1"' '"Q1: unterminated --- yes' ''
cp "$F" "$TMP/f.before"
bash "$SH" "$F" >/dev/null 2>&1; RC=$?
ok "an unterminated list ⇒ exit 3"       "$RC" 3
ok "…and the file is untouched"          "$(cmp -s "$F" "$TMP/f.before" && echo yes || echo no)" yes

echo "== the BOTH-LISTS failure is refused at exit 4, not written =="
# The failure this script exists for: an entry that would remain in `open_questions` while
# a copy sits in `answered_questions` silently blocks the draft forever.
G="$TMP/g.md"
doc "$G" '"c1"' '"Q1: answered --- yes", "Q2: stays open"' '"2020-01-01T00:00:00Z by x · Q2: stays open"'
cp "$G" "$TMP/g.before"
bash "$SH" "$G" >/dev/null 2>&1; RC=$?
ok "the double-listing is refused"       "$RC" 4
ok "…and nothing was written"            "$(cmp -s "$G" "$TMP/g.before" && echo yes || echo no)" yes
# Exit 4 and exit 3 are different fixes: 4 is a state to reconcile, 3 is a list to repair.
ok "…and 4 is not 3"                     "$([ "$RC" != 3 ] && echo yes || echo no)" yes

echo
echo "== --list is READ-ONLY =="
H="$TMP/h.md"; doc "$H" '"c1"' '"Q1: answered --- yes"' ''
cp "$H" "$TMP/h.before"
bash "$SH" --list "$H" open_questions >/dev/null 2>&1
ok "--list writes nothing, even with an answer pending" \
   "$(cmp -s "$H" "$TMP/h.before" && echo yes || echo no)" yes
ok "…and an absent key prints nothing, at exit 0" \
   "$(bash "$SH" --list "$H" no_such_key; echo "rc=$?")" "rc=0"

echo
echo "== an escape it cannot reproduce is refused, not silently dropped =="
# `\u263A` used to scan to `u263A` and re-parse to `u263A`, so the round-trip guard — which
# runs this same scanner — could not see that the backslash was gone.
X1="$TMP/x1.md"; doc "$X1" '"c1"' '"Q1: \u263A --- yes"' ''
cp "$X1" "$TMP/x1.before"
ok "--list refuses the unsupported escape (exit 3)" \
   "$(bash "$SH" --list "$X1" open_questions >/dev/null 2>&1; echo $?)" 3
ok "…the fold refuses it too"   "$(bash "$SH" "$X1" >/dev/null 2>&1; echo $?)" 3
ok "…and nothing was written"   "$(cmp -s "$X1" "$TMP/x1.before" && echo yes || echo no)" yes
F2="$TMP/f2.md"; doc "$F2" '"c1"' '"Q1: he said \"hi\" c:\\tmp --- yes"' ''
ok "the escapes emit() can reproduce still read" \
   "$(bash "$SH" "$F2" >/dev/null 2>&1; echo $?)" 0
ok "…and the entry survived the round trip verbatim" \
   "$(bash "$SH" --list "$F2" answered_questions | sed 's/^[^·]*· //')" 'Q1: he said "hi" c:\tmp --- yes'

echo
echo "== the document is replaced, never truncated in place =="
ok "it writes beside the document and renames" "$(grep -c 'os.replace' "$SH" | tr -d ' ')" 1
ok "…and never opens the document for writing" "$(grep -c 'open(path, "w"' "$SH" | tr -d ' ')" 0
I2="$TMP/i2.md"; doc "$I2" '"c1"' '"Q1: colour? --- blue"' ''
chmod 604 "$I2"
bash "$SH" "$I2" >/dev/null 2>&1
ok "…keeping the document's own mode" \
   "$(ls -l "$I2" | cut -c1-10)" "-rw----r--"
ok "…and leaving no temporary beside it" \
   "$(find "$TMP" -name '.fold-answers.*' | grep -c . | tr -d ' ')" 0

echo
echo "== the login: a COMMITTED answer never stamps this clone's owner =="
# `--author` unresolved used to fall back to `--self`, which attributes someone else's
# committed answer to whoever's loop happened to fold it.
R2="$TMP/repo"; mkdir -p "$R2"
( cd "$R2" && git init -q . \
  && git config user.email nobody@example.invalid && git config user.name Nobody ) >/dev/null 2>&1
printf '{ "ownerGithubUser": "octocat" }\n' > "$R2/instance.config.json"
J="$R2/j.md"; doc "$J" '"c1"' '"Q1: colour? --- blue"' ''
( cd "$R2" && git add -A . && git commit -qm answer ) >/dev/null 2>&1
bash "$SH" --instance "$R2" "$J" >/dev/null 2>&1
ok "an unresolvable commit author stays <unknown>" \
   "$(bash "$SH" --list "$J" answered_questions | sed 's/^[^ ]* by \([^ ]*\) .*/\1/')" "<unknown>"
K="$R2/k.md"; doc "$K" '"c1"' '"Q1: colour? --- blue"' ''
bash "$SH" --instance "$R2" "$K" >/dev/null 2>&1
ok "…while an answer only in the working tree is this session's" \
   "$(bash "$SH" --list "$K" answered_questions | sed 's/^[^ ]* by \([^ ]*\) .*/\1/')" "octocat"

# ONE FOLD, TWO HUMANS. A document-level test picks one login for every entry, so a
# session answer folded beside a committed one is stamped with the committed one's author.
L="$R2/l.md"; doc "$L" '"c1"' '"Q1: committed? --- yes"' ''
( cd "$R2" && git add -A . && git commit -qm committed ) >/dev/null 2>&1
doc "$L" '"c1"' '"Q1: committed? --- yes", "Q2: in session? --- yes"' ''
bash "$SH" --instance "$R2" "$L" >/dev/null 2>&1
who() { bash "$SH" --list "$1" answered_questions | sed -n "$2s/^[^ ]* by \([^ ]*\) .*/\1/p"; }
ok "the committed answer keeps the COMMIT's author"  "$(who "$L" 1)" "<unknown>"
ok "…and the session answer in the SAME fold is this session's" "$(who "$L" 2)" "octocat"

echo
echo "== a double listing is WHOLE entries, never a substring =="
# `e in a` read an open question quoted inside a longer answered one as a double listing
# and refused a valid fold at exit 4.
M="$TMP/m.md"; doc "$M" '"c1"' '"Q1: colour?", "Q2: which? --- the one from Q1: colour?"' ''
ok "an open question quoted INSIDE an answered one folds"  "$(bash "$SH" "$M" >/dev/null 2>&1; echo $?)" 0
ok "…and stays open"        "$(bash "$SH" --list "$M" open_questions)" "Q1: colour?"
# The real double listing still refuses, whether the copy carries its answer or not.
M2="$TMP/m2.md"; doc "$M2" '"c1"' '"Q1: a --- yes", "Q2: b"' '"2020-01-01T00:00:00Z by x · Q2: b --- yes"'
ok "the same question in both lists is still exit 4"       "$(bash "$SH" "$M2" >/dev/null 2>&1; echo $?)" 4

echo
echo "== --list prints ONE entry per line, or refuses =="
# A quoted scalar may carry a newline; printed, it becomes two records, and every caller
# reads this output a line at a time.
N="$TMP/n.md"; doc "$N" '"c1"' '"Q1: two\nlines --- yes"' ''
cp "$N" "$TMP/n.before"
ok "--list refuses an entry that would print as two records" \
   "$(bash "$SH" --list "$N" open_questions >/dev/null 2>&1; echo $?)" 3
ok "…the fold refuses it too"  "$(bash "$SH" "$N" >/dev/null 2>&1; echo $?)" 3
ok "…and nothing was written"  "$(cmp -s "$N" "$TMP/n.before" && echo yes || echo no)" yes

echo
echo "== a DANGLING separator is not an answer =="
# The test used to be `" --- " in entry`, so an entry that merely ENDED with the
# separator — the shape a template leaves, and the shape you get when the separator is
# pre-placed as an affordance for the answer — counted as answered. It moved carrying
# nothing and open_questions emptied. An empty open_questions IS the promotion signal,
# so that turned "nobody has answered this" into "this task is ready". Measured on three
# task documents whose every question was written that way: ten entries, none answered.
D="$TMP/dangle.md"
doc "$D" '"c1"' '"Q1: pre-placed separator --- ", "Q2: separator and spaces ---   "' ''
cp "$D" "$TMP/dangle.before"
ok "a dangling separator folds nothing, exit 0" "$(bash "$SH" "$D" >/dev/null 2>&1; echo $?)" 0
ok "…both questions stay open"                  "$(bash "$SH" --list "$D" open_questions | grep -c . | tr -d ' ')" 2
ok "…answered_questions stays empty"            "$(bash "$SH" --list "$D" answered_questions | grep -c . | tr -d ' ')" 0
ok "…and the document is byte-identical"        "$(cmp -s "$D" "$TMP/dangle.before" && echo yes || echo no)" yes

# The boundary: one non-space character after the separator IS an answer.
E="$TMP/short.md"
doc "$E" '"c1"' '"Q1: terse --- y", "Q2: dangling --- "' ''
ok "a one-character answer still folds"  "$(bash "$SH" "$E" 2>&1 | grep -c '^folded: 1 entry' | tr -d ' ')" 1
ok "…leaving only the dangling one open" "$(bash "$SH" --list "$E" open_questions)" "Q2: dangling --- "

# …and the separator that decides is the LAST one. A question may carry ` --- ` in its own
# text, so a search anywhere in the entry read that inner one as the answer and folded a
# question nobody had answered — the same empty `open_questions`, by another route.
I3="$TMP/inner.md"
doc "$I3" '"c1"' '"Q1: compare a --- b --- ", "Q2: compare c --- d --- the second one"' ''
ok "an inner separator does not answer a dangling entry" \
   "$(bash "$SH" "$I3" 2>&1 | grep -c '^folded: 1 entry' | tr -d ' ')" 1
ok "…the dangling one stays open, inner separator and all" \
   "$(bash "$SH" --list "$I3" open_questions)" "Q1: compare a --- b --- "
ok "…and the folded answer is the text after the FINAL separator" \
   "$(bash "$SH" --list "$I3" answered_questions | sed 's/^[^·]*· //')" \
   "Q2: compare c --- d --- the second one"

echo
echo "== a refusal NAMES the key it refused =="
# scan_flow read the module global `list_key`, which only `--list` sets — so on the fold
# path every refusal printed an empty name and the operator was told that a list they
# could not identify was not a list. A document has two scannable lists, so the message
# must say which one.
K="$TMP/scalar.md"
printf -- '---\ntype: Task\ntitle: "T"\nstatus: draft\nopen_questions: Q1 is a scalar\nanswered_questions: [ ]\n---\n\n# Context\n\nbody\n' > "$K"
ok "a list that is neither form is exit 3" "$(bash "$SH" "$K" >/dev/null 2>&1; echo $?)" 3
ok "…and the message names it"   "$(bash "$SH" "$K" 2>&1 | grep -c 'open_questions is neither a flow nor a block list' | tr -d ' ')" 1
ok "…never an empty name"        "$(bash "$SH" "$K" 2>&1 | grep -c 'fold-answers:  is not' | tr -d ' ')" 0
ok "--list on it names the key too" \
   "$(bash "$SH" --list "$K" open_questions 2>&1 | grep -c 'open_questions is neither' | tr -d ' ')" 1

echo
echo "== SCHEMA.md's block form round-trips: the promotion gate reads and writes it =="
# A non-empty list is one quoted entry per line; empty stays `[ ]`. An answered entry
# stranded in both lists blocks the draft forever, so that is the assertion that counts.
L="$TMP/blockfold.md"
printf -- '---\ntype: Task\ntitle: "T"\nstatus: draft\nacceptance_criteria:\n  - "c1, with a comma"\nopen_questions:\n  - "Q1: `[ ]`, a comma and a ]? --- yes, all three"\nanswered_questions: [ ]\n---\n\n# Context\n\nbody\n' > "$L"
ok "a block list is read, not refused" "$(bash "$SH" --list "$L" open_questions)" 'Q1: `[ ]`, a comma and a ]? --- yes, all three'
ok "the fold exits 0"               "$(bash "$SH" "$L" >/dev/null 2>&1; echo $?)" 0
ok "open_questions is left EMPTY, as [ ]" "$(grep -c '^open_questions: \[ \]$' "$L" | tr -d ' ')" 1
ok "the entry moved to answered_questions" \
   "$(bash "$SH" --list "$L" answered_questions | grep -c '· Q1: `\[ \]`, a comma and a \]? --- yes, all three$' | tr -d ' ')" 1
LO="$(bash "$SH" --list "$L" open_questions)" && LA="$(bash "$SH" --list "$L" answered_questions)" \
  && BOTH="$(comm -12 <(printf '%s\n' "$LO" | sort) <(printf '%s\n' "$LA" | sed 's/^[^·]*· //' | sort) | awk 'NF { n++ } END { print n + 0 }')" \
  || BOTH=unreadable
ok "NO entry survives in both lists (and both lists read)" "$BOTH" 0
ok "answered_questions is written in block form" "$(sed -n '/^answered_questions:$/{n;p;}' "$L" | grep -c '^  - "' | tr -d ' ')" 1
ok "…and the untouched block list is left as it was" "$(grep -c '^  - "c1, with a comma"$' "$L" | tr -d ' ')" 1
M="$TMP/mixed.md"
printf -- '---\ntype: Task\nstatus: draft\nopen_questions:\n  - "Q1: a --- b"\n  wrapped onto a second line\nanswered_questions: [ ]\n---\n' > "$M"
cp "$M" "$TMP/mixed.before"
ok "an indented non-entry line is refused (exit 3)" "$(bash "$SH" "$M" >/dev/null 2>&1; echo $?)" 3
ok "…and nothing was written" "$(cmp -s "$M" "$TMP/mixed.before" && echo yes || echo no)" yes

echo
echo "== usage =="
ok "no argument is exit 2" "$(bash "$SH" >/dev/null 2>&1; echo $?)" 2
ok "an unreadable path is exit 2" "$(bash "$SH" "$TMP/nope.md" >/dev/null 2>&1; echo $?)" 2

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
