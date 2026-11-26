#!/usr/bin/env bash
# metrics.sh — derive .loopd/METRICS.json from records the bundle already keeps: the tick
# ledger, task docs' DISPATCH/TOTAL lines (agent-usage.sh), .loopd/citations/ and the
# machine's usage store. Usage: metrics.sh <bundle-root>. Written only where SNAPSHOT.json
# exists and `board` is not false; no gh, no git, no network. Atomic: a failed run keeps the
# previous file. METRICS_NOW pins generated_at. Schema: docs/metrics.md.
# Exit: 0 written or switched off · 2 cannot compute (jq missing, unreadable input) · 3 usage.
# Reasoning: loopd-usage-metrics/task-001.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 2

die() { echo "metrics: $2" >&2; exit "$1"; }
[ "$#" -eq 1 ] || die 3 "usage: metrics.sh <bundle-root>"
root="$1"
[ -f "$root/instance.config.json" ] && [ -d "$root/$AB_DIR" ] || die 3 "not a bundle root: $root"
[ -f "$root/$AB_SNAPSHOT" ] || exit 0
command -v jq >/dev/null 2>&1 || die 2 "jq not found — METRICS.json not written, previous file kept"
[ "$(jq -r '.board == false' "$root/instance.config.json" 2>/dev/null)" = true ] && exit 0

now="${METRICS_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
out="$root/$AB_METRICS"
work="$(mktemp -d "${TMPDIR:-/tmp}/metrics.XXXXXX")" || die 2 "mktemp failed"
trap 'rm -rf "$work"' EXIT
rec="$work/rec.ndjson"
shopt -s nullglob
export LC_ALL=C

AWK_LIB='
function san(s) { gsub(/[^A-Za-z0-9._\/:@+-]/, "_", s); return s }
function q(s) { return s == "" ? "null" : "\"" san(s) "\"" }
function nz(s) { return s == "" ? "null" : s + 0 }
function val(s, k,   r) {
  if (match(s, " " k "=[0-9]+")) { r = substr(s, RSTART, RLENGTH); sub(/^ [a-z]+=/, "", r); return r }
  return ""
}
function measured(s) { return val(s, "tokens") != "" && val(s, "tools") != "" && val(s, "ms") != "" }
'

bash "$HERE/agent-usage.sh" series --instance "$root" > "$work/series.txt" \
  || die 2 "agent-usage.sh series failed — METRICS.json not written, previous file kept"
awk "$AWK_LIB"'
  / · ticks / {
    split($0, p, " · "); m = p[1]
    t = p[2]; sub(/^ticks /, "", t); tn = t + 0; sub(/^[0-9]+ \(/, "", t); tm = t + 0
    d = p[3]; sub(/^dispatches /, "", d); dn = d + 0; sub(/^[0-9]+ \(/, "", d); dm = d + 0
    printf "{\"k\":\"s\",\"month\":%s,\"ticks\":%d,\"ticks_measured\":%d,\"tick_tokens\":%s,\"dispatches\":%d,\"dispatches_measured\":%d,\"dispatch_tokens\":%s}\n",
      q(m), tn, tm, nz(val(" " p[2], "tokens")), dn, dm, nz(val(" " p[3], "tokens"))
  }' "$work/series.txt" > "$rec" || die 2 "cannot read the series"

awk "$AWK_LIB"'
  /^\* TICK [0-9][0-9][0-9][0-9]-[0-9][0-9]-/ {
    o = index($0, " open: "); c = index($0, " close: ")
    if (o > 0 && (c == 0 || c > o)) next
    rest = $0; sub(/^\* TICK [^ ]+ /, "", rest); sub(/^by [^ ]+ /, "", rest)
    idle = (rest ~ /^idle/) ? "true" : "false"
    printf "{\"k\":\"tick\",\"month\":%s,\"idle\":%s,\"tokens\":%s}\n", q(substr($3, 1, 7)), idle,
      measured($0) ? val($0, "tokens") : "null"
    next
  }
  /^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] .* Project (added|closed|re-closed): / {
    ev = ($0 ~ /Project added: /) ? "added" : "closed"
    s = $0; sub(/.* Project (added|closed|re-closed): /, "", s); sub(/[ `].*/, "", s)
    printf "{\"k\":\"proj\",\"slug\":%s,\"event\":\"%s\",\"date\":%s}\n", q(s), ev, q($2)
  }' "$root/$AB_LEDGER" >> "$rec" || die 2 "cannot read $AB_LEDGER"

tasks=("$root"/projects/*/tasks/*.md)
if [ "${#tasks[@]}" -gt 0 ]; then
  awk "$AWK_LIB"'
    function urls(s) {
      while (match(s, /https?:\/\/[^ ",\]]+\/pull\/[0-9]+/)) { prf[++npf] = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH) }
    }
    function flush(   i, prs, pf) {
      if (key == "") return
      prs = ""; for (i = 1; i <= npr; i++) prs = prs (i > 1 ? "," : "") q(pr[i])
      pf = ""; for (i = 1; i <= npf; i++) pf = pf (i > 1 ? "," : "") q(prf[i])
      printf "{\"k\":\"t\",\"key\":%s,\"project\":%s,\"status\":%s,\"created\":%s,\"promoted\":%s,\"first_dispatch\":%s,\"total_at\":%s,\"dispatches\":%d,\"dispatches_measured\":%d,\"dispatch_tokens\":%s,\"working_ms\":%s,\"rounds\":%s,\"total_tokens\":%s,\"prs\":[%s],\"pr_field\":[%s],\"stall_count\":%d,\"open_questions\":%d}\n",
        q(key), q(proj), q(status), q(created), q(promoted), q(fd), q(tat), nd, ndm,
        (ndm > 0 ? dtok : "null"), ((nd > 0 && ndm == nd) ? dms : "null"),
        nz(rounds), nz(ttok), prs, pf, stall, oq
    }
    FNR == 1 {
      flush()
      n = split(FILENAME, seg, "/"); key = seg[n - 2] "/" seg[n]; sub(/\.md$/, "", key); proj = seg[n - 2]
      fm = 0; list = ""; status = created = promoted = fd = tat = rounds = ttok = ""
      nd = ndm = dtok = dms = stall = oq = npr = npf = 0
    }
    fm < 2 && /^---[[:space:]]*$/ { fm++; next }
    fm == 1 {
      if ($0 ~ /^[A-Za-z_]+:/) {
        list = ""; f = $1; sub(/:$/, "", f); v = $0; sub(/^[A-Za-z_]+:[[:space:]]*/, "", v)
        if (f == "status") status = v
        else if (f == "timestamp") created = v
        else if (f == "stall_count") stall = v + 0
        else if (f == "pr") { list = f; urls(v) }
        else if (f == "open_questions" || f == "answered_questions") {
          if (v == "") list = f
          else if (v !~ /^\[[[:space:]]*\]$/ && f == "open_questions") oq = 1 + gsub(/", "/, "&", v)
        }
      } else if (list != "" && $0 ~ /^[[:space:]]*- /) {
        if (list == "pr") urls($0)
        else if (list == "open_questions") oq++
        else if (match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:]+Z by /))
          printf "{\"k\":\"a\",\"month\":%s}\n", q(substr($0, RSTART, 7))
      }
      next
    }
    /^\* promoted [0-9][0-9][0-9][0-9]-/ && promoted == "" { promoted = $3 }
    /^\* DISPATCH [0-9][0-9][0-9][0-9]-/ {
      nd++; if (fd == "" || $3 < fd) fd = $3
      split($0, p, " · "); role = p[2]; model = p[3]; sub(/^model /, "", model)
      t = "null"; ms = "null"
      if (measured($0)) { ndm++; t = val($0, "tokens"); ms = val($0, "ms"); dtok += t; dms += ms }
      printf "{\"k\":\"d\",\"month\":%s,\"role\":%s,\"model\":%s,\"tokens\":%s,\"ms\":%s}\n",
        q(substr($3, 1, 7)), q(role), q(model), t, ms
    }
    /^\* TOTAL [0-9][0-9][0-9][0-9]-/ && tat == "" {
      tat = $3; r = $0; sub(/.* rounds=/, "", r); rounds = r + 0
      if (measured($0)) ttok = val($0, "tokens")
      for (i = 1; i <= NF; i++) if ($i ~ /^https?:\/\/[^ ]+\/pull\/[0-9]+$/) pr[++npr] = $i
    }
    END { flush() }' "${tasks[@]}" >> "$rec" || die 2 "cannot read the task documents"
fi

cites=("$root/$AB_DIR"/citations/*.txt)
if [ "${#cites[@]}" -gt 0 ]; then
  awk "$AWK_LIB"'
    function flush() { if (src != "") printf "{\"k\":\"c\",\"source\":%s,\"month\":%s,\"kept\":%d}\n", q(src), q(month), kept }
    FNR == 1 { flush(); n = split(FILENAME, seg, "/"); src = seg[n]; sub(/\.txt$/, "", src); kept = 0; month = "" }
    /^recorded: / { month = substr($2, 1, 7) }
    /^KEPT / { kept++ }
    END { flush() }' "${cites[@]}" >> "$rec" || die 2 "cannot read $AB_DIR/citations"
fi

stores=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/store/loopd_*.json)
if [ "${#stores[@]}" -gt 0 ]; then
  jq -c '[to_entries[] | select((.key | startswith("loopd.usage.")) and (.key | endswith(".ended") | not))
          | .value | select(type == "object" and ([.input, .cacheWrite, .output] | all(type == "number")))]
         | {k: "store", sessions: length, tokens: (map(.input + .cacheWrite + .output) | add // 0)}' \
    "${stores[@]}" >> "$rec" 2>/dev/null || echo '{"k":"store","sessions":null,"tokens":null}' >> "$rec"
fi

{ printf '{"k":"holds","names":['
  sep=""; for h in "$root/$AB_MERGE_HOLDS"/*; do printf '%s"%s"' "$sep" "$(basename "$h" | tr -cd 'A-Za-z0-9._-')"; sep=,; done
  printf ']}\n'; } >> "$rec"

read -r -d '' PROG <<'JQ'
def recs(k): [$r[] | select(.k == k)];
def epoch: if . == null then null elif test("^[0-9-]+$") then (. + "T00:00:00Z" | fromdateiso8601) else (try fromdateiso8601 catch null) end;
def r1: . * 10 | round / 10;
def hours(a; b): if a == null or b == null then null else ((b - a) / 3600 | r1) end;
def total: if length == 0 then null else add end;
def ratio(a; b): if a == null or b == null or b == 0 then null else (a / b * 1000 | round / 1000) end;
def mean: if length == 0 then null else (add / length | r1) end;
def tok: if . == null then "?" elif . >= 1000000 then "\(. / 100000 | round / 10)M" elif . >= 1000 then "\(. / 1000 | round)k" else tostring end;
def pct: if . == null then "?" else "\(. * 100 | round)%" end;
def none: {source: "none"};
def tally(f): group_by(f) | map({key: (.[0] | f // "unset"), value: {dispatches: length,
  measured: (map(select(.tokens != null)) | length), tokens: (map(.tokens // empty) | total)}}) | from_entries;
def prsource: split("/") | "\(.[-3])-pr-\(.[-1])";

recs("s") as $s | recs("tick") as $ticks | recs("t") as $tasks | recs("d") as $disp
| recs("c") as $cites | recs("a") as $ans | recs("proj") as $proj | recs("store") as $store
| (recs("holds")[0].names // []) as $marks
| ($cites | map({key: .source, value: .kept}) | from_entries) as $C
| (if ($s | map(.ticks_measured) | add // 0) == 0 then null else ($s | map(.tick_tokens // 0) | add) end) as $sup
| (if ($s | map(.dispatches_measured) | add // 0) == 0 then null else ($s | map(.dispatch_tokens // 0) | add) end) as $bg
| ($tasks | map(
    (.created | epoch) as $c | (.promoted | epoch) as $p | (.first_dispatch | epoch) as $f | (.total_at | epoch) as $z
    | (if .working_ms == null then null else (.working_ms / 3600000 | r1) end) as $w
    | ([(.key | split("/")[1]) + ".result"] + (.prs | map(prsource)) | map($C[.] // empty)) as $kept
    | {key: .key, value: {project, status, created, promoted, first_dispatch, reflected: .total_at,
        dispatches, dispatches_measured,
        tokens: (.total_tokens // .dispatch_tokens),
        tokens_from: (if .total_tokens != null then "total" elif .dispatch_tokens != null then "dispatch" else null end),
        rounds, fix_rounds: (if .rounds == null then null else ([.rounds - 1, 0] | max) end),
        merged_prs: (if .total_at == null then null else (.prs | length) end),
        draft_hours: hours($c; $p), queued_hours: hours($p; $f), in_flight_hours: hours($f; $z),
        working_hours: $w,
        waiting_hours: (if $c == null or $z == null or $w == null then null else ([hours($c; $z) - $w, 0] | max | r1) end),
        pr_opened: none, pr_merged: none,
        stall_count, open_questions,
        cited: (if ($kept | length) == 0 then null else ($kept | add > 0) end)}}) | from_entries) as $T
| ($T | to_entries | map(.value)) as $tv
| ($tv | map(select(.reflected != null))) as $done
| ($done | map(select(.tokens_from == "total"))) as $totals
| ($proj | group_by(.slug) | map({key: .[0].slug, value: {
    added: (map(select(.event == "added") | .date) | min),
    closed: (map(select(.event == "closed") | .date) | max)}}) | from_entries) as $L
| ((($L | keys) + ($tv | map(.project))) | unique | map(. as $k
    | ($tv | map(select(.project == $k))) as $pt | ($L[$k] // {}) as $l
    | {key: $k, value: {state: (if $l.closed != null then "closed" else "live" end),
        added: $l.added, closed: $l.closed,
        open_days: (if $l.added == null or $l.closed == null then null else (hours($l.added | epoch; $l.closed | epoch) / 24 | r1) end),
        tasks: ($pt | length), tasks_reflected: ($pt | map(select(.reflected != null)) | length),
        dispatches: ($pt | map(.dispatches) | add // 0),
        tokens: ($pt | map(.tokens // empty) | total),
        merged_prs: ($pt | map(.merged_prs // empty) | total)}}) | from_entries) as $P
| ($ticks | map(select(.idle))) as $idle
| ($idle | map(select(.tokens != null))) as $idlem
| ($tasks | map(select(.status != "done" and .status != "cancelled"))) as $live
| {owner: {tasks: ($live | map(select(.open_questions > 0 or .status == "blocked")) | length)},
   merge_gate: {holds: ($live | map(.pr_field[] | split("/") | "\(.[-4])_\(.[-3])_\(.[-1])") | unique
     | map(select(. as $n | $marks | index([$n]))) | length)},
   stalled_agent: {tasks: ($live | map(select(.stall_count > 0)) | length), rounds: ($live | map(.stall_count) | add // 0)},
   classifier_block: none, usage_limit: none, ci_flake: none} as $causes
| ([{k: "owner", n: $causes.owner.tasks}, {k: "merge_gate", n: $causes.merge_gate.holds},
    {k: "stalled_agent", n: $causes.stalled_agent.tasks}] | max_by(.n)) as $top
| ($totals | map(.merged_prs) | add // 0) as $tprs
| ($totals | map(.tokens) | total) as $ttok
| (if $tprs == 0 then null else ($ttok / $tprs | round) end) as $perpr
| ($done | map(.fix_rounds // empty)) as $fix
| (ratio($bg; (if $bg == null or $sup == null then null else $bg + $sup end))) as $share
| (if ($store | length) == 0 then {sessions: null, tokens: null}
   else {sessions: ($store | map(.sessions) | if any(. == null) then null else add end),
         tokens: ($store | map(.tokens) | if any(. == null) then null else add end)} end) as $main
| def grp($v): $done | map(select(.cited == $v)) | {tasks: length, mean_tokens: (map(.tokens // empty) | mean),
    mean_rounds: (map(.rounds // empty) | mean), mean_in_flight_hours: (map(.in_flight_hours // empty) | mean)};
  (($s | map(.month)) + ($ticks | map(.month)) + ($ans | map(.month)) + ($cites | map(.month))
   + ($done | map(.reflected[0:7]))) | map(select(. != null)) | unique as $months
| {
  schema_version: 1,
  generated_at: $now,
  headline: {
    delegation_share: (if $share == null then "?" else "\($share | pct) role agents" end),
    tokens_per_merged_pr: ($perpr | tok),
    idle_tick_spend: (if ($idle | length) == 0 then "0 idle ticks"
      elif ($idlem | length) == 0 then "? (\($idle | length) idle ticks, none measured)"
      else "\($idlem | map(.tokens) | add | tok) over \($idlem | length) of \($idle | length) idle ticks" end),
    top_block_cause: (if $top.n == 0 then "none now" else "\($top.k) · \($top.n)" end),
    self_merge_rate: "—"},
  delegation: {source: "ledger+dispatch", stale: false, unit: "tokens",
    role_agent_tokens: $bg, supervision_tokens: $sup, share_role_agents: $share,
    by_role: ($disp | tally(.role)), by_model: ($disp | tally(.model)),
    main_session: ({label: "unattributed (machine-wide)"} + $main)},
  time: {source: "task docs+ledger", stale: false, unit: "hours",
    tasks_reflected: ($done | length),
    mean_draft_hours: ($done | map(.draft_hours // empty) | mean),
    mean_queued_hours: ($done | map(.queued_hours // empty) | mean),
    mean_in_flight_hours: ($done | map(.in_flight_hours // empty) | mean),
    mean_working_hours: ($done | map(.working_hours // empty) | mean),
    mean_waiting_hours: ($done | map(.waiting_hours // empty) | mean),
    projects_closed: ($P | map(select(.state == "closed")) | length),
    mean_project_open_days: ($P | map(.open_days // empty) | mean),
    pr_open_to_merge_hours: none},
  tokens: {source: "ledger+total", stale: false, unit: "tokens",
    supervision: $sup, role_agents: $bg,
    supervision_ticks: ($s | map(.ticks) | add // 0), supervision_ticks_measured: ($s | map(.ticks_measured) | add // 0),
    merged_prs: {totals: ($totals | length), prs: $tprs, tokens: $ttok, per_pr: $perpr,
      fix_rounds: ($fix | total), fix_rounds_per_pr: (if ($done | length) == 0 then null else ($fix | add // 0) / ($done | length) | r1 end)}},
  idle_tick_spend: {source: "ledger", stale: false, unit: "tokens",
    ticks: ($ticks | length), idle_ticks: ($idle | length), idle_share: ratio($idle | length; $ticks | length),
    measured: ($idlem | length), tokens_measured: ($idlem | map(.tokens) | total),
    unmeasured_share: (if ($idle | length) == 0 then null else ratio(($idle | length) - ($idlem | length); $idle | length) end)},
  blocked_by_cause: {source: "task docs+merge holds", stale: false, unit: "count now",
    causes: $causes, top: (if $top.n == 0 then null else $top.k end), hours: none},
  owner_response: {source: "answered_questions", stale: false,
    answers: ($ans | length), needs_you_to_action_hours: none, ready_pr_to_merge_hours: none},
  self_merge: {source: "none", stale: false},
  quality: {source: "none", stale: false},
  kb_efficiency: {source: "citations+total", stale: false, label: "estimate",
    citation_files: ($cites | length), sources_citing: ($cites | map(select(.kept > 0)) | length),
    pr_records: ($cites | map(select(.source | test("-pr-[0-9]+$"))) | length),
    cited: grp(true), not_cited: grp(false)},
  tasks: $T,
  projects: $P,
  periods: ($months | map(. as $m | ($s | map(select(.month == $m)) | .[0] // {}) as $sm
    | {key: $m, value: {
      ticks: ($sm.ticks // 0), ticks_measured: ($sm.ticks_measured // 0), tick_tokens: $sm.tick_tokens,
      dispatches: ($sm.dispatches // 0), dispatches_measured: ($sm.dispatches_measured // 0), dispatch_tokens: $sm.dispatch_tokens,
      idle_ticks: ($idle | map(select(.month == $m)) | length),
      idle_measured: ($idlem | map(select(.month == $m)) | length),
      merged_prs: ($done | map(select(.reflected[0:7] == $m) | .merged_prs) | add // 0),
      answers: ($ans | map(select(.month == $m)) | length),
      citations: ($cites | map(select(.month == $m)) | length)}}) | from_entries)
}
JQ

tmp="$(mktemp "$root/$AB_DIR/.METRICS.json.XXXXXX")" || die 2 "cannot write under $root/$AB_DIR"
if ! jq -n --slurpfile r "$rec" --arg now "$now" "$PROG" > "$tmp" 2>"$work/err" \
   || ! jq -e '.schema_version' "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; die 2 "could not compute ($(head -c 200 "$work/err")) — previous file kept"
fi
mv "$tmp" "$out" || { rm -f "$tmp"; die 2 "cannot replace $out — previous file kept"; }
