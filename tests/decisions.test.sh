#!/usr/bin/env bash
# `decisions:` on project.md — refine's choices made on the owner's behalf
# (loopd-improvements/task-002): the fold (`fold-answers.sh --keys`), the `👀 review` row,
# the tick-delta DELTA and the qa-reviewer prompt text.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO/plugin/scripts"
. "$S/bundle-paths.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/decisions.XXXXXX")" || { echo "decisions.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi }
GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -c user.email=t@example.com \
          -c user.name=Test -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
FOLD() { bash "$S/fold-answers.sh" --keys decisions acknowledged_decisions "$@"; }
n() { grep -c . | tr -d ' '; }

D1='D1: PostgreSQL, not DynamoDB — alternatives: DynamoDB; why: relational; reversible: yes'
D2='D2: no cache — alternatives: redis, in-memory; why: low load; reversible: yes'
D3='D3: JWT sessions — alternatives: cookies; why: stateless; reversible: no'

echo "== fold: ack and overturn both move, nothing re-folds, nothing is deleted =="
P="$TMP/project.md"
printf -- '---\ntype: Project\ntitle: "P"\nstatus: active\ndecisions: [ "%s --- ok", "%s --- use redis, 5 min TTL", "%s" ]\n---\n\nbody\n' \
  "$D1" "$D2" "$D3" > "$P"
ok "the fold exits 0"                   "$(FOLD "$P" >/dev/null 2>&1; echo $?)" 0
ok "decisions: holds only the unanswered" "$(bash "$S/fold-answers.sh" --list "$P" decisions)" "$D3"
ok "ack: moved with its answer verbatim" \
   "$(bash "$S/fold-answers.sh" --list "$P" acknowledged_decisions | grep -cE "^[0-9T:Z-]+ by .+ · $D1 --- ok\$" | tr -d ' ')" 1
ok "overturn: moved with its answer verbatim" \
   "$(bash "$S/fold-answers.sh" --list "$P" acknowledged_decisions | grep -cF "· $D2 --- use redis, 5 min TTL" | tr -d ' ')" 1
ok "the overturn's fresh D<n> appends to decisions:" \
   "$(FOLD --add "$P" 'D4: redis, 5 min TTL — alternatives: none; why: D2 overturned; reversible: yes' >/dev/null 2>&1
      bash "$S/fold-answers.sh" --list "$P" decisions | n)" 2
cp "$P" "$TMP/before"; FOLD "$P" >/dev/null 2>&1
ok "no-refold: a second fold writes nothing" "$(cmp -s "$P" "$TMP/before" && echo yes || echo no)" yes
ok "no-delete: every D<n> is still in the document" \
   "$(for d in D1: D2: D3: D4:; do grep -c "$d" "$P"; done | awk '$1 > 0' | n)" 4
ok "--add of an acknowledged D<n> adds nothing" \
   "$(FOLD --add "$P" "$D1" 2>/dev/null)" "added: 0 entries"
ok "the default pair still refuses a missing answered_questions:" \
   "$(printf -- '---\nopen_questions: [ "Q1: a --- b" ]\n---\n' > "$TMP/t.md"; bash "$S/fold-answers.sh" "$TMP/t.md" >/dev/null 2>&1; echo $?)" 3

echo
echo "== the 👀 review row: one per unanswered D<n>, before approve, mine/held gated =="
I="$TMP/inst"; mkdir -p "$I/projects/demo/tasks" "$I/$AB_DIR"; : > "$I/$AB_AWAITING"
printf '{ "org": "demo" }\n' > "$I/instance.config.json"; printf "# SCHEMA\n" > "$I/$AB_SCHEMA"
proj() { # <slug> <title> <extra frontmatter>
  mkdir -p "$I/projects/$1/tasks"
  printf -- '---\ntype: Project\ntitle: "%s"\nstatus: active\n%s---\n' "$2" "$3" > "$I/projects/$1/project.md"
  printf -- '---\ntype: Task\ntitle: "%s task"\nstatus: draft\nacceptance_criteria: [ "c" ]\nopen_questions: [ ]\n---\n' \
    "$2" > "$I/projects/$1/tasks/task-001-a.md"
}
proj demo Demo "decisions: [ \"$D3\", \"$D2 --- ok\" ]
"
proj plain Plain ""
bash "$S/build-awaiting.sh" --instance "$I" >/dev/null 2>&1
AW="$I/$AB_AWAITING"
ok "one review row per unanswered D<n>" "$(grep -c '\*\*review\*\*' "$AW" | tr -d ' ')" 1
ok "…glyph after \`* \`, linking project.md" \
   "$(grep -cF "* 👀 **review** — [Demo](/projects/demo/project.md) · $D3" "$AW" | tr -d ' ')" 1
ok "…sorted before approve" \
   "$(awk '/\*\*review\*\*/ && !r {r=NR} /\*\*approve\*\*.*Demo task/ {a=NR} END {print (r && a && r < a) ? "yes" : "no"}' "$AW")" yes
ok "…without withholding it" "$(grep -c '\*\*approve\*\*' "$AW" | tr -d ' ')" 2
ok "no decisions: key ⇒ 0 review rows" "$(grep -c 'review\*\* — \[Plain' "$AW" | tr -d ' ')" 0
proj theirs Theirs "owner: someone-else
decisions: [ \"$D1\" ]
"
proj held Held "decisions: [ \"$D1\" ]
"
sed -i.bak 's/^status: active/status: paused/' "$I/projects/held/project.md"
printf '{ "ownerGithubUser": "me" }\n' > "$I/instance.config.local.json"
bash "$S/build-awaiting.sh" --instance "$I" >/dev/null 2>&1
ok "the other human's project ⇒ 0 review rows" "$(grep -c 'review\*\* — \[Theirs' "$AW" | tr -d ' ')" 0
ok "a paused project ⇒ 0 review rows"          "$(grep -c 'review\*\* — \[Held' "$AW" | tr -d ' ')" 0
ok "…and mine still renders"                   "$(grep -c 'review\*\* — \[Demo' "$AW" | tr -d ' ')" 1
proj empty Empty "decisions: [ \"$D1 --- \", \"$D2 --- a --- \" ]
"
bash "$S/build-awaiting.sh" --instance "$I" >/dev/null 2>&1
ok "an empty final \` --- \` answer keeps its review row" "$(grep -c 'review\*\* — \[Empty' "$AW" | tr -d ' ')" 2

echo
echo "== tick-delta: an answered D<n> is a DELTA naming step 2; folded, it is IDLE =="
B="$TMP/bundle"; mkdir -p "$B/projects/p/tasks"
printf -- '---\ntype: Project\nstatus: active\ndecisions: [ "%s --- ok" ]\n---\n' "$D1" > "$B/projects/p/project.md"
printf -- '---\ntype: Task\nstatus: done\n---\n' > "$B/projects/p/tasks/t1.md"
printf '/%s\n' "$AB_STATE_DIR" > "$B/.gitignore"
GIT -C "$B" init -q && GIT -C "$B" add -A && GIT -C "$B" commit -qm init
bash "$S/tick-delta.sh" record --instance "$B" >/dev/null 2>&1
OUT="$(bash "$S/tick-delta.sh" check --instance "$B" 2>&1)"; RC=$?
ok "an answered D<n> after a record ⇒ DELTA (exit 1)" "$RC" 1
ok "…naming decisions:"  "$(printf '%s\n' "$OUT" | grep -c '^DELTA: .*decisions:' | tr -d ' ')" 1
ok "digest names step 2 for it, every task terminal" \
   "$(bash "$S/tick-delta.sh" digest --instance "$B" 2>/dev/null | grep '^steps:' | grep -c 'step-2-refine-drafts.md' | tr -d ' ')" 1
FOLD "$B/projects/p/project.md" >/dev/null 2>&1
GIT -C "$B" commit -qam fold
bash "$S/tick-delta.sh" record --instance "$B" >/dev/null 2>&1
ok "folded ⇒ IDLE (exit 0)" "$(bash "$S/tick-delta.sh" check --instance "$B" >/dev/null 2>&1; echo $?)" 0
ok "…and digest no longer names step 2" \
   "$(bash "$S/tick-delta.sh" digest --instance "$B" 2>/dev/null | grep '^steps:' | grep -c 'step-2' | tr -d ' ')" 0
FOLD --add "$B/projects/p/project.md" "$D2" >/dev/null 2>&1
sed -i.bak "s/\"$D2\"/\"$D2 --- \"/" "$B/projects/p/project.md"; rm -f "$B/projects/p/project.md.bak"
GIT -C "$B" commit -qam empty; bash "$S/tick-delta.sh" record --instance "$B" >/dev/null 2>&1
ok "an empty \` --- \` answer is not owed a fold ⇒ IDLE" \
   "$(grep -c "$D2 --- \"" "$B/projects/p/project.md" | tr -d ' ')/$(bash "$S/tick-delta.sh" check --instance "$B" >/dev/null 2>&1; echo $?)" 1/0

echo
echo "== the prompt text =="
QA="$REPO/plugin/agents/qa-reviewer.md"; S2="$REPO/plugin/tick-steps/step-2-refine-drafts.md"
ok "qa-reviewer's Unapproved decision check reads acknowledged_decisions:" \
   "$(grep -B4 'gets one "Unapproved decision:"' "$QA" | tr '\n' ' ' | grep -c 'answered_questions` nor the project.s `acknowledged_decisions:`' | tr -d ' ')" 1
ok "…from the project.md its brief names" "$(grep -c 'in the `project.md` your brief names' "$QA" | tr -d ' ')" 1
ok "…and an overturned entry approves the answer, not the original" \
   "$(tr '\n' ' ' < "$QA" | grep -c 'the owner.s answer is the approved *choice and a PR that implements the original one gets the line' | tr -d ' ')" 1
ok "the QA brief carries the project.md path" \
   "$(grep -c "The brief also names the task's \`project.md\` path" "$REPO/plugin/tick-steps/step-4-advance.md" | tr -d ' ')" 1
ok "step 2 names the six decision classes" \
   "$(tr '\n' ' ' < "$S2" | grep -c 'technology, topology, *data-model, consistency or caching, security-model or external-dependency choice' | tr -d ' ')" 1
ok "…says a file or function name is not one" "$(grep -c 'Naming a file or a function is not one' "$S2" | tr -d ' ')" 1
ok "…an overturn of a done task becomes a new draft task" \
   "$(tr '\n' ' ' < "$S2" | grep -c 'the *change it now needs is a new `draft` task, never a rewrite of that one' | tr -d ' ')" 1
ok "…and owns the fold whatever the task statuses" \
   "$(grep -c "decision fold is this step's whatever the project's task statuses" "$S2" | tr -d ' ')" 1

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
