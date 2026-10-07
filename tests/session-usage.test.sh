#!/usr/bin/env bash
#
# session-usage.test.sh — a detached session's cost, read from its own transcript, and
# the `agent-usage.sh settle` that fills a dispatch line once that number exists:
# `plugin/scripts/session-usage.sh` and `plugin/scripts/agent-usage.sh`.
#
# THE PROPERTIES, each asserted from both sides:
#   * ONE MESSAGE, ONE COUNT. A transcript repeats a message's usage on every content
#     block's line (2.2 lines per message, measured); summing lines doubles the figure.
#   * UNKNOWN ON ANY DOUBT, NEVER A ZERO — no transcript, two candidates, no usage
#     record, a file that is not JSONL.
#   * SETTLE FILLS THE LAST UNKNOWN LINE AND NOTHING ELSE: a measured line is never
#     rewritten, and a task with no UNKNOWN line is refused.
#   * CACHE READS STAY APART from `tokens`, so `total` and `series` sum what they summed.
#   * THE LINE NAMES WHERE THE CALLS WENT AND HOW MANY FAILED — `errors=N by=Name:N,…`
#     appended after `cached=`, each call counted once by its own id, `by` the top five by
#     count then name and summing to `tools`, `-` for none; a name outside the grammar is
#     UNKNOWN. Every reader of the old line (`total`, `series`) still reads the new one.
#   * TOKENS, NEVER MONEY.
# Fixtures live under mktemp; no real transcript is read. ok() compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"
SU="$REPO/plugin/scripts/session-usage.sh"
AU="$REPO/plugin/scripts/agent-usage.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sessusage.XXXXXX")" || {
  echo "session-usage.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed (the reader requires it)"; exit 0; }

P="$TMP/projects"; mkdir -p "$P/-work-wt-task-001" "$P/-work-wt-task-002"
SID="0a1b2c3d-1111-2222-3333-444455556666"
T="$P/-work-wt-task-001/$SID.jsonl"
# Three assistant messages. msg_A is written as FOUR lines (text, tool_use, the same
# tool_use again verbatim, tool_use) each repeating the same usage; msg_C as two lines
# (Bash, Bash+Edit); msg_B as one. The tool results come back on user lines — tu_2 failed,
# and that failure is written twice; tu_5 failed once. A line with no usage and one that
# is not JSON at all sit between them.
{
  printf '%s\n' '{"type":"user","timestamp":"2026-01-01T00:00:00.000Z","message":{"role":"user","content":"go"}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:01.500Z","message":{"id":"msg_A","model":"m","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":5},"content":[{"type":"text","text":"hi"}]}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:02.000Z","message":{"id":"msg_A","model":"m","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":5},"content":[{"type":"tool_use","id":"tu_1","name":"Bash","input":{}}]}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:02.000Z","message":{"id":"msg_A","model":"m","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":5},"content":[{"type":"tool_use","id":"tu_1","name":"Bash","input":{}}]}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:02.100Z","message":{"id":"msg_A","model":"m","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":7},"content":[{"type":"tool_use","id":"tu_2","name":"Read","input":{}}]}}'
  printf '%s\n' '{"type":"user","timestamp":"2026-01-01T00:00:02.500Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu_1","content":"ok"},{"type":"tool_result","tool_use_id":"tu_2","is_error":true,"content":"ENOENT"}]}}'
  printf '%s\n' '{"type":"user","timestamp":"2026-01-01T00:00:02.500Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu_2","is_error":true,"content":"ENOENT"}]}}'
  printf '%s\n' 'this line is not json'
  printf '%s\n' '{"type":"system","timestamp":"2026-01-01T00:00:03.000Z"}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:04.000Z","message":{"id":"msg_C","model":"m","usage":{"input_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1},"content":[{"type":"tool_use","id":"tu_3","name":"Bash","input":{}}]}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:04.100Z","message":{"id":"msg_C","model":"m","usage":{"input_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1},"content":[{"type":"tool_use","id":"tu_4","name":"Bash","input":{}},{"type":"tool_use","id":"tu_5","name":"Edit","input":{}}]}}'
  printf '%s\n' '{"type":"user","timestamp":"2026-01-01T00:00:05.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu_3","is_error":false,"content":"ok"},{"type":"tool_result","tool_use_id":"tu_4","content":"ok"},{"type":"tool_result","tool_use_id":"tu_5","is_error":true,"content":"no match"}]}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:10.000Z","message":{"id":"msg_B","model":"m","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":2000,"output_tokens":3},"content":[{"type":"text","text":"done"}]}}'
} > "$T"

run() { bash "$SU" "$@" --projects-dir "$P" 2>/dev/null; }
LINE="usage tokens=124 tools=5 ms=10000 cached=3000 errors=2 by=Bash:3,Edit:1,Read:1"
val() { # <line> <key> -> the value, or `none`
  awk -v k="$2" '{ for (i = 1; i <= NF; i++) if (index($i, k "=") == 1) { print substr($i, length(k) + 2); exit } ; print "none" }' <<<"$1"; }

echo "== one message, one count =="
# msg_A counted once at its LAST line (output 7): 10+100+7 = 117; msg_C: 2+0+1 = 3; msg_B: 1+0+3 = 4.
ok "tokens = fresh input + cache writes + output, per message" "$(run "$SID")" "$LINE"
ok "…a naive per-line sum would have said 462 — it does not" \
   "$(run "$SID" | grep -c 'tokens=462')" 0
ok "exit 0 when it printed numbers"               "$(run "$SID" >/dev/null; echo $?)" 0
ok "the 8-character short id finds the same file" "$(run "0a1b2c3d")" "$LINE"
ok "cache reads are NOT inside tokens"            "$(run "$SID" | grep -c 'tokens=3124')" 0

echo "== where the calls went, and how many failed — each call counted once =="
got="$(run "$SID")"
ok "tools counts a tool_use block ONCE however many lines repeat it" "$(val "$got" tools)" 5
ok "by= lists count-desc, ties by name"           "$(val "$got" by)" "Bash:3,Edit:1,Read:1"
ok "…and sums to tools"                           "$(val "$got" by | tr ',' '\n' | awk -F: '{ s += $2 } END { print s + 0 }')" "$(val "$got" tools)"
ok "errors counts a failed call ONCE though its result was written twice" "$(val "$got" errors)" 2
ok "…and an is_error:false result is not one"     "$(val "$got" errors | grep -c '^3$')" 0
ok "the first four keys keep their place and order" \
   "$(awk '{ print $2, $3, $4, $5 }' <<<"$got" | sed 's/=[0-9]*//g')" "tokens tools ms cached"
ok "the new keys append after cached="            "$(awk '{ sub(/=.*/, "", $6); sub(/=.*/, "", $7); print $6, $7 }' <<<"$got")" "errors by"
ok "the line is ONE line with no space inside a value" "$(printf '%s\n' "$got" | wc -l | tr -d ' ') $(awk '{ print NF }' <<<"$got")" "1 7"
# Six names call for the cut: the fifth place goes to the alphabetically earlier of the tie.
H="cccccccc-0000-0000-0000-000000000003"
{ printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:00.000Z","message":{"id":"m1","usage":{"input_tokens":1,"output_tokens":1},"content":[{"type":"tool_use","id":"h1","name":"Zeta","input":{}},{"type":"tool_use","id":"h2","name":"Zeta","input":{}},{"type":"tool_use","id":"h3","name":"Gamma","input":{}},{"type":"tool_use","id":"h4","name":"Alpha","input":{}},{"type":"tool_use","id":"h5","name":"Eps","input":{}},{"type":"tool_use","id":"h6","name":"Beta","input":{}},{"type":"tool_use","id":"h7","name":"mcp__x-y__z.w","input":{}}]}}'
} > "$P/-work-wt-task-002/$H.jsonl"
ok "by= is capped at the top five, so tools can exceed its sum" "$(run "$H")" "usage tokens=2 tools=7 ms=0 cached=0 errors=0 by=Zeta:2,Alpha:1,Beta:1,Eps:1,Gamma:1"
Z="dddddddd-0000-0000-0000-000000000004"
printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:00.000Z","message":{"id":"m1","usage":{"input_tokens":1,"output_tokens":1},"content":[{"type":"text","text":"hi"}]}}' > "$P/-work-wt-task-002/$Z.jsonl"
ok "a session that called no tool: tools=0 errors=0 by=-" "$(run "$Z")" "usage tokens=2 tools=0 ms=0 cached=0 errors=0 by=-"
N1="eeeeeeee-0000-0000-0000-000000000005"
printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:00.000Z","message":{"id":"m1","usage":{"input_tokens":1,"output_tokens":1},"content":[{"type":"tool_use","id":"n1","name":"Bash","input":{}},{"type":"tool_use","id":"n2","name":"a tool,with:junk","input":{}}]}}' > "$P/-work-wt-task-002/$N1.jsonl"
ok "a tool name outside the grammar is UNKNOWN, never a shorter list" "$(run "$N1")" "usage UNKNOWN"
N2="eeeeeeee-0000-0000-0000-000000000006"
printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:00.000Z","message":{"id":"m1","usage":{"input_tokens":1,"output_tokens":1},"content":[{"type":"tool_use","id":"n1","name":7,"input":{}}]}}' > "$P/-work-wt-task-002/$N2.jsonl"
ok "…and so is a tool_use whose name is not a string" "$(run "$N2")" "usage UNKNOWN"
N3="eeeeeeee-0000-0000-0000-000000000007"
{ printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:00.000Z","message":{"id":"m1","usage":{"input_tokens":1,"output_tokens":1},"content":[{"type":"tool_use","id":"n1","name":"Bash","input":{}}]}}'
  printf '%s\n' '{"type":"user","timestamp":"2026-01-01T00:00:01.000Z","message":{"role":"user","content":[{"type":"tool_result","is_error":true,"content":"x"}]}}'
} > "$P/-work-wt-task-002/$N3.jsonl"
ok "a failed result that names no call is UNKNOWN, never errors=0" "$(run "$N3")" "usage UNKNOWN"

echo "== UNKNOWN on any doubt, never a zero =="
ok "no transcript for the id"                     "$(run "ffffffff-0000-0000-0000-000000000000")" "usage UNKNOWN"
ok "…and that is exit 1"                          "$(run "ffffffff-0000-0000-0000-000000000000" >/dev/null; echo $?)" 1
cp "$T" "$P/-work-wt-task-002/$SID.jsonl"
ok "two candidates for one id"                    "$(run "$SID")" "usage UNKNOWN"
rm "$P/-work-wt-task-002/$SID.jsonl"
E="aaaaaaaa-0000-0000-0000-000000000001"
printf '%s\n' '{"type":"user","timestamp":"2026-01-01T00:00:00.000Z","message":{"role":"user","content":"go"}}' > "$P/-work-wt-task-002/$E.jsonl"
ok "a transcript with no usage record"            "$(run "$E")" "usage UNKNOWN"
G="bbbbbbbb-0000-0000-0000-000000000002"
printf 'not a transcript\nat all\n' > "$P/-work-wt-task-002/$G.jsonl"
ok "a file that is not JSONL"                     "$(run "$G")" "usage UNKNOWN"
ok "no figure is ever a bare zero"                "$(for i in "$E" "$G" ffffffff; do run "$i"; done | grep -c 'tokens=0')" 0
ok "an id with a glob character is a usage error" "$(bash "$SU" '0a1b*' --projects-dir "$P" >/dev/null 2>&1; echo $?)" 3
ok "…and so is one too short to be an id"         "$(bash "$SU" 'ab' --projects-dir "$P" >/dev/null 2>&1; echo $?)" 3
ok "no argument is a usage error"                 "$(bash "$SU" >/dev/null 2>&1; echo $?)" 3

echo "== settle fills the LAST UNKNOWN dispatch line, and nothing else =="
DOC="$TMP/task.md"
mk() { printf '%s\n' '---' 'type: Task' 'status: in-progress' '---' '' '# Context' '' 'x' '' '# Notes' '' "$@" > "$DOC"; }
mk '* DISPATCH 2026-01-01T00:00:00Z · software-engineer · model opus · usage tokens=5 tools=1 ms=9' \
   '* DISPATCH 2026-01-02T00:00:00Z · software-engineer · model opus · usage UNKNOWN' \
   '* DISPATCH 2026-01-03T00:00:00Z · qa-reviewer · model opus · usage UNKNOWN'
ok "settle through the reader succeeds"           "$(run "$SID" --settle "$DOC" >/dev/null; echo $?)" 0
ok "the LAST unknown line carries the numbers"    "$(grep -c "^\* DISPATCH 2026-01-03T00:00:00Z · qa-reviewer · model opus · $LINE\$" "$DOC")" 1
ok "the EARLIER unknown line is untouched"        "$(grep -c '^\* DISPATCH 2026-01-02T00:00:00Z · software-engineer · model opus · usage UNKNOWN$' "$DOC")" 1
ok "the MEASURED line is untouched"               "$(grep -c '^\* DISPATCH 2026-01-01T00:00:00Z · software-engineer · model opus · usage tokens=5 tools=1 ms=9$' "$DOC")" 1
ok "no line was added or lost"                    "$(grep -c '^\* DISPATCH ' "$DOC")" 3
ok "the rest of the document is byte-identical"   "$(sed -n '1,10p' "$DOC" | cksum | cut -d' ' -f1)" "$(printf '%s\n' '---' 'type: Task' 'status: in-progress' '---' '' '# Context' '' 'x' '' '# Notes' | cksum | cut -d' ' -f1)"
ok "a second settle takes the next unknown up"    "$(bash "$AU" settle "$DOC" --tokens 7 --tools 1 --duration-ms 3 >/dev/null 2>&1; grep -c 'model opus · usage tokens=7 tools=1 ms=3$' "$DOC")" 1
ok "with none left, settle is REFUSED (exit 1)"   "$(bash "$AU" settle "$DOC" --tokens 7 --tools 1 --duration-ms 3 >/dev/null 2>&1; echo $?)" 1
ok "…and the document did not change"             "$(grep -c 'usage UNKNOWN' "$DOC")" 0
mk '* DISPATCH 2026-01-02T00:00:00Z · software-engineer · model opus · usage UNKNOWN'
ok "settle without all three numbers is exit 3"   "$(bash "$AU" settle "$DOC" --tokens 7 >/dev/null 2>&1; echo $?)" 3
ok "…and leaves UNKNOWN in place"                 "$(grep -c 'usage UNKNOWN$' "$DOC")" 1
ok "an UNKNOWN reading settles NOTHING"           "$(run "$E" --settle "$DOC" >/dev/null; grep -c 'usage UNKNOWN$' "$DOC")" 1
ok "a line merely QUOTING the words is not a dispatch line" \
   "$(mk 'the brief said usage UNKNOWN'; bash "$AU" settle "$DOC" --tokens 1 --tools 1 --duration-ms 1 >/dev/null 2>&1; echo $?)" 1
mk '* DISPATCH 2026-01-02T00:00:00Z · software-engineer · model opus · usage UNKNOWN'
ok "settle with a --by that has a space is exit 3" "$(bash "$AU" settle "$DOC" --tokens 1 --tools 2 --duration-ms 3 --by 'Bash:1 Read:1' >/dev/null 2>&1; echo $?)" 3
ok "…with six names too"                          "$(bash "$AU" settle "$DOC" --tokens 1 --tools 6 --duration-ms 3 --by 'A:1,B:1,C:1,D:1,E:1,F:1' >/dev/null 2>&1; echo $?)" 3
ok "…and the line is still UNKNOWN"               "$(grep -c 'usage UNKNOWN$' "$DOC")" 1
ok "settle without the new keys writes the old line (an older reader's call)" \
   "$(bash "$AU" settle "$DOC" --tokens 1 --tools 2 --duration-ms 3 --cached 4 >/dev/null 2>&1; grep -c 'model opus · usage tokens=1 tools=2 ms=3 cached=4$' "$DOC")" 1

echo "== total and series still read a settled line =="
mk '* DISPATCH 2026-01-03T00:00:00Z · qa-reviewer · model opus · usage UNKNOWN'
run "$SID" --settle "$DOC" >/dev/null
ok "total sums the settled line"                  "$(bash "$AU" total "$DOC" --pr https://example.com/pr/1 >/dev/null 2>&1; grep -c '^\* TOTAL .* rounds=1 · usage tokens=124 tools=5 ms=10000 ' "$DOC")" 1
INST="$TMP/inst"; mkdir -p "$INST/$AB_DIR" "$INST/projects/p/tasks"; cp "$DOC" "$INST/projects/p/tasks/task-001.md"
printf '* TICK 2026-01-03T00:00:00Z by a close: x · usage tokens=10 tools=1 ms=100\n' > "$INST/$AB_LEDGER"
ok "series sums the settled line's first three keys and reads past the rest" \
   "$(bash "$AU" series --instance "$INST" | grep -c '^2026-01 · ticks 1 (1 measured) usage tokens=10 tools=1 ms=100 · dispatches 1 (1 measured) usage tokens=124 tools=5 ms=10000$')" 1

echo "== the threshold is stated in step 4 and in the design doc, the same number =="
S4="$REPO/plugin/tick-steps/step-4-advance.md"; PMD="$REPO/docs/pm-design.md"
for f in "$S4" "$PMD"; do
  ok "$(basename "$f") shows the line's new keys"  "$(grep -c 'usage tokens=N tools=N ms=N cached=N errors=N by=' "$f")" 1
  ok "…and the one thrashing threshold, 20% of at least 20" "$(grep -c '20% of `tools`.*`tools`.*at least 20\|above 20% of `tools` with `tools`.*at least 20' "$f")" 1
  ok "…as a `# Notes` line, report-only"          "$(grep -c 'thrashing: errors=N of tools=N' "$f")" 1
done
ok "step 4 reports it and never re-runs the round" "$(grep -c 'thrashed is REPORTED, never re-run' "$S4")" 1
ok "…and the design doc says no re-dispatch"      "$(grep -c 'no re-dispatch, because a checker that re-ran' "$PMD")" 1

echo "== tokens, never money =="
# No `\$[0-9]` arm here: this script reads its own positional parameters, and a pattern that
# matches `$1` would be measuring bash, not money.
money='USD\|EUR\|price\|pricing\|per million\|per 1M\|cents'
ok "no price, no currency, no pricing source"     "$(grep -ic "$money" "$SU" | tr -d ' ')" 0
ok "agent-usage.sh still names no transcript path" "$(grep -c 'claude/projects\|\.jsonl' "$AU" | tr -d ' ')" 0

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
