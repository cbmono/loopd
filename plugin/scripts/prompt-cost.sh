#!/usr/bin/env bash
# prompt-cost.sh — tokens per assistant turn, per tick step and per dispatch role, read from
# Claude Code session transcripts. Prints counts and names only, never message text.
#
#   prompt-cost.sh [--projects-dir DIR] [--since ISO] [--limit N] [--kind tick|dispatch] [--sessions]
#
# A tick is a `<plugin>:project-manager` session whose brief carries a tick id; its turns go
# to the plugin/tick-steps/ file last read before the turn, `core` before any. A dispatch is
# any other `<plugin>:<role>` session, bucketed by role. Subagent turns bucket as `<x>+sub`.
# Exit: 0 printed · 1 nothing measurable · 3 usage. Reasoning: leaner-prompts/task-001.
set -uo pipefail

usage() { sed -n '2,10p' "$0" >&2; exit 3; }
dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"; since=""; limit=""; kind=""; sessions=no
while [ $# -gt 0 ]; do
  case "$1" in
    --projects-dir|--since|--limit|--kind) [ $# -ge 2 ] || usage ;;
  esac
  case "$1" in
    --projects-dir) dir="$2"; shift 2 ;;
    --since) since="$2"; shift 2 ;;
    --limit) limit="$2"; shift 2 ;;
    --kind) kind="$2"; shift 2 ;;
    --sessions) sessions=yes; shift ;;
    *) usage ;;
  esac
done
case "$limit" in ''|*[!0-9]*) [ -z "$limit" ] || usage ;; esac
case "$kind" in ''|tick|dispatch) ;; *) usage ;; esac
[ -d "$dir" ] || usage
command -v jq >/dev/null 2>&1 || { echo "prompt-cost: jq is required" >&2; exit 1; }

# One row per assistant message: kind role bucket first-timestamp input output cread cwrite.
# Usage is keyed on the message id (a message is written once per content block). The
# message that issues a step Read stays in the bucket it was composed in; the next one
# takes the step.
rows() { jq -Rrn --arg f "$1" '
  def step: (.message.content[]? | select(.type == "tool_use" and .name == "Read")
             | .input.file_path? | strings | capture("/tick-steps/(?<s>step-[A-Za-z0-9-]+)\\.md$") | .s);
  reduce (inputs | fromjson? | select(type == "object")) as $l
    ({role: null, tick: false, cur: "core", next: "core", seen: {}, out: [], t0: null};
     if .role == null and $l.type == "agent-setting" and ($l.agentSetting | type) == "string"
       then .role = ($l.agentSetting | split(":") | last) else . end
     | if $l.type == "user" and ($l.message.content | type) == "string" and ($l.message.content | test("Tick id: `tick-"))
       then .tick = true else . end
     | if $l.type == "assistant" and ($l.message.id | type) == "string" and ($l.message.usage | type) == "object"
       then (if .seen[$l.message.id] then . else
               .cur = .next | .seen[$l.message.id] = true
               | .t0 = (.t0 // $l.timestamp)
               | .out += [{id: $l.message.id, b: (if $l.isSidechain == true then "+sub" else "" end), cur: .cur,
                           u: $l.message.usage, ts: $l.timestamp}] end)
            | (first($l | step) // null) as $s | if $s then .next = $s else . end
       else . end)
  | select(.role != null and (.out | length) > 0)
  | (if .role == "project-manager" and .tick then "tick" else "dispatch" end) as $k
  | .role as $r | .t0 as $t0
  | .out[] | "\($k)\t\($r)\t\(if $k == "tick" then .cur else $r end)\(.b)\t\($t0)\t\($f)\t\(.u.input_tokens // 0)\t\(.u.output_tokens // 0)\t\(.u.cache_read_input_tokens // 0)\t\(.u.cache_creation_input_tokens // 0)"
' "$1" 2>/dev/null; }

all="$(for f in "$dir"/*/*.jsonl; do [ -f "$f" ] || continue; rows "$f"; done)"
[ -n "$all" ] || { echo "prompt-cost: no tick or dispatch transcript under $dir" >&2; exit 1; }

printf '%s\n' "$all" | awk -F'\t' -v since="$since" -v limit="$limit" -v kind="$kind" -v sessions="$sessions" '
  { if (since != "" && $4 < since) next; if (kind != "" && $1 != kind) next; n++; L[n] = $0; t0[$5] = $4; k0[$5] = $1 }
  END {
    if (limit != "") { # keep the N most recent sessions of each kind, by first turn
      for (f in t0) keys[++m] = t0[f] "\t" f
      cnt_t = 0; cnt_d = 0
      for (i = m; i >= 1; i--) for (j = 1; j < i; j++) if (keys[j] < keys[j+1]) { x = keys[j]; keys[j] = keys[j+1]; keys[j+1] = x }
      for (i = 1; i <= m; i++) { split(keys[i], kv, "\t"); f = kv[2]
        c = (k0[f] == "tick") ? ++cnt_t : ++cnt_d; if (c <= limit) keep[f] = 1 }
    }
    for (i = 1; i <= n; i++) { split(L[i], a, "\t"); f = a[5]
      if (limit != "" && !(f in keep)) continue
      key = a[1] "\t" a[3]; S[key, f] = 1; T[key]++; I[key] += a[6]; O[key] += a[7]; R[key] += a[8]; W[key] += a[9]
      tot = a[1] "\tall" ((a[3] ~ /\+sub$/) ? "+sub" : ""); S[tot, f] = 1; T[tot]++; I[tot] += a[6]; O[tot] += a[7]; R[tot] += a[8]; W[tot] += a[9]
      if (a[3] ~ /\+sub$/) continue
      sk = a[1] "\t" f; ST[sk]++; SI[sk] += a[6]; SO[sk] += a[7]; SR[sk] += a[8]; SW[sk] += a[9]; SB[sk] = a[1] "\t" substr(f, length(f) - 41, 36)
      if (!(key in order)) order[key] = ++no; if (!(tot in order)) order[tot] = ++no
    }
    if (no == 0) { print "prompt-cost: no session in the window" > "/dev/stderr"; exit 1 }
    for (k in S) { split(k, p, SUBSEP); NS[p[1]]++ }
    printf "%-9s %-28s %8s %7s %10s %9s %11s %11s %8s %8s %10s %10s\n", "kind", "bucket", "sessions", "turns", "input", "output", "cache_read", "cache_write", "in/turn", "out/turn", "cread/turn", "cwrite/turn"
    for (k in order) { split(k, p, "\t"); row[p[1] "\t" (p[2] == "all" ? "~" : p[2])] = k }
    m = 0; for (r in row) ks[++m] = r
    for (i = m; i >= 1; i--) for (j = 1; j < i; j++) if (ks[j] > ks[j+1]) { x = ks[j]; ks[j] = ks[j+1]; ks[j+1] = x }
    for (i = 1; i <= m; i++) { k = row[ks[i]]; split(k, p, "\t")
      printf "%-9s %-28s %8d %7d %10d %9d %11d %11d %8d %8d %10d %10d\n", p[1], p[2], NS[k], T[k], I[k], O[k], R[k], W[k], I[k]/T[k] + .5, O[k]/T[k] + .5, R[k]/T[k] + .5, W[k]/T[k] + .5 }
    if (sessions == "yes") {
      print ""; printf "main thread only:\n%-9s %-36s %7s %10s %9s %11s %11s %10s\n", "kind", "session", "turns", "input", "output", "cache_read", "cache_write", "cread/turn"
      m = 0; for (r in ST) ks[++m] = SB[r] "\t" r
      for (i = m; i >= 1; i--) for (j = 1; j < i; j++) if (ks[j] > ks[j+1]) { x = ks[j]; ks[j] = ks[j+1]; ks[j+1] = x }
      for (i = 1; i <= m; i++) { split(ks[i], p, "\t"); r = p[3] "\t" p[4]
        printf "%-9s %-36s %7d %10d %9d %11d %11d %10d\n", p[1], p[2], ST[r], SI[r], SO[r], SR[r], SW[r], SR[r]/ST[r] + .5 }
    }
  }'
