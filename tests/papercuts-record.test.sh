#!/usr/bin/env bash
#
# papercuts-record.test.sh — the papercut entry shape, and the four documents that
# promise it.
#
# WHY A HARNESS AND NOT A CONVENTION. A papercut is worth writing only while it is
# cheaper than a `Finding`, and the thing that keeps it cheap is that it is ONE LINE. That
# is a ceiling, and every ceiling in this repo that lived as prose was discovered at merge
# time: the record would fill with three-line entries nobody could group, and the
# cataloguer's pass — which reads the surface field — would degrade to reading prose.
#
# WHAT IS PINNED. The two boundary values (15 and 160 bytes on the note), the four fields,
# the `skill|agent|script` surface vocabulary, that `add` only ever APPENDS, that a pass
# marker scopes what `report` and `due` see, and that the four documents naming the shape
# still name it. Every bound is driven from BOTH sides — the value that must pass and the
# value one byte past it — because a bound asserted in one direction only is satisfied by
# a check that refuses everything.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PC="$REPO/plugin/scripts/papercuts.sh"
SEED="$REPO/plugin/seed/knowledge/papercuts.md"
CONV="$REPO/plugin/seed/CONVENTIONS.md"
CAT="$REPO/plugin/agents/cataloguer.md"
PM="$REPO/plugin/tick-steps/step-7-knowledge-base.md"
CLOSE="$REPO/plugin/skills/close-project/SKILL.md"
[ -x "$PC" ] || { echo "papercuts-record.test: missing or not executable: $PC" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/papercuts.XXXXXX")" \
  || { echo "papercuts-record.test: could not create a temp dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
has() { yn grep -qF "$2" "$1"; }
rep() { printf "%${2}s" '' | tr ' ' "$1"; }   # <char> <n> — n copies of char

REC="$TMP/papercuts.md"
fresh() { rm -f "$REC"; }
add() { # <note> [<surface>] [<task>] [<date>] -> exit code
  bash "$PC" add --file "$REC" --note "$1" --surface "${2:-script:validate-bundle.sh}" \
    --task "${3:-proj/task-001}" --date "${4:-2026-09-01}" >/dev/null 2>&1; echo $?
}

echo "== the entry shape: four fields, an ISO date, and a surface from the vocabulary =="
fresh
ok "a well-formed entry is appended"        "$(add 'exits 0 on an unreadable file, so it reads clean')" 0
ok "…the record now exists"                 "$(yn test -f "$REC")" yes
ok "…and carries exactly one entry line" \
   "$(grep -cE '^2026-09-01 \| proj/task-001 \| script:' "$REC")" 1
ok "a surface outside skill|agent|script is refused" \
   "$(add 'a note that is comfortably long enough' 'tool:jq')" 1
ok "…skill: is in the vocabulary"           "$(add 'a note that is comfortably long enough' 'skill:dispatch')" 0
ok "…agent: is in the vocabulary"           "$(add 'a note that is comfortably long enough' 'agent:qa-reviewer')" 0
ok "a surface with no kind is refused"      "$(add 'a note that is comfortably long enough' 'validate-bundle.sh')" 1
ok "a missing task is usage, not a silent entry" \
   "$(bash "$PC" add --file "$REC" --surface agent:x --note 'a note comfortably long enough' >/dev/null 2>&1; echo $?)" 2
ok "a whitespace-only task is refused"      "$(add 'a note that is comfortably long enough' 'agent:x' ' ')" 1
ok "a non-ISO --date never reaches the record" \
   "$(add 'a note that is comfortably long enough' 'agent:x' 'p/t' '06-09-2026')" 2

echo
echo "== the concision ceiling: ONE line, and the note's two measured bounds =="
fresh
ok "a note at the 15-byte floor is accepted"      "$(add "$(rep a 15)")" 0
ok "…one byte under the floor is REFUSED"         "$(add "$(rep a 14)")" 1
ok "a note at the 160-byte ceiling is accepted"   "$(add "$(rep a 160)")" 0
ok "…one byte over the ceiling is REFUSED"        "$(add "$(rep a 161)")" 1
ok "a note carrying a newline is REFUSED"         "$(add "$(printf 'first line\nsecond line here')")" 1
ok "a note carrying a '|' is REFUSED"             "$(add 'a note with a | in it, breaking the fields')" 1
ok "every line written is a whole entry" \
   "$(awk '/^## Entries/{f=1;next} f&&NF' "$REC" | grep -cvE '^[0-9]{4}-[0-9]{2}-[0-9]{2} \| [^|]+ \| (skill|agent|script):[^|]+ \| .+$')" 0

echo
echo "== append-only: an add never rewrites a byte that was already there =="
fresh
: > "$TMP/before"
bash "$PC" add --file "$REC" --task p/t-1 --surface agent:qa-reviewer \
  --note 'reviewed a head that had already moved' --date 2026-09-01 >/dev/null 2>&1
before_bytes="$(LC_ALL=C wc -c < "$REC" | tr -d ' ')"
head -c "$before_bytes" "$REC" > "$TMP/before"
bash "$PC" add --file "$REC" --task p/t-2 --surface agent:qa-reviewer \
  --note 'asked for a re-review after a fix commit' --date 2026-09-02 >/dev/null 2>&1
head -c "$before_bytes" "$REC" > "$TMP/after"
ok "the file's leading bytes are byte-identical"  "$(yn cmp -s "$TMP/before" "$TMP/after")" yes
ok "…and it grew"  "$(yn test "$(LC_ALL=C wc -c < "$REC" | tr -d ' ')" -gt "$before_bytes")" yes

echo
echo "== check reads the record, and a planted malformation is NOT a datum =="
ok "the clean record checks clean"                "$(yn bash "$PC" check --file "$REC")" yes
printf '2026-09-03 | p/t-3 | doc:CONVENTIONS.md | a surface kind nobody defined\n' >> "$REC"
ok "…a planted bad surface makes check exit 1"    "$(yn bash "$PC" check --file "$REC")" no
ok "…and check NAMES the offending line" \
   "$(bash "$PC" check --file "$REC" 2>&1 >/dev/null | grep -c 'doc:CONVENTIONS.md')" 1
printf '06-09-2026 | p/t-4 | agent:cataloguer | a hand-written line with a non-ISO date\n' >> "$REC"
ok "…and a hand-written non-ISO date too" \
   "$(bash "$PC" check --file "$REC" 2>&1 >/dev/null | grep -c 'not an ISO date')" 1
ok "check on a record with no ## Entries is unknown, not clean" \
   "$(printf '# nope\n' > "$TMP/nh.md"; bash "$PC" check --file "$TMP/nh.md" >/dev/null 2>&1; echo $?)" 2
ok "the SEEDED record checks clean"               "$(yn bash "$PC" check --file "$SEED")" yes

echo
echo "== report groups by surface, and a pass marker scopes what is still unprocessed =="
fresh
add 'exits 0 on an unreadable file, so it reads clean' script:validate-bundle.sh p/t-1 2026-09-01 >/dev/null
add 'the --apply flag is not in the header'           script:validate-bundle.sh p/t-2 2026-09-02 >/dev/null
add 'reviewed a head that had already moved'          agent:qa-reviewer          p/t-3 2026-09-03 >/dev/null
R="$(bash "$PC" report --file "$REC")"
ok "the report counts both surfaces"        "$(printf '%s' "$R" | grep -c '3 entries · 2 surfaces')" 1
ok "…the busiest surface leads"             "$(head -1 <<<"$(printf '%s\n' "$R" | grep -E '^(skill|agent|script):')" | awk '{print $1}')" "script:validate-bundle.sh"
ok "…with its entry count"                  "$(printf '%s' "$R" | grep -c 'script:validate-bundle.sh  (2)')" 1
ok "…and every entry appears under a surface" "$(printf '%s' "$R" | grep -c '^  2026-09-0')" 3
bash "$PC" pass --file "$REC" --date 2026-09-06 >/dev/null
ok "after a pass the record carries the marker" "$(grep -c '^<!-- pass 2026-09-06 ' "$REC")" 1
ok "…the marker is not read back as an entry"   "$(yn bash "$PC" check --file "$REC")" yes
ok "…and report sees nothing unprocessed" \
   "$(bash "$PC" report --file "$REC" | grep -c 'no entries')" 1
ok "…while --all still sees all three"          "$(bash "$PC" report --file "$REC" --all | grep -c '3 entries')" 1

echo
echo "== due: a cadence, not a nag — unprocessed entries AND an old enough last pass =="
ok "nothing since the pass ⇒ not due"       "$(bash "$PC" due --file "$REC" --date 2026-09-20 >/dev/null 2>&1; echo $?)" 1
add 'a fresh papercut arriving after the pass' agent:cataloguer p/t-4 2026-09-07 >/dev/null
ok "an entry 1 day after the pass ⇒ not due" "$(bash "$PC" due --file "$REC" --date 2026-09-07 >/dev/null 2>&1; echo $?)" 1
ok "…6 days after ⇒ still not due"           "$(bash "$PC" due --file "$REC" --date 2026-09-12 >/dev/null 2>&1; echo $?)" 1
ok "…7 days after ⇒ DUE"                     "$(bash "$PC" due --file "$REC" --date 2026-09-13 >/dev/null 2>&1; echo $?)" 0
ok "…and --every moves the cadence"          "$(bash "$PC" due --file "$REC" --date 2026-09-13 --every 30 >/dev/null 2>&1; echo $?)" 1
ok "a due-across-a-month-boundary is arithmetic, not string order" \
   "$(bash "$PC" due --file "$REC" --date 2026-10-01 >/dev/null 2>&1; echo $?)" 0
ok "no record at all ⇒ not due, and never a crash" \
   "$(bash "$PC" due --file "$TMP/absent.md" >/dev/null 2>&1; echo $?)" 1

echo
echo "== the documents that promise the shape still promise it =="
ok "the seed record ships"                  "$(yn test -f "$SEED")" yes
ok "…and states the four-field line"        "$(has "$SEED" 'DATE | TASK | KIND:NAME | what hurt')" yes
ok "…and the two bounds"                    "$(has "$SEED" '15-160 bytes')" yes
ok "…and that it is never edited"           "$(has "$SEED" 'Never edit or delete a line here')" yes
ok "CONVENTIONS tells an agent to record one" "$(has "$CONV" 'scripts/papercuts.sh add')" yes
ok "…with the same two bounds"              "$(has "$CONV" '15-160 bytes')" yes
ok "…and the append-never-edit rule"        "$(has "$CONV" 'Append, never edit or delete')" yes
ok "the cataloguer runs the grouping pass"  "$(has "$CAT" 'scripts/papercuts.sh report')" yes
ok "…proposing one task per surface"        "$(has "$CAT" 'One proposal per surface')" yes
ok "…and never marks the pass itself"       "$(has "$CAT" 'never mark the pass')" yes
ok "close-project marks the pass"           "$(has "$CLOSE" 'scripts/papercuts.sh pass')" yes
ok "…and is allowed to run the script"      "$(has "$CLOSE" 'Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/papercuts.sh:*)')" yes
ok "the tick asks whether a pass is due"    "$(has "$PM" 'scripts/papercuts.sh due')" yes
ok "…and creates the drafts as draft"       "$(has "$PM" 'never `ready`, the human')" yes
ok "the script's own default record path"   "$(has "$PC" 'FILE="knowledge/papercuts.md"')" yes
ok "…and the bounds it enforces are the documented ones" \
   "$(yn grep -qE '^NOTE_MIN=15$' "$PC"; )" yes
ok "…ceiling too"                           "$(yn grep -qE '^NOTE_MAX=160$' "$PC")" yes

echo "== an explicit --file path with whitespace stays one path =="
SP="$TMP/my records.md"
bash "$PC" add --file "$SP" --task p/t-9 --surface script:papercuts.sh \
  --note 'a --file path carrying a space must not word-split' >/dev/null 2>&1
ok "check reads the spaced record"          "$(bash "$PC" check --file "$SP" 2>/dev/null | sed -n 's/papercuts: \([0-9]*\) entries.*/\1/p')" 1

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
