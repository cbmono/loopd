#!/usr/bin/env bash
#
# session-sweep-bounds.test.sh — `session-sweep.sh` stops this bundle's finished sessions that
# still hold a pid, an open task's session idle past maxIdleMinutes, and one busy past
# maxBgRoundMinutes (with a hand-off); `session-handoff.sh` stops a done task's live row
# (stop-leaking-bg-sessions/task-001). `claude` is a PATH stub: `stop` logs, marks the row
# stopped and drops its pid. Exit 0 pass, 1 fail, 2 setup.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO/plugin/scripts"; SWEEP="$S/session-sweep.sh"; SESS="$S/agent-sessions.sh"; HO="$S/session-handoff.sh"
PM="$REPO/plugin/agents/project-manager.md"; STEP5="$REPO/plugin/tick-steps/step-5-reflect-merges.md"
for f in "$SWEEP" "$SESS" "$HO" "$PM" "$STEP5"; do [ -f "$f" ] || { echo "session-sweep-bounds.test: $f not found" >&2; exit 2; }; done
command -v python3 >/dev/null 2>&1 || { echo "session-sweep-bounds.test: python3 required" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sweep-bounds.XXXXXX")" || exit 2
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

LIVE=$$
B="$TMP/bundle"; WT="$TMP/wt"; OTHER="$TMP/other"; T="$B/projects/p/tasks"
mkdir -p "$T" "$B/.loopd" "$WT/x" "$OTHER" "$TMP/cfg/projects/p" "$TMP/cfg/jobs" "$TMP/bin"
printf '{ "worktreeRoot": "%s" }\n' "$WT" > "$B/instance.config.json"
u() { printf '%s-0000-4000-8000-000000000000' "$1"; }
task() { printf -- '---\ntype: Task\nstatus: %s\nworktree: %s/%s\nsession: %s\nopen_questions: [ ]\n---\n\n# Notes\n' \
  "$2" "$WT" "$1" "$(u "$3")" > "$T/$1.md"; }
task task-001-i in-progress 1d1e0001; task task-002-i in-progress 1d1e0002
task task-003-b in-review   b0590001; task task-004-b in-progress b0590002
task task-005-d done        d0de0001; task task-006-b in-progress b0590003
printf 'claimant: t\nsession: %s\n' "$(u 10c10c01)" > "$B/.loopd/.tick-lock"

cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  agents) cat "$FIXTURE" ;;
  stop) printf '%s\n' "$2" >> "$STOPS"
        python3 -c 'import json,sys; p,w=sys.argv[1:]; rows=json.load(open(p))
for r in rows:
    if r.get("sessionId","").split("-")[0]==w: r["state"]="stopped"; r.pop("pid",None)
json.dump(rows,open(p,"w"))' "$FIXTURE" "$2" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/claude"
export FIXTURE="$TMP/rows.json" STOPS="$TMP/stops" CLAUDE_CONFIG_DIR="$TMP/cfg" CLAUDE_CODE_SESSION_ID="$(u 5e1f0001)"
export PATH="$TMP/bin:$PATH"

# <spec>: `<short> <cwd|-> <state|-> <status|-> <kind|-> <age h> [<assistant m ago> <user-text m ago>]`
mk() {
  python3 - "$1" "$FIXTURE" "$TMP/cfg/projects/p" "$LIVE" <<'PY'
import json, sys, time
from datetime import datetime, timezone
spec, out, proj, live = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
iso = lambda m: datetime.fromtimestamp(time.time() - m * 60, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
rows = []
for line in open(spec):
    f = line.split()
    if not f:
        continue
    sid = f[0] + "-0000-4000-8000-000000000000"
    r = {"id": f[0], "sessionId": sid, "pid": live, "startedAt": int((time.time() - float(f[5]) * 3600) * 1000)}
    for k, v in (("cwd", f[1]), ("state", f[2]), ("status", f[3]), ("kind", f[4])):
        if v != "-": r[k] = v
    rows.append(r)
    if len(f) > 6:
        a, u = float(f[6]), float(f[7])
        with open("%s/%s.jsonl" % (proj, sid), "w") as fh:
            for e in ({"type": "user", "timestamp": iso(u), "message": {"content": "go"}},
                      {"type": "assistant", "timestamp": iso(a)},
                      {"type": "user", "timestamp": iso(0.5), "message": {"content": [{"type": "tool_result"}]}}):
                fh.write(json.dumps(e) + "\n")
json.dump(rows, open(out, "w"))
PY
}
sweep() { : > "$STOPS"; bash "$SWEEP" "$B" 2>/dev/null; }
stops() { sort "$STOPS" | tr '\n' ' ' | sed 's/ $//'; }
inflight() { bash "$SESS" in-flight "$B" 2>/dev/null; }

cat > "$TMP/main.spec" <<EOF
1d1e0001 $WT/task-001-i working idle background 30 121 125
1d1e0002 $WT/task-002-i working idle background 30 119 125
b0590001 $WT/task-003-b working busy background 30 1 1441
b0590002 $WT/task-004-b working busy background 72 1 60
b0590003 $WT/task-006-b working busy background 30 1 1380
f1f10001 $B done idle background 5
f1f10002 $WT/x done idle background 5
f1f10003 $OTHER done idle background 5
f1f10004 $B done idle - 5
f1f10005 $B - idle background 5
0be00001 $OTHER working idle background 30 600 600
5e1f0001 $B done idle background 1
10c10c01 $B done idle background 2
EOF
mk "$TMP/main.spec"

echo "== FINISHED / IDLE / BUSY: one fixture run stops exactly the three classes =="
before="$(inflight)"
rep="$(sweep)"; rc=$?
ok "the sweep exits 0" "$rc" 0
ok "claude stop: the finished tick, the 121m idle row, the 24h+ busy row" "$(stops)" "1d1e0001 b0590001 f1f10001"
ok "a reaped done tick reports 'stopped … finished'" "$(grep -c '^stopped f1f10001 (5h) finished$' <<<"$rep")" 1
ok "the idle row reports 'stopped … idle'" "$(grep -c '^stopped 1d1e0001 (1d) idle$' <<<"$rep")" 1
ok "the busy row is handed off with Q1" "$(grep -cE '^handed-off b0590001 b0590001-[0-9a-f]{8} Q1$' <<<"$rep")" 1
ok "…one Q1: do: entry on its task" "$(grep -c 'Q1: do: finish the agent' "$T/task-003-b.md")" 1
hid="$(grep -oE 'b0590001-[0-9a-f]{8}' <<<"$rep" | head -1)"
ok "…filing the fixed text, the record carrying no needs" "$(cat "$B/.loopd/.handoffs/$hid.txt" 2>/dev/null)" "busy past maxBgRoundMinutes — stopped"
ok "the idle-stopped task stays open" "$(sed -n 's/^status: //p' "$T/task-001-i.md")" in-progress
ok "…and its stopped session frees its slot" "${before}→$(inflight)" "5→3"
ok "a second sweep stops nothing and exits 0" "$(sweep; echo "rc=$?"):$(stops)" "rc=0:"

echo "== GUARD: never stopped =="
mk "$TMP/main.spec"; sweep >/dev/null
for g in "1d1e0002|an idle row at 119 minutes" "b0590003|a busy row under the bound (23h)" \
         "b0590002|a busy row with an old startedAt and a fresh round" \
         "f1f10002|a finished row under worktreeRoot" "f1f10003|another bundle's finished row" \
         "0be00001|another bundle's idle row no task records" "f1f10004|a row with no kind" \
         "f1f10005|a row with no state" "5e1f0001|the running tick's own session" \
         "10c10c01|the session on .tick-lock"; do
  ok "no stop for ${g#*|}" "$(grep -c "^${g%%|*}$" "$STOPS")" 0
done
n=0; for f in "$SWEEP" "$SESS" "$HO" "$S/normalise-config.sh" "$S/tick-reap.sh"; do
  n=$((n + $(grep -c 'claude rm' "$f"))); done
ok "grep -c 'claude rm' over the changed scripts" "$n" 0

echo "== KEYS: per-machine, 0 disables, resolved through resolve-config =="
printf '{ "maxIdleMinutes": 100, "maxBgRoundMinutes": 0 }\n' > "$B/instance.config.local.json"
mk "$TMP/main.spec"; sweep >/dev/null
ok "maxIdleMinutes 100 stops the 119m row; maxBgRoundMinutes 0 stops no busy row" "$(stops)" "1d1e0001 1d1e0002 f1f10001"
printf '{ "maxIdleMinutes": 0 }\n' > "$B/instance.config.local.json"
mk "$TMP/main.spec"; rm -f "$T/task-003-b.md"; task task-003-b in-review b0590001; sweep >/dev/null
ok "maxIdleMinutes 0 stops no idle row" "$(stops)" "b0590001 f1f10001"
ok "normalise-config reads both keys as per-machine" \
   "$(bash "$S/normalise-config.sh" "$B" 2>&1 | grep -c 'MISPLACED.*max\(Idle\|BgRound\)Minutes')" 0
rm -f "$B/instance.config.local.json"

echo "== DONE TASK: session-handoff.sh stops a terminal row that still holds a pid =="
printf '%s %s done idle background 3\n' d0de0001 "$WT/task-005-d" > "$TMP/d.spec"; mk "$TMP/d.spec"; : > "$STOPS"
ok "a done task's done+live row is stopped" "$(cd "$B" && bash "$HO" "$T/task-005-d.md" 2>/dev/null)" "stopped d0de0001 done"
ok "…claude stop called once" "$(stops)" "d0de0001"
: > "$STOPS"
ok "a second run is a no-op: ended, no stop" "$(cd "$B" && bash "$HO" "$T/task-005-d.md" 2>/dev/null; echo "rc=$?")" "ended d0de0001 stopped
rc=0"
ok "…with no claude stop" "$(stops)" ""

echo "== CAP: 20 a run, the 21st deferred and stopped next run =="
for i in $(seq 1 21); do printf 'f2%06d %s done idle background %d\n' "$i" "$B" $((100 - i)); done > "$TMP/cap.spec"
mk "$TMP/cap.spec"; rep="$(sweep)"
ok "21 eligible: 20 stops" "$(wc -l < "$STOPS" | tr -d ' ')" 20
ok "…the youngest is listed deferred" "$(grep -c '^deferred f2000021 ' <<<"$rep")" 1
ok "…and stopped next run" "$(sweep >/dev/null; stops)" "f2000021"

echo "== the tick runs the sweep on every tick =="
ok "step 5 names session-sweep.sh" "$(grep -c 'scripts/session-sweep.sh' "$STEP5" | tr -d ' ')" 1
ok "the IDLE fast path (step 0.9) names it" \
   "$(awk '/^0\.9\. /,/^0\.95\. /' "$PM" | grep -c 'scripts/session-sweep.sh' | tr -d ' ')" 1
ok "tick-reap.sh never runs it" "$(grep -c 'session-sweep' "$S/tick-reap.sh")" 0

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
