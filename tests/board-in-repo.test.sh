#!/usr/bin/env bash
# iced — the board is on hold (owner's decision, 2026-10-05). `run.sh --iced`, the nightly
# workflow and any PR whose diff names this file's subject still run it. Thaw: delete these lines.
#
# board-in-repo.test.sh — `/board.html` is NOT tracked, and the migration that took it
# out of the bundles is asserted behaviourally rather than by grepping for prose.
#
# WHY THE PAGE LEFT THE REPO. Committing it bought visibility for free — who may read the
# page IS the repo's permission list — and cost one contended path per tick: on a bundle
# two humans clone, both ticks render the file from their own snapshot and push it, for
# output either of them regenerates in a second. `/<plugin>:board serve` replaced it with
# a local server on 127.0.0.1, so nothing about the board is pushed at all.
#
# THE MIGRATION IS STILL ADDITIVE, WHICH IS WHY SECTION 2 IS BEHAVIOURAL. Instances exist
# carrying the `!/board.html` un-ignore this era appended, and init-bundle.sh never removes
# a line from a live instance's .gitignore — so it appends `/board.html` and leans on git's
# own last-match-wins rule. Asserted with `git check-ignore`, not by grepping for the
# pattern text, because the ORDERING is the mechanism. The tracked FILE is a different
# question and gets its own assertions: it is derived output, so the stamp drops it from
# the index and from disk, once, and says so.
#
# SECTION 3 OUTLIVED THE TRACKED PAGE. Given no instance directory, build-board.sh
# discovers instances from `boardInstances`, which on a real machine names SIBLING
# BUNDLES — so the trailing `.` is a data-governance boundary wherever the output travels,
# and `/<plugin>:board publish` is now the path it travels on. The section renders BOTH
# ways from one fixture, so it fails if the scoping breaks AND fails if the fixture stopped
# being able to leak.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail
. "$(dirname "$0")/tools/plugin-name.sh"

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

TPLSRC="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/board-in-repo.XXXXXX")" || {
  echo "board-in-repo.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yes_if() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

# A copy of the template, so install.sh's own worktree-refusal guard never fires (it
# inspects its own dirname's .git, and this copy has none). Same shape as
# index-ignore-restamp.test.sh.
TPL="$TMP/tpl"; mkdir -p "$TPL"
( cd "$TPLSRC" && git ls-files . ) | while IFS= read -r f; do
  [ -n "$f" ] || continue
  mkdir -p "$TPL/$(dirname "$f")"; cp "$TPLSRC/$f" "$TPL/$f" 2>/dev/null || true
done
chmod +x "$TPL/plugin/scripts/init-bundle.sh" "$TPL"/plugin/scripts/*.sh 2>/dev/null || true

ignored() { # <dir> <path> -> yes if git says the path is ignored there
  ( cd "$1" && git init -q . >/dev/null 2>&1 || true; git check-ignore -q "$2" ) \
    && echo yes || echo no
}

# =======================================================================================
echo "== 1. seed/.gitignore ignores board.html =="
# =======================================================================================
# The seed file is the contract for every instance stamped from now on. Checked through
# git rather than by grepping the file: a `!/board.html` un-ignore could return in a form
# the grep missed, and only git decides what git tracks.
SEEDED="$TMP/seeded"; mkdir -p "$SEEDED" "$SEEDED/$AB_DIR"
cp "$TPL/plugin/seed/.gitignore" "$SEEDED/.gitignore"
: > "$SEEDED/board.html"
ok "a repo seeded from seed/ ignores board.html"        "$(ignored "$SEEDED" board.html)" yes
# The neighbours must keep their ignores — flipping one line must not have flipped three.
: > "$SEEDED/$AB_SNAPSHOT"; mkdir -p "$SEEDED/$AB_BOARD_DIR"; : > "$SEEDED/$AB_BOARD_DIR/board.html"
ok "…SNAPSHOT.json is still ignored"                     "$(ignored "$SEEDED" "$AB_SNAPSHOT")" yes
ok "…and the live board page still is too"               "$(ignored "$SEEDED" "$AB_BOARD_DIR/board.html")" yes

# =======================================================================================
echo "== 2. a re-stamp re-ignores board.html and drops the tracked file =="
# =======================================================================================
# A stamp, then the PREVIOUS era's shape put back by hand — an `!/board.html` un-ignore and
# a committed page. This is the shape every existing instance is in right now, and it must
# not be simulated away.
LEGACY="$TMP/legacy"; mkdir -p "$LEGACY"
git -C "$LEGACY" init -q . >/dev/null 2>&1
git -C "$LEGACY" config user.email fixture@example.invalid
git -C "$LEGACY" config user.name fixture
bash "$TPL/plugin/scripts/init-bundle.sh" "$LEGACY" >"$TMP/outL1" 2>&1
printf '\nboard.html\n!/board.html\n' >> "$LEGACY/.gitignore"
printf '<!doctype html>\n' > "$LEGACY/board.html"
git -C "$LEGACY" add -f .gitignore board.html >/dev/null 2>&1
git -C "$LEGACY" commit -qm fixture >/dev/null 2>&1
ok "the legacy shape really does track board.html" \
  "$(yes_if git -C "$LEGACY" ls-files --error-unmatch board.html)" yes
ok "…and git does NOT ignore it there yet"               "$(ignored "$LEGACY" board.html)" no

bash "$TPL/plugin/scripts/init-bundle.sh" "$LEGACY" >"$TMP/outL2" 2>&1
ok "a re-stamp appends the ignore"           "$(yes_if grep -qxF '/board.html' "$LEGACY/.gitignore")" yes
ok "…and git now reports board.html as ignored"          "$(ignored "$LEGACY" board.html)" yes
# The migration must never remove a line from a live instance's .gitignore.
ok "…the old un-ignore is left in place"     "$(yes_if grep -qxF '!/board.html' "$LEGACY/.gitignore")" yes
# The FILE is a separate question from the PATTERN, and both directions are asserted:
# untracked in the index, and gone from disk, with a line saying so.
ok "…the tracked file is dropped from the index" \
  "$(yes_if sh -c '! git -C "$1" ls-files --error-unmatch board.html >/dev/null 2>&1' _ "$LEGACY")" yes
ok "…and removed from disk"                  "$(yes_if sh -c '! test -e "$1/board.html"' _ "$LEGACY")" yes
ok "…and the stamp said so"                  "$(yes_if grep -qF 'drop  board.html' "$TMP/outL2")" yes

# Counted as a DELTA, not against a literal: this fixture's .gitignore already carries the
# seed's own `/board.html`, so the absolute count is 2 and only "did it grow" is the
# idempotency question.
BEFORE3="$(grep -cxF '/board.html' "$LEGACY/.gitignore")"
bash "$TPL/plugin/scripts/init-bundle.sh" "$LEGACY" >"$TMP/outL3" 2>&1
ok "a THIRD stamp appends nothing (idempotent)" \
  "$(grep -cxF '/board.html' "$LEGACY/.gitignore")" "$BEFORE3"
ok "…and board.html is still ignored"                    "$(ignored "$LEGACY" board.html)" yes
ok "…and says nothing about dropping a file it no longer has" \
  "$(grep -cF 'drop  board.html' "$TMP/outL3")" 0

# A freshly seeded instance already carries the seed's own ignore, so the migration must
# stay quiet — an unconditional append would put a duplicate into every new instance.
FRESH="$TMP/fresh"; mkdir -p "$FRESH"
bash "$TPL/plugin/scripts/init-bundle.sh" "$FRESH" >"$TMP/outF1" 2>&1
ok "a fresh stamp appends NO second ignore"  "$(grep -cxF '/board.html' "$FRESH/.gitignore")" 1
ok "…no un-ignore anywhere in it"            "$(grep -cxF '!/board.html' "$FRESH/.gitignore")" 0
ok "…and board.html is ignored there too"                "$(ignored "$FRESH" board.html)" yes

# =======================================================================================
echo "== 3. THE CROSS-BUNDLE LEAK: a trailing . renders THIS instance only =="
# =======================================================================================
BB="$TPL/plugin/scripts/build-board.sh"
snap() { # <dir> <slug> <unique title>
  mkdir -p "$1/$AB_DIR"
  cat > "$1/$AB_SNAPSHOT" <<JSON
{
  "_schema": "ai-bridge board snapshot v1",
  "group": "$2-group",
  "generated_at": "2026-09-02T00:00:00Z",
  "counts": {"projects": 1, "tasks": 1, "awaiting": 0},
  "projects": [
    {
      "slug": "$2", "title": "$3", "description": "fixture", "kind": "build",
      "status": "active", "autonomy": "gated", "owner": "",
      "awaiting_close": false,
      "phase_progress": {"done": 0, "total": 1},
      "phases": [{"title": "phase one", "order": 1, "status": "active"}],
      "tasks": [{"id": "task-001", "title": "$3 task", "kind": "build",
                 "status": "ready", "assignee": "software-engineer", "in_flight": false,
                 "awaiting": "", "open_questions": 0, "open_question_ids": [],
                 "advisor_notes": 0, "depends_on": [], "pr": ""}],
      "deliverable_paths": []
    }
  ]
}
JSON
}
MINE="$TMP/mine"; OTHER="$TMP/other"; mkdir -p "$MINE" "$OTHER"
snap "$MINE"  mine-slug  ZZMINEPROJECTZZ
snap "$OTHER" other-slug ZZOTHERPROJECTZZ
# The hazard's own precondition: boardInstances naming a SIBLING bundle. This is the
# ordinary configuration on a machine with more than one bundle, not a contrived one.
cat > "$MINE/instance.config.json" <<JSON
{ "group": "mine-group", "board": true, "boardInstances": ["$MINE", "$OTHER"] }
JSON

( cd "$MINE" && bash "$BB" --standalone --out board.html . ) >"$TMP/out-scoped" 2>&1
ok "scoped render writes the file"          "$(yes_if test -s "$MINE/board.html")" yes
ok "…and it carries THIS instance's project" "$(yes_if grep -q ZZMINEPROJECTZZ "$MINE/board.html")" yes
ok "…and NOT the sibling bundle's project"   "$(yes_if grep -q ZZOTHERPROJECTZZ "$MINE/board.html")" no

# The other half, and it is not decoration: without it this section passes on a fixture
# whose sibling stopped rendering for an unrelated reason, which would make the assertion
# above vacuous. A bare render MUST still pull the sibling in.
( cd "$MINE" && bash "$BB" --standalone --out bare.html ) >"$TMP/out-bare" 2>&1
ok "a BARE render still reaches boardInstances (fixture is live)" \
  "$(yes_if grep -q ZZOTHERPROJECTZZ "$MINE/bare.html")" yes

# =======================================================================================
echo "== 4. the tick's own instructions no longer commit a page =="
# =======================================================================================
# Text checks, because the tick is a document an agent reads and there is nothing else to
# execute. Kept to what is load-bearing: the live render it still does, and the two strings
# whose ABSENCE is this change — a tracked render and a board commit.
PM="$TPL/plugin/tick-steps/step-8-render.md"
ok "project-manager.md exists"                          "$(yes_if test -f "$PM")" yes
ok "…still names the LIVE render" \
  "$(yes_if grep -qF -- 'build-board.sh --standalone' "$PM")" yes
ok "…at the resolved path, not the pre-3.0 root one" \
  "$(yes_if grep -qF -- '.loopd/.board-live/board.html' "$PM")" yes
ok "…names no tracked render"    "$(yes_if grep -qF -- '--standalone --out board.html .' "$PM")" no
ok "…and no board commit"        "$(grep -cF -- 'chore: refresh board.html' "$PM")" 0
ok "…and points a human at the local server" \
  "$(yes_if grep -qF -- '/'"${PN}:"'board serve' "$PM")" yes
# The launcher's standing facts are what a human reads to know what the loop does.
SK="$TPL/plugin/skills/dispatch/SKILL.md"
ok "the dispatch skill names no tracked board" \
  "$(yes_if grep -qF -- '--standalone --out board.html .' "$SK")" no
ok "…and names the local server instead" \
  "$(yes_if grep -qF -- '/'"${PN}:"'board serve' "$SK")" yes

# =======================================================================================
echo "== 5. THE SAME BOUNDARY ON THE ARTIFACT PATH: /${PN}:board publishes =="
# =======================================================================================
# WHY THIS SECTION EXISTS ALONGSIDE SECTION 3 RATHER THAN INSTEAD OF IT. Section 3 renders
# `--standalone --out board.html .` — the tick's tracked page, whose audience is the repo's
# permission list. `/<plugin>:board` renders the SAME script with the SAME trailing `.`
# but WITHOUT `--standalone`, because the artifact host supplies the wrapper — a different
# invocation, and an invocation is what the scoping lives in. A guard asserted only against
# the flag combination the tick happens to use would go green on a publish path that
# dropped the `.`, and that page's audience is whoever holds the URL rather than whoever
# holds a clone. So the boundary is asserted against the bytes the publish step reads.
ABASE="$TMP/artifact"; AMINE="$ABASE/mine"; AOTHER="$ABASE/other"
mkdir -p "$AMINE" "$AOTHER"
snap "$AMINE"  mine-slug  ZZMINEPROJECTZZ
snap "$AOTHER" other-slug ZZOTHERPROJECTZZ
# A config carrying one planted literal of each kind the publish criterion names. Every one
# is a real key of a real instance config, and NONE is in the snapshot's field allowlist —
# so any of them reaching the page means the renderer found a route back to the bundle that
# the allowlist never cleared.
#
# `ownerGithubUser` MATCHES `defaultOwner` ON PURPOSE, and it is not decoration: the page is
# per owner, so a project with an empty `owner` resolves to `defaultOwner`, and if that is
# not this clone's login the project sinks into the collapsed other-owners section — which
# reads TRACKED task documents at HEAD, of which this fixture has none. The project would
# then be absent for a reason that has nothing to do with scoping, and the leak assertion
# below would pass vacuously on an empty page.
cat > "$AMINE/instance.config.json" <<JSON
{ "group": "mine-group", "board": true,
  "boardInstances": ["$AMINE", "$AOTHER"],
  "org": "ZZORGLITERALZZ",
  "defaultRepo": "ZZREPOLITERALZZ",
  "defaultOwner": "ZZPERSONLITERALZZ",
  "ownerGithubUser": "ZZPERSONLITERALZZ",
  "authorEmail": "ZZEMAILLITERALZZ@example.com",
  "reposRoot": "/tmp/ZZPATHLITERALZZ",
  "people": { "ZZPERSONLITERALZZ": "ZZEMAILLITERALZZ@example.com" } }
JSON

( cd "$AMINE" && bash "$BB" --out artifact-body.html . ) >"$TMP/out-art" 2>&1
ok "the artifact render writes a body"       "$(yes_if test -s "$AMINE/artifact-body.html")" yes
ok "…and it carries THIS instance's project" "$(yes_if grep -q ZZMINEPROJECTZZ "$AMINE/artifact-body.html")" yes
ok "…and NOT the sibling bundle's project"   "$(yes_if grep -q ZZOTHERPROJECTZZ "$AMINE/artifact-body.html")" no
# The same two-sided shape section 3 uses, and for the same reason: without it the
# assertion above passes on a fixture whose sibling had quietly stopped rendering.
( cd "$AMINE" && bash "$BB" --out bare-artifact.html ) >"$TMP/out-art-bare" 2>&1
ok "a BARE artifact render still reaches boardInstances (fixture is live)" \
  "$(yes_if grep -q ZZOTHERPROJECTZZ "$AMINE/bare-artifact.html")" yes

# ONE LITERAL AT A TIME, NAMED IN THE FAILURE. Checked over the SCOPED page, which is the
# one that gets published.
for lit in ZZORGLITERALZZ ZZREPOLITERALZZ ZZPERSONLITERALZZ ZZEMAILLITERALZZ ZZPATHLITERALZZ; do
  ok "no $lit in the published page" \
    "$(yes_if grep -q "$lit" "$AMINE/artifact-body.html")" no
done
# The bundle's own absolute path is a path literal too, and the one a renderer is most
# likely to embed by accident — it is an argument to the command that produced the page.
ok "…nor the instance's own absolute path" "$(yes_if grep -qF "$AMINE" "$AMINE/artifact-body.html")" no

# NON-VACUITY, and it is the assertion that makes the six above mean something. "No literal
# appears" is satisfied by a renderer that emits nothing at all, so a REPO NAME the snapshot
# DOES allow — inside a PR link, which is on the documented carried list — must still reach
# the page. It is the same kind of literal as `defaultRepo` above and the opposite verdict,
# which is exactly the distinction the criterion draws: what the allowlist cleared travels,
# what it never cleared does not.
python3 - "$AMINE/$AB_SNAPSHOT" <<'PYALLOW' 2>/dev/null || true
import json, sys
d = json.load(open(sys.argv[1]))
d["projects"][0]["tasks"][0]["prs"] = [
    {"repo": "o/ZZALLOWEDREPOZZ", "number": 7,
     "url": "https://example.com/o/ZZALLOWEDREPOZZ/pull/7"}]
json.dump(d, open(sys.argv[1], "w"))
PYALLOW
( cd "$AMINE" && bash "$BB" --out allowed.html . ) >"$TMP/out-art-allowed" 2>&1
ok "an ALLOWED repo name inside a PR link does render (the scan is not vacuous)" \
  "$(yes_if grep -q ZZALLOWEDREPOZZ "$AMINE/allowed.html")" yes
ok "…while the config's defaultRepo still does not" \
  "$(yes_if grep -q ZZREPOLITERALZZ "$AMINE/allowed.html")" no

# =======================================================================================
echo "== 6. the skill and the tick each carry their half of the publish contract =="
# =======================================================================================
# Text checks, because both are documents an agent reads. Kept to the strings that are
# load-bearing: the scoped render on the skill's side (a missing `.` is the leak above),
# and on the tick's side the fact that it does NOT publish — measured, not assumed.
SK_BOARD="$TPL/plugin/skills/board/SKILL.md"
ok "the board skill ships"                              "$(yes_if test -f "$SK_BOARD")" yes
ok "…and names the SCOPED artifact render" \
  "$(yes_if grep -qF -- '/artifact-body.html" .' "$SK_BOARD")" yes
ok "…and never writes the tracked board.html" \
  "$(yes_if grep -qF -- '--out board.html' "$SK_BOARD")" no
ok "the tick tells the human what refreshes the published page" \
  "$(yes_if grep -qF -- 'run /'"${PN}:"'board publish to refresh' "$PM")" yes

printf '\nboard-in-repo.test: pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
