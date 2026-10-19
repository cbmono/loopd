#!/usr/bin/env bash
# unblock.sh — `/loopd:unblock <task>` against a real bundle clone with a bare remote: it
# refuses a task that is not `blocked`, shows the blocker in the session without writing,
# and with a decision stamps one `# Notes` line, zeroes stall_count and returns the task to
# `ready`, committed as the human and pushed — in one atomic write, so a retry never doubles it.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SH="$REPO/plugin/scripts/unblock.sh"
SKILL="$REPO/plugin/skills/unblock/SKILL.md"
command -v python3 >/dev/null 2>&1 || { echo "unblock.test: python3 required" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/unblock-test.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi }

TASK_REL="projects/p/tasks/task-001-x.md"
BLOCKER="CI red on the same check after round 2"
fixture() { # <name> <status> — a bundle clone of a bare remote, one escalated task
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
open_questions: [ ]
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
echo "== THE SKILL =="
ok "the skill runs unblock.sh"               "$(grep -c 'scripts/unblock.sh' "$SKILL" | awk '{print ($1>0)?"yes":"no"}')" yes
ok "…and stays human-invoked only"           "$(grep -c '^disable-model-invocation: true' "$SKILL" | tr -d ' ')" 1

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
