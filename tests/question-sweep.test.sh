#!/usr/bin/env bash
# question-sweep.test.sh — plugin/scripts/question-sweep.sh and fold-answers.sh --sweep against
# a fixture bundle and a stub gh: true, false, unknown and refused predicates, a judgement
# question untouched, agent-written evidence refused, --apply annotating without answering,
# the human's reply folding it, plus the SCHEMA / tick wiring. Reasoning: ai-control-panel-guards/task-005.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
QS="$REPO/plugin/scripts/question-sweep.sh"
FOLD="$REPO/plugin/scripts/fold-answers.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/question-sweep.XXXXXX")" || { echo "mktemp -d failed" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
has() { printf '%s\n' "$1" | grep -cF -- "$2" | tr -d ' '; }
GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -c user.name=t \
  -c user.email=t@example.com -c commit.gpgsign=false -c core.hooksPath=/dev/null \
  -c init.defaultBranch=main "$@"; }

SHA="$(printf 'a%.0s' $(seq 40))"
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/gh.log"
case "\$*" in
  'pr view https://github.com/example-user-007/app/pull/1 --json state --jq .state') echo MERGED ;;
  'pr view https://github.com/example-user-007/app/pull/2 --json state --jq .state') echo OPEN ;;
  'api repos/example-user-007/app --jq .default_branch') echo main ;;
  'api repos/example-user-007/app/commits/main --jq .sha') echo $SHA ;;
  *"contents/conf/app%20cfg.json?ref=$SHA") printf '{ "mode": "on" }\n' ;;
  *"contents/absent.txt?ref=$SHA") echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;;
  *) echo 'gh: offline' >&2; exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

B="$TMP/bundle"; P="$B/projects/demo"; mkdir -p "$P/tasks"
GIT init -q "$B"; GIT -C "$B" remote add origin https://github.com/example-user-007/bundle.git
echo '{ "org": "example-user-007" }' > "$B/instance.config.json"
cat > "$P/project.md" <<'EOF'
---
type: Project
title: "Demo"
status: active
acknowledged_decisions:
  - "2026-11-01T00:00:00Z by example-user-008 · D1: use the queue --- ok"
  - "2026-11-01T00:00:00Z by <unknown> · D2: use a cache --- ok"
  - "2026-11-01T00:00:00Z by example-user-008 · D3: use a lock --- no, a lease"
  - "2026-11-01T00:00:00Z by loopd:project-manager · D4: use a pool --- ok"
---
EOF
PR=https://github.com/example-user-007/app/pull
cat > "$P/tasks/t1.md" <<EOF
---
type: Task
title: "Sweep"
status: draft
open_questions:
  - "Q1: has the fix landed? check: pr-merged $PR/1"
  - "Q2: has the rename landed? check: pr-merged $PR/2"
  - "Q3: which region should we default to?"
  - "Q4: is the mode switched on? check: file example-user-007/app:conf/app cfg.json=\\"mode\\": \\"on\\""
  - "Q5: does the file exist? check: file example-user-007/app:absent.txt"
  - "Q6: did the agent finish? check: finding knowledge/findings/done.md"
  - "Q7: queue? check: decision D1"
  - "Q8: cache? check: decision D2"
  - "Q9: lock? check: decision D3"
  - "Q10: pool? check: decision D4"
  - "Q11: is the API up? check: pr-merged $PR/3"
  - "Q12: do: resume the hand-off check: pr-merged $PR/1"
  - "Q13: already answered check: pr-merged $PR/1 --- yes"
answered_questions: [ ]
---

# Context
EOF
GIT -C "$B" add -A; GIT -C "$B" commit -qm seed

echo "== verdicts (read-only)"
before="$(cat "$P/tasks/t1.md")"
out="$(cd "$B" && bash "$QS" 2>&1)"; rc=$?
v() { printf '%s\n' "$out" | awk -F'\t' -v q="$1" '$3 == q { print $1 }'; }
ok "exit 0" "$rc" 0
ok "pr merged ⇒ true" "$(v Q1)" true
ok "pr open ⇒ false" "$(v Q2)" false
ok "no predicate ⇒ judgement, not listed" "$(has "$out" "	Q3	")" 0
ok "file value on default ⇒ true" "$(v Q4)" true
ok "file evidence is <owner>/<repo>@<sha>:<path>" "$(has "$out" "example-user-007/app@$SHA:conf/app cfg.json")" 1
ok "file absent (404) ⇒ false" "$(v Q5)" false
ok "agent-written evidence (a Finding) ⇒ refused" "$(v Q6)" refused
ok "decision acked by a login ⇒ true" "$(v Q7)" true
ok "decision evidence cites the committed project.md" "$(has "$out" "example-user-007/bundle@$(GIT -C "$B" rev-parse HEAD):projects/demo/project.md")" 1
ok "decision stamped <unknown> ⇒ refused" "$(v Q8)" refused
ok "decision overturned ⇒ false" "$(v Q9)" false
ok "decision stamped loopd:project-manager ⇒ refused" "$(v Q10)" refused
ok "gh failure ⇒ unknown" "$(v Q11)" unknown
ok "do: hand-off never swept" "$(has "$out" "	Q12	")" 0
ok "answered entry never swept" "$(has "$out" "	Q13	")" 0
ok "summary: 3 true, 12 waiting" "$(printf '%s\n' "$out" | tail -1)" "sweep: 3 true, 12 waiting on the human"
ok "refused kind asks gh nothing" "$(grep -c finding "$TMP/gh.log" | tr -d ' ')" 0
ok "without --apply the task is untouched" "$([ "$before" = "$(cat "$P/tasks/t1.md")" ] && echo same)" same

echo "== --apply annotates, never answers"
(cd "$B" && bash "$QS" --apply projects/demo/tasks/t1.md >/dev/null); rc=$?
ok "apply exit 0" "$rc" 0
open="$(bash "$FOLD" --list "$P/tasks/t1.md" open_questions)"
ok "still 13 open entries (promotion still blocked)" "$(printf '%s\n' "$open" | grep -c .)" 13
ok "Q1 carries its sweep note" "$(has "$open" "Q1: has the fix landed? check: pr-merged $PR/1 · sweep: pr-merged $PR/1 true @ $PR/1")" 1
ok "three entries swept" "$(has "$open" ' · sweep: ')" 3
ok "a false predicate is not annotated" "$(printf '%s\n' "$open" | grep '^Q2:' | grep -c 'sweep:' | tr -d ' ')" 0
ok "the note writes no answer" "$(printf '%s\n' "$open" | grep 'sweep:' | grep -c ' --- ' | tr -d ' ')" 0
again="$(cd "$B" && bash "$QS" --apply projects/demo/tasks/t1.md)"
ok "a swept entry is not swept twice" "$(printf '%s\n' "$again" | tail -1)" "sweep: 0 true, 12 waiting on the human"

echo "== the human's reply folds it, stamped by a login"
q1="$(printf '%s\n' "$open" | grep '^Q1:')"; q4="$(printf '%s\n' "$open" | grep '^Q4:')"
(cd "$B" && bash "$FOLD" --answer "$q1" ok projects/demo/tasks/t1.md >/dev/null)
(cd "$B" && bash "$FOLD" --answer "$q4" "no — the flag is read from env, still off" projects/demo/tasks/t1.md >/dev/null)
ans="$(bash "$FOLD" --list "$P/tasks/t1.md" answered_questions)"
ok "ok folds the swept entry" "$(has "$ans" "· $q1 --- ok")" 1
ok "a reply against a wrong sweep folds as the human's answer" "$(has "$ans" "$q4 --- no — the flag")" 1
ok "no fold stamp is the loop's" "$(has "$ans" 'by loopd:')" 0

echo "== fold-answers --sweep refusals"
fold_rc() { bash "$FOLD" --sweep "$@" "$P/tasks/t1.md" >/dev/null 2>&1; echo $?; }
ok "an entry not in the list ⇒ 3" "$(fold_rc 'Q99: nope' x)" 3
ok "a note carrying ' --- ' ⇒ 3" "$(fold_rc "$(printf '%s\n' "$open" | grep '^Q2:')" 'a --- b')" 3

echo "== wiring"
ok "SCHEMA defines the Evidence sweep" "$(grep -c '^### Evidence sweep' "$REPO/plugin/seed/SCHEMA.md")" 1
ok "Decisions name the human names the sweep" "$(awk '/^## Decisions name the human/,/^# Ownership/' "$REPO/plugin/seed/SCHEMA.md" | grep -c 'loopd:project-manager')" 1
ok "the tick core runs the sweep" "$(grep -c 'question-sweep.sh --apply' "$REPO/plugin/agents/project-manager.md")" 1

echo "question-sweep: $pass passed, $fail failed"
[ "$fail" = 0 ]
