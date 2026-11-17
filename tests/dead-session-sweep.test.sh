#!/usr/bin/env bash
#
# dead-session-sweep.test.sh — `agent-sessions.sh dead-ids` and `session-sweep.sh`: the tick
# stops this bundle's dead, unattributed sessions, and dead ones in worktrees only finished tasks
# record, and nothing else (tick-stops-dead-sessions/task-001, all-code-is-slop-lessons/task-022).
# Every `claude` is a PATH stub; `stop` is logged and marks the row stopped. Exit 0 pass, 1 fail, 2 setup.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SESS="$REPO/plugin/scripts/agent-sessions.sh"; SWEEP="$REPO/plugin/scripts/session-sweep.sh"
STEP5="$REPO/plugin/tick-steps/step-5-reflect-merges.md"
for f in "$SESS" "$SWEEP" "$STEP5"; do [ -f "$f" ] || { echo "dead-session-sweep.test: $f not found" >&2; exit 2; }; done
command -v python3 >/dev/null 2>&1 || { echo "dead-session-sweep.test: python3 required" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/dead-sweep.XXXXXX")" || exit 2
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

( exit 0 ) & DEAD=$!; wait "$DEAD"
LIVE=$$

B="$TMP/bundle"; WT="$TMP/wt"; OTHER="$TMP/other"
mkdir -p "$B/projects/p/tasks" "$B/.loopd" "$WT/t1" "$WT/orphan" "$OTHER" "$TMP/cfg/daemon" "$TMP/bin"
printf '{ "worktreeRoot": "%s" }\n' "$WT" > "$B/instance.config.json"
u() { printf '%s-0000-4000-8000-%012d' "$1" "${2:-0}"; }   # <8 hex> [n] -> a full uuid
printf -- '---\ntype: Task\nstatus: in-progress\nworktree: %s\nsession: "%s"\n---\n' "$WT/t1" "$(u 0000a0a0)" \
  > "$B/projects/p/tasks/task-001-x.md"
printf -- '---\ntype: Task\nstatus: done\nsession: %s  # research\n---\n' "$(u 0000b0b0)" > "$B/projects/p/tasks/task-002-y.md"
printf 'claimant: t\nsession: %s\n' "$(u 0000c0c0)" > "$B/.loopd/.tick-lock"
printf '{"workers":{"w1":{"sessionId":"%s","pid":%d},"w2":{"sessionId":"%s","pid":%d}}}\n' \
  "$(u 0000f102)" "$LIVE" "$(u 00000d01)" "$DEAD" > "$TMP/cfg/daemon/roster.json"

cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  agents) [ -n "${FAIL:-}" ] && exit 1; cat "$FIXTURE" ;;
  stop) printf '%s\n' "$2" >> "$STOPS"
        grep -qx "$2" "$TMP/refuse" 2>/dev/null && exit 1
        python3 -c 'import json,sys; p,w=sys.argv[1:]; rows=json.load(open(p))
for r in rows:
    if r.get("sessionId","").split("-")[0]==w: r["state"]="stopped"
json.dump(rows,open(p,"w"))' "$FIXTURE" "$2" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/claude"
export FIXTURE="$TMP/rows.json" STOPS="$TMP/stops" TMP CLAUDE_CONFIG_DIR="$TMP/cfg" CLAUDE_CODE_SESSION_ID="$(u 0000e0e0)"
P="$TMP/bin:$PATH"

# <spec file>: `<sid> <cwd|-> <state> <pid|-|none> <age s|-> [name]` per line -> $FIXTURE
mk() {
  python3 - "$1" "$FIXTURE" <<'PY'
import json, sys, time
rows = []
for line in open(sys.argv[1]):
    if not line.strip():
        continue
    sid, cwd, state, pid, age, *name = line.split()
    r = {"id": sid.split("-")[0], "sessionId": sid, "kind": "background", "state": state}
    if name: r["name"] = name[0]
    if cwd != "-": r["cwd"] = cwd
    if pid != "-": r["pid"] = int(pid)
    if age != "-": r["startedAt"] = int((time.time() - int(age)) * 1000)
    rows.append(r)
json.dump(rows, open(sys.argv[2], "w"))
PY
}
dead_ids() { PATH="$P" bash "$SESS" dead-ids "$B" 2>/dev/null; }
sweep() { : > "$STOPS"; PATH="$P" bash "$SWEEP" "$B" 2>/dev/null; }
stops() { sort "$STOPS" | tr '\n' ' ' | sed 's/ $//'; }

H=3600
cat > "$TMP/main.spec" <<EOF
$(u 00000d01) $B working - $((2*H))
$(u 00000d02) $B/sub blocked - $((25*H))
$(u 00000d03) $B idle - 660
$(u 0000f101) $B working $LIVE $((5*H))
$(u 0000f102) $B working - $((5*H))
$(u 00000a01) $WT/t1 blocked - $((30*H))
$(u 0000c101) $WT/orphan blocked - $((30*H))
$(u 0000c102) $OTHER working - $((5*H))
$(u 0000e101) - working - $((5*H))
$(u 0000e0e0) $B working - $((5*H))
$(u 0000c0c0) $B blocked - $((30*H))
$(u 0000a0a0) $B working - $((5*H))
$(u 0000b0b0) $B working - $((5*H))
$(u 0000b201) $B blocked - $((23*H))
$(u 0000b202) $B working - 540
$(u 0000a201) $B working - -
$(u 0000a301) $B stopped - $((5*H))
$(u 0000d104) $B working $DEAD $((3*H))
EOF
mk "$TMP/main.spec"
WANT="00000d01 00000d02 00000d03 0000d104"

echo "== SELECT: dead-ids prints one <uuid> <short> <age> line per eligible row =="
out="$(dead_ids)"
ok "exactly the dead, unattributed, in-scope rows past their floor" \
   "$(awk '{print $2}' <<<"$out" | sort | tr '\n' ' ' | sed 's/ $//')" "$WANT"
ok "…each line is a full uuid, its short id and an age" \
   "$(grep -cE '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12} [0-9a-f]{8} [0-9]+[dhms]$' <<<"$out")" 4
ok "…oldest first" "$(head -1 <<<"$out" | awk '{print $2, $3}')" "00000d02 1d"

echo "== STOP + REPORTED: the sweep stops exactly those, through full, one line each =="
rep="$(sweep)"; rc=$?
ok "the sweep exits 0" "$rc" 0
ok "claude stop received exactly the ids dead-ids printed" "$(stops)" "$WANT"
ok "one 'stopped <short> (<age>) dead' line per stop" "$(grep -cE '^stopped [0-9a-f]{8} \([0-9]+[dhms]\) dead$' <<<"$rep")" 4
ok "…naming the age dead-ids gave" "$(grep -c '^stopped 00000d02 (1d) dead$' <<<"$rep")" 1
ok "a second sweep finds nothing left to stop" "$(sweep; stops)" ""

echo "== GUARD: what is never stopped =="
mk "$TMP/main.spec"; sweep >/dev/null
for g in "0000f101|a live pid on the row (kill -0)" "0000f102|a live pid in the daemon roster" \
         "00000a01|a dead session in a task's worktree (the task's)" \
         "0000c101|a cwd under the shared worktreeRoot no task records" \
         "0000c102|a cwd outside the bundle root" "0000e101|a row with no cwd (D2)" \
         "0000e0e0|the tick's own session (CLAUDE_CODE_SESSION_ID)" "0000c0c0|the session on .tick-lock" \
         "0000a0a0|a session a task records, cwd at the bundle root" "0000b0b0|…a terminal task's, commented" \
         "0000a201|a row with no startedAt (age ?)" "0000a301|an already-stopped row"; do
  ok "no stop for ${g#*|}" "$(grep -c "^${g%%|*}$" "$STOPS")" 0
done
FAIL=1 sweep >/dev/null; rc=$?
ok "a listing view cannot read: exit 2, zero stops" "$rc:$(stops)" "2:"
sed 's/ [0-9][0-9]* \([0-9-]*\)$/ - \1/' "$TMP/main.spec" > "$TMP/nopid.spec"; mk "$TMP/nopid.spec"
ok "no row carries a pid: exit 2, zero stops" "$(sweep >/dev/null; echo $?):$(stops)" "2:"
printf '[]\n' > "$FIXTURE"
ok "an empty listing is an answer: dead-ids exit 0, no output" "$(dead_ids; echo "rc=$?")" "rc=0"
ok "…and the sweep exits 0, prints nothing, stops nothing" "$(sweep; echo "rc=$?"):$(stops)" "rc=0:"
mk "$TMP/main.spec"
python3 - "$FIXTURE" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
twin = dict(rows[0]); twin["sessionId"] = twin["sessionId"][:-1] + "9"; twin["cwd"] = "/elsewhere"
json.dump(rows + [twin], open(sys.argv[1], "w"))
PY
sweep >/dev/null
ok "a short id full resolves to two sessions is never stopped" "$(grep -c '^00000d01$' "$STOPS")" 0
ok "…and the rest still are" "$(stops)" "00000d02 00000d03 0000d104"

echo "== AGE: the D1 floors =="
cat > "$TMP/age.spec" <<EOF
$(u 0000f101) $B working $LIVE $((5*H))
$(u 0000bb01) $B blocked - $((23*H+3000))
$(u 0000bb02) $B blocked - $((24*H+60))
$(u 0000cc01) $B working - 540
$(u 0000cc02) $B working - 660
EOF
mk "$TMP/age.spec"; sweep >/dev/null
ok "blocked under 24h and other under 10m are kept; both past the floor stopped" "$(stops)" "0000bb02 0000cc02"

echo "== FINISHED WORKTREE: a dead session where only done or cancelled tasks worked =="
T="$B/projects/p/tasks"; mkdir -p "$WT/t3" "$WT/t5" "$WT/t6" "$WT/t8"
task() { { echo ---; echo "type: Task"; [ -n "$3" ] && echo "status: $3"; echo "worktree: $WT/$2"
           [ -n "${4:-}" ] && echo "session: $4"; echo ---; } > "$T/$1.md"; }
task task-003-done t3 done; task task-004-gone t4 cancelled; task task-005-nostatus t5 ""
task task-006-done t6 done; task task-007-open t6 in-review; task task-008-rec t8 done "$(u 0000a8a8)"
printf -- '---\nstatus: done\nworktree: %s\nstatus: in-review\n---\n' "$WT/t9" > "$T/task-009-twice.md"
printf -- '---\nstatus: done\nworktree: %s\tdone\n---\n' "$WT/t10" > "$T/task-010-tab.md"
cat > "$TMP/fin.spec" <<EOF
$(u 0000f101) $B working $LIVE $((5*H))
$(u 0000d301) $WT/t3 blocked - 1800 qa-review-pr-568
$(u 0000d401) $WT/t4/sub working - 1800 qa-review-pr-569
$(u 0000d302) $WT/t3 blocked - 540 qa-review-pr-571
$(u 0000a501) $WT/t5 blocked - $((30*H)) qa-review-pr-574
$(u 0000a601) $WT/t6 working - $((5*H)) qa-review-pr-583
$(u 0000a8a8) $WT/t8 blocked - $((30*H))
$(u 0000c103) $WT/orphan working - $((5*H))
$(u 0000a901) $WT/t9 working - $((5*H))
$(u 0000aa01) $WT/t10 working - $((5*H))
EOF
mk "$TMP/fin.spec"; rep="$(sweep)"
ok "a done task's worktree, and a reclaimed cancelled one's: stopped past 10m, blocked too" "$(stops)" "0000d301 0000d401"
ok "…reported as dead" "$(grep -c '^stopped 0000d301 ([0-9]*m) dead$' <<<"$rep")" 1
for g in "0000d302|a finished worktree's session under 10m" "0000a501|a worktree whose task has no status:" \
         "0000a601|a worktree an open task records too" "0000a8a8|a finished worktree's session a task records" \
         "0000c103|a worktreeRoot path no task of this bundle records" \
         "0000a901|a worktree whose task has two status: lines" "0000aa01|a tab in worktree: forging a status"; do
  mk "$TMP/fin.spec"; sweep >/dev/null
  ok "no stop for ${g#*|}" "$(grep -c "^${g%%|*}$" "$STOPS")" 0
done

echo "== CAP: at most 20 stops a tick (D3) =="
{ printf '%s %s working %s %s\n' "$(u 0000f101)" "$B" "$LIVE" 100
  for i in $(seq 1 25); do printf '%s %s working - %d\n' "$(u "$(printf '0000%04d' "$i")")" "$B" $((H+i)); done; } > "$TMP/cap.spec"
mk "$TMP/cap.spec"; rep="$(sweep)"; rc=$?
ok "25 eligible rows: exactly 20 stops and exit 0" "$(wc -l < "$STOPS" | tr -d ' '):$rc" "20:0"
ok "…the 20 oldest" "$(grep -c '^0000000[1-5]$' "$STOPS")" 0

echo "== REPORTED: a refused stop =="
mk "$TMP/main.spec"; printf '00000d03\n' > "$TMP/refuse"; rep="$(sweep)"; rc=$?
ok "a refused stop prints stop-failed <short>" "$(grep -c '^stop-failed 00000d03$' <<<"$rep"):$rc" "1:0"
ok "…and is not retried in the same tick" "$(grep -c '^00000d03$' "$STOPS")" 1
ok "…and is not reported stopped" "$(grep -c '^stopped 00000d03' <<<"$rep")" 0
rm -f "$TMP/refuse"

echo "== the tick runs it from step 5 and carries the lines to its close =="
ok "step 5 names session-sweep.sh" "$(grep -c 'scripts/session-sweep.sh' "$STEP5" | tr -d ' ')" 1
ok "…and the core carries its lines to log.md" \
   "$(awk '/^5\. \*\*Reflect merges\*\* —/{f=1} /^6\. /{f=0} f' "$REPO/plugin/agents/project-manager.md" | grep -c 'log.md')" 1

echo "== the mutants: the guards above discriminate =="
cp -R "$REPO/plugin/scripts" "$TMP/scripts"; M="$TMP/scripts/agent-sessions.sh"
mk "$TMP/main.spec"
mut() { PATH="$P" bash "$M" dead-ids "$B" 2>/dev/null | awk '{print $2}' | grep -c "^$1$"; }
C="$TMP/scripts/agent-sessions-classify.py"; CSRC="$REPO/plugin/scripts/agent-sessions-classify.py"
sed 's/and not skip & {sid, sid.split("-")\[0\]}/and True/' "$CSRC" > "$C"
ok "dropping the skip set selects the lock's session" "$(mut 0000c0c0)" 1
sed 's/86400 if state == "blocked" and not settled else 600/0/' "$CSRC" > "$C"
ok "dropping the floors selects a 9m-old row" "$(mut 0000b202)" 1
mk "$TMP/fin.spec"
sed 's/if st_ not in ("done", "cancelled"):/if True:/' "$CSRC" > "$C"
ok "dropping the done/cancelled check keeps a done worktree's session" "$(mut 0000d301)" 0
sed 's/state == "blocked" and not settled/state == "blocked"/' "$CSRC" > "$C"
ok "dropping the waiver keeps a 30m blocked one there" "$(mut 0000d301)" 0
cp "$CSRC" "$C"
ok "…and the unmutated copy selects it" "$(mut 0000d301)" 1
mk "$TMP/main.spec"
cp "$CSRC" "$C"; sed 's/ps -p /false /' "$SESS" > "$M"
ok "dropping the roster check selects a roster-live row" "$(mut 0000f102)" 1

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
