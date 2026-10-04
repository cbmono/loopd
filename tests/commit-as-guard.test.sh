#!/usr/bin/env bash
# Exercises the autonomy-aware draft->ready guard in commit-as.sh.
#
# Delegation requires AUTONOMY.md at the repo root (the capability file). setup()
# creates it; the "capability absent" cases delete it to prove the guard gates on
# presence, not just on the autonomy field.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/commit-as.sh"
TMP="$(mktemp -d)" || {
  echo "commit-as-guard.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# NO COMPANION PLUGIN MAY ANSWER FOR THIS FIXTURE. The guard now resolves AUTONOMY.md via
# `resolve-autonomy.sh` — bundle root first, else an installed companion — so the
# "capability absent" cases below would otherwise be decided by whatever the developer
# happens to have installed rather than by the fixture. An empty config dir means an
# absent registry, which is the gated answer. Every assertion in this file is unchanged.
export CLAUDE_CONFIG_DIR="$TMP/no-plugins"
mkdir -p "$CLAUDE_CONFIG_DIR"

pass=0; fail=0

setup() {
  rm -rf "$TMP/repo"; mkdir -p "$TMP/repo"; cd "$TMP/repo" || exit 1
  git init -q .; git config user.email "t@example.com"; git config user.name "Test Human"
  printf '{ "authorEmail": "t@example.com" }\n' > instance.config.json
  # The capability file: without it every autonomy value is inert (see commit-as.sh).
  printf -- '---\ntype: Reference\n---\n# Delegated authority\n' > AUTONOMY.md
  mkdir -p projects/delegated-proj/tasks projects/gated-proj/tasks projects/noauto-proj/tasks projects/other-proj/tasks
  # `yolo` is the ONE mode AUTONOMY.md defines; other-proj carries an invented token
  # to pin the closed set — the guard must fail closed on a word nothing defines.
  printf 'type: Project\nautonomy: yolo\nstatus: active\n' > projects/delegated-proj/project.md
  printf 'type: Project\nautonomy: somefuturemode\nstatus: active\n' > projects/other-proj/project.md
  printf 'type: Project\nautonomy: gated\nstatus: active\n' > projects/gated-proj/project.md
  printf 'type: Project\nstatus: active\n' > projects/noauto-proj/project.md
  git add -A >/dev/null; git commit -qm init
}

task() { # <path> <kind> <status>
  printf 'type: Task\nkind: %s\nstatus: %s\n' "$2" "$3" > "$1"
}

check() { # <name> <expected: allow|block> <role> <files-to-stage...>
  local name="$1" expect="$2" role="$3"; shift 3
  git add "$@" >/dev/null
  local out rc
  # Commit the same paths that were staged: the shared-index guard requires a
  # non-human role to name what it commits, and this is the form agents use.
  out="$("$SCRIPT" "$role" "test: $name" -- "$@" 2>&1)"; rc=$?
  local got; if [ "$rc" -eq 0 ]; then got=allow; else got=block; fi
  if [ "$got" = "$expect" ]; then
    printf '  PASS  %-52s (%s, rc=%s)\n' "$name" "$got" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-52s expected %s got %s (rc=%s)\n' "$name" "$expect" "$got" "$rc"
    printf '        output: %s\n' "$(head -4 <<<"$out" | tr '\n' '|')"
    fail=$((fail+1))
  fi
  git reset -q --hard HEAD >/dev/null 2>&1 || true
}

echo "== autonomy-aware draft->ready guard =="

setup; task projects/delegated-proj/tasks/t1.md build ready
check "delegated + build -> loop may promote" allow project-manager projects/delegated-proj/tasks/t1.md

setup; task projects/gated-proj/tasks/t1.md build ready
check "gated + build -> blocked" block project-manager projects/gated-proj/tasks/t1.md

setup; task projects/delegated-proj/tasks/t1.md research ready
check "delegated + research -> blocked (human-driven)" block project-manager projects/delegated-proj/tasks/t1.md

setup; task projects/noauto-proj/tasks/t1.md build ready
check "no autonomy field -> defaults gated, blocked" block project-manager projects/noauto-proj/tasks/t1.md

setup; task projects/gated-proj/tasks/t1.md build ready
check "human may always promote" allow human projects/gated-proj/tasks/t1.md

setup; task projects/gated-proj/tasks/t1.md build draft
check "no status:ready staged -> untouched" allow project-manager projects/gated-proj/tasks/t1.md

setup; task projects/delegated-proj/tasks/t1.md build ready; task projects/gated-proj/tasks/t2.md build ready
check "mixed batch -> blocked on the gated one" block project-manager projects/delegated-proj/tasks/t1.md projects/gated-proj/tasks/t2.md

setup; printf 'type: Task\nkind: build\nstatus: ready\n' > projects/delegated-proj/tasks/t1.md
git add projects/delegated-proj/tasks/t1.md >/dev/null
git commit -q --author="project-manager <t@example.com>" -m seed >/dev/null
printf 'type: Task\nkind: build\nstatus: in-progress\n' > projects/delegated-proj/tasks/t1.md
check "ready -> in-progress (not an added ready line)" allow project-manager projects/delegated-proj/tasks/t1.md

setup; task "projects/delegated-proj/tasks/task with spaces.md" build ready
check "path with spaces, delegated+build" allow project-manager "projects/delegated-proj/tasks/task with spaces.md"

setup; task "projects/gated-proj/tasks/task with spaces.md" build ready
check "path with spaces, gated -> blocked" block project-manager "projects/gated-proj/tasks/task with spaces.md"

setup; task projects/delegated-proj/tasks/t1.md unset-kind ready
sed -i.bak '/^kind:/d' projects/delegated-proj/tasks/t1.md; rm -f projects/delegated-proj/tasks/t1.md.bak
check "delegated but kind missing -> blocked (fail closed)" block project-manager projects/delegated-proj/tasks/t1.md

setup
sed -i.bak 's/^autonomy: yolo$/autonomy: yolo unexpected/' projects/delegated-proj/project.md; rm -f projects/delegated-proj/project.md.bak
git add projects/delegated-proj/project.md >/dev/null; git commit -qm "malformed autonomy" >/dev/null
task projects/delegated-proj/tasks/t1.md build ready
check "malformed autonomy value -> blocked (fail closed)" block project-manager projects/delegated-proj/tasks/t1.md

# --- the capability file is the on/off switch -------------------------------
setup; rm -f AUTONOMY.md; task projects/delegated-proj/tasks/t1.md build ready
check "no AUTONOMY.md -> delegated project still blocked" block project-manager projects/delegated-proj/tasks/t1.md

setup; rm -f AUTONOMY.md; task projects/gated-proj/tasks/t1.md build draft
check "no AUTONOMY.md, no promotion staged -> untouched" allow project-manager projects/gated-proj/tasks/t1.md

# The mode set is CLOSED: AUTONOMY.md defines exactly one mode ('yolo'), so a token
# nothing defines must fail closed — an earlier version cleared any non-gated value,
# which delegated the human's gate to a typo (audit 2026-08-31, S2).
setup; task projects/other-proj/tasks/t1.md build ready
check "AUTONOMY.md + undefined mode -> blocked (closed set)" block project-manager projects/other-proj/tasks/t1.md

setup; rm -f AUTONOMY.md; task projects/other-proj/tasks/t1.md build ready
check "undefined mode and no AUTONOMY.md -> blocked" block project-manager projects/other-proj/tasks/t1.md

echo
echo "== the delegation must PRE-DATE the commit that uses it =="

# The self-escalation shape: one commit flips autonomy AND promotes on the strength
# of the flip. AUTONOMY.md's "no agent raises autonomy" gets its reader here.
setup
printf 'type: Project\nautonomy: yolo\nstatus: active\n' > projects/gated-proj/project.md
task projects/gated-proj/tasks/t1.md build ready
check "same-commit autonomy flip + promotion -> blocked" block project-manager \
  projects/gated-proj/project.md projects/gated-proj/tasks/t1.md

# A project BORN in the promoting commit is the same shape: its autonomy line is new.
setup
mkdir -p projects/new-proj/tasks
printf 'type: Project\nautonomy: yolo\nstatus: active\n' > projects/new-proj/project.md
task projects/new-proj/tasks/t1.md build ready
check "new project.md + promotion in one commit -> blocked" block project-manager \
  projects/new-proj/project.md projects/new-proj/tasks/t1.md

# The allow half (load-bearing): a project.md edit that does NOT touch autonomy must
# not poison the promotion — the refusal is about the autonomy line, not the file.
setup
printf 'type: Project\nautonomy: yolo\nstatus: paused\n' > projects/delegated-proj/project.md
task projects/delegated-proj/tasks/t1.md build ready
check "project.md edited (not autonomy) + promotion -> allowed" allow project-manager \
  projects/delegated-proj/project.md projects/delegated-proj/tasks/t1.md

# And the sanctioned two-step: the autonomy change lands FIRST (the human's edit),
# the promotion rides the next commit — the first check() above already proves the
# second half; this proves the first half commits cleanly as human.
setup
printf 'type: Project\nautonomy: yolo\nstatus: active\n' > projects/gated-proj/project.md
check "the autonomy flip alone, as human -> allowed" allow human projects/gated-proj/project.md

echo
echo "== shared-index guard: an agent must name what it commits =="

# raw() runs the script with arbitrary trailing args (check() always appends
# pathspecs, which is exactly what these cases need to vary).
raw() { # <name> <expected: allow|block> <role> [args...]
  local name="$1" expect="$2" role="$3"; shift 3
  local out rc
  out="$("$SCRIPT" "$role" "test: $name" "$@" 2>&1)"; rc=$?
  local got; if [ "$rc" -eq 0 ]; then got=allow; else got=block; fi
  if [ "$got" = "$expect" ]; then
    printf '  PASS  %-52s (%s, rc=%s)\n' "$name" "$got" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-52s expected %s got %s (rc=%s)\n' "$name" "$expect" "$got" "$rc"
    printf '        output: %s\n' "$(head -4 <<<"$out" | tr '\n' '|')"
    fail=$((fail+1))
  fi
}

setup; task projects/gated-proj/tasks/t1.md build draft; git add projects/gated-proj/tasks/t1.md >/dev/null
raw "agent role, no paths, no --all-staged -> blocked" block project-manager

setup; task projects/gated-proj/tasks/t1.md build draft; git add projects/gated-proj/tasks/t1.md >/dev/null
raw "agent role + --all-staged -> allowed (explicit opt-out)" allow project-manager --all-staged

setup; task projects/gated-proj/tasks/t1.md build draft; git add projects/gated-proj/tasks/t1.md >/dev/null
raw "human is exempt from naming paths" allow human

setup; task projects/gated-proj/tasks/t1.md build draft; git add projects/gated-proj/tasks/t1.md >/dev/null
raw "'--' with no paths after it -> usage error" block project-manager --

setup; task projects/gated-proj/tasks/t1.md build draft; git add projects/gated-proj/tasks/t1.md >/dev/null
raw "--all-staged AND paths -> refused as ambiguous" block project-manager --all-staged -- projects/gated-proj/tasks/t1.md

# The actual bug this guard exists to prevent: agent A commits its own file while
# agent B has an unrelated file staged in the same shared working tree. A's commit
# must contain ONLY A's file, and B's must still be staged afterwards.
setup
printf 'mine\n' > mine.txt; printf 'sibling in progress\n' > sibling.txt
git add mine.txt sibling.txt >/dev/null
if "$SCRIPT" software-engineer "test: commit only my own path" -- mine.txt >/dev/null 2>&1; then
  committed="$(git show --name-only --format= HEAD | tr -d ' ')"
  still_staged="$(git diff --cached --name-only)"
  if [ "$committed" = "mine.txt" ] && [ "$still_staged" = "sibling.txt" ]; then
    printf '  PASS  %-52s (committed=%s, still staged=%s)\n' \
      "sibling's staged file is NOT swept in" "$committed" "$still_staged"; pass=$((pass+1))
  else
    printf '  FAIL  %-52s committed=[%s] still_staged=[%s]\n' \
      "sibling's staged file is NOT swept in" "$committed" "$still_staged"; fail=$((fail+1))
  fi
else
  printf '  FAIL  %-52s script exited non-zero\n' "sibling's staged file is NOT swept in"; fail=$((fail+1))
fi

# Pathspec scoping of the promotion guard: a sibling's staged promotion into a
# GATED project must not block an agent committing an unrelated path of its own.
setup
task projects/gated-proj/tasks/sibling.md build ready      # sibling's illegal promotion
printf 'mine\n' > mine.txt
git add projects/gated-proj/tasks/sibling.md mine.txt >/dev/null
raw "sibling's staged promotion does not block my paths" allow project-manager -- mine.txt

# ...but the same promotion inside MY pathspec is still refused.
setup
task projects/gated-proj/tasks/t1.md build ready
git add projects/gated-proj/tasks/t1.md >/dev/null
raw "promotion inside my own pathspec is still blocked" block project-manager -- projects/gated-proj/tasks/t1.md

echo
echo "== named paths commit the STAGED blob, not the working tree =="

# `git commit -- <paths>` (git's pathspec form) would commit the working-tree
# content of each named path, silently replacing what was staged. These cases pin
# the staged blob as the thing that lands.
eq() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf '  PASS  %-52s (%s)\n' "$1" "$3"; pass=$((pass+1))
  else
    printf '  FAIL  %-52s expected [%s] got [%s]\n' "$1" "$2" "$3"; fail=$((fail+1))
  fi
}

setup
printf 'staged\n' > mine.txt; git add mine.txt >/dev/null
printf 'working-tree\n' > mine.txt          # drifts AFTER the add
"$SCRIPT" software-engineer "test: staged blob wins" -- mine.txt >/dev/null 2>&1
eq "committed content is the staged version" "staged" "$(git show HEAD:mine.txt)"
eq "the later working-tree edit stays uncommitted" " M mine.txt" "$(git status --short mine.txt)"

# The security case: the promotion gate must judge the blob that lands. A gated
# `status: ready` in the working tree must not slip past a `draft` index.
setup
task projects/gated-proj/tasks/t1.md build draft
git add projects/gated-proj/tasks/t1.md >/dev/null
task projects/gated-proj/tasks/t1.md build ready    # working tree only, not staged
"$SCRIPT" project-manager "test: gate judges the committed blob" \
  -- projects/gated-proj/tasks/t1.md >/dev/null 2>&1
eq "unstaged 'ready' cannot ride in past the gate" \
  "status: draft" "$(git show HEAD:projects/gated-proj/tasks/t1.md | grep '^status:')"

# The close-project flow: a whole project directory staged for removal.
setup
git rm -qr projects/gated-proj >/dev/null
raw "staged directory removal commits as a deletion" allow project-manager -- projects/gated-proj
eq "the removed directory is gone from HEAD" \
  "" "$(git ls-tree -r --name-only HEAD -- projects/gated-proj)"

# A forgotten `git add` is a caller error worth naming: git's own message would
# describe the shared working tree instead, which is confusing here.
setup
printf 'edited but never staged\n' > mine.txt
raw "nothing staged under the named paths -> refused" block project-manager -- mine.txt

echo
echo "== --stage: the documented one-command form =="

# The six skill call sites document `commit-as.sh <role> "<msg>" -- <paths>` as ONE
# command; without --stage the caller has to `git add` first or take the exit-4 refusal
# above. --stage closes that gap and must not widen the selected index by a single path.

rc_of() { # <name> <expected-rc> <role> [args...]
  local name="$1" want="$2" role="$3"; shift 3
  local out rc
  out="$("$SCRIPT" "$role" "test: $name" "$@" 2>&1)"; rc=$?
  LAST_OUT="$out"
  if [ "$rc" -eq "$want" ]; then
    printf '  PASS  %-52s (rc=%s)\n' "$name" "$rc"; pass=$((pass+1))
  else
    printf '  FAIL  %-52s expected rc=%s got rc=%s\n' "$name" "$want" "$rc"
    printf '        output: %s\n' "$(head -4 <<<"$out" | tr '\n' '|')"
    fail=$((fail+1))
  fi
}

said() { # <name> <substring> — against the previous rc_of()'s output
  if grep -Fq -- "$2" <<<"$LAST_OUT"; then
    printf '  PASS  %-52s\n' "$1"; pass=$((pass+1))
  else
    printf '  FAIL  %-52s missing [%s] in: %s\n' "$1" "$2" \
      "$(head -4 <<<"$LAST_OUT" | tr '\n' '|')"; fail=$((fail+1))
  fi
}

# 1. It commits a path that was never `git add`ed — the papercut this flag closes.
setup
printf 'never staged\n' > mine.txt
rc_of "--stage commits an unstaged named path" 0 software-engineer --stage -- mine.txt
eq "…and its content is in HEAD" "never staged" "$(git show HEAD:mine.txt 2>/dev/null)"

# 2. A sibling agent's files — one staged, one not — are outside the pathspec, so
#    neither may ride along. This is the guarantee --stage is not allowed to weaken.
setup
printf 'mine\n' > mine.txt
printf 'sibling staged\n' > sib-staged.txt; git add sib-staged.txt >/dev/null
printf 'sibling unstaged\n' > sib-dirty.txt
rc_of "--stage with a sibling's files around it" 0 software-engineer --stage -- mine.txt
eq "…commits only the named path" "mine.txt" \
   "$(git show --name-only --format= HEAD | tr -d ' ')"
eq "…the sibling's staged file is still staged" "sib-staged.txt" \
   "$(git diff --cached --name-only)"
eq "…the sibling's unstaged file is still untracked" "?? sib-dirty.txt" \
   "$(git status --short sib-dirty.txt)"

# 3. Nothing to stage when the whole index is being committed.
setup
printf 'mine\n' > mine.txt; git add mine.txt >/dev/null
rc_of "--stage plus --all-staged -> refused" 2 software-engineer --stage --all-staged
said "…saying there is nothing for it to do" "nothing for it to do"
rc_of "--stage with no paths -> refused" 2 software-engineer --stage

# 4. WITHOUT the flag, nothing moved: the same unstaged path is still exit 4, and the
#    refusal now names the one-command form.
setup
printf 'never staged\n' > mine.txt
rc_of "no flag: an unstaged named path is still exit 4" 4 software-engineer -- mine.txt
said "…still saying nothing is staged"  "nothing staged under the named path(s)"
said "…and now naming --stage"          "--stage -- <path>..."
eq "…and nothing was committed" "" "$(git show --name-only --format= HEAD | grep mine.txt || true)"

# 5. The close-project step 7 shape: a directory `git rm -r`d, then an edit, one command.
#    rm -rf drops setup's untracked empty tasks/, which `git add` would otherwise match.
setup
git rm -qr projects/gated-proj >/dev/null; rm -rf projects/gated-proj
printf 'type: Project\nstatus: done\n' > projects/noauto-proj/project.md
printf 'sibling unstaged\n' > sib-dirty.txt
rc_of "--stage names a git-rm'd dir and an edit" 0 project-manager \
  --stage -- projects/gated-proj projects/noauto-proj/project.md
eq "…the removed directory is gone from HEAD" \
  "" "$(git ls-tree -r --name-only HEAD -- projects/gated-proj)"
eq "…and the edit landed" "status: done" \
  "$(git show HEAD:projects/noauto-proj/project.md | grep '^status:')"
eq "…and nothing unnamed rode along" \
  "projects/gated-proj/project.md projects/noauto-proj/project.md" \
  "$(git show --name-only --format= HEAD | tr '\n' ' ' | sed 's/ *$//')"

# 6. A path that never existed has no staged deletion to vouch for it: still exit 3.
setup
printf 'mine\n' > mine.txt
rc_of "--stage with a typo'd path -> exit 3" 3 software-engineer --stage -- mine.txt no-such-dir
said "…saying it could not stage" "could not stage the named path(s)"

echo
echo "== the nothing-staged guard is PER PATH, not all-or-nothing =="

# One staged path used to satisfy the whole guard: the commit succeeded, the other
# named paths were silently dropped, and the caller was told it worked.

not_said() { # <name> <substring> — against the previous rc_of()'s output
  if grep -Fq -- "$2" <<<"$LAST_OUT"; then
    printf '  FAIL  %-52s named [%s] but it was staged\n' "$1" "$2"; fail=$((fail+1))
  else
    printf '  PASS  %-52s\n' "$1"; pass=$((pass+1))
  fi
}

setup
printf 'staged\n' > a.txt; git add a.txt >/dev/null
printf 'never staged\n' > b.txt
printf 'never staged\n' > c.txt
rc_of "1 of 3 named paths staged -> exit 4" 4 software-engineer -- a.txt b.txt c.txt
said     "…naming the unstaged b.txt"  "b.txt"
said     "…naming the unstaged c.txt"  "c.txt"
not_said "…and NOT the staged a.txt"   "a.txt"
eq "…and nothing was committed" "" \
   "$(git show --name-only --format= HEAD | grep -E '^[abc]\.txt$' || true)"
eq "…a.txt is still staged for the caller to retry" "a.txt" "$(git diff --cached --name-only)"

setup
printf 'a\n' > a.txt; printf 'b\n' > b.txt; printf 'c\n' > c.txt
git add a.txt b.txt c.txt >/dev/null
rc_of "all 3 named paths staged -> commits" 0 software-engineer -- a.txt b.txt c.txt
eq "…and all three land" "a.txt b.txt c.txt" \
   "$(git show --name-only --format= HEAD | tr '\n' ' ' | sed 's/ *$//')"

# A path staged for DELETION carries a staged change like any other.
setup
printf 'a\n' > a.txt; git add a.txt >/dev/null; git commit -qm "seed a" >/dev/null
git rm -q a.txt >/dev/null
printf 'staged\n' > b.txt; git add b.txt >/dev/null
rc_of "a staged deletion counts as staged" 0 software-engineer -- a.txt b.txt

echo
echo "== a knowledge/ commit is not refused over the index the script injects =="

# commit-as.sh rebuilds knowledge/index.md and appends it to its own path list. That
# path used to be judged by the guard above, so an edit leaving the derived index
# unchanged — the normal case — was refused naming a path the caller never passed.

BUILD_KB="$(dirname "$SCRIPT")/build-kb-index.sh"

finding() { # <path> <lesson> <body>
  printf -- '---\ntype: Finding\nstatus: current\ntitle: Fixture finding\nlesson: %s\n---\n# Fixture finding\n\n%s\n' \
    "$2" "$3" > "$1"
}

setup_kb() {
  setup
  mkdir -p knowledge/findings
  finding knowledge/findings/f1.md "the lesson" "original body"
  bash "$BUILD_KB" >/dev/null 2>&1
  git add knowledge >/dev/null; git commit -qm "seed knowledge" >/dev/null
}

# 1. The reported reproduction: a body-only edit derives no new index row.
setup_kb
finding knowledge/findings/f1.md "the lesson" "body rewritten, no derived field touched"
rc_of "body-only knowledge edit commits" 0 human --stage -- knowledge/findings/f1.md
eq "…and the commit carries exactly the named file" "knowledge/findings/f1.md" \
   "$(git show --name-only --format= HEAD | tr '\n' ' ' | sed 's/ *$//')"

# 2. The guard is kept for what the CALLER named, in the same fixture shape.
setup_kb
finding knowledge/findings/f1.md "the lesson" "edited but never staged"
rc_of "unstaged knowledge path is still exit 4" 4 human -- knowledge/findings/f1.md
said     "…naming the caller's own path" "knowledge/findings/f1.md"
not_said "…and NOT the injected index"   "knowledge/index.md"

# 3. The injected index still lands when the rebuild does move it.
setup_kb
finding knowledge/findings/f1.md "a new lesson the index derives" "body"
rc_of "index moves -> it is committed too" 0 human --stage -- knowledge/findings/f1.md
eq "…and knowledge/index.md is in the commit" "knowledge/index.md" \
   "$(git show --name-only --format= HEAD | grep '^knowledge/index\.md$' || true)"

# 4. Outside knowledge/ the rebuild branch never fires: a deliberately stale index
#    stays stale, and nothing of it reaches the commit.
setup_kb
printf 'stale, and nothing here may regenerate it\n' > knowledge/index.md
printf 'mine\n' > mine.txt
rc_of "a non-knowledge commit leaves the index alone" 0 software-engineer --stage -- mine.txt
eq "…committing only the named path" "mine.txt" \
   "$(git show --name-only --format= HEAD | tr '\n' ' ' | sed 's/ *$//')"
eq "…and the stale index was never rebuilt" "stale, and nothing here may regenerate it" \
   "$(cat knowledge/index.md)"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
