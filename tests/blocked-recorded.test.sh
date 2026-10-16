#!/usr/bin/env bash
#
# blocked-recorded.test.sh — `agent-sessions.sh recorded` tells a `blocked` session whose
# round is recorded (the tick's to stop) from one with nothing recorded (the human's) and
# from one on a live prompt, in one read; the tick's own stop settles like the human's; and
# step 4 stops without `rm` and resumes only an owed round by the full id. Offline: `claude`
# and `gh` are stubs. Reasoning: docs/pm-design.md#step-4.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SESS="$REPO/plugin/scripts/agent-sessions.sh"
SU="$REPO/plugin/scripts/session-usage.sh"
AU="$REPO/plugin/scripts/agent-usage.sh"
S4="$REPO/plugin/tick-steps/step-4-advance.md"
for f in "$SESS" "$SU" "$AU" "$S4"; do
  [ -f "$f" ] || { echo "blocked-recorded.test: $f not found" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || { echo "blocked-recorded.test: python3 required" >&2; exit 2; }

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-60s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-60s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
has() { grep -qF -- "$2" "$1" && echo yes || echo no; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/blocked-recorded.XXXXXX")" || {
  echo "blocked-recorded.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# `claude agents` prints $TMP/agents.json; `claude stop <id>` rewrites that row to `stopped`
# and logs the call; anything else exits 1. `gh` resolves every PR and logs each call.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  agents) [ -n "${STUB_FAIL:-}" ] && exit 1; cat "$STUB_DIR/agents.json" ;;
  stop) echo "stop $2" >> "$STUB_DIR/calls"
        python3 -c 'import json, sys
p, i = sys.argv[1], sys.argv[2]
rows = json.load(open(p))
for r in rows:
    if r.get("id") == i: r["state"] = "stopped"
json.dump(rows, open(p, "w"))' "$STUB_DIR/agents.json" "$2"; echo "stopped $2" ;;
  *) exit 1 ;;
esac
STUB
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$STUB_DIR/calls"
exit 0
STUB
chmod +x "$TMP/bin/claude" "$TMP/bin/gh"
export STUB_DIR="$TMP"
P="$TMP/bin:$PATH"

U1=a1a1a1a1-0000-4000-8000-000000000001   # blocked, turn ended addressing the human
U2=b2b2b2b2-0000-4000-8000-000000000002   # blocked on a startup dialog (`needs`)
U3=c3c3c3c3-0000-4000-8000-000000000003   # blocked, no suggestedReply (mid-round refusal)
U4=d4d4d4d4-0000-4000-8000-000000000004   # blocked, no job record at all
U5=e5e5e5e5-0000-4000-8000-000000000005   # blocked, registry carries waitingFor
U6=f6f6f6f6-0000-4000-8000-000000000006   # working
U7=a7a7a7a7-0000-4000-8000-000000000007   # blocked, unreadable job record
row() { printf '{"id":"%s","sessionId":"%s","kind":"background","state":"%s","startedAt":1791557649233%s}' "${2%%-*}" "$2" "$1" "${3:-}"; }
reset_agents() {
  printf '[%s,%s,%s,%s,%s,%s,%s]\n' "$(row blocked "$U1")" "$(row blocked "$U2")" "$(row blocked "$U3")" \
    "$(row blocked "$U4")" "$(row blocked "$U5" ',"waitingFor":"login"')" "$(row working "$U6")" \
    "$(row blocked "$U7")" > "$TMP/agents.json"
}
reset_agents
J="$TMP/jobs"
job() { mkdir -p "$J/${1%%-*}"; printf '%s\n' "$2" > "$J/${1%%-*}/state.json"; }
job "$U1" '{"state":"working","suggestedReply":"merge it"}'
job "$U2" '{"state":"working","needs":"open this session to continue setup"}'
job "$U3" '{"state":"working"}'
job "$U5" '{"state":"working","suggestedReply":"x"}'
job "$U6" '{"state":"working"}'
job "$U7" 'not json'

mk_task() { # <file> <status> <pr-list>
  printf -- '---\ntype: Task\ntitle: t\nkind: build\nstatus: %s\npr: %s\n---\n\n# Notes\n' "$2" "$3" > "$1"
}
REVIEW="$TMP/review.md";   mk_task "$REVIEW" in-review '[ "https://github.com/example-user-007/demo/pull/1" ]'
PARKED="$TMP/parked.md";   mk_task "$PARKED" in-progress '[ ]'
MISMATCH="$TMP/mismatch.md"; mk_task "$MISMATCH" in-progress '[ "https://github.com/example-user-007/demo/pull/1" ]'
BLOCKED="$TMP/blocked.md"; mk_task "$BLOCKED" blocked '[ ]'

rec() { PATH="$P" bash "$SESS" recorded "$1" "$2" --jobs-dir "$J" 2>/dev/null; echo "rc=$?"; }
one() { rec "$@" | paste -sd ' ' -; }

echo "== one read tells recorded from unrecorded =="
ok "in-review with its PR: recorded"            "$(one "$U1" "$REVIEW")"   "recorded $U1 rc=0"
ok "an honest blocked note: recorded"           "$(one "$U1" "$BLOCKED")"  "recorded $U1 rc=0"
ok "in-progress, no PR: unrecorded (exit 1)"    "$(one "$U1" "$PARKED")"   "unrecorded $U1 check-dispatch=1 rc=1"
ok "a 4 before the advance: unrecorded too"     "$(one "$U1" "$MISMATCH")" "unrecorded $U1 check-dispatch=4 rc=1"
ok "the short id resolves to the full one"      "$(one "${U1%%-*}" "$REVIEW")" "recorded $U1 rc=0"

echo "== a live prompt or no finished turn is never the tick's =="
ok "needs (a startup dialog)"                   "$(one "$U2" "$REVIEW")" "prompt $U2 needs rc=1"
ok "no suggestedReply (a mid-round refusal)"    "$(one "$U3" "$REVIEW")" "prompt $U3 no-finished-turn rc=1"
ok "no job record"                              "$(one "$U4" "$REVIEW")" "prompt $U4 no-job-record rc=1"
ok "waitingFor in the registry"                 "$(one "$U5" "$REVIEW")" "prompt $U5 waiting-for rc=1"
ok "…while nothing recorded still reads unrecorded" "$(one "$U2" "$PARKED")" "unrecorded $U2 check-dispatch=1 rc=1"

echo "== not blocked, and unknown =="
: > "$TMP/calls"
ok "working: not-blocked"                       "$(one "$U6" "$REVIEW")" "not-blocked working rc=1"
ok "…and the host was never asked"              "$(grep -c '^gh ' "$TMP/calls")" 0
ok "an unlisted id: not-blocked gone"           "$(one ffff0000-0000-4000-8000-00000000000f "$REVIEW")" "not-blocked gone rc=1"
ok "an unreadable job record is unknown"        "$(one "$U7" "$REVIEW")" "rc=2"
ok "an unreadable registry is unknown"          "$(STUB_FAIL=1 one "$U1" "$REVIEW")" "rc=2"
ok "no such task document is unknown"           "$(one "$U1" "$TMP/none.md")" "rc=2"
ok "a missing task argument is usage (2)"       "$(PATH="$P" bash "$SESS" recorded "$U1" >/dev/null 2>&1; echo $?)" 2

echo "== the tick's own stop settles the dispatch line like the human's =="
if command -v jq >/dev/null 2>&1; then
  bash "$AU" dispatch "$REVIEW" --role software-engineer --model opus >/dev/null 2>&1
  PR="$TMP/projects"; mkdir -p "$PR/-wt-task"
  printf '%s\n' '{"type":"assistant","timestamp":"2026-10-15T10:00:00.000Z","message":{"id":"m1","usage":{"input_tokens":10,"output_tokens":5},"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}' \
    > "$PR/-wt-task/$U1.jsonl"
  PATH="$P" claude stop "${U1%%-*}" >/dev/null
  ok "the stop took the short id"               "$(grep -c "^stop ${U1%%-*}\$" "$TMP/calls")" 1
  ok "…and the session now reads stopped"       "$(PATH="$P" bash "$SESS" state "$U1")" stopped
  ok "…which recorded no longer answers"        "$(one "$U1" "$REVIEW")" "not-blocked stopped rc=1"
  ok "settle after it fills the line"           "$(bash "$SU" "$U1" --projects-dir "$PR" --store-dir "$TMP/nostore" --settle "$REVIEW" >/dev/null; echo $?)" 0
  ok "…with the stopped round's numbers"        "$(grep -c '^\* DISPATCH .* · usage tokens=15 tools=1 ' "$REVIEW")" 1
  reset_agents
else
  echo "  SKIP  settle: no jq on this machine"
fi

echo "== step 4: stop unconditionally, never rm, resume only an owed round by the full id =="
ok "step 4 runs the one read"                   "$(has "$S4" 'scripts/agent-sessions.sh recorded <the task')" yes
ok "…after the advance"                         "$(has "$S4" '**After** the advance above')" yes
ok "a recorded round is stopped unconditionally" "$(has "$S4" '**Stop it, unconditionally:**')" yes
ok "…by the short id"                           "$(grep -c '`claude stop <the UUID'"'"'s first field>`, then `agent-sessions.sh state <the UUID>`' "$S4" | tr -d ' ')" 2
ok "no line in step 4 runs claude rm"           "$(grep -E 'claude rm' "$S4" | grep -vcE 'Never `claude rm`|`rm` is the human' | tr -d ' ')" 0
ok "resume only when a round is owed"           "$(has "$S4" '**Resume it only when a round is OWED**')" yes
ok "…only to the session that round addresses"  "$(has "$S4" '**only to the session that round addresses**')" yes
ok "…by the full id"                            "$(grep -c -- '--resume <the UUID full printed>' "$S4" | tr -d ' ')" 1
ok "…and never a still-blocked one"             "$(has "$S4" 'never one still `blocked` or `working`')" yes
ok "only unrecorded puts claude stop in AWAITING" "$(has "$S4" 'this is the only `blocked` that puts a `claude stop` in `AWAITING.md`')" yes
ok "a prompt goes to the human as attach"       "$(has "$S4" 'surface it as `claude attach')" yes

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
