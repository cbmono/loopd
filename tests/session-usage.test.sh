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
#   * TOKENS, NEVER MONEY.
# Fixtures live under mktemp; no real transcript is read. ok() compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
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
# Two assistant messages. msg_A is written as THREE lines (text, tool_use, tool_use) each
# repeating the same usage; msg_B as one. A user line, a line with no usage, and one line
# that is not JSON at all sit between them.
{
  printf '%s\n' '{"type":"user","timestamp":"2026-01-01T00:00:00.000Z","message":{"role":"user","content":"go"}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:01.500Z","message":{"id":"msg_A","model":"m","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":5},"content":[{"type":"text","text":"hi"}]}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:02.000Z","message":{"id":"msg_A","model":"m","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":5},"content":[{"type":"tool_use","id":"tu_1","name":"Bash","input":{}}]}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:02.100Z","message":{"id":"msg_A","model":"m","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":7},"content":[{"type":"tool_use","id":"tu_2","name":"Read","input":{}}]}}'
  printf '%s\n' 'this line is not json'
  printf '%s\n' '{"type":"system","timestamp":"2026-01-01T00:00:03.000Z"}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:10.000Z","message":{"id":"msg_B","model":"m","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":2000,"output_tokens":3},"content":[{"type":"text","text":"done"}]}}'
} > "$T"

run() { bash "$SU" "$@" --projects-dir "$P" 2>/dev/null; }

echo "== one message, one count =="
# msg_A counted once at its LAST line (output 7): 10+100+7 = 117; msg_B: 1+0+3 = 4.
ok "tokens = fresh input + cache writes + output, per message" \
   "$(run "$SID")" "usage tokens=121 tools=2 ms=10000 cached=3000"
ok "…a naive per-line sum would have said 349 — it does not" \
   "$(run "$SID" | grep -c 'tokens=349')" 0
ok "exit 0 when it printed numbers"               "$(run "$SID" >/dev/null; echo $?)" 0
ok "the 8-character short id finds the same file" "$(run "0a1b2c3d")" "usage tokens=121 tools=2 ms=10000 cached=3000"
ok "cache reads are NOT inside tokens"            "$(run "$SID" | grep -c 'tokens=3121')" 0

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
ok "the LAST unknown line carries the numbers"    "$(grep -c '^\* DISPATCH 2026-01-03T00:00:00Z · qa-reviewer · model opus · usage tokens=121 tools=2 ms=10000 cached=3000$' "$DOC")" 1
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

echo "== total and series still read a settled line =="
mk '* DISPATCH 2026-01-03T00:00:00Z · qa-reviewer · model opus · usage UNKNOWN'
run "$SID" --settle "$DOC" >/dev/null
ok "total sums the settled line"                  "$(bash "$AU" total "$DOC" --pr https://example.com/pr/1 >/dev/null 2>&1; grep -c '^\* TOTAL .* rounds=1 · usage tokens=121 tools=2 ms=10000 ' "$DOC")" 1

echo "== tokens, never money =="
# No `\$[0-9]` arm here: this script reads its own positional parameters, and a pattern that
# matches `$1` would be measuring bash, not money.
money='USD\|EUR\|price\|pricing\|per million\|per 1M\|cents'
ok "no price, no currency, no pricing source"     "$(grep -ic "$money" "$SU" | tr -d ' ')" 0
ok "agent-usage.sh still names no transcript path" "$(grep -c 'claude/projects\|\.jsonl' "$AU" | tr -d ' ')" 0

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
