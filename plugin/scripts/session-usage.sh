#!/usr/bin/env bash
# session-usage.sh — what ONE detached session cost, read from that session's own
# transcript: the numbers `agent-usage.sh dispatch` has had to record as `usage UNKNOWN`
# since role agents became `claude --bg` sessions and stopped handing a notification back.
#
#   session-usage.sh <session-id> [--projects-dir <dir>] [--settle <task-doc>]
#
# Prints `usage tokens=N tools=N ms=N cached=N`, or `usage UNKNOWN` on ANY doubt — no
# transcript, two candidates, no usage record, a parse failure, no jq. Never a zero.
# `--settle` hands the numbers to `agent-usage.sh settle`, which fills that task's last
# UNKNOWN dispatch line; UNKNOWN settles nothing.
# Exit: 0 printed numbers (and settled, if asked) · 1 UNKNOWN · 2 cannot settle · 3 usage.
#
# tokens = fresh input + cache writes + output. cached = cache READS, kept apart: a
# re-read prefix is real load but not new work, and summing it in would let one long
# session look like a hundred short ones.
# ONE MESSAGE, ONE COUNT. A transcript writes an assistant message as several lines, one
# per content block, each repeating the message's usage — measured at 2.2 lines per
# message. Summing lines doubles the figure, so usage is keyed on the message id.
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
  reduce (inputs | fromjson? | select(type == "object")) as $l
    ({u: {}, t: {}, a: null, z: null};
     (if ($l.timestamp | type) == "string"
        then (.a //= $l.timestamp) | .z = $l.timestamp else . end)
     | if $l.type == "assistant" and ($l.message.usage | type) == "object" and ($l.message.id | type) == "string"
         then .u[$l.message.id] = $l.message.usage
              | reduce ($l.message.content[]? | select(.type == "tool_use") | .id) as $i (.; .t[$i] = 1)
         else . end)
  | if (.u | length) == 0 or .a == null then "UNKNOWN"
    else "\(n("input_tokens") + n("cache_creation_input_tokens") + n("output_tokens")) \(.t | length) \(((.z | secs) - (.a | secs)) * 1000) \(n("cache_read_input_tokens"))"
    end
' "$1" 2>/dev/null)" || unknown
set -- $nums
[ "$#" -eq 4 ] || unknown
for v in "$@"; do case "$v" in ''|*[!0-9]*) unknown ;; esac; done

printf 'usage tokens=%s tools=%s ms=%s cached=%s\n' "$1" "$2" "$3" "$4"
[ -z "$settle" ] && exit 0
bash "$HERE/agent-usage.sh" settle "$settle" --tokens "$1" --tools "$2" --duration-ms "$3" --cached "$4" || exit 2
