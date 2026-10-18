#!/usr/bin/env bash
# answer.sh — `/loopd:answer <task> [Q<n>] <n | text | more>` against a real bundle clone
# with a bare remote: an option records its text, free text records itself, `more` reads
# depth 1, 2, 3 and then hands over (exit 5), and every answer is moved, committed as the
# human and pushed. A failed rebase or push stops at exit 4 and never forces.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SH="$REPO/plugin/scripts/answer.sh"
FOLD="$REPO/plugin/scripts/fold-answers.sh"
SKILL="$REPO/plugin/skills/answer/SKILL.md"
command -v python3 >/dev/null 2>&1 || { echo "answer.test: python3 required" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/answer-test.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi }

TASK_REL="projects/p/tasks/task-001-x.md"
fixture() { # <name> — a bundle clone of a bare remote, one task with Q1 (block) and Q2 (none)
  local b="$TMP/$1"
  git init -q --bare "$b.git"
  git init -q -b main "$b"
  git -C "$b" config user.name "Example Human"; git -C "$b" config user.email t@example.com
  mkdir -p "$b/$(dirname "$TASK_REL")"
  printf '{ "ownerGithubUser": "example-user-007", "people": { "example-user-007": "u7@example.com" } }\n' > "$b/instance.config.json"
  cat > "$b/$TASK_REL" <<'MD'
---
type: Task
title: "T"
status: draft
open_questions: [ "Q1: which region?", "Q2: how many replicas?" ]
answered_questions: [ ]
---

# Context

body

## Question details

### Q1
Recommendation: eu-central-1
Options:
1. eu-central-1
2. us-east-1, close to the users
Context:
- Depth 1: Latency.
- Depth 2: Most users are in Europe;
  data residency points the same way.
- Depth 3: Everything else,
wrapped onto an unindented line.

## Notes
MD
  git -C "$b" add -A && git -C "$b" commit -qm init
  git -C "$b" remote add origin "$b.git"
  git -C "$b" push -q -u origin main
  echo "$b"
}
openq() { bash "$FOLD" --list "$1/$TASK_REL" open_questions; }
lastans() { bash "$FOLD" --list "$1/$TASK_REL" answered_questions | tail -n1; }
run() { local b="$1"; shift; (cd "$b" && bash "$SH" "$TASK_REL" "$@"); }

echo "== OPTION: a bare integer records the option's TEXT, moved, committed, pushed =="
B="$(fixture opt)"
OUT="$(run "$B" 2 2>&1)"; RC=$?
ok "it exits 0"                              "$RC" 0
ok "the answered line carries option 2's text" \
   "$(lastans "$B" | sed -E 's/^[0-9TZ:-]+ by //')" "example-user-007 · Q1: which region? --- us-east-1, close to the users"
ok "…stamped with an ISO date"               "$(lastans "$B" | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z by ')" 1
ok "Q1 is gone from open_questions"          "$(openq "$B")" "Q2: how many replicas?"
ok "the commit is the human's, via people"   "$(git -C "$B" log -1 --format='%an <%ae>')" "Example Human <u7@example.com>"
ok "…and it reached the remote"              "$(git -C "$B.git" log -1 --format=%s main)" "docs: answer Q1 on task-001-x"
ok "the work tree is clean"                  "$(git -C "$B" status --porcelain | wc -l | tr -d ' ')" 0

echo
echo "== TEXT: free text records itself; Q<n> picks the question =="
B="$(fixture txt)"
run "$B" Q2 three, one per zone >/dev/null 2>&1
ok "Q2 is answered with the words"           "$(lastans "$B" | sed 's/^.*· //')" "Q2: how many replicas? --- three, one per zone"
ok "…and Q1 stays open"                      "$(openq "$B")" "Q1: which region?"
B="$(fixture num)"
cp "$B/$TASK_REL" "$TMP/num.before"
OUT="$(run "$B" 7 2>&1)"; RC=$?
ok "an integer past the options refuses"     "$RC" 1
ok "…in one sentence naming --text"          "$(printf '%s\n' "$OUT" | grep -c . | tr -d ' '),$(printf '%s' "$OUT" | grep -c -- '--text 7')" "1,1"
ok "…and writes nothing"                     "$(cmp -s "$B/$TASK_REL" "$TMP/num.before" && echo yes || echo no)" yes
run "$B" --text 7 >/dev/null 2>&1
ok "--text 7 records the number itself"      "$(lastans "$B" | sed 's/^.*· //')" "Q1: which region? --- 7"
B="$(fixture noopt)"
ok "an integer on a question with no block refuses" "$(run "$B" Q2 3 >/dev/null 2>&1; echo $?)" 1
ok "a Q<n> that is not open refuses"         "$(run "$B" Q9 yes >/dev/null 2>&1; echo $?)" 1

echo
echo "== MORE: depth 1, 2, 3 from the document, then exit 5 — and nothing written =="
B="$(fixture more)"
cp "$B/$TASK_REL" "$TMP/more.before"
ok "first more is depth 1"                   "$(run "$B" more 2>&1 | tr '\n' '|')" "Depth 1 of 3 · Q1|Latency.|"
ok "second more is depth 2, continuation kept" "$(run "$B" more 2>&1 | tr '\n' '|')" \
   "Depth 2 of 3 · Q1|Most users are in Europe;|data residency points the same way.|"
ok "third more is depth 3, unindented wrap kept" "$(run "$B" more 2>&1 | tr '\n' '|')" \
   "Depth 3 of 3 · Q1|Everything else,|wrapped onto an unindented line.|"
OUT="$(run "$B" more 2>&1)"; RC=$?
ok "the fourth hands over to the session"    "$RC" 5
ok "…in one sentence"                        "$(printf '%s\n' "$OUT" | grep -c . | tr -d ' ')" 1
ok "more never edits the task"               "$(cmp -s "$B/$TASK_REL" "$TMP/more.before" && echo yes || echo no)" yes
ok "…and its counter is invisible to git"    "$(git -C "$B" status --porcelain | wc -l | tr -d ' ')" 0
ok "Q2 has no stored depth: exit 5 at once"  "$(run "$B" Q2 more >/dev/null 2>&1; echo $?)" 5
run "$B" 1 >/dev/null 2>&1
ok "answering clears the counter"            "$(find "$B/.loopd/.answer-depth" -type f ! -name .gitignore | grep -c . | tr -d ' ')" 0
ok "the script calls no model"               "$(grep -cE '\bclaude\b' "$SH" | tr -d ' ')" 0

B="$(fixture unsaved)"
mkdir -p "$B/.loopd" && : > "$B/.loopd/.answer-depth"
OUT="$(run "$B" more 2>/dev/null)"; RC=$?
ok "a depth it cannot save fails at exit 6"  "$RC" 6
ok "…and shows no depth"                     "$(printf '%s' "$OUT" | grep -c 'Depth' | tr -d ' ')" 0
rm -f "$B/.loopd/.answer-depth"; mkdir -p "$B/.loopd/.answer-depth"; : > "$B/.loopd/.answer-depth/.gitignore"
OUT="$(run "$B" more 2>&1)"
ok "once it can, the count starts at depth 1" "$(head -n1 <<<"$OUT")" "Depth 1 of 3 · Q1"
ok "…and an emptied ignore rule is restored" "$(git -C "$B" status --porcelain | wc -l | tr -d ' ')" 0

echo
echo "== NO OPEN QUESTION: one sentence, exit 1 =="
B="$(fixture none)"
OUT="$(run "$B" 1 >/dev/null 2>&1; run "$B" x >/dev/null 2>&1; run "$B" 1 2>&1)"; RC=$?
ok "it refuses"                              "$RC" 1
ok "…with one sentence"                      "$OUT" "task-001-x has no open question."

echo
echo "== SYNC: a rejected rebase stops at exit 4, aborts its own rebase, never forces =="
B="$(fixture race)"
git clone -q -b main "$B.git" "$TMP/other" 2>/dev/null; git -C "$TMP/other" config user.name o; git -C "$TMP/other" config user.email o@example.com
sed -i.bak 's/"Q1: which region?", //' "$TMP/other/$TASK_REL" && rm -f "$TMP/other/$TASK_REL.bak"
git -C "$TMP/other" commit -qam "other clone edits the list" && git -C "$TMP/other" push -q origin main
REMOTE_BEFORE="$(git -C "$B.git" rev-parse main)"
OUT="$(run "$B" 1 2>&1)"; RC=$?
ok "it exits 4"                              "$RC" 4
ok "…the answer is committed locally"        "$(git -C "$B" log -1 --format=%s)" "docs: answer Q1 on task-001-x"
ok "…no rebase is left in progress"          "$([ -d "$B/.git/rebase-merge" ] || [ -d "$B/.git/rebase-apply" ] && echo yes || echo no)" no
ok "…and the remote is untouched"            "$(git -C "$B.git" rev-parse main)" "$REMOTE_BEFORE"
ok "the script never forces a push"          "$(grep -cE -- '--force|push -f' "$SH" | tr -d ' ')" 0
B="$(fixture foreign)"
git clone -q -b main "$B.git" "$TMP/other2" 2>/dev/null; git -C "$TMP/other2" config user.name o; git -C "$TMP/other2" config user.email o@example.com
sed -i.bak 's/"Q1: which region?", //' "$TMP/other2/$TASK_REL" && rm -f "$TMP/other2/$TASK_REL.bak"
git -C "$TMP/other2" commit -qam "other clone edits the list" && git -C "$TMP/other2" push -q origin main
# A shim whose `pull` lets ANOTHER process start a rebase first, then fails as git would.
mkdir -p "$TMP/shim"; REAL_GIT="$(command -v git)"
cat > "$TMP/shim/git" <<SHIM
#!/usr/bin/env bash
case " \$* " in *" pull --rebase "*)
  "$REAL_GIT" fetch -q; GIT_REFLOG_ACTION=tick "$REAL_GIT" rebase '@{u}' >/dev/null 2>&1; exit 1 ;; esac
exec "$REAL_GIT" "\$@"
SHIM
chmod +x "$TMP/shim/git"
OUT="$(cd "$B" && PATH="$TMP/shim:$PATH" bash "$SH" "$TASK_REL" 1 2>&1)"; RC=$?
ok "a rebase another process started: exit 4" "$RC" 4
ok "…and it is left in progress, not aborted" "$([ -d "$B/.git/rebase-merge" ] || [ -d "$B/.git/rebase-apply" ] && echo yes || echo no)" yes
ok "…saying so"                              "$(printf '%s' "$OUT" | grep -c 'did not start' | tr -d ' ')" 1
B="$(fixture solo)"; git -C "$B" branch -q --unset-upstream
OUT="$(run "$B" 1 2>&1)"; RC=$?
ok "no upstream: committed, not pushed, exit 0" "$RC,$(git -C "$B" log -1 --format=%s)" "0,docs: answer Q1 on task-001-x"

echo
echo "== THE SKILL routes arguments to the script =="
ok "the skill may run answer.sh"             "$(grep -c 'scripts/answer.sh' "$SKILL" | awk '{print ($1>0)?"yes":"no"}')" yes
ok "…and stays human-invoked only"           "$(grep -c '^disable-model-invocation: true' "$SKILL" | tr -d ' ')" 1

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
