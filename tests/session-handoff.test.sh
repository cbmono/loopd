#!/usr/bin/env bash
#
# session-handoff.test.sh — a `blocked` role session whose job record carries `needs` is
# HANDED OFF: its text goes only to the ignored `.loopd/.handoffs/`, AWAITING.md shows one
# linked `👉 do` row, the task gets one fixed-text `Q<n>: do:` entry in one write, and the
# session is stopped; once answered, `--owed` names the resume, and the resumed session's
# next hand-off is a new entry. A done task's session is stopped whatever it is doing, after
# any pending `needs` is filed. Offline: `claude` is a stub that logs every call and never
# reaches a real session. Reasoning: docs/pm-design.md#step-4.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SH="$REPO/plugin/scripts/session-handoff.sh"
SESS="$REPO/plugin/scripts/agent-sessions.sh"
FOLD="$REPO/plugin/scripts/fold-answers.sh"
AW="$REPO/plugin/scripts/build-awaiting.sh"
ANS="$REPO/plugin/scripts/answer.sh"
BOARD="$REPO/plugin/scripts/build-board.sh"
S4="$REPO/plugin/tick-steps/step-4-advance.md"
S5="$REPO/plugin/tick-steps/step-5-reflect-merges.md"
for f in "$SH" "$SESS" "$FOLD" "$AW" "$ANS" "$BOARD" "$S4" "$S5"; do
  [ -f "$f" ] || { echo "session-handoff.test: $f not found" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || { echo "session-handoff.test: python3 required" >&2; exit 2; }

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
cnt() { grep -cF -- "$2" "$1" | tr -d ' '; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/session-handoff.XXXXXX")" || {
  echo "session-handoff.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# `claude agents` prints agents.json; `stop <short>` logs and marks the row stopped;
# `--bg --resume <uuid> <msg>` logs and prints what a flag-free resume prints.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  agents) [ -n "${STUB_FAIL:-}" ] && exit 1; cat "$STUB_DIR/agents.json" ;;
  stop) echo "stop $2" >> "$STUB_DIR/calls"
        [ -n "${STUB_STUCK:-}" ] && exit 0
        python3 -c 'import json, sys
p, i = sys.argv[1], sys.argv[2]
rows = json.load(open(p))
for r in rows:
    if r["id"] == i: r["state"] = "stopped"
json.dump(rows, open(p, "w"))' "$STUB_DIR/agents.json" "$2"; echo "stopped $2" ;;
  --bg) [ "$2" = --resume ] || exit 1
        printf 'resume %s %s\n' "$3" "$4" >> "$STUB_DIR/calls"
        s="${3%%-*}"; printf 'note: woke session %s with its saved options (x)\nbackgrounded · %s · demo\n' "$s" "$s" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/claude"
export STUB_DIR="$TMP" PATH="$TMP/bin:$PATH"
: > "$TMP/calls"

U1=a8b4344d-0000-4000-8000-000000000001   # in-review, needs = the measured jobs
U2=b2b2b2b2-0000-4000-8000-000000000002   # blocked task, needs with links and fold-hostile text
U3=c3c3c3c3-0000-4000-8000-000000000003   # blocked, no needs
U4=9d4e0877-0000-4000-8000-000000000004   # done task, blocked with jobs for after the merge
U5=e5e5e5e5-0000-4000-8000-000000000005   # done task, ended
U6=f6f6f6f6-0000-4000-8000-000000000006   # working
U7=a7a7a7a7-0000-4000-8000-000000000007   # blocked with needs, on a live waitingFor prompt
U8=d8d8d8d8-0000-4000-8000-000000000008   # done task, blocked, no needs
STARTED=1791557649233
agents() { # <state>... in U1..U8 order
  local i=0 out="" s u extra
  for s in "$@"; do i=$((i+1)); eval "u=\$U$i"; extra=""
    [ "$i" = 7 ] && extra=',"waitingFor":"login"'
    out="$out${out:+,}{\"id\":\"${u%%-*}\",\"sessionId\":\"$u\",\"kind\":\"background\",\"state\":\"$s\",\"startedAt\":$STARTED$extra}"; done
  printf '[%s]\n' "$out" > "$TMP/agents.json"
}
all_blocked() { agents blocked blocked blocked blocked done working blocked blocked; }
all_blocked
J="$TMP/jobs"
job() { mkdir -p "$J/${1%%-*}"; python3 -c 'import json, sys; print(json.dumps({"state": "blocked", "sessionId": sys.argv[1], "needs": sys.argv[2]}))' "$1" "$2" > "$J/${1%%-*}/state.json"; }
NEEDS1='review, apply and merge terraform#866; re-login SSO and run sim/simulate.sh, then gh run rerun 39260575390 -R example-user-007/labs'
job "$U1" "$NEEDS1"
job "$U2" 'Decide A --- --- B? See https://docs.example.com/guide.html#12 (attempt#2), [labs#3](https://evil.example.com) and PR #7;
  gh run rerun 11111111 -R example-user-007/labs, then gh run rerun 22222222 -R example-user-008/other'
mkdir -p "$J/${U3%%-*}"; printf '{"state":"blocked","suggestedReply":"x"}\n' > "$J/${U3%%-*}/state.json"
job "$U4" 'Merge PR #559 (labs). Then run the marketing backfill from 2025-10-20'
job "$U7" 'open this session to continue setup'

B="$TMP/bundle"; T="$B/projects/demo/tasks"; mkdir -p "$T" "$B/.loopd" "$B/repos/terraform"
AWF="$B/.loopd/AWAITING.md"; HO="$B/.loopd/.handoffs"
printf '{ "org": "example-user-008" }\n' > "$B/instance.config.json"
printf -- '---\ntype: Project\ntitle: Demo\nstatus: active\ntarget_repo: example-user-007/labs  # the default\n---\n' > "$B/projects/demo/project.md"
mk() { # <file> <status> <session> [open_questions]
  printf -- '---\ntype: Task\ntitle: %s\nkind: build\nstatus: %s\nsession: %s\nopen_questions: %s\n---\n\n# Notes\n\n* earlier note\n' \
    "$(basename "$1" .md)" "$2" "$3" "${4:-[ ]}" > "$1"
}
mk "$T/task-022-sso.md" in-review "$U1"
mk "$T/task-030-links.md" blocked "$U2" '[ "Q1: earlier? --- yes" ]'
mk "$T/task-031-none.md" blocked "$U3"
mk "$T/task-009-done.md" done "$U4"
mk "$T/task-010-ended.md" done "$U5"
mk "$T/task-032-working.md" in-progress "$U6"
mk "$T/task-033-prompt.md" in-review "$U7"
mk "$T/task-011-done.md" done "$U8"
run() { ( cd "$B" && bash "$SH" "$@" --jobs-dir "$J" 2>/dev/null ); echo "rc=$?"; }
one() { run "$@" | paste -sd ' ' -; }
render() { printf '# Awaiting you\n' > "$AWF"; bash "$AW" --instance "$B" >/dev/null 2>&1 || echo "build-awaiting rc=$?" >&2; }
id_of() { grep -oE 'hand-off [0-9a-f]{8}-[0-9a-f]{8}' "$1" | tail -1 | cut -d' ' -f2; }

echo "== an in-review task's needs: handed off, the agent's text kept out of git =="
OUT="$(one "$T/task-022-sso.md")"; ID1="$(id_of "$T/task-022-sso.md")"
ok "handed off as Q1, then stopped" "$OUT" "handed-off a8b4344d $ID1 Q1 rc=0"
ok "…the id is <short>-<8 hex>" "$(printf '%s' "$ID1" | grep -cE '^a8b4344d-[0-9a-f]{8}$')" 1
ok "…ONE fixed-text entry" "$(bash "$FOLD" --list "$T/task-022-sso.md" open_questions | grep -c "^Q1: do: finish the agent's hand-off $ID1 ")" 1
ok "…none of the agent's words in the task" "$(grep -cE 'terraform|simulate|SSO' "$T/task-022-sso.md")" 0
ok "…its Q1 block (1 option, 3 depths)" \
   "$(bash "$FOLD" --block Q1 "$T/task-022-sso.md" | python3 -c 'import json, sys; b = json.load(sys.stdin); print(b["options"][0][1], len(b["depths"]))')" "done 3"
ok "…one note" "$(cnt "$T/task-022-sso.md" "needs handed off $U1 · hand-off $ID1 · Q1 ·")" 1
ok "…the status is unchanged" "$(grep -c '^status: in-review$' "$T/task-022-sso.md")" 1
ok "…the text verbatim in the ignored store" "$(cat "$HO/$ID1.txt")" "$NEEDS1"
ok "…which ignores itself" "$(cat "$HO/.gitignore")" '*'
ok "…and the stop took the short id" "$(cnt "$TMP/calls" "stop a8b4344d")" 1
all_blocked
ok "a retry in the same round: same id, same entry" "$(one "$T/task-022-sso.md")" "handed-off a8b4344d $ID1 Q1 rc=0"
ok "…nothing written twice" "$(grep -c "hand-off $ID1" "$T/task-022-sso.md")" 3

echo "== a blocked task: links are ours, the agent's markdown is escaped =="
OUT="$(one "$T/task-030-links.md")"; ID2="$(id_of "$T/task-030-links.md")"
ok "handed off as Q2, after the answered Q1" "$OUT" "handed-off b2b2b2b2 $ID2 Q2 rc=0"
render
ok "one do row per hand-off" "$(grep -c '^\* 👉 \*\*do\*\* — \[task-022-sso\]' "$AWF")" 1
ok "…known repo#N links" "$(cnt "$AWF" '[terraform#866](https://github.com/example-user-007/terraform/pull/866)')" 1
ok "…a run id links its own -R repo" "$(cnt "$AWF" 'run rerun [39260575390](https://github.com/example-user-007/labs/actions/runs/39260575390)')" 1
ok "…the second -R is the second run's" "$(cnt "$AWF" '[22222222](https://github.com/example-user-008/other/actions/runs/22222222)')" 1
ok "…and the first stays the first's" "$(cnt "$AWF" '[11111111](https://github.com/example-user-007/labs/actions/runs/11111111)')" 1
ok "…PR #N on the task's repo (target_repo comment stripped)" "$(cnt "$AWF" 'PR [labs#7](https://github.com/example-user-007/labs/pull/7)')" 1
ok "…no link from a URL fragment" "$(cnt "$AWF" '/pull/12')" 0
ok "…nor from attempt#2" "$(cnt "$AWF" '/pull/2)')" 0
ok "…an agent-written link is escaped" "$(cnt "$AWF" '\]\(https://evil.example.com\)')" 1
ok "…so it links nowhere" "$(cnt "$AWF" '](https://evil')" 0
ok "…the row names its answer" "$(cnt "$AWF" 'then answer Q2 `done`')" 1
ok "…and nothing says claude attach" "$(cnt "$AWF" 'claude attach')" 0

echo "== the answer, the owed resume, and the next round's hand-off =="
ok "unanswered: not owed" "$(one --owed "$T/task-022-sso.md")" "not-owed unanswered rc=1"
sed -i.bak "s/^  - \"\\(Q1: do: .*\\)\"\$/  - \"\\1 --- done, and the SSO profile is labs-admin\"/" "$T/task-022-sso.md"
( cd "$B" && bash "$FOLD" "$T/task-022-sso.md" ) >/dev/null 2>&1
render
ok "the answer folds, and the row leaves the queue" "$(grep -c 'task-022-sso' "$AWF")" 0
OWED="$(cd "$B" && bash "$SH" --owed "$T/task-022-sso.md" 2>/dev/null)"
ok "owed: the stopped session, with the answer" "$OWED" "owed $U1 $ID1
answer: done, and the SSO profile is labs-admin"
RES="$(PATH="$PATH" claude --bg --resume "$(bash "$SESS" full a8b4344d)" "The human finished hand-off $ID1: done. Carry on with this task.")"
ok "the resume went to the FULL id, flag-free" "$(cnt "$TMP/calls" "resume $U1 The human finished hand-off $ID1")" 1
ok "…and resume-id reads it as the same session" "$(bash "$SESS" resume-id "$U1" "$RES")" "same $U1"
printf '* 2026-10-21T10:00:00Z woke %s\n' "$U1" >> "$T/task-022-sso.md"
ok "after the woke note: not owed again" "$(one --owed "$T/task-022-sso.md")" "not-owed already-resumed rc=1"
STARTED=1791557999999; all_blocked
job "$U1" 'merge terraform#867 now'
OUT="$(one "$T/task-022-sso.md")"; ID3="$(id_of "$T/task-022-sso.md")"
ok "the resumed session's next hand-off is a NEW entry" "$OUT" "handed-off a8b4344d $ID3 Q2 rc=0"
ok "…with a new id" "$([ "$ID3" != "$ID1" ] && echo yes)" yes
STARTED=1791557649233; all_blocked

echo "== fold-hostile text cannot reach the fold =="
ok "the ' --- --- ' needs was filed whole" "$(cnt "$HO/$ID2.txt" 'Decide A --- --- B?')" 1
sed -i.bak "s/^  - \"\\(Q2: do: .*\\)\"\$/  - \"\\1 --- done\"/" "$T/task-030-links.md"
ok "…and its entry folds clean" "$( cd "$B" && bash "$FOLD" "$T/task-030-links.md" >/dev/null 2>&1; echo $?)" 0
ok "an answered entry is never re-added" "$(bash "$FOLD" --add "$T/task-030-links.md" 'Q1: earlier?' >/dev/null; grep -c '"Q1: earlier?"' "$T/task-030-links.md")" 0

echo "== /loopd:answer addresses the hand-off by its label, not 'the first open entry' =="
mk "$T/task-040-two.md" in-review "$U6" '[ "Q1: Decide the region?" ]'
printf -- '\n## Question details\n\n### Q1\nRecommendation: eu\nOptions:\n1. eu\nContext:\n- Depth 1: a\n- Depth 2: b\n- Depth 3: c\n' >> "$T/task-040-two.md"
bash "$FOLD" --add "$T/task-040-two.md" "Q2: do: finish the agent's hand-off f6f6f6f6-00000000 — x" >/dev/null
( cd "$B" && bash "$ANS" --instance "$B" "$T/task-040-two.md" Q2 --text done ) >/dev/null 2>&1
ok "Q2 (the hand-off) is the entry answered" "$(bash "$FOLD" --list "$T/task-040-two.md" answered_questions | grep -c 'Q2: do: .* --- done$')" 1
ok "…and Q1 is still open" "$(bash "$FOLD" --list "$T/task-040-two.md" open_questions)" "Q1: Decide the region?"

echo "== a done task: pending jobs filed first, then stopped =="
: > "$TMP/calls"
OUT="$(one "$T/task-009-done.md")"; ID4="$(id_of "$T/task-009-done.md")"
ok "done + blocked with needs: filed, then stopped" "$OUT" "stopped 9d4e0877 done rc=0"
ok "…its hand-off entry exists" "$(bash "$FOLD" --list "$T/task-009-done.md" open_questions | grep -c "^Q1: do: .*$ID4")" 1
render
ok "…and its row renders though the task is done" "$(grep -c '^\* 👉 \*\*do\*\* — \[task-009-done\].*backfill' "$AWF")" 1
ok "done + blocked, no needs: stopped" "$(one "$T/task-011-done.md")" "stopped d8d8d8d8 done rc=0"
ok "…nothing filed" "$(grep -c 'hand-off' "$T/task-011-done.md")" 0
ok "done + an ended session: nothing to stop" "$(one "$T/task-010-ended.md")" "ended e5e5e5e5 done rc=0"
ok "…and no stop was issued" "$(cnt "$TMP/calls" "stop e5e5e5e5")" 0
ok "a done task is never owed" "$(one --owed "$T/task-009-done.md")" "not-owed task-done rc=1"

echo "== long text: capped at a word, never inside a token =="
LONG="merge terraform#8661 first; $(printf 'word%.0s ' $(seq 1 90))then rerun"
job "$U1" "$LONG"; STARTED=1791558000001; all_blocked
one "$T/task-022-sso.md" >/dev/null; render
ROW="$(grep 'task-022-sso.*8661' "$AWF")"
ok "the row says it is truncated, and where the rest is" "$(printf '%s' "$ROW" | grep -c '(truncated, full text: `.loopd/.handoffs/a8b4344d-')" 1
ok "…the PR number is whole" "$(printf '%s' "$ROW" | grep -c 'terraform#8661\](')" 1
ok "…and the cut is between words" "$(printf '%s' "$ROW" | grep -cE 'word … \(truncated')" 1
STARTED=1791557649233; all_blocked

echo "== B1: a launched resume counts as resumed, so a second tick never resumes again =="
mk "$T/task-050-launched.md" in-progress "$U6"
printf '\n* 2026-10-21T09:00:00Z needs handed off %s · hand-off f6f6f6f6-0000aaaa · Q1 · session stopped by the tick\n' "$U6" >> "$T/task-050-launched.md"
bash "$FOLD" --add "$T/task-050-launched.md" "Q1: do: finish the agent's hand-off f6f6f6f6-0000aaaa — x" >/dev/null
sed -i.bak 's/^  - "\(Q1: do: .*\)"$/  - "\1 --- done"/' "$T/task-050-launched.md"
agents blocked blocked blocked blocked done stopped blocked blocked
ok "answered and stopped: owed" "$(one --owed "$T/task-050-launched.md" | cut -d' ' -f1-2)" "owed $U6"
printf 'resume launched; session id unresolved: 0badc0de\n' >> "$T/task-050-launched.md"
ok "after 'resume launched': not owed" "$(one --owed "$T/task-050-launched.md")" "not-owed already-resumed rc=1"
agents blocked blocked blocked blocked done done blocked blocked
ok "…nor on the next tick, once the old session reads done" "$(one --owed "$T/task-050-launched.md")" "not-owed already-resumed rc=1"
all_blocked

echo "== W1: the next Q number counts advisor: entries and ### headings =="
mk "$T/task-051-advisor.md" in-review "$U3" '[ "advisor: Q1: which db?" ]'
printf -- '\n## Question details\n\n### Q1\nRecommendation: pg\nOptions:\n1. pg\nContext:\n- Depth 1: a\n- Depth 2: b\n- Depth 3: c\n' >> "$T/task-051-advisor.md"
job "$U3" 'merge labs#9'
OUT="$(one "$T/task-051-advisor.md")"
ok "the hand-off becomes Q2" "$(printf '%s' "$OUT" | grep -oE 'Q[0-9]+ rc=0$')" "Q2 rc=0"
ok "…the advisor's ### Q1 block is the only one" "$(grep -c '^### Q1$' "$T/task-051-advisor.md")" 1
ok "…and --block Q2 is the hand-off's" "$(bash "$FOLD" --block Q2 "$T/task-051-advisor.md" | python3 -c 'import json, sys; print(json.load(sys.stdin)["options"][0][1])')" done
mkdir -p "$J/${U3%%-*}"; printf '{"state":"blocked","suggestedReply":"x"}\n' > "$J/${U3%%-*}/state.json"; all_blocked

echo "== W2: a run id takes the -R of its own command only =="
mk "$T/task-052-runs.md" in-review "$U3"
job "$U3" 'gh run rerun 39000001 then gh run rerun 39000002 -R acme/infra'
one "$T/task-052-runs.md" >/dev/null; render
ok "the first run links to the task's repo" "$(cnt "$AWF" '[39000001](https://github.com/example-user-007/labs/actions/runs/39000001)')" 1
ok "…the second to its own -R" "$(cnt "$AWF" '[39000002](https://github.com/acme/infra/actions/runs/39000002)')" 1
mkdir -p "$J/${U3%%-*}"; printf '{"state":"blocked","suggestedReply":"x"}\n' > "$J/${U3%%-*}/state.json"; all_blocked

echo "== L2: the hand-off text lands in the bundle, wherever the tick runs from =="
mk "$T/task-053-cwd.md" in-review "$U3"
job "$U3" 'run the backfill'
mkdir -p "$TMP/elsewhere"
OUT="$( cd "$TMP/elsewhere" && bash "$SH" "$T/task-053-cwd.md" --jobs-dir "$J" 2>/dev/null )"
ID5="$(id_of "$T/task-053-cwd.md")"
ok "handed off from another cwd" "$(printf '%s' "$OUT" | cut -d' ' -f1)" handed-off
ok "…its text is in the bundle's store" "$(cat "$HO/$ID5.txt" 2>/dev/null)" "run the backfill"
ok "…and not under that cwd" "$([ -e "$TMP/elsewhere/.loopd" ] && echo yes || echo no)" no
mkdir -p "$J/${U3%%-*}"; printf '{"state":"blocked","suggestedReply":"x"}\n' > "$J/${U3%%-*}/state.json"; all_blocked

echo "== not its case, and unknown =="
: > "$TMP/calls"
ok "blocked with no needs" "$(one "$T/task-031-none.md")" "not-handed-off no-needs rc=1"
ok "a live waitingFor prompt is never handed off" "$(one "$T/task-033-prompt.md")" "not-handed-off waiting-for rc=1"
ok "working: not blocked" "$(one "$T/task-032-working.md")" "not-handed-off not-blocked working rc=1"
ok "an unreadable registry is unknown" "$(STUB_FAIL=1 one "$T/task-031-none.md")" "rc=2"
ok "no task document is unknown" "$(one "$T/none.md")" "rc=2"
ok "…and none of them was stopped" "$(grep -c '^stop ' "$TMP/calls")" 0
all_blocked
ok "a stop that does not land: exit 3" "$(STUB_STUCK=1 one "$T/task-011-done.md")" "rc=3"

echo "== the step files and the board say so =="
ok "step 4 hands a needs off" "$(cnt "$S4" 'scripts/session-handoff.sh <task-path>')" 1
ok "…never attaches it" "$(cnt "$S4" '**Hand it off, never attach:**')" 1
ok "…has a stopped row that reaches the owed read" "$(grep -c '^   | `stopped` or `done` | either, after a hand-off |' "$S4")" 1
ok "…and runs it" "$(cnt "$S4" 'scripts/session-handoff.sh --owed <task-path>')" 1
ok "step 5 stops a done task's session through it" "$(cnt "$S5" 'scripts/session-handoff.sh <task-path>')" 1
ok "…filing a pending needs first" "$(cnt "$S5" '**A `needs` it still holds is filed first**')" 1
ok "no line in either runs claude rm" "$(cat "$S4" "$S5" | grep -E 'claude rm' | grep -vcE 'Never `claude rm`|never `claude rm`|`rm` is the human' | tr -d ' ')" 0
ok "the board says promotion only for a draft" "$(grep -c 'if t.get("status") == "draft" else' "$BOARD")" 1

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
