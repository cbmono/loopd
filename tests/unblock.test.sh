#!/usr/bin/env bash
# unblock.sh — reached through `/loopd:answer <blocked task>` (answer.sh routes it), against a
# real bundle clone with a bare remote: it refuses a task that is not `blocked`, shows the
# blocker in the session without writing, and with a decision stamps one `# Notes` line, zeroes
# stall_count and returns the task to `ready`, committed as the human and pushed — in one
# atomic write, so a retry never doubles it. A blocked task that still has open questions is
# refused naming them; a `Q<n>` or `--first` answer to one of them is an answer, not an unblock.
# `more`, `later` and a bare integer are refused as a decision unless `--text` forces them.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SH="$REPO/plugin/scripts/unblock.sh"
ANS="$REPO/plugin/scripts/answer.sh"
SKILL="$REPO/plugin/skills/answer/SKILL.md"
command -v python3 >/dev/null 2>&1 || { echo "unblock.test: python3 required" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/unblock-test.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi }

TASK_REL="projects/p/tasks/task-001-x.md"
BLOCKER="CI red on the same check after round 2"
fixture() { # <name> <status> [<open_questions value>] — a bundle clone of a bare remote, one escalated task
  local b="$TMP/$1"
  git init -q --bare "$b.git"
  git init -q -b main "$b"
  git -C "$b" config user.name "Example Human"; git -C "$b" config user.email t@example.com
  mkdir -p "$b/$(dirname "$TASK_REL")"
  printf '{ "ownerGithubUser": "example-user-007", "people": { "example-user-007": "u7@example.com" } }\n' > "$b/instance.config.json"
  cat > "$b/$TASK_REL" <<MD
---
type: Task
title: "T"
status: $2
stall_count: 2
last_blocker: "$BLOCKER"
open_questions: ${3:-[ ]}
---

# Context

body

# Notes

- **Stalled 2/2 rounds on the same blocker** — $BLOCKER  _(2026-10-18T10:00:00Z)_
MD
  git -C "$b" add -A && git -C "$b" commit -qm init
  git -C "$b" remote add origin "$b.git"
  git -C "$b" push -q -u origin main
  echo "$b"
}
run() { local b="$1"; shift; (cd "$b" && bash "$SH" "$TASK_REL" "$@"); }
field() { sed -n "s/^$2: *//p" "$1/$TASK_REL" | sed -n 1p; }

echo "== REFUSAL: a task that is not blocked is left exactly as it was =="
B="$(fixture ready in-progress)"
cp "$B/$TASK_REL" "$TMP/before"
OUT="$(run "$B" --decision use the staging key 2>&1)"; RC=$?
ok "it exits 1"                              "$RC" 1
ok "…in one sentence naming the status"      "$(printf '%s\n' "$OUT" | grep -c . | tr -d ' '),$(printf '%s' "$OUT" | grep -c 'in-progress, not blocked')" "1,1"
ok "…and writes nothing"                     "$(cmp -s "$B/$TASK_REL" "$TMP/before" && echo yes || echo no)" yes
ok "…and commits nothing"                    "$(git -C "$B" rev-list --count HEAD)" 1

echo
echo "== SHOW: the blocker and the escalation note, in the session only =="
B="$(fixture show blocked)"
cp "$B/$TASK_REL" "$TMP/before"
OUT="$(run "$B" 2>&1)"; RC=$?
ok "it exits 0"                              "$RC" 0
ok "…naming the last blocker"                "$(printf '%s' "$OUT" | grep -c "^Last blocker: $BLOCKER$")" 1
ok "…and the escalation note"                "$(printf '%s' "$OUT" | grep -c '^Escalation: - \*\*Stalled 2/2')" 1
ok "…writing nothing"                        "$(cmp -s "$B/$TASK_REL" "$TMP/before" && echo yes || echo no)" yes

echo
echo "== DECISION: one stamped note, the counter reset, back to ready, committed and pushed =="
B="$(fixture go blocked)"
OUT="$(run "$B" --decision use the staging key 2>&1)"; RC=$?
ok "it exits 0"                              "$RC" 0
ok "the note is stamped by the human's login" \
   "$(grep -cE '^- [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z by example-user-007: unblocked — use the staging key$' "$B/$TASK_REL")" 1
ok "…once, under # Notes, after the escalation" \
   "$(sed -n '/^# Notes/,$p' "$B/$TASK_REL" | grep -E '^- ' | sed -E 's/^- \*\*Stalled.*/S/; s/^- [0-9TZ:-]+ by .*/D/' | tr '\n' '|')" "S|D|"
ok "status is ready"                         "$(field "$B" status)" ready
ok "stall_count is 0"                        "$(field "$B" stall_count)" 0
ok "last_blocker is kept"                    "$(field "$B" last_blocker)" "\"$BLOCKER\""
ok "the commit is the human's, via people"   "$(git -C "$B" log -1 --format='%an <%ae>')" "Example Human <u7@example.com>"
ok "…and it reached the remote"              "$(git -C "$B.git" log -1 --format=%s main)" "docs: unblock task-001-x"
ok "the work tree is clean"                  "$(git -C "$B" status --porcelain | wc -l | tr -d ' ')" 0
ok "a second run refuses: it is not blocked any more" "$(run "$B" --decision again >/dev/null 2>&1; echo $?)" 1
B2="$(fixture empty blocked)"; OUT="$(run "$B2" --decision 2>&1)"; RC=$?
ok "an empty decision is a usage error"      "$RC" 2
ok "…named as usage, not an unbound variable" "$(printf '%s' "$OUT" | grep -c 'unbound' | tr -d ' ')" 0
ok "the script never forces a push"          "$(grep -cE -- '--force|push -f' "$SH" | tr -d ' ')" 0

echo
echo "== RETRY: a failed write leaves no note behind, so a retry records the decision once =="
B="$(fixture retry blocked)"
D="$B/$(dirname "$TASK_REL")"
chmod a-w "$D"
if [ -w "$D" ]; then
  echo "  SKIP  a read-only directory is still writable here (root?) — the retry case is not measured"
else
  OUT="$(run "$B" --decision use the staging key 2>&1)"; RC=$?
  chmod u+w "$D"
  ok "a write that cannot land exits 3"      "$RC" 3
  ok "…and the task is still blocked"        "$(field "$B" status)" blocked
  ok "…with no decision note"                "$(grep -c 'unblocked —' "$B/$TASK_REL" | tr -d ' ')" 0
  ok "…and no temp file left beside it"      "$(find "$D" -name '.unblock.*' | grep -c . | tr -d ' ')" 0
  run "$B" --decision use the staging key >/dev/null 2>&1
  ok "the retry records it once"             "$(grep -c 'unblocked — use the staging key$' "$B/$TASK_REL" | tr -d ' ')" 1
  ok "…and moves it to ready"                "$(field "$B" status)" ready
fi
chmod u+w "$D" 2>/dev/null
sed -i.bak 's/^status: ready$/status: blocked/' "$B/$TASK_REL" && rm -f "$B/$TASK_REL.bak"
run "$B" --decision use the staging key >/dev/null 2>&1
ok "a later blocking episode records the same decision again" \
   "$(grep -c 'unblocked — use the staging key$' "$B/$TASK_REL" | tr -d ' ')" 2

echo
echo "== ANSWER: a blocked task path routes to unblock.sh =="
ans() { local b="$1"; shift; (cd "$b" && bash "$ANS" "$TASK_REL" "$@"); }
B="$(fixture via blocked)"
cp "$B/$TASK_REL" "$TMP/before"
OUT="$(ans "$B" 2>&1)"; RC=$?
ok "no decision shows the blocker: exit 0"   "$RC" 0
ok "…naming it"                              "$(printf '%s' "$OUT" | grep -c "^Last blocker: $BLOCKER$")" 1
ok "…writing nothing"                        "$(cmp -s "$B/$TASK_REL" "$TMP/before" && echo yes || echo no)" yes
OUT="$(ans "$B" use the staging key 2>&1)"; RC=$?
ok "a decision unblocks it: exit 0"          "$RC" 0
ok "…stamped under # Notes"                  "$(grep -cE '^- [0-9TZ:-]+ by example-user-007: unblocked — use the staging key$' "$B/$TASK_REL")" 1
ok "…status ready, stall_count 0"            "$(field "$B" status),$(field "$B" stall_count)" "ready,0"
ok "…committed as the unblock"               "$(git -C "$B.git" log -1 --format=%s main)" "docs: unblock task-001-x"
B="$(fixture viatext blocked)"
printf 'retry\nwith the key\n' > "$TMP/decision"
ans "$B" --text-file "$TMP/decision" >/dev/null 2>&1
ok "--text-file carries the decision"        "$(grep -c 'unblocked — retry with the key$' "$B/$TASK_REL" | tr -d ' ')" 1
B="$(fixture notblocked in-progress)"
OUT="$(ans "$B" use the staging key 2>&1)"; RC=$?
ok "a task that is not blocked takes no unblock: exit 1" "$RC" 1
ok "…refused as having no question, not routed" "$OUT" "task-001-x has no open question."
ok "…and gets no note"                       "$(grep -c 'unblocked —' "$B/$TASK_REL" | tr -d ' ')" 0
Q1ONLY='
  - "Q1: which key?"'
B="$(fixture notblockedq in-progress "$Q1ONLY")"
OUT="$(ans "$B" use the staging key 2>&1)"; RC=$?
ok "…with an open question, the words answer it: exit 0" "$RC" 0
ok "…with no unblock note"                   "$(grep -c 'unblocked —' "$B/$TASK_REL" | tr -d ' ')" 0

echo
echo "== ANSWER: on a blocked task, more, later and a number are not a decision unless --text =="
B="$(fixture kw blocked)"
cp "$B/$TASK_REL" "$TMP/before"
for w in later more 7; do
  OUT="$(ans "$B" "$w" 2>&1)"; RC=$?
  ok "'$w' is refused: exit 1"               "$RC" 1
  ok "…pointing at --text $w"                "$(printf '%s' "$OUT" | grep -c -- "use --text $w\.$" | tr -d ' ')" 1
done
ok "…writing nothing"                        "$(cmp -s "$B/$TASK_REL" "$TMP/before" && echo yes || echo no)" yes
ok "…and committing nothing"                 "$(git -C "$B" rev-list --count HEAD)" 1
OUT="$(ans "$B" --text 2>&1)"; RC=$?
ok "an empty --text is a usage error"        "$RC" 2
OUT="$(ans "$B" --text later 2>&1)"; RC=$?
ok "--text later records it: exit 0"         "$RC" 0
ok "…as the decision"                        "$(grep -c 'unblocked — later$' "$B/$TASK_REL" | tr -d ' '),$(field "$B" status)" "1,ready"

echo
echo "== ANSWER: a blocked task with open questions is refused, naming them =="
QS='
  - "Q1: which key?"
  - "Q2: which region?"'
B="$(fixture mixed blocked "$QS")"
cp "$B/$TASK_REL" "$TMP/before"
OUT="$(ans "$B" use the staging key 2>&1)"; RC=$?
ok "it exits 1"                              "$RC" 1
ok "…naming Q1 and Q2"                       "$(printf '%s' "$OUT" | grep -c 'Q1, Q2')" 1
ok "…and writes nothing"                     "$(cmp -s "$B/$TASK_REL" "$TMP/before" && echo yes || echo no)" yes
OUT="$(ans "$B" Q1 the staging key 2>&1)"; RC=$?
ok "Q1 <answer> answers the question: exit 0" "$RC" 0
ok "…which leaves open_questions"            "$(bash "$REPO/plugin/scripts/fold-answers.sh" --list "$B/$TASK_REL" open_questions | grep -c '^Q1:' | tr -d ' ')" 0
ok "…and the task blocked"                   "$(field "$B" status)" blocked
ok "…with no unblock note"                   "$(grep -c 'unblocked —' "$B/$TASK_REL" | tr -d ' ')" 0

echo
echo "== ANSWER: an unnumbered entry on a blocked task is answered with --first, then unblocked =="
UNNUM='
  - "advisor: which key?"'
B="$(fixture unnumbered blocked "$UNNUM")"
cp "$B/$TASK_REL" "$TMP/before"
OUT="$(ans "$B" use the staging key 2>&1)"; RC=$?
ok "words alone are refused: exit 1"         "$RC" 1
ok "…naming the unnumbered entry and --first" "$(printf '%s' "$OUT" | grep -c '(an unnumbered entry).*--first' | tr -d ' ')" 1
ok "…and writes nothing"                     "$(cmp -s "$B/$TASK_REL" "$TMP/before" && echo yes || echo no)" yes
OUT="$(ans "$B" --first the staging key 2>&1)"; RC=$?
ok "--first answers it: exit 0"              "$RC" 0
ok "…which leaves open_questions"            "$(bash "$REPO/plugin/scripts/fold-answers.sh" --list "$B/$TASK_REL" open_questions | grep -c . | tr -d ' ')" 0
ok "…and the task blocked, with no unblock note" "$(field "$B" status),$(grep -c 'unblocked —' "$B/$TASK_REL" | tr -d ' ')" "blocked,0"
OUT="$(ans "$B" use the staging key 2>&1)"; RC=$?
ok "then the words unblock it: exit 0"       "$RC" 0
ok "…status ready"                           "$(field "$B" status)" ready

echo
echo "== THE SKILLS =="
# path-scan: absent — the unblock skill folded into answer; its absence IS the assertion
ok "the unblock skill is gone"               "$([ -e "$REPO/plugin/skills/unblock" ] && echo present || echo gone)" gone
ok "the answer skill names the blocked route" "$(grep -c 'blocked' "$SKILL" | awk '{print ($1>0)?"yes":"no"}')" yes
ok "…and stays human-invoked only"           "$(grep -c '^disable-model-invocation: true' "$SKILL" | tr -d ' ')" 1

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
