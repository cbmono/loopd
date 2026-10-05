#!/usr/bin/env bash
# iced — the board is on hold (owner's decision, 2026-10-05). `run.sh --iced`, the nightly
# workflow and any PR whose diff names this file's subject still run it. Thaw: delete these lines.
#
# Exercises the board pair: scripts/write-snapshot.sh (writer) and
# scripts/build-board.sh (renderer).
#
# The properties that matter are the negative ones, in this order:
#   · THE OFF SWITCH. No SNAPSHOT.json ⇒ the writer writes nothing and exits 0, the
#     board omits that instance entirely, and an `install.sh` re-run after `rm` does
#     NOT resurrect the file (the FIRST_STAMP property, same as AWAITING.md). Get any
#     of those wrong and "delete the file to take this instance off the board" stops
#     being true, which is the one promise the whole feature rests on.
#   · THE FIELD ALLOWLIST IS A DATA-GOVERNANCE BOUNDARY, not a format. The board's
#     HTML can be published to a URL, so the snapshot must carry strictly less than
#     AWAITING.md does: no task `description:`, no document body, no open-question or
#     blocker TEXT (a count and a verb instead), no author EMAIL, and no path
#     outside the bundle. These cases assert the ABSENCE of each, plus that no key
#     outside the documented set is emitted at all — so a field added without reading
#     the header fails here rather than on a published page.
#     ONE identity field IS carried, by a decision rather than an oversight: a project's
#     `owner:`, a GitHub username, without which a published board cannot separate this
#     clone's projects from the other owner's. It is in the allowlist below, the
#     `authorEmail` absence is still asserted beside it, and the reasoning is in
#     write-snapshot.sh's header and in
#     /knowledge/findings/board-owner-identity-named-not-redacted.md. The rendering it
#     exists for is pinned by tests/per-owner-board.test.sh.
#   · UNTRUSTED TEXT REACHES AN HTML SINK. A task title is human-written free text
#     that ends up in markup, so an HTML-metacharacter title must appear escaped and
#     ZERO times raw, and a `javascript:`/`data:` PR URL must render as inert text
#     rather than a link — the writer already refuses to collect one, and the board
#     does not trust it to have done so.
#   · THE PAGE'S EXTERNAL SURFACE IS EXACTLY ONE DECLARED WEBFONT, and nothing else:
#     no `@import`, no `src`/`url()` fetch, and every other http(s) href is a PR link.
#     A board is a reporting page; it has no business phoning anywhere else, and a
#     published one must not be able to. It carries ONE <script> — a clipboard helper —
#     and the assertion that matters is that no snapshot text reaches it. Until
#     2026-08-24 this file read "no <script> anywhere", which was true of the DEFAULT
#     `columns` page and never of the one that got published; the kanban page has since
#     been deleted, so the promise is now stated against the page that actually ships.
#   · A BROKEN INSTANCE CANNOT BLANK THE BOARD. A malformed snapshot is a visible
#     note and exit 0, with the other instances still rendered.
#
# The fixture builds its own instances in a temp dir, so these assertions describe
# this test's content rather than whatever the real bundles happen to hold today. The
# hostile snapshot is HAND-WRITTEN on purpose: the writer cannot produce a
# `javascript:` PR URL, and the renderer's defence has to be tested independently of
# the writer's.
#
# assert() follows the convention of the other harnesses here: 0 is a PASS.
set -euo pipefail

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"
WRITER="$TPL/plugin/scripts/write-snapshot.sh"
BOARD="$TPL/plugin/scripts/build-board.sh"
BRIDGE_INSTALL="$TPL/plugin/scripts/init-bundle.sh"
for f in "$WRITER" "$BOARD" "$BRIDGE_INSTALL"; do
  [[ -f "$f" ]] || { echo "snapshot.test: missing $f" >&2; exit 2; }
done
# build-board.sh needs python3 by design (see its header): parsing arbitrary JSON and
# HTML-escaping are the two things a hand-rolled awk reader gets wrong on exactly the
# input this test feeds it. A machine without it cannot run the board at all, so say
# that rather than reporting green on half a feature.
command -v python3 >/dev/null 2>&1 || {
  echo "snapshot.test: needs python3 (build-board.sh does too — see its header)." >&2; exit 2; }

# TWO STEPS, NEVER ONE — the one-expression form is DESTRUCTIVE. When $TMPDIR names a
# directory that does not exist, `mktemp -d` fails, the inner substitution of
# `TMP="$(cd "$(mktemp -d …)" && pwd)"` is empty, `cd ""` SUCCEEDS WITHOUT MOVING (a
# documented bash no-op), `pwd` returns this script's own cwd — the checkout — and the
# trap below deletes it. That happened twice on 2026-08-23. So the creation is guarded
# here, and the normalisation below is handed a path already known good.
# tests/harness-temp-safety.test.sh fails on the one-expression form anywhere in tests/.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/snapshot-fixture.XXXXXX")" || {
  echo "snapshot.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
# `cd`+`pwd` normalises the path: TMPDIR carries a trailing slash on macOS, so the raw
# mktemp result contains `//` — which Python's Path() collapses, silently making the
# "no filesystem path on the page" assertion below match nothing either way.
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT

# install.sh REFUSES to run from a linked git worktree — deliberately, see its own
# header — and every role agent works in one (CONVENTIONS.md), so $TPL routinely IS one.
# This file runs under `set -e`, so letting that guard's exit 2 reach unhandled would
# kill the WHOLE script mid-run with no summary line at all — worse than the 26 failures
# #48/#50 fixed elsewhere, because there is nothing here for the CI runner to key on
# (ai-bridge-v4/task-031). Same fix as tests/board-renderers.test.sh and
# tests/derived-indexes.test.sh, verbatim: a one-time, filesystem-level copy of THIS
# checkout into a directory outside any git repository at all, where the guard's own
# test (`--git-dir` vs `--git-common-dir`) cannot fire for lack of a repository to ask
# about. Skipped entirely — $BRIDGE_INSTALL stays $TPL/plugin/scripts/init-bundle.sh — when $TPL is already
# a main tree or no git repo at all, so a plain clone pays nothing extra here.
if command -v git >/dev/null 2>&1; then
  _tpl_gd="$(git -C "$TPL" rev-parse --absolute-git-dir 2>/dev/null || true)"
  _tpl_gc="$(git -C "$TPL" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "$_tpl_gd" ] && [ -n "$_tpl_gc" ] && [ "$_tpl_gd" != "$_tpl_gc" ]; then
    INSTALL_SRC="$TMP/install-src"
    # The copy below reads all of $TPL, so the destination must not live INSIDE $TPL --
    # $TMP comes from $TMPDIR, which a caller can point anywhere, including into the
    # checkout, and `cp -R "$TPL"/. "$TPL/…"` copies a tree into itself. A resolved-path
    # prefix check against $TPL alone is not enough, though: install.sh's guard fires off
    # $0's own directory, so if $TMP resolves inside SOME OTHER linked worktree instead —
    # not $TPL, just any of them — the copy still sits inside a linked worktree from
    # git's point of view and the guard fires again on the copy, achieving nothing. So
    # this asks the exact question install.sh's own guard asks, of $TMP itself, rather
    # than comparing path text against one specific worktree; same abort-loudly shape as
    # the mktemp guard above (task-017), because a wrong answer here is silent and
    # expensive.
    _tmp_gd="$(git -C "$TMP" rev-parse --absolute-git-dir 2>/dev/null || true)"
    _tmp_gc="$(git -C "$TMP" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
    if [ -n "$_tmp_gd" ] && [ -n "$_tmp_gc" ] && [ "$_tmp_gd" != "$_tmp_gc" ]; then
      echo "snapshot.test: TMPDIR ($TMP) resolves inside a linked git worktree (git dir: $_tmp_gd); the install-source copy would still trip install.sh's own worktree guard. Point TMPDIR outside every worktree, not just this template's." >&2
      exit 2
    fi
    mkdir -p "$INSTALL_SRC"
    cp -R "$TPL"/. "$INSTALL_SRC"/
    rm -rf "$INSTALL_SRC/.git"
    BRIDGE_INSTALL="$INSTALL_SRC/plugin/scripts/init-bundle.sh"
  fi
fi

pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
has()    { grep -qF <<<"$2" -- "$1" && echo 0 || echo 1; }
hasnt()  { grep -qF <<<"$2" -- "$1" && echo 1 || echo 0; }
fhas()   { grep -qF -- "$1" "$2" && echo 0 || echo 1; }
fhasnt() { grep -qF -- "$1" "$2" && echo 1 || echo 0; }
eq()     { [[ "$1" == "$2" ]] && echo 0 || echo 1; }

# Strings that must never leave a task document. Each is planted in exactly one place
# the snapshot is forbidden to read, so a leak names its own source.
SECRET_DESC="SECRET-TASK-DESCRIPTION"
SECRET_BODY="SECRET-DOCUMENT-BODY"
SECRET_QUESTION="SECRET-QUESTION-TEXT"
SECRET_BLOCKER="SECRET-BLOCKER-REASON"
SECRET_EMAIL="secret-person@example.com"
OUT_OF_BUNDLE="/tmp/SECRET-OUT-OF-BUNDLE-ROOT"
# The publisher's own absolute path, planted in exactly one place: a YAML trailing
# comment on a `deliverable_paths:` line whose value carries an unbalanced quote (a hand
# edit — see the `finished` fixture). It reaches the snapshot, and from there a copy
# button on the published board, only if that comment is swallowed into the value.
SECRET_ABS_PATH="/Users/SECRET-PUBLISHER-HOME/private/notes.md"
# A second one, for the vector that carries no comment at all: a `deliverable_paths:`
# value holding TWO paths, the second absolute (the `plain` fixture). It is not a parse
# defect — the writer forwards this key verbatim and the value really is what it says —
# so unlike the one above it DOES reach SNAPSHOT.json, and the assertion that matters is
# about the published PAGE. Kept separate for exactly that reason: sharing one sentinel
# would make "never in the snapshot" and "never on the page" impossible to state apart.
SECRET_PAGE_PATH="/Users/SECRET-PUBLISHER-HOME/Desktop/report.md"
# A third, for the vector that needs neither a comment nor whitespace: an absolute path
# glued to a legitimate one with a `:` (the `colon` fixture). It is its own sentinel
# because it fails for its own reason — the segment class, not the comment cut — and one
# shared needle would make "the cut is right" and "the shape check is right" impossible
# to tell apart when either breaks.
#
# EVERY SEGMENT OF IT IS ORDINARY ON PURPOSE. The obvious spelling of this vector ends in
# `/.ssh/id_rsa`, and that one is rejected by a DIFFERENT rule — a segment may not begin
# with `.` — so a fixture using it stays green when `:` is put back into the class, which
# is the mutation it exists to catch. Measured: with `.ssh` in the sentinel, re-admitting
# `:` passed all three harnesses. Spelled with only word-leading segments after the
# colon, the `:` exclusion is the only thing dropping it.
SECRET_COLON_PATH="/Users/SECRET-PUBLISHER-HOME/Desktop/keys.txt"
# A fourth, for `depends_on`: a trailing comment naming a file off the publisher's own
# disk (the `ci` project's task-008 fixture). Unlike the three above this is not about
# a path reaching the page — depends_on carries bare task IDs, never a path, so a
# leak here would be a FRAGMENT of this string, not the whole thing (see task-008's own
# comment for the exact fragment and why). Kept as its own sentinel so "the real edge
# survives" and "no fragment of the comment leaks in its place" stay two assertions,
# not one guess at a shared string doing both jobs.
SECRET_DEP_COMMENT_PATH="/Users/SECRET-PUBLISHER-HOME/private/notes[1].md"
# An HTML-metacharacter title, and the two forms it may appear in on the page.
HOSTILE_TITLE='<script>alert(1)</script> & <b>bold</b>'
HOSTILE_ESCAPED='&lt;script&gt;alert(1)&lt;/script&gt;'

echo "== shell portability of the shipped scripts =="
# These two scripts get symlinked into instances on machines this repo never sees, so
# a GNU-only regex escape is a silent wrong ANSWER rather than an error: `\b` in an ERE
# degrades count_questions to its 1-item fallback on a grep that does not implement it.
# NOTE, honestly: this machine's /usr/bin/grep is BSD grep 2.6.0-FreeBSD, which DOES
# support \b — verified, including that it is a true word boundary and not a literal
# `b`. So no runtime fixture can demonstrate the difference here, and asserting one
# would be a test that passes for the wrong reason. The portable POSIX bracket form is
# used instead, and THIS is the assertion that holds the line: a static check that the
# escape has not come back. It is the only form of this test that can actually fail.
# Comment lines are stripped first: the fix's own comment NAMES the escape it removed,
# and that prose is the record of why. Only executable lines are checked.
# AND THIS CHECK WAS ITSELF VACUOUS UNTIL 2026-08-27 — the `grep -q` was the bug. Under
# this file's `set -o pipefail`, `grep -q` exits at the FIRST match and SIGPIPEs whatever
# is still feeding it, so the pipeline reports the FEEDER's 141 rather than grep's 0: the
# `&&` never fires and a file that DOES carry the escape is reported clean. Measured,
# with `\s` on line 808 of a 1,260-line build-board.sh: PASS. It is not fixed by moving
# the sed into a variable — a `printf … | grep -q` behind it SIGPIPEs exactly the same
# way, which cost a second attempt here. `grep -c` is the fix, because it consumes ALL of
# its input and so never signals the writer; the planted-escape assertion below is what
# stops either vacuous form coming back unnoticed.
no_gnu_escape() { # <file> <escape letter>
  local body hits
  body="$(sed 's/^[[:space:]]*#.*$//' "$1")"
  hits="$(printf '%s\n' "$body" | grep -c "\\\\$2" || true)"
  [[ "$hits" == 0 ]]
}
for f in "$WRITER" "$BOARD"; do
  assert "no GNU-only \\b escape in $(basename "$f")" "$(yes_if no_gnu_escape "$f" b)"
  assert "no GNU-only \\s escape in $(basename "$f")" "$(yes_if no_gnu_escape "$f" s)"
done
# The check, checked, in both directions — and the FILE SIZE is load-bearing, not
# decoration. The vacuous form fails only once the pipe FILLS: `grep -q` exits at the
# first match and SIGPIPEs the sed behind it, and with a small file sed has already
# finished writing, so a short fixture reproduces nothing and the mutant survives
# (measured: reverting the fix passed a 1,300-line plant). The escape therefore sits at
# the TOP with tens of thousands of lines behind it, which is the real shape — the
# original defect had `\s` on line 808 of a 1,260-line script whose lines are long.
PLANT="$TMP/plant-escape.sh"
{ printf 'y=%s\n' '"[^/\s#]+"'; seq 40000 | sed 's/.*/x=1/'; } > "$PLANT"
PLANT_OK="$TMP/plant-comment-only.sh"
{ printf '%s\n' '# this comment names the \s escape it removed'; seq 40000 | sed 's/.*/x=1/'; } > "$PLANT_OK"
assert "…and the check itself sees a planted \\s once the pipe fills" \
  "$( no_gnu_escape "$PLANT" s && echo 1 || echo 0 )"
assert "…while an \\s that appears only in a comment is still not a hit" \
  "$( no_gnu_escape "$PLANT_OK" s && echo 0 || echo 1 )"

# ---------------------------------------------------------------- fixture instances
new_instance() { # <dir> — the minimum the writer requires of an instance root
  mkdir -p "$1" "$1/$AB_DIR"
  : > "$1/$AB_SCHEMA"
  cat > "$1/instance.config.json" <<CFG
{
  "org": "fixture-org",
  "reposRoot": "$OUT_OF_BUNDLE",
  "worktreeRoot": "$OUT_OF_BUNDLE/_wt",
  "authorEmail": "$SECRET_EMAIL"
}
CFG
}

ALPHA="$TMP/group/_ai-bridge-alpha"     # full content, and the one the writer runs in
BETA="$TMP/group/_ai-bridge-beta"       # malformed snapshot
GAMMA="$TMP/group/_ai-bridge-gamma"     # no snapshot at all — off the board
DELTA="$TMP/group/_ai-bridge-delta"     # hand-written hostile snapshot
new_instance "$ALPHA"; new_instance "$BETA"; new_instance "$GAMMA"; new_instance "$DELTA"

mkdir -p "$ALPHA/projects/ci/tasks" "$ALPHA/projects/ci/phases" \
         "$ALPHA/projects/empty" "$ALPHA/projects/finished/tasks"

cat > "$ALPHA/projects/ci/project.md" <<PRJ
---
type: Project
title: CI hardening
description: make the pipeline boring again
kind: build
status: active
autonomy: gated
---
# Context
$SECRET_BODY
PRJ
cat > "$ALPHA/projects/ci/phases/phase-1.md" <<'PH'
---
type: Phase
title: Groundwork
order: 1
status: done
---
PH
cat > "$ALPHA/projects/ci/phases/phase-2.md" <<'PH'
---
type: Phase
title: Rollout
order: 2
status: active
---
PH

# draft + open questions  ⇒ awaiting "answer", carrying the COUNT and not the text
cat > "$ALPHA/projects/ci/tasks/task-001.md" <<TSK
---
type: Task
title: '$HOSTILE_TITLE'
kind: build
status: draft
assignee: software-engineer
phase: projects/ci/phases/phase-1.md
description: $SECRET_DESC
open_questions: [ "Q1: $SECRET_QUESTION", "Q2: $SECRET_QUESTION again" ]
acceptance_criteria: []
pr: []
---
# Notes
$SECRET_BODY
TSK
# in-review + a PR + the tick's MERGEABLE read ⇒ awaiting "merge". Without that last
# term this used to be `status` plus a link, which is how three CONFLICTING pull requests
# were presented as merge rows on 2026-09-13.
cat > "$ALPHA/projects/ci/tasks/task-002.md" <<TSK
---
type: Task
title: Bump the pinned toolchain
kind: build
status: in-review
assignee: software-engineer
depends_on: [ /projects/ci/tasks/task-001.md ]
open_questions: []
pr_mergeable: MERGEABLE
pr: [ "https://github.com/acme/monorepo/pull/2725" ]
---
TSK
# The same shape the host reported CONFLICTING: a rebase round, never a merge row.
cat > "$ALPHA/projects/ci/tasks/task-009.md" <<TSK
---
type: Task
title: Widen the retry window
kind: build
status: in-review
assignee: software-engineer
pr_mergeable: CONFLICTING
pr: [ "https://github.com/acme/monorepo/pull/2726" ]
---
TSK
# And a PR no tick has asked the host about. Absent is not MERGEABLE.
cat > "$ALPHA/projects/ci/tasks/task-010.md" <<TSK
---
type: Task
title: Drop the legacy shim
kind: build
status: in-review
assignee: software-engineer
pr: [ "https://github.com/acme/monorepo/pull/2727" ]
---
TSK
# blocked  ⇒ awaiting "unblock", the VERB and never the reason
cat > "$ALPHA/projects/ci/tasks/task-003.md" <<TSK
---
type: Task
title: Rotate the publish token
kind: build
status: blocked
assignee: devops-engineer
description: blocked because $SECRET_BLOCKER
depends_on:
  - /projects/ci/tasks/task-001.md
  - /projects/ci/tasks/task-002.md
open_questions: []
---
# Notes
$SECRET_BLOCKER
TSK
# refined draft, no questions  ⇒ awaiting "approve" (the promote gate; a task already
# at `ready` awaits nothing — it is waiting on a dispatch, not on a human)
cat > "$ALPHA/projects/ci/tasks/task-004.md" <<'TSK'
---
depends_on: [ "/projects/ci/tasks/task-001.md", "/projects/ci/tasks/task-002.md" ]
advisor_notes: [ "Should this be split before dispatch?", "Is the target repo right?" ]
type: Task
title: Add a smoke test
kind: build
status: draft
assignee: qa-reviewer
open_questions: []
acceptance_criteria: [ "it runs in CI" ]
---
TSK
# in-progress  ⇒ in_flight, awaiting nothing
cat > "$ALPHA/projects/ci/tasks/task-005.md" <<'TSK'
---
type: Task
title: Cache the dependency store
kind: build
status: in-progress
assignee: software-engineer
---
TSK

# Two open questions, EACH carrying a `]` before the list's own closing bracket: one a
# Markdown PR link in the `[repo#N](url)` style this bundle's own CLAUDE.md mandates
# for citing PRs, the other just ordinary brackets. This is the fixture that says WHY
# list_region() is comment-agnostic and the trailing-comment strip lives at the
# `deliverable_paths` consumer instead. Two attempts to strip from the shared helper
# both ended this list early: one truncated at the FIRST `]`, inside Q1's own link; the
# next tracked quote parity and stopped at that SAME `]`, because Q1's link sits between
# two ESCAPED quotes and counting `"` characters reads the parity as "outside a quote".
# Either way Q2 vanished off a list that gates draft -> ready and feeds AWAITING.md, and
# a dropped entry shows up nowhere. One fixture, both wrong answers — whatever decides
# where a free-text list ends must never be something an entry's own text can spell.
cat > "$ALPHA/projects/ci/tasks/task-006.md" <<'TSK'
---
type: Task
title: Fix the bracket-swallowing question count
kind: build
status: draft
assignee: software-engineer
open_questions: [ "Q1: keep the \"[repo#42](https://github.com/acme/x/pull/42)\" style?", "Q2: bracket [note] mid-question" ]
pr: []
---
TSK

# `acceptance_criteria: []` with a trailing YAML comment, on a draft with NO open
# questions. list_filled()'s bracket-and-whitespace strip left the comment text behind
# and read that leftover as "the list is non-empty" — so a task with NO real criteria
# at all was reported `awaiting: "approve"`. `approve` is read straight off this field
# for AWAITING.md, so this invented a queue item out of a comment, which is exactly the
# one thing that surface's own rule forbids (never invent an item).
cat > "$ALPHA/projects/ci/tasks/task-007.md" <<'TSK'
---
type: Task
title: Still shaping this one
kind: build
status: draft
assignee: software-engineer
acceptance_criteria: []  # nothing decided yet, still refining the shape
open_questions: []
---
TSK

# `depends_on` with a trailing comment that itself names a file off the publisher's
# own disk. Before the fix, the unstripped comma-split treated the WHOLE rest of the
# line — bracket, comment and all — as the one entry's text, so:
#   · the real edge (task-001) was lost, and
#   · `sed 's#^.*/##; s#\.md$##'` (meant to turn a bundle path into a bare ID) instead
#     took the LAST slash-terminated segment of the comment's own path and stripped
#     ITS `.md`, fabricating the ID `notes[1]` — a fragment of a local filesystem path,
#     never in the allowlist, standing in for a real structural reference the board draws.
cat > "$ALPHA/projects/ci/tasks/task-008.md" <<TSK
---
type: Task
title: Ship the thing task-001 blocks on
kind: build
status: draft
assignee: software-engineer
depends_on: [ /projects/ci/tasks/task-001.md ]   # blocked by $SECRET_DEP_COMMENT_PATH
acceptance_criteria: [ "ships" ]
open_questions: []
---
TSK

# THE SHAPES A REAL BOARD'S QUESTIONS ACTUALLY HAVE, in one project, because the field
# they feed is the whole point of this round. Reproduced from a live 8-project instance
# whose 38 open questions are ALL `Q<n>`-prefixed and whose renderer still rendered a
# generic `answer question` for every one of them — because the snapshot carried a COUNT
# and the renderer had nothing to read.
#
# Each entry is a different way the number arrives, and the fourth is the honest absence:
#   · `Q1 (HALF ANSWERED …` — NO COLON after the number. This is a real entry from that
#     board, and the writer's old token count (`Q[0-9]+[.:]`) does not see it at all;
#   · a STAMPED entry, `<iso> · Q2: …`, which is what the PM writes today;
#   · an ESCALATED one, `advisor: Q3. …`, with a `.` and a comma in its prose;
#   · one with no `Q<n>` at all, which must stay unnumbered and must still count.
# The question TEXT carries $SECRET_QUESTION so the file-wide "text never reaches the
# snapshot" assertion covers this new field too, rather than only the old fixture.
mkdir -p "$ALPHA/projects/qshapes/tasks"
cat > "$ALPHA/projects/qshapes/project.md" <<'PRJ'
---
type: Project
title: Question shapes
description: every way a question names its number
kind: build
status: active
---
PRJ
cat > "$ALPHA/projects/qshapes/tasks/task-044-the-dwd-calendar-grant.md" <<TSK
---
type: Task
title: Three questions, three shapes
kind: build
status: draft
assignee: software-engineer
open_questions: [ "Q1 (HALF ANSWERED 2026-08-29) $SECRET_QUESTION", "2026-08-30T16:01:52Z · Q2: $SECRET_QUESTION", "advisor: Q3. $SECRET_QUESTION, and a comma" ]
acceptance_criteria: []
pr: []
---
TSK
# THE MARKER CAN COME BEFORE THE STAMP AS WELL AS AFTER IT, and the lead skip is
# BOUNDED, so the two are not interchangeable: with `advisor: ` still in front, this
# entry's `·` sits past the 41-character bound and the lead is not skipped at all, so
# the number is never reached. Skipping the marker first brings the `·` back inside the
# bound. Contrived-looking and deliberately so — it is the one band in which the first
# of the two marker skips is the only thing doing any work, and without it that branch
# is code no fixture reaches. build-board.sh's Q_LEAD has the same pair for the same
# reason, and reads this entry identically.
cat > "$ALPHA/projects/qshapes/tasks/task-047-marker-first.md" <<TSK
---
type: Task
title: An escalation stamped after the marker
kind: build
status: draft
assignee: software-engineer
open_questions: [ "advisor: 2026-08-30T16:01:52Z (escalated) · Q5: $SECRET_QUESTION" ]
acceptance_criteria: []
pr: []
---
TSK
# A NUMBER MUST END WHERE IT IS READ, on the writer's side too. `Q1234` read as `Q123`
# is a label that is not in the document, on a control claiming to have read it — the
# renderer's own guard against this is pinned in artifact-board.test.sh, and the writer
# needs its own because the renderer now trusts the label it is handed.
cat > "$ALPHA/projects/qshapes/tasks/task-046-runs-on.md" <<TSK
---
type: Task
title: Numbers that do not end where they are read
kind: build
status: draft
assignee: software-engineer
open_questions: [ "Q1234: $SECRET_QUESTION four digits", "Q2x: $SECRET_QUESTION a letter straight after" ]
acceptance_criteria: []
pr: []
---
TSK
cat > "$ALPHA/projects/qshapes/tasks/task-045-no-number.md" <<TSK
---
type: Task
title: A question that names no number
kind: build
status: draft
assignee: software-engineer
open_questions: [ "$SECRET_QUESTION with no prefix at all" ]
acceptance_criteria: []
pr: []
---
TSK

# A project with no tasks at all — must render empty rather than error.
cat > "$ALPHA/projects/empty/project.md" <<'PRJ'
---
type: Project
title: Nothing here yet
description: scaffolded, not started
kind: research
status: active
---
PRJ

# The COMMA-SPLIT shape, and it needs its own project because it needs an UNQUOTED
# value — the `finished` fixture below opens a quote, which sends the splitter down its
# quote-seam branch and cannot split on a comma at all.
#
# What it pins: a swallowed trailing comment is not one bad entry, it is TWO. The
# entries are re-split on commas after the value is taken, so a comment containing one
# puts the `#` in the first fragment and everything after the comma in the SECOND — and
# that second fragment carries this project's own `/projects/<slug>/deliverables/`
# prefix, no `..`, and no `#`, so every per-entry rule the renderer applies passes it
# and the publisher's absolute path renders as a copy button. A per-entry guard cannot
# see this; the comment has to be gone before the split. The `[old]` at the end is not
# decoration either: it puts a `]` after the comment's `#`, which is exactly the case a
# strip anchored on the LAST bracket of the line declines to touch.
mkdir -p "$ALPHA/projects/handedited"
cat > "$ALPHA/projects/handedited/project.md" <<PRJ
---
type: Project
title: Hand-edited deliverables
description: someone typed the deliverable_paths line themselves
kind: research
status: active
deliverable_paths: [ /projects/handedited/deliverables/report.md ]   # hand-edited; kept, /projects/handedited/deliverables/see $SECRET_ABS_PATH [old]
---
PRJ

# The SAME hazard in the OTHER YAML shape. A block sequence's key line carries no `]`
# at all, so a cut that waits for a flow terminator cannot fire here and the comment
# would ride into the entry — where the comma splits it exactly as above. This fixture
# is the one that says the block case is load-bearing: without it the suite stays green
# while a block-form list leaks.
#
# Its SECOND entry is the block mirror of the `quoted` fixture below: ` #` opens a
# comment on a block line, but NOT inside a quoted scalar, so Psych reads
# `b #2.md` whole. Cutting there fabricates `.../b`, a path no parser returned — which
# is why this entry must survive into the snapshot intact and reach no button.
mkdir -p "$ALPHA/projects/blockform"
cat > "$ALPHA/projects/blockform/project.md" <<PRJ
---
type: Project
title: Block-form deliverables
description: the same key, written as a block sequence
kind: research
status: done
retain: true
deliverable_paths:
  - /projects/blockform/deliverables/notes.md  # hand-edited; kept, /projects/blockform/deliverables/see $SECRET_ABS_PATH
  - "/projects/blockform/deliverables/b #2.md"
---
PRJ

# THE VECTOR THAT NEEDS NO COMMENT, no quote and no bracket — the one four review rounds
# of comment-stripping could not have caught, because there is nothing to strip. Two
# paths in one value: the first is this project's own, the second is off the publisher's
# disk, and the whole string carries the correct prefix, no `..` and no `#`. Rendered as
# one value it is a copy button labelled `report.md`, which looks exactly right.
#
# It reaches SNAPSHOT.json verbatim and that is BY DESIGN — this file forwards the key
# and does not check its shape (see write-snapshot.sh's header), the snapshot is
# gitignored and never published as-is. Hence a SECOND sentinel: the assertions below
# say this one must never reach the PAGE, which is the artifact that leaves the machine.
mkdir -p "$ALPHA/projects/plain"
cat > "$ALPHA/projects/plain/project.md" <<PRJ
---
type: Project
title: Two paths, one value
description: no comment, no quote, no bracket — and still not one path
kind: research
status: done
retain: true
deliverable_paths: [ /projects/plain/deliverables/report.md $SECRET_PAGE_PATH ]
---
PRJ

# AN UNQUOTED `]` ENDS THE FLOW SEQUENCE — settled against a real YAML parser, not by
# eye. Ruby's Psych reads this line as ONE entry, `.../a`: in flow context a plain
# scalar cannot contain `]`, so the first unquoted one is the terminator and
# ` #1.md, .../b.md ]` is a COMMENT. `b.md` is therefore not a stamped deliverable at
# all, and rendering it would invent a path out of comment text — the same defect as
# truncating one, reached from the other side. An earlier revision did exactly that,
# and a test written from the eye rather than the parser called it correct.
#
# What must happen: `.../a` renders, because it is the entry; `b.md` does not, because
# it is comment. The fixture whose sibling really IS a sibling is `quoted`, below —
# quoting is what makes `]` an ordinary character and leaves YAML two entries to keep.
mkdir -p "$ALPHA/projects/sibling"
cat > "$ALPHA/projects/sibling/project.md" <<'PRJ'
---
type: Project
title: A bracket inside a filename
description: an unquoted ] is the flow terminator, so the rest of the line is a comment
kind: research
status: done
retain: true
deliverable_paths: [ /projects/sibling/deliverables/a] #1.md, /projects/sibling/deliverables/b.md ]
---
PRJ

# THE SHAPE WHERE THE SIBLING IS REAL, and the blocker this round exists to close.
# Inside a QUOTED scalar neither `]` nor `#` is special, so Psych reads TWO entries
# here: `a ] #1.md` (whitespace in it, so the renderer drops it, visibly) and `b.md`, a
# perfectly good deliverable a human stamped. A cut that reads that `#` as a comment
# fails in both directions at once — it fabricates `.../a`, a path no parser ever read,
# and it deletes `b.md` with nothing to show it ever existed. NOTHING LEAKS either way,
# which is precisely why only a parser could settle it and five rounds of argument did
# not.
mkdir -p "$ALPHA/projects/quoted"
cat > "$ALPHA/projects/quoted/project.md" <<'PRJ'
---
type: Project
title: A quoted entry carrying ] and #
description: inside quotes neither is special, so YAML has two entries on this line
kind: research
status: done
retain: true
deliverable_paths: [ "/projects/quoted/deliverables/a ] #1.md", "/projects/quoted/deliverables/b.md" ]
---
PRJ

# A FLOW SEQUENCE THAT NEVER TERMINATES — the shape with no parser answer at all, since
# Psych refuses the document outright. Which is exactly why it needs pinning: where
# there is no reading to be faithful to, the cut must fail toward "leave the line alone
# and let the shape check drop whatever it drops", never toward "cut anyway". Cutting at
# this line's ` #` hands the renderer `.../a` — a filename truncated into a path nobody
# wrote, on the one input class that cannot be settled by argument. Declining leaves the
# comma split to do the honest thing: the fragment carrying whitespace goes, `b.md`
# stays.
mkdir -p "$ALPHA/projects/unterminated"
cat > "$ALPHA/projects/unterminated/project.md" <<'PRJ'
---
type: Project
title: An inline list with no closing bracket
description: not valid YAML at all, so the cut declines rather than guesses
kind: research
status: done
retain: true
deliverable_paths: [ /projects/unterminated/deliverables/a #1.md, /projects/unterminated/deliverables/b.md
---
PRJ

# THE OTHER QUOTE STYLE, AND YAML'S ONLY SINGLE-QUOTE ESCAPE — the shape a green suite
# stayed green over. Every deliverable fixture above this one is flow-form and UNQUOTED,
# so a scan that handled the `\"` escape but had no case for `''` was never exercised:
# it closed the scalar at the FIRST quote of the pair and cut INSIDE a string Psych reads
# as a single atom. Psych's reading here is TWO entries — `o'brien[draft].md #2`, which
# the render-time shape check then drops on its own merits, and `clean.md`, a perfectly
# good deliverable a human stamped. The defect rendered the first (fabricated) and
# deleted the second, which is both halves of the failure at once.
mkdir -p "$ALPHA/projects/sqescaped"
cat > "$ALPHA/projects/sqescaped/project.md" <<'PRJ'
---
type: Project
title: A single-quoted entry with an escaped apostrophe
description: a doubled quote inside a single-quoted scalar is an apostrophe, not its end
kind: research
status: done
retain: true
deliverable_paths: [ '/projects/sqescaped/deliverables/o''brien[draft].md #2', /projects/sqescaped/deliverables/clean.md ]
---
PRJ

# The ordinary single-quoted list, which nothing exercised either. It carries no trap at
# all, and that is the point: the quote handling added for the trap above must not cost
# the plain case its entries.
mkdir -p "$ALPHA/projects/sqplain"
cat > "$ALPHA/projects/sqplain/project.md" <<'PRJ'
---
type: Project
title: An ordinary single-quoted list
description: both entries are stamped deliverables and both must render
kind: research
status: done
retain: true
deliverable_paths: [ '/projects/sqplain/deliverables/a.md', '/projects/sqplain/deliverables/b.md' ]
---
PRJ

# CRITERION 4, REACHED THROUGH A CHARACTER NO DENYLIST HAD THOUGHT OF. No comment, no
# whitespace, no `..`, no `#`, prefix perfectly correct — an absolute path glued on with
# a `:`, rendered whole into a copy button and labelled `id_rsa` so nothing looked wrong.
# It is the fifth character to defeat the same move, which is why the segment class is
# now stated as what a filename MAY contain rather than as a list of what it may not.
mkdir -p "$ALPHA/projects/colon"
cat > "$ALPHA/projects/colon/project.md" <<PRJ
---
type: Project
title: An absolute path glued on with a colon
description: prefix-correct, whitespace-free, and still two paths
kind: research
status: done
retain: true
deliverable_paths: [ "/projects/colon/deliverables/deck.md:$SECRET_COLON_PATH" ]
---
PRJ

# A NON-ASCII FILENAME, and it is a fixture rather than a nicety: this awk is
# byte-oriented, so substr() hands back one BYTE of a multi-byte character, and testing
# that byte with a regex aborted the whole program — taking the clean sibling on the same
# line with it and printing a parser error into the run's output. A `deliverables/` full
# of German or Japanese filenames is not exotic; losing the entire key over one of them
# is the kind of failure nobody attributes to a comment strip.
#
# The MIDDLE entry earns its place separately: it puts a multi-byte character immediately
# before a `#`, which is the scan's OTHER per-character test — the one deciding whether a
# `#` opens a comment. Without it that branch is UNPINNED, measured: a mutant reverting
# only that branch passes all three harnesses. `roh-Ü#1.md` is not a comment (YAML wants
# whitespace before the `#`), so it survives to the snapshot and is dropped at render on
# its own merits, leaving the two clean siblings to show the key came through whole.
mkdir -p "$ALPHA/projects/umlaut"
cat > "$ALPHA/projects/umlaut/project.md" <<'PRJ'
---
type: Project
title: A deliverable whose name is not ASCII
description: one multi-byte character must not cost the key its entries
kind: research
status: done
retain: true
deliverable_paths: [ /projects/umlaut/deliverables/Übersicht.md, /projects/umlaut/deliverables/roh-Ü#1.md, /projects/umlaut/deliverables/plain.md ]
---
PRJ

# NFD — the SAME filename macOS hands back DECOMPOSED, which is a legitimately stamped
# deliverable rather than an exotic input: a macOS directory listing spells `Ü` as
# `U` + U+0308, so closeout resolving an `artifacts:` entry off one stamps exactly this.
# The segment class admitted `\w`, which does NOT include a combining mark (Unicode
# category M) — so the entry was dropped, the project rendered one deliverable short,
# and the count tag agreed with the short list, so nothing looked wrong. That is the
# "loses a real entry" class, reached through a filename instead of through a comment.
#
# The name is BUILT from an escape rather than typed, because an editor or a formatter
# that normalises this file would otherwise turn the fixture into its NFC twin silently
# and leave the assertions green over a case the file no longer contains. The first
# assertion below is what makes that non-vacuous.
NFD_UE="$(printf 'U\xcc\x88')"          # U+0055 U+0308 — NOT the single codepoint U+00DC
NFD_NAME="${NFD_UE}bersicht-nfd.md"
mkdir -p "$ALPHA/projects/nfd"
cat > "$ALPHA/projects/nfd/project.md" <<PRJ
---
type: Project
title: A deliverable macOS handed back decomposed
description: a combining mark belongs to a legitimate filename, not to an attack
kind: research
status: done
retain: true
deliverable_paths: [ /projects/nfd/deliverables/$NFD_NAME ]
---
PRJ

# Every task terminal ⇒ the board shows a close PROPOSAL, never an action.
#
# Its `deliverable_paths:` line is the HAND-EDITED shape: someone opened a quote and
# never closed it, and left a trailing comment naming a path on their own disk. Psych
# REFUSES this document — an unterminated quoted scalar is not YAML — so there is no
# parser reading to defer to here, and the cut falls back to a quote-blind scan rather
# than dropping a path a human can plainly read. What must not happen is the other
# thing: a strip that looked for the list's `]` while tracking quote state found no
# unquoted `]`, truncated nothing, and the whole comment — absolute path included —
# became the deliverable path a copy button carries on the published board.
cat > "$ALPHA/projects/finished/project.md" <<PRJ
---
type: Project
title: Docs cleanup
kind: build
status: active
deliverable_paths: [ "/projects/finished/deliverables/report.md ]   # hand-edited; taken from $SECRET_ABS_PATH
---
PRJ
cat > "$ALPHA/projects/finished/tasks/task-001.md" <<'TSK'
---
type: Task
title: Fix the broken links
status: done
assignee: cataloguer
---
TSK

# A DONE project. Its folder survives closeout (`retain: true`), so the writer meets it
# on every tick — and must stop at this frontmatter. The task below is planted to be
# LOUD if it is ever read: an open question, a PR, and a blocked status would each move
# a count and add an awaiting verb, and its title is a sentinel that can only appear in
# the snapshot by way of `tasks/`.
mkdir -p "$ALPHA/projects/retained/tasks" "$ALPHA/projects/retained/phases"
cat > "$ALPHA/projects/retained/project.md" <<'PRJ'
---
type: Project
title: AI adoption research
description: finished, kept as a reference surface
kind: research
status: done
retain: true
# The trailing comment is SCHEMA.md:72's documented comment for this key, VERBATIM and
# whole — commas, backticks and the `[ ]` it names included. A real project.md is
# allowed to look like this, so the fixture does too rather than the tidier form the
# writer would produce itself. Copying only its FIRST SENTENCE is what an earlier round
# did, and it cut the line one word before the `[ ]` that makes it hard: a comment
# carrying a `]` of its own defeats any strip that decides where the list ends by
# looking for the LAST bracket on the line. Green over the easy half of the case it
# names is worse than no test — if you shorten this line, you have deleted the test.
deliverable_paths: [ /projects/retained/deliverables/deck.md ]   # WRITTEN BY CLOSEOUT, not by hand. Bundle-relative paths, resolved once from each task's `artifacts:` and verified on disk at closeout. `[ ]` means closeout looked and found none.
---
PRJ
cat > "$ALPHA/projects/retained/phases/phase-1.md" <<'PH'
---
type: Phase
title: SENTINEL-DONE-PHASE
order: 1
status: active
---
PH
cat > "$ALPHA/projects/retained/tasks/task-001.md" <<'TSK'
---
type: Task
title: SENTINEL-DONE-PROJECT-TASK
kind: research
status: blocked
assignee: software-engineer
open_questions: [ "Q1: would change the awaiting count", "Q2: and the question count" ]
pr: [ "https://github.com/acme/monorepo/pull/9999" ]
---
TSK

echo "== the off switch: absence, on the writer's side =="
SNAP="$ALPHA/$AB_SNAPSHOT"
OFF_RC=0; OFF_OUT="$( cd "$ALPHA" && bash "$WRITER" 2>&1 )" || OFF_RC=$?
assert "no SNAPSHOT.json -> exits 0"              "$(eq "$OFF_RC" 0)"
assert "no SNAPSHOT.json -> the file is NOT created" "$(yes_if test ! -e "$SNAP")"
assert "…and it says the instance is off the board"  "$(has 'off the board' "$OFF_OUT")"
assert "…and names the way back in"                  "$(has "touch $AB_SNAPSHOT" "$OFF_OUT")"
Q_OUT="$( cd "$ALPHA" && bash "$WRITER" --quiet 2>&1 )" || true
assert "--quiet with no snapshot is completely silent" "$(eq "$Q_OUT" "")"
assert "…and still creates nothing"                   "$(yes_if test ! -e "$SNAP")"

echo "== refusals =="
mkdir -p "$ALPHA/SNAPSHOT.json.d" && mv "$ALPHA/SNAPSHOT.json.d" "$ALPHA/$AB_SNAPSHOT"
DIR_RC=0; DIR_OUT="$( cd "$ALPHA" && bash "$WRITER" 2>&1 )" || DIR_RC=$?
assert "a directory at that path -> exits 2"     "$(eq "$DIR_RC" 2)"
assert "…and says it refuses to overwrite"       "$(has 'refusing to overwrite' "$DIR_OUT")"
assert "…and the directory is still there"       "$(yes_if test -d "$SNAP")"
rmdir "$SNAP"
mkdir -p "$TMP/stranger"
STR_RC=0; STR_OUT="$( cd "$TMP/stranger" && bash "$WRITER" 2>&1 )" || STR_RC=$?
assert "outside an instance root -> exits 2"     "$(eq "$STR_RC" 2)"
assert "…and names what it expected to find"     "$(has 'instance.config.json' "$STR_OUT")"

echo "== a real snapshot, once the switch is on =="
touch "$SNAP"
RUN_OUT="$( cd "$ALPHA" && SNAPSHOT_NOW=2026-08-22T00:00:00Z bash "$WRITER" 2>&1 )"
assert "the run reports what it wrote"     "$(has 'SNAPSHOT.json' "$RUN_OUT")"
assert "…with the project count"           "$(has '16 project(s)' "$RUN_OUT")"
# 13, not 14: the done project's task is never counted, because it is never read.
assert "…and the task count"                "$(has '15 task(s)' "$RUN_OUT")"
assert "…and the awaiting count (11 verbs across 5 live projects)" "$(has '11 awaiting' "$RUN_OUT")"
# The run captures stderr too, and an awk that aborts mid-line says so THERE while still
# exiting 0 and writing a file — a whole `deliverable_paths` key lost with the evidence
# printed somewhere nobody reads. So the absence of that text is an assertion.
assert "…and no parser error was printed on the way"     "$(hasnt 'awk:' "$RUN_OUT")"
assert "the file is non-empty"              "$(yes_if test -s "$SNAP")"
assert "it parses as JSON"                  "$(yes_if python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$SNAP")"
assert "no temp file was left behind"       "$(yes_if sh -c '! ls "$1".tmp.* >/dev/null 2>&1' _ "$SNAP")"
# SNAPSHOT_NOW is the whole reproducibility story: without it the file differs on every
# run and nothing downstream can be diffed.
cp "$SNAP" "$TMP/first.json"
( cd "$ALPHA" && SNAPSHOT_NOW=2026-08-22T00:00:00Z bash "$WRITER" --quiet )
assert "SNAPSHOT_NOW pins generated_at (byte-identical re-run)" "$(yes_if cmp -s "$TMP/first.json" "$SNAP")"

echo "== the field allowlist =="
# The documented set, and nothing else.
#
# This PARSES the JSON rather than grepping it. The previous version matched
# `"[A-Za-z_][A-Za-z0-9_]*":`, which only ever sees identifier-shaped keys — a
# perfectly valid `"source-path"` or `"document body"` was invisible to it, so a
# snapshot could carry a field outside the allowlist while this assertion reported
# green. Since the allowlist is a data-governance boundary rather than a format,
# a check that can be walked around is worse than no check: it certifies the
# boundary while not testing it. Recursing over the parsed object also covers keys
# at any depth, which the flat text scan only did by accident.
# `owner` is in this set DELIBERATELY and is the only identity field that is — see the
# header. Removing it here is how the reversal would get silently undone, so the writer's
# own header, this line, and per-owner-board.test.sh all have to move together.
ALLOWED=' _schema _sensitivity _carries group generated_at counts projects tasks awaiting slug title description kind status autonomy owner deliverable_paths awaiting_close phase_progress done total phases file order id assignee phase in_flight open_questions open_question_ids advisor_notes depends_on prs pr_mergeable repo number url '
extra_keys() { # <json file> <allowed> -> the keys present but not allowed
  python3 - "$1" "$2" <<'PYK'
import json, sys
allowed = set(sys.argv[2].split())
def keys(v):
    if isinstance(v, dict):
        for k, child in v.items():
            yield k
            yield from keys(child)
    elif isinstance(v, list):
        for child in v:
            yield from keys(child)
with open(sys.argv[1], encoding="utf-8") as fh:
    print(" ".join(sorted(set(keys(json.load(fh))) - allowed)))
PYK
}
EXTRA="$(extra_keys "$SNAP" "$ALLOWED")"
assert "no key outside the documented set is emitted${EXTRA:+ (saw:$EXTRA)}" "$(eq "$EXTRA" "")"
# …and PROVE that check can actually fail. A non-identifier key is exactly the shape
# the old grep could not see, so it is the shape this fixture plants.
printf '%s\n' '{"group":"g","counts":{"tasks":1},"source-path":"/home/someone/bundle"}' > "$TMP/badkey.json"
BADKEY="$(extra_keys "$TMP/badkey.json" "$ALLOWED")"
assert "a non-identifier key IS caught (the old grep missed it)" "$(eq "$BADKEY" "source-path")"
printf '%s\n' '{"group":"g","projects":[{"slug":"s","document body":"leak"}]}' > "$TMP/badkey2.json"
BADKEY2="$(extra_keys "$TMP/badkey2.json" "$ALLOWED")"
assert "…and one with a space, nested inside a list" "$(eq "$BADKEY2" "document body")"
assert "a task description never reaches the snapshot"   "$(fhasnt "$SECRET_DESC" "$SNAP")"
assert "no document body reaches the snapshot"           "$(fhasnt "$SECRET_BODY" "$SNAP")"
assert "open-question TEXT never reaches the snapshot"    "$(fhasnt "$SECRET_QUESTION" "$SNAP")"
# SCOPED TO THE TASK IT NAMES, not a whole-file grep for `"open_questions": 2`. As a
# file-wide grep this is the positive half of a privacy pair — the text never travels,
# the count does — and ANY later fixture that happens to carry two questions satisfies
# it, at which point it certifies nothing about task-001 while still reading green. That
# is not hypothetical: the task-006 fixture below silently took it over exactly that way.
assert "…the COUNT does (2 questions on task-001)"        "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
p=[p for p in d["projects"] if p["slug"]=="ci"][0]
t=[t for t in p["tasks"] if t["id"]=="task-001"][0]
sys.exit(0 if t["open_questions"]==2 else 1)' "$SNAP")"
# …AND SO DOES A LABEL PER QUESTION, WHICH IS THE FIELD THIS ROUND ADDED. A total is
# all the snapshot used to carry, so the board's `answer Q<n>` control — which reads a
# number out of the question — had nothing to read and degraded to the unnumbered
# control on every instance, and a task with three questions could only ever produce one
# handle. Each entry's number comes from the entry itself: the first names Q1 with NO
# COLON after it (a real shape, and one the old token count could not see at all), the
# second is stamped, the third is escalated and carries a comma in its prose.
assert "each open question gets its OWN label, in document order (task-044)" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=[t for p in d["projects"] for t in p["tasks"] if t["id"].startswith("task-044")][0]
sys.exit(0 if t["open_question_ids"]==["Q1","Q2","Q3"] and t["open_questions"]==3 else 1)' "$SNAP")"
# NON-VACUITY, and it is the whole reason this fixture exists: the first entry really
# does carry no colon, so a reader that required one would report two labels, not three.
assert "…and the first entry really has no colon after its Q1" \
  "$(yes_if python3 -c '
import sys
src=open(sys.argv[1],encoding="utf-8").read()
i=src.index("Q1 (HALF ANSWERED")
sys.exit(0 if src[i:i+3]=="Q1 " else 1)' "$ALPHA/projects/qshapes/tasks/task-044-the-dwd-calendar-grant.md")"
# THE HONEST NO-NUMBER PATH, AS ITS OWN CASE. A question with no `Q<n>` still counts as
# a question and still gets an entry — an EMPTY one, because the writer read its text,
# found no number, and says so. Inventing `Q1` for it is the defect; dropping it is a
# question that disappears off the board.
assert "a question that names no number gets an empty label, not a fabricated one" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=[t for p in d["projects"] for t in p["tasks"] if t["id"].startswith("task-045")][0]
sys.exit(0 if t["open_question_ids"]==[""] and t["open_questions"]==1 else 1)' "$SNAP")"
assert "a number that does not end where it is read yields no label" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=[t for p in d["projects"] for t in p["tasks"] if t["id"].startswith("task-046")][0]
sys.exit(0 if t["open_question_ids"]==["",""] and t["open_questions"]==2 else 1)' "$SNAP")"
# NON-VACUITY: a number that DOES end where it is read still reads, in the same run —
# otherwise a writer that labelled nothing at all would satisfy the line above.
assert "…while a bounded number in the same run still does" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=[t for p in d["projects"] for t in p["tasks"] if t["id"].startswith("task-044")][0]
sys.exit(0 if t["open_question_ids"][0]=="Q1" else 1)' "$SNAP")"
assert "a marker BEFORE the stamp still yields the number (task-047)" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=[t for p in d["projects"] for t in p["tasks"] if t["id"].startswith("task-047")][0]
sys.exit(0 if t["open_question_ids"]==["Q5"] else 1)' "$SNAP")"
# NON-VACUITY: the `·` really does sit past the bound while the marker is still there,
# so this measures the first skip and not the second one doing the same job twice.
assert "…and its lead really is past the bound without the marker skip" \
  "$(yes_if python3 -c '
import sys
line=[l for l in open(sys.argv[1],encoding="utf-8") if "escalated" in l][0]
i=line.index("advisor:")
sys.exit(0 if line.index("\u00b7") - i > 41 and line.index("\u00b7") - i - len("advisor: ") <= 41 else 1)' \
  "$ALPHA/projects/qshapes/tasks/task-047-marker-first.md")"
# THE GOVERNANCE BOUNDARY THE NEW FIELD SITS ON. It is a per-question field, and the
# rule that keeps it inside the allowlist is that it can carry NOTHING BUT a number:
# `Q` + digits, or empty. This is checked over every label in the file, so a future
# edit that widened it to "the first few words of the question" fails here — the
# file-wide text sentinel above only catches THIS fixture's own question text.
# SPELLED `[0-9][0-9]*` AND NOT `[0-9]{1,3}`, AND THIS IS NOT STYLE. Bash performs
# BRACE EXPANSION on a command ARGUMENT before anything else, and it does not spare a
# `{m,n}` sitting inside a `$( … )` in that argument: the whole word expands to TWO
# words, the substitution runs twice — once with `{1}`, once with `{3}` — and `assert`
# is handed the second run's answer. Measured here: the check passed standing alone,
# failed as an argument, and `echo "[$(… {1,3} …)]"` prints its line twice. It does NOT
# happen in an assignment (`V="$( … )"`), which is why the same shape elsewhere in this
# suite is fine and why this one looked impossible. tests/review-route.test.sh:196 has
# the live version of the bug. Recorded in
# /knowledge/findings/brace-expansion-mangles-a-regex-inside-a-command-substitution.md.
assert "no label carries anything but a Q and digits" "$(yes_if python3 -c '
import json,re,sys
d=json.load(open(sys.argv[1]))
bad=[q for p in d["projects"] for t in p["tasks"]
     for q in t["open_question_ids"] if not re.fullmatch(r"(Q[0-9][0-9]*)?", str(q))]
sys.exit(0 if not bad else 1)' "$SNAP")"
# THE COUNT AND THE LABELS COME FROM ONE PARSE, so they cannot disagree. They used to be
# derived separately, and a task whose questions all read `Q1 (…` counted 1 while
# carrying three questions — a count that cannot produce the handles beside it.
assert "…and every task's count agrees with its labels" "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
bad=[t["id"] for p in d["projects"] for t in p["tasks"]
     if not (len(t["open_question_ids"])==t["open_questions"]
             or (not t["open_question_ids"] and t["open_questions"]<=1))]
sys.exit(0 if not bad else 1)' "$SNAP")"

# Regression for a shared list_region() that decides where a free-text list ENDS and
# swallows a real second question whenever an entry's own text carries a `]` before the
# list's closing one — a Markdown PR link (`[repo#N](url)`) in Q1, bare brackets in Q2,
# and an escaped `\"` inside Q1 for the quote-parity variant of the same silent drop.
# All must still be counted; losing any is the drop this pins (task-007 rounds 2-4).
assert "a ] INSIDE an entry does not end the list early (task-006, 2 questions)" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=[t for p in d["projects"] for t in p["tasks"] if t["id"]=="task-006"][0]
sys.exit(0 if t["open_questions"]==2 else 1)' "$SNAP")"

# depends_on is carried as bundle-local task IDs, never as paths. That is the whole
# reason it sits inside the allowlist rather than being an exception to it: an ID is a
# structural reference between two documents in this bundle, like `phase:`, and not one
# of the four things the allowlist names (prose, bodies, identity, out-of-bundle paths).
# If a future edit emits the raw `/projects/.../task-x.md` value instead, that is an
# out-of-bundle-shaped path on a publishable page and this assertion is the tripwire.
# advisor_notes is a COUNT and gets NO awaiting verb: it is the loop's inbox, not the
# human's, so a task with untriaged concerns must not appear as awaiting anything.
assert "advisor_notes defaults to 0"                      "$(fhas '"advisor_notes": 0' "$SNAP")"
# A FLOW-form list must count every entry. Counting only block-form `- ` lines reported
# 1 for a two-entry flow list, which is the bug this pins (CodeRabbit, PR #8).
assert "…and counts every entry of a FLOW-form list"      "$(fhas '"advisor_notes": 2' "$SNAP")"

assert "depends_on carries a task ID (inline form)"        "$(fhas '"depends_on": ["task-001"]' "$SNAP")"
assert "…and both entries of a BLOCK-form list"           "$(fhas '"depends_on": ["task-001", "task-002"]' "$SNAP")"
# A QUOTED path must normalise to the same ID. The closing quote used to defeat the
# `.md` suffix rule, emitting `task-001.md"` — an invalid ID on a publishable page.
assert "…and a QUOTED path normalises identically"        "$(fhasnt '.md\"' "$SNAP")"
assert "…while a task with none gets an empty array"      "$(fhas '"depends_on": []' "$SNAP")"
assert "…and never a path"                                "$(fhasnt '"depends_on": ["/' "$SNAP")"
# A file-scoped `.md"]` grep would also flag `deliverable_paths`, which legitimately
# carries a bundle-relative path ending in `.md` — so this checks `depends_on` ARRAYS
# specifically, not the whole file for that shape.
assert "…and never keeps the .md suffix"                  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
bad=[dep for p in d["projects"] for t in p["tasks"] for dep in t["depends_on"] if dep.endswith(".md")]
sys.exit(0 if not bad else 1)' "$SNAP")"
# task-008: a trailing YAML comment on the depends_on line must neither eat the real
# edge nor fabricate one out of the comment's own text (see task-008's own comment).
assert "a trailing comment on depends_on still keeps the real edge (task-008)" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=[t for p in d["projects"] for t in p["tasks"] if t["id"]=="task-008"][0]
sys.exit(0 if t["depends_on"]==["task-001"] else 1)' "$SNAP")"
assert "…and fabricates no ID out of the comment"          "$(fhasnt '"notes[1]"' "$SNAP")"
assert "…nor any fragment of the leaked path"              "$(fhasnt "$SECRET_DEP_COMMENT_PATH" "$SNAP")"
assert "a blocker reason never reaches the snapshot"      "$(fhasnt "$SECRET_BLOCKER" "$SNAP")"
assert "…the VERB does (unblock)"                         "$(fhas '"awaiting": "unblock"' "$SNAP")"
assert "authorEmail never reaches the snapshot"           "$(fhasnt "$SECRET_EMAIL" "$SNAP")"
assert "no path outside the bundle reaches the snapshot"  "$(fhasnt "$OUT_OF_BUNDLE" "$SNAP")"
assert "the assignee is a ROLE, not a person"             "$(fhas '"assignee": "software-engineer"' "$SNAP")"
assert "the sensitivity note travels with the file"       "$(fhas 'AS SENSITIVE AS THE TASK DOCUMENTS' "$SNAP")"

echo "== derived state the board reads =="
assert "an in-progress task is in_flight"        "$(yes_if grep -qF '"id": "task-005", "title": "Cache the dependency store", "kind": "build", "status": "in-progress", "assignee": "software-engineer", "phase": "", "in_flight": true' "$SNAP")"
assert "an in-review task is NOT in flight"      "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=[t for p in d["projects"] for t in p["tasks"] if t["id"]=="task-002"][0]
sys.exit(0 if t["in_flight"] is False and t["awaiting"]=="merge" else 1)' "$SNAP")"
assert "a CONFLICTING in-review PR is a rebase round, not a merge row" "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=[t for p in d["projects"] for t in p["tasks"] if t["id"]=="task-009"][0]
sys.exit(0 if t["awaiting"]=="" and t["in_flight"] is True and t["pr_mergeable"]=="CONFLICTING" else 1)' "$SNAP")"
assert "a PR the tick never asked about gets no merge verb"            "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=[t for p in d["projects"] for t in p["tasks"] if t["id"]=="task-010"][0]
sys.exit(0 if t["awaiting"]=="" and t["pr_mergeable"]=="UNKNOWN" else 1)' "$SNAP")"
assert "a refined draft awaits approve"          "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=[t for p in d["projects"] for t in p["tasks"] if t["id"]=="task-004"][0]
sys.exit(0 if t["awaiting"]=="approve" else 1)' "$SNAP")"
# task-007: `acceptance_criteria: []` plus a trailing comment, no open questions. This
# must await NOTHING — not "approve", which is what a comment left over after the
# bracket-and-whitespace strip used to fake (see task-007's own comment).
assert "an EMPTY criteria list with a trailing comment awaits nothing (task-007)" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=[t for p in d["projects"] for t in p["tasks"] if t["id"]=="task-007"][0]
sys.exit(0 if t["awaiting"]=="" else 1)' "$SNAP")"
assert "the hostile title round-trips exactly"   "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=[t for p in d["projects"] for t in p["tasks"] if t["id"]=="task-001"][0]
sys.exit(0 if t["title"]==sys.argv[2] else 1)' "$SNAP" "$HOSTILE_TITLE")"
assert "a project with no tasks yields an empty list, not an error" "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
p=[p for p in d["projects"] if p["slug"]=="empty"][0]
sys.exit(0 if p["tasks"]==[] and p["phases"]==[] else 1)' "$SNAP")"
assert "all-terminal project proposes a close"   "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
p={p["slug"]:p for p in d["projects"]}
sys.exit(0 if p["finished"]["awaiting_close"] and not p["empty"]["awaiting_close"] else 1)' "$SNAP")"
assert "phase progress counts done vs total"     "$(fhas '"phase_progress": {"done": 1, "total": 2}' "$SNAP")"

echo "== a DONE project is read no further than its frontmatter =="
# `retain: true` keeps a finished project's folder, so the writer now meets done
# projects on every tick. The whole justification for keeping them is that they cost ONE
# frontmatter parse — so what is asserted here is an ABSENCE OF READING, not a filtered
# output. The two are indistinguishable in the JSON, which is why the fixture's task is
# planted to be loud: if `tasks/` were opened, its title would appear, the task count
# would be 8, `open_questions` would be 2, its PR would be collected and `blocked` would
# add an `unblock` verb. Each of those is a separate way for the read to show itself.
assert "the done project IS on the board (a retained project is a reference card)" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
p={p["slug"]:p for p in d["projects"]}
r=p["retained"]
sys.exit(0 if r["status"]=="done" and r["title"]=="AI adoption research" else 1)' "$SNAP")"
assert "…with tasks[] and phases[] empty — neither directory was walked" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
r=[p for p in d["projects"] if p["slug"]=="retained"][0]
sys.exit(0 if r["tasks"]==[] and r["phases"]==[] and r["phase_progress"]=={"done":0,"total":0} else 1)' "$SNAP")"
assert "…and deliverable_paths IS forwarded — from project.md's own frontmatter, never from tasks/" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
r=[p for p in d["projects"] if p["slug"]=="retained"][0]
sys.exit(0 if r["deliverable_paths"]==["/projects/retained/deliverables/deck.md"] else 1)' "$SNAP")"
# The fixture's `deliverable_paths:` line carries a trailing YAML comment (SCHEMA.md's
# own documented form — see the fixture above). An exact single-entry match above
# already proves the comment was not swallowed into the path; this pins the failure
# mode directly, so a regression names itself instead of just failing the exact-match.
assert "…and the trailing comment never reaches the snapshot at all" \
  "$(fhasnt "WRITTEN BY CLOSEOUT" "$SNAP")"
# Its TAIL, separately: the comment carries commas, so a swallowed one is re-split into
# fragments that no longer contain the words the assertion above looks for. Checking the
# first four words of a comment proves nothing about the fragment that comes after the
# comma — which is the half that can carry a path.
assert "…including the fragments after its commas" \
  "$(fhasnt "means closeout looked and found none" "$SNAP")"
# The fixture line above claims to be SCHEMA.md's documented form. That claim decayed
# once already: the comment was copied as a PREFIX, cut one word before the `[ ]` that
# makes the case hard, while the note beside it still said "exactly". So assert the
# claim rather than repeating it — the two comments must be byte-identical, and a
# SCHEMA.md edit that changes the shape of the documented form fails here rather than
# leaving this fixture quietly testing a form nothing documents.
doc_comment() { head -1 <<<"$(sed -n 's/^deliverable_paths:[^#]*#/#/p' "$1")"; }
SCHEMA_DP_COMMENT="$(doc_comment "$TPL/plugin/seed/SCHEMA.md")"
# Non-emptiness first, or the comparison below passes on two empty strings the day
# SCHEMA.md's documented form loses its comment — which is the same failure this whole
# assertion exists to catch, arriving from the other side.
assert "SCHEMA.md still documents this key WITH a trailing comment" \
  "$(yes_if test -n "$SCHEMA_DP_COMMENT")"
assert "…and the fixture's trailing comment IS that one, byte for byte" \
  "$(eq "$(doc_comment "$ALPHA/projects/retained/project.md")" "$SCHEMA_DP_COMMENT")"
# The comma-split shape (the `handedited` fixture): one entry out, not two, and the
# absolute path hidden after the comment's comma nowhere in the file.
assert "a comment's comma does not split a second entry out of the value" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
p=[p for p in d["projects"] if p["slug"]=="handedited"][0]
sys.exit(0 if p["deliverable_paths"]==["/projects/handedited/deliverables/report.md"] else 1)' "$SNAP")"
# …and the same for a BLOCK-form list, whose key line carries no `]`. Both entries,
# exactly as Psych reads them: the comment gone off the first, and the second — a
# QUOTED scalar whose ` #` is not a comment — carried whole rather than cut to `.../b`.
assert "…and the same holds for a BLOCK-form list, whose key line carries no ]" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
p=[p for p in d["projects"] if p["slug"]=="blockform"][0]
sys.exit(0 if p["deliverable_paths"]==["/projects/blockform/deliverables/notes.md",
                                       "/projects/blockform/deliverables/b #2.md"] else 1)' "$SNAP")"
# The `sibling` fixture: an UNQUOTED `]` inside what looks like a filename. Psych reads
# one entry, `.../a`, and treats the rest of the line as a comment — so the property is
# that the parser is followed in both directions: the entry it returns survives, and the
# comment text it discarded never becomes a second entry.
assert "an unquoted ] terminates the list, so the entry before it survives" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
p=[p for p in d["projects"] if p["slug"]=="sibling"][0]
sys.exit(0 if p["deliverable_paths"]==["/projects/sibling/deliverables/a"] else 1)' "$SNAP")"
# The `quoted` fixture, and the reason it exists: inside quotes a `]` is an ordinary
# character, so Psych really does have two entries and the clean one MUST come through.
# A cut that reads the quoted `#` as a comment loses `b.md` and invents `.../a`.
assert "a quoted ] is no terminator: the clean sibling entry survives" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
p=[p for p in d["projects"] if p["slug"]=="quoted"][0]
sys.exit(0 if p["deliverable_paths"]==["/projects/quoted/deliverables/a ] #1.md",
                                       "/projects/quoted/deliverables/b.md"] else 1)' "$SNAP")"
# The SINGLE-quoted forms, which nothing exercised until a fabrication shipped past a
# green suite. `''` is YAML's only single-quote escape, so the first line below is TWO
# entries and the apostrophe belongs to the first one; a scan that closes the scalar at
# the first quote of the pair reads the rest as a comment, fabricates the truncation and
# takes `clean.md` with it. The assertion is the parser's own reading, both entries.
assert "a doubled quote inside a single-quoted entry does not end it" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
p=[p for p in d["projects"] if p["slug"]=="sqescaped"][0]
sys.exit(0 if len(p["deliverable_paths"])==2
         and p["deliverable_paths"][1]=="/projects/sqescaped/deliverables/clean.md"
         and p["deliverable_paths"][0].startswith("/projects/sqescaped/deliverables/o")
         and p["deliverable_paths"][0].endswith("#2") else 1)' "$SNAP")"
assert "…and the plain single-quoted list keeps both of its entries" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
p=[p for p in d["projects"] if p["slug"]=="sqplain"][0]
sys.exit(0 if p["deliverable_paths"]==["/projects/sqplain/deliverables/a.md",
                                       "/projects/sqplain/deliverables/b.md"] else 1)' "$SNAP")"
# One multi-byte character used to abort the awk scan outright, so the key came back
# EMPTY — the `Übersicht.md` entry did not merely fail to render, it took `plain.md`
# with it. Both entries, and nothing on the run's output about a parser.
assert "…and a non-ASCII filename costs the key neither of its entries" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
p=[p for p in d["projects"] if p["slug"]=="umlaut"][0]
sys.exit(0 if p["deliverable_paths"]==["/projects/umlaut/deliverables/\u00dcbersicht.md",
                                       "/projects/umlaut/deliverables/roh-\u00dc#1.md",
                                       "/projects/umlaut/deliverables/plain.md"] else 1)' "$SNAP")"
# The fixture is only a test of NFD while it is still decomposed. Asserted before
# anything is asserted ABOUT it, so a file that got normalised on its way through an
# editor fails here rather than passing everything below over its NFC twin.
assert "the NFD fixture really is decomposed, not its NFC twin" \
  "$(yes_if python3 -c '
import sys, unicodedata
n=sys.argv[1]
sys.exit(0 if n!=unicodedata.normalize("NFC",n)
              and any(unicodedata.category(c)[0]=="M" for c in n) else 1)' "$NFD_NAME")"
assert "…and the decomposed filename reaches the snapshot whole" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
p=[p for p in d["projects"] if p["slug"]=="nfd"][0]
sys.exit(0 if p["deliverable_paths"]==["/projects/nfd/deliverables/"+sys.argv[2]] else 1)' "$SNAP" "$NFD_NAME")"
# The same defect, reached the other way round — through the VALUE rather than the
# comment. The `finished` fixture's line opens a quote and never closes it, so a strip
# that decided where the list ended by tracking quote state found no unquoted `]`, kept
# the whole line, and folded the comment (with the publisher's absolute path in it) into
# the entry. Two assertions, because they fail differently: the first says the path is
# still the path, the second says the absolute path is nowhere in the file at all.
assert "an unbalanced quote does not let the trailing comment into the value" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
p=[p for p in d["projects"] if p["slug"]=="finished"][0]
sys.exit(0 if p["deliverable_paths"]==["/projects/finished/deliverables/report.md"] else 1)' "$SNAP")"
assert "…and the absolute path it hides never reaches the snapshot" \
  "$(fhasnt "$SECRET_ABS_PATH" "$SNAP")"
assert "a project carrying no deliverable_paths key gets an empty array, not an error" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
p=[p for p in d["projects"] if p["slug"]=="empty"][0]
sys.exit(0 if p["deliverable_paths"]==[] else 1)' "$SNAP")"
assert "…and its task's title never reaches the snapshot" \
  "$(fhasnt 'SENTINEL-DONE-PROJECT-TASK' "$SNAP")"
assert "…nor its phase's title (phases are skipped by the same continue)" \
  "$(fhasnt 'SENTINEL-DONE-PHASE' "$SNAP")"
assert "…nor its PR, which the task loop would have collected" \
  "$(fhasnt '/pull/9999' "$SNAP")"
assert "…and a done project proposes no close (it is already closed)" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
r=[p for p in d["projects"] if p["slug"]=="retained"][0]
sys.exit(0 if r["awaiting_close"] is False else 1)' "$SNAP")"
# THE SKIP AND THE `owner` FIELD ARRIVED IN DIFFERENT PRs and collided in the same hunk,
# so this is the assertion that keeps them merged rather than merely adjacent. The loop
# has two exits and one `project_stanza()` builder: a done project must carry the SAME
# field set as a live one, or a published board partitions retained work away from the
# human who owns it — and the drift would be invisible, because nobody diffs a board.
# Comparing the key sets rather than naming `owner` is deliberate: it catches the NEXT
# field added to one exit and not the other, which is the failure that recurs. Reading
# `owner:` off frontmatter already in memory opens no file, so it does not give the
# skip's saving back — the assertions above still hold.
assert "…and its field set is IDENTICAL to a live project's, `owner` included" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
p={x["slug"]:x for x in d["projects"]}
sys.exit(0 if set(p["retained"]) == set(p["ci"]) and "owner" in p["retained"] else 1)' "$SNAP")"
# The negative assertions above hold just as well if the writer never found the project
# at all, so prove the fixture is real: the same task doc, under a project that is NOT
# done, moves every one of those numbers.
cp -R "$ALPHA/projects/retained" "$ALPHA/projects/notdone"
sed -i.bak 's/^status: done$/status: active/' "$ALPHA/projects/notdone/project.md" && rm -f "$ALPHA/projects/notdone/project.md.bak"
CTRL_OUT="$( cd "$ALPHA" && SNAPSHOT_NOW=2026-08-22T00:00:00Z bash "$WRITER" 2>&1 )"
assert "control: the same task under a LIVE project IS read (16 tasks)" "$(has '16 task(s)' "$CTRL_OUT")"
assert "…and its title does reach the snapshot"  "$(fhas 'SENTINEL-DONE-PROJECT-TASK' "$SNAP")"
# deliverable_paths comes off the SAME frontmatter parse every project already gets, not
# off the done-project skip specifically — so a LIVE project carrying the key forwards it
# too, proving this is "read project.md's frontmatter", not "a done-project special case".
assert "…and deliverable_paths is read from a LIVE project's frontmatter too" \
  "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
c=[p for p in d["projects"] if p["slug"]=="notdone"][0]
sys.exit(0 if c["deliverable_paths"]==["/projects/retained/deliverables/deck.md"] else 1)' "$SNAP")"
rm -rf "$ALPHA/projects/notdone"
( cd "$ALPHA" && SNAPSHOT_NOW=2026-08-22T00:00:00Z bash "$WRITER" --quiet )
assert "…and the sentinel is gone again once the control project is removed" \
  "$(fhasnt 'SENTINEL-DONE-PROJECT-TASK' "$SNAP")"

echo "== the other three instances =="
printf '{ this is not json' > "$BETA/$AB_SNAPSHOT"
# Hand-written, because the writer will not produce a non-http PR URL — and the board
# is required not to trust that.
cat > "$DELTA/$AB_SNAPSHOT" <<DELTASNAP
{
  "group": "delta",
  "generated_at": "2026-08-22T00:00:00Z",
  "counts": {"projects": 1, "tasks": 2, "awaiting": 1},
  "projects": [
    {
      "slug": "hostile", "title": "Hostile input", "kind": "build", "status": "active",
      "autonomy": "gated", "awaiting_close": false,
      "phase_progress": {"done": 0, "total": 0}, "phases": [],
      "tasks": [
        {"id": "task-001", "title": "$HOSTILE_TITLE", "kind": "build", "status": "in-review",
         "assignee": "software-engineer", "phase": "", "in_flight": false,
         "awaiting": "merge", "open_questions": 0,
         "prs": [{"repo": "evil/repo", "number": 1, "url": "javascript:alert(document.domain)"},
                 {"repo": "evil/repo", "number": 2, "url": "data:text/html,<script>alert(1)</script>"},
                 {"repo": "acme/monorepo", "number": 3, "url": "https://github.com/acme/monorepo/pull/3"}]},
        {"id": "task-002", "title": "onerror=alert(1) autofocus", "kind": "build",
         "status": "made-up-status", "assignee": "software-engineer", "phase": "",
         "in_flight": false, "awaiting": "", "open_questions": 0, "prs": []}
      ]
    }
  ]
}
DELTASNAP
assert "gamma has no snapshot (the off-switch fixture)" "$(yes_if test ! -e "$GAMMA/$AB_SNAPSHOT")"

echo "== the board renders, and a broken instance cannot blank it =="
HTML="$TMP/board.html"
B_RC=0; B_ERR="$( cd "$TMP" && bash "$BOARD" --out "$HTML" "$ALPHA" "$BETA" "$GAMMA" "$DELTA" 2>&1 )" || B_RC=$?
assert "exits 0 with a malformed snapshot in the list" "$(eq "$B_RC" 0)"
assert "the run counts the unreadable snapshot"    "$(has '1 unreadable snapshot(s)' "$B_ERR")"
assert "…and says on stderr which instance is off the board" "$(has "no $AB_SNAPSHOT (off the board)" "$B_ERR")"
assert "a malformed snapshot becomes a visible note" "$(fhas 'Unreadable snapshot' "$HTML")"
# THE WHOLE ROUND-TRIP, ON THE PAGE THIS INVOCATION WRITES: the writer read three
# differently-shaped questions out of a task document, and the renderer put one
# correctly-numbered control on each. Neither script's output is taken on faith — this
# is the assertion that would have caught the defect, since the renderer's own harness
# feeds it hand-written snapshots that carry what the writer never did.
card_of() { # <html> <project title> — that project's card, cut at the NEXT card, never
            # at the next </details>: cards nest them, one per rail item.
  python3 - "$1" "$2" <<'PYC'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
i = t.index(sys.argv[2])
j = t.find('<details class="proj', i)
sys.stdout.write(t[i:] if j < 0 else t[i:j])
PYC
}
for n in 1 2 3; do
  assert "writer through renderer: question Q$n gets its own handle" \
    "$(grep -qF "answer Q$n</button>" <<<"$(card_of "$HTML" 'Question shapes')" && echo 0 || echo 1)"
done
# SCOPED TO THAT TASK'S ROW, not to the card: the same project holds other tasks with
# questions of their own, so a card-wide count measures the fixture rather than the task.
item_of() { # <html> <task title> — one waiting row
  python3 - "$1" "$2" <<'PYI'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
for li in re.findall(r'<li class="ask">.*?</li>', t, re.S):
    if sys.argv[2] in li:
        sys.stdout.write(li)
        break
PYI
}
assert "…three handles for three questions, not one for the task" \
  "$(eq "$(item_of "$HTML" 'Three questions, three shapes' | grep -oF 'answer Q' | wc -l | tr -d ' ')" 3)"
# NON-VACUITY: before the labels existed this card rendered exactly one unnumbered
# control for that task, so the assertions above measure the new field and not a
# renderer that was already numbering things.
assert "…and the task really carries three questions" "$(yes_if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
t=[t for p in d["projects"] for t in p["tasks"] if t["id"].startswith("task-044")][0]
sys.exit(0 if t["open_questions"]==3 else 1)' "$SNAP")"
# THE HONEST PATH, END TO END TOO: the other task's question names no number, and the
# page says so rather than calling it Q1.
assert "…while the unnumbered question keeps the honest control" \
  "$(grep -qF 'answer question</button>' <<<"$(card_of "$HTML" 'Question shapes')" && echo 0 || echo 1)"
assert "…and no Q1 is invented for it" "$(yes_if python3 -c '
import re,sys
t=open(sys.argv[1],encoding="utf-8").read()
i=t.index("A question that names no number")
j=t.find("</li>", i)
sys.exit(0 if not re.search(r"Q[0-9]", t[i:j if j>0 else len(t)]) else 1)' "$HTML")"

assert "…naming the instance by directory NAME"     "$(fhas "_ai-bridge-beta/$AB_SNAPSHOT" "$HTML")"
assert "…and not by its path"                      "$(fhasnt '/_ai-bridge-beta' "$HTML")"
assert "…and telling the human how to fix it"       "$(fhas 'write-snapshot.sh' "$HTML")"
assert "alpha is still rendered beside the broken one" "$(fhas 'CI hardening' "$HTML")"
assert "delta is still rendered too"                "$(fhas 'Hostile input' "$HTML")"
assert "an instance with no snapshot is absent entirely" "$(fhasnt '_ai-bridge-gamma' "$HTML")"
assert "…including its group name"                  "$(fhasnt '>gamma ' "$HTML")"
assert "a project with no tasks renders empty, not broken" "$(fhas 'class="ptitle">Nothing here yet' "$HTML")"
assert "an unknown status still gets a column"      "$(fhas 'made-up-status' "$HTML")"
# Shown as a rail item carrying the command, never run: the page copies a prompt, the
# bundle is where a decision is recorded.
assert "the close proposal is shown, never taken"   "$(fhas 'class="verb">close' "$HTML")"
assert "…carrying the command a human would run"   "$(fhas 'close-project finished' "$HTML")"
# The retained project's deliverables panel, on the SAME page this real invocation
# produces — not a fixture built just to exercise the renderer in isolation. See
# /knowledge/findings/a-flags-default-forked-one-command-into-two-boards.md: a test
# that only ever exercises an isolated fixture is testing whichever page the fixture
# happens to name, not the one this call actually writes.
assert "a retained project's deliverable is a copy button"  "$(fhas 'data-copy="/projects/retained/deliverables/deck.md"' "$HTML")"
assert "…labelled by filename"                              "$(fhas '>deck.md</button>' "$HTML")"
assert "…reusing the existing data-what convention"         "$(fhas 'data-what="Deliverable path"' "$HTML")"
# task-008's edge, end to end on the SAME page this invocation writes — writer through
# renderer, not the writer's JSON output taken on faith. A `]  # comment` on the
# depends_on line must still draw the real dependency button pointing at task-001, and
# must draw no button (and copy no path) for the comment's own fabricated fragment.
assert "task-008's real dependency renders as a dep button (writer through renderer)" \
  "$(fhas 'data-copy="ci/task-001" data-what="Task handle" title="task-001">001</button>' "$HTML")"
assert "…and the comment's fabricated fragment renders nothing"    "$(fhasnt 'notes[1]' "$HTML")"
assert "…nor any fragment of the leaked path reaches the page"     "$(fhasnt "$SECRET_DEP_COMMENT_PATH" "$HTML")"
# Criterion 4, end to end on the page a real invocation writes — not on a hand-written
# snapshot. The `finished` fixture's hand-edited `deliverable_paths:` line hides an
# absolute path in a trailing comment, behind an unbalanced quote. What may appear on
# the page is the clean bundle-relative path, or nothing; the comment is neither.
assert "a hand-edited line still copies the bundle-relative path" \
  "$(fhas 'data-copy="/projects/finished/deliverables/report.md"' "$HTML")"
assert "…and the absolute path in its comment reaches no page"  "$(fhasnt "$SECRET_ABS_PATH" "$HTML")"
# LOOK INSIDE THE VALUE, not at its first characters. `fhasnt 'data-copy="/Users'` only
# says no value BEGINS with /Users — and the leak this pins puts the path in the MIDDLE
# of a value whose first characters are a perfectly good bundle-relative prefix. Spelled
# the first way, this assertion passed on a page that was leaking.
no_copy_value_with() { # <needle> <file>
  ! grep -qF -- "$1" <<<"$(grep -o 'data-copy="[^"]*"' "$2")"
}
assert "…nor any /Users path ANYWHERE inside something to copy" \
  "$(yes_if no_copy_value_with '/Users' "$HTML")"
# Criterion 4 against the shape that needs no comment AND no whitespace: an absolute path
# glued to a legitimate one with a `:`. The generic sweep above catches it too; this pair
# names it, so a regression says which vector came back rather than only that one did.
assert "a colon-glued absolute path is never a copy button" \
  "$(fhasnt 'data-copy="/projects/colon/deliverables' "$HTML")"
assert "…and its sentinel reaches no page"                     "$(fhasnt "$SECRET_COLON_PATH" "$HTML")"
# The single-quote pair, on the same real page. They fail in opposite directions, which
# is why both are here: the fabrication must NOT be a button, and the clean entry the
# fabrication used to delete MUST be one.
assert "an escaped apostrophe does not fabricate a truncated path" \
  "$(fhasnt 'data-copy="/projects/sqescaped/deliverables/o' "$HTML")"
assert "…while the clean sibling on that same line is a button" \
  "$(fhas 'data-copy="/projects/sqescaped/deliverables/clean.md"' "$HTML")"
assert "…and an ordinary single-quoted list renders both entries" \
  "$(yes_if sh -c 'grep -qF "data-copy=\"/projects/sqplain/deliverables/a.md\"" "$1" && grep -qF "data-copy=\"/projects/sqplain/deliverables/b.md\"" "$1"' _ "$HTML")"
assert "…and a non-ASCII filename renders as itself"           \
  "$(fhas 'data-copy="/projects/umlaut/deliverables/Übersicht.md"' "$HTML")"
# …and so does the DECOMPOSED spelling of the same name. `\w` matches the NFC form and
# not the NFD one, so this is the half the fixture above cannot certify: a class that
# admits `Übersicht.md` still drops what a macOS listing actually hands back.
assert "…and so does the same name spelled decomposed (NFD)"   \
  "$(fhas "data-copy=\"/projects/nfd/deliverables/$NFD_NAME\"" "$HTML")"
# Criterion 4 against the comma-split shape, on the same real page. The `handedited`
# fixture's comment hides a second, prefix-correct path after a comma; if the comment
# survives the parse, THIS is the button it becomes.
assert "the comma-split fragment is never a copy button" \
  "$(fhasnt 'data-copy="/projects/handedited/deliverables/see' "$HTML")"
assert "…while the real path on that same line still is"       \
  "$(fhas 'data-copy="/projects/handedited/deliverables/report.md"' "$HTML")"
# Criterion 4 against the shape with NO comment in it — the `plain` fixture, two paths in
# one value. Nothing upstream can strip anything here; the only thing between it and a
# copy button is the render-time rule that a deliverable path contains no whitespace. It
# does reach the snapshot (see the sentinel's own note), so this is the assertion that
# says the page and the snapshot are not the same promise.
assert "two paths in one value reach the snapshot…"            "$(fhas "$SECRET_PAGE_PATH" "$SNAP")"
assert "…and neither of them reaches the page"                 "$(fhasnt "$SECRET_PAGE_PATH" "$HTML")"
assert "…the whole value being dropped, not trimmed to its clean half" \
  "$(fhasnt 'data-copy="/projects/plain/deliverables' "$HTML")"
# The other direction, on the same real page, and the pair that says the parser is
# followed rather than approximated. They fail in OPPOSITE directions — one on a lost
# entry, one on an invented one — and each names the shape only it can reach:
#   · `quoted`: quoting makes `]` ordinary, YAML has two entries, so the clean one is a
#     button and the truncation `.../a` is not;
#   · `sibling`: an unquoted `]` terminates the list, so `b.md` lives in a COMMENT and
#     must reach no button — rendering it invents a deliverable out of comment text;
#   · `blockform`: ` #` inside a quoted BLOCK entry is not a comment either, so no
#     `.../b` may appear.
assert "a clean sibling entry is still a copy button"          \
  "$(fhas 'data-copy="/projects/quoted/deliverables/b.md"' "$HTML")"
assert "…and no truncated path was fabricated beside it"       \
  "$(fhasnt 'data-copy="/projects/quoted/deliverables/a"' "$HTML")"
assert "…nor is comment text past an unquoted ] rendered as an entry" \
  "$(fhasnt 'data-copy="/projects/sibling/deliverables/b.md"' "$HTML")"
assert "…while the entry that unquoted ] terminated still is one" \
  "$(fhas 'data-copy="/projects/sibling/deliverables/a"' "$HTML")"
assert "…and a quoted # on a BLOCK entry line is truncated into no path" \
  "$(fhasnt 'data-copy="/projects/blockform/deliverables/b"' "$HTML")"
# The line no parser will read at all. A cut needs a flow TERMINATOR before it may treat
# a `#` on a key line as a comment; drop that requirement and this fixture's filename is
# truncated into `.../a` and rendered. Both directions again, and neither leaks — which
# is why nothing else on this page can catch it.
assert "…nor is a filename truncated on a list that never closes" \
  "$(fhasnt 'data-copy="/projects/unterminated/deliverables/a"' "$HTML")"
assert "…while its readable clean entry is still a button" \
  "$(fhas 'data-copy="/projects/unterminated/deliverables/b.md"' "$HTML")"
# EXACTLY thirteen deliverable buttons on this page — one per fixture whose line yields
# a whole, well-formed path (retained, finished, handedited, blockform's first entry,
# `sibling`'s single entry, the clean second entry of `quoted` and `unterminated`,
# `sqescaped`'s clean sibling, both of `sqplain`'s, both of `umlaut`'s and `nfd`'s one;
# `plain` and `colon` yield none, each being two paths in one value) — and both failure directions are silent, sitting either
# side of the same fix. Too FEW is the documented comment form costing a panel: a strip
# anchored on the line's last bracket leaves SCHEMA.md's own comment in the value, the
# shape check drops the only entry, and the retained project renders with no
# deliverables panel at all — green on "nothing leaked", green on "no error", feature
# gone. It is also a clean entry lost beside a QUOTED bracketed filename. Too MANY is a
# comment fragment rendering as a path. A `fhas` on any one button sees none of it.
DELIV_BTNS="$(grep -oF 'data-what="Deliverable path"' "$HTML" | grep -c . || true)"
assert "exactly one copy button per stamped path, no more and no fewer (saw $DELIV_BTNS)" \
  "$(eq "$DELIV_BTNS" 13)"
assert "no filesystem path reaches the page"        "$(fhasnt "$TMP" "$HTML")"
# Belt and braces, because the check above depends on how the fixture path is spelled:
# an instance is named by its DIRECTORY NAME, so the name must never appear with a
# leading slash (i.e. as the tail of a path) anywhere on the page.
assert "…an instance is identified by name, never by path" "$(fhasnt '/_ai-bridge-alpha' "$HTML")"
# The second half, or the first is vacuous on a page that never names the instance at
# all. An instance is labelled by its GROUP here — the directory name is the fallback
# only when the snapshot carries none — so that is what must be present.
assert "…and the instance is still identified, by group"   "$(fhas 'class="where">alpha › ' "$HTML")"

echo "== untrusted text at an HTML sink =="
RAW_HITS="$(grep -oF -- '<script>alert(1)</script>' "$HTML" | grep -c . || true)"
assert "ZERO raw occurrences of the metacharacter title (saw $RAW_HITS)" "$(eq "$RAW_HITS" 0)"
assert "…and it is present in escaped form"         "$(fhas "$HOSTILE_ESCAPED" "$HTML")"
# ONE <script>, and no snapshot text in it. "No script at all" was the kanban page's
# property and never this one's; the honest promise is the boundary, not the tag count,
# because a clipboard helper that interpolated a title would be an injection whether or
# not it was the only script on the page. This page also carries a retained project's
# deliverables panel (asserted above) — its copy buttons reuse this SAME helper, so this
# assertion is what pins "no second script was added for it" on the page a real
# invocation actually writes, not on an isolated fixture.
# -c counts LINES, not occurrences — a second <script> sharing a line with the first
# would still read 1 and pass. -o prints one match per line, so piping to `wc -l` counts
# occurrences regardless of how many share a line.
assert "exactly one <script> element" \
  "$(eq "$(grep -oF '<script' "$HTML" | wc -l | tr -d ' ')" 1)"
assert "…and NOTHING from a snapshot is inside it" "$(yes_if python3 -c '
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
blocks = re.findall(r"<script\b[^>]*>(.*?)</script>", t, re.I | re.S)
needles = sys.argv[2:]
sys.exit(0 if len(blocks) == 1 and not any(n in b for b in blocks for n in needles) else 1)' \
  "$HTML" "$HOSTILE_TITLE" 'CI hardening' 'Hostile input' 'made-up-status')"
assert "no raw <b> from a title either"             "$(fhasnt '<b>bold</b>' "$HTML")"
assert "an event-handler-shaped title stays text"   "$(fhasnt ' onerror=' "$HTML")"
assert "a javascript: URL is never an href"         "$(fhasnt 'href="javascript:' "$HTML")"
assert "a data: URL is never an href"               "$(fhasnt 'href="data:' "$HTML")"
assert "…the withheld link is inert text instead"   "$(fhas 'link withheld: not http/https' "$HTML")"
assert "…and the http PR link beside it still works" "$(fhas 'href="https://github.com/acme/monorepo/pull/3"' "$HTML")"
# Secrets must not reappear via the board even though the snapshot is clean — the
# renderer reads only the snapshot, and this pins that.
for s in "$SECRET_DESC" "$SECRET_BODY" "$SECRET_QUESTION" "$SECRET_BLOCKER" "$SECRET_EMAIL"; do
  assert "the page carries no '$s'" "$(fhasnt "$s" "$HTML")"
done

echo "== the only external request is the declared webfont =="
# The two font hosts are spelled out here, verbatim, rather than described: a page that
# started fetching from a third host would otherwise slip through a looser pattern, and
# this list is the whole declaration of what the published board may reach.
FONT_HOSTS='https://fonts.gstatic.com https://fonts.googleapis.com/'
BAD_HREF=""
while IFS= read -r h; do
  case "$h" in
    http://*|https://*)
      case "$h" in
        *"/pull/"*) ;;
        https://fonts.gstatic.com*|https://fonts.googleapis.com/*) ;;
        *) BAD_HREF="$BAD_HREF $h" ;;
      esac ;;
  esac
done < <(grep -oE 'href="[^"]*"' "$HTML" | sed 's/^href="//; s/"$//')
assert "every http(s) href is a PR link or the webfont${BAD_HREF:+ (saw:$BAD_HREF)}" "$(eq "$BAD_HREF" "")"
for host in $FONT_HOSTS; do
  assert "…and the webfont host $host is really there" "$(fhas "$host" "$HTML")"
done
assert "no src= attribute at all"       "$(fhasnt 'src=' "$HTML")"
assert "no @import in the stylesheet"   "$(fhasnt '@import' "$HTML")"
# EVERY url(), not just an absolute one: `url(assets/icon.svg)` is a fetch too, and
# the header promises no CSS resource reference at all. The old pattern also used
# `\s`, which is a GNU extension rather than POSIX ERE — so it was a portability trap
# on top of being too narrow.
no_css_url() { # <html file> -> 0 when no <style> block contains url(
  python3 - "$1" <<'PYU'
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
blocks = re.findall(r"<style\b[^>]*>(.*?)</style>", html, re.I | re.S)
sys.exit(0 if all(not re.search(r"url\s*\(", b, re.I) for b in blocks) else 1)
PYU
}
assert "no url() fetch in the stylesheet" "$(yes_if no_css_url "$HTML")"
# Prove the strengthened check fails on a RELATIVE url(), which the old one passed.
printf '%s\n' '<style>.a{background:url(assets/icon.svg)}</style>' > "$TMP/relurl.html"
assert "…and a relative url() is now rejected" "$(eq "$(yes_if no_css_url "$TMP/relurl.html")" 1)"
printf '%s\n' '<style>.a{color:red}</style><p>url(not-in-css)</p>' > "$TMP/txturl.html"
assert "…while url( outside a <style> block is not a false alarm" "$(yes_if no_css_url "$TMP/txturl.html")"
# Exactly two: the preconnect and the stylesheet, both to the hosts asserted above. A
# third <link> is a new external dependency and must be a deliberate edit here.
assert "exactly two <link> elements"    "$(eq "$(grep -cF '<link' "$HTML")" 2)"
assert "no <iframe>"                    "$(fhasnt '<iframe' "$HTML")"

echo "== output shape =="
assert "the default output is an Artifact page body (no doctype)" "$(fhasnt '<!doctype' "$HTML")"
assert "…and no <body> tag"              "$(fhasnt '<body' "$HTML")"
assert "…but it does carry a <title>"    "$(fhas '<title>Bridge Board</title>' "$HTML")"
SA="$TMP/standalone.html"
( cd "$TMP" && bash "$BOARD" --standalone --out "$SA" "$ALPHA" ) >/dev/null 2>&1
assert "--standalone opens with a doctype" "$(yes_if grep -qF '<!doctype html>' <<<"$(head -1 "$SA")")"
assert "…and the content sits in <body>, not <head>" "$(yes_if python3 -c '
import sys,re
t=open(sys.argv[1]).read()
head=t[t.index("<head>"):t.index("</head>")]
body=t[t.index("<body>"):t.index("</body>")]
sys.exit(0 if "<style>" in head and "Bridge Board</h1>" in body and "<h1>" not in head else 1)' "$SA")"
assert "…with exactly one <body> element" "$(eq "$(grep -cF '<body>' "$SA")" 1)"

# THE CSS-ONLY TAB STRIP WAS THE KANBAN PAGE'S, and it went with it. Its assertions
# lived here because a radio/panel/rule mismatch rendered a board where no panel was
# ever displayed — a bug that looked like "no projects". Nothing equivalent survives:
# this page collapses with <details>, which pairs nothing and needs no generated CSS, so
# there is no drift to pin. tests/artifact-board.test.sh asserts the <details> behaviour
# (collapsed by default, finished projects under a divider) where the markup lives.
# Two, not four, is still the fact worth reading off the page: beta is malformed and
# gamma has no snapshot, so neither is an instance on the board. Sixteen blocks: alpha's
# sixteen projects — including the RETAINED done ones, which are on the board as
# reference cards even though their tasks were never read, and the five whose
# deliverable_paths line is hostile, which are still projects and still render — plus
# delta's one.
assert "one project block per project of the 2 rendered instances" \
  "$(eq "$(grep -cF '<details class="proj' "$HTML")" 17)"

echo "== discovery is explicit, never a glob =="
D1="$( cd "$ALPHA" && bash "$BOARD" --out "$TMP/d1.html" 2>&1 )"
assert "no args, no boardInstances -> just this instance" "$(has '1 instance(s)' "$D1")"
# The page carries no "listed from" footer to read, so the source is asserted by what
# is ON it: alpha's work and not delta's. That is the fact the footer line stood for.
assert "…and the page carries only that instance's work" \
  "$(yes_if sh -c 'grep -qF "CI hardening" "$1" && ! grep -qF "Hostile input" "$1"' _ "$TMP/d1.html")"
python3 - "$ALPHA/instance.config.json" "$DELTA" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["boardInstances"]=[".",sys.argv[2]]
json.dump(d,open(p,"w"),indent=2)
PY
D2="$( cd "$ALPHA" && bash "$BOARD" --out "$TMP/d2.html" 2>&1 )"
assert "boardInstances is used when no dirs are named"   "$(has '2 instance(s)' "$D2")"
assert "…and BOTH instances' work is on the page"        \
  "$(yes_if sh -c 'grep -qF "CI hardening" "$1" && grep -qF "Hostile input" "$1"' _ "$TMP/d2.html")"
assert "named dirs override the config"                  "$(has '1 instance(s)' "$( cd "$ALPHA" && bash "$BOARD" --out "$TMP/d3.html" "$DELTA" 2>&1 )")"
printf 'not json at all' > "$TMP/badcfg-cfg"
cp "$ALPHA/instance.config.json" "$TMP/goodcfg" && cp "$TMP/badcfg-cfg" "$ALPHA/instance.config.json"
D4="$( cd "$ALPHA" && bash "$BOARD" --out "$TMP/d4.html" 2>&1 )"
assert "an unreadable config falls back to this instance" "$(has '1 instance(s)' "$D4")"
assert "…and says so on stderr"                           "$(has 'unreadable' "$D4")"
# A config that PARSES but whose top level is not an object. This is a different
# failure from "not JSON at all" above: json.loads succeeds, so the except clause is
# never reached, and a bare .get() on the result raises AttributeError — which was
# NOT in the caught tuple, so the run ended in a traceback instead of the documented
# fallback. One case per JSON top-level type that has no .get.
for shape in '["a","b"]' '"just-a-string"' '5' 'null' 'true'; do
  printf '%s\n' "$shape" > "$ALPHA/instance.config.json"
  RC=0; OUT="$( cd "$ALPHA" && bash "$BOARD" --out "$TMP/dshape.html" 2>&1 )" || RC=$?
  assert "a config whose top level is $shape falls back, exit 0" "$(eq "$RC" 0)"
  assert "…rendering just this instance"   "$(has '1 instance(s)' "$OUT")"
  assert "…with no Python traceback"       "$(hasnt 'Traceback' "$OUT")"
done
cp "$TMP/goodcfg" "$ALPHA/instance.config.json"
NOSUCH="$( cd "$TMP" && bash "$BOARD" --out "$TMP/d5.html" "$TMP/no-such-instance" 2>&1 )"
assert "a named directory that does not exist is skipped, not fatal" "$(has 'no such directory' "$NOSUCH")"
# No readable snapshot ⇒ NOTHING is written, and the run says so. The kanban page used
# to write an empty-state note here; publishing an empty page is not useful, and the
# person who can fix it is reading stderr, not the artifact.
assert "…and no page is written at all"                     "$(yes_if test ! -e "$TMP/d5.html")"
assert "…while the run says so on stderr"                   "$(has 'nothing written' "$NOSUCH")"

echo "== a drifted snapshot cannot blank the board =="
# THE MAJOR CASE. These snapshots are syntactically valid JSON, so the malformed-file
# path above never sees them — the wrong TYPES surface later, at int() and at a sort
# comparison. A bare int("many") raises ValueError before a single byte of output is
# written, so one drifted instance took the whole board down with it, including every
# healthy instance on the same page. That directly contradicts the header's promise
# that a malformed snapshot is a visible card rather than a crash.
#
# Each case therefore asserts BOTH halves: this instance survives, AND the healthy
# instance beside it still renders. A fix that swallows the drift by dropping every
# instance would pass the first half alone.
DRIFT="$TMP/group/_ai-bridge-drift"
mkdir -p "$DRIFT" "$DRIFT/$AB_DIR"
drift_case() { # <label> <snapshot json>
  printf '%s\n' "$2" > "$DRIFT/$AB_SNAPSHOT"
  local rc=0 out
  # rm FIRST. Without this the file survives from the previous case, and both the
  # "an output file is written" and "healthy instance still renders" assertions pass
  # by reading STALE output — green while the run they claim to describe crashed.
  rm -f "$TMP/drift.html"
  out="$( cd "$TMP" && bash "$BOARD" --out "$TMP/drift.html" "$ALPHA" "$DRIFT" 2>&1 )" || rc=$?
  assert "$1: exits 0"                       "$(eq "$rc" 0)"
  assert "$1: an output file is written"      "$(yes_if test -s "$TMP/drift.html")"
  assert "$1: no traceback"                   "$(hasnt 'Traceback' "$out")"
  assert "$1: the healthy instance still renders" "$(fhas 'CI hardening' "$TMP/drift.html")"
}
drift_case "a non-numeric task count" \
  '{"group":"drift","counts":{"tasks":"many","projects":1,"awaiting":0},"projects":[]}'
drift_case "a non-numeric phase total" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","phase_progress":{"total":"two","done":"one"},"phases":[],"tasks":[]}]}'
drift_case "a non-numeric phase order" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","phase_progress":{"total":2,"done":1},"phases":[{"order":"first","title":"A","status":"active"},{"order":2,"title":"B","status":"done"}],"tasks":[]}]}'
# A non-string group is the TypeError variant: it survives a truthiness test, so it
# reached the awaiting sort still an int and compared int with str there. It needs an
# awaiting item to reach that sort at all, which is why this fixture carries one.
drift_case "a non-string group" \
  '{"group":5,"counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","tasks":[{"id":"task-001","title":"T","status":"blocked","awaiting":"unblock","open_questions":0,"prs":[]}]}]}'
# ANCHORED to the markup that carries a group on purpose. A bare `fhas 5` passes on any
# page: the stylesheet alone contains "5" dozens of times, so it would report green even
# if the coercion dropped the group entirely. The assertion has to name where it appears
# — here the decision rail's "group › project" line, which is why the fixture carries an
# awaiting item at all.
assert "…and the coerced group is rendered in the rail" \
  "$(fhas 'class="where">5 › ' "$TMP/drift.html")"
rm -rf "$DRIFT"

echo "== installer: on by first stamp, off by deletion, forever =="
INST="$TMP/group/_ai-bridge-stamped"
mkdir -p "$INST"
( cd "$INST" && git init -q . ) 2>/dev/null || true
bash "$BRIDGE_INSTALL" "$INST" >"$TMP/i1.out" 2>&1
assert "the first stamp creates SNAPSHOT.json"  "$(yes_if test -f "$INST/$AB_SNAPSHOT")"
assert "…and says the instance is on the board" "$(fhas "seed  $AB_SNAPSHOT" "$TMP/i1.out")"
assert "the seeded snapshot is VALID JSON (no note on a brand-new instance)" \
  "$(yes_if python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$INST/$AB_SNAPSHOT")"
FRESH="$( cd "$TMP" && bash "$BOARD" --out "$TMP/fresh.html" "$INST" 2>&1 )"
assert "…so a fresh instance renders with no unreadable note" "$(has '0 unreadable snapshot(s)' "$FRESH")"
assert "the seeded .gitignore ignores the snapshot" "$(fhas 'SNAPSHOT.json' "$INST/.gitignore")"
assert "…and the derived board HTML"                "$(fhas 'board.html' "$INST/.gitignore")"
printf 'LOCAL SNAPSHOT CONTENT\n' > "$INST/$AB_SNAPSHOT"
bash "$BRIDGE_INSTALL" "$INST" >/dev/null 2>&1
assert "a refresh never clobbers an existing snapshot" "$(fhas 'LOCAL SNAPSHOT CONTENT' "$INST/$AB_SNAPSHOT")"
# THE OFF SWITCH IS CONFIG NOW, NOT DELETION — and the difference is deliberate.
#
# It used to be opt-in by presence: `rm SNAPSHOT.json` was permanent because only a FIRST
# stamp created the file. That inverted the common case — every instance stamped before
# the board existed silently stayed off it, and three of three real instances were in
# that state. So `board` in instance.config.json decides, and it survives a re-stamp.
#
# What deletion still does, and what it no longer does, are both asserted here.
rm "$INST/$AB_SNAPSHOT"
bash "$BRIDGE_INSTALL" "$INST" >"$TMP/i2.out" 2>&1
assert "a re-stamp RESTORES a deleted snapshot (board defaults on)" \
  "$(yes_if test -f "$INST/$AB_SNAPSHOT")"
assert "…and says so"                               "$(fhas "seed  $AB_SNAPSHOT" "$TMP/i2.out")"

# `board: false` is the durable opt-out: it must beat a re-stamp, which deletion no
# longer does. This is the assertion a no-publish instance depends on.
rm "$INST/$AB_SNAPSHOT"
python3 - "$INST/instance.config.json" <<'PYCFG'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d["board"] = False
json.dump(d, open(p, "w"), indent=2)
PYCFG
bash "$BRIDGE_INSTALL" "$INST" >"$TMP/i3.out" 2>&1
assert "board:false keeps it off across a re-stamp"  "$(yes_if test ! -e "$INST/$AB_SNAPSHOT")"
assert "…and the installer says which key did it"   "$(fhas 'board: false in instance.config.json' "$TMP/i3.out")"
python3 - "$INST/instance.config.json" <<'PYCFG'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d.pop("board", None)
json.dump(d, open(p, "w"), indent=2)
PYCFG
assert "an ABSENT board key still means on"          "$(yes_if sh -c 'bash "$1" "$2" >/dev/null 2>&1; test -f "$2/$AB_SNAPSHOT"' _ "$BRIDGE_INSTALL" "$INST")"

# The writer is unchanged: it refreshes an existing snapshot and NEVER creates one. That
# is what still makes a mid-session `rm` take effect immediately.
rm "$INST/$AB_SNAPSHOT"
mkdir -p "$INST/projects/x/tasks"
cat > "$INST/projects/x/project.md" <<'PRJ'
---
type: Project
title: After the rm
kind: build
status: active
---
PRJ
( cd "$INST" && bash "$TPL/plugin/scripts/write-snapshot.sh" --quiet ) || true
assert "the writer never resurrects a deleted snapshot" "$(yes_if test ! -e "$INST/$AB_SNAPSHOT")"
OFFBOARD="$( cd "$TMP" && bash "$BOARD" --out "$TMP/off.html" "$INST" 2>&1 )"
assert "…and that instance is off the board"           "$(has "no $AB_SNAPSHOT (off the board)" "$OFFBOARD")"
assert "…so there is nothing to write"                 "$(has 'nothing written' "$OFFBOARD")"
assert "…and no page carries its content"              "$(yes_if test ! -e "$TMP/off.html")"

# ---------------------------------------------------------------- `closed`
# projects/CLOSED.md is TRACKED and written by close-project-folder.sh; this half of the
# chain is the parse. Two properties: a stanza with deliverables becomes an entry, and
# ABSENCE LEAVES THE KEY OUT — never an empty array, so a reader can tell "no closed
# projects" from "a snapshot older than this key".
echo
echo "== projects/CLOSED.md -> the \`closed\` array =="
CLI="$TMP/group/_ai-bridge-closed"
mkdir -p "$CLI/projects" "$CLI/$AB_DIR"
: > "$CLI/$AB_SCHEMA"; echo '{ "org": "fixture-org" }' > "$CLI/instance.config.json"
: > "$CLI/$AB_SNAPSHOT"
( cd "$CLI" && bash "$TPL/plugin/scripts/write-snapshot.sh" --quiet )
assert "no CLOSED.md ⇒ no \`closed\` key at all"  "$(yes_if python3 -c '
import json,sys; sys.exit(0 if "closed" not in json.load(open(sys.argv[1])) else 1)' "$CLI/$AB_SNAPSHOT")"

cat > "$CLI/projects/CLOSED.md" <<'CLOSED'
# Closed projects

## ai-bridge-2x

- closed: 2026-09-08
- pinned: 8fefa76aaaaaaaabbbbbbbbccccccccdddddddd
- outcome: ten merged PRs, 2.0.1 → 2.1.5
- deliverable: `/projects/ai-bridge-2x/project.md` — https://github.com/o/r/blob/8fefa76aaaaaaaabbbbbbbbccccccccdddddddd/projects/ai-bridge-2x/project.md
  - restore: `gh api repos/o/r/contents/projects/ai-bridge-2x/project.md?ref=8fefa76 --jq .content | base64 -d > /tmp/project.md`

## shipped-nothing

- closed: 2026-09-01
- pinned: 1111111111111111111111111111111111111111
- outcome: cancelled before it produced anything
CLOSED
( cd "$CLI" && bash "$TPL/plugin/scripts/write-snapshot.sh" --quiet )
CLJ="$CLI/$AB_SNAPSHOT"
assert "the snapshot still parses as JSON"       "$(yes_if python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$CLJ")"
assert "…one entry, and it is the one WITH deliverables" "$(yes_if python3 -c '
import json,sys
c = json.load(open(sys.argv[1]))["closed"]
sys.exit(0 if len(c) == 1 and c[0]["slug"] == "ai-bridge-2x" else 1)' "$CLJ")"
assert "…a project that shipped NOTHING adds no entry"   "$(yes_if python3 -c '
import json,sys
c = json.load(open(sys.argv[1]))["closed"]
sys.exit(0 if not any(x["slug"] == "shipped-nothing" for x in c) else 1)' "$CLJ")"
assert "…the date, sha and one-line outcome are carried" "$(yes_if python3 -c '
import json,sys
c = json.load(open(sys.argv[1]))["closed"][0]
sys.exit(0 if c["closed"] == "2026-09-08" and c["sha"].startswith("8fefa76")
         and c["outcome"].startswith("ten merged PRs") else 1)' "$CLJ")"
assert "…one deliverable, path and PERMALINK"    "$(yes_if python3 -c '
import json,sys
d = json.load(open(sys.argv[1]))["closed"][0]["deliverables"]
sys.exit(0 if len(d) == 1 and d[0]["path"] == "/projects/ai-bridge-2x/project.md"
         and "/blob/8fefa76" in d[0]["url"] and "/blob/main/" not in d[0]["url"] else 1)' "$CLJ")"
# The restore command is CLOSED.md's, for a human at a terminal. It names a local
# filesystem path, so it stays out of the file one step from being published.
assert "…and the restore command is NOT carried"  "$(fhasnt 'base64 -d' "$CLJ")"

# THE WHOLE URL, UNDER EVERY AWK ON THE MACHINE. The `path — url` separator is an em
# dash, which is multi-byte: index()/substr() count BYTES on BSD awk and mawk and
# CHARACTERS on gawk in a UTF-8 locale, so the parse's old hardcoded `q + 5` started two
# characters late under gawk and served `tps://…`. Asserting the path suffix is exactly
# what let that through, so this asserts the scheme too — and runs the whole write under
# each awk present via a PATH shim, skipping (loudly) any that is not installed.
CLURL='https://github.com/o/r/blob/8fefa76aaaaaaaabbbbbbbbccccccccdddddddd/projects/ai-bridge-2x/project.md'
for _awk in gawk mawk awk; do
  _bin="$(command -v "$_awk" 2>/dev/null || true)"
  if [ -z "$_bin" ]; then echo "   (skip: no $_awk here — its units are unpinned on this machine)"; continue; fi
  _shim="$TMP/awkshim-$_awk"; mkdir -p "$_shim"
  printf '#!/bin/sh\nexec %s "$@"\n' "$_bin" > "$_shim/awk"; chmod +x "$_shim/awk"
  ( cd "$CLI" && PATH="$_shim:$PATH" bash "$TPL/plugin/scripts/write-snapshot.sh" --quiet )
  assert "…the deliverable URL survives \`$_awk\` WHOLE, scheme included" "$(yes_if python3 -c '
import json,sys
d = json.load(open(sys.argv[1]))["closed"][0]["deliverables"]
sys.exit(0 if d[0]["url"] == sys.argv[2] else 1)' "$CLJ" "$CLURL")"
done
# The loop can only pin the awks a machine HAS, and CI is macos-latest — BSD awk, no
# gawk, no mawk — so the invariant is asserted statically as well: the offset past the
# separator is DERIVED from its length and never a literal, which is the one property
# that holds in either unit.
assert "…and the parse derives that offset, never hardcodes it" "$(yes_if python3 -c '
import re, sys
prog = open(sys.argv[1], encoding="utf-8").read().split("closed_records()", 1)[1].split("\n}", 1)[0]
sys.exit(0 if "q + length(SEP)" in prog and not re.search(r"q \+ [0-9]", prog) else 1)' "$TPL/plugin/scripts/write-snapshot.sh")"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
