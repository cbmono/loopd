#!/usr/bin/env bash
#
# pr-body-clearance.sh — assert that a pull request's BODY carries the required SHAPE:
# a TL;DR line, a `Verified:` line that cites something, and a well-formed
# acceptance-criteria table under a heading whose tally matches it, with every row inside
# the two-sided bound `CONVENTIONS.md` puts on their evidence. This is precondition 3 of
# the delegated merge gate (`AUTONOMY.md` → "Merge under `yolo`"). `required-checks.sh` is
# precondition 1 and calls in here for every PR it is about to clear, exactly as it calls
# `review-clearance.sh`.
#
#   Usage: pr-body-clearance.sh <pr> [--repo <owner>/<name>] [--head <sha>]
#          pr-body-clearance.sh --body-file <path>   (decide on a local draft)
#          pr-body-clearance.sh --self-test          (prove this script RUNS)
#
# WHY THIS EXISTS — `CONVENTIONS.md` has required a short, shaped PR body since the rule
# merged at 14:59 UTC on 2026-08-29. FIVE HOURS LATER an agent that had that rule — the
# document is seeded into its instance and its own agent file references it — opened a
# 14,673-character description. The rule was present, reachable and referenced, and it was
# not followed, because the short form's only reader was `tests/pr-body-shape.test.sh`,
# which asserts THE RULE IS NAMED IN THE DOCUMENT. That is a reader for the documentation,
# not for the thing the rule governs. Nothing read a PR body. This file is that reader.
#
# IT NOW REFUSES ON LENGTH TOO, AND THAT REVERSES THIS FILE'S ORIGINAL DESIGN. Until
# 2026-09-06 the body's character count was computed, printed and never compared, on the
# argument that a large change honestly needs words. The owner's verdict that day settled
# it the other way — bodies #122 and #135 ran 5,826 and 6,423 characters — and
# `CONVENTIONS.md` -> "Write less" is now the rule: 2,500 characters, at most 3 `## Notes`
# bullets. Refused at EXIT 4, its own code, because the fix is "move the reasoning to the
# task doc", not "add the missing element" (1) or "say what to run" (3).
#
# THE TEXT-MATCHED ELEMENTS, AND WHICH DIRECTION EACH MATCH FAILS IN. Text matching
# is unavoidable
# here — a PR body is prose — so it is arranged the way `review-clearance.sh` arranges its
# refusal detection: EVERY MATCH FAILS CLOSED. A false "structure missing" sends a human
# to look at a well-formed PR and costs a glance; a false "structure present" would clear
# a body nobody can read. Both tests below are therefore narrow, and both are computed on
# a rendering with FENCED CODE BLOCKS REMOVED — otherwise a body that merely QUOTES
# `CONVENTIONS.md`'s example (which is a fenced TL;DR line above a fenced table) would
# clear on the example rather than on its own content, which is the one false positive
# this file could plausibly have had.
#
#   1. A TL;DR MARKER LINE. Matched only where the marker LEADS THE LINE'S OWN CONTENT —
#      as the text of an ATX heading, as a CLOSED leading bold/italic run, or as a bare
#      token followed by a separator. Neither a sentence that mentions "the TL;DR rule"
#      mid-paragraph NOR a heading that merely contains the token (`## Is the TL;DR rule
#      required?`) matches: the first cut anchored the heading row at the `#` and then
#      allowed anything before the token, which cleared exactly that heading. The failure
#      is toward refusal. THE MARKER IS DELIBERATELY SPELLED SEVERAL WAYS BECAUSE THE
#      RULE ITSELF MOVES: `CONVENTIONS.md` requires the heading `## Description` today,
#      and the `(TL;DR)` suffix it carried until 2026-09-06 still clears FOR ONE RELEASE
#      with a one-line deprecation notice. A gate that pinned one spelling exclusively
#      would refuse correct pull requests opened before the rename landed — and a gate
#      that refuses correct work is a gate somebody switches off.
#
#   2. THE ACCEPTANCE-CRITERIA TABLE — THE SAME ARTIFACT THE MERGE GATE ALREADY READS.
#      `SCHEMA.md` clause 7 and `AUTONOMY.md` precondition 3 consume the `✓`/`✗` table in
#      the PR body; this file does not introduce a second format, it requires that one.
#      WELL-FORMED IS ASSERTED THE WAY THE HOST DEFINES IT: a header row, a delimiter row
#      with the SAME NUMBER OF CELLS (GitHub renders no table at all when those differ,
#      and a table that does not render is not a table a human can read), and at least one
#      data row. Plus one identifying property — at least one data row carries a `✓` or a
#      `✗` — so that a table of changed files is not mistaken for the criteria table. A
#      body whose marks are spelled some other way (`[x]`, "yes") is REFUSED, which is
#      again the safe direction: a glance, not a clearance.
#
#   3. THE TWO-SIDED BOUND ON EACH CRITERIA ROW'S EVIDENCE CELL — MEASURED, NOT MATCHED.
#      `CONVENTIONS.md` has bounded that cell on both sides since 2026-08-29: a ceiling
#      ("a row carries what a reviewer needs to CHECK THE CLAIM, and stops — narration is
#      not wanted") and a floor ("short is the goal; cryptic is a failure"). NOTHING READ
#      IT, and a day later ai-bridge#71 shipped criteria rows of 500-600 characters whose
#      evidence column carried shell one-liners and their own reasoning — inside the very
#      machinery built to end unread rules. This element is that reader.
#
#      THE CELL, NOT THE ROW. A row also carries the criterion text VERBATIM from the
#      task document, which its author may not shorten; charging that against a bound
#      would punish an author for obeying a different rule. Whole-row length is also
#      empirically useless here: at 2026-08-30T16:00Z the worst whole ROW of #70 (577
#      bytes) and of #71 (588) were eleven bytes apart, while their evidence cells were
#      325 and 487.
#
#      THE CORPUS, re-read at 2026-08-30T16:24Z — every row of the acceptance-criteria
#      table of three real pull requests, 34 rows, bytes under LC_ALL=C:
#
#          PR              rows   evidence cell                 verdict wanted
#          #67 (merged)     11    92 .. 377                     pass
#          #70 (open)       11    19 .. 189                     pass
#          #71 (open)       12    160 .. 341, then 422/462/487  fail (exactly those 3)
#
#      CEILING 400 BYTES — the midpoint of the empty band 378-421, which is the widest
#      gap in the corpus. It leaves 23 bytes over the largest honest cell and stops 22
#      short of the smallest offending one, and it fails EXACTLY the three rows the
#      incident names and no other row of the 34. FLOOR 13 BYTES — the midpoint of 9 and
#      17, likewise measured: `see above` (9) is the longest thing `CONVENTIONS.md` names
#      as a floor FAILURE, and `CI run 1234 green` (17) is the shortest thing it offers
#      as real evidence, with the corpus bottoming out at 19. Both numbers therefore have
#      a margin on each side rather than sitting on an observation, and neither was
#      chosen for being round.
#
#      THE STRONGEST SINGLE CASE FOR 400 IS #70'S ROUND-2 BODY, because it was rewritten
#      to this house style AFTER the style was written and it is complete on all 11
#      criteria: longest whole ROW 264 bytes, longest evidence CELL 189. A recent,
#      fully-evidenced body sits at less than half the ceiling that catches #71 — so this
#      bound refuses bloat and not thoroughness, and a ceiling that could not clear that
#      body would be set too tight. `tests/pr-body-clearance.test.sh` drives that exact
#      row rather than leaving the claim in a PR body nobody can re-run.
#
#      A LIVE PR BODY IS NOT A FIXTURE — #70's moved under the measurement (325 then 189),
#      so the four boundary values are pinned in `tests/pr-body-clearance.test.sh`.
#
#      IT IS COUNTED IN BYTES, UNDER `LC_ALL=C`, ON PURPOSE. `length()` counts characters
#      in some awks and bytes in others, so an unpinned locale would put the threshold in
#      a different place on a developer's macOS than on CI — a gate whose verdict depends
#      on the machine is not a gate. Bytes are the reproducible unit; the numbers above
#      were measured the same way.
#
#      BOTH SIDES FAIL LOUDLY AND NAME THE ROW. A bare exit code sends the author back to
#      diff their own table against a threshold; the refusal below prints, per offending
#      row, its index, its measured length, the bound it broke and a bounded excerpt of
#      its criterion text.
#
#   4. THE `Verified:` LINE, AND THE ONE THING REQUIRED OF WHAT IT SAYS: THAT IT CITES
#      SOMETHING. The owner named alteos-gmbh/monorepo#3286 as the shape every PR body
#      should have, and its lead is followed by exactly one line — "Verified: 277/0
#      locally, 10/10 non-deploy checks green on [run 33430116558](...)". A reader learns
#      from that one line whether to trust the eighteen rows below it. Elements 1-3 did
#      not require it, so nothing carried it.
#
#      MATCHED THE WAY THE TL;DR MARKER IS MATCHED, and for the same reason: anchored at
#      the start of a line and leading the line's own content, so a sentence that MENTIONS
#      the Verified line does not satisfy it and the failure is toward refusal. Two
#      spellings — a bare `Verified: …` and a leading `**Verified:**`.
#
#      A `### Verified` HEADING IS DELIBERATELY NOT ONE OF THEM. This element is ONE LINE
#      carrying the counts and the link; a heading is the start of a SECTION, whose link
#      would sit on some other line, and accepting it would mean deciding how far below a
#      heading the citation may be. There is no honest answer to that, and the element it
#      would be checking is not the element #3286 has. An author whose Verified line has
#      grown into a section still writes the one line.
#
#      WHAT IT CLAIMS IS THE AUTHOR'S BUSINESS; THAT IT CITES SOMETHING IS THIS GATE'S.
#      The line must carry at least one LINK — a markdown `[text](url)` or a bare
#      `http(s)://` — because "all green" with nothing to open is the same assertion
#      without evidence that the row FLOOR already refuses one column over. This file
#      cannot and must not check whether 277/0 is true; it can check that a reader has
#      somewhere to go and find out, and that is the whole of the requirement. A line
#      present without a link is therefore a DIFFERENT refusal from a line absent, because
#      the fix is different.
#
#   5. THE CRITERIA HEADING'S TALLY, AND — WHEN IT HAS ANY `✗` — THE REASON FOR THEM.
#      This is the single most valuable element of #3286 and the one that costs a reader
#      the most when it is missing. `### Criteria (10 ✓ / 8 ✗ — every ✗ is a later slice
#      or task-001)`. `SCHEMA.md` clause 7 makes an unverified criterion BLOCK clearance,
#      so a table carrying eight `✗` looks alarming until the heading explains that every
#      one of them is deferred by design — and without the heading a reader has to
#      reconstruct that from eighteen rows before they can decide anything.
#
#      THE TALLY IS CHECKED AGAINST THE TABLE, NOT MERELY REQUIRED TO EXIST. A heading
#      claiming 10 `✓` over a table carrying 9 is a defect — the number is the first thing
#      a reader takes and the last thing anyone re-derives — so the rows are counted here
#      and the two are compared. That comparison is on COUNTS OF ROWS, which is not a
#      length and is not the body: see the length paragraphs above, which this element
#      does not touch.
#
#      THE REASON IS REQUIRED ONLY WHEN `M > 0`, and only that it is THERE. A tally with
#      no `✗` needs no explanation and demanding one would be noise. When there are `✗`s,
#      a bare `(10 ✓ / 8 ✗)` is exactly the alarming artifact this element exists to
#      prevent, so the heading must carry text after the tally. Whether the reason is a
#      GOOD one is the reviewer's judgement and is deliberately not decided here — the
#      same division as element 4.
#
#   6. `### Notes` IS OPTIONAL, AND ITS BULLETS LEAD WITH THE CLAIM. A small PR needs no
#      notes at all and a body without the section clears; NO NUMBER OF NOTES IS EVER
#      REQUIRED. But #3286's notes are readable because each bullet opens with a bolded
#      sentence that IS the finding — "**A grep-derived inventory would have been short by
#      8 and looked complete.**" — with the explanation after it, so the section is
#      skimmable in bold alone. That shape is checkable and the finding itself is not, so
#      that shape is what is checked.
#
#      ONLY BULLETS AT COLUMN ZERO COUNT. A GFM sub-item under a bullet at column 0 is
#      indented by at least two spaces, so restricting the check to unindented list
#      markers excludes children exactly, rather than by a guess at how far they are
#      indented — and refusing a correctly-nested sub-bullet would be a false refusal on
#      correct work, which is the failure that gets a gate switched off. The section is
#      recognised only where the heading TEXT is exactly `Notes`, for the same reason:
#      narrow, and wrong toward clearing an oddly-named section that was optional anyway.
#      ITS DEPTH IS NOT SIGNIFICANT — `## Notes` and `### Notes` are the same section to
#      this reader. `CONVENTIONS.md` writes `## Notes` in its prose and #3286 writes
#      `### Notes`; pinning either depth would refuse one of the two documents this file
#      exists to enforce.
#
# WHAT THIS DOES NOT DO, AND WHOSE JOB THAT IS. It answers "is the criteria table there
# and well-formed", never "is every row `✓`". WHETHER EVERY ROW IS `✓` STAYS
# `AUTONOMY.md` PRECONDITION 3 / `SCHEMA.md` CLAUSE 7 — an unverified criterion blocking
# clearance is an existing gate with an existing reader, and duplicating it here would
# give the repo two answers to one question. This file closes the gap that nothing read
# the body's SHAPE at all.
#
# GENERIC PLUGIN FILE — ships inside the `loopd` plugin; nothing to edit per
# instance. It takes no org, repo or vendor identity: those come from the arguments.
#
# Exit codes — 0 is the ONLY clearance; every other code is a refusal:
#
#   0  the body carries a TL;DR marker, a `Verified:` line citing at least one link, and
#      a well-formed criteria table under a heading whose tally matches its rows and
#      explains any `✗`, whose every row is inside the evidence bound, with `### Notes`
#      either absent or claim-first, inside the concision ceilings below
#   1  the body is readable and a required element is MISSING, INCOMPLETE or CONTRADICTED
#      BY THE TABLE. stderr names every one of them — the TL;DR line, the `Verified:`
#      line (absent, or present and citing nothing), the criteria table, its heading's
#      tally (absent, disagreeing with the rows, or leaving `✗`s unexplained), and any
#      `### Notes` bullet that does not lead with its claim
#   2  usage error, or the environment cannot answer (no `gh`/`jq`, an unreadable PR, an
#      unreadable body file, a pattern table that will not compile, or a `--head` that no
#      longer matches the PR) — UNKNOWN, and unknown is never clearance
#   3  the shape is all there, but at least one criteria row's evidence cell is outside
#      the two-sided bound. stderr names every offending row. A SEPARATE CODE because the
#      fix is different — 1 says "add the missing thing", 3 says "move the reasoning to
#      the task doc" or "say what to run" — and callers that already treat any non-zero
#      as a refusal (`required-checks.sh`) need no change to honour it
#   4  every element is present and every row is inside its bound, but the body is over
#      2,500 characters or carries more than 3 `## Notes` bullets. Its own code for its
#      own fix: relocate, do not add
#
# FAILS CLOSED. A body this script cannot fetch is not an empty body: reading a transient
# 5xx as "no body" would be a refusal today and a clearance the moment anything downstream
# treated one of these codes as benign, so the fetch refuses at exit 2 rather than
# proceeding with an empty string.
#
# WHAT IT PRINTS IS UNTRUSTED TEXT. The body comes from a pull request, which anyone able
# to open one can write. Nothing from it is echoed back except the names of the elements
# that were missing and, for a row outside the bound, an EXCERPT of that row's criterion
# text — reduced to printable ASCII (every other byte becomes `.`, which under `LC_ALL=C`
# also removes every control byte and so every terminal escape) and truncated to 60 bytes.
# No part of the body is an input to anything but the two matches and the one measurement
# above.
#
# AND A TRUNCATED COPY OF THIS FILE IS UNKNOWN STATE TOO — the sibling's lesson, taken
# whole: `--self-test` proves this file RUNS, which is not proving it is COMPLETE. A copy
# cut off below the self-test block still runs and still prints the sentinel. The last
# line of this file is therefore a completeness sentinel, asserted by `--self-test`, which
# no cut short of the end can satisfy.
#
# No `set -e`: a `grep` that finds nothing is an ANSWER here, not a fault, and under `-e`
# the first such test would exit the script with a success-looking code. Every failure
# path below is explicit.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

# --- table 1: what a TL;DR marker line looks like -----------------------------
# One POSIX ERE per line, matched case-insensitively against the fence-stripped body.
# Blank lines and whole-line `#` comments are ignored; a pattern may not carry a trailing
# comment, because the whole line is the pattern. Same reading rules as the sibling's
# tables, and — like them — every row is compiled up front by `validate_tables`, because
# a table that will not compile is not a table that matches less, it is a table that
# matches NOTHING, and here that turns every PR into a refusal nobody can explain.
#
# EVERY ROW IS ANCHORED AT THE START OF A LINE. That anchor is the fail-closed property:
# without it, a body that discusses the TL;DR rule in a sentence would clear on the
# discussion. Row 1 is the heading `CONVENTIONS.md` requires today, matched as the WHOLE
# heading text — trailing `#`s and all, since a closed ATX heading is one the host renders
# — so `## Description of the parser` does not clear; row 2 is the same heading
# with the retired `(TL;DR)` suffix, plus the bare `## TL;DR` spelling; row 3 is the
# leading-emphasis form `**TL;DR** — …`; row 4 is the bare token followed by a separator,
# which is what an author writes when they are not looking at any document.
TLDR_MARKERS='
^[[:space:]]{0,3}#{1,6}[[:space:]]+description[[:space:]]*(#+[[:space:]]*)?$
^[[:space:]]{0,3}#{1,6}[[:space:]]+(description[[:space:]]*)?\(?tl[;:/ ]?dr
^[[:space:]]{0,3}(\*\*|__|\*|_)[[:space:]]*(description[[:space:]]*)?\(?tl[;:/ ]?dr\)?[[:space:]]*(\*\*|__|\*|_)
^[[:space:]]{0,3}\(?tl[;:/ ]?dr\)?[[:space:]]*[]):：.,;—–-]
'

# --- table 1a: the RETIRED heading spelling, kept for one release --------------
# A strict subset of table 1, read the same way. It decides nothing — a body matching it
# has already cleared element 1 — it only earns the one-line deprecation notice below, so
# an author who opened a pull request before the rename is told rather than refused.
DEPRECATED_TLDR_MARKERS='
^[[:space:]]{0,3}#{1,6}[[:space:]]+description[[:space:]]*\(?tl[;:/ ]?dr
'

# --- table 2: the marks that identify the ACCEPTANCE-CRITERIA table ------------
# Fixed strings, not EREs — these are the two glyphs `SCHEMA.md` clause 7 and
# `AUTONOMY.md` precondition 3 already read, and this file requires that same artifact
# rather than inventing a second one. A data row carrying one of them is what tells the
# criteria table apart from any other table in a body.
#
# THEY ARE NAMED SEPARATELY AS WELL AS TABLED, because element 5 has to tell them APART:
# `has_mark` only asks whether a row is a criteria row, while the tally asks how many rows
# are verified and how many are not. Deriving "which glyph is which" from the table's row
# ORDER would put a silent dependency on a list anyone may reorder, so each glyph is a
# named constant and the table is built from the two.
CRITERIA_MARK_VERIFIED='✓'
CRITERIA_MARK_UNVERIFIED='✗'
CRITERIA_MARKS="$CRITERIA_MARK_VERIFIED
$CRITERIA_MARK_UNVERIFIED"

# --- table 4: what a `Verified:` marker line looks like ------------------------
# One POSIX ERE per line, read exactly as table 1 is read and anchored for exactly the
# same reason: without the anchor, a body that DISCUSSES the Verified line would clear on
# the discussion, and the fail-closed direction here is refusal. Row 1 is the bare
# `Verified: …` form #3286 uses; row 2 is a leading `**Verified:**`. A heading spelling is
# deliberately absent — see element 4 in the header. What the line CLAIMS is not matched
# at all.
VERIFIED_MARKERS='
^[[:space:]]{0,3}verified[[:space:]]*[]):：.,;—–-]
^[[:space:]]{0,3}(\*\*|__|\*|_)[[:space:]]*verified[[:space:]]*:?[[:space:]]*(\*\*|__|\*|_)
'

# --- table 5: what counts as the CITATION on that line -------------------------
# One POSIX ERE per line, matched anywhere ON the marker line (not anchored — a link sits
# mid-sentence). Row 1 is a markdown inline link, row 2 a bare URL. Kept deliberately
# small: the requirement is that a reader has somewhere to go, so widening this table
# means deciding that some new thing is somewhere to go, which is a decision and not a
# convenience.
VERIFIED_CITATIONS='
\]\([^)[:space:]]+\)
https?://[^[:space:]<>]+
'

# --- table 3: the two-sided bound on one criteria row's EVIDENCE cell ----------
# Bytes, under `LC_ALL=C`. Both numbers are midpoints of a measured empty band, not round
# numbers — element 3 of the header carries the corpus and the arithmetic. Moving either
# one means re-measuring: `tests/pr-body-clearance.test.sh` pins all four boundary values
# (377 and 325 clear, 422 and 487 refuse; 17 clears, 9 refuses), so a change made without
# the measurement goes red rather than through.
#
# THIS IS NOT A BODY LENGTH AND MUST NEVER BECOME ONE. Nothing below sums these, and
# nothing below compares them to the body's own length; see the header.
CRITERIA_EVIDENCE_CEILING=400
CRITERIA_EVIDENCE_FLOOR=13

# --- table 6: the concision ceilings, from CONVENTIONS.md -> "Write less" ------
# Owner's decision 2026-09-06; that section carries the measurement. Both are refused at
# exit 4. `tests/pr-body-clearance.test.sh` pins them and drives a body on each side.
BODY_CEILING_CHARS=2500
NOTES_CEILING=3

# --- table 7: the reviewer-generated blocks, NOT counted against the ceiling ----
# A ceiling is only meaningful over the half the checked party can change. CodeRabbit
# appends a release-notes block (740 and 531 characters, measured on #195 and #200) that
# regenerates on every review, so a body that cleared when it was posted refuses later.
#
# THE ANCHOR IS THE MARKER, NEVER THE EDITOR'S LOGIN: a login is whoever pushed the last
# edit, and the block outlives them. Text carrying no marker is counted in full, and an
# opening marker with no closing one strips nothing — an unrecognised block is counted,
# never guessed at, which is the only direction that cannot hide an author's own prose.
# Literal lines, not EREs: these are emitted verbatim by the tool that writes them.
#
# AND THE MARKER IS NOT AN EXEMPTION THE AUTHOR CAN WRITE HIMSELF. Nothing in a body says
# who typed a line, so an unbounded strip lets an author put the required structure
# outside an exact pair and his essay inside it. The strip is therefore worth at most what
# the generator emits, markers included — 531, 740 and 741 measured on #200, #195 and
# #206, so 1,000 is a POLICY bound over three observations and not an empty band. Past it
# nothing is stripped and the body counts as posted: this gate's verdict before the strip.
GENERATED_OPEN='<!-- This is an auto-generated comment: release notes by coderabbit.ai -->'
GENERATED_CLOSE='<!-- end of auto-generated comment: release notes by coderabbit.ai -->'
GENERATED_CEILING=1000

# --- table 8: verbatim criterion text, NOT counted against the ceiling ----------
# The author copies it from the task doc and may not shorten it (element 3's reason, one
# level up). Bounded per row like the block above: 800 over a largest real criterion of 702.
CRITERION_ALLOWANCE=800

# The body less every marked block. Byte-for-byte the input when there is no block, so a
# body nobody appended to is measured exactly as before. Nothing else reads this copy:
# every structural check below still runs on the body as posted.
authored_half() { # <src> <dst>
  if ! grep -Fq -- "$GENERATED_OPEN" "$1" || ! grep -Fq -- "$GENERATED_CLOSE" "$1"; then
    cat -- "$1" > "$2"
    return 0
  fi
  # `open` and `close` are awk's own; the block's markers are named around them.
  awk -v bopen="$GENERATED_OPEN" -v bclose="$GENERATED_CLOSE" '
    function trimmed(s) { sub(/[[:space:]]+$/, "", s); sub(/^[[:space:]]+/, "", s); return s }
    {
      if (!inb && trimmed($0) == bopen) { inb = 1; nb = 0; buf[++nb] = $0; next }
      if (inb) {
        buf[++nb] = $0
        if (trimmed($0) == bclose) { inb = 0; nb = 0 }
        next
      }
      print
    }
    END { if (inb) for (i = 1; i <= nb; i++) print buf[i] }
  ' < "$1" > "$2"
  [ "$(( $(char_count "$1") - $(char_count "$2") ))" -le "$GENERATED_CEILING" ] \
    || cat -- "$1" > "$2"
}

# THE number the ceiling compares and `report_length` prints: the authored copy less its
# own criteria table's criterion cells. ONE unit for both terms, chosen once — bytes off
# code points would over-subtract every multibyte glyph, which fails open.
counted_chars() { # <raw-body> -> "<counted> <exempt>"; leaves $TMPD/authored
  local n c
  authored_half "$1" "$TMPD/authored"
  render_body "$TMPD/authored" "$TMPD/authored.rendered"
  table_scan "$TMPD/authored.rendered" \
    | awk '/^criterion\t/ { sub(/^criterion\t/, ""); print }' > "$TMPD/criteria"
  if command -v jq >/dev/null 2>&1 \
     && n="$(jq -Rs 'length' < "$TMPD/authored" 2>/dev/null)" && [ -n "$n" ] \
     && c="$(jq -Rn --argjson cap "$CRITERION_ALLOWANCE" \
               '[inputs | length | if . > $cap then $cap else . end] | add // 0' \
               < "$TMPD/criteria" 2>/dev/null)" && [ -n "$c" ]; then
    :
  else
    n="$(LC_ALL=C wc -c < "$TMPD/authored" | tr -d ' ')"
    c="$(LC_ALL=C awk -v cap="$CRITERION_ALLOWANCE" \
           '{ l = length($0); s += (l > cap ? cap : l) } END { print s + 0 }' \
           "$TMPD/criteria")"
  fi
  case "$n$c" in ''|*[!0-9]*) return 2 ;; esac
  printf '%s %s\n' "$(( n - c ))" "$c"
}

# What the caller is measured on, said before the verdict. The second line only appears
# where a block was actually found, so a body nobody appended to prints what it always did.
report_length() { # <body-file> <label>
  local counted exempt authored posted
  read -r counted exempt <<EOF
$(counted_chars "$1")
EOF
  authored="$(char_count "$TMPD/authored")"
  posted="$(char_count "$1")"
  echo "pr-body-clearance: $2 is ${counted:-unknown} characters (ceiling $BODY_CEILING_CHARS)" >&2
  [ "${exempt:-0}" = 0 ] || {
    echo "pr-body-clearance: …not counting $exempt characters of verbatim criterion text" >&2
    echo "pr-body-clearance:    (at most $CRITERION_ALLOWANCE a row)" >&2
  }
  if [ "$posted" != "$authored" ]; then
    echo "pr-body-clearance: …of $posted posted; the rest is a reviewer-generated block" >&2
  elif grep -Fq -- "$GENERATED_OPEN" "$1" && grep -Fq -- "$GENERATED_CLOSE" "$1"; then
    echo "pr-body-clearance: …its marked block is over the $GENERATED_CEILING-character" >&2
    echo "pr-body-clearance:    allowance, so the whole body is counted" >&2
  fi
}

# CODE POINTS, which is what the host reports as a body's length. `jq` when it is there;
# bytes otherwise, which OVER-counts a multibyte body and so only ever refuses earlier —
# the fail-closed direction for a ceiling. The self-test runs before the `jq` check.
# A draft file's trailing newline counts; that is one character high, and earlier.
char_count() { # <file>
  local n
  if command -v jq >/dev/null 2>&1 && n="$(jq -Rs 'length' < "$1" 2>/dev/null)" \
     && [ -n "$n" ]; then
    printf '%s' "$n"
    return 0
  fi
  LC_ALL=C wc -c < "$1" | tr -d ' '
}

usage() {
  echo "Usage: $(basename "$0") <pr> [--repo <owner>/<name>] [--head <sha>]" >&2
  echo "       $(basename "$0") --body-file <path>   (decide on a local draft)" >&2
  echo "       $(basename "$0") --self-test          (prove this script RUNS)" >&2
  exit 2
}

# `rows <table>` strips comments and blank lines; every table is read through it, so a
# malformed row is inert rather than silently matching everything.
rows() { printf '%s\n' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
                                  | grep -v '^#' | grep -v '^$'; }

# Compile every ERE row before anything is classified with it. Checked here (up front),
# and again in --self-test so the caller refuses a sibling carrying a broken table.
validate_tables() {
  local bad="" r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    printf '' | grep -Eq "$r" 2>/dev/null || [ $? -eq 1 ] || bad="$bad          $r
"
  done <<EOF
$(rows "$TLDR_MARKERS")
$(rows "$DEPRECATED_TLDR_MARKERS")
$(rows "$VERIFIED_MARKERS")
$(rows "$VERIFIED_CITATIONS")
EOF
  [ -z "$bad" ] || {
    echo "error: these rows in this script's ERE tables are not valid POSIX EREs, so" >&2
    echo "       the table matches nothing and every PR would be refused for a reason" >&2
    echo "       that is not about its body. Refusing (fail closed):" >&2
    printf '%s' "$bad" >&2
    return 2
  }
  return 0
}

# --- the rendering both tests read -------------------------------------------
# ONE question: which lines of this body would a reader actually see as content? Fenced
# blocks (``` and ~~~, at up to three spaces of indent, closed or left open to EOF) are
# removed, because a body that QUOTES the convention's example would otherwise clear on
# the example. Carriage returns go too — the host stores CRLF for a body typed in the web
# editor, and a stray \r at end of line defeats an anchored match for no reason a human
# could see.
#
# THE STRIPPER IS A TOGGLE, AND AN UNBALANCED FENCE THEREFORE BLANKS THE REST OF THE BODY.
# That is the fail-closed direction HERE and it is worth stating, because in
# `review-clearance.sh` the same property was a defect: there, a blanked body stopped a
# REFUSAL being seen, which cleared a PR. Here everything downstream needs to FIND
# something, so a blanked body finds neither element and refuses. An author who opens a
# fence and never closes it gets a refusal and a glance, which is the correct answer to a
# body the host will render as one long code block anyway.
render_body() { # <src> <dst>
  tr -d '\r' < "$1" | awk '
    {
      line = $0
      if (fence == 0) {
        if (match(line, /^[[:space:]]{0,3}(`{3,}|~{3,})/)) {
          opener = substr(line, RSTART, RLENGTH)
          sub(/^[[:space:]]+/, "", opener)
          fchar = substr(opener, 1, 1)
          fwidth = length(opener)
          fence = 1
          next
        }
        print line
        next
      }
      # Inside a fence, and CommonMark closes one ONLY on a run of the SAME character
      # that is at least as long, with nothing but whitespace after it. A toggle that
      # closed on any fence line read a ``` nested inside a ````md block as the closer,
      # exposing the QUOTED content below it as body content — which is the one direction
      # that matters, because quoted content is exactly what must not clear this gate.
      if (match(line, /^[[:space:]]{0,3}(`{3,}|~{3,})[[:space:]]*$/)) {
        closer = substr(line, RSTART, RLENGTH)
        gsub(/[[:space:]]/, "", closer)
        if (substr(closer, 1, 1) == fchar && length(closer) >= fwidth) fence = 0
      }
      next
    }
  ' > "$2"
}

# --- element 1: is there a TL;DR marker line? --------------------------------
#   0 yes   1 no   2 the table will not compile (unknown; the caller refuses)
has_tldr() { # <rendered-body>
  local pat rc
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    grep -Eiq "$pat" "$1" 2>/dev/null; rc=$?
    [ "$rc" -eq 0 ] && return 0
    [ "$rc" -eq 1 ] || return 2
  done <<EOF
$(rows "$TLDR_MARKERS")
EOF
  return 1
}

# --- element 1a: is that marker the RETIRED heading spelling? -----------------
#   0 yes   1 no   2 the table will not compile (unknown; the caller refuses)
has_deprecated_tldr() { # <rendered-body>
  local pat rc
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    grep -Eiq "$pat" "$1" 2>/dev/null; rc=$?
    [ "$rc" -eq 0 ] && return 0
    [ "$rc" -eq 1 ] || return 2
  done <<EOF
$(rows "$DEPRECATED_TLDR_MARKERS")
EOF
  return 1
}

# --- element 4: is there a `Verified:` line, and does it cite anything? -------
# Two questions, three answers, because the FIXES are different: a line that is not there
# has to be written, a line that is there and cites nothing has to gain the link. Folding
# them into one refusal would send an author who wrote the line looking for a line they
# had already written.
#
#   0 a marker line carrying at least one citation
#   1 no marker line at all
#   2 a table will not compile (unknown; the caller refuses)
#   3 a marker line is there, and no line matching one carries a citation
#
# EVERY MARKER LINE IN THE BODY IS OFFERED TO THE CITATION TABLE, not just the first. A
# body whose lead mentions "Verified:" and whose real Verified line sits two paragraphs
# down is a body that cites something, and refusing it would be a false refusal on correct
# work. The refusal at 3 therefore means NO line matching any marker carried a link.
has_verified() { # <rendered-body>
  local pat lpat rc lines seen=0
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    lines="$(grep -Ei "$pat" "$1" 2>/dev/null)"; rc=$?
    [ "$rc" -eq 0 ] || { [ "$rc" -eq 1 ] || return 2; continue; }
    seen=1
    while IFS= read -r lpat; do
      [ -n "$lpat" ] || continue
      printf '%s\n' "$lines" | grep -Eq "$lpat" 2>/dev/null; rc=$?
      [ "$rc" -eq 0 ] && return 0
      [ "$rc" -eq 1 ] || return 2
    done <<EOF
$(rows "$VERIFIED_CITATIONS")
EOF
  done <<EOF
$(rows "$VERIFIED_MARKERS")
EOF
  [ "$seen" -eq 1 ] && return 3
  return 1
}

# --- element 6: `### Notes`, when it is there, leads each bullet with its claim -
# A SEPARATE PASS FROM THE TABLE, and deliberately so. Elements 2, 3 and 5 all ask about
# ONE artifact — the criteria table — which is why they share one parser; the notes are a
# different artifact, and giving them their own reader keeps "which table is the criteria
# table" answered in exactly one place.
#
# Output is TAB-separated, one line:
#   notes<TAB>absent   no `Notes` section, or one carrying no bullets — both CLEAR, since
#                      the section is optional and no number of notes is ever required
#   notes<TAB>ok       every column-zero bullet under it opens with bold
#   notes<TAB>bare<TAB><n><TAB><excerpt>   one line per bullet that does not
# Plus, always, `notecount<TAB><n>` — its own record type so the state reader above,
# which takes the FIRST `notes` line, cannot pick the count up as a state.
notes_scan() { # <rendered-body>
  LC_ALL=C awk '
    # Untrusted text leaves here, reduced and truncated exactly as the table scan does it.
    function excerpt(s,   out) {
      out = s
      gsub(/[^[:print:]]/, ".", out)
      if (length(out) > 60) out = substr(out, 1, 57) "..."
      return out
    }
    {
      line = $0
      if (line ~ /^[[:space:]]{0,3}#{1,6}[[:space:]]+/) {
        h = line
        sub(/^[[:space:]]*#+[[:space:]]*/, "", h)
        sub(/[[:space:]]*#+[[:space:]]*$/, "", h)
        sub(/[[:space:]]+$/, "", h)
        # The heading TEXT, at any depth: `## Notes` and `### Notes` are one section here.
      innotes = (tolower(h) ~ /^notes[^0-9a-z]*$/) ? 1 : 0
        next
      }
      if (innotes == 0) next
      # COLUMN ZERO ONLY. A GFM sub-item under a bullet at column 0 is indented by at
      # least two spaces, so this excludes children exactly rather than by a guess.
      if (line !~ /^[-*+][[:space:]]+/) next
      nth++
      if (line !~ /^[-*+][[:space:]]+(\*\*|__)/)
        bare = bare sprintf("notes\tbare\t%d\t%s\n", nth, excerpt(line))
    }
    END {
      if (nth == 0)        printf "notes\tabsent\n"
      else if (bare == "") printf "notes\tok\n"
      else                 printf "%s", bare
      printf "notecount\t%d\n", nth
    }
  ' "$1"
}

# --- elements 2, 3 and 5: the table's shape, its rows' evidence, and its tally -
# ONE PASS, ONE PARSER, ON PURPOSE. Elements 2 and 3 ask two questions of the same
# artifact ("is the criteria table well-formed" and "is each of its rows inside the
# bound"), and a second parser for the second question would give this repo two answers
# to "which table is the criteria table" — the exact defect this file's header warns
# about one level up. So the table is located once and both answers come out of that.
#
# Output is TAB-separated, state first:
#   state<TAB>ok        a header + a cell-count-matching delimiter + >=1 data row, and a
#                       data row carries one of the marks the merge gate reads
#   state<TAB>unmarked  a well-formed table exists, but no data row carries `✓`/`✗` — so
#                       it is some other table, and the criteria table is absent
#   state<TAB>none      no well-formed table at all
#   row<TAB>over|under<TAB><n><TAB><bytes><TAB><criterion excerpt>
#                       one line per criteria row outside the bound. Emitted only for
#                       rows that CARRY A MARK, so a continuation or spacer row inside
#                       the table is never measured as if it were a criterion.
#   tally<TAB>ok                                   the heading agrees with the rows
#   tally<TAB>noheading                            no ATX heading above the table at all
#   tally<TAB>nottallied<TAB><heading excerpt>     a heading, carrying no `N ✓ / M ✗`
#   tally<TAB>mismatch<TAB><claimed ✓><TAB><claimed ✗><TAB><actual ✓><TAB><actual ✗><TAB><undecidable rows>
#   tally<TAB>unexplained<TAB><claimed ✗><TAB><heading excerpt>
#                       element 5. Emitted only alongside `state ok`, for the same reason
#                       the row lines are: with no criteria table there is no tally to be
#                       right or wrong about.
#
# GREP'S STATUS IS NOT CONSULTED HERE BECAUSE NOTHING IS GREPPED: the shape is decided
# structurally, in one awk pass, which is the same move the sibling made when it took
# evidence and pinning off prose and onto the structured API.
#
# `LC_ALL=C` PINS THE UNIT. See element 3 in the header: `length()` is characters in some
# awks and bytes in others, and a threshold that moves with the machine is not a
# threshold. It changes nothing else here — every pattern in this program is ASCII, and
# the marks are compared with `index()`, which is a byte search either way.
table_scan() { # <rendered-body>
  # awk's `-v` cannot carry a literal newline, so the table travels as one RS-separated
  # (0x1e) field and is split back below. A record separator cannot occur in a PR body
  # the host serves as JSON text, so nothing an author writes can add a row here.
  LC_ALL=C awk -v marks="$(rows "$CRITERIA_MARKS" | tr '\n' '\036')" \
       -v mchk="$CRITERIA_MARK_VERIFIED" -v mcrs="$CRITERIA_MARK_UNVERIFIED" \
       -v ceiling="$CRITERIA_EVIDENCE_CEILING" -v floor="$CRITERIA_EVIDENCE_FLOOR" '
    function cellcount(s,   arr, n) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      # An ESCAPED pipe is content, not a cell boundary — that is how GFM says to put a
      # `|` inside a cell, and counting it as a boundary would inflate the header past
      # the delimiter row and refuse a table the host renders perfectly.
      gsub(/\\\|/, "", s)
      sub(/^\|/, "", s); sub(/\|$/, "", s)
      n = split(s, arr, "|")
      return n
    }
    # A delimiter row is one whose EVERY cell is a GFM delimiter cell — a run of dashes
    # with an optional leading and/or trailing colon. Asking only whether the LINE is made
    # of pipes, dashes, colons and spaces is not the same question and is weaker in the
    # dangerous direction: `|---|:|` passes that test while GitHub renders no table at
    # all, so a marked row underneath it would have cleared a non-table. GitHub also
    # renders nothing when the cell count differs from the header row above, and that
    # equality is checked at the call site.
    function is_delim(s,   arr, n, i, c) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      if (index(s, "|") == 0) return 0
      sub(/^\|/, "", s); sub(/\|$/, "", s)
      n = split(s, arr, "|")
      if (n < 1) return 0
      for (i = 1; i <= n; i++) {
        c = arr[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", c)
        if (c !~ /^:?-+:?$/) return 0
      }
      return 1
    }
    function has_mark(s,   i, n, m) {
      n = split(marks, m, "\036")
      for (i = 1; i <= n; i++) if (m[i] != "" && index(s, m[i]) > 0) return 1
      return 0
    }
    # A cell that is NOTHING BUT a mark — `✓`, `**✗**`, `` `✓` `` — is the merge-gate
    # column, not evidence and not criterion text. A cell that merely CONTAINS a mark is
    # content. An EMPTY cell is neither: it answers 0, so that a row whose evidence cell
    # was left blank is measured (at length 0) rather than skipped over.
    function mark_only(c,   t) {
      t = c
      gsub(/[*_` ~]/, "", t)
      if (t == "") return 0
      # One glyph and nothing else: 3 bytes under LC_ALL=C, 1 character if some future
      # caller loses that pinning. `<= 3` covers both rather than depending on it.
      return has_mark(t) && length(t) <= 3
    }
    # WHICH mark a cell is, for element 5. `mark_only` answers "is this the mark column";
    # the tally has to count the two glyphs apart, and it reads them from the two named
    # constants rather than from the marks table row order.
    function mark_of(c,   t) {
      t = c
      gsub(/[*_` ~]/, "", t)
      if (t == "") return ""
      if (length(t) <= 3) {
        if (index(t, mchk) > 0) return "chk"
        if (index(t, mcrs) > 0) return "crs"
      }
      return ""
    }
    # One rows verdict: "chk", "crs", or "" when the row is undecidable. The mark COLUMN
    # is read first, because that is the cell the merge gate reads; only if no cell is
    # just a mark does this fall back to the row carrying exactly ONE KIND of glyph. A row
    # carrying both, or neither in a countable position, answers "" and is counted as
    # undecidable — which makes the tally disagree with the table and refuse, the safe
    # direction for a row nobody can classify.
    function row_mark(s,   arr, n, i, m, mm) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      gsub(/\\\|/, "\002", s)
      sub(/^\|/, "", s); sub(/\|$/, "", s)
      n = split(s, arr, "|")
      for (i = 1; i <= n; i++) {
        m = mark_of(arr[i])
        if (m != "") return m
      }
      mm = ""
      if (index(s, mchk) > 0) mm = "chk"
      if (index(s, mcrs) > 0) mm = (mm == "" ? "crs" : "both")
      return (mm == "both") ? "" : mm
    }
    # The nearest ATX heading ABOVE the criteria table, with its markers stripped. Element
    # 5 asks the heading for a tally, so a table with no heading anywhere above it has no
    # tally by construction and says so.
    function heading_above(idx,   k, h) {
      for (k = idx; k >= 1; k--) {
        if (lines[k] ~ /^[[:space:]]{0,3}#{1,6}[[:space:]]+/) {
          h = lines[k]
          sub(/^[[:space:]]*#+[[:space:]]*/, "", h)
          sub(/[[:space:]]*#+[[:space:]]*$/, "", h)
          return h
        }
      }
      return ""
    }
    # Untrusted text leaves here too, reduced and truncated exactly as split_row does it.
    function excerpt(s,   out) {
      out = s
      gsub(/[^[:print:]]/, ".", out)
      if (length(out) > 60) out = substr(out, 1, 57) "..."
      return out
    }
    # Splits one row into R_EVI (the evidence cell), R_LABEL (a bounded, sanitised excerpt
    # of the cells before it) and R_MARKLAST (the row has no evidence column at all).
    #
    # EVIDENCE IS THE LAST CELL. Not "the last cell that is not a mark", which sounds more
    # forgiving and is worse: it silently skips a BLANK evidence cell and reports the
    # criterion text in its place, so the one row with no evidence at all is the one row
    # that clears. Last-cell is also the shape the CONVENTIONS.md example prescribes and
    # the shape all three measured pull requests use, and reading from the right means an
    # extra leading column (an index, as in #71) costs nothing. A row whose last cell is
    # the bare mark has put the evidence somewhere this reader will not look, and says so
    # in those words rather than measuring the mark.
    # (No apostrophes below this line until the closing quote — the whole awk program is
    # one single-quoted shell word, so one would end it.)
    function split_row(s,   arr, n, i, c, out) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      gsub(/\\\|/, "\002", s)      # an escaped pipe is CONTENT, exactly as in cellcount
      sub(/^\|/, "", s); sub(/\|$/, "", s)
      n = split(s, arr, "|")
      R_EVI = ""; R_LABEL = ""; R_MARKLAST = 0; R_CRIT = ""
      if (n < 1) return 0
      R_EVI = arr[n]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", R_EVI)
      R_MARKLAST = mark_only(R_EVI)
      gsub(/\002/, "|", R_EVI)
      out = ""
      for (i = 1; i < n; i++) {
        c = arr[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", c)
        if (c == "" || mark_only(c)) continue
        if (length(c) > length(R_CRIT)) R_CRIT = c
        out = (out == "" ? c : out " " c)
      }
      # UNTRUSTED TEXT LEAVES HERE. Under LC_ALL=C `[:print:]` is ASCII 0x20-0x7e, so this
      # one substitution strips control bytes (and so every terminal escape) and the
      # trailing half of a multi-byte character the truncation below could otherwise cut
      # in two. Then a fixed 60 bytes, because an excerpt that identifies the row is the
      # whole job and a body must not be able to print itself through this gate.
      gsub(/\002/, "|", out)       # restore first: a `|` is content and must survive
      gsub(/[^[:print:]]/, ".", out)
      if (length(out) > 60) out = substr(out, 1, 57) "..."
      R_LABEL = (out == "" ? "(row " nth ")" : out)
      gsub(/\002/, "\\|", R_CRIT)
      return 1
    }
    { lines[NR] = $0 }
    END {
      found = 0; marked = 0; nth = 0; offenders = ""
      actchk = 0; actcrs = 0; ambig = 0; crit_head = ""; crit_head_seen = 0
      for (i = 2; i <= NR; i++) {
        if (!is_delim(lines[i])) continue
        head = lines[i-1]
        if (index(head, "|") == 0) continue
        if (cellcount(head) < 2) continue
        if (cellcount(head) != cellcount(lines[i])) continue
        rowcount = 0; rowmarked = 0; tcrit = ""
        for (j = i + 1; j <= NR; j++) {
          if (index(lines[j], "|") == 0) break
          if (lines[j] ~ /^[[:space:]]*$/) break
          rowcount++
          if (!has_mark(lines[j])) continue
          rowmarked = 1
          # ELEMENT 5, counted on the same rows element 3 measures — one walk of the
          # table answers both, which is why there is still exactly one parser here.
          rm = row_mark(lines[j])
          if (rm == "chk") actchk++
          else if (rm == "crs") actcrs++
          else ambig++
          # ELEMENT 3, measured on this row and nothing else. A row with no evidence cell
          # at all reports length 0, which is a floor failure — the honest answer, since
          # a criterion whose evidence column is empty is exactly the assertion-without-
          # evidence the floor exists to refuse.
          nth++
          if (!split_row(lines[j])) continue
          if (R_CRIT != "") tcrit = tcrit "criterion\t" R_CRIT "\n"
          len = length(R_EVI)
          if (R_MARKLAST)
            offenders = offenders sprintf("row\tmark\t%d\t%d\t%s\n", nth, len, R_LABEL)
          else if (len > ceiling)
            offenders = offenders sprintf("row\tover\t%d\t%d\t%s\n", nth, len, R_LABEL)
          else if (len < floor)
            offenders = offenders sprintf("row\tunder\t%d\t%d\t%s\n", nth, len, R_LABEL)
        }
        if (rowcount < 1) continue
        found = 1
        if (rowmarked) {
          marked = 1
          # The heading of the FIRST marked table is the criteria heading. Taking the last
          # one would let a second marked table further down the body move the tally onto
          # a heading the author did not write it under.
          if (crit_head_seen == 0) {
            crit_head = heading_above(i - 2); crit_head_seen = 1; crit = tcrit
          }
        }
      }
      # The state line comes FIRST and always, so a reader can take the verdict without
      # having to know how many row lines follow it.
      if (found && marked)  printf "state\tok\n"
      else if (found)       printf "state\tunmarked\n"
      else                  printf "state\tnone\n"
      # Rows are only ever reported for the state the caller acts on. Under `unmarked` or
      # `none` there is no criteria table, so a length measured inside some other table
      # would be a refusal about a row nobody wrote as a criterion.
      if (found && marked) printf "%s%s", offenders, crit
      # ELEMENT 5, for the same reason and under the same condition.
      if (found && marked) {
        if (crit_head == "") { printf "tally\tnoheading\n"; exit }
        # Built from the two named glyphs rather than written out, so the marks table and
        # the tally can never disagree about which glyph means verified.
        tre = "([0-9]+)[ \t]*" mchk "[ \t]*/[ \t]*([0-9]+)[ \t]*" mcrs
        if (!match(crit_head, tre)) {
          printf "tally\tnottallied\t%s\n", excerpt(crit_head); exit
        }
        t = substr(crit_head, RSTART, RLENGTH)
        rest = substr(crit_head, RSTART + RLENGTH)
        split(t, dg, /[^0-9]+/)
        clchk = dg[1] + 0; clcrs = dg[2] + 0
        if (clchk != actchk || clcrs != actcrs) {
          printf "tally\tmismatch\t%d\t%d\t%d\t%d\t%d\n",
                 clchk, clcrs, actchk, actcrs, ambig
          exit
        }
        # THE REASON IS ASKED TO BE THERE, NEVER TO BE GOOD. Everything that is not a
        # letter or a digit goes — whitespace, brackets, dashes, the glyphs themselves —
        # so a heading closing on `8 ✗)` or `8 ✗ —` is bare and one carrying words is not.
        gsub(/[^0-9A-Za-z]/, "", rest)
        if (clcrs > 0 && rest == "") {
          printf "tally\tunexplained\t%d\t%s\n", clcrs, excerpt(crit_head); exit
        }
        printf "tally\tok\n"
      }
    }
  ' "$1"
}

# --- element 3's verdict: the shape is here, are the rows inside the bound? ---
# Reached ONLY when both structural elements are present, so every message below is about
# a body that is otherwise correct.
#
# IT FAILS LOUDLY AND IT NAMES THE ROW, on BOTH sides. A gate that answered `3` and
# stopped would leave the author diffing a twelve-row table against a number they have to
# go and read, and the natural response to that is to stop running the gate. Each
# offending row therefore gets its index, its measured length, which bound it broke, and
# what to do — and the two sides get DIFFERENT advice, because they are different
# mistakes: over the ceiling means the reasoning belongs in the task doc, under the floor
# means the row does not say what to run.
report_rows() { # <scan> <label> -> 0 clear, 3 at least one row outside the bound
  local scan="$1" label="$2" offenders n kind idx len text tab
  tab="$(printf '\t')"
  offenders="$(printf '%s\n' "$scan" | awk -F'\t' '$1 == "row" { print }')"
  # SILENT ON SUCCESS. The clearance line is printed by `decide` after the concision
  # ceilings have also answered, so a body cannot be told "ok" and then refused.
  [ -n "$offenders" ] || return 0
  n="$(printf '%s\n' "$offenders" | grep -c '^')"
  echo "refuse: $label carries both structural elements, but $n acceptance-criteria" >&2
  echo "        row(s) fall outside the two-sided bound $AB_CONVENTIONS puts on the" >&2
  echo "        EVIDENCE column — floor $CRITERIA_EVIDENCE_FLOOR bytes, ceiling $CRITERIA_EVIDENCE_CEILING bytes:" >&2
  # `set -u` is on and a short line would leave a field unset, so every field is read
  # through a default. The emitted lines always carry five, but a refusal that aborted the
  # script on an unset variable would be a gate that stopped reporting half-way.
  while IFS="$tab" read -r _ kind idx len text; do
    kind="${kind:-}"; idx="${idx:-?}"; len="${len:-?}"; text="${text:-}"
    [ -n "$kind" ] || continue
    if [ "$kind" = mark ]; then
      echo "        row $idx has NO evidence column: \"$text\"" >&2
      echo "          Its last cell is the ✓/✗ mark. Evidence goes in the LAST column —" >&2
      echo "          '| Criterion | ✓ | Verified by |' — which is where a reader looks" >&2
      echo "          for it and the only cell this bound reads." >&2
    elif [ "$kind" = over ]; then
      echo "        row $idx over the CEILING at $len bytes: \"$text\"" >&2
      echo "          Cut it to the command and its result. Why you chose the approach," >&2
      echo "          what you tried first and the incident behind it belong in the" >&2
      echo "          commit message and the task doc, which travel with the change." >&2
    else
      echo "        row $idx under the FLOOR at $len bytes: \"$text\"" >&2
      echo "          Name the artifact a reader can re-run — the test file and its" >&2
      echo "          tally, the command, the CI run, the URL. 'ok', 'see above' and a" >&2
      echo "          bare commit SHA tell a reader nothing to do next." >&2
    fi
  done <<EOF
$offenders
EOF
  echo "        This bounds ONE CELL of ONE ROW. The body's own ceiling is a separate" >&2
  echo "        check with a separate code (4). See $AB_CONVENTIONS, 'The criteria table" >&2
  echo "        is the merge gate'." >&2
  return 3
}

# --- element 7: the concision ceilings, CONVENTIONS.md -> "Write less" ---------
# LAST, and only over a body whose every element is present and whose every row is inside
# its bound — so its advice is always "relocate", never "add". Both ceilings are reported
# in one pass: an author over both should learn both in one run.
report_concision() { # <raw-body> <notes-scan> <label> -> 0 clear, 4 over a ceiling
  local raw="$1" nscan="$2" label="$3" chars exempt notes rc=0
  read -r chars exempt <<EOF
$(counted_chars "$raw")
EOF
  notes="$(printf '%s\n' "$nscan" | awk -F'\t' '$1 == "notecount" { print $2; exit }')"
  case "$chars" in ''|*[!0-9]*) return 2 ;; esac
  case "$notes" in ''|*[!0-9]*) return 2 ;; esac
  if [ "$chars" -gt "$BODY_CEILING_CHARS" ]; then
    rc=4
    echo "refuse: $label carries every required element, and it is $chars authored" >&2
    echo "        characters — over the $BODY_CEILING_CHARS-character ceiling $AB_CONVENTIONS sets in" >&2
    echo "        'Write less'. A marked reviewer block is not counted, up to $GENERATED_CEILING" >&2
    echo "        characters; a larger one is counted in full, markers or no markers." >&2
    echo "        Nor is each criteria row's verbatim criterion text, up to" >&2
    echo "        $CRITERION_ALLOWANCE characters a row; its evidence is yours and is counted." >&2
    echo "        Keep the TL;DR line, the Verified line and the criteria table. Move the" >&2
    echo "        design, the alternatives and the incident into the task doc and the" >&2
    echo "        commit message, which travel with the change and have no ceiling." >&2
  fi
  if [ "$notes" -gt "$NOTES_CEILING" ]; then
    rc=4
    echo "refuse: $label carries $notes Notes bullets — over the $NOTES_CEILING $AB_CONVENTIONS allows." >&2
    echo "        A note is for something a reviewer cannot see from the diff. Past three" >&2
    echo "        it is the essay the section replaced, arriving under another heading." >&2
  fi
  return "$rc"
}

# --- the verdict, over a body already on disk ---------------------------------
# The ONE place a body becomes an exit code, so both call sites (a fetched PR and a local
# draft) answer identically. <label> only names the subject in the messages.
decide() { # <raw-body> <rendered-body> <label> -> 0 clear, 1, 2, 3 a row, 4 too long
  local raw="$1" rendered="$2" label="$3" tldr verified scan tstate tally tkind rc
  local nscan nstate bare_n bare_txt
  local tab; tab="$(printf '\t')"
  has_tldr "$rendered"; tldr=$?
  [ "$tldr" -eq 2 ] && return 2
  # A notice, never a verdict: the retired spelling clears for one release.
  has_deprecated_tldr "$rendered" \
    && echo "note: '## Description (TL;DR)' is deprecated — use '## Description'; it clears for one more release." >&2
  has_verified "$rendered"; verified=$?
  [ "$verified" -eq 2 ] && return 2
  scan="$(table_scan "$rendered")"
  tstate="$(printf '%s\n' "$scan" | awk -F'\t' '$1 == "state" { print $2; exit }')"
  case "$tstate" in ok|unmarked|none) : ;; *) return 2 ;; esac
  tally="$(printf '%s\n' "$scan" | awk -F'\t' '$1 == "tally" { print; exit }')"
  tkind="$(printf '%s\n' "$tally" | cut -f2)"
  # A `state ok` with no tally line at all is a scan that did not finish, which is unknown
  # rather than a verdict about the body.
  if [ "$tstate" = ok ]; then
    case "$tkind" in ok|noheading|nottallied|mismatch|unexplained) : ;; *) return 2 ;; esac
  fi
  nscan="$(notes_scan "$rendered")"
  nstate="$(printf '%s\n' "$nscan" | awk -F'\t' '$1 == "notes" { print $2; exit }')"
  case "$nstate" in ok|absent|bare) : ;; *) return 2 ;; esac

  # STRUCTURE IS DECIDED BEFORE THE ROW BOUND, AND THAT ORDER IS THE POINT. Exit 1 says a
  # required element is missing; exit 3 says every element is there and one row is out of
  # bounds. Reporting the second while the first is unresolved would tell an author to
  # trim rows of a table the gate has not agreed exists.
  if [ "$tldr" -eq 0 ] && [ "$verified" -eq 0 ] && [ "$tstate" = ok ] \
     && [ "$tkind" = ok ] && [ "$nstate" != bare ]; then
    report_rows "$scan" "$label" || return $?
    report_concision "$raw" "$nscan" "$label" || return $?
    echo "ok: $label carries a TL;DR line and a well-formed acceptance-criteria" >&2
    echo "    table, a Verified line that cites something, a heading tally that matches" >&2
    echo "    the rows, claim-first notes where it has any, and is inside the" >&2
    echo "    $AB_CONVENTIONS concision ceilings." >&2
    return 0
  fi

  echo "refuse: $label does not carry the shape $AB_CONVENTIONS requires of a PR body." >&2
  rc=1
  [ "$tldr" -eq 0 ] || {
    echo "        MISSING: the TL;DR line. One sentence — what changes, and why it is" >&2
    echo "        safe to merge — as the heading '## Description' or a leading '**TL;DR**'." >&2
  }
  if [ "$verified" -eq 1 ]; then
    echo "        MISSING: the Verified line. One line under the lead carrying what you" >&2
    echo "        ran and a link a reader can open — 'Verified: 277/0 locally, 10/10" >&2
    echo "        checks green on [run 33430116558](https://.../runs/33430116558)'. It" >&2
    echo "        is how a reader decides in one line whether to trust the rest." >&2
  elif [ "$verified" -eq 3 ]; then
    echo "        INCOMPLETE: the Verified line cites nothing. It carries no link, so a" >&2
    echo "        reader has nowhere to go and check it — add the CI run, the workflow" >&2
    echo "        URL or the page you loaded. What the line CLAIMS is your business;" >&2
    echo "        that it cites something a reader can open is this gate's." >&2
  fi
  case "$tstate" in
    none)
      echo "        MISSING: the acceptance-criteria table. One row per criterion, a" >&2
      echo "        '✓'/'✗', and the evidence. No well-formed markdown table was found" >&2
      echo "        (a header row, a delimiter row with the same number of cells, and at" >&2
      echo "        least one data row)." >&2 ;;
    unmarked)
      echo "        MISSING: the acceptance-criteria table. A well-formed table is here," >&2
      echo "        but no row of it carries a '✓' or a '✗' — that column IS the checkbox" >&2
      echo "        state $AB_SCHEMA clause 7 and AUTONOMY.md read, so as written there is" >&2
      echo "        nothing for the merge gate to consult." >&2 ;;
  esac
  case "$tkind" in
    noheading)
      echo "        MISSING: a heading over the criteria table, so it carries no tally." >&2
      echo "        Head it '### Criteria (10 ✓ / 8 ✗ — every ✗ is a later slice)' — the" >&2
      echo "        counts, and why the ✗s are there. A reader takes the shape of the" >&2
      echo "        table from that line instead of from eighteen rows." >&2 ;;
    nottallied)
      echo "        MISSING: the tally on the criteria heading, which reads:" >&2
      echo "          \"$(printf '%s\n' "$tally" | cut -f3)\"" >&2
      echo "        Write the counts into it — '### Criteria (10 ✓ / 8 ✗ — every ✗ is a" >&2
      echo "        later slice)'. $AB_SCHEMA clause 7 makes an unverified criterion block" >&2
      echo "        clearance, so the counts are the first thing a reader needs." >&2 ;;
    mismatch)
      echo "        WRONG: the criteria heading claims $(printf '%s\n' "$tally" | cut -f3) ✓ / $(printf '%s\n' "$tally" | cut -f4) ✗, and the table" >&2
      echo "        carries $(printf '%s\n' "$tally" | cut -f5) ✓ / $(printf '%s\n' "$tally" | cut -f6) ✗. A tally a reader cannot trust costs more than" >&2
      echo "        no tally at all, because it is the one number nobody re-derives." >&2
      [ "$(printf '%s\n' "$tally" | cut -f7)" = 0 ] || {
        echo "        ($(printf '%s\n' "$tally" | cut -f7) row(s) carry both glyphs or neither in a countable cell, so" >&2
        echo "        they counted as neither. Put one ✓ or one ✗ in its own cell.)" >&2
      } ;;
    unexplained)
      echo "        MISSING: the reason for the $(printf '%s\n' "$tally" | cut -f3) ✗ on the criteria heading, which reads:" >&2
      echo "          \"$(printf '%s\n' "$tally" | cut -f4)\"" >&2
      echo "        $AB_SCHEMA clause 7 makes an unverified criterion block clearance, so a" >&2
      echo "        table with ✗ in it looks alarming until the heading says why. Put the" >&2
      echo "        reason after the tally — '(10 ✓ / 8 ✗ — every ✗ is a later slice or" >&2
      echo "        task-001)'. Whether the reason is a good one is the reviewer's call," >&2
      echo "        not this gate's; that it is there is this gate's." >&2 ;;
  esac
  if [ "$nstate" = bare ]; then
    echo "        MISSING: the bold claim opening these Notes bullet(s):" >&2
    while IFS="$tab" read -r _ _ bare_n bare_txt; do
      bare_n="${bare_n:-?}"; bare_txt="${bare_txt:-}"
      [ -n "$bare_txt" ] || continue
      echo "          note $bare_n: \"$bare_txt\"" >&2
    done <<EOF
$(printf '%s\n' "$nscan" | awk -F'\t' '$2 == "bare" { print }')
EOF
    echo "        Each note opens with a bolded sentence that IS the finding — '**A grep-" >&2
    echo "        derived inventory would have been short by 8 and looked complete.**' —" >&2
    echo "        with the explanation after it, so the section is skimmable in bold" >&2
    echo "        alone. The section is optional; a note that buries its claim is not." >&2
  fi
  echo "        This is the STRUCTURE refusal. Length is a separate check with a" >&2
  echo "        separate code (4). See $AB_CONVENTIONS, 'The PR body has a required" >&2
  echo "        shape'." >&2
  return "$rc"
}

# --- --self-test: no network, no PR -------------------------------------------
#
# It PROVES THIS SCRIPT RUNS, which `[ -x ]` does not. A dead shebang, a syntax error, a
# zero-byte file and a copy truncated half-way through an install all carry the executable
# bit and then fail every invocation — which in a caller that treats a non-zero code as
# "refuse" would look like a gate working perfectly while it read nothing at all. So
# `required-checks.sh` runs this first and refuses unless it exits 0 AND prints
# SELFTEST_OK verbatim. That string is the contract between the two files, duplicated
# there on purpose: a shared constant would have to be sourced, and sourcing a broken file
# is the failure being tested for.
#
# THE CONTROLS ARE THE POINT — a banner would pass for any stub that prints a banner. This
# drives the real decision function in EVERY direction it can answer in — clear, missing
# element, over the ceiling, under the floor — so a copy whose tables no longer fire, or
# whose row bound has been quietly widened to infinity, cannot answer 0 here. The two row
# probes are built at the MEASURED boundary values (element 3), not at a comfortable
# distance from them, so a copy that moved the constant by a little fails as surely as one
# that deleted it.
#
# AND "IT RUNS" IS NOT "IT IS COMPLETE": this block sits near the TOP, so a copy truncated
# below it would still reach this exit. The last line of the file is asserted here.
SELFTEST_OK="pr-body-clearance: self-test ok"
EOF_SENTINEL="#EOF: pr-body-clearance.sh is complete to here"
if [ "${1:-}" = "--self-test" ]; then
  [ "$#" -eq 1 ] || usage
  [ -r "$0" ] || {
    echo "self-test: cannot read '$0' to prove it is complete — refusing" >&2; exit 2; }
  [ "$(tail -n 1 "$0")" = "$EOF_SENTINEL" ] || {
    echo "self-test: this file does not end with its completeness sentinel, so it is" >&2
    echo "           truncated or was cut short — the tables and the classifier below" >&2
    echo "           this line cannot be assumed to be here. Refusing." >&2; exit 2; }
  TMPD="$(mktemp -d)" || {
    echo "self-test: could not create a temp dir — refusing" >&2; exit 2; }
  trap 'rm -rf "$TMPD"' EXIT
  validate_tables || exit 2

  st_probe() { # <expected-rc> <name> <body lines...>
    local want="$1" name="$2"; shift 2
    printf '%s\n' "$@" > "$TMPD/raw"
    render_body "$TMPD/raw" "$TMPD/rendered"
    decide "$TMPD/raw" "$TMPD/rendered" "self-test body" >/dev/null 2>&1
    [ "$?" -eq "$want" ] || {
      echo "self-test: $name did not answer $want — refusing" >&2; exit 2; }
  }

  # An evidence cell of exactly <n> bytes, so the two row probes sit ON the measured
  # boundary rather than near it.
  st_cell() { printf '%*s' "$1" '' | tr ' ' 'x'; }

  # The lead every probe below shares, so each probe states only the thing it is about.
  ST_VERIFIED='Verified: `a.test.sh` 40/0 on [run 1](https://example.invalid/runs/1).'
  ST_HEAD1='### Criteria (1 ✓ / 0 ✗)'
  ST_HEADX='### Criteria (0 ✓ / 1 ✗ — it needs a human)'

  st_probe 0 "a conforming body (heading form)" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |'
  st_probe 0 "…and the retired heading spelling, still cleared for one release" \
    '## Description (TL;DR)' 'It does the thing.' '' "$ST_VERIFIED" '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |'
  st_probe 0 "a conforming body (bold form)" \
    '**TL;DR** — it does the thing.' '' "$ST_VERIFIED" '' "$ST_HEADX" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✗ | needs a human |'
  st_probe 1 "a body with no TL;DR marker" \
    'It does the thing.' '' "$ST_VERIFIED" '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |'
  st_probe 1 "a body with no criteria table" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' \
    'Some prose and nothing else.'
  st_probe 1 "a body whose only table is inside a code fence" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' "$ST_HEAD1" '' '```md' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |' '```'
  st_probe 0 "a row at the largest honest evidence cell measured (#67, 377)" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' \
    "| it works | ✓ | $(st_cell 377) |"
  st_probe 3 "a row at ai-bridge#71's worst evidence cell (487)" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' \
    "| it works | ✓ | $(st_cell 487) |"
  st_probe 3 "a row whose evidence is 'see above'" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | see above |'

  # ELEMENTS 4, 5 AND 6, EACH DRIVEN IN BOTH DIRECTIONS. A copy whose Verified table no
  # longer fires, whose tally is never compared, or whose notes reader was deleted answers
  # 0 on every probe above — so each new check gets a probe that can only pass while the
  # check is really there, and its control is the clearing body at the top of this block.
  st_probe 1 "a body with no Verified line" \
    '## Description' 'It does the thing.' '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |'
  st_probe 1 "a Verified line citing nothing" \
    '## Description' 'It does the thing.' '' 'Verified: 40/0 locally, all green.' \
    '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |'
  st_probe 1 "a criteria heading carrying no tally" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' '### Criteria' '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |'
  st_probe 1 "a tally that contradicts the table" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' \
    '### Criteria (2 ✓ / 0 ✗)' '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |'
  st_probe 1 "a tally whose ✗ is unexplained" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' \
    '### Criteria (0 ✓ / 1 ✗)' '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✗ | needs a human |'
  st_probe 1 "a ### Notes bullet that buries its claim" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |' \
    '' '### Notes' '' '- the parser is in awk because grep cannot count cells.'
  st_probe 0 "…and the same note, claim first" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |' \
    '' '### Notes' '' '- **The parser is in awk.** grep cannot count a table cell.'

  # ELEMENT 7, BOTH CEILINGS, BOTH DIRECTIONS. A copy whose length check was deleted
  # answers 0 on the over-ceiling probes; a copy that set the ceiling too low answers 4
  # on the 2,000-character one. The controls are the two clearing probes.
  ST_NOTE1='- **One.** A reviewer cannot see this from the diff.'
  ST_NOTE2='- **Two.** Nor this.'
  ST_NOTE3='- **Three.** Nor this.'
  ST_NOTE4='- **Four.** This is the essay arriving under another heading.'
  st_probe 0 "a 2,000-character body carrying every element" \
    '## Description' "It does the thing. $(st_cell 1800)" '' "$ST_VERIFIED" '' \
    "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |'
  st_probe 4 "the same body past the 2,500-character ceiling" \
    '## Description' "It does the thing. $(st_cell 2600)" '' "$ST_VERIFIED" '' \
    "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |'
  # THE AUTHORED HALF, AND THE BOUND ON IT. A block the size of a real one is stripped;
  # the same markers around more text than the generator emits strip nothing. A copy that
  # strips on something else, strips nothing, or strips whatever it is given fails one.
  st_probe 0 "a generated block inside the allowance" \
    '## Description' "It does the thing. $(st_cell 1700)" '' "$ST_VERIFIED" '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |' \
    '' "$GENERATED_OPEN" "$(st_cell 700)" "$GENERATED_CLOSE"
  st_probe 4 "…an author's own pair around 2,600 characters, which strips nothing" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |' \
    '' "$GENERATED_OPEN" "$(st_cell 2600)" "$GENERATED_CLOSE"
  st_probe 4 "…the same text with no marker around it" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |' \
    '' "$(st_cell 2600)"
  st_probe 4 "…and an author over the ceiling beside a block of his own" \
    '## Description' "It does the thing. $(st_cell 2600)" '' "$ST_VERIFIED" '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |' \
    '' "$GENERATED_OPEN" 'Generated.' "$GENERATED_CLOSE"
  st_probe 4 "…and an opening marker that never closes" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |' \
    '' "$GENERATED_OPEN" "$(st_cell 2600)"

  # TABLE 8, BOTH DIRECTIONS: four 700-character criteria clear; one of 3,400 is charged
  # past its allowance. A copy that drops the subtraction fails the first, one that drops
  # the bound fails the second.
  st_probe 0 "2,800 characters of verbatim criterion text" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' '### Criteria (4 ✓ / 0 ✗)' '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' \
    "| $(st_cell 700) | ✓ | \`a.test.sh\` 40/0 |" "| $(st_cell 700) | ✓ | \`a.test.sh\` 40/0 |" \
    "| $(st_cell 700) | ✓ | \`a.test.sh\` 40/0 |" "| $(st_cell 700) | ✓ | \`a.test.sh\` 40/0 |"
  st_probe 4 "…and one criterion past its $CRITERION_ALLOWANCE-character allowance" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' "| $(st_cell 3400) | ✓ | \`a.test.sh\` 40/0 |"

  st_probe 0 "three claim-first notes" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |' \
    '' '### Notes' '' "$ST_NOTE1" "$ST_NOTE2" "$ST_NOTE3"
  st_probe 4 "…and a fourth" \
    '## Description' 'It does the thing.' '' "$ST_VERIFIED" '' "$ST_HEAD1" '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |' \
    '' '### Notes' '' "$ST_NOTE1" "$ST_NOTE2" "$ST_NOTE3" "$ST_NOTE4"

  printf '%s\n' "$SELFTEST_OK"
  exit 0
fi

# --- argument parsing ---------------------------------------------------------
pr=""; repo=""; want_head=""; body_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)      repo="${2:-}";      [ -n "$repo" ] || usage; shift 2 ;;
    --head)      want_head="${2:-}"; [ -n "$want_head" ] || usage; shift 2 ;;
    --body-file) body_file="${2:-}"; [ -n "$body_file" ] || usage; shift 2 ;;
    -h|--help)   usage ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) [ -z "$pr" ] || { echo "error: unexpected argument '$1'" >&2; usage; }
       pr="$1"; shift ;;
  esac
done

validate_tables || exit 2

command -v jq >/dev/null 2>&1 || {
  echo "error: jq not found — the body cannot be read, so this refuses (fail closed)" >&2
  exit 2
}

TMPD="$(mktemp -d)" || {
  echo "error: could not create a temp dir — refusing (fail closed)" >&2
  exit 2
}
trap 'rm -rf "$TMPD"' EXIT

# --- route 1: a local draft, so an author can check before opening the PR ------
# It exists because the cheapest moment to catch a malformed body is before it is
# published, and an author who has to open the PR to learn the shape was wrong will fix
# it in a force-push nobody reads. It is not the gate: `required-checks.sh` always takes
# route 2, against what the host actually serves.
if [ -n "$body_file" ]; then
  [ -z "$pr" ] && [ -z "$repo" ] && [ -z "$want_head" ] || {
    echo "error: --body-file decides on a local file; it takes no PR, repo or head." >&2
    usage
  }
  [ -r "$body_file" ] || {
    echo "error: cannot read '$body_file' — a body this script cannot read is unknown" >&2
    echo "       state, and unknown is never clearance. Refusing." >&2
    exit 2
  }
  # Reported here for the author; `decide` measures it again against the ceiling.
  report_length "$body_file" "$body_file"
  render_body "$body_file" "$TMPD/rendered"
  decide "$body_file" "$TMPD/rendered" "'$body_file'"
  exit $?
fi

# --- route 2: the actual PR body, from the host -------------------------------
[ -n "$pr" ] || usage

command -v gh >/dev/null 2>&1 || {
  echo "error: gh not found — the PR body cannot be read, so this refuses" >&2
  exit 2
}

# bash 3.2 (the macOS default) errors on "${arr[@]}" when arr is empty under `set -u`.
R=()
[ -n "$repo" ] && R=(--repo "$repo")

# A FETCH THAT ERRORS IS NOT AN EMPTY BODY. Reading a transient 5xx as "no body" is a
# refusal today and would be a clearance the moment anything downstream treated one of
# these codes as benign, so this refuses at exit 2 instead of classifying an empty string.
raw="$(gh pr view "$pr" ${R[@]+"${R[@]}"} \
       --json url,number,body,headRefOid 2>/dev/null)" || {
  echo "error: could not read PR $pr${repo:+ in $repo} — its body is unknown, and" >&2
  echo "       unknown is never clearance. Refusing (fail closed)." >&2
  exit 2
}

head_sha="$(printf '%s' "$raw" | jq -r '.headRefOid // ""' 2>/dev/null)" || head_sha=""
url="$(printf '%s' "$raw" | jq -r '.url // ""' 2>/dev/null)" || url=""
[ -n "$head_sha" ] && [ -n "$url" ] || {
  echo "error: could not resolve the head SHA / URL of PR $pr — the answer would be" >&2
  echo "       about a PR this script cannot identify. Refusing (fail closed)." >&2
  exit 2
}

# The verified head the caller pinned must still be the PR's head. Same guard as the two
# siblings: if it moved, every answer here is about a different state of the pull request,
# which is unknown rather than refused.
if [ -n "$want_head" ] && [ "$want_head" != "$head_sha" ]; then
  echo "error: head moved — verified $want_head, PR $pr is now at $head_sha. The body" >&2
  echo "       read here is not the one that was verified. Refusing (fail closed)." >&2
  exit 2
fi

# An ABSENT body field is a read that did not answer; an EMPTY one is a body somebody
# left blank. Both refuse, but not with the same code — a blank body is a real, readable
# PR missing both elements, and telling its author that is more useful than "unknown".
printf '%s' "$raw" | jq -e 'has("body")' >/dev/null 2>&1 || {
  echo "error: PR $pr reports no body field at all, so its body is unknown rather than" >&2
  echo "       empty. Unknown is never clearance. Refusing (fail closed)." >&2
  exit 2
}
# `-j`, not `-r`: `-r` appends a newline the body does not have, and this file is what
# the ceiling is measured on — so the printed count and the compared count are one number.
printf '%s' "$raw" | jq -j '.body // ""' > "$TMPD/body" 2>/dev/null || {
  echo "error: the body of PR $pr could not be extracted — refusing (fail closed)" >&2
  exit 2
}

report_length "$TMPD/body" "PR $pr body"

render_body "$TMPD/body" "$TMPD/rendered"
decide "$TMPD/body" "$TMPD/rendered" "the body of PR $pr ($url)"; drc=$?

# The clearance record the PreToolUse hook reads offline (ai-bridge-v3/task-044). It is
# written, never read, here — and it can only ever fail silently, so it cannot change the
# answer this script just gave.
if [ "$drc" -eq 0 ]; then
  "$(dirname "${BASH_SOURCE[0]:-$0}")/clearance-receipt.sh" record pr-body-clearance.sh \
    --repo "$(printf '%s' "$url" | sed -E 's#^https?://[^/]+/([^/]+/[^/]+)/pull/[0-9]+.*#\1#')" \
    --pr "$(printf '%s' "$raw" | jq -r '.number // ""' 2>/dev/null)" \
    --head "$head_sha" >/dev/null 2>&1 || true
fi
exit $drc

# --- completeness sentinel — THIS MUST REMAIN THE LAST LINE OF THIS FILE -------
# `--self-test` asserts that the last line of this file is exactly the line below, which
# is how a truncated copy is told from a complete one. See the header.
#EOF: pr-body-clearance.sh is complete to here
