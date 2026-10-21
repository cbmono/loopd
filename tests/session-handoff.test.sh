#!/usr/bin/env bash
#
# session-handoff.test.sh — a `blocked` role session whose job record carries `needs` is
# written down and stopped, never handed to the human as `claude attach`; a done task's
# session is stopped whatever state it is in. Offline: `claude` is a stub that logs every
# `stop` and never reaches a real session. Reasoning: docs/pm-design.md#step-4.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SH="$REPO/plugin/scripts/session-handoff.sh"
FOLD="$REPO/plugin/scripts/fold-answers.sh"
AW="$REPO/plugin/scripts/build-awaiting.sh"
S4="$REPO/plugin/tick-steps/step-4-advance.md"
S5="$REPO/plugin/tick-steps/step-5-reflect-merges.md"
for f in "$SH" "$FOLD" "$AW" "$S4" "$S5"; do
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

# `claude agents` prints agents.json; `claude stop <short>` logs and marks that row stopped.
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
  *) exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/claude"
export STUB_DIR="$TMP" PATH="$TMP/bin:$PATH"
: > "$TMP/calls"

U1=a8b4344d-0000-4000-8000-000000000001   # blocked, needs = jobs (the measured string)
U2=b2b2b2b2-0000-4000-8000-000000000002   # blocked, needs = a question
U3=c3c3c3c3-0000-4000-8000-000000000003   # blocked, no needs
U4=9d4e0877-0000-4000-8000-000000000004   # blocked on a done task
U5=e5e5e5e5-0000-4000-8000-000000000005   # done on a done task
U6=f6f6f6f6-0000-4000-8000-000000000006   # working
U7=a7a7a7a7-0000-4000-8000-000000000007   # blocked, needs carries a credential shape
agents() { # <state>... in U1..U7 order
  local i=0 out="" s u
  for s in "$@"; do i=$((i+1)); eval "u=\$U$i"
    out="$out${out:+,}{\"id\":\"${u%%-*}\",\"sessionId\":\"$u\",\"kind\":\"background\",\"state\":\"$s\"}"; done
  printf '[%s]\n' "$out" > "$TMP/agents.json"
}
agents blocked blocked blocked blocked done working blocked
J="$TMP/jobs"
job() { mkdir -p "$J/${1%%-*}"; python3 -c 'import json, sys; print(json.dumps({"state": "blocked", "sessionId": sys.argv[1], "needs": sys.argv[2]}))' "$1" "$2" > "$J/${1%%-*}/state.json"; }
job "$U1" 'review, apply and merge terraform#866; re-login SSO and run sim/simulate.sh, then gh run rerun 39260575390 -R example-user-007/labs'
job "$U2" 'Which region should the bucket default to?'
mkdir -p "$J/${U3%%-*}"; printf '{"state":"blocked","suggestedReply":"x"}\n' > "$J/${U3%%-*}/state.json"
job "$U7" 'set token=ghp_abcdefghijklmnopqrstuvwxyz0123 in the repo secrets. Then rerun CI'

B="$TMP/bundle"; T="$B/projects/demo/tasks"; mkdir -p "$T" "$B/.loopd"
AWF="$B/.loopd/AWAITING.md"
printf '{ "org": "example-user-008" }\n' > "$B/instance.config.json"
printf -- '---\ntype: Project\ntitle: Demo\nstatus: active\ntarget_repo: example-user-007/labs\n---\n' > "$B/projects/demo/project.md"
mk() { # <file> <status> <session> [open_questions]
  printf -- '---\ntype: Task\ntitle: %s\nkind: build\nstatus: %s\nsession: %s\nopen_questions: %s\n---\n\n# Notes\n\n* earlier note\n' \
    "$(basename "$1" .md)" "$2" "$3" "${4:-[ ]}" > "$1"
}
mk "$T/task-022-sso.md" in-review "$U1"
mk "$T/task-030-q.md" in-progress "$U2" '[ "Q1: earlier? --- yes" ]'
mk "$T/task-031-none.md" in-progress "$U3"
mk "$T/task-009-done.md" done "$U4"
mk "$T/task-010-ended.md" done "$U5"
mk "$T/task-032-working.md" in-progress "$U6"
mk "$T/task-033-secret.md" in-progress "$U7"
run() { ( cd "$B" && bash "$SH" "$1" --jobs-dir "$J" 2>/dev/null ); echo "rc=$?"; }
one() { run "$@" | paste -sd ' ' -; }

echo "== a needs of human jobs: written down, then stopped =="
ok "handed off: two jobs, no question" "$(one "$T/task-022-sso.md")" "handed-off a8b4344d do=2 ask=- rc=0"
ok "…one do: entry per job" "$(bash "$FOLD" --list "$T/task-022-sso.md" open_questions | grep -c '^do: ')" 2
ok "…kept as written" "$(bash "$FOLD" --list "$T/task-022-sso.md" open_questions | sed -n 1p)" "do: review, apply and merge terraform#866"
ok "…one hand-off note naming the full id" "$(cnt "$T/task-022-sso.md" "needs handed off $U1 · do=2 · ask=-")" 1
ok "…the status is unchanged" "$(grep -c '^status: in-review$' "$T/task-022-sso.md")" 1
ok "…and the stop took the short id" "$(cnt "$TMP/calls" "stop a8b4344d")" 1
agents blocked blocked blocked blocked done working blocked
ok "a re-run stops again" "$(one "$T/task-022-sso.md")" "handed-off a8b4344d do=2 ask=- rc=0"
ok "…and writes nothing twice" "$(bash "$FOLD" --list "$T/task-022-sso.md" open_questions | grep -c '^do: ')" 2
ok "…and keeps one note" "$(cnt "$T/task-022-sso.md" "needs handed off $U1")" 1

echo "== AWAITING.md: one linked do row per job, never an attach =="
printf '# Awaiting you\n' > "$AWF"
bash "$AW" --instance "$B" >/dev/null 2>&1 || echo "build-awaiting rc=$?" >&2
ok "two do rows for the task" "$(grep -c '^\* 👉 \*\*do\*\* — \[task-022-sso\]' "$AWF")" 2
ok "…repo#N becomes the PR link" "$(cnt "$AWF" '[terraform#866](https://github.com/example-user-007/terraform/pull/866)')" 1
ok "…a run id becomes the run link" "$(cnt "$AWF" 'run rerun [39260575390](https://github.com/example-user-007/labs/actions/runs/39260575390)')" 1
ok "…and nothing says claude attach" "$(cnt "$AWF" 'claude attach')" 0
sed -i.bak 's/^  - "do: review, apply and merge terraform#866"$/  - "do: review, apply and merge terraform#866 --- done"/' "$T/task-022-sso.md"
( cd "$B" && bash "$FOLD" "$T/task-022-sso.md" ) >/dev/null 2>&1
bash "$AW" --instance "$B" >/dev/null 2>&1 || echo "build-awaiting rc=$?" >&2
ok "a job acknowledged with ' --- done' folds and leaves the queue" "$(grep -c '\*\*do\*\* — \[task-022-sso\]' "$AWF")" 1
ok "…into answered_questions" "$(bash "$FOLD" --list "$T/task-022-sso.md" answered_questions | grep -c 'do: review.* --- done$')" 1

echo "== a needs that asks: a numbered question with its block =="
ok "handed off as Q2 (after the answered Q1)" "$(one "$T/task-030-q.md")" "handed-off b2b2b2b2 do=0 ask=Q2 rc=0"
ok "…the Q2 entry" "$(bash "$FOLD" --list "$T/task-030-q.md" open_questions | grep -c '^Q2: Which region should the bucket default to?$')" 1
ok "…its block has an option and three depths" \
   "$(bash "$FOLD" --block Q2 "$T/task-030-q.md" | python3 -c 'import json, sys; b = json.load(sys.stdin); print(len(b["options"]), len(b["depths"]))')" "1 3"
bash "$AW" --instance "$B" >/dev/null 2>&1 || echo "build-awaiting rc=$?" >&2
ok "…and it renders as an answer row" "$(grep -c '❓ \*\*answer\*\* — \[task-030-q\].*Q2: Which region' "$AWF")" 1

echo "== a credential shape never reaches the document =="
ok "handed off" "$(one "$T/task-033-secret.md")" "handed-off a7a7a7a7 do=2 ask=- rc=0"
ok "…the token is redacted" "$(cnt "$T/task-033-secret.md" 'ghp_')" 0
ok "…and the job survives around it" "$(cnt "$T/task-033-secret.md" 'do: set token=[redacted] in the repo secrets')" 1

echo "== a done task's session is stopped whatever it is doing =="
: > "$TMP/calls"
ok "done + blocked (no needs, no record): stopped" "$(one "$T/task-009-done.md")" "stopped 9d4e0877 done rc=0"
ok "…by the short id" "$(cnt "$TMP/calls" "stop 9d4e0877")" 1
ok "…and the done task gets no entry" "$(grep -c '^open_questions: \[ \]$' "$T/task-009-done.md")" 1
ok "done + an ended session: nothing to stop" "$(one "$T/task-010-ended.md")" "ended e5e5e5e5 done rc=0"
ok "…and no stop was issued" "$(cnt "$TMP/calls" "stop e5e5e5e5")" 0

echo "== not its case, and unknown =="
agents blocked blocked blocked blocked done working blocked
ok "blocked with no needs: step 4's other rows" "$(one "$T/task-031-none.md")" "not-handed-off no-needs rc=1"
ok "working: not blocked" "$(one "$T/task-032-working.md")" "not-handed-off not-blocked working rc=1"
ok "an unreadable registry is unknown" "$(STUB_FAIL=1 one "$T/task-031-none.md")" "rc=2"
ok "no task document is unknown" "$(one "$T/none.md")" "rc=2"
ok "…and no stop was issued for any of them" "$(grep -c 'stop c3c3c3c3\|stop f6f6f6f6' "$TMP/calls")" 0
agents blocked blocked blocked blocked done working blocked
ok "a stop that does not land: exit 3" "$(STUB_STUCK=1 one "$T/task-009-done.md")" "rc=3"

echo "== the step files say so =="
ok "step 4 hands a needs off" "$(cnt "$S4" 'scripts/session-handoff.sh <task-path>')" 1
ok "…and never attaches it" "$(cnt "$S4" '**Hand it off, never attach:**')" 1
ok "…and resumes the owed round (same task, same PR)" "$(cnt "$S4" "**A hand-off's round is owed once the human has")" 1
ok "step 5 stops a done task's session through it" "$(cnt "$S5" 'scripts/session-handoff.sh <task-path>')" 1
ok "no line in either runs claude rm" "$(cat "$S4" "$S5" | grep -E 'claude rm' | grep -vcE 'Never `claude rm`|never `claude rm`|`rm` is the human' | tr -d ' ')" 0

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
