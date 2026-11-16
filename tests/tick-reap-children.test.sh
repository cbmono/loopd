#!/usr/bin/env bash
#
# tick-reap-children.test.sh — a `blocked` tick with a live fork or `Agent` child is working,
# not BLOCKED. The listing (AB_SESSIONS_LISTING) and the job record are rows captured on CLI
# 2.1.325 and redacted (tests/fixtures/tick-reap-children): `claude agents --json` has no
# child field; the job record's `inFlight.tasks` is the signal. Pins the four quadrants, the
# one-read guard, the budget-bounded fallback with no record, and that a post-close reap
# stops no session with a live child. A stub `claude` records every argv.
# Reasoning: awaiting-rows-clear-on-idle-ticks/task-004.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SC="$REPO/plugin/scripts"
FX="$REPO/tests/fixtures/tick-reap-children"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/reapkids.XXXXXX")" || { echo "tick-reap-children.test: mktemp failed" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
has() { grep -qF -- "$2" <<<"$1" && echo yes || echo no; }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMP/argv"
case "${1:-}" in
  --bg) echo "backgrounded · 1234abcd" ;;
  stop) ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/claude"
export TMP PATH="$TMP/bin:$PATH" CLAUDE_CONFIG_DIR="$TMP/cfg" AB_SESSIONS_LISTING="$TMP/listing.json"
JOB="$CLAUDE_CONFIG_DIR/jobs/1234abcd/state.json"; mkdir -p "${JOB%/*}"
TS=2026-11-16T17:00:00Z
CFG='{ "roleTiers": { "project-manager": "deep" }, "models": { "deep": "opus" } }'

listing() { # <row fixture> [waitingFor] [state] [status]
  python3 - "$FX/$1.row.json" "${2:-}" "${3:-}" "${4:-}" > "$AB_SESSIONS_LISTING" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
if sys.argv[2]: rows[0]["waitingFor"] = sys.argv[2]
if sys.argv[3]: rows[0]["state"] = sys.argv[3]
if sys.argv[4]: rows[0]["status"] = sys.argv[4]
print(json.dumps(rows))
PY
}
job() { # <state fixture|none> [job state]
  rm -f "$JOB"; [ "$1" = none ] && return
  python3 - "$FX/$1.state.json" "${2:-}" > "$JOB" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
if sys.argv[2]: d["state"] = sys.argv[2]
print(json.dumps(d))
PY
}
n=0
spawned() { # [config json] -> B: a bundle whose lock holds a spawned tick, its entry open
  n=$((n+1)); B="$TMP/b$n"; mkdir -p "$B/.loopd"
  printf '%s\n' "${1:-$CFG}" > "$B/instance.config.json"
  printf '/.loopd/.tick-lock\n/.loopd/.tick-lock.claim\n' > "$B/.gitignore"
  ID="$(bash "$SC/tick-lock.sh" mint)"
  printf '# Log\n\n* TICK %s by me open: %s · refining\n' "$TS" "$ID" > "$B/.loopd/log.md"
  { git -C "$B" init -q && git -C "$B" add -A && git -C "$B" -c user.name=t -c user.email=t@example.com commit -qm init; } >/dev/null 2>&1
  listing fork-live
  bash "$SC/tick-lock.sh" acquire --instance "$B" --agent project-manager --claimant "$ID" >/dev/null 2>&1 \
    && bash "$SC/tick-spawn.sh" --instance "$B" --tick "$ID" --gap 10m >/dev/null 2>&1 \
    || { echo "tick-reap-children.test: could not spawn the fixture tick" >&2; exit 2; }
  rm -f "$TMP/argv"
}
closed() { printf '* TICK %s by me close: refined 3 drafts\n' "$TS" >> "$B/.loopd/log.md"
           { git -C "$B" add -A && git -C "$B" -c user.name=t -c user.email=t@example.com commit -qm close; } >/dev/null 2>&1; }
backdate() { sed -i.bak "s/^spawned: .*/spawned: $(( $(date +%s) - $1 ))/" "$B/.loopd/.tick-lock"; }
reap() { rm -f "$TMP/argv"; OUT="$(bash "$SC/tick-reap.sh" --instance "$B" "$@" 2>&1)"; RC=$?; }
locked() { [ -e "$B/.loopd/.tick-lock" ] && echo yes || echo no; }
stops() { grep -c '^stop' "$TMP/argv" 2>/dev/null | tr -d ' ' || true; }
stops0() { s="$(stops)"; echo "${s:-0}"; }

echo "== the captured rows: no child field in the listing, inFlight in the job record =="
ok "listing row keys (CLI 2.1.325)" "$(python3 -c 'import json,sys; print(",".join(sorted(json.load(open(sys.argv[1]))[0])))' "$FX/fork-live.row.json")" \
   "cwd,id,kind,name,pid,sessionId,startedAt,state,status"
ok "the live-fork job record counts the fork" "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["inFlight"]["tasks"], d["inFlight"]["kinds"][0], d["cliVersion"])' "$FX/fork-live.state.json")" \
   "1 local_agent 2.1.325"
spawned; listing blocked; job fork-live
ok "children mode: blocked row, live fork" "$(bash "$SC/agent-sessions.sh" children 1234abcd)" "waiting=no children=1 job=working"
job blocked
ok "children mode: blocked row, finished fork (queued is not counted)" "$(bash "$SC/agent-sessions.sh" children 1234abcd)" "waiting=no children=0 job=blocked"
job none
ok "children mode: no job record ⇒ unread" "$(bash "$SC/agent-sessions.sh" children 1234abcd)" "waiting=no children=unread job=-"

echo "== criterion 1: blocked, no waitingFor, a live child ⇒ in progress =="
spawned; listing blocked; job fork-live; reap
ok "exit 1" "$RC" 1
ok "…says in progress" "$(has "$OUT" "tick $ID in progress (session 1234abcd, blocked, 1 in flight)")" yes
ok "…prints no BLOCKED:" "$(has "$OUT" 'BLOCKED:')" no
ok "…runs no claude stop" "$(stops0)" 0
ok "…and keeps the lock" "$(locked)" yes
listing blocked; job fork-live working
reap; ok "one read: the child ended and the job resumed ⇒ held, no BLOCKED" "$RC:$(has "$OUT" 'BLOCKED:'):$(stops0)" "1:no:0"
job blocked working
reap; ok "…a record that disagrees with the listing holds (inside the budget)" "$RC:$(has "$OUT" 'blocked, job working')" "1:yes"
backdate 3600; reap
ok "…and past the budget is BLOCKED" "$RC:$(has "$OUT" 'BLOCKED:')" "4:yes"

echo "== criterion 2: the four quadrants =="
spawned; listing blocked "permission prompt"; job blocked; reap
ok "waitingFor, no child ⇒ exit 4 BLOCKED:" "$RC:$(has "$OUT" "BLOCKED: tick $ID"):$(locked)" "4:yes:yes"
listing blocked "permission prompt"; job fork-live; reap
ok "waitingFor and a live child ⇒ exit 4 BLOCKED: (a prompt is a prompt)" "$RC:$(has "$OUT" "BLOCKED: tick $ID")" "4:yes"
listing blocked; job fork-live; reap
ok "a live child, no waitingFor ⇒ exit 1" "$RC:$(locked)" "1:yes"
listing blocked; job blocked; reap
ok "neither, signal readable ⇒ exit 4 BLOCKED:" "$RC:$(has "$OUT" "BLOCKED: tick $ID"):$(stops0)" "4:yes:0"

echo "== criterion 5: no readable record ⇒ held until the tick's budget =="
spawned; listing blocked; job none; reap
ok "neither, no record, inside 45m ⇒ exit 1, no BLOCKED:" "$RC:$(has "$OUT" 'BLOCKED:'):$(has "$OUT" 'children unread')" "1:no:yes"
backdate 2600; reap
ok "…at 43m ⇒ still exit 1" "$RC" 1
backdate 2760; reap
ok "…past 45m ⇒ exit 4 BLOCKED: as today" "$RC:$(has "$OUT" "BLOCKED: tick $ID"):$(locked)" "4:yes:yes"
spawned '{ "roleTiers": { "project-manager": "deep" }, "models": { "deep": "opus" }, "maxAgentMinutes": 2 }'
listing blocked; job none; backdate 60; reap
ok "maxAgentMinutes 2, at 1m ⇒ exit 1" "$RC" 1
backdate 180; reap
ok "…at 3m ⇒ exit 4" "$RC" 4
spawned '{ "roleTiers": { "project-manager": "deep" }, "models": { "deep": "opus" }, "maxAgentMinutes": 2, "roleMinutes": { "project-manager": 10 } }'
listing blocked; job none; backdate 180; reap
ok "roleMinutes project-manager 10 outranks it: at 3m ⇒ exit 1" "$RC" 1
backdate 660; reap
ok "…at 11m ⇒ exit 4" "$RC" 4
spawned; listing blocked; job none; TICK_REAP_POLL=1 TICK_REAP_SLICE=1 reap --wait
ok "--wait inside the budget ⇒ waits (5), no BLOCKED:" "$RC:$(has "$OUT" 'BLOCKED:')" "5:no"
backdate 3600; TICK_REAP_POLL=1 reap --wait
ok "--wait past the budget ⇒ exit 4 BLOCKED:" "$RC:$(has "$OUT" 'BLOCKED:')" "4:yes"

echo "== criterion 3: a committed close never stops a session with a live child =="
spawned; closed; listing blocked; job fork-live; reap
ok "blocked, live child ⇒ exit 1, still finishing" "$RC:$(has "$OUT" "tick $ID closed its entry and is still finishing")" "1:yes"
ok "…no claude stop" "$(stops0)" 0
ok "…lock kept" "$(locked)" yes
listing blocked "" working idle; job fork-live; reap
ok "idle-after-close, live child ⇒ exit 1, no stop, lock kept" "$RC:$(stops0):$(locked)" "1:0:yes"
listing blocked; job blocked; reap
ok "the child finished ⇒ reaped and stopped" "$RC:$(locked):$(grep -c '^stop 1234abcd$' "$TMP/argv" | tr -d ' ')" "0:no:1"
spawned; closed; listing blocked; job none; reap
ok "no readable record ⇒ stopped as today" "$RC:$(stops0)" "0:1"

echo "== the turn-over stop (no ledger entry) spares a live child too =="
spawned; printf '# Log\n' > "$B/.loopd/log.md"; { git -C "$B" add -A && git -C "$B" -c user.name=t -c user.email=t@example.com commit -qm rm; } >/dev/null 2>&1
backdate 300; listing blocked "" working idle; job fork-live; reap
ok "working, turn idle, no entry, live child ⇒ held, no stop" "$RC:$(stops0):$(locked)" "1:0:yes"
job blocked; reap
ok "…nothing in flight ⇒ stopped and closed as today" "$RC:$(stops0):$(locked)" "0:1:no"

echo "== the exit-4 contract text =="
ok "dispatch SKILL.md: a live child is exit 1, never 4" "$(has "$(cat "$REPO/plugin/skills/dispatch/SKILL.md")" 'or `Agent` child is exit **1**, never 4')" yes
ok "pm-design.md: the live-child row" "$(has "$(cat "$REPO/docs/pm-design.md")" '| open, or none | `blocked`, a live child | hold, exit 1')" yes
ok "tick-reap.sh: the blocked) comment names the job record" "$(has "$(cat "$SC/tick-reap.sh")" 'ONE job read saying blocked with nothing')" yes

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
