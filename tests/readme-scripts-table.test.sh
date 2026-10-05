#!/usr/bin/env bash
#
# readme-scripts-table.test.sh — README.md's `## Scripts` section and `plugin/scripts/`
# account for each other, in both directions.
#
# WHY. A hand-maintained table of scripts drifts the moment a PR adds one, silently, and
# nothing read it. Measured 2026-09-01 on `origin/main` (55088f8): the section carried
# **19 rows against 26 scripts** — `welcome.sh`, `control.sh`, `pr-body-clearance.sh`,
# `pr-comment-clearance.sh`, `reclaim-worktree.sh`, `resolve-config.sh` and
# `resolve-max-agents.sh` were in no row and named nowhere else in the README. Four of the
# seven predate the PR that was blamed for the drift, so the table had been wrong for far
# longer than anyone thought — which is exactly what a table with no reader looks like.
#
# THE CONTRACT THIS PINS IS "EVERY SCRIPT IS ACCOUNTED FOR", NOT "EVERY SCRIPT IS A USER
# COMMAND". Some of what ships in `plugin/scripts/` is internal plumbing a reader should
# not be told to run (`resolve-config.sh`, `resolve-max-agents.sh`, `welcome.sh`, which
# backs the `/loopd:welcome` command). The README therefore carries a second, explicitly
# labelled **Internal helpers** table under the same heading, and this file scans the whole
# `## Scripts` SECTION rather than one table — so a helper is documented as a helper and
# still counts as accounted for. A future script may go in either table; it may not go in
# neither.
#
# WHY NOT AN EXTENSION OF `scripts-executable.test.sh`, WHICH ALREADY ENUMERATES THE SAME
# DIRECTORY. That file is ~494 lines, is scope-bounded by its own header to committed
# executable BITS, and pins `EXPECTED_ASSERTIONS` under an annotated change history that is
# a known merge magnet (knowledge/findings/a-running-counter-annotated-by-a-comment-history-
# is-a-merge-magnet.md). Documentation correspondence is a different concern, and this
# suite's grain is one small file per concern. Adding a second concern to that file would
# make every README edit collide with its counter.
#
# THE SECTION SELECTOR IS ASSERTED UNIQUE, ON PURPOSE. Selecting a documentation region by
# its first matching heading is the shape that already cost this codebase two false-red
# assertions (knowledge/findings/a-new-bullet-citing-a-script-retargets-a-first-match-
# selector.md): a first match silently retargets when a second one appears. So the count of
# `## Scripts` headings is asserted to be exactly 1 before anything is read out of it.
#
# NON-VACUOUS BY CONSTRUCTION. A check that only ever sees a correct README proves nothing
# — it would pass identically on a table nobody had fixed. So the same predicates run on
# THREE inputs: the real README (expected clean), a copy with one row deleted (must report
# that script as undocumented), and a copy with a row naming a script that does not exist
# (must report that row as stale). Both mutants are the two directions of drift.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
README="$REPO/README.md"
SCRIPTS="$REPO/plugin/scripts"
[ -f "$README" ] || { echo "readme-scripts-table.test: missing $README" >&2; exit 2; }
[ -d "$SCRIPTS" ] || { echo "readme-scripts-table.test: missing $SCRIPTS" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/readme-scripts-table.XXXXXX")" \
  || { echo "readme-scripts-table.test: could not create a temp dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-56s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-56s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# Every `*.sh` that ships in plugin/scripts/, one per line, sorted.
shipped() { find "$SCRIPTS" -maxdepth 1 -name '*.sh' -exec basename {} \; | sort; }

# Every script named in the leading cell of a row of ANY table inside the `## Scripts`
# section — the section runs from its own heading to the next `## ` heading.
documented() { # <readme>
  awk '/^## Scripts$/ { f=1; next } f && /^## / { exit } f' "$1" \
    | grep -oE '^\| `[A-Za-z0-9._-]+\.sh`' | tr -d '|` ' | sort -u
}

# The two directions of drift, as lines. Empty output is clean.
undocumented() { comm -23 <(shipped) <(documented "$1"); }   # ships, no row
stale_rows()   { comm -13 <(shipped) <(documented "$1"); }   # row, no script

echo
echo "== 1. the section selector is unique =="
ok "exactly one '## Scripts' heading in the README" \
   "$(grep -c '^## Scripts$' "$README" | tr -d ' ')" 1
ok "…and it yields rows"      "$([ -n "$(documented "$README")" ] && echo yes || echo no)" yes
ok "…and the directory ships scripts" "$([ -n "$(shipped)" ] && echo yes || echo no)" yes

echo
echo "== 2. the real README accounts for every script, and names no ghost =="
ok "no script ships undocumented ($(undocumented "$README" | tr '\n' ' '))" \
   "$(undocumented "$README" | wc -l | tr -d ' ')" 0
ok "no row names a script that does not exist ($(stale_rows "$README" | tr '\n' ' '))" \
   "$(stale_rows "$README" | wc -l | tr -d ' ')" 0

echo
echo "== 3. both mutants go RED — the check discriminates =="
# Delete the row for a script that really ships. Chosen at runtime rather than hard-coded,
# so a rename cannot turn this half of the harness into a no-op that still passes.
victim="$(head -n1 <<<"$(documented "$README")")"
ok "picked a documented script to remove" "$([ -n "$victim" ] && echo yes || echo no)" yes
grep -v "^| \`$victim\`" "$README" > "$TMP/missing-row.md"
ok "mutant A: the removed script is reported undocumented" \
   "$(undocumented "$TMP/missing-row.md" | grep -cx "$victim" | tr -d ' ')" 1

# A row naming a script that does not ship. Appended inside the section, not after it.
awk '/^## Troubleshooting$/ && !d { print "| `no-such-script.sh` | a ghost row | no |"; print ""; d=1 } { print }' \
  "$README" > "$TMP/ghost-row.md"
ok "mutant B: the ghost row is reported stale" \
   "$(stale_rows "$TMP/ghost-row.md" | grep -cx 'no-such-script.sh' | tr -d ' ')" 1
ok "…and mutant B still reports nothing undocumented" \
   "$(undocumented "$TMP/ghost-row.md" | wc -l | tr -d ' ')" 0

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
