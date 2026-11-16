#!/usr/bin/env bash
#
# agent-control-role-session.test.sh — `plugin/hooks/agent-control.sh` bounds a top-level
# `claude --bg --agent <plugin>:<role>` session (no `agent_id`), not only a subagent, and
# never matches the PM tick or the owner's interactive session (bg-role-agent-guards).
# Payloads are the measured keys-only fixtures in tests/fixtures/hook-payloads/, with
# values filled in here.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$REPO/tests/fixtures/hook-payloads"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/rolesess.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed (the hook requires it)"; exit 0; }

INST="$TMP/inst"; mkdir -p "$INST/scripts" "$INST/projects/p/tasks" "$INST/.claude/control"
printf '{"maxRepeatedToolCalls":3,"maxAgentMinutes":45}\n' > "$INST/instance.config.json"
TASKDOC="$INST/projects/p/tasks/task-001.md"; : > "$TASKDOC"
cp "$REPO/plugin/scripts/control.sh" "$REPO/plugin/scripts/bundle-paths.sh" "$INST/scripts/"
PLUG="$TMP/plugin"; mkdir -p "$PLUG/hooks" "$PLUG/scripts" "$PLUG/agents"
cp "$REPO/plugin/hooks/agent-control.sh" "$PLUG/hooks/"
cp "$REPO/plugin/scripts/resolve-config.sh" "$PLUG/scripts/"
cp "$REPO"/plugin/agents/*.md "$PLUG/agents/"
HOOK="$PLUG/hooks/agent-control.sh"
CTL="$INST/.claude/control"

PROD="$TMP/prod"; git init -q "$PROD"; git -C "$PROD" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m i
WT="$TMP/wt"; git -C "$PROD" worktree add -q "$WT" -b task-001 >/dev/null 2>&1
printf '%s\n' "$INST" > "$PROD/.git/loopd-bundle"

ctl() { ( cd "$INST" && bash scripts/control.sh "$@" ) >/dev/null 2>&1; }

# run <shape> <session_id> <prompt_id> <agent_type> <tool> <command|file_path> [project_dir]
run() {
  jq --arg s "$2" --arg p "$3" --arg t "$4" --arg n "$5" --arg c "$6" '
      .session_id = $s | .prompt_id = $p | .hook_event_name = "PreToolUse" | .tool_name = $n
      | (if has("agent_type") then .agent_type = $t else . end)
      | (if has("agent_id") then .agent_id = "sub-1" else . end)
      | (if $n == "Bash" then .tool_input = { command: $c } else .tool_input = { file_path: $c, old_string: "a", new_string: "b" } end)
      | (if $p == "" then del(.prompt_id) else . end)' "$FIX/$1.PreToolUse.Bash.json" > "$TMP/payload"
  OUT="$(CLAUDE_PROJECT_DIR="${7:-$WT}" bash "$HOOK" < "$TMP/payload" 2>/dev/null)"; RC=$?
}
verdict() { if [ -z "$OUT" ]; then echo allowed; else printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"'; fi; }
reason()  { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }
state()   { find "$CTL" -type f | sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done | cksum | tr -d ' '; }
RT=loopd:software-engineer

echo "== doom loop: the Nth identical call of a role session is denied"
S1=11111111-aaaa-4bbb-8ccc-000000000001
run bg-agent "$S1" p1 "$RT" Bash "make test"; ok "call 1 allowed" "$(verdict)" allowed
run bg-agent "$S1" p1 "$RT" Bash "make test"; ok "call 2 allowed" "$(verdict)" allowed
run bg-agent "$S1" p1 "$RT" Bash "make test"; ok "call 3 denied at maxRepeatedToolCalls=3" "$(verdict)" deny
ok "…by the doom-loop guard" "$(reason | grep -c 'DOOM-LOOP')" 1
ok "…exit 0" "$RC" 0
run bg-agent "$S1" p1 "$RT" Bash "make lint"; ok "a different call is allowed" "$(verdict)" allowed
ok "roster names the session and its role" "$(awk -F'\t' -v s="$S1" '$1==s {print $2}' "$CTL/agents")" "$RT"

echo "== wall clock: past maxAgentMinutes a role session is capped"
S2=11111111-aaaa-4bbb-8ccc-000000000002
run bg-agent "$S2" p1 "$RT" Bash "echo start"; ok "first call allowed and starts the clock" "$(verdict)" allowed
CLK="$CTL/agents.d/$S2.started"
ok "clock records the round's prompt" "$(cut -d' ' -f2 "$CLK")" p1
printf '%s p1\n' "$(( $(date +%s) - 46 * 60 ))" > "$CLK"
run bg-agent "$S2" p1 "$RT" Bash "pnpm build"; ok "a call past 45 minutes is capped" "$(verdict)" deny
ok "…by the time cap" "$(reason | grep -c 'TIME CAP')" 1
run bg-agent "$S2" p1 "$RT" Bash "git push origin HEAD"; ok "past the cap: git push still allowed" "$(verdict)" allowed
run bg-agent "$S2" p1 "$RT" Edit "$TASKDOC"; ok "past the cap: Edit of its task doc allowed" "$(verdict)" allowed
run bg-agent "$S2" p1 "$RT" Edit "$INST/CLAUDE.md"; ok "past the cap: Edit of any other file capped" "$(verdict)" deny
run bg-agent "$S2" p1 "$RT" Edit "$INST/projects/p/tasks/../../../CLAUDE.md"; ok "past the cap: a ../ path out of tasks/ capped" "$(verdict)" deny
mkdir -p "$INST/projects/p/tasks/x/tasks"; : > "$INST/projects/p/tasks/x/tasks/t.md"
run bg-agent "$S2" p1 "$RT" Edit "$INST/projects/p/tasks/x/tasks/t.md"; ok "past the cap: a nested tasks/ directory capped" "$(verdict)" deny
ln -s "$INST/CLAUDE.md" "$INST/projects/p/tasks/link.md"
run bg-agent "$S2" p1 "$RT" Edit "$INST/projects/p/tasks/link.md"; ok "past the cap: a symlinked task doc capped" "$(verdict)" deny

echo "== resume: claude --bg --resume keeps the session; a new prompt restarts the clock"
run bg-resume "$S2" p2 "$RT" Bash "pnpm build"; ok "resumed round's first call allowed" "$(verdict)" allowed
ok "clock now keyed on the resumed round's prompt" "$(cut -d' ' -f2 "$CLK")" p2
ok "…and restarted (elapsed < 1 minute)" "$(( ( $(date +%s) - $(cut -d' ' -f1 "$CLK") ) < 60 ))" 1
run bg-resume "$S2" p2 "$RT" Bash "pnpm test"; ok "a later call in the same round does not restart it" "$(cut -d' ' -f2 "$CLK")" p2

echo "== no prompt_id: no clock, never a cap"
S3=11111111-aaaa-4bbb-8ccc-000000000003
run bg-agent "$S3" "" "$RT" Bash "echo x"; ok "allowed" "$(verdict)" allowed
ok "no clock file" "$([ -e "$CTL/agents.d/$S3.started" ] && echo yes || echo no)" no
ok "clock-unknown is logged" "$(grep -c "clock-unknown	$S3" "$CTL/control.log")" 1

echo "== halt reaches a role session by its session id, and only it"
S4=11111111-aaaa-4bbb-8ccc-000000000004
ctl halt "$S4" "wrong repo"
run bg-agent "$S4" p1 "$RT" Bash "echo y"; ok "halted session denied" "$(verdict)" deny
ok "…with continue:false" "$(printf '%s' "$OUT" | jq -r '.continue')" false
run bg-agent "$S1" p9 "$RT" Bash "echo y"; ok "another role session is not touched" "$(verdict)" allowed
ctl clear "$S4"

echo "== never matched: PM tick, owner's interactive session, and near misses"
S5=11111111-aaaa-4bbb-8ccc-000000000005
BEFORE="$(state)"
for rep in 1 2 3 4; do run bg-pm-tick "$S5" p1 loopd:project-manager Bash "make test"; done
ok "PM tick in a marked worktree: no deny at the 4th identical call" "$(verdict)" allowed
run interactive "$S5" p1 "" Bash "make test"; run interactive "$S5" p1 "" Bash "make test"
run interactive "$S5" p1 "" Bash "make test"; run interactive "$S5" p1 "" Bash "make test"
ok "owner's session in a marked worktree: no deny" "$(verdict)" allowed
run bg-agent "$S5" p1 "$RT" Bash "make test" "$INST"; ok "role agent_type rooted in the bundle itself: silent" "$OUT" ""
run bg-agent "$S5" p1 loopd:probe Bash "make test"; ok "an agent this plugin does not ship: silent" "$OUT" ""
run bg-agent "$S5" p1 software-engineer Bash "make test"; ok "a bare, un-namespaced agent_type: silent" "$OUT" ""
rm -f "$PROD/.git/loopd-bundle"
run bg-agent "$S5" p1 "$RT" Bash "make test"; ok "no .git/loopd-bundle marker: silent" "$OUT" ""
printf '%s\n' "$INST" > "$PROD/.git/loopd-bundle"
ok "none of those wrote a state file, roster line or log line" "$(state)" "$BEFORE"
ctl halt "$S5" "should not reach the tick"
run bg-pm-tick "$S5" p1 loopd:project-manager Bash "echo z"; ok "a halt naming the tick's session never reaches it" "$(verdict)" allowed
ctl clear "$S5"

echo "== a subagent stays keyed on agent_id"
run subagent "$S1" p1 general-purpose Bash "echo s"
ok "roster gains the subagent's agent_id, not its session" "$(awk -F'\t' '$1=="sub-1"' "$CTL/agents" | wc -l | tr -d ' ')" 1

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
