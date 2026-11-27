#!/usr/bin/env bash
# metrics-report.sh — print the /loopd:metrics report, as markdown, from .loopd/METRICS.json.
# Run from the bundle root. Usage: metrics-report.sh [--project <slug>] [--since <YYYY-MM[-DD]>].
# Read-only: reads METRICS.json, instance.config.json, the ledger and the hook's run state; no gh, no git, no write,
# and nothing recomputed — the figures are metrics.sh's (schema: docs/metrics.md).
# Exit: 0 printed, metrics off or not computed yet · 2 not a bundle root, no jq or config unreadable · 3 usage
# · 4 METRICS.json unreadable, truncated or of an unknown schema.
# Rules, thresholds and filter semantics: docs/metrics.md → "The report".
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 2

die() { echo "metrics-report: $2" >&2; exit "$1"; }
project=""; since=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) [ "$#" -ge 2 ] || die 3 "--project needs a slug"; project="$2"; shift 2 ;;
    --since) [ "$#" -ge 2 ] || die 3 "--since needs a date"; since="$2"; shift 2 ;;
    *) die 3 "usage: metrics-report.sh [--project <slug>] [--since <YYYY-MM|YYYY-MM-DD>]" ;;
  esac
done
case "$project" in
  '') ;;
  *[!a-z0-9._-]*|[!a-z0-9]*) die 3 "--project takes a project slug (a-z, 0-9, . _ -), got an invalid one" ;;
esac
if [ -n "$since" ]; then
  printf '%s\n' "$since" | grep -Eq '^[0-9]{4}-(0[1-9]|1[0-2])(-(0[1-9]|[12][0-9]|3[01]))?$' \
    || die 3 "--since takes a UTC date, YYYY-MM or YYYY-MM-DD"
  since="${since:0:7}"
fi

ab_is_bundle . && [ -d "$AB_DIR" ] || die 2 "run from a control-panel instance root (instance.config.json)"
command -v jq >/dev/null 2>&1 || die 2 "jq not found — the metrics report needs jq"
board="$(jq -r '.board == false' instance.config.json 2>/dev/null)" || die 2 "cannot parse instance.config.json"
F="$AB_METRICS"
if [ "$board" = true ]; then
  echo "Metrics are off: \"board\": false in instance.config.json. Remove the key (or set it true) to turn them on; the next tick that changes something writes $F."
  exit 0
fi
last="$(ab_last_full_tick "$AB_LEDGER")"
tried=""; failed=""
if [ ! -L "$AB_METRICS_RUN" ] && [ "$(cat "$AB_METRICS_RUN/attempt" 2>/dev/null)" = "${last:-none}" ]; then
  tried=yes
  failed="$(sed -n 's/^exit \([0-9]\{1,3\}\) close .*/\1/p' "$AB_METRICS_RUN/failed" 2>/dev/null | head -n 1)"
fi
if [ ! -e "$F" ]; then
  if [ -f "$AB_SNAPSHOT" ] && [ -n "$failed" ]; then
    echo "Metrics are not computed: no $F, and the run for the newest full tick failed (exit $failed). It is not retried on a session turn; the next full tick computes them."
  elif [ -f "$AB_SNAPSHOT" ] && [ -n "$tried" ]; then
    echo "Metrics are not computed: no $F, and the run for the newest full tick has already been made. The next full tick computes them."
  elif [ -f "$AB_SNAPSHOT" ]; then
    echo "Metrics are not computed yet: no $F. The next session turn on this bundle computes them, and so does the next tick that changes something."
  else
    echo "Metrics are off: no $AB_SNAPSHOT. They follow the board switch, \"board\" in instance.config.json (on unless false), and need that file."
  fi
  exit 0
fi
[ -f "$F" ] && [ -r "$F" ] || die 4 "$F is unreadable"
[ -s "$F" ] || die 4 "$F is empty — truncated; the next full tick rewrites it"
check="$(jq -r '
  def iso: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
  if type != "object" then "is not a JSON object"
  elif (.schema_version | IN(1, 2) | not) then "has an unknown schema_version \(.schema_version | tojson) (this report reads 1 and 2)"
  elif (.generated_at | iso | not) then "has no UTC generated_at"
  elif ([.headline, .delegation, .time, .tokens, .idle_tick_spend, .blocked_by_cause, .owner_response,
         .self_merge, .quality, .kb_efficiency, .tasks, .projects, .periods] | all(type == "object") | not)
    then "is missing a section of schema \(.schema_version)"
  else "ok" end' "$F" 2>/dev/null)" || die 4 "$F is truncated or not JSON; the next full tick rewrites it"
[ "$check" = ok ] || die 4 "$F ${check:-is truncated or not JSON}"
if [ -n "$project" ]; then
  jq -e --arg p "$project" '.projects | has($p)' "$F" >/dev/null 2>&1 \
    || die 3 "no project '$project' in $F — run without --project to list them"
fi

read -r -d '' PROG <<'JQ'
def stale(f): if f.stale == true then " (stale)" else "" end;
def clean: tostring | explode | map(select(. >= 32 and . != 127 and . != 124)) | implode;
def cut(n): if . == null then null else clean | if length > n then .[0:n - 1] + "…" else . end end;
def none: type == "object" and .source == "none";
def fig: if . == null then "? unknown" elif none then "— source: none" elif type == "object" then "? unknown" else clean end;
def tok: if type == "number" then (if . >= 1000000 then "\(. / 100000 | round / 10)M" elif . >= 1000 then "\(. / 1000 | round)k" else tostring end) else fig end;
def pct: if type == "number" then "\(. * 100 | round)%" else fig end;
def h: if type == "number" then "\(.)h" elif type == "object" and has("mean_hours") then (.mean_hours | h) + stale(.) else fig end;
def d: if type == "number" then "\(.)d" else fig end;
def row: "| " + (map(fig) | join(" | ")) + " |";
def head: (row), ("|" + (map("---|") | join("")));
def more(n; total; what): if total > n then ["", "… \(total - n) more \(what) not shown; narrow with --project or --since."] else [] end;

. as $m
| ($m.tasks | to_entries | map(.value + {key}) | map(select(($project == "" or .project == $project)
    and ($since == "" or ((.created // "") | tostring | .[0:7]) >= $since)))) as $tasks
| ($m.projects | to_entries | map(.value + {key}) | map(select($project == "" or .key == $project))) as $projects
| ($m.periods | to_entries | map(select($since == "" or .key >= $since)) | sort_by(.key)) as $months
| $m.delegation as $dl | $m.time as $t | $m.tokens as $tk | $m.idle_tick_spend as $it
| $m.blocked_by_cause as $b | $m.owner_response as $o | $m.kb_efficiency as $kb
| [
  {n: 1, m: "idle_tick_spend.idle_share", v: $it.idle_share, t: 0.5, ge: true, f: ($it.idle_share | pct),
   say: "Lengthen the `/loopd:dispatch` gap, or stop the loop between batches: half or more of the ticks found nothing to do."},
  {n: 2, m: "delegation.share_role_agents", v: $dl.share_role_agents, t: 0.5, ge: false, f: ($dl.share_role_agents | pct),
   say: "Shift work from supervision to role agents: PM ticks spend more tokens than the agents doing the work."},
  {n: 3, m: "tokens.merged_prs.fix_rounds_per_pr", v: $tk.merged_prs.fix_rounds_per_pr, t: 1, ge: true, f: ($tk.merged_prs.fix_rounds_per_pr | fig),
   say: "Tighten acceptance criteria before promoting: merged PRs average a fix round or more."},
  {n: 4, m: "blocked_by_cause.causes.owner.tasks", v: $b.causes.owner.tasks, t: 3, ge: true, f: ($b.causes.owner.tasks | fig),
   say: "Clear the owner queue with `/loopd:answer`: these tasks wait on you."},
  {n: 5, m: "blocked_by_cause.causes.stalled_agent.tasks", v: $b.causes.stalled_agent.tasks, t: 2, ge: true, f: ($b.causes.stalled_agent.tasks | fig),
   say: "Look at the stalled tasks before dispatching more: their agents ended without progress."},
  {n: 6, m: "time.mean_queued_hours", v: $t.mean_queued_hours, t: 24, ge: true, f: ($t.mean_queued_hours | h),
   say: "Dispatch sooner after promoting: promoted tasks wait a day or more for their first dispatch."},
  {n: 7, m: "kb_efficiency not_cited/cited mean_rounds",
   v: (if ($kb.cited.tasks // 0) >= 3 and ($kb.not_cited.tasks // 0) >= 3 and ($kb.cited.mean_rounds | type) == "number"
         and ($kb.not_cited.mean_rounds | type) == "number" and $kb.cited.mean_rounds > 0
       then ($kb.not_cited.mean_rounds / $kb.cited.mean_rounds * 100 | round / 100) else null end),
   t: 1.25, ge: true, f: "\($kb.not_cited.mean_rounds | fig) vs \($kb.cited.mean_rounds | fig) rounds, an estimate",
   say: "Cite Findings in more briefs: tasks that cited one needed fewer review rounds (an estimate, not time saved)."}
  ] as $rules
| ($rules | map(select((.v | type) == "number" and (if .ge then .v >= .t else .v < .t end))
    | .s = (if .ge then .v / .t elif .v <= 0 then 1000000 else .t / .v end))
  | sort_by(-.s, .n) | .[0:3]) as $fired
| "# loopd metrics",
  "",
  "Generated \($m.generated_at | clean) · schema \($m.schema_version) · project: \(if $project == "" then "all" else $project end) · since: \(if $since == "" then "all months" else $since end)",
  (if $stale != "" then "", "**Stale:** these figures were generated before the last full tick (\($stale | clean)). \(if $failed != "" then "The recompute for that tick failed (exit \($failed | clean)) and is not retried on a session turn; they refresh on the next tick that changes something."
       elif $tried != "" then "The recompute for that tick has already been made; they refresh on the next tick that changes something."
       else "The next session turn on this bundle recomputes them; PR figures refresh on the next tick that changes something." end)" else empty end),
  "",
  "## Headline",
  "",
  (["Delegation", "Tokens per merged PR", "Idle-tick spend", "Top block cause", "Self-merge rate"] | head),
  ([$m.headline | .delegation_share, .tokens_per_merged_pr, .idle_tick_spend, .top_block_cause, .self_merge_rate] | map(if type == "string" then cut(48) else . end) | row),
  "",
  "## Families (bundle-wide, all time — filters do not apply)",
  "",
  (["Family", "Figure", "Value"] | head),
  (["delegation" + stale($dl), "role-agent share of tokens", ($dl.share_role_agents | pct)] | row),
  (["delegation" + stale($dl), "role-agent / supervision tokens", "\($dl.role_agent_tokens | tok) / \($dl.supervision_tokens | tok)"] | row),
  (["delegation" + stale($dl), "main session, \($dl.main_session.label // "unattributed" | cut(40))", "\($dl.main_session.tokens | tok) tokens over \($dl.main_session.sessions | fig) sessions"] | row),
  (["time" + stale($t), "tasks reflected", ($t.tasks_reflected | fig)] | row),
  (["time" + stale($t), "mean draft / queued / in flight", "\($t.mean_draft_hours | h) / \($t.mean_queued_hours | h) / \($t.mean_in_flight_hours | h)"] | row),
  (["time" + stale($t), "mean working / waiting", "\($t.mean_working_hours | h) / \($t.mean_waiting_hours | h)"] | row),
  (["time" + stale($t), "projects closed, mean days open", "\($t.projects_closed | fig), \($t.mean_project_open_days | d)"] | row),
  (["time" + stale($t), "PR open to merge", ($t.pr_open_to_merge_hours | h)] | row),
  (["tokens" + stale($tk), "supervision / role agents", "\($tk.supervision | tok) / \($tk.role_agents | tok)"] | row),
  (["tokens" + stale($tk), "per merged PR", "\($tk.merged_prs.per_pr | tok) over \($tk.merged_prs.prs | fig) PRs"] | row),
  (["tokens" + stale($tk), "fix rounds per merged PR", ($tk.merged_prs.fix_rounds_per_pr | fig)] | row),
  (["idle-tick spend" + stale($it), "idle ticks", "\($it.idle_ticks | fig) of \($it.ticks | fig) (\($it.idle_share | pct))"] | row),
  (["idle-tick spend" + stale($it), "tokens measured", "\($it.tokens_measured | tok) over \($it.measured | fig) idle ticks; \($it.unmeasured_share | pct) unmeasured"] | row),
  (["owner response" + stale($o), "answers given", ($o.answers | fig)] | row),
  (["owner response" + stale($o), "Needs-you row to action", ($o.needs_you_to_action_hours | h)] | row),
  (["owner response" + stale($o), "ready PR to merge", ($o.ready_pr_to_merge_hours | h)] | row),
  (["self-merge" + stale($m.self_merge), "rate", (if $m.self_merge | none then $m.self_merge else ($m.self_merge.rate | pct) end | fig)] | row),
  (["quality" + stale($m.quality), "review findings and fix rounds", (if $m.quality | none then ($m.quality | fig) else "\($m.quality.cr_findings_per_pr | fig) findings / PR, \($m.quality.fix_rounds_per_pr | fig) fix rounds / PR, \($m.quality.first_round_merge_share | pct) merged in one round" end)] | row),
  "",
  "## By role",
  "",
  (["Role", "Dispatches", "Measured", "Tokens"] | head),
  ($dl.by_role | if type == "object" then to_entries | sort_by(-(.value.tokens // 0), .key) | .[0:10][]
     | [(.key | cut(40)), .value.dispatches, .value.measured, (.value.tokens | tok)] | row else empty end),
  (more(10; ($dl.by_role | if type == "object" then length else 0 end); "roles")[]),
  "",
  "## Blocked by cause\(stale($b)) — counted now; hours: \($b.hours | fig)",
  "",
  (["Cause", "Now"] | head),
  (["owner", "\($b.causes.owner.tasks | fig) tasks"] | row),
  (["merge gate", "\($b.causes.merge_gate.holds | fig) holds"] | row),
  (["stalled agent", "\($b.causes.stalled_agent.tasks | fig) tasks, \($b.causes.stalled_agent.rounds | fig) stall rounds"] | row),
  (["classifier block", ($b.causes.classifier_block | fig)] | row),
  (["usage limit", ($b.causes.usage_limit | fig)] | row),
  (["CI flake", ($b.causes.ci_flake | fig)] | row),
  "",
  "## KB efficiency\(stale($kb)) — an estimate, not measured time saved",
  "",
  (["Reflected tasks", "Tasks", "Mean tokens", "Mean rounds", "Mean in flight"] | head),
  ((["cited a Finding", $kb.cited], ["cited none", $kb.not_cited]) as [$lab, $g] | [$lab,
     $g.tasks, ($g.mean_tokens | tok), $g.mean_rounds, ($g.mean_in_flight_hours | h)] | row),
  "",
  "From \($kb.citation_files | fig) citation files, \($kb.pr_records | fig) of them per-PR records.",
  "",
  "## Projects",
  "",
  (["Project", "State", "Added", "Closed", "Open", "Tasks", "Reflected", "Dispatches", "Tokens", "Merged PRs"] | head),
  ($projects | sort_by(.added // "", .key) | reverse | .[0:25][]
     | [(.key | cut(40)), .state, .added, (.closed // "—"), (.open_days | d), .tasks, .tasks_reflected, .dispatches, (.tokens | tok), .merged_prs] | row),
  (if ($projects | length) == 0 then "| none in this selection |" else empty end),
  (more(25; $projects | length; "projects")[]),
  "",
  "## Tasks (newest first)",
  "",
  (["Task", "Status", "Created", "Tokens", "Rounds", "In flight", "Working", "Waiting", "Cited"] | head),
  ($tasks | sort_by(.created // "", .key) | reverse | .[0:25][]
     | [(.key | cut(60)), (.status | cut(20)), ((.created // null) | if type == "string" then .[0:10] else . end), (.tokens | tok), .rounds,
        (.in_flight_hours | h), (.working_hours | h), (.waiting_hours | h), .cited] | row),
  (if ($tasks | length) == 0 then "| none in this selection |" else empty end),
  (more(25; $tasks | length; "tasks")[]),
  "",
  "## Months\(if $project != "" then " (bundle-wide: METRICS.json keeps no per-project months)" else "" end)",
  "",
  (["Month", "Ticks", "Tick tokens", "Idle", "Dispatches", "Dispatch tokens", "Merged PRs", "Answers", "Citations"] | head),
  ($months | .[-24:][] | .value as $v
     | [.key, $v.ticks, ($v.tick_tokens | tok), $v.idle_ticks, $v.dispatches, ($v.dispatch_tokens | tok), $v.merged_prs, $v.answers, $v.citations] | row),
  (if ($months | length) == 0 then "| none in this selection |" else empty end),
  (more(24; $months | length; "months")[]),
  "",
  (if ($months | length) < 3 then "Trend: omitted until three months exist (\($months | length) so far)."
   else ($months | .[-3:] | map(.value)) as $l
     | "Trend, last three months: tick tokens \($l | map(.tick_tokens | tok) | join(" → ")) · dispatch tokens \($l | map(.dispatch_tokens | tok) | join(" → ")) · idle ticks \($l | map(.idle_ticks | fig) | join(" → ")) · merged PRs \($l | map(.merged_prs | fig) | join(" → "))." end),
  "",
  "No backfill: a metric logged for the first time starts empty, so a `source: none` figure above has no months and no trend yet.",
  "",
  "## Suggested changes",
  "",
  (if ($fired | length) == 0 then "No rule fired on these figures."
   else ($fired | to_entries[] | "\(.key + 1). \(.value.say) `\(.value.m)` = \(.value.f) (rule \(.value.n): \(if .value.ge then "≥" else "<" end) \(.value.t))") end)
JQ

stale=""
gen="$(jq -r .generated_at "$F")"
[ -n "$last" ] && [[ "$gen" < "$last" ]] && stale="$last"
report="$(jq -r --arg project "$project" --arg since "$since" --arg stale "$stale" --arg tried "$tried" --arg failed "$failed" "$PROG" "$F" 2>/dev/null)" \
  || die 4 "$F does not match schema 1 — a figure has an unexpected type"
printf "%s\n" "$report"
