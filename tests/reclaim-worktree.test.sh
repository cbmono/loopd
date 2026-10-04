#!/usr/bin/env bash
#
# reclaim-worktree.test.sh — exercises plugin/scripts/reclaim-worktree.sh, the ONE script
# in this template that deletes a worktree.
#
# Removal is allowed back only because it deletes ONE path a task RECORDED instead of a
# path it inferred from a scan, so what has to be proven here is not that removal works
# (a handful of assertions) but that every refusal holds (most of this file). A guard
# that quietly stops firing turns this back into the delete path that destroyed three
# running agents' worktrees on 2026-08-04.
#
# Four properties any change must preserve:
#   1. It never touches the real reposRoot. It builds its own bundle whose
#      instance.config.json points at an mktemp tree.
#   2. It builds OUTSIDE any synced folder and refuses if $TMPDIR is inside one.
#   3. ONE fixture is removed in the whole run; the rest are asserted still present as a
#      blanket property, not only per case.
#   4. Both directions per guard: the fixture that trips it REFUSES, and — for the two
#      guards that can clear — the same fixture CLEARS once the trip is removed. A
#      harness of refusals alone passes a script that refuses everything.
#
# `gh` is stubbed (a fake `gh` first on PATH) so PR state is a fixture, not a network
# call. It answers only `gh pr view <url> --json state --jq .state`.
#
# Usage:  tests/reclaim-worktree.test.sh
#         RECLAIM=/path/to/reclaim-worktree.sh tests/reclaim-worktree.test.sh
set -uo pipefail

RECLAIM="${RECLAIM:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/reclaim-worktree.sh}"
TPLSRC="$(cd "$(dirname "$0")/.." && pwd)"

die() { printf 'reclaim-worktree.test: %s\n' "$*" >&2; exit 2; }
[ -f "$RECLAIM" ] || die "script not found at $RECLAIM"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/reclaim-fixture.XXXXXX")" || die "mktemp failed"
# macOS $TMPDIR is a symlink (/var -> /private/var) and `git worktree list --porcelain`
# prints resolved paths: an unresolved comparison matches nothing.
TMP="$(cd "$TMP" && pwd -P)"
case "$TMP" in
  *Dropbox*|*iCloud*|*"Google Drive"*|*OneDrive*)
    rm -rf "$TMP"; die "refusing to build fixtures inside a synced folder ($TMP)" ;;
esac
trap 'rm -rf "$TMP"' EXIT

ORIGIN="$TMP/origin.git"
REPOS="$TMP/repos"
REPO="$REPOS/proj"
WTROOT="$TMP/wt"
OUTSIDE="$TMP/outside"
INSTANCE="$TMP/instance"
FIXTURES="$TMP/gh-fixtures"
TASKS="$INSTANCE/projects/demo/tasks"

mkdir -p "$REPOS" "$WTROOT" "$OUTSIDE" "$TASKS" "$TMP/bin" "$TMP/nogh"

cat > "$INSTANCE/instance.config.json" <<JSON
{
  "org": "fixture-org",
  "reposRoot": "$REPOS",
  "worktreeRoot": "$WTROOT",
  "authorEmail": "fixture@example.com"
}
JSON

g() { git -C "$REPO" "$@"; }

git init -q -b main "$REPO"
g config user.email fixture@example.com
g config user.name  Fixture
g config commit.gpgsign false
printf 'one\n' > "$REPO/tracked.txt"
printf '.env\nnode_modules/\ntmp/\n' > "$REPO/.gitignore"
g add tracked.txt .gitignore; g commit -qm 'c1'
git init -q --bare -b main "$ORIGIN"
g remote add origin "$ORIGIN"
g push -q -u origin main
g remote set-head origin -a >/dev/null

# The shape a finished dispatch has: on a branch, one commit, pushed, nothing dirty.
wt_pushed() { # <path> <branch>
  git -C "$REPO" worktree add -q "$1" -b "$2" origin/main >/dev/null
  git -C "$1" config user.email fixture@example.com
  git -C "$1" config user.name Fixture
  printf 'work\n' > "$1/feature.txt"
  git -C "$1" add feature.txt
  git -C "$1" commit -qm "work on $2"
  git -C "$1" push -q -u origin "$2"
}

# Detached at a sha on NO ref — what a squash-merged head looks like once its remote
# branch is deleted, and the class whose commits a removal destroys irrecoverably.
wt_detached() { # <path> -> prints the sha
  local tmpbr="tmp/$(basename "$1")"
  g branch -q "$tmpbr" main
  git -C "$REPO" worktree add -q --detach "$1" "$tmpbr" >/dev/null
  git -C "$1" config user.email fixture@example.com
  git -C "$1" config user.name Fixture
  printf 'detached work\n' > "$1/feature.txt"
  git -C "$1" add feature.txt
  git -C "$1" commit -qm 'detached work'
  g branch -qD "$tmpbr"
  git -C "$1" rev-parse HEAD
}

PR1="https://github.com/fixture-org/proj/pull/1"
PR2="https://github.com/fixture-org/proj/pull/2"
PR_CLOSED="https://github.com/fixture-org/proj/pull/3"
PR_OTHER="https://github.com/fixture-org/other/pull/9"

# `-` omits a key entirely, which is how "absent" is tested.
write_task() { # <id> <status> <worktree|-> <branch|-> <target_repo|-> <pr-urls...|->
  local id=$1 st=$2 wt=$3 br=$4 tr=$5; shift 5
  {
    echo "---"
    echo "type: Task"
    echo "title: fixture $id"
    echo "kind: build"
    echo "status: $st"
    [ "$tr" = "-" ] || echo "target_repo: $tr"
    [ "$wt" = "-" ] || echo "worktree: $wt"
    [ "$br" = "-" ] || echo "branch: $br"
    if [ "${1:-}" = "-" ] || [ "$#" -eq 0 ]; then
      echo "pr: [ ]"
    else
      printf 'pr: [ %s ]\n' "$(printf '%s, ' "$@" | sed 's/, $//')"
    fi
    echo "timestamp: 2026-10-02T00:00:00Z"
    echo "---"
    echo
    echo "# Context"
    echo "A fixture task."
  } > "$TASKS/$id.md"
}

cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
if [ "${1:-}" != pr ] || [ "${2:-}" != view ]; then
  echo "gh-stub: unhandled invocation: $*" >&2; exit 1
fi
url="${3:-}"
state="$(awk -v u="$url" '$1 == u { print $2 }' "${GH_FIXTURES:?}")"
[ -n "$state" ] || { echo "gh-stub: no fixture for $url" >&2; exit 1; }
printf '%s\n' "$state"
STUB
chmod +x "$TMP/bin/gh"

cat > "$FIXTURES" <<EOF
$PR1 MERGED
$PR2 OPEN
$PR_CLOSED CLOSED
$PR_OTHER MERGED
EOF

OUT=""; RC=0
run() { # <args...>   → sets OUT and RC
  OUT="$( cd "$INSTANCE" \
    && PATH="${STUB_PATH:-$TMP/bin:$PATH}" \
       GH_FIXTURES="$FIXTURES" \
       bash "${SCRIPT:-$RECLAIM}" "$@" 2>&1 )"
  RC=$?
}

pass=0; fail=0
assert() { if [ "$2" = 0 ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
no_if()  { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
eq()     { [ "$1" = "$2" ] && echo 0 || echo 1; }
has()    { grep -Eq -- "$1" <<<"$OUT" && echo 0 || echo 1; }

registered() { # <path> — still a registered worktree of the fixture repo?
  grep -Fxq "worktree $1" <<<"$(git -C "$REPO" worktree list --porcelain)"
}

# Exit 1, a message naming the reason, and the worktree STILL THERE. The third is the
# one that matters: a refusal that printed the right words while removing the directory
# anyway would pass the first two.
refusal() { # <label> <task-id> <reason-regex> <worktree-path|->
  local label=$1 id=$2 want=$3 wt=$4
  run "projects/demo/tasks/$id.md"
  assert "$label: exits 1"            "$(eq "$RC" 1)"
  assert "$label: says why"           "$(has "$want")"
  if [ "$wt" != "-" ]; then
    assert "$label: worktree survives"   "$(yes_if test -d "$wt")"
    assert "$label: still registered"    "$(yes_if registered "$wt")"
  fi
}

echo "== G2: only a 'done' task may reclaim =="
WT_STATUS="$WTROOT/proj-demo-status"
wt_pushed "$WT_STATUS" okf/demo-status
write_task task-status-cancelled  cancelled   "$WT_STATUS" okf/demo-status fixture-org/proj "$PR1"
write_task task-status-review     in-review   "$WT_STATUS" okf/demo-status fixture-org/proj "$PR1"
write_task task-status-progress   in-progress "$WT_STATUS" okf/demo-status fixture-org/proj "$PR1"
write_task task-status-blocked    blocked     "$WT_STATUS" okf/demo-status fixture-org/proj "$PR1"
write_task task-status-ready      ready       "$WT_STATUS" okf/demo-status fixture-org/proj "$PR1"
refusal "G2 cancelled"    task-status-cancelled  'refuse:.*not .done.' "$WT_STATUS"
refusal "G2 in-review"    task-status-review     'refuse:.*not .done.' "$WT_STATUS"
refusal "G2 in-progress"  task-status-progress   'refuse:.*not .done.' "$WT_STATUS"
refusal "G2 blocked"      task-status-blocked    'refuse:.*not .done.' "$WT_STATUS"
refusal "G2 ready"        task-status-ready      'refuse:.*not .done.' "$WT_STATUS"

echo "== G3: what the task records =="
write_task task-no-worktree done - - fixture-org/proj "$PR1"
run "projects/demo/tasks/task-no-worktree.md"
assert "G3 no worktree recorded: exits 3 (nothing to do)" "$(eq "$RC" 3)"
assert "G3 no worktree recorded: says so"                 "$(has 'noop:.*records no .worktree')"

# A `worktree:` line in the BODY is not a record.
cat > "$TASKS/task-body-only.md" <<EOF
---
type: Task
title: fixture body-only
status: done
target_repo: fixture-org/proj
pr: [ $PR1 ]
timestamp: 2026-10-02T00:00:00Z
---

# Notes
worktree: $WT_STATUS
branch: okf/demo-status
EOF
run "projects/demo/tasks/task-body-only.md"
assert "G1 a worktree: line in the BODY is not a record" "$(eq "$RC" 3)"
assert "G1 …and that worktree survives"                  "$(yes_if test -d "$WT_STATUS")"

write_task task-no-branch done "$WT_STATUS" - fixture-org/proj "$PR1"
refusal "G3 no branch recorded" task-no-branch 'refuse:.*no .branch:' "$WT_STATUS"

echo "== G4: the path is one of ours =="
WT_OUT="$OUTSIDE/proj-demo-outside"
wt_pushed "$WT_OUT" okf/demo-outside
write_task task-outside done "$WT_OUT" okf/demo-outside fixture-org/proj "$PR1"
refusal "G4 outside the worktree roots" task-outside \
  'refuse:.*not inside this bundle.s worktree roots' "$WT_OUT"

write_task task-relative done "wt/relative" okf/x fixture-org/proj "$PR1"
refusal "G4 a relative path" task-relative 'refuse:.*not an absolute path' -

write_task task-dotdot done "$WTROOT/../wt/x" okf/x fixture-org/proj "$PR1"
refusal "G4 a path containing .." task-dotdot "refuse:.*contains" -

write_task task-gone done "$WTROOT/never-existed" okf/x fixture-org/proj "$PR1"
run "projects/demo/tasks/task-gone.md"
assert "G4 a recorded path that is gone: exits 3" "$(eq "$RC" 3)"
assert "G4 …and calls it already reclaimed"       "$(has 'noop:.*already reclaimed')"

write_task task-is-repo done "$REPO" main fixture-org/proj "$PR1"
refusal "G4 the repo itself" task-is-repo 'refuse:' -
assert "G4 the repo itself: repo survives" "$(yes_if test -e "$REPO/.git")"

echo "== G5: the expected repo comes from the task =="
WT_NOREPO="$WTROOT/proj-demo-norepo"
wt_pushed "$WT_NOREPO" okf/demo-norepo
write_task task-no-target done "$WT_NOREPO" okf/demo-norepo - "$PR1"
refusal "G5 no target_repo recorded" task-no-target 'refuse:.*no .target_repo:' "$WT_NOREPO"

write_task task-uncloned done "$WT_NOREPO" okf/demo-norepo fixture-org/absent "$PR1"
refusal "G5 target_repo not cloned" task-uncloned 'refuse:.*is not cloned' "$WT_NOREPO"

echo "== G6: a registered worktree of THAT repo =="
PLAIN="$WTROOT/plain-directory"
mkdir -p "$PLAIN"; printf 'somebody work\n' > "$PLAIN/leftover.txt"
write_task task-unregistered done "$PLAIN" okf/demo-plain fixture-org/proj "$PR1"
run "projects/demo/tasks/task-unregistered.md"
assert "G6 an unregistered directory: exits 1"  "$(eq "$RC" 1)"
assert "G6 an unregistered directory: says why" "$(has 'refuse:.*not a registered worktree')"
assert "G6 an unregistered directory: survives" "$(yes_if test -f "$PLAIN/leftover.txt")"

OTHER="$REPOS/other"
git init -q -b main "$OTHER"
git -C "$OTHER" config user.email fixture@example.com
git -C "$OTHER" config user.name Fixture
printf 'x\n' > "$OTHER/f.txt"; git -C "$OTHER" add f.txt; git -C "$OTHER" commit -qm c1
WT_WRONGREPO="$WTROOT/other-demo-wrongrepo"
git -C "$OTHER" worktree add -q "$WT_WRONGREPO" -b okf/demo-wrongrepo main >/dev/null
write_task task-wrong-repo done "$WT_WRONGREPO" okf/demo-wrongrepo fixture-org/proj "$PR1"
run "projects/demo/tasks/task-wrong-repo.md"
assert "G6 a worktree of another repo: exits 1"  "$(eq "$RC" 1)"
assert "G6 a worktree of another repo: says why" "$(has 'refuse:.*not a registered worktree')"
assert "G6 a worktree of another repo: survives" "$(yes_if test -d "$WT_WRONGREPO")"

echo "== G7: a lock is an explicit 'do not touch' =="
WT_LOCKED="$WTROOT/proj-demo-locked"
wt_pushed "$WT_LOCKED" okf/demo-locked
git -C "$REPO" worktree lock "$WT_LOCKED"
write_task task-locked done "$WT_LOCKED" okf/demo-locked fixture-org/proj "$PR1"
refusal "G7 locked" task-locked 'refuse:.*LOCKED' "$WT_LOCKED"

echo "== G8: detached, and branch identity =="
WT_DETACHED="$WTROOT/proj-demo-detached"
S_DETACHED="$(wt_detached "$WT_DETACHED")"
write_task task-detached done "$WT_DETACHED" okf/demo-detached fixture-org/proj "$PR1"
refusal "G8 detached HEAD" task-detached 'refuse:.*DETACHED HEAD' "$WT_DETACHED"
run "projects/demo/tasks/task-detached.md"
assert "G8 detached HEAD: offers the rescue command" "$(has "branch <name> $S_DETACHED")"
assert "G8 detached HEAD: its commit is still there" \
  "$(yes_if git -C "$REPO" cat-file -e "$S_DETACHED^{commit}")"

WT_RECYCLED="$WTROOT/proj-demo-recycled"
wt_pushed "$WT_RECYCLED" okf/demo-actual
write_task task-recycled done "$WT_RECYCLED" okf/demo-recorded fixture-org/proj "$PR1"
refusal "G8 branch mismatch (recycled path)" task-recycled 'refuse:.*but .*recorded' "$WT_RECYCLED"

echo "== G9: nothing uncommitted =="
WT_DIRTY="$WTROOT/proj-demo-dirty"
wt_pushed "$WT_DIRTY" okf/demo-dirty
printf 'local edit\n' >> "$WT_DIRTY/tracked.txt"
write_task task-dirty done "$WT_DIRTY" okf/demo-dirty fixture-org/proj "$PR1"
refusal "G9 a modified tracked file" task-dirty 'refuse:.*uncommitted changes' "$WT_DIRTY"

# What the PRUNER's name heuristic would call "scaffolding". The pruner may downgrade
# such a worktree to a report line; this script DELETES, so there is no allowance.
WT_SCAFF="$WTROOT/proj-demo-scaffolding"
wt_pushed "$WT_SCAFF" okf/demo-scaffolding
printf 'probe\n' > "$WT_SCAFF/probe-viewof.ts"
write_task task-scaffolding done "$WT_SCAFF" okf/demo-scaffolding fixture-org/proj "$PR1"
refusal "G9 untracked scaffolding is NOT an allowance" task-scaffolding \
  'refuse:.*uncommitted changes' "$WT_SCAFF"

echo "== G10: nothing unpushed =="
WT_UNPUSHED="$WTROOT/proj-demo-unpushed"
wt_pushed "$WT_UNPUSHED" okf/demo-unpushed
printf 'more\n' >> "$WT_UNPUSHED/feature.txt"
git -C "$WT_UNPUSHED" commit -qam 'a commit that was never pushed'
write_task task-unpushed done "$WT_UNPUSHED" okf/demo-unpushed fixture-org/proj "$PR1"
refusal "G10 an unpushed commit" task-unpushed \
  'refuse:.*commit\(s\) that no remote-tracking ref' "$WT_UNPUSHED"

echo "== G11: every recorded PR merged, checked BY URL =="
WT_PR="$WTROOT/proj-demo-pr"
wt_pushed "$WT_PR" okf/demo-pr
write_task task-pr-open done "$WT_PR" okf/demo-pr fixture-org/proj "$PR2"
refusal "G11 an open PR" task-pr-open 'refuse:.*is OPEN, not MERGED' "$WT_PR"

# THE HAZARD THIS TASK EXISTS FOR. prune-worktrees.sh reaches REMOVABLE on merged OR
# closed; delegating to that set would auto-delete the worktree of an ABANDONED PR,
# which is the one most likely to hold the only copy of unpushed work.
write_task task-pr-closed done "$WT_PR" okf/demo-pr fixture-org/proj "$PR_CLOSED"
refusal "G11 CLOSED-UNMERGED is never removed" task-pr-closed \
  'refuse:.*is CLOSED, not MERGED' "$WT_PR"
run "projects/demo/tasks/task-pr-closed.md"
assert "G11 …and the refusal names the hazard" "$(has 'CLOSED-UNMERGED is never')"

write_task task-pr-mixed done "$WT_PR" okf/demo-pr fixture-org/proj "$PR1" "$PR2"
refusal "G11 one of two PRs still open" task-pr-mixed 'refuse:.*is OPEN, not MERGED' "$WT_PR"
write_task task-pr-mixed-closed done "$WT_PR" okf/demo-pr fixture-org/proj "$PR1" "$PR_CLOSED"
refusal "G11 one of two PRs closed unmerged" task-pr-mixed-closed \
  'refuse:.*is CLOSED, not MERGED' "$WT_PR"

# `pr: [ ]` is a REFUSAL, not a vacuous pass: "every PR recorded is merged" is true of
# an empty list, so a task hand-set to done with no PR would otherwise authorise removal.
write_task task-pr-none done "$WT_PR" okf/demo-pr fixture-org/proj -
refusal "G11 an EMPTY pr: refuses (never vacuously true)" task-pr-none \
  'refuse:.*records no PR URL' "$WT_PR"
run "projects/demo/tasks/task-pr-none.md"
assert "G11 …and says an empty pr: establishes nothing" "$(has 'establishes nothing')"

write_task task-pr-other done "$WT_PR" okf/demo-pr fixture-org/proj "$PR_OTHER"
refusal "G11 the only merged PR is in another repo" task-pr-other 'refuse:.*belongs to' "$WT_PR"

write_task task-pr-unknown done "$WT_PR" okf/demo-pr fixture-org/proj \
  "https://github.com/fixture-org/proj/pull/404"
refusal "G11 gh cannot read the PR" task-pr-unknown 'refuse:.*could not read' "$WT_PR"

write_task task-pr-nogh done "$WT_PR" okf/demo-pr fixture-org/proj "$PR1"
STUB_PATH="$TMP/nogh:/usr/bin:/bin" run "projects/demo/tasks/task-pr-nogh.md"
assert "G11 no gh available: exits 1"  "$(eq "$RC" 1)"
assert "G11 no gh available: says why" "$(has 'refuse: gh is not available')"
assert "G11 no gh available: survives" "$(yes_if test -d "$WT_PR")"

echo "== G12: ignored content that is not a known cache =="
# `git worktree remove` does NOT refuse a tree whose only content is ignored. Asserted
# on this very git, so the guard is justified by measurement and not by a claim.
PROBE="$TMP/probe"; mkdir -p "$PROBE"
git init -q -b main "$PROBE/repo"
git -C "$PROBE/repo" config user.email fixture@example.com
git -C "$PROBE/repo" config user.name Fixture
printf '.env\n' > "$PROBE/repo/.gitignore"
git -C "$PROBE/repo" add .gitignore
git -C "$PROBE/repo" commit -qm c1
git -C "$PROBE/repo" worktree add -q "$PROBE/wt" -b probe >/dev/null
printf 'TOKEN=shape-only\n' > "$PROBE/wt/.env"
PROBE_ST="$(git -C "$PROBE/wt" status --porcelain)"
git -C "$PROBE/repo" worktree remove "$PROBE/wt" >/dev/null 2>&1
PROBE_RC=$?
assert "plain 'git worktree remove' does NOT see an ignored .env (status is empty)" \
  "$([ -z "$PROBE_ST" ] && echo 0 || echo 1)"
assert "…and removes the tree anyway, taking the .env with it" \
  "$([ "$PROBE_RC" -eq 0 ] && [ ! -e "$PROBE/wt" ] && echo 0 || echo 1)"

WT_ENV="$WTROOT/proj-demo-env"
wt_pushed "$WT_ENV" okf/demo-env
printf 'TOKEN=shape-only\n' > "$WT_ENV/.env"
write_task task-env done "$WT_ENV" okf/demo-env fixture-org/proj "$PR1"
assert "the .env fixture is invisible to git status (so only G12 can catch it)" \
  "$([ -z "$(git -C "$WT_ENV" status --porcelain)" ] && echo 0 || echo 1)"
refusal "G12 an ignored .env refuses" task-env 'refuse:.*IGNORED content' "$WT_ENV"
run "projects/demo/tasks/task-env.md"
assert "G12 …and names the file"      "$(has '\.env')"
assert "G12 …and the .env survives"   "$(yes_if test -f "$WT_ENV/.env")"

# THE MUTANT. A copy of the script with G12 deleted must DELETE this same worktree. If
# it does not, the assertion above proves nothing about the guard.
MUTANT="$TMP/reclaim-no-g12.sh"
awk '/^# --- G12:/ { skip=1 } /^# --- G13:/ { skip=0 } !skip' "$RECLAIM" > "$MUTANT"
ln -sf "$(dirname "$RECLAIM")/bundle-paths.sh" "$TMP/bundle-paths.sh"
ln -sf "$(dirname "$RECLAIM")/plugin-name.sh"  "$TMP/plugin-name.sh"
assert "the mutant really dropped G12"  \
  "$(no_if grep -q 'IGNORED content' "$MUTANT")"
assert "the mutant is still runnable"   "$(yes_if bash -n "$MUTANT")"
SCRIPT="$MUTANT"; run "projects/demo/tasks/task-env.md"; SCRIPT=""
assert "MUTANT without G12: exits 0 (would have removed it)" "$(eq "$RC" 0)"
assert "MUTANT without G12: the worktree and its .env are GONE" "$(no_if test -e "$WT_ENV")"

# A known cache is allowed through: a guard that refuses every real worktree is a guard
# nobody can ship.
WT_CACHE="$WTROOT/proj-demo-cache"
wt_pushed "$WT_CACHE" okf/demo-cache
mkdir -p "$WT_CACHE/node_modules/pkg" "$WT_CACHE/tmp"
printf 'x\n' > "$WT_CACHE/node_modules/pkg/index.js"
printf 'draft\n' > "$WT_CACHE/tmp/pr-body.md"
write_task task-cache done "$WT_CACHE" okf/demo-cache fixture-org/proj "$PR1"
run --dry-run "projects/demo/tasks/task-cache.md"
assert "G12 node_modules/ and tmp/ are a known cache: clears" "$(eq "$RC" 0)"
# …and the same tree refuses the moment a non-cache ignored file joins them.
printf 'TOKEN=shape-only\n' > "$WT_CACHE/.env"
run --dry-run "projects/demo/tasks/task-cache.md"
assert "G12 …and one .env beside them refuses"               "$(eq "$RC" 1)"
rm -f "$WT_CACHE/.env"

echo "== G13: nothing is running inside it =="
WT_LIVE="$WTROOT/proj-demo-live"
wt_pushed "$WT_LIVE" okf/demo-live
write_task task-live done "$WT_LIVE" okf/demo-live fixture-org/proj "$PR1"
# Bounded at the CHILD, per CONVENTIONS.md: the sibling watchdog fires whether or not
# this shell survives, and its stdio is redirected so a leftover sleep cannot hold the
# capture's pipe open.
( cd "$WT_LIVE" && exec sleep 45 ) & LIVE_PID=$!
( sleep 60; kill "$LIVE_PID" 2>/dev/null ) >/dev/null 2>&1 &
run --dry-run "projects/demo/tasks/task-live.md"
assert "G13 a live process inside it: exits 1" "$(eq "$RC" 1)"
assert "G13 …says a live process holds it"     "$(has 'refuse:.*live process')"
kill "$LIVE_PID" 2>/dev/null; wait "$LIVE_PID" 2>/dev/null
run --dry-run "projects/demo/tasks/task-live.md"
assert "G13 the process is what refused (the same fixture clears once it is gone)" \
  "$(eq "$RC" 0)"

echo "== blanket: the refusal matrix removed nothing =="
MATRIX_WT="$(git -C "$REPO" worktree list --porcelain | grep -c '^worktree ')"
assert "every fixture worktree is still registered" \
  "$([ "$MATRIX_WT" -ge 9 ] && echo 0 || echo 1)"
assert "no fixture directory was deleted by any refusal" \
  "$(yes_if test -d "$WT_STATUS" -a -d "$WT_LOCKED" -a -d "$WT_DETACHED" -a -d "$WT_DIRTY" \
       -a -d "$WT_UNPUSHED" -a -d "$WT_PR" -a -d "$WT_SCAFF" -a -d "$WT_RECYCLED" \
       -a -d "$WT_OUT" -a -d "$WT_CACHE" -a -d "$WT_LIVE")"
assert "no output mentions a synced path" \
  "$(grep -Eq 'Dropbox|iCloud|OneDrive' <<<"$OUT" && echo 1 || echo 0)"

echo "== the script passes no --force, anywhere =="
assert "no --force anywhere in reclaim-worktree.sh (0 hits, comments included)" \
  "$(no_if grep -q -- '--force' "$RECLAIM")"
assert "no -f flag on 'worktree remove'" "$(no_if grep -Eq 'worktree remove .*-f' "$RECLAIM")"

echo "== the positive case: a finished worktree is reclaimed =="
WT_GOOD="$WTROOT/proj-demo-good"
wt_pushed "$WT_GOOD" okf/demo-good
write_task task-good done "$WT_GOOD" okf/demo-good fixture-org/proj "$PR1"

run --dry-run "projects/demo/tasks/task-good.md"
assert "dry run: exits 0 (every guard passed)" "$(eq "$RC" 0)"
assert "dry run: says it WOULD remove"         "$(has 'would remove: ')"
assert "dry run: removed nothing"              "$(yes_if test -d "$WT_GOOD")"
assert "dry run: still registered"             "$(yes_if registered "$WT_GOOD")"

run "projects/demo/tasks/task-good.md"
assert "removal: exits 0"                      "$(eq "$RC" 0)"
assert "removal: reports the path and branch"  "$(has "removed: $WT_GOOD  \[okf/demo-good\]")"
assert "removal: the directory is gone"        "$(no_if test -d "$WT_GOOD")"
assert "removal: it is deregistered"           "$(no_if registered "$WT_GOOD")"
# The branch ref surviving is why a mis-identification costs a checkout and never work.
assert "removal: the branch ref survives" \
  "$(yes_if git -C "$REPO" show-ref --verify --quiet refs/heads/okf/demo-good)"
assert "removal: the commit survives" \
  "$(yes_if git -C "$REPO" cat-file -e "okf/demo-good^{commit}")"
assert "removal: no other worktree went with it" "$(yes_if test -d "$WT_STATUS")"

run "projects/demo/tasks/task-good.md"
assert "a repeat run: exits 3 (nothing to do)"  "$(eq "$RC" 3)"
assert "a repeat run: says already reclaimed"   "$(has 'noop:.*already reclaimed')"

echo "== usage / environment =="
run
assert "no task path: exits 2"        "$(eq "$RC" 2)"
run --bogus "projects/demo/tasks/task-no-worktree.md"
assert "an unknown option: exits 2"   "$(eq "$RC" 2)"
run "projects/demo/tasks/absent.md"
assert "a missing task doc: exits 2"  "$(eq "$RC" 2)"
OUTSIDE_RC=0
OUT="$( cd "$TMP" && bash "$RECLAIM" "instance/projects/demo/tasks/task-no-worktree.md" 2>&1 )" \
  || OUTSIDE_RC=$?
assert "run outside a bundle root: exits 2" "$(eq "$OUTSIDE_RC" 2)"

# The hole a review found once: the prefix strip left `rel` absolute for a path outside
# the bundle, and every later guard then read an attacker-chosen file.
EXT="$TMP/external"; mkdir -p "$EXT"
cp "$TASKS/task-no-branch.md" "$EXT/stolen.md"
run "$EXT/stolen.md"
assert "G1 an external task path: exits 2"  "$(eq "$RC" 2)"
assert "G1 …and says why"                   "$(has 'not a task document of this bundle')"
run "projects/demo/tasks/task-no-branch.md"
assert "G1 the in-place task is NOT refused for location" \
  "$(grep -q 'not a task document of this bundle' <<<"$OUT" && echo 1 || echo 0)"

echo "== worktreeRoot absent: the legacy <reposRoot>/_wt root =="
mkdir -p "$REPOS/_wt"
WT_LEGACY="$REPOS/_wt/proj-demo-legacy"
wt_pushed "$WT_LEGACY" okf/demo-legacy
write_task task-legacy done "$WT_LEGACY" okf/demo-legacy fixture-org/proj "$PR1"
cat > "$INSTANCE/instance.config.json" <<JSON
{ "reposRoot": "$REPOS", "authorEmail": "fixture@example.com" }
JSON
run --dry-run "projects/demo/tasks/task-legacy.md"
assert "a legacy-root worktree is accepted with no worktreeRoot key" "$(eq "$RC" 0)"
write_task task-live-legacycfg done "$WT_LIVE" okf/demo-live fixture-org/proj "$PR1"
run --dry-run "projects/demo/tasks/task-live-legacycfg.md"
assert "with no worktreeRoot, a path under the unconfigured root is refused" "$(eq "$RC" 1)"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
