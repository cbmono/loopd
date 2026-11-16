#!/usr/bin/env bash
#
# fold-terminal-answers.test.sh — the tick's script fold of answered questions on `done` and
# `cancelled` tasks, paused projects included (task-002, D5), against a stamped git instance.
# Both directions: a terminal task's answer moves and stops naming step 2; a live task's answer
# (in-progress or draft, active or paused) is left for the model and still names its step.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SH="$REPO/plugin/scripts/fold-terminal-answers.sh"
FOLD="$REPO/plugin/scripts/fold-answers.sh"
TD="$REPO/plugin/scripts/tick-delta.sh"
PM="$REPO/plugin/agents/project-manager.md"
command -v python3 >/dev/null 2>&1 || { echo "fold-terminal-answers.test: python3 required" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/fold-terminal.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -c user.email=t@example.com \
          -c user.name=Test -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }

INST="$TMP/inst"
bash "$REPO/plugin/scripts/init-bundle.sh" "$INST" >/dev/null 2>&1 || { echo "stamp failed" >&2; exit 2; }
mkdir -p "$INST/projects/on/tasks" "$INST/projects/off/tasks"
printf -- '---\ntype: Project\nstatus: active\n---\n' > "$INST/projects/on/project.md"
printf -- '---\ntype: Project\nstatus: paused\n---\n' > "$INST/projects/off/project.md"
task() { # <path> <status> <open-entry> [body]
  printf -- '---\ntype: Task\nkind: build\nstatus: %s\nacceptance_criteria: [ "c" ]\nopen_questions:\n  - "%s"\nanswered_questions: [ ]\n---\n\n%s\n' \
    "$2" "$3" "${4:-body}" > "$INST/$1"
}
commit() { GIT -C "$INST" add -A >/dev/null 2>&1; GIT -C "$INST" commit -qm "$1" >/dev/null 2>&1; }
GIT -C "$INST" init -q
run() { ( cd "$INST" && bash "$SH" ); }
digest() { ( cd "$INST" && PATH="$TMP/bin:$PATH" bash "$TD" digest 2>/dev/null ) | grep '^steps:'; }
names() { grep -c "$1" <<<"${2-$(digest)}" | tr -d ' '; }
openq() { bash "$FOLD" --list "$INST/$1" open_questions | grep -c . | tr -d ' '; }
ansq() { bash "$FOLD" --list "$INST/$1" answered_questions | grep -c . | tr -d ' '; }
# No PR is read here; a gh that answers nothing proves it.
mkdir -p "$TMP/bin"; printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/gh"; chmod +x "$TMP/bin/gh"

echo "== terminal tasks: a paused project's done, an active project's cancelled =="
DONE=projects/off/tasks/task-001.md; CANC=projects/on/tasks/task-002.md
task "$DONE" done "Q1: colour? --- blue"
task "$CANC" cancelled "Q1: size? --- large"
commit fixture
ok "precondition: the digest names step 2 for them today" "$(names step-2-refine-drafts.md)" 1
OUT="$(run)"; RC=$?
ok "it exits 0"                                       "$RC" 0
ok "one folded line per rewritten doc, instance-relative" \
   "$(printf '%s\n' "$OUT" | sort | tr '\n' '|')" "folded $DONE|folded $CANC|"
ok "the paused project's done task: open_questions empty" "$(openq "$DONE")" 0
ok "…its answer is in answered_questions"           "$(ansq "$DONE")" 1
ok "the active project's cancelled task: open empty" "$(openq "$CANC")" 0
ok "…its answer is in answered_questions"           "$(ansq "$CANC")" 1
commit folded
ok "the next digest names no step 2"                 "$(names step-2-refine-drafts.md)" 0
ok "…and no step 3"                                  "$(names step-3-dispatch.md)" 0
ok "a second run rewrites nothing"                   "$(run)" ""

echo "== live tasks keep the model fold and their step =="
# One at a time, so the steps line can only be naming the doc under test.
live() { # <path> <status> <want step-2> <want step-4> [body]
  task "$1" "$2" "Q1: which? --- this one" "${5:-body}"; commit "add $1"
  cp "$INST/$1" "$TMP/before"
  local out d; out="$(run)"; d="$(digest)"
  ok "$2 in $(cut -d/ -f2 <<<"$1"): no output"            "$out" ""
  ok "…and the doc is byte-identical"                      "$(cmp -s "$INST/$1" "$TMP/before" && echo yes || echo no)" yes
  ok "…and the digest still names step 2"                   "$(names step-2-refine-drafts.md "$d")" "$3"
  ok "…and step 4 as expected"                              "$(names step-4-advance.md "$d")" "$4"
  rm -f "$INST/$1"; commit "drop $1"
}
live projects/on/tasks/task-010.md in-progress 1 1
live projects/off/tasks/task-011.md in-progress 1 1
live projects/on/tasks/task-012.md draft 1 0
live projects/off/tasks/task-013.md draft 1 0
live projects/off/tasks/task-014.md draft 1 1 "Q1: needs handed off to the owner."
live projects/on/tasks/task-015.md draft 1 1 "Q1: needs handed off to the owner."

echo "== a doc it cannot fold is named, left alone, and the run carries on =="
BAD=projects/on/tasks/task-020.md; BOTH=projects/on/tasks/task-021.md; NEXT=projects/on/tasks/task-022.md
printf -- '---\ntype: Task\nstatus: done\nopen_questions: [ "Q1: x? --- y", \n---\n' > "$INST/$BAD"
printf -- '---\ntype: Task\nstatus: done\nopen_questions: [ "Q1: x? --- y", "Q1: x?" ]\nanswered_questions: [ ]\n---\n' > "$INST/$BOTH"
mkdir -p "$INST/projects/gone/tasks"; NOPM=projects/gone/tasks/task-023.md
task "$NOPM" done "Q1: z? --- w"
task "$NEXT" done "Q1: next? --- yes"
for f in "$BAD" "$BOTH" "$NOPM"; do cp "$INST/$f" "$TMP/$(basename "$f").before"; done
OUT="$(run)"; RC=$?
ok "it still exits 0"                                  "$RC" 0
ok "fold-answers exit 3 is a skipped line"             "$(grep -c "^skipped $BAD fold-answers exit 3: " <<<"$OUT" | tr -d ' ')" 1
ok "fold-answers exit 4 is a skipped line"             "$(grep -c "^skipped $BOTH fold-answers exit 4: " <<<"$OUT" | tr -d ' ')" 1
ok "project-paused exit 2 is a skipped line"           "$(grep -c "^skipped $NOPM project-paused: " <<<"$OUT" | tr -d ' ')" 1
for f in "$BAD" "$BOTH" "$NOPM"; do
  ok "…$(basename "$f") is byte-identical" "$(cmp -s "$INST/$f" "$TMP/$(basename "$f").before" && echo yes || echo no)" yes
done
ok "…and the doc after them is still folded"           "$(grep -cx "folded $NEXT" <<<"$OUT" | tr -d ' ')" 1
ok "outside an instance root: exit 2"                  "$( (cd "$TMP" && bash "$SH" >/dev/null 2>&1); echo $?)" 2

echo "== the script is a writer outside the probe, on fold-answers.sh's own parser =="
ok "tick-delta.sh has no fold mode"                    "$(grep -c 'fold-terminal-answers' "$TD" | tr -d ' ')" 0
ok "the script calls fold-answers.sh"                  "$(grep -c 'fold-answers.sh" --instance' "$SH" | tr -d ' ')" 1
ok "…and parses no open_questions itself"              "$(grep -v '^[[:space:]]*#' "$SH" | grep -c 'open_questions' | tr -d ' ')" 0

echo "== the PM runs it before the digest, stages and reports each folded path =="
step1="$(awk '/^1\. \*\*Orient/,/^2\. \*\*Refine/' "$PM")"
flat="$(tr '\n' ' ' <<<"$step1" | tr -s ' ')"
fl="$(awk '/scripts\/fold-terminal-answers\.sh/ && !n { n = NR } END { print n }' <<<"$step1")"
dl="$(awk '/scripts\/tick-delta\.sh digest/ && !n { n = NR } END { print n }' <<<"$step1")"
ok "step 1 runs the script"                            "$([ -n "$fl" ] && echo yes || echo no)" yes
ok "…before the digest"                                "$([ -n "$fl" ] && [ -n "$dl" ] && [ "$fl" -lt "$dl" ] && echo yes || echo no)" yes
ok "…whatever the digest exits"                        "$(grep -c 'whatever the digest' <<<"$step1" | tr -d ' ')" 1
ok "…stages each folded path with commit-as.sh"        "$(grep -c '`folded <path>`[^.]*commit-as.sh' <<<"$flat" | tr -d ' ')" 1
ok "…and names it in the close summary"                "$(grep -c 'commit-as.sh`, name those paths in your close summary' <<<"$flat" | tr -d ' ')" 1

echo
echo "fold-terminal-answers.test: $pass passed, $fail failed"
[ "$fail" = 0 ]
