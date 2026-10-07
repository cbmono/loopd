#!/usr/bin/env bash
# session-usage.sh — what ONE detached session cost, read from that session's own
# transcript: the numbers `agent-usage.sh dispatch` has had to record as `usage UNKNOWN`
# since role agents became `claude --bg` sessions and stopped handing a notification back.
#
#   session-usage.sh <session-id> [--projects-dir <dir>] [--settle <task-doc>]
#
# Prints `usage tokens=N tools=N ms=N cached=N errors=N by=Bash:152,Agent:30,…`, or
# `usage UNKNOWN` on ANY doubt — no transcript, two candidates, no usage record, a parse
# failure, no jq. Never a zero. `--settle` hands the numbers to `agent-usage.sh settle`,
# which fills that task's last UNKNOWN dispatch line; UNKNOWN settles nothing.
# Exit: 0 printed numbers (and settled, if asked) · 1 UNKNOWN · 2 cannot settle · 3 usage.
#
# tokens = fresh input + cache writes + output. cached = cache READS, kept apart: a
# re-read prefix is real load but not new work, and summing it in would let one long
# session look like a hundred short ones. tools = distinct tool_use blocks; by = the top
# five tool names by count (desc, ties by name; `-` when there were none), so it sums to
# tools whenever five names cover them; errors = distinct tool_result blocks flagged
# is_error (7 of 236 on a healthy tick, 2026-10-07). The first four keys keep their place
# — `agent-usage.sh total` matches `tokens= tools= ms=` as one run — and the new two append.
# ONE MESSAGE, ONE COUNT. A transcript writes an assistant message as several lines, one
# per content block, each repeating the message's usage — measured at 2.2 lines per
# message. Summing lines doubles the figure, so usage is keyed on the message id and a
# tool call on its own id.
# This is the one file that knows where a transcript lives. It is a Claude Code internal,
# so everything here fails to UNKNOWN rather than guessing at a changed format.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
UNKNOWN='usage UNKNOWN'

usage() { sed -n '2,12p' "$0" >&2; exit 3; }
unknown() { printf '%s\n' "$UNKNOWN"; exit 1; }

id="${1:-}"; [ -n "$id" ] || usage; shift
dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"; settle=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --projects-dir) dir="$2" ;;
    --settle)       settle="$2" ;;
    *) usage ;;
  esac
  shift 2
done
# The id is globbed below, so it may hold only what a session id holds.
case "$id" in *[!0-9a-f-]*) usage ;; esac
[ "${#id}" -ge 8 ] || usage

command -v jq >/dev/null 2>&1 || unknown
shopt -s nullglob
set -- "$dir"/*/"$id"*.jsonl
[ "$#" -eq 1 ] || unknown

nums="$(jq -Rrn '
  def n(k): [.u[] | .[k] // 0] | add // 0;
  def secs: sub("\\.[0-9]+"; "") | fromdateiso8601;
  def by: [.t[]] | group_by(.) | map({k: .[0], n: length}) | sort_by([-.n, .k]) | .[:5]
          | if length == 0 then "-" else map("\(.k):\(.n)") | join(",") end;
  reduce (inputs | fromjson? | select(type == "object")) as $l
    ({u: {}, t: {}, e: {}, a: null, z: null};
     (if ($l.timestamp | type) == "string"
        then (.a //= $l.timestamp) | .z = $l.timestamp else . end)
     | if $l.type == "assistant" and ($l.message.usage | type) == "object" and ($l.message.id | type) == "string"
         then .u[$l.message.id] = $l.message.usage
              | reduce ($l.message.content[]? | select(.type == "tool_use")) as $b (.; .t[$b.id] = $b.name)
         else . end
     | reduce ($l.message.content[]? | select(.type == "tool_result" and .is_error == true) | .tool_use_id) as $i (.; .e[$i] = 1))
  | if (.u | length) == 0 or .a == null or ([.t[] | type == "string"] | all | not) then "UNKNOWN"
    else "\(n("input_tokens") + n("cache_creation_input_tokens") + n("output_tokens")) \(.t | length) \(((.z | secs) - (.a | secs)) * 1000) \(n("cache_read_input_tokens")) \(.e | length) \(by)"
    end
' "$1" 2>/dev/null)" || unknown
set -- $nums
[ "$#" -eq 6 ] || unknown
for v in "$1" "$2" "$3" "$4" "$5"; do case "$v" in ''|*[!0-9]*) unknown ;; esac; done
# A name outside the grammar would split the one line, so it is doubt, not a sixth field.
by_re='^(-|[A-Za-z0-9_.-]+:[0-9]+(,[A-Za-z0-9_.-]+:[0-9]+){0,4})$'
[[ $6 =~ $by_re ]] || unknown

printf 'usage tokens=%s tools=%s ms=%s cached=%s errors=%s by=%s\n' "$1" "$2" "$3" "$4" "$5" "$6"
[ -z "$settle" ] && exit 0
bash "$HERE/agent-usage.sh" settle "$settle" --tokens "$1" --tools "$2" --duration-ms "$3" --cached "$4" --errors "$5" --by "$6" || exit 2
