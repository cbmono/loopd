#!/usr/bin/env bash
#
# pr-body-shape.test.sh — the short form for PR bodies, review replies, progress reports
# and GitHub comments keeps every element that was load-bearing BEFORE it got short.
#
# WHY THIS EXISTS. `CONVENTIONS.md` never asked for a long PR body: it asked for the
# task's `acceptance_criteria` with how each was verified, plus a note when a threshold
# fired. The prose accumulated by habit, and the fix is a required shape — a one-sentence
# TL;DR, the criteria as a table, threshold questions as one flagged line each, reasoning
# moved to the commit message and the task doc. The risk that fix carries is precise and
# worth a harness: "be brief" is the most plausible excuse anyone will ever have for
# dropping the CRITERIA TABLE, and the criteria table is a MERGE GATE, not decoration.
# `SCHEMA.md` clause 7 refuses clearance while one row is `✗`, `AUTONOMY.md` repeats it as
# a delegated-merge precondition, and the independent reviewer grades against exactly that
# column. A future edit that shortens the rule by one bullet would delete the gate while
# every other check in this repo stayed green.
#
# So this file does not assert "the document mentions brevity". It asserts, one by one,
# that each element the gate is made of is still NAMED AS REQUIRED:
#   * the table is required, always, and it is the criteria that go in it;
#   * `✓` means verified BY THE AUTHOR, and `✗` is the honest state, not a failure;
#   * a `✗` blocks merge-eligibility, and it says so citing `SCHEMA.md`;
#   * the `✓`/`✗` column IS the checkbox state the clearance predicate reads — pinned in
#     `SCHEMA.md` and `AUTONOMY.md` too, because a table in `CONVENTIONS.md` that no
#     consumer is told to read would be a gate nobody applies;
#   * evidence is named (a command, a test file and its tally, a run, a URL) and brevity
#     is stated to be licence to drop NARRATION, never licence to assert without evidence.
#
# GITHUB COMMENTS ARE PINNED THE SAME WAY, AND FOR THE SAME REASON. The first version of
# this rule covered PR bodies, review replies and progress reports; inline code comments
# and PR thread comments were never named, so they kept the old habit — measured at 2,027
# characters against 120 for the humans on the same pull request. A rule that names its
# surfaces is the fix, so this file pins that the surfaces stay named: the ~280-character
# target, the shape (what is wrong, where, what to do), the three things that do not
# belong (the diff restated, incident history, rejected alternatives), and the answer to
# the question that motivated the rule — that the verbosity buys the AGENT readers
# nothing either, since a reviewing agent reads the diff and the criteria table, not our
# narration. Drop that last clause and the rule loses its justification, which is how a
# future editor talks themselves back into 2,000-character comments.
#
# AND IT PROVES IT CAN FAIL. Every assertion here is re-run against a MUTANT copy of the
# same document with the bullet it depends on deleted, and must flip to absent. A grep
# that would pass against a document with the rule cut out of it is not a check — this
# repo has shipped tests that passed for the wrong reason, and the mutation block below is
# how this one is not another. The control (the TL;DR line, which the mutation does not
# touch) must stay present in the mutant, so "the mutation deleted everything" cannot
# masquerade as a working check.
#
# Matching is done on a NEWLINE-SQUEEZED copy of each document, so a phrase that reflows
# across a line break still matches and a future re-wrap does not turn this red for a
# change nobody made.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONV="$REPO/plugin/seed/CONVENTIONS.md"
SEED="$REPO/plugin/seed/CLAUDE.md"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
AUTONOMY="$REPO/plugin-yolo/companion/AUTONOMY.md"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-body-shape.XXXXXX")" || {
  echo "pr-body-shape.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# One line, single-spaced: phrase matching survives a re-wrap.
flatten() { tr '\n' ' ' < "$1" | tr -s ' '; }

# Delete the bullet that starts with <marker> — from that line to the line before the
# next top-level `- ` bullet. This is the mutation a "just make it shorter" edit would
# make, and every gate assertion below must notice it.
strip_bullet() { # <file> <marker>
  awk -v m="$2" '
    index($0, m) && /^- / { skip=1; next }
    skip && /^- /          { skip=0 }
    !skip                  { print }
  ' "$1"
}

# Delete from the line containing <marker> to the end of its section (the next `## `).
strip_to_heading() { # <file> <marker>
  awk -v m="$2" '
    index($0, m) { skip=1 }
    skip && /^## / { skip=0 }
    !skip { print }
  ' "$1"
}

for f in "$CONV" "$SEED" "$SCHEMA" "$AUTONOMY"; do
  [ -f "$f" ] || { echo "pr-body-shape.test: $f not found" >&2; exit 2; }
done

CONV_FLAT="$(flatten "$CONV")"
SEED_FLAT="$(flatten "$SEED")"
SCHEMA_FLAT="$(flatten "$SCHEMA")"
AUTONOMY_FLAT="$(flatten "$AUTONOMY")"

saw() { # <haystack> <fixed string> -> yes|no
  grep -qF -- "$2" <<<"$1" && echo yes || echo no
}

echo "== 1. the shape: the heading LITERAL, TL;DR, criteria table, flagged line =="
# The heading is asserted as the exact string a gate greps for, in the rule AND in the
# example, because `pr-body-clearance.sh` matches on it: a doc that renamed the heading
# while the predicate kept the old one would refuse every conforming PR.
ok "the opening heading is a LITERAL"     "$(saw "$CONV_FLAT" 'It opens with the literal heading `## Description`')" yes
ok "…named first among the parts"         "$(saw "$CONV_FLAT" '**The heading `## Description`, first**')" yes
ok "…required character for character"    "$(saw "$CONV_FLAT" '**That exact string, character for character**')" yes
ok "the example opens with that heading"  "$(saw "$CONV_FLAT" '```md ## Description')" yes
ok "a one-sentence TL;DR follows it"      "$(saw "$CONV_FLAT" 'then **a one-sentence TL;DR** under it')" yes
ok "the gate that reads it is named"      "$(saw "$CONV_FLAT" 'pr-body-clearance.sh` looks for it at the clearance gate')" yes
ok "the criteria go in a TABLE"           "$(saw "$CONV_FLAT" "task's \`acceptance_criteria\` as a table")" yes
ok "one row per criterion, text verbatim" "$(saw "$CONV_FLAT" 'one row per criterion, its text verbatim')" yes
ok "the example carries a table header"   "$(saw "$CONV_FLAT" '| Criterion | ✓ | Verified by |')" yes
ok "a threshold question is ONE line"     "$(saw "$CONV_FLAT" '**A short flagged line per threshold question**')" yes
ok "…and is not a section or an essay"    "$(saw "$CONV_FLAT" 'Not a section, not an essay.')" yes
ok "reasoning moves to commit + task doc" "$(saw "$CONV_FLAT" '**Reasoning goes in the commit message and the task doc.**')" yes
ok "the reader is a human deciding merge" "$(saw "$CONV_FLAT" '**human deciding whether to merge**')" yes
ok "…not an agent reconstructing work"    "$(saw "$CONV_FLAT" 'not an agent reconstructing how you worked')" yes

echo
echo "== 2. the threshold rules emit that one line, rather than their own sections =="
ok "harness growth is one ⚠️ line"        "$(saw "$CONV_FLAT" '⚠️ Needs your call: harness growth 414 lines.')" yes
ok "PR size is one ⚠️ line"               "$(saw "$CONV_FLAT" 'say so in the PR body as one `⚠️` line')" yes
# The reviewer-notes surfaces are bounded to one line each. Without this, "not an essay"
# is advice; with it, the ceiling is a countable property of each ⚠️ and each ## Notes
# entry — and the section is pinned under the NAME it actually grows back under.
ok "each ⚠️ is bounded to ONE line"       "$(saw "$CONV_FLAT" '**Each `⚠️` stays one line')" yes
ok "…a ⚠️ paragraph is not a flag"        "$(saw "$CONV_FLAT" 'has stopped being a flag')" yes
ok "## Notes is bounded the same way"     "$(saw "$CONV_FLAT" '**one line per note, at most THREE of them, bounded exactly as the `⚠️` lines are.**')" yes
ok "…named as the section that regrows"   "$(saw "$CONV_FLAT" '"Judgement calls for the reviewer" is the heading this section grows under')" yes

echo
echo "== 3. THE GATE: the criteria table is required and blocks a merge when unmet =="
ok "the table is REQUIRED, always"        "$(saw "$CONV_FLAT" '**Required, always**')" yes
ok "it is called the merge gate"          "$(saw "$CONV_FLAT" '**The criteria table is the merge gate')" yes
ok "✓ only for what you verified"         "$(saw "$CONV_FLAT" '**Mark `✓` only for a criterion you actually verified')" yes
ok "…and the rest are marked ✗"           "$(saw "$CONV_FLAT" 'mark the rest `✗`**')" yes
ok "a ✗ blocks merge-eligibility"         "$(saw "$CONV_FLAT" 'A `✗` **blocks the PR from being merge-eligible**')" yes
ok "…citing the SCHEMA.md clause"         "$(saw "$CONV_FLAT" 'An unverified acceptance criterion blocks clearance')" yes
ok "never ✓ because the rest passed"      "$(saw "$CONV_FLAT" 'Never mark `✓` because everything else passed.')" yes
ok "it must travel with the PR"           "$(saw "$CONV_FLAT" 'it must travel with the PR, not just your own')" yes

echo
echo "== 4. the consumers are told to read that same column =="
ok "SCHEMA reads coverage from ✓/✗"       "$(saw "$SCHEMA_FLAT" 'reads *criteria coverage* from the **`✓`/`✗` column**')" yes
ok "SCHEMA still bars prose as an input"  "$(saw "$SCHEMA_FLAT" '**Free prose is never an input**')" yes
ok "SCHEMA clause 7 refuses on one ✗"     "$(saw "$SCHEMA_FLAT" "Every acceptance-criteria row in the PR body's table is \`✓\`.")" yes
ok "AUTONOMY repeats it for the merge"    "$(saw "$AUTONOMY_FLAT" "Every acceptance-criteria row in the PR body's table is \`✓\`.")" yes

echo
echo "== 5. brevity is licence to drop narration, never to assert without evidence =="
ok "short AND auditable is stated"        "$(saw "$CONV_FLAT" '**Short and auditable are the same thing here')" yes
ok "a tally is shorter than a paragraph"  "$(saw "$CONV_FLAT" 'is *shorter* than a paragraph and *more* checkable than one')" yes
ok "…because the reader can re-run it"    "$(saw "$CONV_FLAT" 'names an artifact the reader can re-run')" yes
ok "never licence to assert w/o evidence" "$(saw "$CONV_FLAT" 'licence to assert without evidence')" yes
ok "what counts as evidence is named"     "$(saw "$CONV_FLAT" 'Name the command, the test file and its tally, the CI run, or the URL you loaded.')" yes

echo
echo "== 5b. the row bound is TWO-SIDED: a ceiling AND a readability floor =="
# Both halves are asserted separately, because the failure mode of deleting either one is
# a rule that still reads as sensible. Cut the ceiling and rows grow back to prose; cut
# the floor and "be brief" licenses `ok` and `see above`, which are shorter than a
# paragraph and check nothing — a cheaper failure, not a fixed one.
ok "a row stops at the CLAIM's evidence"  "$(saw "$CONV_FLAT" '**A row carries what a reviewer needs to CHECK THE CLAIM, and stops**')" yes
ok "narration is refused outright"        "$(saw "$CONV_FLAT" '**Narration is not wanted**')" yes
ok "…and what narration means is listed"  "$(saw "$CONV_FLAT" 'not the criterion restated in your own words')" yes
ok "the FLOOR is stated as a floor"       "$(saw "$CONV_FLAT" '**The floor is readability, and it binds exactly as hard as the ceiling')" yes
ok "…a person can check the claim"        "$(saw "$CONV_FLAT" 'a person reading a row can check the claim from it')" yes
ok "…and the cryptic failures are named"  "$(saw "$CONV_FLAT" '`ok`, `done`, `see above` and a bare commit SHA do not')" yes
ok "short is the goal, cryptic a failure" "$(saw "$CONV_FLAT" '**Short is the goal; cryptic is a failure**')" yes

echo
echo "== 5c. Q1's answer is recorded AT the rule, so it is not re-opened =="
# The question ("is the verbosity required for the external reviewer?") was answered by
# the owner on 2026-08-30. Recorded only in a task doc it would be re-derived by the next
# agent, who reads the rule and not the task — so the answer is pinned beside the rule.
ok "the bar is called the rule's test"    "$(saw "$CONV_FLAT" "**That two-sided bar is the rule's own test")" yes
ok "…the question is quoted and dated"    "$(saw "$CONV_FLAT" 'Asked 2026-08-30: is any of this verbosity required for CodeRabbit')" yes
ok "…and answered: NO"                    "$(saw "$CONV_FLAT" 'or another external reviewer? **No.**')" yes
ok "the reviewer is treated as an agent"  "$(saw "$CONV_FLAT" 'Treat the reviewer as an **AI agent**')" yes
ok "…and rows stay human-understandable"  "$(saw "$CONV_FLAT" '**and keep every row human-understandable.**')" yes
ok "BOTH halves are said to bind"         "$(saw "$CONV_FLAT" '**Both halves bind**')" yes
ok "re-surveying the reviewer is refused" "$(saw "$CONV_FLAT" 'rather than surveying past reviewer behaviour to re-derive it')" yes

echo
echo "== 5d. the two-sided bar has a READER, and its numbers are the measured ones =="
# 5b asserts the bar is WRITTEN. This asserts it is READ, which is a different claim and
# the one that was false: the bar shipped 2026-08-29 with nothing checking it and a PR
# breached it the next day. The numbers are pinned here as well as in the script because a
# threshold whose derivation lives only in a shell constant reads as a round number to the
# next agent, and a round number is the first thing somebody "adjusts".
ok "the reader is named at the rule"      "$(saw "$CONV_FLAT" 'That bar has a reader, and the reader is the same one that reads the shape.')" yes
ok "…it measures the EVIDENCE cell"       "$(saw "$CONV_FLAT" "measures **each criteria row's EVIDENCE cell**")" yes
ok "…refuses at its own exit code"        "$(saw "$CONV_FLAT" 'refuses at **exit 3**')" yes
ok "…and names the offending row"         "$(saw "$CONV_FLAT" 'names every offending row by index, length and criterion text')" yes
ok "both bounds are stated as numbers"    "$(saw "$CONV_FLAT" '**Floor 13 bytes, ceiling 400 bytes.**')" yes
ok "evidence goes in the LAST column"     "$(saw "$CONV_FLAT" '**Evidence goes in the LAST column**')" yes
ok "the bound is ONE CELL, not the body"  "$(saw "$CONV_FLAT" '**The bound is on ONE CELL, never on the body.**')" yes
ok "…stated as the OPPOSITE of a cap"     "$(saw "$CONV_FLAT" 'it is the opposite of a body cap')" yes
ok "…and the criterion text is exempt"    "$(saw "$CONV_FLAT" 'The criterion text does not count against the bound')" yes
ok "the corpus and the unit travel too"   "$(saw "$CONV_FLAT" 'Over 34 criteria rows of three real PRs at 2026-08-30T16:24Z (bytes, `LC_ALL=C`)')" yes
ok "…with the per-PR measurements"        "$(saw "$CONV_FLAT" '#67 **92–377**, #70 **19–189**, #71 **160–341** plus **422, 462, 487**')" yes
ok "the ceiling is derived, not chosen"   "$(saw "$CONV_FLAT" '400 is the midpoint of the empty band 378–421')" yes
ok "the floor is derived, not chosen"     "$(saw "$CONV_FLAT" '13 is the midpoint of `see above` (9)')" yes
ok "moving a number means re-measuring"   "$(saw "$CONV_FLAT" '**Moving either number means re-measuring**')" yes
ok "a body in this style clears with room" "$(saw "$CONV_FLAT" '**A body written to this style clears it with room to spare**')" yes
ok "…with that corroborating measurement"  "$(saw "$CONV_FLAT" 'has a longest row of **264 bytes** and a longest evidence cell of **189**')" yes
ok "…so it refuses bloat, not thoroughness" "$(saw "$CONV_FLAT" 'The bound refuses bloat, not thoroughness.')" yes

echo
echo "== 5e. one house style, and the trim/record split that bounds every length rule =="
# The split is the load-bearing half. "Be concise" without it is read as "write less
# everywhere", which trims the commit message and the task doc — the two places the
# reasoning was moved TO. Each surface is therefore named on the side it belongs to.
ok "the style has a name"                 "$(saw "$CONV_FLAT" '**Write for a human who will not read it.**')" yes
ok "…say the thing, then stop"            "$(saw "$CONV_FLAT" 'Say the thing, then stop')" yes
ok "short sentences, one idea each"       "$(saw "$CONV_FLAT" '**Short sentences.** One idea each.')" yes
ok "bullets, tables and icons"            "$(saw "$CONV_FLAT" '**Bullets, tables and icons over paragraphs.**')" yes
ok "…two of a thing makes it a table"     "$(saw "$CONV_FLAT" 'More than two of a thing is a table.')" yes
ok "lead with the outcome"                "$(saw "$CONV_FLAT" '**Lead with the outcome** — what happened and what it means')" yes
ok "the split is stated as a rule"        "$(saw "$CONV_FLAT" '**Trim the transmission, never the record.**')" yes
ok "…the CONCISE surfaces are listed"     "$(saw "$CONV_FLAT" '| PR bodies, review comments and replies, status reports, code comments | **concise**')" yes
ok "…the BOUNDED record is listed"        "$(saw "$CONV_FLAT" '| Commit messages, `Finding`s | **bounded, but wider**')" yes
ok "…the task doc is the unbounded one"   "$(saw "$CONV_FLAT" '| Task docs | **as long as the reasoning needs**')" yes
ok "brevity never drops evidence"         "$(saw "$CONV_FLAT" '**Brevity is never an excuse to drop evidence, a criterion or a caveat.**')" yes
ok "…it is licence to drop NARRATION"     "$(saw "$CONV_FLAT" 'It is licence to drop *narration*')" yes
ok "…the task doc has no length limit"    "$(saw "$CONV_FLAT" 'is the one surface with no length limit')" yes
ok "…so reasoning has nowhere to be lost" "$(saw "$CONV_FLAT" '**So there is nowhere for reasoning to be lost:**')" yes

echo
echo "== 6. review replies: one line per finding, evidence listed, nothing restated =="
ok "one line per finding fixed"           "$(saw "$CONV_FLAT" 'One line per finding **fixed**')" yes
ok "one line per finding not taken"       "$(saw "$CONV_FLAT" 'one line per finding **not taken** (with the reason)')" yes
ok "evidence as a short list"             "$(saw "$CONV_FLAT" 'the evidence as a short list at the end')" yes
ok "never restate the finding back"       "$(saw "$CONV_FLAT" '**Never restate the finding back at the reviewer**')" yes
ok "the reply is a list, not a letter"    "$(saw "$CONV_FLAT" '**The reply is a list, not a letter**')" yes

echo
echo "== 7. GitHub comments: about a tweet, shaped, and no help to an agent either =="
ok "a comment is about 280 characters"    "$(saw "$CONV_FLAT" '**A GitHub comment is about 280 characters — roughly a tweet.**')" yes
ok "inline code comments are named"       "$(saw "$CONV_FLAT" 'an **inline code comment**')" yes
ok "PR thread comments are named"         "$(saw "$CONV_FLAT" 'a **PR thread comment**')" yes
ok "longer only if the finding needs it"  "$(saw "$CONV_FLAT" 'Longer only when the finding genuinely needs it')" yes
ok "…and never by default"                "$(saw "$CONV_FLAT" '**never by default**')" yes
ok "the shape: what/where/what to do"     "$(saw "$CONV_FLAT" '**The shape is: what is wrong, where, and what to do.**')" yes
ok "the example shows that shape"         "$(saw "$CONV_FLAT" '`run.sh:42` — `$dir` is unquoted')" yes
ok "never restate the diff back"          "$(saw "$CONV_FLAT" '**Never restate the diff back at the reader**')" yes
ok "no history, no rejected alternatives" "$(saw "$CONV_FLAT" '**No incident history, no rejected alternatives**')" yes
ok "evidence as a short list, not prose"  "$(saw "$CONV_FLAT" '**Evidence as a short list, not prose.**')" yes
ok "agents do NOT need the verbosity"     "$(saw "$CONV_FLAT" '**The verbosity is not needed for the agent readers either**')" yes
ok "…they read the diff and the table"    "$(saw "$CONV_FLAT" 'reads the **diff** and the **criteria table**, not our narration')" yes
ok "…so brevity costs nothing either way" "$(saw "$CONV_FLAT" '**brevity costs nothing on either side**')" yes
ok "280 is a cost, not a reason"          "$(saw "$CONV_FLAT" '**280 is what a comment MAY cost, never a reason to write one.**')" yes
ok "…so the usual inline count is zero"   "$(saw "$CONV_FLAT" 'the usual number of inline comments in a diff is **zero**')" yes
ok "the measured average is recorded"     "$(saw "$CONV_FLAT" 'averaged **2,027 characters** across 6 inline comments')" yes
ok "…and the 6 is read alongside it"      "$(saw "$CONV_FLAT" '**Read the 6 as well as the 2,027.**')" yes
ok "…against the humans on the same PR"   "$(saw "$CONV_FLAT" 'averaged **120** across 2')" yes
ok "…and the ratio is stated"             "$(saw "$CONV_FLAT" '**17x the humans**')" yes

echo
echo "== 8. progress reports: outcome first, tables, decisions last and short =="
ok "lead with the outcome"                "$(saw "$SEED_FLAT" '**Lead with the outcome**')" yes
ok "tables over paragraphs"               "$(saw "$SEED_FLAT" '**Tables over paragraphs**')" yes
ok "decisions last, and short"            "$(saw "$SEED_FLAT" '**What needs a decision goes last, and short**')" yes
ok "same discipline as a PR body"         "$(saw "$SEED_FLAT" 'same discipline as a PR body')" yes
ok "reasoning lives where it is durable"  "$(saw "$SEED_FLAT" 'Reasoning belongs where it is durable')" yes
ok "the criteria table invariant is here" "$(saw "$SEED_FLAT" "The PR body carries the task's \`acceptance_criteria\` as a table, always")" yes
# The seed carries the invariants that must hold whether or not an agent reached
# CONVENTIONS.md. The heading is now one of them — it is gated, so an agent that never
# read the long rule still has to know the string.
ok "the seed names the heading literal"   "$(saw "$SEED_FLAT" 'The PR body opens with the literal heading `## Description`')" yes
ok "…and says the gate greps for it"      "$(saw "$SEED_FLAT" 'the clearance gate greps for it')" yes
ok "the seed carries the row bound"       "$(saw "$SEED_FLAT" '**A row is a command and its result, not a narration**')" yes
ok "…and the readability floor with it"   "$(saw "$SEED_FLAT" 'Short is the goal; cryptic is a failure.')" yes

echo
echo "== 9. MUTATION: cut the gate bullet out and every gate assertion flips =="
# The edit this file exists to catch: someone "shortens" CONVENTIONS.md by deleting the
# bullet that carries the gate, leaving the shape bullet (and its heading) intact.
strip_bullet "$CONV" '**The criteria table is the merge gate' > "$TMP/conv-no-gate.md"
MUT_FLAT="$(flatten "$TMP/conv-no-gate.md")"
ok "the mutation removed something"       "$([ "$(wc -c < "$TMP/conv-no-gate.md")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no)" yes
ok "CONTROL: the heading survives it"     "$(saw "$MUT_FLAT" '**The heading `## Description`, first**')" yes
ok "CONTROL: the shape bullet survives"   "$(saw "$MUT_FLAT" '**Required, always**')" yes
ok "mutant: ✓-only-if-verified is gone"   "$(saw "$MUT_FLAT" '**Mark `✓` only for a criterion you actually verified')" no
ok "mutant: the merge block is gone"      "$(saw "$MUT_FLAT" 'A `✗` **blocks the PR from being merge-eligible**')" no
ok "mutant: the SCHEMA citation is gone"  "$(saw "$MUT_FLAT" 'An unverified acceptance criterion blocks clearance')" no
ok "mutant: short-AND-auditable is gone"  "$(saw "$MUT_FLAT" '**Short and auditable are the same thing here')" no
ok "mutant: the evidence rule is gone"    "$(saw "$MUT_FLAT" 'licence to assert without evidence')" no
# The row bound, the floor and Q1's answer live in this same bullet, so the "just make it
# shorter" edit takes them too — and each must flip, or its assertion above is passing for
# a reason other than the rule being present.
ok "mutant: the row bound is gone"        "$(saw "$MUT_FLAT" '**A row carries what a reviewer needs to CHECK THE CLAIM, and stops**')" no
ok "mutant: narration-refused is gone"    "$(saw "$MUT_FLAT" '**Narration is not wanted**')" no
ok "mutant: the readability floor is gone" "$(saw "$MUT_FLAT" '**Short is the goal; cryptic is a failure**')" no
ok "mutant: Q1's recorded answer is gone" "$(saw "$MUT_FLAT" 'or another external reviewer? **No.**')" no
ok "mutant: both-halves-bind is gone"     "$(saw "$MUT_FLAT" '**Both halves bind**')" no
# The reader and its two numbers live in this bullet too. Losing them is the worse half of
# the cut: the bar would still READ as a rule while nothing measured it again.
ok "mutant: the named reader is gone"     "$(saw "$MUT_FLAT" 'That bar has a reader, and the reader is the same one that reads the shape.')" no
ok "mutant: the two bounds are gone"      "$(saw "$MUT_FLAT" '**Floor 13 bytes, ceiling 400 bytes.**')" no
ok "mutant: the measurement is gone"      "$(saw "$MUT_FLAT" '400 is the midpoint of the empty band 378–421')" no
ok "mutant: one-cell-not-the-body is gone" "$(saw "$MUT_FLAT" '**The bound is on ONE CELL, never on the body.**')" no

echo
echo "== 10. MUTATION: cut the review bullet, and the reply rules all flip =="
strip_bullet "$CONV" '**One review per PR' > "$TMP/conv-no-reply.md"
REPLY_FLAT="$(flatten "$TMP/conv-no-reply.md")"
ok "CONTROL: the gate survives this cut"  "$(saw "$REPLY_FLAT" '**Required, always**')" yes
ok "mutant: list-not-a-letter is gone"    "$(saw "$REPLY_FLAT" '**The reply is a list, not a letter**')" no
ok "mutant: per-finding lines are gone"   "$(saw "$REPLY_FLAT" 'One line per finding **fixed**')" no
ok "mutant: don't-restate is gone"        "$(saw "$REPLY_FLAT" '**Never restate the finding back at the reviewer**')" no

echo
echo "== 11. MUTATION: cut the progress-report rules from the seed =="
# From the short-form paragraph to the end of its section — what "trim this section"
# would actually delete.
strip_to_heading "$SEED" '**And keep it short — same discipline as a PR body' > "$TMP/seed-no-report.md"
SEEDMUT_FLAT="$(flatten "$TMP/seed-no-report.md")"
ok "CONTROL: the PR-link rule survives"   "$(saw "$SEEDMUT_FLAT" 'link to the real artifacts')" yes
ok "CONTROL: the next section survives"   "$(saw "$SEEDMUT_FLAT" '## Ad-hoc requests vs. the project loop')" yes
ok "mutant: outcome-first is gone"        "$(saw "$SEEDMUT_FLAT" '**Lead with the outcome**')" no
ok "mutant: tables-over-prose is gone"    "$(saw "$SEEDMUT_FLAT" '**Tables over paragraphs**')" no
ok "mutant: decisions-last is gone"       "$(saw "$SEEDMUT_FLAT" '**What needs a decision goes last, and short**')" no

echo
echo "== 12. MUTATION: cut the comment bullet, and every comment assertion flips =="
strip_bullet "$CONV" '**A GitHub comment is about 280 characters' > "$TMP/conv-no-comment.md"
COMMENT_FLAT="$(flatten "$TMP/conv-no-comment.md")"
ok "CONTROL: the gate survives this cut"  "$(saw "$COMMENT_FLAT" '**Required, always**')" yes
ok "CONTROL: the reply rules survive it"  "$(saw "$COMMENT_FLAT" 'One line per finding **fixed**')" yes
ok "mutant: the tweet target is gone"     "$(saw "$COMMENT_FLAT" '**A GitHub comment is about 280 characters — roughly a tweet.**')" no
ok "mutant: the inline surface is gone"   "$(saw "$COMMENT_FLAT" 'an **inline code comment**')" no
ok "mutant: the thread surface is gone"   "$(saw "$COMMENT_FLAT" 'a **PR thread comment**')" no
ok "mutant: the stated shape is gone"     "$(saw "$COMMENT_FLAT" '**The shape is: what is wrong, where, and what to do.**')" no
ok "mutant: don't-restate-the-diff gone"  "$(saw "$COMMENT_FLAT" '**Never restate the diff back at the reader**')" no
ok "mutant: the agent-reader answer gone" "$(saw "$COMMENT_FLAT" '**The verbosity is not needed for the agent readers either**')" no
ok "mutant: the measurement is gone"      "$(saw "$COMMENT_FLAT" 'averaged **2,027 characters** across 6 inline comments')" no
ok "mutant: cost-not-a-reason is gone"    "$(saw "$COMMENT_FLAT" '**280 is what a comment MAY cost, never a reason to write one.**')" no

echo
echo "== 13. MUTATION: cut the shape bullet, and the heading assertions flip =="
# The heading is the one element a machine depends on: `pr-body-clearance.sh` greps for
# `## Description` and refuses a body without it. So the assertions that pin the
# literal need their own mutation — otherwise a future edit could drop the heading from
# the document while the predicate kept refusing on it, and every PR would be refused by
# a rule nobody could find. The gate bullet is the control, since it is a separate bullet.
strip_bullet "$CONV" '**The PR body has a required shape' > "$TMP/conv-no-shape.md"
SHAPE_FLAT="$(flatten "$TMP/conv-no-shape.md")"
ok "the mutation removed something"       "$([ "$(wc -c < "$TMP/conv-no-shape.md")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no)" yes
ok "CONTROL: the gate bullet survives"    "$(saw "$SHAPE_FLAT" '**The criteria table is the merge gate')" yes
ok "CONTROL: the row bound survives"      "$(saw "$SHAPE_FLAT" '**Narration is not wanted**')" yes
ok "mutant: the heading literal is gone"  "$(saw "$SHAPE_FLAT" 'It opens with the literal heading `## Description`')" no
ok "mutant: the example heading is gone"  "$(saw "$SHAPE_FLAT" '```md ## Description')" no
ok "mutant: character-for-character gone" "$(saw "$SHAPE_FLAT" '**That exact string, character for character**')" no
ok "mutant: the named gate is gone"       "$(saw "$SHAPE_FLAT" 'pr-body-clearance.sh` looks for it at the clearance gate')" no
ok "mutant: the one-line ⚠️ bound is gone" "$(saw "$SHAPE_FLAT" '**Each `⚠️` stays one line')" no
ok "mutant: the ## Notes bound is gone"   "$(saw "$SHAPE_FLAT" '**one line per note, bounded exactly as the `⚠️` lines are.**')" no

echo
echo "== 14. MUTATION: cut the house-style bullet, and the trim/record split goes =="
# The bullet most likely to be deleted as "meta", because it states a principle rather
# than a procedure. What goes with it is the sentence that stops "be concise" from being
# applied to the commit message and the task doc — so the surfaces on BOTH sides of the
# split are asserted to vanish together, and the length rules that depend on the split
# (the PR-body shape, the criteria bullet) are the control.
strip_bullet "$CONV" '**Write for a human who will not read it.**' > "$TMP/conv-no-style.md"
STYLE_FLAT="$(flatten "$TMP/conv-no-style.md")"
ok "the mutation removed something"       "$([ "$(wc -c < "$TMP/conv-no-style.md")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no)" yes
ok "CONTROL: the PR-body shape survives"  "$(saw "$STYLE_FLAT" '**The heading `## Description`, first**')" yes
ok "CONTROL: the criteria bullet survives" "$(saw "$STYLE_FLAT" '**Required, always**')" yes
ok "mutant: the style name is gone"       "$(saw "$STYLE_FLAT" '**Write for a human who will not read it.**')" no
ok "mutant: short sentences are gone"     "$(saw "$STYLE_FLAT" '**Short sentences.** One idea each.')" no
ok "mutant: tables-over-prose is gone"    "$(saw "$STYLE_FLAT" '**Bullets, tables and icons over paragraphs.**')" no
ok "mutant: the trim/record split is gone" "$(saw "$STYLE_FLAT" '**Trim the transmission, never the record.**')" no
ok "mutant: the CONCISE surfaces are gone" "$(saw "$STYLE_FLAT" '| PR bodies, review comments and replies, status reports, code comments | **concise**')" no
ok "mutant: the RECORD surfaces are gone" "$(saw "$STYLE_FLAT" '| Task docs, commit messages, `Finding`s | **as long as the reasoning needs**')" no
ok "mutant: evidence-is-never-cut is gone" "$(saw "$STYLE_FLAT" '**Brevity is never an excuse to drop evidence, a criterion or a caveat.**')" no

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
