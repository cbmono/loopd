#!/usr/bin/env bash
#
# Exercises plugin/scripts/migrate-bundle.sh. The properties that matter most are
# the negative ones: the default run must change nothing on disk, a missing timestamp
# git cannot date must NOT be invented, and a dangling reference must be reported
# rather than rewritten — that decision belongs to /close-project step 6, where the
# task it points at is still readable.
#
# assert() follows the convention of the other harnesses here: 0 is a PASS.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MIGRATE="$HERE/../plugin/scripts/migrate-bundle.sh"
VALIDATE="$HERE/../plugin/scripts/validate-bundle.sh"
[[ -f "$MIGRATE" ]] || { echo "migrate-bundle.test: not found at $MIGRATE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/migrate-bundle-fixture.XXXXXX")" || {
  echo "migrate-bundle.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
B="$TMP/bundle"
mkdir -p "$B"/{objectives,knowledge/findings,knowledge/services}
mkdir -p "$B"/projects/live/tasks
cd "$B"

echo '{ "org": "x", "reposRoot": "/tmp" }' > instance.config.json
echo '# Schema' > SCHEMA.md
TS="2026-01-01T00:00:00Z"

doc() { local p="$1"; shift; mkdir -p "$(dirname "$p")"; printf '%s\n' "$@" > "$p"; }

doc objectives/o.md '---' 'type: Objective' 'title: O' 'status: active' "timestamp: $TS" '---' 'body'
doc projects/live/project.md '---' 'type: Project' 'title: L' 'status: active' "timestamp: $TS" '---' 'body'
# valid, must not be touched
doc knowledge/findings/ok.md '---' 'type: Finding' 'title: OK' 'status: current' 'provenance: human' "timestamp: $TS" '---' 'body'
doc knowledge/services/ok.md '---' 'type: Service' 'title: OK' 'status: active' 'provenance: human' "timestamp: $TS" '---' 'body'
# mechanical fixes
doc knowledge/findings/open.md '---' 'type: Finding' 'title: F1' 'status: open' "timestamp: $TS" '---' 'body'
doc knowledge/findings/active.md '---' 'type: Finding' 'title: F2' 'status: active' "timestamp: $TS" '---' 'body'
doc knowledge/findings/nostatus.md '---' 'type: Finding' 'title: F3' "timestamp: $TS" '---' 'body'
doc knowledge/services/current.md '---' 'type: Service' 'title: S1' 'status: current' "timestamp: $TS" '---' 'body'
# NOT a mapping the script knows: it carries a meaning the script cannot read, so it
# must be reported and left alone rather than normalised into a fixed value.
doc knowledge/findings/unsupported.md '---' 'type: Finding' 'title: F5' 'status: wibble' "timestamp: $TS" '---' 'body'
doc knowledge/services/unsupported.md '---' 'type: Service' 'title: S2' 'status: retired' "timestamp: $TS" '---' 'body'
# Frontmatter that opens and never closes. add_field inserts before the SECOND
# delimiter, so with only one it silently no-ops — and the script once printed FIXED
# for that non-write, on a real bundle. A false success is worse than the error it
# claims to fix, so this is a regression test, not a hypothetical.
doc projects/live/tasks/task-003-unterminated.md '---' 'type: Task' 'title: T3' 'status: draft' 'body, no closing delimiter'
# timestamp from git
doc projects/live/tasks/task-001-nots.md '---' 'type: Task' 'title: T1' 'status: draft' '---' 'body'
# dangling ref — must be reported, never rewritten
doc projects/live/tasks/task-002-dangling.md '---' 'type: Task' 'title: T2' 'status: draft' \
  'depends_on: [ /projects/gone/tasks/task-009.md ]' "timestamp: $TS" '---' 'body'

git init -q -b main . && git add -A && git -c user.email=a@b -c user.name=a commit -qm init

# untracked after the commit: git cannot date it, so it must be SKIPPED not invented
doc knowledge/findings/untracked-nots.md '---' 'type: Finding' 'title: F4' 'status: current' '---' 'body'

pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }

# A distinctive mode, to catch a repair that silently rewrites permissions.
chmod 664 knowledge/findings/open.md
MODE_BEFORE="$(stat -f '%Lp' knowledge/findings/open.md 2>/dev/null || stat -c '%a' knowledge/findings/open.md)"

BEFORE="$(find . -name '*.md' -exec shasum {} \; | sort)"
DRY="$(bash "$MIGRATE" 2>&1)"
AFTER_DRY="$(find . -name '*.md' -exec shasum {} \; | sort)"

echo "== the default run reports and changes nothing =="
assert "no file changed by a default run" "$([[ "$BEFORE" == "$AFTER_DRY" ]] && echo 0 || echo 1)"
assert "output says report only"          "$(printf '%s' "$DRY" | grep -q 'report only' && echo 0 || echo 1)"
assert "uses WOULD FIX, not FIXED"        "$(printf '%s' "$DRY" | grep -q 'WOULD FIX' && echo 0 || echo 1)"

echo "== each mechanical class is recognised =="
assert "Finding open -> current"      "$(printf '%s' "$DRY" | grep -q "Finding status 'open' -> current" && echo 0 || echo 1)"
assert "Finding active -> current"    "$(printf '%s' "$DRY" | grep -q "Finding status 'active' -> current" && echo 0 || echo 1)"
assert "Finding with no status"       "$(printf '%s' "$DRY" | grep -q 'Finding has no status' && echo 0 || echo 1)"
assert "Service current -> active"    "$(printf '%s' "$DRY" | grep -q "Service status 'current' -> active" && echo 0 || echo 1)"
assert "missing timestamp from git"   "$(printf '%s' "$DRY" | grep -q 'author date of the commit' && echo 0 || echo 1)"

echo "== an unestablished status is reported, never normalised =="
assert "an unknown Finding status is held for a human" \
  "$(printf '%s' "$DRY" | grep -q "Finding status 'wibble' is not a mapping" && echo 0 || echo 1)"
assert "an unknown Service status is held for a human" \
  "$(printf '%s' "$DRY" | grep -q "Service status 'retired' is not a mapping" && echo 0 || echo 1)"

echo "== an unterminated frontmatter block is skipped, never falsely fixed =="
assert "unterminated frontmatter is SKIPPED" \
  "$(printf '%s' "$DRY" | grep -q 'opens but never closes' && echo 0 || echo 1)"
assert "it is never reported as a fix" \
  "$(printf '%s' "$DRY" | grep -A1 'task-003-unterminated' | grep -qE 'WOULD FIX|FIXED' && echo 1 || echo 0)"

echo "== the refusals =="
assert "a date git cannot supply is SKIPPED, not invented" \
  "$(printf '%s' "$DRY" | grep -q 'refusing to invent a date' && echo 0 || echo 1)"
assert "a dangling ref is left to a human"  "$(printf '%s' "$DRY" | grep -q 'HUMAN' && echo 0 || echo 1)"
assert "the dangling ref names /close-project step 6" \
  "$(printf '%s' "$DRY" | grep -q 'close-project step 6' && echo 0 || echo 1)"

echo "== valid documents are not mentioned =="
assert "knowledge/findings/ok.md untouched"  "$(printf '%s' "$DRY" | grep -q 'findings/ok.md' && echo 1 || echo 0)"
assert "knowledge/services/ok.md untouched" "$(printf '%s' "$DRY" | grep -q 'services/ok.md' && echo 1 || echo 0)"

echo "== --apply writes, and only the right things =="
cp projects/live/tasks/task-003-unterminated.md "$TMP/unterminated.pristine"
APPLY_RC=0
APPLY_OUT="$(bash "$MIGRATE" --apply 2>&1)" || APPLY_RC=$?
assert "Finding open became current"   "$(grep -q '^status: current' knowledge/findings/open.md && echo 0 || echo 1)"
assert "Finding active became current" "$(grep -q '^status: current' knowledge/findings/active.md && echo 0 || echo 1)"
assert "Finding gained a status"       "$(grep -q '^status: current' knowledge/findings/nostatus.md && echo 0 || echo 1)"
assert "Service current became active" "$(grep -q '^status: active' knowledge/services/current.md && echo 0 || echo 1)"
assert "task gained a timestamp"       "$(grep -q '^timestamp: 20' projects/live/tasks/task-001-nots.md && echo 0 || echo 1)"
assert "the dangling ref was NOT rewritten" \
  "$(grep -q '/projects/gone/tasks/task-009.md' projects/live/tasks/task-002-dangling.md && echo 0 || echo 1)"
assert "the untracked file was NOT given a date" \
  "$(grep -q '^timestamp:' knowledge/findings/untracked-nots.md && echo 1 || echo 0)"
assert "a valid Finding kept its status" "$(grep -q '^status: current' knowledge/findings/ok.md && echo 0 || echo 1)"
assert "frontmatter still closes properly" \
  "$([[ "$(grep -c '^---$' knowledge/findings/nostatus.md)" == 2 ]] && echo 0 || echo 1)"
assert "an unknown Finding status survived --apply" \
  "$(grep -q '^status: wibble' knowledge/findings/unsupported.md && echo 0 || echo 1)"
assert "an unknown Service status survived --apply" \
  "$(grep -q '^status: retired' knowledge/services/unsupported.md && echo 0 || echo 1)"
assert "a repaired file keeps its original mode" \
  "$([[ "$(stat -f '%Lp' knowledge/findings/open.md 2>/dev/null || stat -c '%a' knowledge/findings/open.md)" == "$MODE_BEFORE" ]] && echo 0 || echo 1)"
assert "no temp file was left behind" \
  "$(find . -name '.migrate-bundle.*' | grep -q . && echo 1 || echo 0)"
assert "the unterminated file is byte-identical to before" \
  "$(cmp -s "$TMP/unterminated.pristine" projects/live/tasks/task-003-unterminated.md && echo 0 || echo 1)"
assert "apply mode reports it SKIPPED" \
  "$(printf '%s\n' "$APPLY_OUT" | grep -A1 'task-003-unterminated' | grep -q 'never closes' && echo 0 || echo 1)"
assert "apply mode never prints FIXED for it" \
  "$(printf '%s\n' "$APPLY_OUT" | grep -B1 'task-003-unterminated' | grep -q 'FIXED' && echo 1 || echo 0)"
assert "--apply reports 0 FAILED writes"  "$(printf '%s' "$APPLY_OUT" | grep -q '0 FAILED' && echo 0 || echo 1)"
assert "--apply exits 0 when every write landed" "$([[ $APPLY_RC -eq 0 ]] && echo 0 || echo 1)"

echo "== a write that cannot land reports FAILED and exits 1 =="
# An unwritable directory makes the beside-the-target temp file impossible, so the
# write genuinely cannot happen. The run must say FAILED on stderr, must NOT print
# FIXED for that path, and must exit 1 — a caller reading stdout alone must never
# see a success it did not get.
mkdir -p knowledge/runbooks
doc knowledge/runbooks/locked.md '---' 'type: Finding' 'title: L' 'status: open' "timestamp: $TS" '---' 'body'
chmod 555 knowledge/runbooks
set +e
FAIL_OUT="$(bash "$MIGRATE" --apply 2>&1)"; FAIL_RC=$?
FAIL_STDOUT="$(bash "$MIGRATE" --apply 2>/dev/null)"
set -e
chmod 755 knowledge/runbooks
assert "a write that cannot land exits 1"     "$([[ $FAIL_RC -eq 1 ]] && echo 0 || echo 1)"
assert "it is reported as FAILED"             "$(printf '%s' "$FAIL_OUT" | grep -q 'FAILED' && echo 0 || echo 1)"
# The per-file FAILED line goes to stderr; the summary legitimately reports the
# count on stdout, so match the per-file shape, not the word.
assert "the per-file FAILED line goes to stderr" \
  "$(printf '%s\n' "$FAIL_STDOUT" | grep -qE '^  FAILED ' && echo 1 || echo 0)"
assert "the stderr stream carries the per-file FAILED line" \
  "$(printf '%s\n' "$FAIL_OUT" | grep -qE '^  FAILED ' && echo 0 || echo 1)"
assert "stdout never claims FIXED for it"     "$(printf '%s\n' "$FAIL_STDOUT" | grep -B1 'locked.md' | grep -q 'FIXED' && echo 1 || echo 0)"
assert "the unwritable file kept its status"  "$(grep -q '^status: open' knowledge/runbooks/locked.md && echo 0 || echo 1)"
assert "the summary counts the failure"       "$(printf '%s' "$FAIL_OUT" | grep -qE '[1-9][0-9]* FAILED' && echo 0 || echo 1)"
rm -f knowledge/runbooks/locked.md

echo "== idempotence =="
SECOND="$(bash "$MIGRATE" 2>&1)"
assert "a second run fixes nothing more" \
  "$(printf '%s' "$SECOND" | grep -q '0 would be fixed' && echo 0 || echo 1)"

echo "== the validator agrees, apart from what needs a human =="
set +e; VOUT="$(bash "$VALIDATE" 2>&1)"; set -e
assert "only the unestablished statuses still fail the enum check" \
  "$([[ "$(printf '%s' "$VOUT" | grep -c 'is not valid for type')" == 2 ]] && echo 0 || echo 1)"
assert "the dangling ref still errors" "$(printf '%s' "$VOUT" | grep -q 'dangling reference' && echo 0 || echo 1)"

echo "== refusing to run outside an instance root =="
mkdir -p "$TMP/x" && cd "$TMP/x"
set +e; bash "$MIGRATE" >/dev/null 2>&1; RC=$?; set -e
assert "exits 2 outside an instance root" "$([[ $RC -eq 2 ]] && echo 0 || echo 1)"

# =========================================================================================
# THE 3.0 LAYOUT STEP — its own bundle, because it moves the fixture out from under itself.
# =========================================================================================
. "$HERE/../plugin/scripts/bundle-paths.sh"

L="$TMP/layout"; mkdir -p "$L/projects/p/tasks" "$L/knowledge/findings"; cd "$L"
echo '{ "org": "x" }' > instance.config.json
echo '# Schema' > SCHEMA.md
echo '# Conventions' > CONVENTIONS.md
printf 'AWAITING.md\n/.board-live/\n/.tick-lock\nnode_modules/\n' > .gitignore
doc projects/p/tasks/task-001-x.md '---' 'type: Task' 'title: T' 'status: draft' "timestamp: $TS" '---' \
  'See [SCHEMA](/SCHEMA.md) and [CONVENTIONS](/CONVENTIONS.md).'
# BOTH FORMS, in one bundle: a document written before the move and one written after it.
doc knowledge/findings/both.md '---' 'type: Finding' 'title: F' 'status: current' \
  'lesson: one line' "timestamp: $TS" '---' \
  'Root form [S](/SCHEMA.md); new form [C](/.ai-bridge/CONVENTIONS.md).'
git init -q -b main . && git add -A && git -c user.email=a@b -c user.name=a commit -qm init
: > AWAITING.md   # gitignored, so git mv would refuse it
# A SYMLINKED document. The relink reads through it and renames a temp file over the
# target — which turns a human's link into a regular file, whether or not the content
# had anything to rewrite.
doc "$TMP/link-target.md" '---' 'type: Task' 'title: L' 'status: draft' "timestamp: $TS" '---' 'Linked.'
ln -s "$TMP/link-target.md" projects/p/tasks/task-002-linked.md

echo "== the layout step: report-only by default =="
DRY="$(bash "$MIGRATE" 2>&1)"
assert "it reports the move"           "$(printf '%s' "$DRY" | grep -q "WOULD MOVE SCHEMA.md -> $AB_SCHEMA" && echo 0 || echo 1)"
assert "the untracked file too"        "$(printf '%s' "$DRY" | grep -q "WOULD MOVE AWAITING.md -> $AB_AWAITING" && echo 0 || echo 1)"
assert "nothing actually moved"        "$([[ -f SCHEMA.md && ! -e $AB_SCHEMA ]] && echo 0 || echo 1)"

echo "== it refuses on a live lock, and prints the commands instead =="
: > .tick-lock
LOCKED="$(bash "$MIGRATE" --apply 2>&1)"
assert "REFUSED while a tick holds the lock" "$(printf '%s' "$LOCKED" | grep -q 'REFUSED.*lock' && echo 0 || echo 1)"
assert "the manual command list is printed"  "$(printf '%s' "$LOCKED" | grep -q "git mv SCHEMA.md $AB_SCHEMA" && echo 0 || echo 1)"
# `git mv` on a derived file fails with "not under version control", so the printed
# command has to make the same tracked/untracked decision the apply path makes.
assert "…with plain mv for the untracked one" "$(printf '%s' "$LOCKED" | grep -q "  mv AWAITING.md $AB_AWAITING" && echo 0 || echo 1)"
assert "and it moved nothing"                "$([[ -f SCHEMA.md ]] && echo 0 || echo 1)"
rm -f .tick-lock

echo "== it refuses a dirty TRACKED tree, but not untracked dirt =="
echo 'edited' >> CONVENTIONS.md
DIRTY="$(bash "$MIGRATE" --apply 2>&1)"
assert "REFUSED on a dirty tracked tree" "$(printf '%s' "$DIRTY" | grep -q 'REFUSED.*tracked tree is dirty' && echo 0 || echo 1)"
git add -A && git -c user.email=a@b -c user.name=a commit -qm edit
: > untracked-scratch.md
CLEANISH="$(bash "$MIGRATE" 2>&1)"
assert "untracked dirt is NOT a refusal"  "$(printf '%s' "$CLEANISH" | grep -q 'REFUSED' && echo 1 || echo 0)"
rm -f untracked-scratch.md

echo "== --apply moves, rewrites the ignores and relinks =="
OUT="$(bash "$MIGRATE" --apply 2>&1)"
assert "SCHEMA.md is at its new path"     "$([[ -f $AB_SCHEMA && ! -e SCHEMA.md ]] && echo 0 || echo 1)"
assert "git still tracks it there"        "$(git ls-files --error-unmatch -- "$AB_SCHEMA" >/dev/null 2>&1 && echo 0 || echo 1)"
assert "the gitignored file moved too"    "$([[ -f $AB_AWAITING && ! -e AWAITING.md ]] && echo 0 || echo 1)"
assert "…and git does not track THAT"     "$(git ls-files --error-unmatch -- "$AB_AWAITING" >/dev/null 2>&1 && echo 1 || echo 0)"
assert "no symlink was left behind"       "$([[ -z "$(find . -maxdepth 1 -type l)" ]] && echo 0 || echo 1)"
assert "the root ignore lines are gone"   "$(grep -qxE '/?(AWAITING\.md|\.board-live/|\.tick-lock)' .gitignore && echo 1 || echo 0)"
assert "a human's own ignore line stayed" "$(grep -qx 'node_modules/' .gitignore && echo 0 || echo 1)"
assert "the task doc's links were rewritten" \
  "$(grep -q "(/$AB_SCHEMA)" projects/p/tasks/task-001-x.md && grep -q "(/$AB_CONVENTIONS)" projects/p/tasks/task-001-x.md && echo 0 || echo 1)"
assert "a symlinked document is still a symlink" \
  "$([[ -L projects/p/tasks/task-002-linked.md ]] && echo 0 || echo 1)"

echo "== and the link checker is clean on a bundle that carried both forms =="
set +e; LV="$(bash "$VALIDATE" 2>&1)"; LV_RC=$?; set -e
assert "validate-bundle reports 0 errors"  "$(printf '%s' "$LV" | grep -q ', 0 errors,' && echo 0 || echo 1)"
assert "…and exits 0"                      "$([[ $LV_RC -eq 0 ]] && echo 0 || echo 1)"
assert "no link still names the old root"  "$(grep -rq '(/SCHEMA\.md\|(/CONVENTIONS\.md' projects knowledge && echo 1 || echo 0)"
assert "…and the already-new form is untouched" \
  "$(grep -q "(/$AB_CONVENTIONS)" knowledge/findings/both.md && echo 0 || echo 1)"

echo "== the layout step is idempotent =="
AGAIN="$(bash "$MIGRATE" 2>&1)"
assert "a migrated bundle says nothing about the layout" \
  "$(printf '%s' "$AGAIN" | grep -q 'pre-3.0 layout' && echo 1 || echo 0)"

echo "== a half-migrated bundle stops before the FIRST move =="
# Its own bundle: an occupied destination has to be caught while every source is still
# at the root, and a per-path guard would only see it after earlier paths had moved.
H="$TMP/half"; mkdir -p "$H"; cd "$H"
echo '{ "org": "x" }' > instance.config.json
echo '# Schema' > SCHEMA.md
echo '# Conventions' > CONVENTIONS.md
mkdir -p .board-live "$AB_BOARD_DIR"
HALF="$(bash "$MIGRATE" --apply 2>&1)"
assert "it names the occupied destination" \
  "$(printf '%s' "$HALF" | grep -q 'STOPPED' && printf '%s' "$HALF" | grep -q ".board-live -> $AB_BOARD_DIR" && echo 0 || echo 1)"
assert "and moved nothing at all"          "$([[ -f SCHEMA.md && -d .board-live && ! -e $AB_SCHEMA ]] && echo 0 || echo 1)"
assert "no source was nested inside it"    "$([[ ! -e $AB_BOARD_DIR/.board-live ]] && echo 0 || echo 1)"

# =========================================================================================
# THE .loopd RENAME — `.ai-bridge/` moves whole, with its ignore lines, its statusline pin
# and a mounted KB. AB_DIR still names the old directory until that flip lands, so the KB
# is read back through a copy of the scripts with AB_DIR flipped: the plugin that will read it.
# =========================================================================================
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null AI_BRIDGE_KB_TIMEOUT=3
SCRIPTS="$HERE/../plugin/scripts"
FLIPPED="$TMP/flipped"; cp -R "$SCRIPTS" "$FLIPPED"
sed -i.bak 's|^AB_DIR=".ai-bridge"$|AB_DIR=".loopd"|' "$FLIPPED/bundle-paths.sh"
assert "the flipped copy really resolves .loopd" "$([[ "$(bash "$FLIPPED/bundle-paths.sh" AB_DIR)" == .loopd ]] && echo 0 || echo 1)"

KBW="$TMP/kb-work"; KBBARE="$TMP/kb.bare"
mkdir -p "$KBW/knowledge/findings" && doc "$KBW/knowledge/findings/kept.md" '---' 'type: Finding' 'title: K' 'status: current' 'provenance: human' "timestamp: $TS" '---' 'body'
git -C "$KBW" init -q -b main && git -C "$KBW" add -A && git -C "$KBW" commit -qm kb
git clone -q --bare "$KBW" "$KBBARE"
STALE="$TMP/_ai-bridge-old"   # the bundle's directory before someone renamed it

mk_rename() { # <dir> — a 3.x bundle: tracked state, derived state, a stale pin and a KB mount
  mkdir -p "$1/.ai-bridge/agents" "$1/.claude" && cd "$1"
  printf '{ "org": "x", "knowledge": { "repo": "%s", "path": "knowledge", "ref": "main" } }\n' "$KBBARE" > instance.config.json
  echo '# Schema' > .ai-bridge/SCHEMA.md; echo '# Log' > .ai-bridge/log.md
  printf '#!/usr/bin/env bash\nexit 0\n' > .claude/ai-bridge-statusline.sh
  cat > .claude/settings.json <<JSON
{
  "statusLine": { "type": "command", "command": "bash $STALE/.claude/ai-bridge-statusline.sh", "refreshInterval": 5000 },
  "permissions": { "deny": [ "Bash(rm -rf /)", "Bash(terraform destroy:*)" ] },
  "\$schema": "the unconditional second layer behind the deny-destructive hook"
}
JSON
  cat > .gitignore <<'GI'
# Derived queue — rewritten by each /ai-bridge:dispatch tick (the ai-bridge-llm companion too).
/.ai-bridge/AWAITING.md
/.ai-bridge/.tick-lock
# >>> ai-bridge index ignore >>>
/.ai-bridge/index.md
# <<< ai-bridge index ignore <<<
/.ai-bridge/kb.git/
/knowledge/
node_modules/
GI
  git init -q -b main . && git add -A && git commit -qm init
  echo 'derived' > .ai-bridge/AWAITING.md
  bash "$SCRIPTS/kb-sync.sh" --instance . mount >/dev/null 2>&1
  git --git-dir=.ai-bridge/kb.git config core.worktree "$STALE/"
}
treesum() { find . -path ./.git/objects -prune -o -type f -print | LC_ALL=C sort | xargs shasum 2>/dev/null; git rev-parse HEAD; }

mk_rename "$TMP/rename"; R="$(pwd)"
assert "the fixture mounted a KB at .ai-bridge/kb.git" "$([[ -d .ai-bridge/kb.git && -f knowledge/findings/kept.md ]] && echo 0 || echo 1)"
assert "…which git status cannot see"  "$([[ -z "$(git status --porcelain)" ]] && echo 0 || echo 1)"
GI_REFS="$(grep -c ai-bridge .gitignore)"; SET_BEFORE="$(jq -S 'del(.statusLine.command)' .claude/settings.json)"

echo "== the rename: the dry run is the default, writes nothing and names everything =="
BEFORE="$(treesum)"; RD="$(bash "$MIGRATE" 2>&1)"
assert "a dry run wrote nothing"                "$([[ "$BEFORE" == "$(treesum)" ]] && echo 0 || echo 1)"
assert "it names the directory move"            "$(printf '%s\n' "$RD" | grep -q 'WOULD MOVE .ai-bridge -> .loopd' && echo 0 || echo 1)"
assert "it names every ignore-line rewrite"     "$([[ "$(printf '%s\n' "$RD" | grep -c 'WOULD REWRITE .gitignore:')" == "$GI_REFS" ]] && echo 0 || echo 1)"
assert "it names the pin rewrite, whole path"   "$(printf '%s\n' "$RD" | grep -qF "WOULD REPIN  .claude/settings.json: bash $STALE/.claude/ai-bridge-statusline.sh -> bash $R/.claude/ai-bridge-statusline.sh" && echo 0 || echo 1)"
assert "it says how the KB mount is handled"    "$(printf '%s\n' "$RD" | grep -q 'WOULD KEEP  .ai-bridge/kb.git' && printf '%s\n' "$RD" | grep -qF "WOULD SET   .loopd/kb.git core.worktree $STALE/ -> $R" && echo 0 || echo 1)"

echo "== --apply: ignores first, then the move, then the mount and one commit =="
RA_RC=0; RA="$(bash "$MIGRATE" --apply 2>&1)" || RA_RC=$?
assert "--apply exits 0"                        "$([[ $RA_RC -eq 0 ]] && echo 0 || echo 1)"
assert ".gitignore holds 0 ai-bridge references" "$([[ "$(grep -c ai-bridge .gitignore || true)" == 0 ]] && echo 0 || echo 1)"
assert "…and was rewritten BEFORE the move"     "$(printf '%s\n' "$RA" | grep -nE 'REWROTE|MOVED' | head -1 | grep -q REWROTE && echo 0 || echo 1)"
assert "the derived files are still ignored"    "$(git check-ignore -q .loopd/AWAITING.md && git check-ignore -q .loopd/kb.git && echo 0 || echo 1)"
assert "a human's own ignore line stayed"       "$(grep -qx 'node_modules/' .gitignore && echo 0 || echo 1)"
assert ".ai-bridge/ is gone, .loopd/ holds it"  "$([[ ! -e .ai-bridge && -f .loopd/SCHEMA.md && -f .loopd/AWAITING.md ]] && echo 0 || echo 1)"
assert "git followed the move"                  "$(git log --follow --format=%s -- .loopd/SCHEMA.md | grep -qx init && echo 0 || echo 1)"
assert "the pin names the whole new path"       "$([[ "$(jq -r .statusLine.command .claude/settings.json)" == "bash $R/.claude/ai-bridge-statusline.sh" ]] && echo 0 || echo 1)"
assert "…and that path exists"                  "$([[ -f "$(jq -r .statusLine.command .claude/settings.json | cut -d' ' -f2-)" ]] && echo 0 || echo 1)"
assert "nothing else in settings.json moved"    "$([[ "$(jq -S 'del(.statusLine.command)' .claude/settings.json)" == "$SET_BEFORE" ]] && echo 0 || echo 1)"
assert ".loopd/kb.git exists"                   "$([[ -d .loopd/kb.git ]] && echo 0 || echo 1)"
assert "its core.worktree names the new root"   "$([[ "$(git --git-dir=.loopd/kb.git config core.worktree)" == "$R" ]] && echo 0 || echo 1)"
set +e; KS="$(bash "$FLIPPED/kb-sync.sh" --instance . status 2>&1)"; KS_RC=$?
KP="$(bash "$FLIPPED/kb-sync.sh" --instance . pull 2>&1)"; KP_RC=$?; set -e
assert "kb-sync.sh status exits 0"              "$([[ $KS_RC -eq 0 ]] && echo 0 || echo 1)"
assert "kb-sync.sh pull merges, not warns"      "$([[ $KP_RC -eq 0 ]] && ! printf '%s' "$KP" | grep -q 'not checked out' && echo 0 || echo 1)"
assert "git status --porcelain is empty"        "$([[ -z "$(git status --porcelain)" ]] && echo 0 || echo 1)"

echo "== a second run changes nothing and says so =="
BEFORE="$(treesum)"; R2D="$(bash "$MIGRATE" 2>&1)"; R2A="$(bash "$MIGRATE" --apply 2>&1)"
assert "the dry run reports no pending moves"   "$(printf '%s\n' "$R2D" | grep -q 'WOULD' && echo 1 || echo 0)"
assert "--apply wrote nothing"                  "$([[ "$BEFORE" == "$(treesum)" ]] && echo 0 || echo 1)"
assert "the output says already migrated"       "$(printf '%s\n' "$R2A" | grep -q 'already migrated' && echo 0 || echo 1)"

echo "== the refusals: an occupied .loopd/, a broken settings.json, an unpushed KB =="
O="$TMP/occupied"; mk_rename "$O"; mkdir -p .loopd && echo mine > .loopd/keep.md
BEFORE="$(treesum)"; OC="$(bash "$MIGRATE" --apply 2>&1)"
assert "layout_conflicts STOPS an occupied .loopd/" "$(printf '%s\n' "$OC" | grep -q 'STOPPED' && printf '%s\n' "$OC" | grep -q '.ai-bridge -> .loopd' && echo 0 || echo 1)"
assert "…and nothing was written or overwritten"    "$([[ "$BEFORE" == "$(treesum)" && -d .ai-bridge/kb.git ]] && echo 0 || echo 1)"
J="$TMP/badjson"; mk_rename "$J"; echo '{ "permissions": ' > .claude/settings.json; git commit -qam broken
BEFORE="$(treesum)"; JS="$(bash "$MIGRATE" --apply 2>&1)"
assert "a settings.json that does not parse is REFUSED" "$(printf '%s\n' "$JS" | grep -q 'REFUSED.*settings.json' && echo 0 || echo 1)"
assert "…and nothing was written"                   "$([[ "$BEFORE" == "$(treesum)" ]] && echo 0 || echo 1)"
U="$TMP/unpushed"; mk_rename "$U"; echo more >> knowledge/findings/kept.md
git --git-dir=.ai-bridge/kb.git --work-tree=. commit -qam local
BEFORE="$(treesum)"; UP="$(bash "$MIGRATE" --apply 2>&1)"
assert "an unpushed KB commit is REFUSED"           "$(printf '%s\n' "$UP" | grep -q 'REFUSED.*unpushed' && echo 0 || echo 1)"
assert "…and nothing was written"                   "$([[ "$BEFORE" == "$(treesum)" ]] && echo 0 || echo 1)"
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL   # provenance below names its own authors

# =========================================================================================
# PROVENANCE — from git history, and every doubt lands on human.
# =========================================================================================
V="$TMP/prov"; mkdir -p "$V/knowledge"/{findings,services,teams,runbooks,references}; cd "$V"
echo '{ "org": "x" }' > instance.config.json
git init -q -b main .
as() { local who="$1"; shift; git add -A && git -c user.email=a@b -c user.name="$who" -c commit.gpgsign=false commit -qm "$*"; }
kdoc() { doc "knowledge/$1.md" '---' "type: $2" 'title: X' ${3:+"$3"} "timestamp: $TS" '---' "${4:-body}"; }
kdoc findings/machine Finding 'status: current'
kdoc findings/body Finding 'status: current' 'provenance: human'
kdoc references/old Reference 'status: current'
kdoc findings/dirty Finding 'status: current'
kdoc findings/already Finding 'status: current'; sed -i.bak 's/^status: current$/status: current\nprovenance: human/' knowledge/findings/already.md
kdoc runbooks/bot Runbook 'provenance: bot'; rm -f knowledge/findings/*.bak
kdoc services/edited Service 'status: active'
as cataloguer add
git mv knowledge/references/old.md knowledge/references/renamed.md && as cataloguer rename
echo 'a person was here' >> knowledge/services/edited.md && as "A Person" edit
kdoc teams/person Team && as "A Person" add
kdoc runbooks/claude Runbook && as Claude add
echo 'pending' >> knowledge/findings/dirty.md
kdoc findings/untracked Finding 'status: current'
line() { printf '%s\n' "$1" | grep -A1 "knowledge/$2.md" | tail -1; }

echo "== provenance: the report classifies from git, and writes nothing =="
PD="$(bash "$MIGRATE" 2>&1)"
assert "a role-created, untouched document is machine" "$(line "$PD" findings/machine | grep -q -- '-> machine (created by cataloguer' && echo 0 || echo 1)"
assert "a rename is followed, not read as unresolved" "$(line "$PD" references/renamed | grep -q -- '-> machine' && echo 0 || echo 1)"
assert "a person's later edit makes it mixed" "$(line "$PD" services/edited | grep -q -- '-> mixed (created by cataloguer, later edited by A Person)' && echo 0 || echo 1)"
assert "an uncommitted edit makes it mixed" "$(line "$PD" findings/dirty | grep -q -- '-> mixed' && echo 0 || echo 1)"
# person.md and claude.md are near-copies of role-created files: --follow alone calls them COPIES.
assert "a person's document is human, not its look-alike's" "$(line "$PD" teams/person | grep -q -- '-> human (created by A Person)' && echo 0 || echo 1)"
assert "a non-role name (Claude) is human" "$(line "$PD" runbooks/claude | grep -q -- '-> human' && echo 0 || echo 1)"
assert "a file git does not know is human, never machine" "$(line "$PD" findings/untracked | grep -q -- '-> human (unresolved' && echo 0 || echo 1)"
assert "a value outside the set is held for a human" "$(printf '%s\n' "$PD" | grep -q "provenance 'bot' is not machine|mixed|human" && echo 0 || echo 1)"
assert "an existing value is never re-derived" "$(printf '%s\n' "$PD" | grep -q 'findings/already.md' && echo 1 || echo 0)"
assert "the tally counts each class and the unresolved" "$(printf '%s\n' "$PD" | grep -qx 'provenance: 3 machine, 2 mixed, 3 human (1 of them unresolved in git).' && echo 0 || echo 1)"

echo "== provenance: without commit-as.sh there is no role list, so nothing is machine =="
mkdir -p "$TMP/lonely" && cp "$MIGRATE" "$HERE/../plugin/scripts/bundle-paths.sh" "$TMP/lonely/"
LD="$(bash "$TMP/lonely/migrate-bundle.sh" 2>&1)"
assert "every document falls to human" "$(printf '%s\n' "$LD" | grep -q '^provenance: 0 machine, 0 mixed, 8 human' && echo 0 || echo 1)"

echo "== provenance: --apply writes inside the frontmatter, and the validator agrees =="
bash "$MIGRATE" --apply >/dev/null 2>&1 || true
fmp() { awk '/^---$/{n++; next} n==1 && /^provenance:/{sub(/^provenance: */,""); print}' "knowledge/$1.md"; }
assert "machine written" "$([[ "$(fmp findings/machine)" == machine ]] && echo 0 || echo 1)"
assert "mixed written" "$([[ "$(fmp services/edited)" == mixed ]] && echo 0 || echo 1)"
assert "human written" "$([[ "$(fmp teams/person)" == human ]] && echo 0 || echo 1)"
assert "the field landed inside the --- block, not after a body line" "$([[ "$(fmp findings/body)" == machine ]] && grep -qx 'provenance: human' knowledge/findings/body.md && echo 0 || echo 1)"
assert "the out-of-set value survived" "$(grep -qx 'provenance: bot' knowledge/runbooks/bot.md && echo 0 || echo 1)"
assert "the existing human label survived" "$([[ "$(fmp findings/already)" == human ]] && echo 0 || echo 1)"
set +e; PV="$(bash "$VALIDATE" 2>&1)"; set -e
assert "only the out-of-set value still errors" "$([[ "$(printf '%s\n' "$PV" | grep -c 'provenance')" == 1 ]] && echo 0 || echo 1)"
assert "a second run derives nothing" "$(bash "$MIGRATE" 2>&1 | grep -q '^provenance:' && echo 1 || echo 0)"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
