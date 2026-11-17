#!/usr/bin/env bash
#
# agent-control-stuck-signature.test.sh — `plugin/hooks/agent-control.sh` logs ONE
# `stuck-signature` line for a role session or a subagent that repeats a failure or piles up
# errors past `stuckSignature`'s call floor, denies nothing, and is a no-op with the key unset.
# Payloads are the measured keys-only fixtures in tests/fixtures/hook-payloads/.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$REPO/tests/fixtures/hook-payloads"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/stucksig.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed (the hook requires it)"; exit 0; }

INST="$TMP/inst"; mkdir -p "$INST/scripts" "$INST/.claude/control"
printf '{"stuckSignature":true}\n' > "$INST/instance.config.json"
cp "$REPO/plugin/scripts/control.sh" "$REPO/plugin/scripts/bundle-paths.sh" "$INST/scripts/"
PLUG="$TMP/plugin"; mkdir -p "$PLUG/hooks" "$PLUG/scripts" "$PLUG/agents" "$PLUG/.claude-plugin"
cp "$REPO/plugin/.claude-plugin/plugin.json" "$PLUG/.claude-plugin/"
cp "$REPO/plugin/hooks/agent-control.sh" "$PLUG/hooks/"
cp "$REPO/plugin/scripts/resolve-config.sh" "$PLUG/scripts/"
cp "$REPO"/plugin/agents/*.md "$PLUG/agents/"
HOOK="$PLUG/hooks/agent-control.sh"
CTL="$INST/.claude/control"; LOG="$CTL/control.log"

PROD="$TMP/prod"; git init -q "$PROD"; git -C "$PROD" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m i
WT="$TMP/wt"; git -C "$PROD" worktree add -q "$WT" -b task-001 >/dev/null 2>&1
printf '%s\n' "$INST" > "$PROD/.git/loopd-bundle"
RT="$(jq -r .name "$REPO/plugin/.claude-plugin/plugin.json"):software-engineer"

# ev <shape> <event> <session> <command> [error] — one hook call; DENIES counts any output.
DENIES=0
ev() {
  local fx="$FIX/$1.$2.Bash.json" t="$RT"
  case "$1" in subagent) t=general-purpose ;; bg-pm-tick) t="${RT%%:*}:project-manager" ;; esac
  jq --arg e "$2" --arg s "$3" --arg c "$4" --arg err "${5:-}" --arg t "$t" '
      .session_id = $s | .hook_event_name = $e | .tool_name = "Bash" | .tool_input = { command: $c }
      | (if has("agent_type") then .agent_type = $t else . end)
      | (if has("agent_id") then .agent_id = "sub-1" else . end)
      | (if has("error") then .error = $err else . end)' "$fx" > "$TMP/payload"
  out="$(CLAUDE_PROJECT_DIR="$WT" bash "$HOOK" < "$TMP/payload" 2>/dev/null)"
  [ -z "$out" ] || DENIES=$((DENIES+1))
}
# call <shape> <session> <command> [error] — PreToolUse, then PostToolUseFailure if it failed.
call() { ev "$1" PreToolUse "$2" "$3"; [ -z "${4:-}" ] || ev "$1" PostToolUseFailure "$2" "$3" "$4"; }
lines() { cat "$LOG" 2>/dev/null | grep -c "stuck-signature"; }
varied() { local i; for i in $(seq 1 "$3"); do call "$1" "$2" "echo step $i"; done; }

echo "== a role session: varied commands, one repeated failure ⇒ one line"
S1=11111111-aaaa-4bbb-8ccc-000000000001
varied bg-agent "$S1" 18
call bg-agent "$S1" "pnpm test --filter a" $'Exit code 1\nError: Cannot find module /tmp/x/a.js at 12:7'
call bg-agent "$S1" "pnpm test --filter b" $'Exit code 1\nError: Cannot find module /var/y/b.js at 40:2'
ok "two of one signature: no line yet" "$(lines)" 0
call bg-agent "$S1" "pnpm test --filter c" $'Exit code 1\nError: Cannot find module ./c.js at 9:1'
ok "the third, past C=18 calls, logs one line" "$(lines)" 1
L="$(grep stuck-signature "$LOG")"
ok "…naming the session, the role and the tool" "$(printf '%s' "$L" | awk -F'\t' -v s="$S1" '$3==s && $4 ~ /software-engineer$/ && $5=="Bash" {print "yes"}')" yes
ok "…the arm, the counts and a fingerprint" "$(printf '%s' "$L" | grep -cE 'arm=repeat calls=21 errors=3 repeats=3 fingerprint=[0-9a-f]{16} session=')" 1
ok "…and never the output, in the log or the state" "$(grep -rc 'Cannot find' "$CTL" | awk -F: '{n+=$NF} END {print n+0}')" 0
call bg-agent "$S1" "pnpm test --filter d" $'Exit code 1\nError: Cannot find module /z/d.js at 1:1'
ok "a fourth repeat adds no second line" "$(lines)" 1
ok "nothing was denied" "$DENIES" 0

echo "== a dispatched subagent gets its own line"
S2=11111111-aaaa-4bbb-8ccc-000000000002
varied subagent "$S2" 18
for i in 1 2 3; do call subagent "$S2" "cargo build -p c$i" $'Exit code 101\nerror[E0425]: cannot find value `x'"$i"'` in /src/m'"$i"'.rs'; done
ok "the subagent's repeat logs one line" "$(grep -c $'stuck-signature\tsub-1\tgeneral-purpose' "$LOG")" 1

echo "== distinct failures, fewer than E, past C ⇒ none"
: > "$LOG"
S3=11111111-aaaa-4bbb-8ccc-000000000003
varied bg-agent "$S3" 18
for e in "No such file" "Permission denied" "Connection refused" "Syntax error" "Timed out" "Out of memory" "Bad gateway"; do
  call bg-agent "$S3" "run $e" $'Exit code 2\n'"$e"
done
ok "seven distinct failures: no line" "$(lines)" 0
call bg-agent "$S3" "run eighth" $'Exit code 2\nUnknown flag'
ok "the eighth error (E=8) logs the errors arm" "$(grep -c 'arm=errors calls=26 errors=8 repeats=1' "$LOG")" 1

echo "== the call floor: a repeat before C calls ⇒ none"
: > "$LOG"
S4=11111111-aaaa-4bbb-8ccc-000000000004
for i in 1 2 3 4; do call bg-agent "$S4" "make $i" $'Exit code 2\nmake: *** [all] Error 2'; done
ok "four repeats in four calls: no line" "$(lines)" 0

echo "== REPEAT_SKIP waits are transparent"
S5=11111111-aaaa-4bbb-8ccc-000000000005
varied bg-agent "$S5" 18
for i in $(seq 1 12); do call bg-agent "$S5" "gh pr checks 12" $'Exit code 8\nsome checks are still pending'; done
ok "twelve failing waits past C: no line" "$(lines)" 0
ok "…and not counted as calls" "$(cut -d' ' -f1 "$CTL/stuck/$S5.n")" 18
call bg-agent "$S5" "sleep 1; make" $'Exit code 2\nmake failed'
call bg-agent "$S5" "sleep 1; make" $'Exit code 2\nmake failed'
call bg-agent "$S5" "sleep 1; make" $'Exit code 2\nmake failed'
ok "a wait chained to work is counted" "$(lines)" 1

echo "== never matched: the PM tick and the owner's session"
: > "$LOG"
for s in bg-pm-tick interactive; do
  varied "$s" 11111111-aaaa-4bbb-8ccc-000000000006 18
  for i in 1 2 3; do call "$s" 11111111-aaaa-4bbb-8ccc-000000000006 "x" $'Exit code 1\nboom'; done
done
ok "no line for either" "$(lines)" 0

echo "== D3: the ring keeps the last 64 signatures"
S7=11111111-aaaa-4bbb-8ccc-000000000007
for i in $(seq 1 80); do ev bg-agent PostToolUseFailure "$S7" "t" "Exit code 1"$'\n'"distinct failure $(printf '%s' "$i" | tr 0-9 a-j)"; done
ok "80 failures leave a ring of 64" "$(wc -l < "$CTL/stuck/$S7" | tr -d ' ')" 64
ok "…and the error count of 80" "$(cut -d' ' -f2 "$CTL/stuck/$S7.n")" 80
ok "…in a bounded set of files" "$(ls "$CTL/stuck" | grep -c "^$S7")" 2

echo "== control.sh round resets a role session for its next round"
( cd "$INST" && bash scripts/control.sh round "$S1" ) >/dev/null 2>&1
ok "round clears the state" "$(ls "$CTL/stuck" | grep -c "^$S1" || true)" 0

echo "== key absent from both layers ⇒ nothing hashed, counted or written but one cache line"
printf '{}\n' > "$INST/instance.config.json"; printf '{"stuckSignature":null}\n' > "$INST/instance.config.local.json"
rm -rf "$CTL"; mkdir -p "$CTL"
S8=11111111-aaaa-4bbb-8ccc-000000000008
varied bg-agent "$S8" 18
for i in 1 2 3 4; do call bg-agent "$S8" "x" $'Exit code 1\nboom'; done
ok "no stuck state" "$([ -e "$CTL/stuck" ] && echo yes || echo no)" no
ok "one cache line, reading off" "$(cut -d' ' -f1 "$CTL/stuck-limit") $(wc -l < "$CTL/stuck-limit" | tr -d ' ')" "off 1"
ok "no log line" "$(lines)" 0

echo "== overrides: a local object beats the tracked true"
printf '{"stuckSignature":true}\n' > "$INST/instance.config.json"
printf '{"stuckSignature":{"calls":2,"repeats":2,"errors":"x"}}\n' > "$INST/instance.config.local.json"
rm -f "$CTL/stuck-limit"
S9=11111111-aaaa-4bbb-8ccc-000000000009
call bg-agent "$S9" "a" $'Exit code 1\nboom'; call bg-agent "$S9" "b" $'Exit code 1\nboom'
ok "C=2 N=2 from the local layer, a bad E falls to 8" "$(cat "$CTL/stuck-limit" | cut -d' ' -f1)" "2,2,8"
ok "…and logs at the second repeat" "$(lines)" 1

echo "== fail open: an unreadable payload logs and allows"
printf 'not json' | CLAUDE_PROJECT_DIR="$WT" bash "$HOOK" >/dev/null 2>&1; ok "exit 0" "$?" 0

echo
echo "agent-control-stuck-signature: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
