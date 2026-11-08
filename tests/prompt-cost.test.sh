#!/usr/bin/env bash
#
# prompt-cost.test.sh — `plugin/scripts/prompt-cost.sh`: tokens per assistant turn, per
# tick step and per dispatch role, from fixture transcripts; prints no message text.
#
# THE PROPERTIES:
#   * ONE MESSAGE, ONE COUNT — a message written on several lines is one turn.
#   * D1 — a tick's turns go to the tick-steps file last read BEFORE the turn; `core` before
#     any; the turn that issues the Read stays where it was composed.
#   * A subagent turn (`<session>/subagents/*.jsonl`) buckets apart (`+sub`), under the step
#     current at its timestamp, so a per-turn mean is the main thread's.
#   * ONCE ACROSS FILES — a resumed session copies its parent's messages into a new file:
#     the copy is the same session, its copied turns count once, its new turns count.
#   * COUNTS ONLY — a sentinel planted in every text field never reaches stdout.
#   * THE TICK NEVER RUNS IT — no tick step, agent prompt or skill names the script.
# Fixtures live under mktemp. ok() compares actual to expected.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PC="$REPO/plugin/scripts/prompt-cost.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/promptcost.XXXXXX")" || { echo "prompt-cost.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

P="$TMP/projects"; mkdir -p "$P/-work-bundle" "$P/-work-wt-task-002" "$P/-work-other"
SECRET="qzxv-never-printed-7731"
T1="11111111-1111-4111-8111-111111111111"; D1="22222222-2222-4222-8222-222222222222"
D2="33333333-3333-4333-8333-333333333333"; T2="44444444-4444-4444-8444-444444444444"
D3="77777777-7777-4777-8777-777777777777"
usage() { printf '"usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s}' "$@"; }
msg() { # <id> <ts> <usage> <content-json> [sidechain]
  printf '{"type":"assistant","timestamp":"%s","isSidechain":%s,"message":{"id":"%s",%s,"content":%s}}\n' "$2" "${5:-false}" "$1" "$3" "$4"; }
step_read() { printf '[{"type":"tool_use","id":"r%s","name":"Read","input":{"file_path":"/plug/tick-steps/%s.md"}}]' "$1" "$2"; }
text() { printf '[{"type":"text","text":"%s"}]' "$SECRET"; }

# The tick: 4 main turns + 1 subagent turn. m1 (core) reads step-3 on its second line, so
# m2 and m3 are step-3-dispatch; m3 reads step-8, so m4 is step-8-render. m1 is written on
# two lines with the same usage. The subagent turn s1 sits in the session's subagents/ dir,
# timestamped inside step-3.
{ printf '{"type":"agent-setting","agentSetting":"loopd:project-manager"}\n'
  printf '{"type":"user","timestamp":"2026-01-01T00:00:00Z","message":{"role":"user","content":"You are ONE LIVE tick. Tick id: `tick-20260101T000000Z-ab12` %s"}}\n' "$SECRET"
  msg m1 2026-01-01T00:00:01Z "$(usage 10 100 1000 5)" "$(text)"
  msg m1 2026-01-01T00:00:01Z "$(usage 10 100 1000 5)" "$(step_read 1 step-3-dispatch)"
  msg m2 2026-01-01T00:00:02Z "$(usage 20 200 2000 10)" "$(text)"
  msg m3 2026-01-01T00:00:03Z "$(usage 30 300 3000 15)" "$(step_read 2 step-8-render)"
  msg m4 2026-01-01T00:00:04Z "$(usage 40 400 4000 20)" "$(text)"
  printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"%s"}]}}\n' "$SECRET"
} > "$P/-work-bundle/$T1.jsonl"
mkdir -p "$P/-work-bundle/$T1/subagents"
{ printf '{"type":"user","isSidechain":true,"timestamp":"2026-01-01T00:00:02Z","message":{"role":"user","content":"sub brief %s"}}\n' "$SECRET"
  msg s1 2026-01-01T00:00:02.500Z "$(usage 1 1 100 1)" "$(text)" true
} > "$P/-work-bundle/$T1/subagents/agent-s1.jsonl"
# A later tick that reads no step at all (the idle fast path).
{ printf '{"type":"agent-setting","agentSetting":"loopd:project-manager"}\n'
  printf '{"type":"user","timestamp":"2026-02-01T00:00:00Z","message":{"role":"user","content":"Tick id: `tick-20260201T000000Z-cd34`"}}\n'
  msg n1 2026-02-01T00:00:01Z "$(usage 2 0 500 3)" "$(text)"
} > "$P/-work-bundle/$T2.jsonl"
# Two dispatches: a software-engineer (two turns, one subagent turn, then resumed: D3 copies
# d1 and d2 and adds d3) and a qa-reviewer (one).
{ printf '{"type":"agent-setting","agentSetting":"loopd:software-engineer"}\n'
  printf '{"type":"user","timestamp":"2026-01-02T00:00:00Z","message":{"role":"user","content":"brief %s"}}\n' "$SECRET"
  msg d1 2026-01-02T00:00:01Z "$(usage 5 50 500 7)" "$(text)"
  msg d2 2026-01-02T00:00:02Z "$(usage 5 50 700 9)" "$(step_read 3 step-3-dispatch)"
} > "$P/-work-wt-task-002/$D1.jsonl"
mkdir -p "$P/-work-wt-task-002/$D1/subagents"
msg e1 2026-01-02T00:00:01.500Z "$(usage 3 3 300 3)" "$(text)" true > "$P/-work-wt-task-002/$D1/subagents/agent-e1.jsonl"
{ cat "$P/-work-wt-task-002/$D1.jsonl"
  msg d3 2026-01-02T00:00:03Z "$(usage 5 50 900 11)" "$(text)"
} > "$P/-work-wt-task-002/$D3.jsonl"
{ printf '{"type":"agent-setting","agentSetting":"loopd:qa-reviewer"}\n'
  msg q1 2026-01-03T00:00:01Z "$(usage 8 80 800 4)" "$(text)"
} > "$P/-work-wt-task-002/$D2.jsonl"
# Noise: a session with no agent setting, and a file that is not JSONL.
msg x1 2026-01-01T00:00:01Z "$(usage 9 9 9 9)" "$(text)" > "$P/-work-other/55555555-5555-4555-8555-555555555555.jsonl"
printf 'not json %s\n' "$SECRET" > "$P/-work-other/66666666-6666-4666-8666-666666666666.jsonl"

run() { bash "$PC" --projects-dir "$P" "$@" 2>&1; }
row() { printf '%s\n' "$2" | awk -v k="$1" '$1 == k {print}' | awk -v b="$2" 'NR==1'; }
cell() { # <kind> <bucket> <output> <column index>
  awk -v k="$1" -v b="$2" -v c="$4" '$1 == k && $2 == b && !done { print $c; done = 1 }' <<<"$3"; }

echo "== 1. buckets, turns and sums =="
OUT="$(run)"; rc=$?
ok "exit 0 with measurable sessions" "$rc" 0
ok "tick core: m1 (on two lines, once) and the idle tick"  "$(cell tick core "$OUT" 4)" 2
ok "…cache_read 1500, m1 not doubled"                   "$(cell tick core "$OUT" 7)" 1500
ok "step-3-dispatch: m2 and m3 (the reading turn stays)" "$(cell tick step-3-dispatch "$OUT" 4)" 2
ok "…cache_read 5000, cread/turn 2500"                  "$(cell tick step-3-dispatch "$OUT" 7),$(cell tick step-3-dispatch "$OUT" 11)" "5000,2500"
ok "step-8-render: m4 only"                             "$(cell tick step-8-render "$OUT" 4)" 1
ok "the subagent turn buckets as step-3-dispatch+sub (by its timestamp)" "$(cell tick step-3-dispatch+sub "$OUT" 4)" 1
ok "tick all: 2 sessions, 5 main-thread turns"          "$(cell tick all "$OUT" 3),$(cell tick all "$OUT" 4)" "2,5"
ok "…input, output, cache_read, cache_write summed"     "$(cell tick all "$OUT" 5) $(cell tick all "$OUT" 6) $(cell tick all "$OUT" 7) $(cell tick all "$OUT" 8)" "102 53 10500 1000"
ok "…subagent turns total apart as all+sub"             "$(cell tick all+sub "$OUT" 4),$(cell tick all+sub "$OUT" 7)" "1,100"
ok "dispatch by role: software-engineer 3 turns (d1, d2 once; d3 from the resumed copy)" "$(cell dispatch software-engineer "$OUT" 4)" 3
ok "…the resumed copy is not a second session"          "$(cell dispatch software-engineer "$OUT" 3)" 1
ok "…a step Read in a dispatch is not a tick step"      "$(printf '%s\n' "$OUT" | grep -c 'dispatch  step-')" 0
ok "…cread/turn 700"                                    "$(cell dispatch software-engineer "$OUT" 11)" 700
ok "…its subagent turn buckets as software-engineer+sub" "$(cell dispatch software-engineer+sub "$OUT" 4),$(cell dispatch software-engineer+sub "$OUT" 7)" "1,300"
ok "qa-reviewer 1 turn, 800 cache_read"                 "$(cell dispatch qa-reviewer "$OUT" 4),$(cell dispatch qa-reviewer "$OUT" 7)" "1,800"
ok "dispatch all: 2 sessions, 4 turns"                  "$(cell dispatch all "$OUT" 3),$(cell dispatch all "$OUT" 4)" "2,4"
ok "a session with no agent setting is not counted"     "$(printf '%s\n' "$OUT" | grep -c '^dispatch  all .* 2 ')" 1

echo "== 2. counts only, never text =="
ok "the sentinel in text, brief, tool_result and subagent file never prints" "$(printf '%s' "$OUT" | grep -c "$SECRET")" 0
OUT_S="$(run --sessions)"
ok "…nor with --sessions"                                "$(printf '%s' "$OUT_S" | grep -c "$SECRET")" 0
ok "--sessions lists each session once, by id"           "$(printf '%s\n' "$OUT_S" | grep -c -E "^(tick|dispatch) +($T1|$T2|$D1|$D2) ")" 4
ok "…the resumed copy is listed under its parent, with 3 turns" "$(printf '%s\n' "$OUT_S" | grep -c " $D3 "),$(printf '%s\n' "$OUT_S" | awk -v s="$D1" '$2 == s {print $3}')" "0,3"
ok "…the tick's per-session cread/turn is the main-thread mean" "$(printf '%s\n' "$OUT_S" | awk -v s="$T1" '$2 == s {print $8}')" 2500

echo "== 3. the window =="
ok "--since keeps sessions whose first turn is at or after it" "$(cell tick all "$(run --since 2026-01-02)" 3),$(cell dispatch all "$(run --since 2026-01-02)" 3)" "1,2"
ok "--limit 1 keeps the most recent of each kind"        "$(cell tick all "$(run --limit 1)" 4),$(cell dispatch all "$(run --limit 1)" 4)" "1,1"
ok "--kind tick drops every dispatch row"                "$(printf '%s\n' "$(run --kind tick)" | grep -c '^dispatch')" 0
run --since 2027-01-01 >/dev/null 2>&1; ok "an empty window is exit 1, never a zero table" "$?" 1
mkdir -p "$TMP/empty"; bash "$PC" --projects-dir "$TMP/empty" >/dev/null 2>&1; ok "no transcript at all is exit 1" "$?" 1
bash "$PC" --bogus >/dev/null 2>&1; ok "an unknown flag is usage (exit 3)" "$?" 3
bash "$PC" --projects-dir "$P" --kind step >/dev/null 2>&1; ok "…and so is a kind outside tick|dispatch" "$?" 3

echo "== 4. the tick never runs the report =="
hits="$(grep -rl 'prompt-cost' "$REPO/plugin/tick-steps" "$REPO/plugin/agents" "$REPO/plugin/skills" "$REPO/plugin/hooks" 2>/dev/null | wc -l | tr -d ' ')"
ok "no tick step, agent prompt, skill or hook names prompt-cost" "$hits" 0

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
