#!/usr/bin/env bash
#
# write-snapshot.sh — write this instance's board snapshot (SNAPSHOT.json).
#
#   Usage: write-snapshot.sh [--quiet]
#
# WHAT IT IS. One flat JSON file at the bundle root, derived from the bundle's own
# frontmatter (`projects/*/project.md`, `projects/*/phases/*.md`,
# `projects/*/tasks/*.md` — the schema-defined locations, per SCHEMA.md). It is the
# OBSERVATION CONTRACT for the cross-instance board: `build-board.sh` reads
# these files, from several instances, and renders one HTML page. Nothing else reads
# it, and nothing reads the bundle to build the board.
#
# ABSENCE IS THE OFF SWITCH — the same contract as AWAITING.md, and the reason this
# script exists rather than the PM hand-assembling JSON:
#
#   · No SNAPSHOT.json  ⇒  exit 0, write nothing, say nothing. That instance simply
#     does not appear on the board.
#   · `rm SNAPSHOT.json` is therefore permanent: this script NEVER creates the file,
#     and `/<plugin>:init` creates it on the FIRST STAMP ONLY (FIRST_STAMP), so
#     no later refresh resurrects it.
#   · `touch SNAPSHOT.json` turns it back on. Presence is the switch; content is
#     derived, so an empty or truncated file is fine — the next run overwrites it.
#
# It must NOT be machinery the stamp re-creates. AUTONOMY.md is a deletable capability that
# used to live there, and the old install.sh re-linked it unconditionally, so a
# per-bundle `rm` was silently undone. A generated,
# gitignored root file has no such hole.
#
# DATA GOVERNANCE — READ BEFORE ADDING A FIELD.
# The board is rendered to an HTML page that a human may PUBLISH to a URL. AWAITING.md
# never leaves the instance; this file is one step from leaving it. So the snapshot
# deliberately carries STRICTLY LESS than AWAITING.md does:
#
#   CARRIED (the whole allowlist):
#     project: slug, title, description, kind, status, autonomy, owner (a GitHub
#              username — see the reversal below before you remove it),
#              deliverable_paths (bundle-relative paths, VERBATIM from project.md —
#              closeout stamps these, this file only forwards them; see task-007's
#              board panel and the shape check build-board.sh applies before render)
#     phase:   file, order, title, status
#     closed:  slug, close date, pinned sha, one-line outcome, and one bundle-relative
#              path + GitHub permalink per deliverable — read from the TRACKED
#              projects/CLOSED.md, which close-project-folder.sh writes. A SECOND
#              deliberate widening (2026-09-08): a closed project has no folder left, so
#              the board can only reach it through here. The permalink is the one URL
#              other than a PR URL this file carries, and it is a github.com blob link
#              by construction; the `restore:` command in CLOSED.md is NOT carried, and
#              the board applies href()'s http/https rule to the URL like any other.
#     task:    id, title, kind, status, assignee (a ROLE slug, never a person),
#              in_flight, pr_mergeable, awaiting (a verb, not a reason), open_questions (a COUNT),
#              open_question_ids (one `Q<n>` LABEL per open question, never its text —
#              read the widening note below before you touch it), prs (repo, number, url)
#   THE LABELS ARE A DELIBERATE WIDENING OF THIS LIST (2026-08-31), and the shape is
#   what keeps it narrow. Until then the snapshot carried a COUNT and nothing else, and
#   the board's `answer Q<n>` control — which reads a question's number out of the
#   question's own text — therefore had NOTHING TO READ: measured on a real 8-project
#   instance, `answer Q<n>` × 0 and the unnumbered `answer question` × 18, on every
#   instance, every render. A count cannot produce three handles for a task with three
#   questions, so the fix had to be here rather than in the renderer.
#   WHAT `open_question_ids` MAY CONTAIN, exactly: `Q` followed by decimal digits, or
#   the empty string for a question that names no number. question_labels() below can
#   emit nothing else — not one byte of question TEXT, which stays on the NEVER list
#   directly below and is still asserted absent by tests/snapshot.test.sh. A label is a
#   HANDLE INTO the document ("the second question in this task"), the same class of
#   thing as `depends_on`'s task IDs; the question it names is still only in the task
#   doc and in AWAITING.md.
#   NEVER CARRIED:
#     · task `description:` and every document BODY (`# Context`, `# Notes`,
#       `# Result`) — free prose, the likeliest place a logged-in page or a customer
#       record gets quoted;
#     · the TEXT of `open_questions` or of a blocker reason — the board shows the
#       verb (❓ answer, ⛔ unblock) and the task it belongs to, and the human opens
#       the task doc for the question itself. AWAITING.md carries that text; the
#       board does not;
#     · any author identity (`authorEmail`), any filesystem path outside this bundle
#       (`reposRoot`, `worktreeRoot`), any URL other than a PR URL. `deliverable_paths`
#       is the one exception to enforcing this by construction rather than by trust:
#       this file forwards it VERBATIM (see the CARRIED entry above) and does not
#       itself check the shape, so a hand-edited project.md can put an out-of-bundle
#       path into SNAPSHOT.json (gitignored, never published as-is).
#       WHAT THIS FILE DOES AND DOES NOT GUARANTEE, stated exactly, because an earlier
#       version of this paragraph claimed a safety property the code did not have and
#       an external review walked straight through it: nothing here keeps such a path
#       out of SNAPSHOT.json. The only thing between it and a PUBLISHED page is
#       build-board.sh's bundle_deliverable(), which renders an entry only if the WHOLE
#       value matches one `/projects/<slug>/deliverables/<segment>[/<segment>…]` shape —
#       not a prefix test with a list of bad characters, which is what four review
#       rounds each defeated in a new way. It is also SCOPED TO THIS KEY: every other
#       list key is emitted as parsed, with no consumer that re-checks anything.
#
# `owner:` IS CARRIED, AND THAT IS A REVERSAL — read this before "restoring" the rule.
# Until 2026-08-26 the list above ended with `owner:` on the NEVER side, on the ground
# that on a bundle shared by two humans it names a PERSON and the board's HTML can be
# published. That reasoning is not wrong; it was outweighed. Artifact publishing turned
# out to be ACCOUNT-SCOPED — exactly one account can ever publish to a given URL — so two
# humans cannot share one published board, and each one's board has to separate "my
# projects" from "the other owner's" to be worth opening at all. A board that cannot say
# whose project is whose cannot do that. So identity is now carried DELIBERATELY, for
# exactly one field and exactly one purpose: partitioning the page (build-board.sh).
#
# The shape of the concession is what keeps it narrow, and it is the shape to preserve:
#   · it is a GitHub USERNAME, never an email — public, stable, and already what
#     SCHEMA.md requires of `owner:`. `authorEmail` stays on the NEVER list beside it,
#     for precisely the difference that an address is a contact detail and a login is a
#     handle;
#   · the value is copied VERBATIM from the project document and resolved nowhere here.
#     The board applies SCHEMA.md's resolution (project `owner:` → `defaultOwner` →
#     unowned), so this file gains no config reader and no second copy of that rule;
#   · nothing else moves. Task `owner:` is not carried: the board partitions by PROJECT,
#     and a per-task override is a dispatch concern, not a rendering one.
#
# THE PUBLISHED PAGE NAMES THOSE OWNERS. The other-owners section is collapsed by
# default, and that is ERGONOMICS, not a privacy control — the names are in the HTML
# whether the section is open or shut. Do not describe the collapse as redaction, here or
# on the page. The decision, and the account-scoping fact that forced it, are recorded in
# /knowledge/findings/board-owner-identity-named-not-redacted.md.
#
# Titles ARE carried: a board without them is unreadable. They are written by humans
# and could say anything, so **this file is exactly as sensitive as the task documents
# it derives from** — that sentence is repeated in the file's own `_sensitivity` key,
# because whoever finds the JSON will not have read this header. No customer PII
# belongs in a task title in the first place (instance `CLAUDE.md`, "Data handling").
#
# Deterministic, no network, no `jq`, no `python3` — bash + awk, like every other
# script under `scripts/`, so it ships into every instance unchanged. `generated_at`
# is the only non-deterministic field; set `SNAPSHOT_NOW` to pin it.
#
# A `status: done` PROJECT IS READ NO FURTHER THAN ITS FRONTMATTER. Its stanza is
# emitted from fields already parsed; `phases/` and `tasks/` are never opened. See the
# `continue` in the assembly loop for why that one line is what makes `retain: true`
# affordable.
#
# Verified by tests/snapshot.test.sh.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet|-q) QUIET=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    *) echo "usage: $0 [--quiet]" >&2; exit 2 ;;
  esac
  shift
done

ab_is_bundle . || {
  echo "write-snapshot: run from a control-panel instance root (instance.config.json)." >&2
  exit 2
}

OUT="$AB_SNAPSHOT"

# The off switch, checked before any work. Absent = this instance opted out of the
# board; that is silence and success, never an error and never a create.
if [[ ! -e "$OUT" ]]; then
  [[ $QUIET -eq 1 ]] || echo "write-snapshot: no $OUT — this instance is off the board (touch $OUT to enable)."
  exit 0
fi
# A directory (or anything not a regular file) at that path is a human's doing, and
# overwriting it would destroy content. Refuse loudly instead.
[[ -f "$OUT" ]] || { echo "write-snapshot: $OUT exists but is not a regular file — refusing to overwrite." >&2; exit 2; }

NOW="${SNAPSHOT_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
GROUP="$(ab_group .)"

# ---------------------------------------------------------------- JSON primitives
# Single-line YAML values only, so parameter expansion is enough and correct: strip
# C0 controls and DEL (they cannot appear in a legal JSON string unescaped), then
# escape the four things that can occur in a title. Order matters — backslash first.
jstr() {
  local s
  s="$(printf '%s' "${1-}" | tr -d '\000-\010\013\014\016-\037\177')"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '"%s"' "$s"
}

# ---------------------------------------------------------------- frontmatter
# Same contract as validate-bundle.sh: exit 3 when the file does not open with
# `---`, exit 4 when it opens and never closes. Either way we treat the document as
# unreadable and skip it — a malformed doc is validate-bundle's finding to report,
# not something to guess at here.
frontmatter() {
  awk '
    NR==1 && $0!="---" { bad=3; exit }
    /^---$/ { n++; if (n==2) { closed=1; exit } ; next }
    n==1 { print }
    END { if (bad) exit bad; if (!closed) exit 4 }
  ' "$1"
}

# A scalar field. Strips one layer of matching surrounding quotes (a YAML title may
# legitimately be quoted because it contains a colon).
fmfield() { # <frontmatter> <key>
  local v
  v="$(printf '%s\n' "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1)"
  v="${v%"${v##*[![:space:]]}"}"          # rtrim
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s' "$v"
}

# An enum-ish field: same, but a trailing `# comment` is not part of the value.
fmenum() { # <frontmatter> <key>
  local v; v="$(fmfield "$1" "$2")"
  v="${v%%#*}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

# The raw text of a list field, in BOTH YAML forms (inline `k: [ a, b ]` and a block
# sequence of `- ` lines). Copied in shape from validate-bundle.sh's refs_for, for
# the same reason: no instance uses block style today, and nothing forbids it.
#
# DELIBERATELY COMMENT-AGNOSTIC — read this before stripping a trailing `# comment`
# here again. Six keys share this helper and five are FREE TEXT, so anything deciding
# where an inline list ENDS decides it for prose a human wrote, and two attempts from
# here both ended a list early on real documents: truncate-at-first-`]` stopped inside a
# Markdown PR link (`[repo#N](url)`, the style this bundle's CLAUDE.md mandates), and
# quote-parity stopped at that same `]` when the link sat between escaped quotes. Each
# dropped the second entry off `open_questions` — which gates `draft -> ready` and feeds
# AWAITING.md — invisibly. Only `deliverable_paths` needs a strip and only it can afford
# one, so it lives at that consumer: deliverable_path_entries below.
list_region() { # <frontmatter> <key>
  printf '%s\n' "$1" | awk -v k="$2" '
    $0 ~ "^" k ":" { rest=$0; sub(/^[^:]*:/, "", rest); print rest; inblk=1; next }
    inblk && /^[[:space:]]+-[[:space:]]*/ { print; next }
    inblk && /^[[:space:]]*$/ { next }
    /^[^[:space:]]/ { inblk=0 }
  '
}

# Is a list field non-empty? `[]`, `[ ]`, and a bare key all count as empty.
list_filled() { # <frontmatter> <key>
  local r; r="$(list_region "$1" "$2")"
  r="$(printf '%s' "$r" | tr -d '[:space:]' | tr -d '[]')"
  [[ -n "$r" ]]
}

# A genuine trailing YAML comment, removed line by line: a `#` preceded by
# whitespace and outside a quoted scalar starts one, and everything from there to
# end of line goes. NOT folded into list_region()/yaml_list_entries() above —
# those stay DELIBERATELY comment-agnostic for the five free-text keys they serve
# (see list_region's header: a blanket strip there has twice eaten a real entry).
# This exists for the two callers below that need comment-safety without touching
# that shared contract: acceptance_criteria_filled() and depends_ids(). Same
# quote-tracking as deliverable_path_entries()'s own scoped strip, minus its extra
# bracket-position gate — a deliverable_paths-specific heuristic neither caller here
# needs, since both only ever see a single flow list or one block entry per line.
strip_trailing_comment() { # <text, one or more lines>
  awk '
    function ws(x) { return index(" \t\r\n", x) > 0 }
    {
      q = ""; fresh = 1; cut = 0; n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (q != "") {
          if (q == "\"" && c == "\\") { i++; continue }
          if (c == q) {
            if (q == "'\''" && substr($0, i + 1, 1) == "'\''") { i++; continue }
            q = ""
          }
          continue
        }
        if (fresh && (c == "\"" || c == "'\''")) { q = c; fresh = 0; continue }
        if (c == "#" && i > 1 && ws(substr($0, i - 1, 1))) { cut = i; break }
        fresh = (ws(c) || c == "," || c == "[" || c == "-")
      }
      print (cut > 0 ? substr($0, 1, cut - 1) : $0)
    }
  ' <<<"$1"
}

# Comment-safe counterpart to list_filled(), for acceptance_criteria ONLY: this
# boolean drives the `approve` verb in the awaiting switch below, which is exactly
# the field AWAITING.md is built from. `acceptance_criteria: []  # still drafting`
# used to strip to a non-empty `#stilldrafting…` and read as filled — a draft with
# NO real criteria reported as needing a human to approve it.
acceptance_criteria_filled() { # <frontmatter>
  local r
  r="$(strip_trailing_comment "$(list_region "$1" acceptance_criteria)")"
  r="$(printf '%s' "$r" | tr -d '[:space:]' | tr -d '[]')"
  [[ -n "$r" ]]
}

# ONE LINE PER OPEN QUESTION, IN DOCUMENT ORDER: its `Q<n>` label, or `-` when the
# question names no number. This is the field the board's per-question control is built
# from, and it replaces a total that could never produce more than one handle.
#
# THE ONLY BYTES IT CAN EMIT are `Q`, decimal digits, and `-`. That is what keeps a
# per-question field inside the header's allowlist: the entry's own text is read here
# and discarded here, and nothing derived from it beyond the number leaves. `-` rather
# than an empty line because the caller reads this through `while read`, where an empty
# line and "no line at all" are the same thing — and an unnumbered question must still
# COUNT as a question and still get its own (unnumbered) handle.
#
# IT READS THE NUMBER THE QUESTION CARRIES, NEVER THE POSITION IN THE LIST. Answering
# Q1 and leaving Q2 open is the ordinary case; a label taken from the index would then
# name the wrong question. The rule:
#   · skip an `advisor:` marker (the project-manager stamps escalations with one),
#   · skip at most ONE `·`-delimited lead segment — a stamped entry reads
#     `2026-08-30T16:01:52Z · Q2: …` — bounded at 41 so an unbounded skip cannot hunt
#     for a `Q7` mentioned in the middle of a question's prose,
#   · then read `Q` + 1-3 digits that END there. `Q1 (HALF ANSWERED …` — no colon —
#     is a real shape on a real board and must yield Q1; `Q1234` yields nothing.
# This is the only reader of a question's NUMBER; the renderer only parses the label, and
# snapshot.test.sh pins the two end-to-end (write the snapshot, render it, read the
# buttons back).
#
# SPELLED WITHOUT `\s`/`\b`: banned file-wide, see the header of tests/snapshot.test.sh.
# `tolower()` before matching is how the case-insensitive `q` is done without gawk's
# IGNORECASE, and it is length-preserving for ASCII, so the offsets stay valid; the
# `·` bound is counted in whatever units the local awk uses (bytes on a BSD awk,
# characters on a gawk in a UTF-8 locale), which a heuristic bound can afford.
question_labels() { # <frontmatter>
  yaml_list_entries "$1" open_questions | awk '
    {
      s = tolower($0)
      sub(/^[ \t\r]+/, "", s)
      if (substr(s, 1, 8) == "advisor:") { s = substr(s, 9); sub(/^[ \t\r]+/, "", s) }
      p = index(s, "·")
      if (p > 0 && p <= 41) sub(/^[^·]*·[ \t\r]*/, "", s)
      if (substr(s, 1, 8) == "advisor:") { s = substr(s, 9); sub(/^[ \t\r]+/, "", s) }
      lab = "-"
      if (match(s, /^q[0-9][0-9]?[0-9]?/)) {
        nxt = substr(s, RLENGTH + 1, 1)
        if (nxt == "" || index("0123456789abcdefghijklmnopqrstuvwxyz_", nxt) == 0)
          lab = "Q" (substr(s, 2, RLENGTH - 1) + 0)
      }
      print lab
    }'
}

# How many open questions — ONE PER PARSED ENTRY, so this and question_labels() can
# never disagree about how many there are. They used to be derived separately: this
# counted `Q<n>` TOKENS in the raw region, which reports 0 for a task whose three
# questions are all spelled `Q1 (…` with no colon, and then falls back to 1. A count
# that disagrees with the handles beside it is the same class of defect as a count that
# cannot produce handles at all.
# An unnumbered but non-empty list still counts as 1 when nothing parses at all: the
# board only ever renders "this task needs an answer", so the fallback is honest rather
# than a guess at a number, and the renderer degrades to one unnumbered control for it.
count_questions() { # <frontmatter>
  local n
  n="$(question_labels "$1" | awk 'END { print NR + 0 }')"
  if [[ "${n:-0}" -gt 0 ]]; then printf '%s' "$n"
  elif list_filled "$1" open_questions; then printf '1'
  else printf '0'; fi
}

# ONE normaliser for every list field, because three ad-hoc pipelines drifted into
# three different bugs (CodeRabbit, PR #8): a quoted `depends_on` entry kept its
# closing quote so the `.md` strip missed and the ID came out `task-001.md"`; a
# flow-form `advisor_notes` with two entries counted 1; and a flow-form
# `open_questions` stranded a quote on the first and last entry.
#
# The single cause in all three was ORDER: split before trimming, or strip quotes
# before removing the flow brackets, and the outer entries keep a stray character.
# So: trim, unwrap the brackets, trim again, THEN split, THEN unquote, THEN trim.
#
# Splitting is quote-aware. A quoted list is split on the quote-comma-quote seam,
# never a bare comma — question text routinely contains commas and splitting on those
# shreds one question into several. An unquoted list (the form `depends_on` uses) has
# no such hazard, so a bare comma is the right separator there.
#
# Takes the REGION, not the key, so the one caller that pre-processes its own region
# (deliverable_path_entries) reuses this splitter instead of copying it. Every other
# caller goes through yaml_list_entries below and passes the region untouched.
list_entries_from_region() { # <region>
  local inner
  inner="$(printf '%s\n' "$1" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | sed -e 's/^-[[:space:]]*//' \
    | sed -e 's/^\[//' -e 's/\]$//' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$inner" in
    *'"'*) inner="$(printf '%s\n' "$inner" | sed -e 's/"[[:space:]]*,[[:space:]]*"/\
/g')" ;;
    *)     inner="$(printf '%s\n' "$inner" | sed -e 's/[[:space:]]*,[[:space:]]*/\
/g')" ;;
  esac
  printf '%s\n' "$inner" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | sed -e 's/^"//' -e 's/"$//' \
    | sed -e "s/^'//" -e "s/'\$//" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | grep -v '^$' \
    | grep -vE '^(\[|\]|\[\])$' || true
}

yaml_list_entries() { # <frontmatter> <key>
  list_entries_from_region "$(list_region "$1" "$2")"
}

# The task IDs a task depends on. Emitted as IDs, not paths: an ID is what a human
# reads on the board and the full path is derivable from the project slug, so
# carrying the path would be redundant AND longer. Bundle-relative either way, so
# this adds no out-of-bundle path to the published page.
#
# WHY THIS IS INSIDE THE ALLOWLIST rather than an exception to it: `depends_on` is a
# structural reference between two documents in this bundle, exactly like `phase:`
# which the snapshot already carries. It is not free prose, not identity, and not a
# path outside the bundle — the four things the allowlist actually names. A reader
# adding a field here should be able to say which of those four it is; this is none.
#
# COMMENT-STRIPPED before the split, unlike yaml_list_entries()'s other three
# callers: `depends_on: [ /projects/p/tasks/task-006.md ]  # blocked by
# /Users/…/notes[1].md` used to lose the real edge AND fabricate a bogus one —
# `notes[1]`, a fragment of a local filesystem path off the comment — because the
# unstripped comma-split saw the comment text as part of the (only) entry. A
# structural reference losing its edge is exactly the failure `depends_on`'s own
# allowlist entry above says this field must not have.
depends_ids() { # <frontmatter>
  # Entries arrive already trimmed and unquoted, so basename-then-suffix is safe.
  list_entries_from_region "$(strip_trailing_comment "$(list_region "$1" depends_on)")" \
    | sed -e 's#^.*/##' -e 's#\.md$##' | grep -v '^$' || true
}

# The bundle-relative deliverable paths a done project's closeout stamped into
# `deliverable_paths:` (close-project-folder.sh). Carried VERBATIM — unlike
# `depends_ids` above this is not normalised to a bare id, because a deliverable is
# a file to copy a path TO, not a document to reference by id.
#
# WHY THIS COSTS NOTHING EXTRA: it is read from the SAME frontmatter this loop
# already has in hand for every project, live or done, so it needs no extra parse
# and no directory walk of its own — `deliverables/` is never listed from disk here
# (that is exactly the filesystem walk task-007 rejected; see its task doc).
# Trusting the stamp's shape is not this file's job either: closeout verifies each
# path exists before writing it, but a human can still hand-edit project.md, so
# build-board.sh's bundle_deliverable() requires every entry to match one whole
# `/projects/<slug>/deliverables/<segment>[/<segment>…]` shape before it can render —
# the same "the writer already restricts what it collects; the board does not trust it
# to have done so" rule href() applies to a PR URL's scheme.
#
# THE TRAILING-COMMENT STRIP LIVES HERE, at this one key and nowhere else — and it is
# about FIDELITY, not safety: what keeps a bad value off the published page is that
# whole-value shape check, which drops anything a strip left comment-shaped. SCHEMA.md
# documents this key WITH a trailing `# comment` on the same line, so without a strip
# the documented form loses its own deliverable — the panel is simply missing an entry
# a human stamped.
#
# Safe at this key and not in list_region() because these entries are bare paths, never
# prose. THE PROPERTY THE CUT MUST HOLD, stated as the only thing that can settle it:
# THE CUT REMOVES EXACTLY THE SPAN A YAML PARSER READS AS A COMMENT — no more, so a
# clean sibling entry can never go with it, and no less, so no comment text can be
# fabricated into a path. Earlier rounds each stated a weaker proxy for this and each
# proxy had a hole, because a proxy is checked by argument and this is checked against
# a parser. Two rules are all YAML needs here, and the scan below is exactly them:
#   · a `#` opens a comment only when it is preceded by whitespace AND is not inside a
#     QUOTED scalar. Inside quotes `#` is an ordinary character, which is what
#     `[ "…/a #1.md", "…/b.md" ]` turns on: YAML reads two entries there, so a cut at
#     that `#` both fabricates `…/a` and deletes the clean `…/b.md`;
#   · in the flow (inline) form the sequence ENDS at the first UNQUOTED `]`, so a
#     comment can only begin after one. `[ …/a] #1.md, …/b.md ]` is therefore ONE
#     entry, `…/a`, and everything from ` #1.md` on is comment — the reason this is not
#     a "lost sibling" but the parser's own reading, and `…/b.md` must NOT render.
#     A quote only opens a scalar where a scalar may START — FOUR positions, which is
#     what `fresh` below is set from: line start, after whitespace, after `[`, after
#     `,`. So an apostrophe inside a plain path is not a quote. BOTH of YAML's escapes
#     are needed to find where a scalar ENDS, and there is exactly one per quote style:
#     `\"` does not close a double-quoted scalar, and `''` does not close a single-quoted
#     one — it IS an apostrophe. Handle only the first and
#     `[ '…/o''brien[draft].md #2', …/clean.md ]` is cut INSIDE one atom: it fabricates
#     `…/o''brien[draft].md`, and it deletes `…/clean.md`, which is an entry YAML really
#     does return. A block entry line has no terminator to wait for: its siblings are on
#     other lines, so the first unquoted whitespace-`#` on it is a comment.
# Anything the cut declines to remove stays exactly as written, and the render-time
# shape check drops whichever fragments the comma-split makes of it — a visible drop,
# never a fabricated path.
deliverable_path_entries() { # <frontmatter>
  list_entries_from_region "$(list_region "$1" deliverable_paths | awk '
    # One left-to-right pass. CCOL = where a comment begins, TCOL = the flow
    # terminator, OPEN = the line ended inside a quoted scalar; 0 = absent. CCOL
    # returns early, so TCOL is set only by a `]` that precedes the comment — which
    # is the whole condition the inline form needs. `noq` ignores quoting entirely.
    # Testing ONE CHARACTER with a regex is a locale trap, and it cost the whole key:
    # this awk is byte-oriented, so substr() returns one BYTE of a multi-byte character
    # and `~ /[[:space:]]/` on that byte aborts the program with "towc: multibyte
    # conversion failure" — so a legitimately stamped `Übersicht.md` did not merely fail
    # to render, it took every sibling deliverable with it. index() compares bytes and
    # cannot fail. YAML separation space is space and tab; the line breaks are in the set
    # only because a CRLF file leaves a `\r` on the line.
    function ws(x) { return index(" \t\r\n", x) > 0 }
    function scan(s, noq,   i, c, q, fresh, n) {
      CCOL = 0; TCOL = 0; OPEN = 0; q = ""; fresh = 1; n = length(s)
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (q != "") {
          if (q == "\"" && c == "\\") i++
          else if (c == q && q == "'\''" && substr(s, i + 1, 1) == "'\''") i++
          else if (c == q) q = ""
          continue
        }
        if (!noq && fresh && (c == "\"" || c == "'\''")) { q = c; fresh = 0; continue }
        if (c == "#" && i > 1 && ws(substr(s, i - 1, 1))) { CCOL = i; return }
        if (c == "]" && TCOL == 0) TCOL = i
        fresh = (ws(c) || c == "," || c == "[")
      }
      OPEN = (q != "")
    }
    {
      scan($0, 0)
      # A quoted scalar left OPEN is not valid YAML at all — Psych refuses the
      # document — so there is no parser reading to be faithful to, and quote state
      # has nothing to say. Fall back to the quote-blind scan (what this cut did
      # before it was quote-aware) rather than dropping a path a human can still
      # read: an unterminated scalar already swallows the rest of the line, so the
      # fallback cannot cost an entry any parser would have returned.
      if (OPEN) scan($0, 1)
      if (CCOL > 0 && ($0 ~ /^[[:space:]]*-/ || TCOL > 0)) $0 = substr($0, 1, CCOL - 1)
      print
    }
  ')"
}

# How many advisor concerns are still untriaged. A COUNT, never the text: unlike
# `open_questions` this is not a human gate at all — it is the loop's own inbox — so
# the board shows it as information, not as something demanding attention. It gets no
# awaiting verb for exactly that reason.
advisor_note_count() { # <frontmatter>
  local n
  n="$(yaml_list_entries "$1" advisor_notes | grep -c . || true)"
  if [[ "${n:-0}" -gt 0 ]]; then printf '%s' "$n"
  # Non-empty but nothing parsed: report 1 rather than 0. The board only ever says
  # "there is something here", so an honest floor beats a silent zero.
  elif list_filled "$1" advisor_notes; then printf '1'
  else printf '0'; fi
}

# ONE stanza builder, and it is not tidiness. The project loop has TWO exits — the
# done-project skip and the normal path — so a field added to one and not the other
# renders a retained project differently from a live one, on a page nobody diffs. It
# reads the loop's own variables and takes only what differs between the two.
#
# `deliverable_paths` is read directly off `$p_deliverable_paths_json` rather than
# taken as a positional argument like `$4`/`$5`: it is parsed from the frontmatter
# BOTH exits already have in hand, before the loop forks on `$p_status`, so — unlike
# the phase/task JSON — it never differs between the two call sites and adding a
# parameter for it would say otherwise.
project_stanza() { # <awaiting_close> <ph_done> <ph_total> <phases_json> <tasks_json>
  printf '%s' "
    {
      \"slug\": $(jstr "$slug"),
      \"title\": $(jstr "$p_title"),
      \"description\": $(jstr "$p_desc"),
      \"kind\": $(jstr "$p_kind"),
      \"status\": $(jstr "$p_status"),
      \"autonomy\": $(jstr "$p_autonomy"),
      \"owner\": $(jstr "$p_owner"),
      \"awaiting_close\": $1,
      \"phase_progress\": {\"done\": $2, \"total\": $3},
      \"phases\": [$4],
      \"tasks\": [$5],
      \"deliverable_paths\": [$p_deliverable_paths_json]
    }"
}

# ---------------------------------------------------------------- assembly
tasks_total=0
awaiting_total=0
projects_json=""
projects_n=0

# `find | sort` rather than a glob, so an instance with no projects/ dir is a clean
# empty snapshot instead of a literal `projects/*/project.md` path.
PROJECT_FILES="$(find ./projects -mindepth 2 -maxdepth 2 -name 'project.md' 2>/dev/null | sort || true)"

while IFS= read -r pfile; do
  [[ -n "$pfile" ]] || continue
  pdir="$(dirname "$pfile")"
  slug="$(basename "$pdir")"
  pfm=""; if ! pfm="$(frontmatter "$pfile" 2>/dev/null)"; then pfm=""; fi
  [[ -n "$pfm" ]] || continue          # unreadable frontmatter: skip, don't guess

  p_title="$(fmfield "$pfm" title)"; [[ -n "$p_title" ]] || p_title="$slug"
  p_desc="$(fmfield "$pfm" description)"
  p_kind="$(fmenum "$pfm" kind)";      [[ -n "$p_kind" ]] || p_kind="build"
  p_status="$(fmenum "$pfm" status)"
  p_autonomy="$(fmenum "$pfm" autonomy)"; [[ -n "$p_autonomy" ]] || p_autonomy="gated"
  # Identity, carried on purpose — see the reversal in the header. Verbatim and
  # unresolved: `defaultOwner` is the board's to apply, not this file's.
  p_owner="$(fmfield "$pfm" owner)"
  # Same frontmatter, same cost as every other project field above — read here so
  # BOTH exits below carry it, not just the done one. A live project rarely has the
  # key at all (closeout is what stamps it), so this is `[]` for almost every
  # project on the board and costs nothing extra to compute.
  p_deliverable_paths_json=""
  while IFS= read -r dp; do
    [[ -n "$dp" ]] || continue
    [[ -n "$p_deliverable_paths_json" ]] && p_deliverable_paths_json="$p_deliverable_paths_json, "
    p_deliverable_paths_json="$p_deliverable_paths_json$(jstr "$dp")"
  done <<< "$(deliverable_path_entries "$pfm")"

  # ---- a DONE project is read no further than this line.
  #
  # A finished project used to be deleted at closeout, and the stated reason was never
  # disk — it was that "a done folder left live would only cost context on every PM
  # tick" (SCHEMA.md). `retain: true` keeps the folder, so that cost has to go
  # somewhere, and here is where it goes: the project frontmatter is ALREADY parsed
  # above, before anything walks `phases/` or `tasks/`, so skipping here costs exactly
  # one frontmatter parse per retained project and opens `tasks/` zero times. That is
  # the trade that makes retention affordable; if this `continue` ever moves below the
  # task loop it silently gives the cost back.
  #
  # The project STANZA is still emitted, from the frontmatter in hand — the skip is of
  # the phase and task WALKS, not of the project. A retained project is a reference card
  # on the board (its deliverables are listed from `deliverable_paths:` in project.md),
  # and a project omitted from the snapshot entirely could not be rendered at all.
  # `awaiting_close` is false by definition here: a done project is already closed.
  if [[ "$p_status" == "done" ]]; then
    projects_n=$((projects_n+1))
    projects_json="$projects_json${projects_json:+,}$(project_stanza false 0 0 '' '')"
    continue
  fi

  # A paused project's verbs agree with AWAITING.md: `merge` survives, nothing else does.
  # Exit 1 is the only "paused"; exit 2 cannot answer and must not hide work.
  p_held=0; prc=0
  bash "$(dirname "${BASH_SOURCE[0]:-$0}")/project-paused.sh" "$pfile" >/dev/null 2>&1 || prc=$?
  [[ $prc -eq 1 ]] && p_held=1

  # ---- phases
  phases_json=""; ph_total=0; ph_done=0
  while IFS= read -r phfile; do
    [[ -n "$phfile" ]] || continue
    phfm=""; if ! phfm="$(frontmatter "$phfile" 2>/dev/null)"; then phfm=""; fi
    [[ -n "$phfm" ]] || continue
    ph_title="$(fmfield "$phfm" title)"; [[ -n "$ph_title" ]] || ph_title="$(basename "$phfile" .md)"
    ph_status="$(fmenum "$phfm" status)"
    ph_order="$(fmenum "$phfm" order)"
    case "$ph_order" in ''|*[!0-9]*) ph_order=0 ;; esac
    ph_total=$((ph_total+1))
    [[ "$ph_status" == "done" ]] && ph_done=$((ph_done+1))
    phases_json="$phases_json${phases_json:+,}
      {\"file\": $(jstr "$(basename "$phfile")"), \"order\": $ph_order, \"title\": $(jstr "$ph_title"), \"status\": $(jstr "$ph_status")}"
  done <<EOF
$(find "$pdir/phases" -maxdepth 1 -name '*.md' 2>/dev/null | grep -vE '/(index|log)\.md$' | sort || true)
EOF

  # ---- tasks
  tasks_json=""; t_count=0; t_terminal=0
  while IFS= read -r tfile; do
    [[ -n "$tfile" ]] || continue
    tfm=""; if ! tfm="$(frontmatter "$tfile" 2>/dev/null)"; then tfm=""; fi
    [[ -n "$tfm" ]] || continue
    t_id="$(basename "$tfile" .md)"
    t_title="$(fmfield "$tfm" title)"; [[ -n "$t_title" ]] || t_title="$t_id"
    t_status="$(fmenum "$tfm" status)"
    t_kind="$(fmenum "$tfm" kind)"; [[ -n "$t_kind" ]] || t_kind="$p_kind"
    t_assignee="$(fmenum "$tfm" assignee)"
    # The tick's own mergeability read, persisted by `review-clearance.sh --record`.
    # Absent is not MERGEABLE: this file is offline by contract, so the only honest answer
    # about a PR nobody has asked the host about is "not known to be mergeable".
    t_mergeable="$(fmenum "$tfm" pr_mergeable)"
    case "$t_mergeable" in MERGEABLE|CONFLICTING) ;; *) t_mergeable="UNKNOWN" ;; esac
    t_phase="$(fmfield "$tfm" phase)"; t_phase="$(basename "$t_phase" 2>/dev/null || true)"
    [[ "$t_phase" == "." ]] && t_phase=""
    oq="$(count_questions "$tfm")"
    # The per-question labels the board builds one control per. A `-` line is a
    # question that names no number, and it becomes `""` — present, so it is still a
    # question with a handle of its own, and empty, so no number is fabricated for it.
    # The array is emitted even when it is empty: a reader that finds the key absent is
    # reading a snapshot older than 2026-08-31 and correctly falls back to the count.
    ql_json=""
    while IFS= read -r ql; do
      [[ -n "$ql" ]] || continue
      [[ -n "$ql_json" ]] && ql_json="$ql_json, "
      case "$ql" in
        -) ql_json="$ql_json\"\"" ;;
        *) ql_json="$ql_json$(jstr "$ql")" ;;
      esac
    done <<EOF
$(question_labels "$tfm")
EOF

    # PR URLs only — never the surrounding `pr:` text, whatever else it holds.
    prs_json=""
    while IFS= read -r url; do
      [[ -n "$url" ]] || continue
      num="${url##*/}"
      case "$num" in ''|*[!0-9]*) continue ;; esac
      repo="${url%/pull/*}"; repo="${repo#*://}"; repo="${repo#*/}"
      prs_json="$prs_json${prs_json:+, }{\"repo\": $(jstr "$repo"), \"number\": $num, \"url\": $(jstr "$url")}"
    done <<EOF
$(list_region "$tfm" pr | grep -oE 'https?://[A-Za-z0-9._~:/?#@!$&*+=%-]+/pull/[0-9]+' | sort -u || true)
EOF

    # in_flight = a role agent is working it. `in-review` is NOT in flight: the agent
    # has handed over and the PR is waiting on a reviewer or a merge — UNLESS the host
    # reported it CONFLICTING, which is a rebase round, not a queue position.
    in_flight=false; [[ "$t_status" == "in-progress" ]] && in_flight=true
    [[ "$t_status" == "in-review" && "$t_mergeable" == "CONFLICTING" ]] && in_flight=true

    # depends_on -> a JSON array of IDs. jstr() does the escaping, as everywhere else.
    an="$(advisor_note_count "$tfm")"

    dep_json=""
    while IFS= read -r dep; do
      [[ -n "$dep" ]] || continue
      [[ -n "$dep_json" ]] && dep_json="$dep_json, "
      dep_json="$dep_json$(jstr "$dep")"
    done <<< "$(depends_ids "$tfm")"

    # The awaiting verb, and ONLY the verb — mirrors session-banner.sh's glyph set
    # (✅ approve · ❓ answer · 🔀 merge · ⛔ unblock · 🏁 close) minus the reason text.
    # A `draft` with no acceptance_criteria is still being refined, so it awaits
    # nothing yet; with questions open it awaits an answer, not an approval.
    awaiting=""
    case "$t_status" in
      draft)
        if [[ "$oq" != 0 ]]; then awaiting="answer"
        elif acceptance_criteria_filled "$tfm"; then awaiting="approve"; fi ;;
      # THE MERGE VERB REQUIRES MERGEABLE. On 2026-09-13 three CONFLICTING PRs were
      # presented as merge rows; `status: in-review` plus a PR link was the whole test.
      in-review) [[ -n "$prs_json" && "$t_mergeable" == "MERGEABLE" ]] && awaiting="merge" ;;
      blocked)   awaiting="unblock" ;;
    esac
    [[ $p_held -eq 1 && "$awaiting" != merge ]] && awaiting=""
    [[ -n "$awaiting" ]] && awaiting_total=$((awaiting_total+1))

    case "$t_status" in done|cancelled) t_terminal=$((t_terminal+1)) ;; esac
    t_count=$((t_count+1)); tasks_total=$((tasks_total+1))

    tasks_json="$tasks_json${tasks_json:+,}
      {\"id\": $(jstr "$t_id"), \"title\": $(jstr "$t_title"), \"kind\": $(jstr "$t_kind"), \"status\": $(jstr "$t_status"), \"assignee\": $(jstr "$t_assignee"), \"phase\": $(jstr "$t_phase"), \"in_flight\": $in_flight, \"pr_mergeable\": $(jstr "$t_mergeable"), \"awaiting\": $(jstr "$awaiting"), \"open_questions\": $oq, \"open_question_ids\": [$ql_json], \"advisor_notes\": $an, \"depends_on\": [$dep_json], \"prs\": [$prs_json]}"
  done <<EOF
$(find "$pdir/tasks" -maxdepth 1 -name '*.md' 2>/dev/null | grep -vE '/(index|log)\.md$' | sort || true)
EOF

  # A close proposal, same rule as the PM's step 6: every task terminal, at least
  # one task, project not already done. Never an action — the board only shows it.
  awaiting_close=false
  if [[ $p_held -eq 0 && $t_count -gt 0 && $t_terminal -eq $t_count && "$p_status" != "done" ]]; then
    awaiting_close=true; awaiting_total=$((awaiting_total+1))
  fi

  projects_n=$((projects_n+1))
  projects_json="$projects_json${projects_json:+,}$(project_stanza \
    "$awaiting_close" "$ph_done" "$ph_total" "$phases_json" "$tasks_json")"
done <<EOF
$PROJECT_FILES
EOF

# ---------------------------------------------------------------- closed projects
# projects/CLOSED.md — tracked, written by close-project-folder.sh, one `## <slug>`
# stanza per closed project that had deliverables. The key prefixes below ARE the parse
# contract; a hand-written variation simply does not parse, which is the intended
# failure for a file whose own header says not to hand-edit it.
closed_records() { # -> TSV: P slug | C date | S sha | O outcome | D path url
  awk '
    BEGIN { SEP = " — " }
    /^## / { print "P\t" substr($0, 4); next }
    /^- closed: /  { print "C\t" substr($0, 11); next }
    /^- pinned: /  { print "S\t" substr($0, 11); next }
    /^- outcome: / { print "O\t" substr($0, 12); next }
    /^- deliverable: / {
      # `length(SEP)` and never a literal 5: the em dash is multi-byte, and index()/
      # substr() count BYTES on a BSD/mawk awk and CHARACTERS on a gawk in a UTF-8
      # locale — a hardcoded offset ate `https://` on one of them.
      s = substr($0, 16); q = index(s, SEP)
      if (q > 0) { p = substr(s, 1, q - 1); u = substr(s, q + length(SEP)) } else { p = s; u = "" }
      gsub(/`/, "", p); sub(/^[ \t]+/, "", u); sub(/[ \t]+$/, "", u)
      print "D\t" p "\t" u
    }
  ' projects/CLOSED.md
}

closed_json=""
c_slug=""; c_date=""; c_sha=""; c_out=""; c_dlv=""
# Emitted only for a stanza that has at least one deliverable — CLOSED.md is an index of
# things to come back to, and log.md already records every close.
flush_closed() {
  [[ -n "$c_slug" && -n "$c_dlv" ]] || return 0
  [[ -n "$closed_json" ]] && closed_json="$closed_json,"
  closed_json="$closed_json
    {\"slug\": $(jstr "$c_slug"), \"closed\": $(jstr "$c_date"), \"sha\": $(jstr "$c_sha"), \"outcome\": $(jstr "$c_out"), \"deliverables\": [$c_dlv]}"
}
if [[ -f projects/CLOSED.md ]]; then
  while IFS=$'\t' read -r kind a b; do
    case "$kind" in
      P) flush_closed; c_slug="$a"; c_date=""; c_sha=""; c_out=""; c_dlv="" ;;
      C) c_date="$a" ;;
      S) c_sha="$a" ;;
      O) c_out="$a" ;;
      D) [[ -n "$c_dlv" ]] && c_dlv="$c_dlv, "
         c_dlv="$c_dlv{\"path\": $(jstr "$a"), \"url\": $(jstr "$b")}" ;;
    esac
  done <<EOF
$(closed_records)
EOF
  flush_closed
fi
# Absent or empty ⇒ the key is left OUT, never written as `[]`: a reader must be able to
# tell "this instance has no closed projects" from "this snapshot predates the key".
CLOSED_BLOCK=""
if [[ -n "$closed_json" ]]; then CLOSED_BLOCK="\"closed\": [$closed_json],
  "; fi

# ---------------------------------------------------------------- write
# Temp file BESIDE the target, never $TMPDIR: a cross-filesystem `mv` degrades to
# copy-and-remove, where an interruption leaves a half-written snapshot that the
# board would then report as malformed. Same reasoning as migrate-bundle.sh.
tmp="$OUT.tmp.$$"
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<JSON
{
  "_schema": "ai-bridge board snapshot v1",
  "_sensitivity": "Derived and gitignored. AS SENSITIVE AS THE TASK DOCUMENTS IT COMES FROM: titles are human-written free text. No customer PII belongs in a task title, and none belongs here. Delete this file to take this instance off the board for good.",
  "_carries": "project title/description/kind/status/autonomy and project owner (a GitHub USERNAME, carried deliberately so a board can separate this clone's projects from the other owner's -- see write-snapshot.sh's header and /knowledge/findings/board-owner-identity-named-not-redacted.md); deliverable_paths verbatim from project.md (closeout-stamped, shape-checked at RENDER time by build-board.sh, not by this file); phase title/order/status; task id/title/kind/status/assignee-ROLE/in_flight/pr_mergeable (MERGEABLE|CONFLICTING|UNKNOWN, the tick's last host read)/awaiting-VERB/open-question COUNT/open_question_ids (one Qn LABEL per open question -- the letter Q plus digits, or empty for a question that names no number; never a byte of the question TEXT)/advisor_notes COUNT/depends_on IDs/PR links. Never: task descriptions, document bodies, question or blocker TEXT, author EMAIL.",
  "group": $(jstr "$GROUP"),
  "generated_at": $(jstr "$NOW"),
  "counts": {"projects": $projects_n, "tasks": $tasks_total, "awaiting": $awaiting_total},
  ${CLOSED_BLOCK}"projects": [$projects_json]
}
JSON

mv "$tmp" "$OUT"
trap - EXIT

# Verify the write landed rather than claiming it did — migrate-bundle.sh once
# printed FIXED for a write it never made, on a real bundle.
[[ -s "$OUT" ]] || { echo "write-snapshot: FAILED — $OUT is empty after the write." >&2; exit 1; }
[[ $QUIET -eq 1 ]] || printf 'write-snapshot: %s — %d project(s), %d task(s), %d awaiting.\n' \
  "$OUT" "$projects_n" "$tasks_total" "$awaiting_total"
exit 0
