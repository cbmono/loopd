#!/usr/bin/env bash
#
# pr-body-clearance.test.sh — exercises precondition 3 of the delegated merge gate,
# plugin/scripts/pr-body-clearance.sh.
#
# WHAT IT HAS TO PROVE, AND WHY EACH HALF IS HERE.
#
# `tests/pr-body-shape.test.sh` — the file next door — asserts that the short-form rule
# IS NAMED IN `CONVENTIONS.md`. That is a reader for the documentation, and it is doing
# its job. It is not a reader for the thing the rule governs, which is why an agent that
# had the rule opened a 14,673-character description five hours after it merged. This
# file covers the other reader: the one that takes an actual PR body and answers.
#
# THE LENGTH GATE, WHICH REVERSES WHAT THIS FILE USED TO PIN. Until 2026-09-06 the
# assertions here were the opposite: a 14,673-character body had to CLEAR, and no
# magnitude comparison on the count was allowed to exist. The owner's verdict that day
# set a hard ceiling instead (`CONVENTIONS.md` -> "Write less"), so the cases are inverted
# and the numbers behind them are real bodies, not round ones:
#
#   * ai-bridge#122 at 5,826 characters and #135 at 6,423 -> exit 4, both measured
#     2026-09-06 off the host.
#   * a 2,000-character body carrying every element -> clear. The ceiling has to leave a
#     complete body room, or it is a gate somebody switches off.
#   * the ROW bound is still not a SUM: rows at their own ceiling in a body under 2,500
#     clear, and a body of forty such rows is refused for its LENGTH (4), not its rows (3).
#
# THE FALSE-POSITIVE CASE THIS FILE ALSO PINS. A body that merely QUOTES the convention's
# example — which is a fenced TL;DR line above a fenced table — must NOT clear on the
# example. Fenced blocks are stripped before either test runs, and `a quoted example is
# not a body` drives that. It is the only route by which this predicate could have said
# "structure present" about a body carrying none, and being wrong in that direction is
# the only way it can be dangerous: a false "structure missing" costs a human a glance.
#
# EVERY SPELLING OF THE TL;DR MARKER IS PINNED, and that is coordination, not
# thoroughness. `CONVENTIONS.md` requires the heading `## Description` since 2026-09-06;
# the `(TL;DR)` suffix it carried before that clears FOR ONE MORE RELEASE, with a
# one-line deprecation notice, so a pull request opened before the rename is told rather
# than refused. Both spellings, and the notice, are pinned below; the notice is pinned in
# BOTH directions, because a notice that fires on the new heading is as wrong as one that
# never fires at all.
#
# `gh` is replaced by a stub on PATH, so the whole matrix runs offline. The stub answers
# from $FIX; an absent fixture is an absent thing, exactly as in review-clearance.test.sh.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/pr-body-clearance.sh"
SELFTEST_OK="pr-body-clearance: self-test ok"
HEAD_SHA="0c2592f7bb98d3de9a7a181d1762dfcaf80785d9"
OTHER_SHA="0123456789abcdef0123456789abcdef01234567"

# The description that motivated the original task, to the character. It used to have to
# clear; since the ceiling it is the far side of the boundary.
INCIDENT_CHARS=14673

# --- the concision ceilings, and the bodies behind them -----------------------
# FIXTURES, measured 2026-09-06 off cbmono/loopd and pinned here for the same reason
# the row corpus is: a live PR body is not a baseline. Both are the owner's evidence for
# the ceiling, so both must be refused, and a complete body at 2,000 must not be.
BODY_CEILING=2500
PR122_CHARS=5826           # -> must REFUSE at 4
PR135_CHARS=6423           # -> must REFUSE at 4
GOOD_BODY_CHARS=2000       # a complete body inside the ceiling -> must CLEAR
NOTES_CEILING=3

# --- the corpus behind the ROW bound ------------------------------------------
# THESE ARE FIXTURES, NOT A LIVE READ, AND THAT IS DELIBERATE. They were measured on
# 2026-08-30T16:24Z in bytes under `LC_ALL=C` over every acceptance-criteria row of three
# real pull requests (34 rows). Two of the three were OPEN, and #70's body was edited
# between two reads twenty-four minutes apart — its worst evidence cell went 325 -> 189
# while this change was being written. A gate calibrated against a body anyone can edit
# has no baseline at all, so the boundary values live here as constants and the harness
# never asks the host for them.
#
# The bound separates the corpus exactly: everything in #67 and #70 clears, and the three
# rows of #71 that carried shell one-liners and their own reasoning do not.
ROW_CEILING=400            # midpoint of the empty band 378-421, the widest gap
ROW_FLOOR=13               # midpoint of `see above` (9) and `CI run 1234 green` (17)
PR67_WORST_CELL=377        # largest honest cell in the corpus  -> must CLEAR
PR70_WORST_CELL=189        #                                    -> must CLEAR
PR70_SHORTEST_CELL=19      # shortest honest cell in the corpus -> must CLEAR
# #70's ROUND-2 body is the strongest single case for this ceiling, because it was
# rewritten to the house style AFTER the style was written and it is criteria-complete:
# 11 rows, longest whole ROW 264 bytes, longest evidence CELL 189. A recently-written,
# fully-evidenced body therefore sits at less than half the ceiling that catches #71 —
# so the bound is refusing bloat and not refusing thoroughness. A ceiling this case could
# not clear would be set too tight, and that is asserted below rather than asserted in a
# PR body nobody can re-run.
PR70_R2_WORST_ROW=264
PR71_BLOATED_CELLS="422 462 487"   # the three rows of #71      -> must REFUSE
# #71's evidence cells in the order they appear in its table, so a whole-table fixture
# reproduces which rows the reader names, not merely how many.
PR71_ROW_CELLS="341 317 462 334 271 298 187 340 487 422 160 266"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-body-clearance.XXXXXX")" || {
  echo "pr-body-clearance.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
command -v jq >/dev/null 2>&1 || { echo "jq is required to run this test"; exit 2; }
REAL_JQ="$(command -v jq)"
export FIX="$TMP/fix"
mkdir -p "$TMP/bin" "$FIX"

# --- stub ---------------------------------------------------------------------
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Minimal `gh` for pr-body-clearance.sh: it makes exactly one call, `gh pr view --json`.
case "${1:-} ${2:-}" in
  "pr view")
    [ -f "$FIX/gh_broken" ] && { echo "could not resolve to a PullRequest" >&2; exit 1; }
    [ -f "$FIX/pr_json" ] || { echo "could not resolve to a PullRequest" >&2; exit 1; }
    cat "$FIX/pr_json"; exit 0 ;;
esac
echo "stub: unhandled gh $*" >&2; exit 99
STUB
cat > "$TMP/bin/jq" <<STUB
#!/usr/bin/env bash
# The real jq, unless a case asks for a reader that cannot answer.
[ -f "\$FIX/jq_broken" ] && { echo "jq: broken pipe of a parser" >&2; exit 5; }
exec "$REAL_JQ" "\$@"
STUB
chmod +x "$TMP/bin/gh" "$TMP/bin/jq"
export PATH="$TMP/bin:$PATH"

# --- fixtures -----------------------------------------------------------------
body_file() { # <lines...> -> a file holding them
  local f; f="$(mktemp "$TMP/body.XXXXXX")"; printf '%s\n' "$@" > "$f"; printf '%s' "$f"
}

serve() { # <body-file> [head] — publish it as the PR the script will read
  rm -f "$FIX/gh_broken" "$FIX/jq_broken"
  "$REAL_JQ" -n --arg h "${2:-$HEAD_SHA}" --rawfile b "$1" \
    '{url:"https://github.com/acme/widgets/pull/42", number:42, headRefOid:$h, body:$b}' \
    > "$FIX/pr_json"
}

chars() { "$REAL_JQ" -Rs 'length' < "$1"; }   # code points, as the host counts them
cell() { printf '%*s' "$1" '' | tr ' ' 'x'; }   # an evidence cell of exactly <n> bytes

# --- assertions ---------------------------------------------------------------
expect() { # <name> <expected-rc> [args...] — runs against PR 42
  local name="$1" want="$2"; shift 2
  local out rc
  out="$("$SCRIPT" "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq "$want" ]; then
    printf '  PASS  %-58s (rc=%s)\n' "$name" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-58s expected rc=%s got rc=%s\n' "$name" "$want" "$rc"
    printf '        output: %s\n' "$(head -3 <<<"$out" | tr '\n' '|')"
    fail=$((fail+1))
  fi
  LAST_OUT="$out"
}

says() { # <name> <substring> — against the previous expect()'s output
  if grep -Fq "$2" <<<"$LAST_OUT"; then
    printf '  PASS  %-58s\n' "$1"; pass=$((pass+1))
  else
    printf '  FAIL  %-58s missing %s in: %s\n' "$1" "$2" "$(head -3 <<<"$LAST_OUT" | tr '\n' '|')"
    fail=$((fail+1))
  fi
}

says_not() { # <name> <substring> — the previous output must NOT contain it
  if grep -Fq "$2" <<<"$LAST_OUT"; then
    printf '  FAIL  %-58s unexpectedly said %s\n' "$1" "$2"; fail=$((fail+1))
  else
    printf '  PASS  %-58s\n' "$1"; pass=$((pass+1))
  fi
}

ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

TABLE_HEAD='| Criterion | ✓ | Verified by |'
TABLE_RULE='|---|---|---|'
TABLE_ROW='| the retry backs off on 429 | ✓ | `foo.test.sh` 40/0 |'
TABLE_CRIT='the retry backs off on 429'   # verbatim criterion text: not counted

# --- the three elements #3286 carries and elements 1-3 never asked for --------
# Every fixture below that is meant to CLEAR carries all of them, so a case about the
# table is not silently also a case about the Verified line. The ones that are about a
# new element drop or corrupt exactly that element and nothing else.
VERIFIED='Verified: `foo.test.sh` 40/0 on [run 1](https://example.invalid/actions/runs/1).'

crit_head() { # <✓ rows> [<✗ rows>] -> a criteria heading whose tally matches them
  if [ "${2:-0}" = 0 ]; then printf '### Criteria (%s ✓ / 0 ✗)' "$1"
  else printf '### Criteria (%s ✓ / %s ✗ — every ✗ needs a human)' "$1" "$2"; fi
}

shaped_body() { # <✓ rows> <✗ rows> <table lines...> -> a body carrying every element
  local c="$1" x="$2"; shift 2
  body_file '## Description' 'Adds the gate.' '' "$VERIFIED" '' \
            "$(crit_head "$c" "$x")" '' "$@"
}

good_body() { shaped_body 1 0 "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW"; }

echo "== the script runs, and proves it =="
out="$("$SCRIPT" --self-test 2>&1)"; rc=$?
ok "--self-test exits 0"                 "$rc" 0
ok "--self-test prints its contract"     "$out" "$SELFTEST_OK"

# The sibling's lesson, taken whole: "IT RUNS" IS NOT "IT IS COMPLETE". A copy cut off
# below the self-test block still reaches that block, still passes it, and still prints
# the sentinel — with the classifier below the cut simply gone. So the last line of the
# file is a completeness sentinel the self-test asserts, and every cut past the self-test
# block has to fail.
#
# AND THE CONTRACT IS THE PAIR, NEVER THE EXIT CODE ALONE, which is the reason this is
# spelled out rather than checked with `ok "$rc" 2`: a copy cut inside the HEADER is a
# file of nothing but comments, which runs fine and exits 0 having decided nothing. Only
# "exit 0 AND the sentinel string on stdout" separates that from a working script, and
# that pair is exactly what `required-checks.sh` compares.
selftest_contract() { # <path> -> yes if it exits 0 AND prints the contract string
  local out rc
  out="$("$1" --self-test 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "$SELFTEST_OK" ]; then echo yes; else echo no; fi
}
CUT="$TMP/cut.sh"
head -c 6000 "$SCRIPT" > "$CUT"; chmod +x "$CUT"
ok "a copy cut inside the header does not satisfy the contract" "$(selftest_contract "$CUT")" no

TOTAL_LINES="$(grep -c '' "$SCRIPT")"
ST_LINE="$(grep -n '^if \[ "\${1:-}" = "--self-test" \]' "$SCRIPT" | cut -d: -f1)"
ok "the self-test block is located" "$([ -n "$ST_LINE" ] && echo yes || echo no)" yes
for pct in 5 33 66 99; do
  n=$(( ST_LINE + ( (TOTAL_LINES - ST_LINE) * pct / 100 ) ))
  head -n "$n" "$SCRIPT" > "$CUT"; chmod +x "$CUT"
  ok "cut ${pct}% past the self-test -> refuses to vouch for itself" \
     "$(selftest_contract "$CUT")" no
done
ok "…while the intact file does vouch for itself" "$(selftest_contract "$SCRIPT")" yes

echo
echo "== both elements present: it clears, at whatever length =="
serve "$(good_body)"
expect "the heading form (CONVENTIONS.md's shape) -> clear" 0 42
says   "  ...and says both elements are there" "carries a TL;DR line and a well-formed"

serve "$(body_file '**TL;DR** — adds the gate.' '' "$VERIFIED" '' "$(crit_head 1)" '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "the bold form (CONVENTIONS.md's shape today) -> clear" 0 42

serve "$(body_file 'TL;DR: adds the gate.' '' "$VERIFIED" '' "$(crit_head 1)" '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "the bare-token form -> clear" 0 42

echo
echo "== the heading rename: the new form, the retired one, and the notice =="
# `## Description` is the required heading; `## Description (TL;DR)` clears for one more
# release so a body written before the rename is not refused at the merge gate.
serve "$(good_body)"
expect "'## Description' -> clear" 0 42
says_not "  ...with NO deprecation notice on the current heading" "is deprecated"

serve "$(body_file '## Description (TL;DR)' 'Adds the gate.' '' "$VERIFIED" '' \
                   "$(crit_head 1)" '' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "the retired '## Description (TL;DR)' -> still clear" 0 42
says   "  ...carrying the one-line deprecation notice" "is deprecated"
says   "  ...that names the heading to move to"        "use '## Description'"

# The new row matches the WHOLE heading text, so a heading that merely STARTS with the
# word is not the marker — the same fail-closed narrowing `## Is the TL;DR rule required?`
# already gets one block down.
serve "$(body_file '## Description ##' 'Adds the gate.' '' "$VERIFIED" '' \
                   "$(crit_head 1)" '' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "a closed ATX '## Description ##' -> clear" 0 42

serve "$(body_file '## Description of the parser' 'Adds the gate.' '' "$VERIFIED" '' \
                   "$(crit_head 1)" '' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "'## Description of the parser' is not the marker -> refuse" 1 42
says   "  ...naming the TL;DR line as missing" "MISSING: the TL;DR line"

# A `✗` row is the HONEST state of an unverified criterion, and SCHEMA.md clause 7 is what
# refuses on it. This predicate must not double as that gate, or the repo has two answers
# to one question — and the second one would refuse an honestly-marked PR before a human
# ever saw why.
serve "$(shaped_body 0 1 "$TABLE_HEAD" "$TABLE_RULE" \
                     '| works with two host accounts | ✗ | needs two accounts |')"
expect "a table whose row is ✗ -> still CLEAR (that is clause 7's job)" 0 42

echo
echo "== the BODY ceiling: the two bodies the owner measured, and one that fits =="
# Exact lengths, so a ceiling moved anywhere above 5,826 stops catching #122 and goes red
# here rather than quietly clearing the evidence it was set on.
sized_body() { # <chars> -> a complete body padded to COUNT exactly that many characters
  local want="$1" f; f="$TMP/sized.$want.md"
  { printf '%s\n' '## Description' 'Adds the gate.' '' "$VERIFIED" '' "$(crit_head 1)" ''
    printf '%s\n' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW"
    printf '\n'
  } > "$f"
  # `printf %*s` then a translate: ordinary prose characters, no newline, so the count is
  # exact rather than approximately right.
  printf '%*s' "$(( want + ${#TABLE_CRIT} - $(chars "$f") ))" '' | tr ' ' 'x' >> "$f"
  printf '%s' "$f"
}

B122="$(sized_body "$PR122_CHARS")"
ok "the #122 fixture counts exactly its measured length" \
   "$(( $(chars "$B122") - ${#TABLE_CRIT} ))" "$PR122_CHARS"
serve "$B122"
expect "ai-bridge#122's length (${PR122_CHARS}) -> REFUSE on length" 4 42
says   "  ...naming the ceiling it broke"          "over the ${BODY_CEILING}-character ceiling"
says   "  ...and telling the author to relocate"   "Move the"

B135="$(sized_body "$PR135_CHARS")"
serve "$B135"
expect "ai-bridge#135's length (${PR135_CHARS}) -> REFUSE on length" 4 42

GOODSIZE="$(sized_body "$GOOD_BODY_CHARS")"
ok "the 2,000-character fixture counts exactly that" \
   "$(( $(chars "$GOODSIZE") - ${#TABLE_CRIT} ))" "$GOOD_BODY_CHARS"
serve "$GOODSIZE"
expect "a ${GOOD_BODY_CHARS}-character complete body -> CLEAR" 0 42
says   "  ...and reports the count against the ceiling" "body is $GOOD_BODY_CHARS characters (ceiling $BODY_CEILING)"

# The boundary itself, both sides, one character apart — a ceiling nobody drove at its own
# edge is a ceiling that can be off by one and never say so.
serve "$(sized_body "$BODY_CEILING")"
expect "a body AT the ceiling -> CLEAR"            0 42
serve "$(sized_body "$(( BODY_CEILING + 1 ))")"
expect "one character past it -> REFUSE"           4 42

# The motivating body of the ORIGINAL design, which used to have to clear here. Kept as a
# case, with its verdict reversed, so the reversal is visible in the file rather than
# implied by a deletion.
serve "$(sized_body "$INCIDENT_CHARS")"
expect "the ${INCIDENT_CHARS}-character incident body -> now REFUSE" 4 42

echo
echo "== the ceiling measures the AUTHORED half: ai-bridge#195, verbatim =="
# THE REAL CASE, captured as a fixture for the reason the row corpus is: a body anyone can
# edit is not a baseline — #195's has been edited three times since. This is the state it
# was in at 2026-09-09T21:34Z, when the gate refused it for 740 characters of release
# notes CodeRabbit wrote into it. The author cannot shorten that block and it regenerates
# on every review, so a body that cleared when it was posted refused later.
BODY195="$(cd "$(dirname "$0")" && pwd)/fixtures/pr-body/ai-bridge-195.md"
PR195_POSTED=2672          # what the host served     -> was REFUSED at 4
PR195_AUTHORED=1932        # what its author wrote    -> must CLEAR
PR195_CRITERIA=585         # of which verbatim criterion text, not counted
PR195_OVER=2600            # the same body, authored past the ceiling -> must REFUSE
OPEN195='<!-- This is an auto-generated comment: release notes by coderabbit.ai -->'
CLOSE195='<!-- end of auto-generated comment: release notes by coderabbit.ai -->'

ok "the fixture is there"   "$([ -r "$BODY195" ] && echo yes || echo no)" yes
ok "…verbatim, to the character" "$(chars "$BODY195")" "$PR195_POSTED"
ok "…carrying the marker pair"   "$(grep -cF -e "$OPEN195" -e "$CLOSE195" "$BODY195")" 2

serve "$BODY195"
expect "#195 as posted (${PR195_POSTED}) -> CLEAR on its ${PR195_AUTHORED} authored" 0 42
says   "  ...reporting the counted half" \
       "body is $(( PR195_AUTHORED - PR195_CRITERIA )) characters (ceiling $BODY_CEILING)"
says   "  ...and the criterion text it left out" \
       "not counting $PR195_CRITERIA characters of verbatim criterion text"

says   "  ...and what it did not count"    "of $PR195_POSTED posted"

# The cases below are about the block, not the criteria, so they run on #195 with its
# criterion allowance spent again as prose: every count below is its authored count.
BODY195P="$TMP/pr195-prose.md"
awk -v m="$OPEN195" -v pad="$(printf '%*s' "$(( PR195_CRITERIA - 1 ))" '' | tr ' ' 'x')" \
  '$0 == m { print pad } { print }' "$BODY195" > "$BODY195P"

# THE MARKER IS THE ANCHOR, NEVER THE EDITOR'S LOGIN — which nothing here even reads. The
# identical text without its markers is an unrecognised block, so it is counted in full.
UNMARKED195="$TMP/pr195-unmarked.md"
grep -vF -e "$OPEN195" -e "$CLOSE195" "$BODY195P" > "$UNMARKED195"
serve "$UNMARKED195"
expect "…the same text with the markers removed -> REFUSE" 4 42
says   "  ...on the whole body"            "over the ${BODY_CEILING}-character ceiling"

# It loosens exactly one thing: an author past the ceiling is still refused, block or no.
OVER195="$TMP/pr195-over.md"
{ awk -v m="$OPEN195" '$0 == m { exit } { print }' "$BODY195P"
  # One short of the difference: the padding line carries its own newline.
  printf '%*s\n' "$(( PR195_OVER - PR195_AUTHORED - 1 ))" '' | tr ' ' 'x'
  awk -v m="$OPEN195" 'index($0, m) { p = 1 } p { print }' "$BODY195P"
} > "$OVER195"
serve "$OVER195"
expect "…and #195 padded to ${PR195_OVER} AUTHORED characters -> REFUSE" 4 42
says   "  ...counting its author's half, not the block" "is $PR195_OVER characters"

echo
echo "== and the marker pair is NOT an exemption an author can write himself =="
# Nothing in a body says who typed a line, so the strip is bounded by what the generator
# emits, markers included. Past the bound it strips nothing and the body is counted as
# posted — the verdict this gate gave before the strip existed.
GENERATED_CEILING=1000
PR195_BLOCK=740            # markers included: 2672 - 1932, the block CodeRabbit wrote

ok "the fixture's block is the measured 740" "$(( PR195_POSTED - PR195_AUTHORED ))" "$PR195_BLOCK"

padded_block() { # <chars> -> #195 with its block padded to exactly that many characters
  local want="$1" out="$TMP/pr195-block-$1.md"
  { awk -v m="$OPEN195" '{ print } index($0, m) { exit }' "$BODY195P"
    printf '%*s\n' "$(( want - PR195_BLOCK - 1 ))" '' | tr ' ' 'x'
    awk -v m="$OPEN195" 'p { print } index($0, m) { p = 1 }' "$BODY195P"
  } > "$out"
  printf '%s' "$out"
}

# The bound itself, both sides, one character apart.
AT="$(padded_block "$GENERATED_CEILING")"
ok "…the padded block is exactly the allowance" \
   "$(( $(chars "$AT") - PR195_AUTHORED - PR195_CRITERIA ))" "$GENERATED_CEILING"
serve "$AT"
expect "a block AT the ${GENERATED_CEILING}-character allowance -> CLEAR" 0 42
says   "  ...still on the authored half"   "body is $PR195_AUTHORED characters"
OVER="$(padded_block "$(( GENERATED_CEILING + 1 ))")"
serve "$OVER"
expect "one character past it -> counted in full -> REFUSE" 4 42
says   "  ...naming the allowance it broke" "marked block is over the ${GENERATED_CEILING}-character"
says   "  ...and counting the body as posted" "is $(( PR195_AUTHORED + GENERATED_CEILING + 1 )) characters"

# THE SELF-GRANT, which is what the bound exists for: the required structure outside an
# exact pair the author typed, his essay inside it.
SELF_GRANT="$(body_file '## Description' 'Adds the gate.' '' "$VERIFIED" '' "$(crit_head 1)" '' \
                        "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW" '' \
                        "$OPEN195" "$(printf '%*s' 2600 '' | tr ' ' 'x')" "$CLOSE195")"
serve "$SELF_GRANT"
expect "an author-owned exact pair around 2,600 characters -> REFUSE" 4 42
says   "  ...counting every character of it"  "over the ${BODY_CEILING}-character ceiling"

echo
echo "== verbatim criterion text is not charged: loopd task-025, verbatim =="
# Eight real criteria, quoted in full, pinned here because the task doc they came from is
# not in this repo. Under the old count this body refused at 4.
BODY025="$(cd "$(dirname "$0")" && pwd)/fixtures/pr-body/loopd-task-025-criteria.md"
T025_POSTED=4729
T025_CRITERIA=3849
CRITERION_ALLOWANCE=800
ok "the fixture is there, to the character" "$(chars "$BODY025")" "$T025_POSTED"
ok "…its criterion column alone, past the ceiling" \
   "$(awk -F' [|] ' '$2 == "✓" && $1 != "| Criterion" { sub(/^[|] /, "", $1); printf "%s", $1 }' \
      "$BODY025" | "$REAL_JQ" -Rs 'length')" "$T025_CRITERIA"
expect "task-025 quoted in full (${T025_POSTED}) -> CLEAR" 0 --body-file "$BODY025"
says   "  ...printing the number it compared" \
       "is $(( T025_POSTED - T025_CRITERIA )) characters (ceiling $BODY_CEILING)"
says   "  ...and what it left out"   "not counting $T025_CRITERIA characters"

crit_body() { # <criterion cell> <prose chars> -> one row, padded to COUNT <prose chars>
  local f; f="$(body_file '## Description' 'Adds the gate.' '' "$VERIFIED" '' "$(crit_head 1)" '' \
                          "$TABLE_HEAD" "$TABLE_RULE" "| $1 | ✓ | \`foo.test.sh\` 40/0 |")"
  printf '%*s' "$(( $2 - $(chars "$f") + $(printf '%s' "$1" | "$REAL_JQ" -Rs length) ))" '' \
    | tr ' ' 'x' >> "$f"
  printf '%s' "$f"
}
# The allowance, both sides: a criterion AT it costs nothing, one past it costs one.
serve "$(crit_body "$(cell "$CRITERION_ALLOWANCE")" "$BODY_CEILING")"
expect "a criterion AT the ${CRITERION_ALLOWANCE}-character allowance -> CLEAR" 0 42
F801="$(crit_body "$(cell "$(( CRITERION_ALLOWANCE + 1 ))")" "$BODY_CEILING")"
serve "$F801"
expect "one character past it -> charged that one -> REFUSE" 4 42
says   "  ...printing the number it compared" "is $(( BODY_CEILING + 1 )) characters"

# ONE UNIT. A criterion of 200 em-dashes is 200 characters and 600 bytes; subtracting
# bytes from a code-point count would clear this body. Without jq both terms are bytes.
DASHES="$(printf '%*s' 200 '' | sed 's/ /—/g')"
FDASH="$(crit_body "$DASHES" "$(( BODY_CEILING + 1 ))")"
expect "200 em-dashes of criterion, body one past -> REFUSE" 4 --body-file "$FDASH"
says   "  ...subtracting 200 characters, not 600 bytes" "not counting 200 characters"
touch "$FIX/jq_broken"
expect "…and without jq, bytes from bytes -> still REFUSE" 4 --body-file "$FDASH"
says   "  ...subtracting 600 bytes from a byte count" "not counting 600 characters"
rm -f "$FIX/jq_broken"

# THE CRITERIA TABLE ONLY: a second marked table's first column is the author's text.
TWO="$(body_file '## Description' 'Adds the gate.' '' "$VERIFIED" '' "$(crit_head 2)" '' \
                 "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW" '' '### More' '' \
                 "$TABLE_HEAD" "$TABLE_RULE" "| $(cell 2600) | ✓ | \`foo.test.sh\` 40/0 |")"
expect "a 2,600-character cell in a SECOND marked table -> REFUSE" 4 --body-file "$TWO"

# ONLY WHAT SURVIVES IN THE AUTHORED COPY: a table inside a marked block is already gone
# from the count, so its criterion is not subtracted a second time.
INBLOCK="$(body_file '## Description' "Adds the gate. $(cell 2361)" '' "$VERIFIED" '' \
                     "$(crit_head 1)" '' "$OPEN195" "$TABLE_HEAD" "$TABLE_RULE" \
                     "| $(cell 700) | ✓ | \`foo.test.sh\` 40/0 |" "$CLOSE195")"
expect "a criteria table inside a marked block -> nothing subtracted -> REFUSE" 4 \
       --body-file "$INBLOCK"
says   "  ...one authored character past the ceiling" "is $(( BODY_CEILING + 1 )) characters"
says_not "  ...and no criterion text left out" "not counting"

echo
echo "== the NOTES ceiling: three is the limit, and the fourth is the essay =="
notes_body() { # <n> -> a complete body carrying n claim-first Notes bullets
  local n="$1" i lines=()
  for i in $(seq 1 "$n"); do lines+=("- **Note $i.** A reviewer cannot see this from the diff."); done
  body_file '## Description' 'Adds the gate.' '' "$VERIFIED" '' "$(crit_head 1)" '' \
            "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW" '' '### Notes' '' "${lines[@]}"
}
serve "$(notes_body "$NOTES_CEILING")"
expect "${NOTES_CEILING} claim-first notes -> CLEAR" 0 42
serve "$(notes_body "$(( NOTES_CEILING + 1 ))")"
expect "a fourth note -> REFUSE on length"         4 42
says   "  ...naming the count and the limit"       "carries 4 Notes bullets — over the $NOTES_CEILING"
# Bounded per SECTION, not per body: the notes ceiling must not fire on a body with none.
serve "$(good_body)"
expect "no Notes section at all -> still CLEAR"    0 42

echo
echo "== both ceilings are the measured ones, and they are compared =="
# The constants are pinned HERE as well as in the script, so "somebody rounded it up" is a
# red test and not a diff nobody reads.
ok "the body ceiling is the stated one"            \
   "$(grep -c "^BODY_CEILING_CHARS=$BODY_CEILING\$" "$SCRIPT" || true)" 1
ok "the notes ceiling is the stated one"           \
   "$(grep -c "^NOTES_CEILING=$NOTES_CEILING\$" "$SCRIPT" || true)" 1
# The count reaches exactly ONE comparison. More than one would be a second, unmeasured
# body bound; none would be the old design back with the constant left as decoration.
ok "the body count is compared exactly once"       \
   "$(grep -cE 'chars" -gt "\$BODY_CEILING_CHARS"' "$SCRIPT" || true)" 1
# The ROW classifier still never sees the body's own length: the two bounds stay
# independent, which is what keeps a 12-row table from being refused for its rows' sum.
ok "the row classifier never sees the body count"  \
   "$(sed -n '/^table_scan() {/,/^}/p' "$SCRIPT" | grep -cE 'body_chars|BODY_CEILING' || true)" 0
ok "the classifier compares a row length twice"    \
   "$(grep -cE 'len > ceiling|len < floor' "$SCRIPT" || true)" 2
# The two thresholds are pinned to the measured values HERE as well as in the script, so
# "somebody rounded it up" is a red test and not a diff nobody reads.
ok "the ceiling is the measured one"               \
   "$(grep -c "^CRITERIA_EVIDENCE_CEILING=$ROW_CEILING\$" "$SCRIPT" || true)" 1
ok "the floor is the measured one"                 \
   "$(grep -c "^CRITERIA_EVIDENCE_FLOOR=$ROW_FLOOR\$" "$SCRIPT" || true)" 1

echo
echo "== the ROW bound: the reader #66's two-sided bar never had =="
# THE RULE EXISTED AND NOTHING READ IT. `CONVENTIONS.md` bounded the evidence column on
# both sides on 2026-08-29; ai-bridge#71 breached it the next day with three rows of
# 500-600 characters, inside the machinery built to end unread rules. Everything below
# drives the reader that closes that, at the measured boundaries rather than near them.

row_body() { # <evidence-bytes>... -> a conforming body with one criteria row per argument
  local -a lines
  # The heading's tally is COMPUTED from the argument count, so a case that adds a row
  # cannot accidentally become a case about a tally that no longer matches its table.
  lines=('## Description' 'Adds the gate.' '' "$VERIFIED" '' "$(crit_head "$#")" '' \
         "$TABLE_HEAD" "$TABLE_RULE")
  local n i=0
  for n in "$@"; do
    i=$((i+1))
    lines+=("| criterion number $i | ✓ | $(cell "$n") |")
  done
  body_file "${lines[@]}"
}

serve "$(row_body "$PR67_WORST_CELL")"
expect "#67's largest honest cell ($PR67_WORST_CELL) -> clear" 0 42
serve "$(row_body "$PR70_WORST_CELL")"
expect "#70's largest cell ($PR70_WORST_CELL) -> clear" 0 42
serve "$(row_body "$PR70_SHORTEST_CELL")"
expect "#70's shortest cell ($PR70_SHORTEST_CELL) -> clear" 0 42
# The round-2 case, built as a WHOLE ROW of exactly 264 bytes so the number in the comment
# above is the number under test: criterion text padded out, evidence at #70's own worst
# cell. It must clear with margin, not by a byte.
r2_evidence="$(cell "$PR70_WORST_CELL")"
# The mark is 3 bytes in UTF-8 and `${#var}` counts characters, so the width is computed
# from the parts rather than from a string length that would disagree with the gate.
r2_pad=$(( PR70_R2_WORST_ROW - PR70_WORST_CELL - 23 ))
serve "$(shaped_body 1 0 "$TABLE_HEAD" "$TABLE_RULE" \
                     "| criterion $(cell "$r2_pad") | ✓ | $r2_evidence |")"
r2_row="| criterion $(cell "$r2_pad") | ✓ | $r2_evidence |"
ok "…and the fixture row really is that wide" \
   "$(printf '%s' "$r2_row" | LC_ALL=C wc -c | tr -d ' ')" "$PR70_R2_WORST_ROW"
expect "#70 round-2's worst ROW (${PR70_R2_WORST_ROW}B, cell ${PR70_WORST_CELL}B) -> clear" 0 42
for n in $PR71_BLOATED_CELLS; do
  serve "$(row_body "$n")"
  expect "#71's bloated cell ($n) -> refuse" 3 42
done

# ON the boundary, both sides, so a threshold moved by one goes red here.
serve "$(row_body "$ROW_CEILING")"
expect "exactly the ceiling ($ROW_CEILING) -> clear" 0 42
serve "$(row_body "$((ROW_CEILING + 1))")"
expect "one byte over the ceiling -> refuse" 3 42
serve "$(row_body "$ROW_FLOOR")"
expect "exactly the floor ($ROW_FLOOR) -> clear" 0 42
serve "$(row_body "$((ROW_FLOOR - 1))")"
expect "one byte under the floor -> refuse" 3 42

# THE WHOLE OF #71'S TABLE, in its own row order. This is the regression: not "a long row
# is caught" but "these three rows, and only these three, and by their index".
# shellcheck disable=SC2086
serve "$(row_body $PR71_ROW_CELLS)"
expect "#71's twelve rows -> refuse" 3 42
says   "  ...counting exactly the three that breached" "but 3 acceptance-criteria"
says   "  ...naming row 3 by index and length"  "row 3 over the CEILING at 462 bytes"
says   "  ...naming row 9 by index and length"  "row 9 over the CEILING at 487 bytes"
says   "  ...naming row 10 by index and length" "row 10 over the CEILING at 422 bytes"
says   "  ...and quoting the criterion text"    "criterion number 9"
says_not "  ...while row 1, inside the bound, is not named" "row 1 over"

echo
echo "== the bound is on ONE CELL — not the row, and never the body =="
# A row is criterion text + mark + evidence. The criterion is copied VERBATIM out of the
# task document, so an author cannot shorten it; a bound that charged for it would refuse
# a correct PR for obeying a different rule. #67's worst whole ROW is 489 bytes with a
# 377-byte cell, so this case is the corpus, not a hypothetical.
LONGCRIT="$(cell 600)"
serve "$(shaped_body 1 0 "$TABLE_HEAD" "$TABLE_RULE" \
                     "| $LONGCRIT | ✓ | \`foo.test.sh\` 40/0 |")"
expect "a 600-byte CRITERION with short evidence -> clear" 0 42
# …and the same row with the lengths swapped is the case that must refuse, which is what
# makes the one above a statement about the COLUMN rather than about leniency.
serve "$(shaped_body 1 0 "$TABLE_HEAD" "$TABLE_RULE" \
                     "| a short criterion | ✓ | $LONGCRIT |")"
expect "…the same 600 bytes in the EVIDENCE cell -> refuse" 3 42

echo
echo "== the floor refuses what CONVENTIONS.md names as failing it =="
for evidence in 'ok' 'done' 'see above' 'yes' 'verified'; do
  serve "$(shaped_body 1 0 "$TABLE_HEAD" "$TABLE_RULE" \
                       "| the retry backs off on 429 | ✓ | $evidence |")"
  expect "evidence '$evidence' -> refuse" 3 42
done
says "  ...telling the author what to name instead" "Name the artifact a reader can re-run"
# …and the shortest thing the document offers as REAL evidence clears, so the floor is a
# bound and not a general demand for more words.
for evidence in '`foo.test.sh` 40/0' 'CI run 1234 green' '`shellcheck -x run.sh` clean'; do
  serve "$(shaped_body 1 0 "$TABLE_HEAD" "$TABLE_RULE" \
                       "| the retry backs off on 429 | ✓ | $evidence |")"
  expect "evidence '$evidence' -> clear" 0 42
done

# An EMPTY evidence cell is the one a "skip the mark column" reader would have missed
# entirely: it would take the criterion text as the evidence and clear the single row in
# the table that has no evidence at all.
serve "$(shaped_body 1 0 "$TABLE_HEAD" "$TABLE_RULE" \
                     '| the retry backs off on 429 | ✓ |  |')"
expect "an EMPTY evidence cell -> refuse" 3 42
says   "  ...at length zero, not at the criterion's length" "under the FLOOR at 0 bytes"

# The mark in the last column means the evidence is somewhere this reader does not look,
# and saying that is more useful than measuring a glyph.
serve "$(shaped_body 1 0 '| Criterion | Verified by | ✓ |' "$TABLE_RULE" \
                     '| the retry backs off on 429 | `foo.test.sh` 40/0 | ✓ |')"
expect "the ✓ column LAST -> refuse" 3 42
says   "  ...naming that, rather than measuring the mark" "has NO evidence column"

echo
echo "== the row bound is not a SUM, and the two bounds stay separate =="
# Four rows each AT the row ceiling, in a body under the body ceiling: it clears, because
# nothing adds the cells up. Forty of them is refused for the BODY's length (4) and not
# for its rows (3) — the two bounds answer separately, with separate advice.
# shellcheck disable=SC2046
serve "$(row_body $(for _ in $(seq 4); do printf '%s ' "$ROW_CEILING"; done))"
expect "four rows each AT the row ceiling -> clear" 0 42
# shellcheck disable=SC2046
serve "$(row_body $(for _ in $(seq 40); do printf '%s ' "$ROW_CEILING"; done))"
expect "forty of them -> refused for LENGTH, not for the rows" 4 42
says   "  ...naming the body ceiling"              "over the ${BODY_CEILING}-character ceiling"

# A refusal for a missing element still carries its promise WORD FOR WORD. The row bound
# is a different refusal with a different code, and it must not have edited this one.
serve "$(body_file 'No shape at all here.')"
expect "a shapeless body -> refuse on STRUCTURE" 1 42
says   "  ...naming length as a separate code" \
       "This is the STRUCTURE refusal. Length is a separate check with a"
says   "  ...and it is a DIFFERENT code from the row bound" "MISSING:"

# Untrusted text: the excerpt of a criterion is the one thing from the body this script
# echoes, so an escape sequence in it must not reach the terminal.
ESC="$(printf 'a\033[31mred\033[0m criterion')"
serve "$(shaped_body 1 0 "$TABLE_HEAD" "$TABLE_RULE" "| $ESC | ✓ | ok |")"
expect "a criterion carrying an ANSI escape -> refuse" 3 42
ok "…and the escape does not survive into the message" \
   "$(printf '%s' "$LAST_OUT" | grep -c "$(printf '\033')" || true)" 0
says "  ...while the readable part of it still names the row" "red"

echo
echo "== a missing element is a refusal, and it is named =="
serve "$(body_file 'Adds the gate, and here is a lot of detail about it.' '' \
                   "$VERIFIED" '' "$(crit_head 1)" '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "no TL;DR marker -> refuse" 1 42
says   "  ...naming the TL;DR line as the missing element" "MISSING: the TL;DR line"
says_not "  ...and not blaming the table, which is present" "MISSING: the acceptance-criteria table"

serve "$(body_file '## Description' 'Adds the gate.' '' "$VERIFIED" '' \
                   'Some prose, and no table.')"
expect "no criteria table -> refuse" 1 42
says   "  ...naming the table as the missing element" "MISSING: the acceptance-criteria table"
says_not "  ...and not blaming the TL;DR, which is present" "MISSING: the TL;DR line"

serve "$(body_file 'Just some prose.')"
expect "neither element -> refuse" 1 42
says   "  ...naming the TL;DR line" "MISSING: the TL;DR line"
says   "  ...and the table too"     "MISSING: the acceptance-criteria table"

serve "$(body_file '')"
expect "an EMPTY body -> refuse (readable, not unknown)" 1 42

# A table of changed files is not the criteria table, and the `✓`/`✗` column is exactly
# what tells them apart — the same column SCHEMA.md clause 7 and AUTONOMY.md read.
serve "$(body_file '## Description' 'Adds the gate.' '' "$VERIFIED" '' \
                   '| File | Change |' '|---|---|' '| a.sh | new |')"
expect "a table with no ✓/✗ in it -> refuse" 1 42
says   "  ...saying there is nothing for the merge gate to consult" "nothing for the merge gate to consult"

# GitHub renders NO TABLE when the delimiter row's cell count differs from the header's,
# so a body like this shows the reader a wall of pipes. Refusing it is the safe direction.
serve "$(body_file '## Description' 'Adds the gate.' '' "$VERIFIED" '' \
                   "$TABLE_HEAD" '|---|---|' "$TABLE_ROW")"
expect "a table the host would not render -> refuse" 1 42

serve "$(body_file '## Description' 'Adds the gate.' '' "$VERIFIED" '' \
                   "$TABLE_HEAD" "$TABLE_RULE")"
expect "a table header with no data row -> refuse" 1 42

# An escaped pipe is CONTENT in GFM, and counting it as a cell boundary would refuse a
# table the host renders perfectly — a false "structure missing" on a correct PR, which
# is the failure that gets a gate switched off.
serve "$(shaped_body 1 0 '| Criterion | \| | Verified by |' "$TABLE_RULE" \
                     '| a cell with a \| in it | ✓ | `foo.test.sh` 40/0 |')"
expect "a table whose cells escape a pipe -> clear" 0 42

echo
echo "== every text match fails in the SAFE direction =="
# A false "structure missing" costs a human a glance. A false "structure present" would
# clear a body nobody can read — so the TL;DR patterns are anchored at the start of a
# line, and a sentence that merely MENTIONS the rule does not satisfy it.
serve "$(body_file 'This change follows the TL;DR rule in CONVENTIONS.md closely.' '' \
                   "$VERIFIED" '' "$(crit_head 1)" '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "a mid-sentence mention of TL;DR does not count -> refuse" 1 42

# THREE CASES FROM THE REVIEW OF THIS PR (ai-bridge#65), all in the dangerous direction —
# each one is a body the first cut CLEARED and a human could not have read as shaped.
serve "$(body_file '## Is the TL;DR rule required?' 'Some discussion of it.' '' \
                   "$VERIFIED" '' "$(crit_head 1)" '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "a heading that only MENTIONS TL;DR -> refuse" 1 42
says   "  ...naming the TL;DR line as missing" "MISSING: the TL;DR line"
# …while the heading forms that ARE the marker still clear, so the fix is a narrowing and
# not a break. (`## Description` and `**TL;DR** —` are covered above; this is the bare
# heading.)
serve "$(body_file '## TL;DR' 'Adds the gate.' '' "$VERIFIED" '' "$(crit_head 1)" '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "a bare '## TL;DR' heading -> still clear" 0 42

# `|---|:|` is not a delimiter row: GitHub renders no table at all, so a marked row under
# it is not the criteria table however much it looks like one.
serve "$(body_file '## Description' 'Adds the gate.' '' "$VERIFIED" '' \
                   '| Criterion | ✓ |' '|---|:|' '| it works | ✓ |')"
expect "a delimiter row with a non-delimiter cell -> refuse" 1 42
# …and the alignment colons GFM does allow are still a delimiter row.
serve "$(shaped_body 1 0 "$TABLE_HEAD" '|:---|:---:|---:|' "$TABLE_ROW")"
expect "alignment colons in the delimiter row -> clear" 0 42

echo
echo "== a quoted example is not a body =="
# The one route to a false "structure present": `CONVENTIONS.md`'s example IS a TL;DR line
# above a criteria table, inside a fence. A body that pastes it while saying nothing of
# its own must not clear on the paste.
serve "$(body_file 'Here is the shape CONVENTIONS.md asks for:' '' '```md' \
                   '**TL;DR** — one sentence.' '' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW" \
                   '```' '' 'Anyway, this change does some things.')"
expect "both elements present ONLY inside a code fence -> refuse" 1 42
says   "  ...naming the TL;DR line" "MISSING: the TL;DR line"
says   "  ...and the table too"     "MISSING: the acceptance-criteria table"

# A ``` inside a ````-opened fence is NOT a closer — CommonMark closes a fence only on a
# run of the same character at least as long. A toggle that closed on any fence line let
# the quoted content below it out, which is the same false "structure present" the fence
# stripper exists to prevent.
serve "$(body_file 'Here is the shape, quoted at four backticks:' '' '````md' \
                   '**TL;DR** — one sentence.' '' '```sh' 'echo nested' '```' '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW" '````' '' 'Anyway.')"
expect "a nested fence does not close its outer fence -> refuse" 1 42

# The other half of that: real content OUTSIDE a fence still clears when the body also
# happens to contain a fence. Stripping must not eat the body.
serve "$(shaped_body 1 0 '```sh' 'echo hi' '```' '' \
                     "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "a body with a fence AND real content -> clear" 0 42

echo
echo "== element 4: the Verified line, and the one thing asked of what it says =="
# #3286's lead is followed by exactly one line — "Verified: 277/0 locally, 10/10
# non-deploy checks green on [run 33430116558](...)" — and a reader decides from that one
# line whether to trust the eighteen rows below it. Nothing required it, so nothing had it.
serve "$(body_file '## Description' 'Adds the gate.' '' "$(crit_head 1)" '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "no Verified line -> refuse" 1 42
says   "  ...naming the Verified line as the missing element" "MISSING: the Verified line"
says_not "  ...and not blaming the TL;DR, which is present"   "MISSING: the TL;DR line"
says_not "  ...nor the table, which is present"               "MISSING: the acceptance-criteria table"

# PRESENT AND CITING NOTHING IS A DIFFERENT REFUSAL FROM ABSENT, because the fix is
# different: one line has to be written, the other has to gain a link. Telling an author
# who wrote the line that it is missing sends them looking for what they already did.
serve "$(body_file '## Description' 'Adds the gate.' '' \
                   'Verified: 40/0 locally, and every check is green.' '' "$(crit_head 1)" '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "a Verified line citing nothing -> refuse" 1 42
says   "  ...saying it cites nothing, not that it is absent" "INCOMPLETE: the Verified line cites nothing"
says_not "  ...and not calling it missing"                   "MISSING: the Verified line"

# WHAT IT CLAIMS IS NOT CHECKED AND MUST NOT BE. All three of these are unverifiable
# assertions about test counts; all three clear, because each cites something a reader can
# open, and that is the whole of the requirement.
for cite in 'Verified: 40/0 on [run 1](https://example.invalid/runs/1).' \
            'Verified: 40/0, CI green — https://example.invalid/actions/runs/1' \
            '**Verified:** 40/0 on [run 1](https://example.invalid/runs/1).'; do
  serve "$(body_file '## Description' 'Adds the gate.' '' "$cite" '' "$(crit_head 1)" '' \
                     "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
  expect "a Verified line citing something -> clear" 0 42
done
# A `### Verified` HEADING IS NOT THIS ELEMENT, and that is the narrow direction on
# purpose: the element is ONE LINE carrying the counts and the link, and accepting a
# heading would mean deciding how many lines below it the citation may sit. The author
# whose Verified line has grown into a section still writes the one line.
serve "$(body_file '## Description' 'Adds the gate.' '' '### Verified' \
                   '40/0 on [run 1](https://example.invalid/runs/1).' '' "$(crit_head 1)" '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "a '### Verified' SECTION is not the one line -> refuse" 1 42
says   "  ...naming the Verified line as missing" "MISSING: the Verified line"

# ANCHORED, exactly as the TL;DR markers are, and failing toward refusal for the same
# reason: a body that DISCUSSES the Verified line must not clear on the discussion.
serve "$(body_file '## Description' 'Adds the gate.' '' \
                   'Everything here was verified: see https://example.invalid/runs/1.' '' \
                   "$(crit_head 1)" '' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "a mid-sentence 'verified:' does not count -> refuse" 1 42
says   "  ...naming the Verified line as missing" "MISSING: the Verified line"

echo
echo "== element 5: the tally is CHECKED AGAINST the table, not merely required =="
# The single most valuable element of #3286, and the one a reader pays most for when it is
# absent: `### Criteria (10 ✓ / 8 ✗ — every ✗ is a later slice or task-001)`. SCHEMA.md
# clause 7 makes an unverified criterion block clearance, so eight ✗ look alarming until
# the heading says every one is deferred by design — otherwise a reader reconstructs that
# from eighteen rows before they can decide anything.
# NO HEADING ANYWHERE ABOVE THE TABLE — the bold TL;DR spelling, which leaves the body
# without an ATX heading at all, so there is nowhere a tally could be.
serve "$(body_file '**TL;DR** — adds the gate.' '' "$VERIFIED" '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "no heading over the criteria table -> refuse" 1 42
says   "  ...saying the table carries no tally" "MISSING: a heading over the criteria table"

# …and with the house heading present but no `### Criteria` one, the nearest heading above
# the table is `## Description`, which is a heading carrying no tally. Same
# refusal, different sentence, because the fix is different.
serve "$(body_file '## Description' 'Adds the gate.' '' "$VERIFIED" '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "the lead heading is the nearest one, and it has no tally -> refuse" 1 42
says   "  ...asking for the tally on it" "MISSING: the tally on the criteria heading"

serve "$(body_file '## Description' 'Adds the gate.' '' "$VERIFIED" '' \
                   '### Criteria' '' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "a heading with no tally -> refuse" 1 42
says   "  ...naming the tally as the missing part" "MISSING: the tally on the criteria heading"
says   "  ...and quoting the heading it read"      "Criteria"

# A TALLY NOBODY CHECKS IS WORSE THAN NO TALLY, because it is the one number a reader
# takes on trust and never re-derives. Both directions, one row apart.
serve "$(body_file '## Description' 'Adds the gate.' '' "$VERIFIED" '' \
                   '### Criteria (2 ✓ / 0 ✗)' '' "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "a tally claiming one ✓ too many -> refuse" 1 42
says   "  ...naming what it claims and what the table has" "claims 2 ✓ / 0 ✗"
says   "  ...and the actual counts"                        "carries 1 ✓ / 0 ✗"

serve "$(body_file '## Description' 'Adds the gate.' '' "$VERIFIED" '' \
                   '### Criteria (1 ✓ / 1 ✗ — the ✗ needs a human)' '' \
                   "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW")"
expect "a tally claiming a ✗ the table does not have -> refuse" 1 42
says   "  ...naming both sides" "carries 1 ✓ / 0 ✗"

# …and the tally that AGREES clears, in both mixes, so the check is a comparison and not a
# demand for a particular number.
serve "$(shaped_body 2 1 "$TABLE_HEAD" "$TABLE_RULE" \
                     '| a | ✓ | `a.test.sh` 40/0 |' '| b | ✓ | `b.test.sh` 12/0 |' \
                     '| c | ✗ | needs two host accounts |')"
expect "a tally that matches a 2 ✓ / 1 ✗ table -> clear" 0 42

# The mark column is read the way the merge gate reads it, so a decorated mark still
# counts — a body that bolds or code-spans its glyphs is not a body with no tally.
serve "$(shaped_body 1 1 "$TABLE_HEAD" "$TABLE_RULE" \
                     '| a | **✓** | `a.test.sh` 40/0 |' '| b | `✗` | needs a human |')"
expect "bolded and code-spanned marks still count -> clear" 0 42

# THE REASON, AND ONLY WHEN THERE ARE ✗. A bare `(0 ✓ / 1 ✗)` is exactly the alarming
# artifact this element exists to prevent.
serve "$(body_file '## Description' 'Adds the gate.' '' "$VERIFIED" '' \
                   '### Criteria (0 ✓ / 1 ✗)' '' "$TABLE_HEAD" "$TABLE_RULE" \
                   '| works with two host accounts | ✗ | needs two accounts |')"
expect "a ✗ tally with no reason -> refuse" 1 42
says   "  ...asking for the reason, not for the tally" "MISSING: the reason for the 1 ✗"
says_not "  ...and not claiming the tally is wrong"    "WRONG: the criteria heading"

# A heading that closes on punctuation is still bare — the reason has to be words.
serve "$(body_file '## Description' 'Adds the gate.' '' "$VERIFIED" '' \
                   '### Criteria (0 ✓ / 1 ✗ —)' '' "$TABLE_HEAD" "$TABLE_RULE" \
                   '| works with two host accounts | ✗ | needs two accounts |')"
expect "a dash where the reason should be -> refuse" 1 42
says   "  ...still asking for the reason" "MISSING: the reason for the 1 ✗"

# …while a tally with NO ✗ needs no reason, because there is nothing to explain. Demanding
# one there would be noise on every fully-verified PR.
serve "$(good_body)"
expect "a 1 ✓ / 0 ✗ tally with no reason -> clear" 0 42

echo
echo "== element 6: ### Notes is OPTIONAL, and its bullets lead with the claim =="
# A small PR needs no notes and NO NUMBER OF NOTES IS EVER REQUIRED — `good_body` above
# has none and clears. What is checked is the shape of the ones that are there: each opens
# with a bolded sentence that IS the finding, so the section is skimmable in bold alone.
NOTE_BOLD='- **A grep-derived inventory would have been short by 8.** `emails.ts` has a NUL byte.'
NOTE_BARE='- A grep-derived inventory would have been short by 8; `emails.ts` has a NUL byte.'

serve "$(shaped_body 1 0 "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW" '' '### Notes' '' "$NOTE_BOLD")"
expect "one claim-first note -> clear" 0 42
serve "$(shaped_body 1 0 "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW" '' '### Notes' '' \
                     "$NOTE_BOLD" '- **The environment axis is a deployment property.**' \
                     '- **Deny-by-default lives at registration.** The server does not boot.')"
expect "three claim-first notes -> clear (no number is required)" 0 42

serve "$(shaped_body 1 0 "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW" '' '### Notes' '' "$NOTE_BARE")"
expect "a note that buries its claim -> refuse" 1 42
says   "  ...naming the note by index"    "note 1:"
says   "  ...and quoting enough to find it" "A grep-derived inventory"
says_not "  ...while not calling the section missing" "MISSING: the acceptance-criteria table"

serve "$(shaped_body 1 0 "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW" '' '### Notes' '' \
                     "$NOTE_BOLD" "$NOTE_BARE")"
expect "one bold note and one bare -> refuse on the bare one" 1 42
says   "  ...naming the second, not the first" "note 2:"

# COLUMN ZERO ONLY. A correctly-nested sub-item is indented by at least two spaces, and
# refusing one would be a false refusal on correct work — the failure that gets a gate
# switched off.
serve "$(shaped_body 1 0 "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW" '' '### Notes' '' \
                     "$NOTE_BOLD" '  - the NUL byte makes grep call the file binary')"
expect "a nested sub-bullet under a claim-first note -> clear" 0 42

# THE HEADING DEPTH IS NOT SIGNIFICANT, and that is not a nicety: `CONVENTIONS.md` writes
# `## Notes` in its prose while #3286 — the worked example the same document names — writes
# `### Notes`. A reader pinned to either depth would silently stop checking one of them.
serve "$(shaped_body 1 0 "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW" '' '## Notes' '' "$NOTE_BARE")"
expect "a bare bullet under '## Notes' -> refuse, same as under '### Notes'" 1 42
says   "  ...naming the note"    "note 1:"
serve "$(shaped_body 1 0 "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW" '' '## Notes' '' "$NOTE_BOLD")"
expect "…and a claim-first bullet under '## Notes' -> clear" 0 42

# …while a heading that merely BEGINS with the word is a different section, which is the
# narrow direction: wrong toward clearing a section that was optional anyway.
serve "$(shaped_body 1 0 "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW" '' \
                     '### Notes for the reviewer' '' "$NOTE_BARE")"
expect "'### Notes for the reviewer' is not the Notes section -> clear" 0 42

# …and a bullet OUTSIDE the section is not a note. The section ends at the next heading.
serve "$(shaped_body 1 0 "$TABLE_HEAD" "$TABLE_RULE" "$TABLE_ROW" '' '### Notes' '' \
                     "$NOTE_BOLD" '' '### Follow-ups' '' '- split the emails slice out')"
expect "a bullet under the NEXT heading is not a note -> clear" 0 42

echo
echo "== the exemplar the owner named: alteos-gmbh/monorepo#3286 =="
# "This one looks perfect." It is captured VERBATIM as a fixture rather than re-fetched,
# for the reason the row corpus is pinned: a live PR body is not a fixture, and a gate
# calibrated against something anyone can edit has no baseline. Every new element above
# was derived from this body, so this is the case that says the derivation was faithful.
EXEMPLAR="$(cd "$(dirname "$0")" && pwd)/fixtures/pr-body/alteos-monorepo-3286.md"
EXEMPLAR_CHARS=3554        # the body itself; the fixture adds the trailing newline
EXEMPLAR_CHECK=10          # its tally, and its table:  10 ✓
EXEMPLAR_CROSS=8           #                             8 ✗ over 18 rows
ok "the fixture is there"  "$([ -r "$EXEMPLAR" ] && echo yes || echo no)" yes
ok "…verbatim, to the character" "$(( $(chars "$EXEMPLAR") - 1 ))" "$EXEMPLAR_CHARS"
ok "…and its table really is ${EXEMPLAR_CHECK} ✓ / ${EXEMPLAR_CROSS} ✗" \
   "$(grep -c '| ✓ |' "$EXEMPLAR") $(grep -c '| ✗ |' "$EXEMPLAR")" \
   "$EXEMPLAR_CHECK $EXEMPLAR_CROSS"
ok "…under a heading claiming exactly that" \
   "$(grep -c "^### Criteria ($EXEMPLAR_CHECK ✓ / $EXEMPLAR_CROSS ✗ — " "$EXEMPLAR")" 1

# NOT ONE OF THE THREE NEW CHECKS FIRES ON IT. `decide` runs every structural check before
# it prints, so these are statements that each check RAN and PASSED — not that an earlier
# refusal hid them.
expect "the exemplar, verbatim, through the whole reader" 1 --body-file "$EXEMPLAR"
says_not "  element 4: its Verified line is accepted"   "MISSING: the Verified line"
says_not "  …and accepted as citing something"          "INCOMPLETE: the Verified line"
says_not "  element 5: its heading tally is accepted"   "MISSING: the tally on the criteria heading"
says_not "  …and agrees with its own eighteen rows"     "WRONG: the criteria heading"
says_not "  …and its eight ✗ are explained"             "MISSING: the reason for the"
says_not "  element 6: its notes all lead with a claim"  "MISSING: the bold claim opening"
says_not "  …and its criteria table is well-formed"     "MISSING: the acceptance-criteria table"

# WHAT IT IS REFUSED FOR IS TWO RULES THAT ARE OLDER THAN THIS CHANGE AND ARE NOT ITS
# SUBJECT, and #3286 is a pull request in ANOTHER repository with its own house style. Both
# are pinned here so the day either moves, this goes red and somebody decides it on purpose
# rather than discovering it:
#   1. `CONVENTIONS.md` requires the literal heading `## Description` opening every
#      body — "that exact string, character for character". #3286 opens with its TL;DR
#      SENTENCE and no heading, so element 1 refuses it.
says "  what it is refused for: the loopd TL;DR heading" "MISSING: the TL;DR line"

#   2. Two of its evidence cells are under the measured 13-byte floor — `see Notes` (9)
#      and `binary slice` (12). `see above` (9) is the longest thing CONVENTIONS.md names
#      as a floor FAILURE, so this is the floor working, not the floor misfiring.
EXEMPLAR_HOUSED="$TMP/exemplar-housed.md"
{ printf '%s\n\n' '## Description'; cat "$EXEMPLAR"; } > "$EXEMPLAR_HOUSED"
expect "…the same body under the loopd heading -> the ROW bound, and only it" \
       3 --body-file "$EXEMPLAR_HOUSED"
says   "  naming both cells under the floor"  "but 2 acceptance-criteria"
says   "  row 11, 'binary slice'"             "row 11 under the FLOOR at 12 bytes"
says   "  row 16, 'see Notes'"                "row 16 under the FLOOR at 9 bytes"
says_not "  and nothing structural is wrong with it" "MISSING:"

echo
echo "== unreadable is never clearance =="
serve "$(good_body)"
: > "$FIX/gh_broken"
expect "the PR cannot be fetched -> unknown, not clear" 2 42
says   "  ...saying unknown is never clearance" "unknown is never clearance"

serve "$(good_body)"
rm -f "$FIX/pr_json"
expect "no PR at all -> unknown, not clear" 2 42

# A body field the host did not send is not an empty body: one is a read that did not
# answer, the other is a PR somebody left blank, and only the second is the author's fault.
"$REAL_JQ" -n --arg h "$HEAD_SHA" \
  '{url:"https://github.com/acme/widgets/pull/42", number:42, headRefOid:$h}' > "$FIX/pr_json"
expect "no body FIELD -> unknown, not an empty body" 2 42
says   "  ...saying so in those words" "unknown rather than"

serve "$(good_body)"
: > "$FIX/jq_broken"
expect "the JSON reader cannot answer -> unknown, not clear" 2 42
rm -f "$FIX/jq_broken"

serve "$(good_body)"
expect "a head that moved under the caller -> unknown, not clear" 2 42 --head "$OTHER_SHA"
says   "  ...saying the body read is not the one verified" "not the one that was verified"

serve "$(good_body)"
expect "the caller's head still matches -> clear" 0 42 --head "$HEAD_SHA"

echo
echo "== --body-file: the same verdict, before the PR is opened =="
GOOD="$(good_body)"
BAD="$(body_file 'No shape at all here.')"
expect "a conforming draft -> clear" 0 --body-file "$GOOD"
says   "  ...and reports its length against the ceiling" "characters (ceiling $BODY_CEILING)"
expect "a draft with no shape -> refuse" 1 --body-file "$BAD"
expect "a draft that does not exist -> unknown, not clear" 2 --body-file "$TMP/nope.md"
expect "--body-file with a PR number too -> usage error" 2 --body-file "$GOOD" 42

echo
echo "== usage =="
rc=0; "$SCRIPT" >/dev/null 2>&1 || rc=$?
ok "no arguments -> usage error"   "$rc" 2
serve "$GOOD"
expect "an unknown option -> usage error" 2 42 --nope

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
