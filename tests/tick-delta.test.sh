#!/usr/bin/env bash
#
# tick-delta.test.sh — the idle-tick fast-path probe: `plugin/scripts/tick-delta.sh`.
#
# THE ONE PROPERTY THAT MATTERS, asserted from both sides everywhere: a false DELTA
# costs one full tick — the price that was always paid — but a false IDLE skips owed
# work, so ONLY a byte-for-byte fingerprint match may print IDLE, and every doubt
# (no record, no `gh`, a poisoned PR read, a live dispatch, a dirty tree) must resolve
# to a full tick (exit 1 or 2), never to 0. "It detects the delta" alone would pass a
# probe that says DELTA always, so the idle direction is pinned first and re-pinned
# after every delta case is healed.
#
# `gh` IS A PATH STUB reading canned per-URL answers from a control directory — no
# network, nothing real is fetched, and the stub can be made to fail on demand, which
# is how the poisoned-fingerprint direction is exercised. Fixtures live under mktemp;
# no real instance is touched. ok() compares actual to expected, this directory's
# convention.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

SRC="$REPO/plugin/scripts/tick-delta.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tickdelta.XXXXXX")" || {
  echo "tick-delta.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git \
          -c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false \
          -c core.hooksPath=/dev/null "$@"; }

# ------------------------------------------------------------------- the fixture
INST="$TMP/inst"
mkdir -p "$INST/projects/proj-a/tasks" "$INST/scripts"
cp "$SRC" "$INST/scripts/tick-delta.sh"; chmod +x "$INST/scripts/tick-delta.sh"
# tick-delta.sh sources its sibling resolver (ai-bridge-v3/task-031), so the staged copy
# has to carry it too — and since task-024 the digest also reads its sibling
# `fold-answers.sh` and the `../tick-steps` directory, both of which it REFUSES to guess
# around. A stage missing either is a stage that no longer resembles an install.
cp "$(dirname "$SRC")/bundle-paths.sh" "$INST/scripts/bundle-paths.sh"
cp "$(dirname "$SRC")/fold-answers.sh" "$INST/scripts/fold-answers.sh"
cp -R "$REPO/plugin/tick-steps" "$INST/tick-steps"
SH="$INST/scripts/tick-delta.sh"

# Delimited frontmatter, not just the keys: the digest reads `open_questions` through
# fold-answers.sh's parser, which refuses a document it cannot bound.
task() { # <file> <status> [pr-url]
  { printf -- '---\ntype: Task\nkind: build\nstatus: %s\n' "$2"
    [ $# -ge 3 ] && printf 'pr: ["%s"]\n' "$3" || printf 'pr: []\n'
    printf -- '---\n'
  } > "$1"
}
printf 'type: Project\nstatus: active\nautonomy: gated\n' > "$INST/projects/proj-a/project.md"
task "$INST/projects/proj-a/tasks/t1.md" ready
task "$INST/projects/proj-a/tasks/t2.md" in-review "https://github.com/example-org/example-repo/pull/7"
# The real instance gitignores the fingerprint (install.sh's guard block); without this,
# `git add -A` below would COMMIT .tick-state and every later record would dirty the tree.
printf '/%s\n' "$AB_STATE_DIR" > "$INST/.gitignore"
GIT -C "$INST" init -q
GIT -C "$INST" add -A && GIT -C "$INST" commit -qm init

# The gh stub: `gh pr view <url> --json ... --jq ...` prints the canned line for the
# URL's PR number from $GHDIR/<n>, or fails when $GHDIR/<n>.fail exists.
GHDIR="$TMP/gh"; mkdir -p "$GHDIR"
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'EOS'
#!/usr/bin/env bash
url="$3"
n="${url##*/}"
[ -e "$GHDIR/$n.fail" ] && exit 1
[ -f "$GHDIR/$n" ] || exit 1
cat "$GHDIR/$n"
EOS
chmod +x "$BIN/gh"
printf 'OPEN abc1234 NONE\n' > "$GHDIR/7"
WITH() { PATH="$BIN:$PATH" GHDIR="$GHDIR" "$SH" "$@" --instance "$INST"; }

run() { # <check|record> -> "rc:<n> first-line"
  local out rc
  out="$(WITH "$1" 2>&1)"; rc=$?
  printf 'rc:%s %s' "$rc" "$(head -1 <<<"$out" | cut -c1-12)"
}

echo "== no record yet: doubt resolves to the full tick, never to IDLE =="
ok "check before any record is exit 2"          "$(run check)" "rc:2 CANNOT ANSWE"
WITH record; ok "record writes the state file"  "$([ -f "$INST/$AB_STATE_DIR" ] && echo yes || echo no)" yes

echo "== the idle direction: only a byte-for-byte match says IDLE =="
ok "record then check is IDLE (exit 0)"          "$(run check)" "rc:0 IDLE: finger"
ok "…and idle twice in a row stays idle"        "$(run check)" "rc:0 IDLE: finger"

echo "== every delta class flips it — and healing each restores IDLE =="
GIT -C "$INST" commit -q --allow-empty -m tick
ok "a new bundle commit is a DELTA"              "$(run check)" "rc:1 DELTA: the f"
WITH record; ok "…healed by re-record"          "$(run check)" "rc:0 IDLE: finger"

printf 'edited\n' >> "$INST/projects/proj-a/tasks/t1.md"
ok "a dirty tracked file is a DELTA"             "$(run check)" "rc:1 DELTA: track"
GIT -C "$INST" checkout -q -- .
ok "…healed by a clean tree"                    "$(run check)" "rc:0 IDLE: finger"

printf 'draft\n' > "$INST/projects/proj-a/tasks/new-draft.md"
ok "an untracked file under projects/ is a DELTA" "$(run check)" "rc:1 DELTA: untra"
rm -f "$INST/projects/proj-a/tasks/new-draft.md"

task "$INST/projects/proj-a/tasks/t1.md" in-progress
GIT -C "$INST" add -A && GIT -C "$INST" commit -qm dispatch
WITH record
ok "an in-progress task is a DELTA even against its own record" "$(run check)" "rc:1 DELTA: task("
task "$INST/projects/proj-a/tasks/t1.md" ready
GIT -C "$INST" add -A && GIT -C "$INST" commit -qm undo
WITH record; ok "…and clears when nothing is in flight"        "$(run check)" "rc:0 IDLE: finger"

printf 'OPEN def5678 NONE\n' > "$GHDIR/7"
ok "a moved PR head is a DELTA"                  "$(run check)" "rc:1 DELTA: the f"
printf 'MERGED def5678 NONE\n' > "$GHDIR/7"
ok "…so is a state change"                      "$(run check)" "rc:1 DELTA: the f"
printf 'OPEN abc1234 CHANGES_REQUESTED\n' > "$GHDIR/7"
ok "…so is a review decision"                   "$(run check)" "rc:1 DELTA: the f"
printf 'OPEN abc1234 NONE\n' > "$GHDIR/7"
ok "…and the original PR facts restore IDLE"    "$(run check)" "rc:0 IDLE: finger"

touch "$INST/$AB_AWAITING"
ok "a touched AWAITING.md (queue re-enable) is a DELTA" "$(run check)" "rc:1 DELTA: the f"
rm -f "$INST/$AB_AWAITING"

echo "== a poisoned fingerprint is no answer at all — and record refuses to write it =="
touch "$GHDIR/7.fail"
ok "an unreadable PR makes check exit 2"         "$(run check)" "rc:2 CANNOT ANSWE"
before="$(cat "$INST/$AB_STATE_DIR")"
WITH record 2>/dev/null; rc=$?
ok "…and record refuses (exit 2)"               "$rc" 2
ok "…leaving the previous record untouched"     "$([ "$(cat "$INST/$AB_STATE_DIR")" = "$before" ] && echo yes || echo no)" yes
rm -f "$GHDIR/7.fail"

# HERMETIC: a bin dir holding every tool the script needs and NOTHING else — a bare
# system PATH could still carry a real gh (and would let this test touch the network).
NOGH="$TMP/nogh"; mkdir -p "$NOGH"
for t in bash sh git sed grep sort date mv rm diff head cut env; do
  tp="$(command -v "$t" 2>/dev/null)" && ln -s "$tp" "$NOGH/$t"
done
ok "no gh on PATH is exit 2, never IDLE"         "$(PATH="$NOGH" "$SH" check --instance "$INST" >/dev/null 2>&1; echo "rc:$? ")" "rc:2 "

# In `check`, an unreadable tracked file trips the dirty branch first (git reports it
# modified) — fail-closed either way. The load-bearing path is RECORD, which has no dirty
# pre-check: a record built over the unreadable file would be the hole a later check
# "matches".
chmod 000 "$INST/projects/proj-a/tasks/t1.md"
before2="$(cat "$INST/$AB_STATE_DIR")"
WITH record 2>/dev/null; rc2=$?
ok "record over an unreadable task file refuses (exit 2)"       "$rc2" 2
ok "…leaving the record untouched"              "$([ "$(cat "$INST/$AB_STATE_DIR")" = "$before2" ] && echo yes || echo no)" yes
chmod 644 "$INST/projects/proj-a/tasks/t1.md"
ok "…and readable again restores IDLE"          "$(run check)" "rc:0 IDLE: finger"

echo "== the digest: the same walk, enriched, for the tick that must orient =="
D="$(WITH digest)"; drc=$?
ok "digest exits 0 and prints the enumeration"   "$drc" 0
ok "…a project line with status and autonomy"   "$(printf '%s\n' "$D" | grep -c 'project proj-a status=active autonomy=gated')" 1
ok "…a task line with the orienting fields"     "$(printf '%s\n' "$D" | grep -c 'tasks/t2.md status=in-review kind=build assignee=- deps=0 q=0 crit=no wt=no')" 1
ok "…and the PR facts fetched once"             "$(printf '%s\n' "$D" | grep -c 'pr https://github.com/example-org/example-repo/pull/7 OPEN abc1234 NONE')" 1

mkdir -p "$INST/projects/done-proj/tasks"
printf 'type: Project\nstatus: done\n' > "$INST/projects/done-proj/project.md"
task "$INST/projects/done-proj/tasks/old.md" done
GIT -C "$INST" add -A && GIT -C "$INST" commit -qm done-proj
ok "a done project is skipped at its frontmatter in the digest" \
   "$(WITH digest | grep -c 'done-proj/tasks')" 0
ok "…and in the probe walk too"                 "$(WITH record; grep -c 'done-proj/tasks' "$INST/$AB_STATE_DIR")" 0
ok "…while its project line still shows in the digest" "$(WITH digest | grep -c 'project done-proj status=done')" 1

echo "== a paused project is still walked: in-flight work and its PRs stay monitored =="
# tick-delta.sh is deliberately untouched by the pause gate: it skips `done` alone, so an
# agent running inside a paused project and a PR finishing there both still reach the tick.
mkdir -p "$INST/projects/held/tasks"
printf 'type: Project\nstatus: paused\n' > "$INST/projects/held/project.md"
printf -- '---\ntype: Task\nkind: build\nstatus: in-progress\nsession: s-1\npr: []\n---\n' \
  > "$INST/projects/held/tasks/run.md"
task "$INST/projects/held/tasks/rev.md" in-review "https://github.com/example-org/example-repo/pull/8"
printf 'OPEN fed4321 NONE\n' > "$GHDIR/8"
GIT -C "$INST" add -A && GIT -C "$INST" commit -qm held
D="$(WITH digest)"
ok "the paused project is enumerated"            "$(printf '%s\n' "$D" | grep -c '^project held status=paused')" 1
ok "…its in-progress task, status unchanged"     "$(printf '%s\n' "$D" | grep -c 'held/tasks/run.md status=in-progress')" 1
ok "…its in-review task, status unchanged"       "$(printf '%s\n' "$D" | grep -c 'held/tasks/rev.md status=in-review')" 1
ok "…and the digest says inflight yes"           "$(printf '%s\n' "$D" | grep -cx 'inflight yes')" 1
ok "…and its PR is still read from the host"     "$(printf '%s\n' "$D" | grep -c 'pr https://github.com/example-org/example-repo/pull/8 OPEN fed4321 NONE')" 1
WITH record
ok "check is DELTA, never IDLE, while an agent runs in a paused project" "$(run check)" "rc:1 DELTA: task("
rm -rf "$INST/projects/held" "$GHDIR/8"; GIT -C "$INST" add -A && GIT -C "$INST" commit -qm unheld
WITH record

mkdir -p "$INST/projects/broken/tasks"
task "$INST/projects/broken/tasks/orphan.md" ready
ok "a tasks/ dir with no project.md poisons the walk (exit 2, not a silent hole)" \
   "$(WITH digest >/dev/null 2>&1; echo $?)" 2
rm -rf "$INST/projects/broken"; GIT -C "$INST" checkout -q -- . 2>/dev/null

echo "== the digest counts list ELEMENTS, and a one-line list ends on its own line =="
# A sed range /A/,/B/ never tests B on A's line, so `key: [ ]` used to run on to the NEXT
# `]`. The fixture keeps a real task's key ORDER, because the order decided the wrong number.
QD="$INST/projects/proj-q/tasks"; mkdir -p "$QD"
printf 'type: Project\nstatus: active\n' > "$INST/projects/proj-q/project.md"
cat > "$QD/empty.md" <<'EOF'
---
type: Task
title: "an empty-list fixture"
kind: build
status: ready
assignee: software-engineer
depends_on: [ ]
acceptance_criteria: [ "one", "two" ]
open_questions: [ ]
answered_questions: [ "2026-01-01T00:00:00Z by example-user-007 · Q1: which? --- this one" ]
worktree: /tmp/wt
branch: b
pr: [ "https://github.com/example-org/example-repo/pull/9" ]
open_caveats: [ ]
---
EOF
cat > "$QD/filled.md" <<'EOF'
---
type: Task
status: ready
depends_on: [ task-006 ]
acceptance_criteria: [ "x" ]
open_questions: [ "Q1: a comma, and a ] inside quotes?", "Q2: b" ]
worktree: /tmp/wt
pr: [ ]
---
EOF
cat > "$QD/multi.md" <<'EOF'
---
type: Task
status: ready
depends_on:
  - task-001
  - task-002
open_questions: [
  "Q1: one",
  "Q2: two",
  "Q3: three"
]
acceptance_criteria: [ "x" ]
---
EOF
cat > "$QD/prose.md" <<'EOF'
---
type: Task
status: ready
open_questions: [ ]
---

A body line carrying the delimiter --- which is prose, not an answer.
EOF
GIT -C "$INST" add -A && GIT -C "$INST" commit -qm counts
D="$(WITH digest)"
ok 'an empty one-line list counts 0, in a real task'"'"'s key order' \
   "$(printf '%s\n' "$D" | grep -c 'proj-q/tasks/empty.md .* deps=0 q=0 crit=yes wt=yes$')" 1
ok 'a filled one-line list counts its elements (1 dep, 2 quoted questions)' \
   "$(printf '%s\n' "$D" | grep -c 'proj-q/tasks/filled.md .* deps=1 q=2 crit=yes wt=yes$')" 1
ok '...and a list across several lines still counts its elements' \
   "$(printf '%s\n' "$D" | grep -c 'proj-q/tasks/multi.md .* deps=2 q=3 crit=yes wt=no$')" 1
ok 'an empty open_questions with --- in the body and a later list does not name step 2' \
   "$(printf '%s\n' "$D" | grep '^steps:' | grep -c 'step-2')" 0
ok '...while the steps line keeps its shape' \
   "$(printf '%s\n' "$D" | grep -c '^steps: .*step-3-dispatch.md')" 1
rm -rf "$INST/projects/proj-q"; GIT -C "$INST" add -A && GIT -C "$INST" commit -qm uncounts

echo "== plumbing =="
ok "not a git repo is exit 2"    "$(mkdir -p "$TMP/plain"; "$SH" check --instance "$TMP/plain" >/dev/null 2>&1; echo $?)" 2
ok "a bad mode is usage (3)"     "$("$SH" frobnicate >/dev/null 2>&1; echo $?)" 3
ok "the shipped file is executable in the index" \
   "$(cd "$REPO" && git ls-files -s plugin/scripts/tick-delta.sh | awk '{print $1}')" 100755

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
