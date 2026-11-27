#!/usr/bin/env bash
#
# add-task.test.sh — plugin/scripts/add-task.sh: every field of the draft it writes, for a
# build and a research project; the validator seam; the commit, snapshot and push; each
# refusal writes nothing. Also the validate-bundle.sh warning for a shared task number.
# Fixtures under mktemp; no gh, no network. Exit: 0 all pass · 1 one failed · 2 no fixture.
# Reasoning: prefer-tasks-in-open-projects/task-001.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"
command -v python3 >/dev/null 2>&1 || { echo "  (python3 absent — skipped)"; echo "pass=0 fail=0"; exit 0; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/add-task.XXXXXX")" || exit 2
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s — got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
S="$REPO/plugin/scripts"

BASE="$TMP/base"
bash "$REPO/tests/fixtures/simple-board/mk.sh" "$BASE" >/dev/null 2>&1 || { echo "fixture failed"; exit 2; }
proj() { # <slug> <frontmatter lines>
  mkdir -p "$BASE/projects/$1/tasks"
  printf -- '---\ntype: Project\ntitle: "%s"\n%stimestamp: 2026-11-01T00:00:00Z\n---\n' "$1" "$2" > "$BASE/projects/$1/project.md"; }
proj build-p $'kind: build\ntarget_repo: owner/name\nstatus: active\n'
printf -- '---\ntype: Task\ntitle: x\nstatus: done\ntimestamp: 2026-11-01T00:00:00Z\n---\n' > "$BASE/projects/build-p/tasks/task-009-old.md"
proj research-p $'kind: research\nstatus: paused\n'
proj nokind-p $'status: active\n'
proj done-p $'kind: build\nstatus: done\n'
mkdir -p "$BASE/projects/empty-p"
printf '%s\n' "/$AB_SNAPSHOT" > "$BASE/.gitignore"
( cd "$BASE" && SNAPSHOT_NOW=2026-11-01T00:00:00Z bash "$S/write-snapshot.sh" --quiet ) >/dev/null 2>&1
( cd "$BASE" && git init -q -b main && git config user.name "Example Human" && git config user.email t@example.com &&
  git add -A && git commit -qm fixture ) || { echo "fixture failed"; exit 2; }
N=0
fresh() { D="$TMP/b$((++N))"; cp -R "$BASE" "$D" || { echo "fixture failed"; exit 2; }; }
run() { ( cd "$D" && bash "${SCRIPTS:-$S}/add-task.sh" "$@" ) >"$TMP/out" 2>"$TMP/err"; echo $?; }
fm() { # <file> <key> — the raw frontmatter value, `<absent>` when the key is missing
  awk -v k="$2" 'NR==1{next} $0=="---"{exit} index($0, k ":")==1{sub("^" k ":[ ]?", ""); print; f=1} END{if(!f) print "<absent>"}' "$1"; }
yaml() { python3 -c 'import json,sys; print(json.loads(sys.argv[1]))' "$1" 2>/dev/null || echo unparseable; }
new() { ls "$D/projects/$1/tasks" | grep -vxF -f <(ls "$BASE/projects/$1/tasks") || true; }
DESC=$'Send the "late" notice: twice # then stop.\nSecond   line here.'
ONE='Send the "late" notice: twice # then stop. Second line here.'

echo "== 1. a build project: every field =="
fresh
ok "add-task.sh exits 0" "$(run build-p "$DESC")" 0
F="$(new build-p)"
ok "the file is task-010, one past the highest, slugged from the first sentence" "$F" "task-010-send-the-late-notice-twice-then-stop.md"
T="$D/projects/build-p/tasks/$F"
ok "type: Task" "$(fm "$T" type)" Task
ok "status: draft" "$(fm "$T" status)" draft
ok "kind copied from project.md" "$(fm "$T" kind)" build
ok "target_repo copied on build" "$(fm "$T" target_repo)" owner/name
ok "pr: []" "$(fm "$T" pr)" "[]"
ok "no artifacts on build" "$(fm "$T" artifacts)" "<absent>"
ok "assignee empty" "$(fm "$T" assignee)" ""
ok "title is the first sentence" "$(yaml "$(fm "$T" title)")" 'Send the "late" notice: twice # then stop'
ok "original_request is the description, one line, whitespace collapsed" "$(yaml "$(fm "$T" original_request)")" "$ONE"
ok "…JSON-quoted on one line" "$(grep -c '^original_request: "' "$T")" 1
ok "description is the same line" "$(yaml "$(fm "$T" description)")" "$ONE"
ok "acceptance_criteria empty" "$(fm "$T" acceptance_criteria)" "[]"
ok "open_questions empty" "$(fm "$T" open_questions)" "[]"
ok "timestamp is ISO 8601 UTC" "$(fm "$T" timestamp | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$')" 1
ok "a # Context section" "$(grep -cx '# Context' "$T")" 1
ok "validate-bundle.sh passes the new file" "$(cd "$D" && bash "$S/validate-bundle.sh" "projects/build-p/tasks/$F" >/dev/null 2>&1; echo $?)" 0
ok "committed: exactly one path, the new file" "$(git -C "$D" show --name-only --format= HEAD)" "projects/build-p/tasks/$F"
ok "…as human through commit-as.sh, subject names the id" "$(git -C "$D" log -1 --format=%s)" "feat: add task-010 to build-p"
ok "…and the tree is clean" "$(git -C "$D" status --porcelain | wc -l | tr -d ' ')" 0
ok "the snapshot knows the new task" "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(any(t["id"]==sys.argv[2] for p in d["projects"] for t in p["tasks"]))' "$D/$AB_SNAPSHOT" "${F%.md}")" True
ok "no origin: the push is skipped silently" "$(wc -c < "$TMP/err" | tr -d ' ')" 0

echo "== 2. a research project, and kind absent =="
fresh
ok "research: exits 0 with kind=research" "$(run research-p 'Survey the vendors' kind=research)" 0
T="$D/projects/research-p/tasks/$(new research-p)"
ok "…first task is task-001" "$(new research-p)" "task-001-survey-the-vendors.md"
ok "…kind research" "$(fm "$T" kind)" research
ok "…no target_repo" "$(fm "$T" target_repo)" "<absent>"
ok "…no pr" "$(fm "$T" pr)" "<absent>"
ok "…artifacts empty" "$(fm "$T" artifacts)" "[]"
ok "…and no deliverable stub" "$([ -e "$D/projects/research-p/deliverables" ] && echo made || echo none)" none
ok "kind absent in project.md ⇒ build" "$(run nokind-p 'Do a thing' kind=build)|$(fm "$D/projects/nokind-p/tasks/$(new nokind-p)" kind)" "0|build"
ok "…and no target_repo to copy is no key" "$(fm "$D/projects/nokind-p/tasks/$(new nokind-p)" target_repo)" "<absent>"

echo "== 3. refusals: distinct exits, one line, nothing written =="
refuse() { # <name> <want rc> <args...>
  local name="$1" want="$2"; shift 2; fresh
  ok "$name" "$(run "$@")|$(wc -l < "$TMP/err" | tr -d ' ')|$(git -C "$D" status --porcelain | wc -l | tr -d ' ')|$(git -C "$D" rev-list --count HEAD)" "$want|1|0|1"
}
refuse "an empty description → 1" 1 build-p $' \n\t '
refuse "slug ../x → 3" 3 ../x "Do it"
refuse "slug a/b → 3" 3 a/b "Do it"
refuse "a missing project folder → 5" 5 nope "Do it"
refuse "a folder with no project.md → 5" 5 empty-p "Do it"
refuse "a done project → 6" 6 done-p "Do it"
refuse "kind=research on a build project → 7" 7 build-p "Do it" kind=research
refuse "kind=build on a research project → 7" 7 research-p "Do it" kind=build
fresh
ok "kind=other is usage → 2" "$(run build-p "Do it" kind=other)|$(git -C "$D" status --porcelain | wc -l | tr -d ' ')" "2|0"

echo "== 4. the validator seam: a failing validate-bundle.sh keeps nothing =="
SCRIPTS="$TMP/scripts"; cp -R "$S" "$SCRIPTS" && printf '#!/usr/bin/env bash\nexit 1\n' > "$SCRIPTS/validate-bundle.sh"
fresh
ok "exits 8" "$(run build-p "Do it")" 8
ok "…the file is removed" "$(new build-p)" ""
ok "…nothing committed" "$(git -C "$D" rev-list --count HEAD)" 1
ok "…one line on stderr" "$(wc -l < "$TMP/err" | tr -d ' ')" 1
unset SCRIPTS

echo "== 5. the push =="
fresh; git init -q --bare "$TMP/origin$N.git"
git -C "$D" remote add origin "$TMP/origin$N.git" && git -C "$D" push -q -u origin main 2>/dev/null
ok "with an origin: exits 0" "$(run build-p "Do it")" 0
ok "…and origin has the commit" "$(git -C "$TMP/origin$N.git" rev-parse main)" "$(git -C "$D" rev-parse HEAD)"
rm -rf "$TMP/origin$N.git"
ok "an unreachable origin: exits 4, committed, not pushed" "$(run build-p "Do more")|$(git -C "$D" log -1 --format=%s)" "4|feat: add task-011 to build-p"

echo "== 6. validate-bundle.sh warns on a shared task number =="
fresh
cp "$D/projects/build-p/tasks/task-009-old.md" "$D/projects/build-p/tasks/task-009-twin.md"
out="$(cd "$D" && bash "$S/validate-bundle.sh" projects/build-p/tasks/task-009-twin.md 2>&1)"; rc=$?
ok "warns, naming the twin" "$(grep -c 'shares task-009 with task-009-old.md' <<<"$out")" 1
ok "…as a warning: exit 0" "$rc" 0
rm "$D/projects/build-p/tasks/task-009-twin.md"
ok "…and with the twin gone, none" "$(cd "$D" && bash "$S/validate-bundle.sh" projects/build-p/tasks/task-009-old.md 2>&1 | grep -c 'shares task-')" 0

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
