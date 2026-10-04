#!/usr/bin/env bash
#
# close-project-folder.test.sh — the folder half of closeout, which is the one step of
# it that DELETES FILES.
#
# WHAT IS ACTUALLY AT RISK HERE, and why the assertions are shaped the way they are:
#
#   · A PRUNE THAT IS TOO WIDE IS UNRECOVERABLE for anything not yet committed, and the
#     obvious spelling of "drop the screenshots" — an extension sweep — eats
#     `deliverables/`, which is where a research project's .pdf/.html/.png OUTPUT
#     lives. So the fixture plants a deliverable of every pruned extension, a sibling
#     project, and a file at the bundle root, and asserts every one of them survives.
#   · A PRUNE THAT IS TOO NARROW IS INVISIBLE. `tmp/` in the real project this came from
#     held employee records; a rule that silently matched nothing would leave them in a
#     folder now kept forever. So the negative assertions are paired with positive ones,
#     and with a control that shows the same files ARE removed when they should be.
#   · `sources/**/*.md` ARE CITED BY `index.md` ("evidence captured in sources/
#     02/03/05"), and a retained project exists to be read. The citations are therefore
#     RESOLVED against the pruned tree here, not assumed to still work.
#   · `deliverable_paths:` IS AN INTERFACE. The board reads it instead of walking
#     `tasks/` (which the done-project skip removed), so every stamped path must resolve
#     to a file that exists, and a declared-but-missing artifact must not be stamped.
#   · NO FILENAME FROM `tmp/` MAY BE PRINTED. The report is what reaches a terminal, a
#     transcript and possibly the log entry, and a filename is content — the bundle's
#     no-PII rule covers it. Asserted on the real output, not on the header comment.
#
# THE FIXTURE IS A GIT REPO because the no-retain path is `git rm -r`, and "the folder
# is gone" is only true if the removal is staged rather than left as an untracked mess.
#
# assert() follows the convention of the other harnesses here: 0 is a PASS.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"
SCRIPT="$TPL/plugin/scripts/close-project-folder.sh"
[[ -f "$SCRIPT" ]] || { echo "close-project-folder.test: missing $SCRIPT" >&2; exit 2; }

# TWO STEPS, NEVER ONE — the one-expression form is DESTRUCTIVE when $TMPDIR names a
# directory that does not exist: `mktemp -d` fails, `cd ""` succeeds without moving, and
# the trap below then deletes this checkout. See tests/harness-temp-safety.test.sh.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/close-project-folder.XXXXXX")" || {
  echo "close-project-folder.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2
  exit 2; }
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if()  { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
no_if()   { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
has()     { grep -qF <<<"$2" -- "$1" && echo 0 || echo 1; }
hasnt()   { grep -qF <<<"$2" -- "$1" && echo 1 || echo 0; }
eq()      { [[ "$1" == "$2" ]] && echo 0 || echo 1; }
exists()  { [[ -e "$1" ]] && echo 0 || echo 1; }
gone()    { [[ -e "$1" ]] && echo 1 || echo 0; }

# A filename that must never be printed. In the project this rule came from, `tmp/` held
# roster and seat exports — employee records — and the report is the thing that escapes
# into terminals and log entries.
PII_NAME="roster-export-2026.csv"

# No global excludes: a machine whose ~/.gitignore lists .DS_Store would leave the
# fixture's copies untracked, and the folder would survive `git rm -r` on that machine only.
git_c() { git -c core.excludesFile=/dev/null -c user.name=fixture -c user.email=fixture@example.com -c commit.gpgsign=false "$@"; }

# ---------------------------------------------------------------- fixture
# Rebuilt from scratch for each scenario, because every scenario deletes something.
new_instance() { # <dir>
  local root="$1" slug="$2" retain="$3"
  rm -rf "$root"
  mkdir -p "$root/projects/$slug/tasks" \
           "$root/projects/$slug/deliverables" \
           "$root/projects/$slug/sources/sub" \
           "$root/projects/$slug/tmp/nested" \
           "$root/projects/$slug/TEMP" \
           "$root/projects/sibling/sources" \
           "$root/knowledge/findings"
  : > "$root/SCHEMA.md"
  echo '{ "org": "fixture-org" }' > "$root/instance.config.json"
  echo 'root file' > "$root/log.md"
  # A file at the bundle root and a whole sibling project, both carrying the extensions
  # the prune removes INSIDE the target project. Nothing outside `projects/<slug>/` is
  # in scope, and this is how that is checked rather than assumed.
  : > "$root/screenshot-at-the-root.png"
  : > "$root/projects/sibling/sources/keep-me.png"
  : > "$root/projects/sibling/.DS_Store"

  cat > "$root/projects/$slug/project.md" <<PRJ
---
type: Project
title: AI adoption research
description: finished research, kept as a reference surface
kind: research
${retain}status: done
timestamp: 2026-08-26T00:00:00Z
---
# Context
Closed 2026-08-26.
PRJ

  # Two tasks declaring artifacts, in BOTH YAML list forms — the inline one and a block
  # sequence — because an instance may legitimately write either and a stamp that reads
  # only one silently under-reports the project's deliverables.
  cat > "$root/projects/$slug/tasks/task-001.md" <<TSK
---
type: Task
title: Build the mandate deck
kind: research
status: done
artifacts: [ /projects/$slug/deliverables/deck.md, /projects/$slug/deliverables/deck.html ]
timestamp: 2026-08-26T00:00:00Z
---
TSK
  cat > "$root/projects/$slug/tasks/task-002.md" <<TSK
---
type: Task
title: Draw the cover
kind: research
status: done
artifacts:
  - /projects/$slug/deliverables/cover.png
  - /projects/$slug/deliverables/never-written.pdf
timestamp: 2026-08-26T00:00:00Z
---
TSK
  cat > "$root/projects/$slug/tasks/task-003.md" <<TSK
---
type: Task
title: Superseded outline
kind: research
status: cancelled
timestamp: 2026-08-26T00:00:00Z
---
TSK

  # The deliverables: exactly the extensions an extension sweep would eat.
  echo 'deck' > "$root/projects/$slug/deliverables/deck.md"
  echo '<html>' > "$root/projects/$slug/deliverables/deck.html"
  echo 'PNG' > "$root/projects/$slug/deliverables/cover.png"
  echo 'PDF' > "$root/projects/$slug/deliverables/handout.pdf"
  : > "$root/projects/$slug/deliverables/.DS_Store"

  # Evidence: markdown extracts stay, the screenshots they came from go.
  echo 'extract 02' > "$root/projects/$slug/sources/02-extract.md"
  echo 'extract 03' > "$root/projects/$slug/sources/03-extract.md"
  echo 'extract 05' > "$root/projects/$slug/sources/sub/05-extract.MD"
  : > "$root/projects/$slug/sources/02-screenshot.jpg"
  : > "$root/projects/$slug/sources/03-screenshot.png"
  : > "$root/projects/$slug/sources/seats.csv"

  # The front door, citing the three extracts by path. These citations must still
  # resolve after the prune — that is what makes a retained project worth keeping.
  cat > "$root/projects/$slug/index.md" <<IDX
# AI adoption research

- [Build the mandate deck](tasks/task-001.md) → [deck](deliverables/deck.md)
- evidence captured in sources/ 02/03/05:
  - [02](sources/02-extract.md)
  - [03](sources/03-extract.md)
  - [05](sources/sub/05-extract.MD)
IDX
  echo '# project log' > "$root/projects/$slug/log.md"

  # Working files. NEVER read, only counted — see the PII assertions below.
  : > "$root/projects/$slug/tmp/$PII_NAME"
  : > "$root/projects/$slug/tmp/nested/seats.png"
  : > "$root/projects/$slug/TEMP/scratch.txt"
  : > "$root/projects/$slug/.DS_Store"

  ( cd "$root" && git init -q . && git_c add -A . >/dev/null 2>&1 && \
    git_c commit -qm "fixture" >/dev/null 2>&1 )
}

run() { # <root> <args...> -> prints output, sets RC
  local root="$1"; shift
  RC=0
  OUT="$( cd "$root" && bash "$SCRIPT" "$@" 2>&1 )" || RC=$?
}

# ---------------------------------------------------------------- refusals
echo "== refusals: nothing destructive happens on a bad call =="
ROOT="$TMP/a"
new_instance "$ROOT" adoption "retain: true"$'\n'

run "$ROOT" adoption --apply
assert "a well-formed call succeeds"                  "$(eq "$RC" 0)"

new_instance "$ROOT" adoption "retain: true"$'\n'
mkdir -p "$TMP/stranger"
RC=0; OUT="$( cd "$TMP/stranger" && bash "$SCRIPT" adoption --apply 2>&1 )" || RC=$?
assert "outside an instance root -> exits 2"          "$(eq "$RC" 2)"
assert "…and names what it expected to find"          "$(has 'instance.config.json' "$OUT")"

run "$ROOT" ../../etc --apply
assert "a slug with path separators -> exits 2"       "$(eq "$RC" 2)"
assert "…and says it is not a project slug"           "$(has 'not a project slug' "$OUT")"
assert "…and the project is untouched"                "$(exists "$ROOT/projects/adoption/tmp")"

run "$ROOT" adoption/../adoption --apply
assert "a slug that traverses back into itself -> exits 2" "$(eq "$RC" 2)"

run "$ROOT" no-such-project --apply
assert "an unknown slug -> exits 2"                   "$(eq "$RC" 2)"
assert "…and says there is nothing to close"          "$(has 'nothing to close' "$OUT")"

run "$ROOT" adoption
assert "without --apply it is report-only: exits 0"   "$(eq "$RC" 0)"
assert "…and says nothing changed"                    "$(has 'nothing changed' "$OUT")"
assert "…and tmp/ is still there"                     "$(exists "$ROOT/projects/adoption/tmp")"
assert "…and project.md was NOT stamped"              "$(no_if grep -q '^deliverable_paths:' "$ROOT/projects/adoption/project.md")"
assert "…while still reporting what it would prune"   "$(has 'PRUNE' "$OUT")"

# ---------------------------------------------------------------- retained
echo "== retain: true — the folder stays, frozen =="
new_instance "$ROOT" adoption "retain: true"$'\n'
run "$ROOT" adoption --apply
P="$ROOT/projects/adoption"
assert "exits 0"                                      "$(eq "$RC" 0)"
assert "the folder is KEPT"                           "$(exists "$P")"
assert "…and says so"                                 "$(has 'RETAINED' "$OUT")"

echo "== …and what survives it =="
assert "tasks/ survives in full (3 task docs)"        "$(eq "$(ls "$P/tasks" | wc -l | tr -d ' ')" 3)"
assert "project.md survives"                          "$(exists "$P/project.md")"
assert "index.md survives"                            "$(exists "$P/index.md")"
assert "the project log.md survives"                  "$(exists "$P/log.md")"
assert "deliverables/deck.md survives"                "$(exists "$P/deliverables/deck.md")"
assert "deliverables/deck.html survives (a pruned extension, in the kept dir)" \
                                                      "$(exists "$P/deliverables/deck.html")"
assert "deliverables/cover.png survives"              "$(exists "$P/deliverables/cover.png")"
assert "deliverables/handout.pdf survives"            "$(exists "$P/deliverables/handout.pdf")"
assert "even a .DS_Store INSIDE deliverables/ survives — the subtree is never walked" \
                                                      "$(exists "$P/deliverables/.DS_Store")"
assert "sources/02-extract.md survives"               "$(exists "$P/sources/02-extract.md")"
assert "sources/sub/05-extract.MD survives (case-insensitive .md)" \
                                                      "$(exists "$P/sources/sub/05-extract.MD")"

echo "== …and what does not =="
assert "tmp/ is gone"                                 "$(gone "$P/tmp")"
assert "TEMP/ is gone (the name is matched case-insensitively)" "$(gone "$P/TEMP")"
assert "the project's .DS_Store is gone"              "$(gone "$P/.DS_Store")"
assert "sources/02-screenshot.jpg is gone"            "$(gone "$P/sources/02-screenshot.jpg")"
assert "sources/03-screenshot.png is gone"            "$(gone "$P/sources/03-screenshot.png")"
assert "sources/seats.csv is gone"                    "$(gone "$P/sources/seats.csv")"

echo "== the prune is scoped to this project, by explicit path =="
assert "a .png at the bundle root survives"           "$(exists "$ROOT/screenshot-at-the-root.png")"
assert "a sibling project's sources/*.png survives"   "$(exists "$ROOT/projects/sibling/sources/keep-me.png")"
assert "a sibling project's .DS_Store survives"       "$(exists "$ROOT/projects/sibling/.DS_Store")"
assert "…and the sibling folder itself is untouched"  "$(exists "$ROOT/projects/sibling")"

echo "== index.md's citations still resolve after the prune =="
# Not "the .md files are still there" — the actual links, read out of the actual file
# and tested against the pruned tree. A retained project exists to be read; if its front
# door dangles, retaining it bought nothing.
BROKEN=0
while IFS= read -r target; do
  [[ -n "$target" ]] || continue
  [[ -e "$P/$target" ]] || { BROKEN=$((BROKEN+1)); echo "        dangling: $target"; }
done <<EOF
$(grep -oE '\]\([^)]+\)' "$P/index.md" | sed -e 's/^](//' -e 's/)$//')
EOF
assert "every link in index.md resolves ($BROKEN dangling)" "$(eq "$BROKEN" 0)"
assert "…and index.md still names the evidence it cites"    "$(yes_if grep -q 'sources/ 02/03/05' "$P/index.md")"

echo "== deliverable_paths: the stamp the board reads instead of walking tasks/ =="
STAMP="$(awk '/^deliverable_paths:/ { f = 1; print; next } f && /^  - / { print; next } { f = 0 }' "$P/project.md")"
assert "project.md carries the key"                   "$(has 'deliverable_paths:' "$STAMP")"
assert "…in SCHEMA.md's block form, one quoted path per line" "$(has '  - "/projects/' "$STAMP")"
assert "…with the inline-list task's artifacts"       "$(has '/projects/adoption/deliverables/deck.md' "$STAMP")"
assert "…and the html one"                            "$(has '/projects/adoption/deliverables/deck.html' "$STAMP")"
assert "…and the BLOCK-list task's artifact"          "$(has '/projects/adoption/deliverables/cover.png' "$STAMP")"
assert "…and NOT the one that was never written"      "$(hasnt 'never-written.pdf' "$STAMP")"
assert "…which is reported as a warning instead"      "$(has 'declared artifact does not exist' "$OUT")"
assert "every stamped path is bundle-relative (starts with /projects/)" "$(yes_if python3 - "$STAMP" <<'PY'
import sys
lines = sys.argv[1].splitlines()[1:]
paths = [l.strip()[2:].strip().strip('"') for l in lines]
sys.exit(0 if paths and all(p.startswith("/projects/") for p in paths) else 1)
PY
)"
# THE assertion the board depends on: every stamped path resolves to a file that is
# still there AFTER the prune. A stamp made before a prune that then deleted one of its
# own targets would put a dead button on a published page.
RESOLVED=0; DEAD=0
while IFS= read -r ref; do
  [[ -n "$ref" ]] || continue
  if [[ -f "$ROOT$ref" ]]; then RESOLVED=$((RESOLVED+1)); else DEAD=$((DEAD+1)); echo "        dead: $ref"; fi
done <<EOF
$(printf '%s' "$STAMP" | grep -oE '/projects/[A-Za-z0-9._/-]+')
EOF
assert "all 3 stamped paths resolve to existing files"  "$(eq "$RESOLVED" 3)"
assert "…and none is dead"                              "$(eq "$DEAD" 0)"

echo "== a declared artifact is protected from the prune =="
# A task may declare a deliverable that happens to live under sources/ — a place the
# prune would otherwise take it from. The stamp is computed first and used as a
# keep-set, so the two rules cannot contradict each other.
new_instance "$ROOT" adoption "retain: true"$'\n'
: > "$ROOT/projects/adoption/sources/odd-place.png"
python3 - "$ROOT/projects/adoption/tasks/task-002.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().replace("  - /projects/adoption/deliverables/cover.png",
                           "  - /projects/adoption/deliverables/cover.png\n  - /projects/adoption/sources/odd-place.png")
open(p, "w").write(s)
PY
run "$ROOT" adoption --apply
assert "a sources/ file declared as an artifact is KEPT" "$(exists "$ROOT/projects/adoption/sources/odd-place.png")"
assert "…and the report says why"                        "$(has 'declared deliverable' "$OUT")"
assert "…while its undeclared neighbour still goes"      "$(gone "$ROOT/projects/adoption/sources/02-screenshot.jpg")"

echo "== the prune is reported, and reports no filename out of tmp/ =="
new_instance "$ROOT" adoption "retain: true"$'\n'
run "$ROOT" adoption --apply
assert "the report names the pruned tmp/ directory"     "$(has 'projects/adoption/tmp/' "$OUT")"
assert "…and the pruned TEMP/ directory"                "$(has 'projects/adoption/TEMP/' "$OUT")"
assert "…and offers a log.md fragment naming them"      "$(has 'log.md fragment' "$OUT")"
assert "…which says what was KEPT too"                  "$(has 'kept tasks/' "$OUT")"
assert "…and names the pruned sources/ files"           "$(has 'sources/02-screenshot.jpg' "$OUT")"
# The one thing the report must never contain.
assert "NO filename from inside tmp/ is printed"        "$(hasnt "$PII_NAME" "$OUT")"
assert "…nor the nested one"                            "$(hasnt 'seats.png' "$OUT")"
assert "…the directory is reported by entry COUNT instead" "$(has 'contents not listed' "$OUT")"

echo "== nothing to prune is not an error =="
new_instance "$ROOT" tidy "retain: true"$'\n'
rm -rf "$ROOT/projects/tidy/tmp" "$ROOT/projects/tidy/TEMP" "$ROOT/projects/tidy/.DS_Store"
rm -f "$ROOT/projects/tidy/sources/"*.jpg "$ROOT/projects/tidy/sources/"*.png "$ROOT/projects/tidy/sources/"*.csv
run "$ROOT" tidy --apply
assert "a folder with nothing to prune exits 0"        "$(eq "$RC" 0)"
assert "…and says the folder is retained in full"      "$(has 'retained in full' "$OUT")"
assert "…and still stamps deliverable_paths"           "$(yes_if grep -q '^deliverable_paths:' "$ROOT/projects/tidy/project.md")"

echo "== a project with no artifacts at all stamps an empty list =="
new_instance "$ROOT" bare "retain: true"$'\n'
rm -f "$ROOT/projects/bare/tasks/task-001.md" "$ROOT/projects/bare/tasks/task-002.md"
run "$ROOT" bare --apply
assert "exits 0"                                       "$(eq "$RC" 0)"
assert "…and stamps an explicit empty list"            "$(yes_if grep -qF 'deliverable_paths: [ ]' "$ROOT/projects/bare/project.md")"

echo "== the stamp is idempotent =="
new_instance "$ROOT" adoption "retain: true"$'\n'
run "$ROOT" adoption --apply
run "$ROOT" adoption --apply
assert "a second --apply exits 0"                      "$(eq "$RC" 0)"
assert "…and leaves exactly one deliverable_paths key" \
  "$(eq "$(grep -c '^deliverable_paths:' "$ROOT/projects/adoption/project.md")" 1)"
assert "…and does not duplicate its entries" \
  "$(eq "$(grep -c 'deck.md' "$ROOT/projects/adoption/project.md")" 1)"
assert "…and the frontmatter still closes"             "$(eq "$(grep -c '^---$' "$ROOT/projects/adoption/project.md")" 2)"
assert "…and every other field survived the rewrite"   "$(yes_if grep -q '^type: Project$' "$ROOT/projects/adoption/project.md")"
assert "…including the body"                           "$(yes_if grep -q 'Closed 2026-08-26' "$ROOT/projects/adoption/project.md")"

echo "== no retain: the folder is removed, exactly as before =="
new_instance "$ROOT" adoption ""
run "$ROOT" adoption --apply
assert "exits 0"                                       "$(eq "$RC" 0)"
assert "the folder is GONE"                            "$(gone "$ROOT/projects/adoption")"
assert "…and says it was not retained"                 "$(has 'not retained' "$OUT")"
assert "…the removal is STAGED, not just unlinked" \
  "$(yes_if grep -q '^projects/adoption/project.md$' <<<"$(git -C "$ROOT" diff --cached --name-only)")"
assert "…the sibling project is untouched"             "$(exists "$ROOT/projects/sibling")"
assert "…and so is the rest of the bundle"             "$(exists "$ROOT/knowledge/findings")"

new_instance "$ROOT" adoption ""
run "$ROOT" adoption
assert "without --apply the folder stays"              "$(exists "$ROOT/projects/adoption")"
assert "…and it says it would remove it"               "$(has 'REMOVE' "$OUT")"

echo "== retain: anything-but-true is not retention =="
for v in false '"true"x' maybe; do
  new_instance "$ROOT" adoption "retain: $v"$'\n'
  run "$ROOT" adoption --apply
  assert "retain: $v removes the folder"               "$(gone "$ROOT/projects/adoption")"
done
# …and the affirmative spellings that DO retain, so the check above is not just
# "everything is removed".
for v in true True TRUE; do
  new_instance "$ROOT" adoption "retain: $v"$'\n'
  run "$ROOT" adoption --apply
  assert "retain: $v keeps the folder"                 "$(exists "$ROOT/projects/adoption")"
done

echo "== the report-only default cannot delete, even with a git repo under it =="
new_instance "$ROOT" adoption ""
run "$ROOT" adoption
assert "no --apply: exits 0"                           "$(eq "$RC" 0)"
assert "…nothing is staged"                            "$(yes_if sh -c 'cd "$1" && [ -z "$(git diff --cached --name-only)" ]' _ "$ROOT")"
assert "…and the folder is intact"                     "$(exists "$ROOT/projects/adoption/tasks/task-001.md")"

echo "== untracked leftovers: the derived index goes, everything else is named and kept =="
# The bundle's own ignore lines, so these files are UNTRACKED as they are on a real
# instance and `git rm -r` leaves them. Removing every ignored file would pass the first
# block below and fail the second: that is the mutant this section is built to kill.
ROOT="$TMP/left"
left_instance() { # <untrack...>
  new_instance "$ROOT" adoption ""
  printf '%s\n' 'tmp/' '.env' '/projects/*/index.md' > "$ROOT/.gitignore"
  ( cd "$ROOT" && git_c rm -rq --cached -- "$@" && git_c add .gitignore && git_c commit -qm ignore ) >/dev/null 2>&1
}
P="$ROOT/projects/adoption"

left_instance projects/adoption/index.md
run "$ROOT" adoption --apply
assert "derived index only: exits 0"                  "$(eq "$RC" 0)"
assert "…index.md is removed"                         "$(gone "$P/index.md")"
assert "…and the now-empty folder with it"            "$(gone "$P")"
assert "…reported as removed, by name"                "$(has 'PRUNE  projects/adoption/index.md' "$OUT")"
assert "…and nothing is left to inspect"              "$(hasnt 'inspect' "$OUT")"

left_instance projects/adoption/index.md projects/adoption/tmp
echo 'TOKEN=x' > "$P/.env"
run "$ROOT" adoption --apply
assert "index.md + a gitignored .env: exits 0"        "$(eq "$RC" 0)"
assert "…index.md is removed"                         "$(gone "$P/index.md")"
assert "….env is STILL THERE"                         "$(exists "$P/.env")"
assert "…so is the untracked tmp/"                    "$(exists "$P/tmp/$PII_NAME")"
assert "…and the folder is not removed"               "$(exists "$P")"
assert "…the notice names .env"                       "$(has 'projects/adoption/.env' "$OUT")"
assert "…and asks a human to inspect it"              "$(has 'inspect and remove by hand' "$OUT")"
assert "…tmp/ is listed by directory and count"       "$(has 'projects/adoption/tmp/ (3 entries, contents not listed)' "$OUT")"
assert "…and no filename from inside it is printed"   "$(hasnt "$PII_NAME" "$OUT")"

left_instance projects/adoption/index.md
run "$ROOT" adoption
assert "report-only with an untracked index: exits 0" "$(eq "$RC" 0)"
assert "…index.md still exists"                       "$(exists "$P/index.md")"
assert "…and it says it would remove it"              "$(has 'would remove projects/adoption/index.md' "$OUT")"

echo "== the closeout PROSE routes to this script, and invents no status value =="
# The steps around this script are prose an agent executes, which cannot be driven from
# a harness — but WHICH MECHANISM the prose names can be, and that is the part that
# rots. These assertions exist so a future edit cannot quietly put a hand-rolled
# `git rm -r` back beside a tested script, or grow the status enum a value.
# ---------------------------------------------------------------- projects/CLOSED.md
# THE SHA IS ASSERTED AGAINST A REAL REMOVAL, NOT A STRING. The fixture is closed for
# real — the script runs, then the closing commit is made — and the recorded sha is then
# compared against `git rev-parse HEAD^` of that commit. A hand-written expectation would
# pass while the script pinned the wrong end of the parent edge, which is the ONE defect
# that matters here: a branch-path or child-commit link 404s exactly when it is needed.
echo "== the closed index: projects/CLOSED.md =="
ROOT="$TMP/closed"
new_instance "$ROOT" adoption ""
( cd "$ROOT" && git remote add origin git@github.com:fixture-org/fixture-bundle.git )
run "$ROOT" adoption --apply
assert "the closeout exits 0"                         "$(eq "$RC" 0)"
assert "…and writes projects/CLOSED.md"               "$(exists "$ROOT/projects/CLOSED.md")"
assert "…and STAGES it, so it lands in the closing commit" \
  "$(yes_if grep -qx 'projects/CLOSED.md' <<<"$(git -C "$ROOT" diff --cached --name-only)")"
assert "…under a \`## <slug>\` heading"               "$(yes_if grep -qx '## adoption' "$ROOT/projects/CLOSED.md")"
assert "…with an ISO close date"                      "$(yes_if grep -qE '^- closed: [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$ROOT/projects/CLOSED.md")"
assert "…and the project's one-line outcome"          "$(yes_if grep -q '^- outcome: finished research, kept as a reference surface$' "$ROOT/projects/CLOSED.md")"

# THE PARENT EDGE, on the real commit. This is the assertion the whole file is for.
( cd "$ROOT" && git_c commit -qm "chore: close adoption" >/dev/null 2>&1 )
CLOSING="$( cd "$ROOT" && git rev-parse HEAD )"
PARENT="$( cd "$ROOT" && git rev-parse "$CLOSING^" )"
PINNED="$(sed -n 's/^- pinned: //p' "$ROOT/projects/CLOSED.md")"
assert "the pinned sha is the PARENT of the closing commit" "$(eq "$PINNED" "$PARENT")"
assert "…and is NOT the closing commit itself"              "$(no_if test "$PINNED" = "$CLOSING")"
assert "…the folder really is gone at the closing commit"   "$(no_if sh -c \
  'cd "$1" && git cat-file -e "HEAD:projects/adoption/project.md"' _ "$ROOT")"
assert "…and really is there at the pinned one"             "$(yes_if sh -c \
  'cd "$1" && git cat-file -e "$2:projects/adoption/deliverables/deck.html"' _ "$ROOT" "$PINNED")"

# One row per DECLARED deliverable that existed. `never-written.pdf` was declared and
# never written; `handout.pdf` exists and was never declared. Neither is a deliverable.
assert "a row per declared deliverable that exists (3)" \
  "$(eq "$(grep -c '^- deliverable: ' "$ROOT/projects/CLOSED.md")" 3)"
assert "…a declared-but-missing artifact gets no row"  "$(hasnt 'never-written.pdf' "$(cat "$ROOT/projects/CLOSED.md")")"
assert "…an undeclared file on disk gets no row"       "$(hasnt 'handout.pdf' "$(cat "$ROOT/projects/CLOSED.md")")"
assert "the link is a permalink at the pinned sha"     "$(yes_if grep -qF \
  "https://github.com/fixture-org/fixture-bundle/blob/$PARENT/projects/adoption/deliverables/deck.html" "$ROOT/projects/CLOSED.md")"
assert "…and never a branch path"                      "$(hasnt '/blob/main/' "$(cat "$ROOT/projects/CLOSED.md")")"
assert "…the restore command sits beside it"           "$(yes_if grep -qF \
  "  - restore: \`gh api repos/fixture-org/fixture-bundle/contents/projects/adoption/deliverables/deck.html?ref=$PARENT --jq .content | base64 -d > /tmp/deck.html\`" "$ROOT/projects/CLOSED.md")"
assert "…and the file says not to hand-edit it"        "$(has 'Do not hand-edit' "$(cat "$ROOT/projects/CLOSED.md")")"

# A project that shipped nothing: log.md already records the close, so an index of
# things to come back to gains nothing from a row.
new_instance "$ROOT" bare ""
rm -rf "$ROOT/projects/bare/tasks" "$ROOT/projects/bare/deliverables"
mkdir -p "$ROOT/projects/bare/tasks"
( cd "$ROOT" && git_c add -A . >/dev/null 2>&1 && git_c commit -qm refix >/dev/null 2>&1 )
run "$ROOT" bare --apply
assert "a project with NO deliverables still closes"   "$(eq "$RC" 0)"
assert "…and writes no CLOSED.md at all"               "$(gone "$ROOT/projects/CLOSED.md")"
assert "…and says so"                                  "$(has 'no entry' "$OUT")"

# The report-only default is a dry run: it must say what it WOULD record and write nothing.
new_instance "$ROOT" adoption ""
run "$ROOT" adoption
assert "report-only names the entry it would add"      "$(has 'CLOSED.md += ## adoption' "$OUT")"
assert "…and writes nothing"                           "$(gone "$ROOT/projects/CLOSED.md")"

# Re-running against an index that already names the project must not double it.
new_instance "$ROOT" adoption ""
run "$ROOT" adoption --apply
n1="$(grep -c '^## adoption$' "$ROOT/projects/CLOSED.md")"
( cd "$ROOT" && git_c commit -qm close >/dev/null 2>&1 )
mkdir -p "$ROOT/projects/adoption/tasks" "$ROOT/projects/adoption/deliverables"
echo deck > "$ROOT/projects/adoption/deliverables/deck.md"
cat > "$ROOT/projects/adoption/project.md" <<'PRJ'
---
type: Project
title: AI adoption research
description: finished research, kept as a reference surface
kind: research
status: done
timestamp: 2026-08-26T00:00:00Z
---
PRJ
cat > "$ROOT/projects/adoption/tasks/task-001.md" <<'TSK'
---
type: Task
title: Build the mandate deck
status: done
artifacts: [ /projects/adoption/deliverables/deck.md ]
---
TSK
( cd "$ROOT" && git_c add -A . >/dev/null 2>&1 && git_c commit -qm resurrect >/dev/null 2>&1 )
run "$ROOT" adoption --apply
assert "a second close of the same slug appends nothing" \
  "$(eq "$(grep -c '^## adoption$' "$ROOT/projects/CLOSED.md")" "$n1")"
assert "…and says why"                                 "$(has 'not appending a second entry' "$OUT")"

CMD="$TPL/plugin/skills/close-project/SKILL.md"
PM="$TPL/plugin/tick-steps/step-6-close-projects.md"
SCH="$TPL/plugin/seed/SCHEMA.md"
assert "/close-project's folder step calls the script" \
  "$(yes_if grep -q 'close-project-folder.sh <slug> --apply' "$CMD")"
assert "…and says not to remove the folder by hand"     "$(yes_if grep -q 'Do not .git rm. or .rm. the folder by hand' "$CMD")"
assert "…and it is in the command's allowed-tools"      "$(yes_if grep -q 'Bash(bash \${CLAUDE_PLUGIN_ROOT}/scripts/close-project-folder.sh:\*)' "$CMD")"
assert "the PM's closeout calls the same script"        "$(yes_if grep -q 'close-project-folder.sh <slug>' "$PM")"
# Step 1 stayed in the core when step 6 moved out — it runs on every full tick.
assert "the PM skips done projects at the frontmatter"  "$(yes_if grep -q 'skip every .status: done. project right' "$TPL/plugin/agents/project-manager.md")"
assert "SCHEMA.md documents retain:"                    "$(yes_if grep -q '^retain: true ' "$SCH")"
assert "…and names CLOSED.md as where deliverables are found" \
  "$(yes_if grep -q 'CLOSED.md.* is where a closed project.s deliverables are found' "$SCH")"
assert "…and says CLOSED.md is TRACKED"                 "$(yes_if grep -q 'is TRACKED (unlike' "$SCH")"
# The `no archive/` line stands, but no longer stands alone contradicting the index.
assert "…and the 'no archive/' line says what replaces it" \
  "$(yes_if grep -q 'there is still no .archive/.; what replaces it is an INDEX' "$SCH")"
assert "…and retain: is NOT removed by this change"     "$(yes_if grep -qF 'With `retain: true`** the folder stays' "$SCH")"
assert "…and deliverable_paths: as closeout-written"    "$(yes_if grep -qE '^  - "/projects/<slug>/deliverables/' "$SCH")"
assert "…and that non-terminal tasks become cancelled"  "$(yes_if grep -q 'not terminal at closeout becomes .cancelled' "$SCH")"
# The enum itself, at its enforcement point. A "closed-unfinished" sibling status would
# show up here first, and the criterion this pins is that none was introduced.
assert "the Task status enum is unchanged (seven values)" \
  "$(yes_if grep -qF 'Task)      echo "draft ready in-progress in-review blocked cancelled done" ;;' "$TPL/plugin/scripts/validate-bundle.sh")"

printf '\nclose-project-folder.test: pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]] || exit 1
exit 0
