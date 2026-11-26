#!/usr/bin/env bash
#
# metrics.test.sh — plugin/scripts/metrics.sh derives .loopd/METRICS.json from a fixture
# bundle and a stubbed `gh`: one computed value per family, unknown never a 0, the gh cache
# (0 calls once every PR is closed), stale figures kept offline, the tick-cost join, the board
# switch, the atomic write, the key allowlist and wall-time budgets on a fixture sized to a
# real bundle. Schema: docs/metrics.md. Reasoning: loopd-usage-metrics/task-001, task-004.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
M="$REPO/plugin/scripts/metrics.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/metrics.XXXXXX")" || { echo "metrics.test: mktemp failed" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
command -v jq >/dev/null 2>&1 || { echo "metrics.test: jq is required" >&2; exit 2; }

export CLAUDE_CONFIG_DIR="$TMP/config" METRICS_NOW=2026-11-01T00:00:00Z

# The host: `pr view <n>` answers $GHFX/view-<n>.json (honouring --jq), else a 404 on stderr;
# `api` answers $GHFX/<commits|reviews|rcomments|icomments>-<n>.json; GH_OFFLINE fails all.
GHFX="$TMP/ghfx"; mkdir -p "$TMP/bin" "$GHFX"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$GHFX/calls"
[ -n "${GH_OFFLINE:-}" ] && { echo "error connecting to api.github.com" >&2; exit 1; }
jqf=""; prev=""; for a in "$@"; do [ "$prev" = --jq ] && jqf="$a"; prev="$a"; done
out() { [ -f "$1" ] || { echo "GraphQL: Could not resolve to a PullRequest" >&2; exit 1; }
        if [ -n "$jqf" ]; then jq -r "$jqf" "$1"; else cat "$1"; fi; exit 0; }
case "$1 $2" in
  "pr view") out "$GHFX/view-$3.json" ;;
  "api graphql") echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}}'; exit 0 ;;
esac
for a in "$@"; do case "$a" in
  */pulls/*/commits*) n="${a#*/pulls/}"; out "$GHFX/commits-${n%%/*}.json" ;;
  */pulls/*/reviews*) n="${a#*/pulls/}"; out "$GHFX/reviews-${n%%/*}.json" ;;
  */pulls/*/comments*) n="${a#*/pulls/}"; out "$GHFX/rcomments-${n%%/*}.json" ;;
  */issues/*/comments*) n="${a#*/issues/}"; out "$GHFX/icomments-${n%%/*}.json" ;;
esac; done
exit 99
STUB
chmod +x "$TMP/bin/gh"; export GHFX PATH="$TMP/bin:$PATH"
calls() { : > "$GHFX/calls"; }
ncalls() { grep -c . "$GHFX/calls" | tr -d ' '; }
CRB='"user":{"login":"coderabbitai[bot]","type":"Bot"}'
ghpr() { # <n> <state> <created> <merged|null> <last commit> <last review> <x-rows>
  local m=null; [ "$4" = null ] || m="\"$4\""
  jq -n --argjson n "$1" --arg s "$2" --arg c "$3" --argjson m "$m" --arg lc "$5" --arg lr "$6" --argjson x "$7" '
    {number: $n, url: "https://github.com/example-user-007/widget/pull/\($n)", state: $s, createdAt: $c, mergedAt: $m,
     closedAt: $m, mergedBy: {login: "example-user-007"}, author: {login: "example-user-007"}, headRefOid: ("b" * 40),
     commits: [{committedDate: $lc}], reviews: [{submittedAt: $lr}],
     body: ("## Description\n\n| C | ✓ | V |\n|---|---|---|\n" + ("| b | ✗ | later |\n" * $x))}' > "$GHFX/view-$1.json"
  printf '[]\n' > "$GHFX/icomments-$1.json"
}
cr_rounds() { # <n> <rounds> <inline findings> — one CodeRabbit review per commit
  local i=0 c="[" r="["
  while [ "$i" -lt "$2" ]; do i=$((i+1)); sha="$(printf '%040d' "$1$i")"
    c="$c${c#[}{\"sha\":\"$sha\"}"; c="${c%\}}},"; r="$r{$CRB,\"state\":\"COMMENTED\",\"commit_id\":\"$sha\",\"body\":\"One nit.\"},"; done
  printf '%s]\n' "${c%,}" > "$GHFX/commits-$1.json"; printf '%s]\n' "${r%,}" > "$GHFX/reviews-$1.json"
  jq -n --argjson k "$3" "[range(\$k) | {$CRB}]" > "$GHFX/rcomments-$1.json"
}
ghpr 7 MERGED 2026-10-01T03:00:00Z 2026-10-01T09:00:00Z 2026-10-01T05:00:00Z 2026-10-01T07:00:00Z 1; cr_rounds 7 2 3
ghpr 9 MERGED 2026-10-05T00:30:00Z 2026-10-05T02:30:00Z 2026-10-05T01:00:00Z 2026-10-05T02:00:00Z 0; cr_rounds 9 1 0
ghpr 8 OPEN 2026-10-04T00:00:00Z null 2026-10-04T01:00:00Z 2026-10-04T01:00:00Z 0
mkdir -p "$CLAUDE_CONFIG_DIR/plugins/store"
printf '%s\n' '{"loopd.usage.abc12345":{"input":10,"cacheWrite":20,"output":30,"cacheRead":5,"ms":1,"toolErrors":0,"tools":{}},"loopd.usage.abc12345.ended":true}' \
  > "$CLAUDE_CONFIG_DIR/plugins/store/loopd_x.json"

B="$TMP/bundle"; T="$B/projects/alpha/tasks"; U=https://github.com/example-user-007/widget/pull
mkdir -p "$B/.loopd/citations" "$B/.loopd/.merge-holds" "$T"
echo '{}' > "$B/instance.config.json"; echo '{}' > "$B/.loopd/SNAPSHOT.json"
cat > "$B/.loopd/log.md" <<'LOG'
## 2026-10-11 — Project closed: gone (removed)
## 2026-10-01 — Project added: gone
## 2026-10-01 — Project added: alpha
* TICK 2026-10-01T01:00:00Z by example-user-007 open: tick-1 · full walk
* TICK 2026-10-01T01:00:00Z by example-user-007 close: dispatched one, merged widget#9 under yolo · usage tokens=1000 tools=1 ms=10
* TICK 2026-10-01T02:00:00Z by example-user-007 idle — fingerprint unchanged (tick-delta) · tick-2
* TICK 2026-10-01T03:00:00Z by example-user-007 idle — fingerprint unchanged (tick-delta) · tick-3
* TICK 2026-10-01T04:00:00Z by example-user-007 idle — fingerprint unchanged (tick-delta) · tick-4
* TICK 2026-10-01T05:00:00Z by example-user-007 idle — fingerprint unchanged · usage tokens=50 tools=1 ms=1
* TICK 2026-10-01T06:00:00Z by example-user-008 idle — fingerprint unchanged (tick-delta) · tick-9
LOG
mkdir -p "$B/.loopd/.tick-cost"
printf 'tick-1\t500\t9\t90\tx\ntick-2\t70\t1\t10\tx\ntick-3\tunknown\tunknown\tunknown\tx\ntick-x\t999\t1\t1\tx\n' > "$B/.loopd/.tick-cost/ticks.tsv"
printf -- '---\ntype: Project\nautonomy: yolo\n---\n' > "$B/projects/alpha/project.md"
cat > "$T/task-001-done.md" <<EOF
---
type: Task
status: "done"
timestamp: "2026-10-01T00:00:00Z"
stall_count: 0
open_questions: [ ]
answered_questions:
  - "2026-10-02T00:00:00Z by example-user-007 · Q1: which? --- this"
  - "2026-10-02T01:00:00Z by example-user-007 · Q2: when? --- now"
---
# Notes

* promoted 2026-10-01T02:00:00Z by example-user-007
* DISPATCH 2026-10-01T04:00:00Z · software-engineer · model opus · effort high · usage tokens=3000 tools=5 ms=3600000
* DISPATCH 2026-10-01T06:00:00Z · software-engineer · model opus · effort high · usage tokens=1000 tools=5 ms=3600000
* TOTAL 2026-10-01T10:00:00Z · rounds=2 · usage tokens=4000 tools=10 ms=7200000 · $U/7
EOF
cat > "$T/task-002-live.md" <<EOF
---
type: Task
status: in-progress
timestamp: 2026-10-03T00:00:00Z
stall_count: 1
pr: [ $U/8 ]
open_questions:
  - "Q1: which region?"
---
# Notes

* DISPATCH 2026-10-04T00:00:00Z · qa-reviewer · model sonnet · usage UNKNOWN
EOF
cat > "$T/task-003-other.md" <<EOF
---
type: Task
status: done
timestamp: 2026-10-05T00:00:00Z
pr: [ $U/9, $U/10 ]
open_questions: [ ]
---
# Notes

* DISPATCH 2026-10-05T01:00:00Z · software-engineer · model sonnet · usage tokens=2000 tools=2 ms=1800000
* TOTAL 2026-10-05T03:00:00Z · rounds=1 · usage tokens=2000 tools=2 ms=1800000 · $U/9
EOF
printf 'recorded: 2026-10-01\nKEPT some-finding\n' > "$B/.loopd/citations/widget-pr-7.txt"
printf 'recorded: 2026-10-05\nUNREAD other-finding\n' > "$B/.loopd/citations/widget-pr-9.txt"
printf 'recorded: 2026-10-05\n' > "$B/.loopd/citations/task-099-elsewhere.result.txt"
: > "$B/.loopd/.merge-holds/example-user-007_widget_8"
: > "$B/.loopd/.merge-holds/example-user-007_widget_5"

F="$B/.loopd/METRICS.json"
q() { jq -c "$1" "$F" 2>/dev/null; }

echo "== it writes the file =="
calls; bash "$M" "$B"; ok "exit 0" "$?" 0
ok "schema_version" "$(q .schema_version)" 2
ok "generated_at is UTC and pinned" "$(q .generated_at)" '"2026-11-01T00:00:00Z"'
ok "one object per family" "$(q '[.delegation,.time,.tokens,.idle_tick_spend,.blocked_by_cause,.owner_response,.self_merge,.quality,.kb_efficiency] | map(type) | unique')" '["object"]'
ok "headline holds five strings" "$(q '.headline | map_values(type) | [.delegation_share,.tokens_per_merged_pr,.idle_tick_spend,.top_block_cause,.self_merge_rate] | unique')" '["string"]'
ok "per-task keys are <slug>/<id>" "$(q '.tasks | keys')" '["alpha/task-001-done","alpha/task-002-live","alpha/task-003-other"]'
ok "monthly buckets" "$(q '.periods | keys')" '["2026-10"]'

echo "== one computed value per file-sourced family =="
ok "delegation: share of role-agent tokens (6000/7050)" "$(q .delegation.share_role_agents)" 0.851
ok "delegation: per role" "$(q '.delegation.by_role["software-engineer"].tokens')" 6000
ok "time: working hours from dispatch ms" "$(q '.tasks["alpha/task-001-done"].working_hours')" 2
ok "time: waiting = created→TOTAL minus working" "$(q '.tasks["alpha/task-001-done"].waiting_hours')" 8
ok "time: working unknown when a dispatch is UNKNOWN" "$(q '.tasks["alpha/task-002-live"].working_hours')" null
ok "tokens: per merged PR from TOTAL lines" "$(q .tokens.merged_prs.per_pr)" 3000
ok "tokens: fix rounds from TOTAL rounds" "$(q .tokens.merged_prs.fix_rounds)" 1
ok "tokens: headline" "$(q .headline.tokens_per_merged_pr)" '"3k"'
ok "idle: five idle ticks, two measured (tick-cost, then ledger)" "$(q '[.idle_tick_spend.idle_ticks, .idle_tick_spend.measured, .idle_tick_spend.tokens_measured]')" '[5,2,120]'
ok "idle: the unmeasured share is reported, not zeroed" "$(q .idle_tick_spend.unmeasured_share)" 0.6
ok "blocked: owner, merge gate (live PR only), stalled" "$(q '.blocked_by_cause.causes | [.owner.tasks, .merge_gate.holds, .stalled_agent.tasks]')" '[1,1,1]'
ok "owner_response: answers counted" "$(q .owner_response.answers)" 2
ok "kb: label and files read" "$(q '[.kb_efficiency.label, .kb_efficiency.citation_files]')" '["estimate",3]'
ok "kb: cited vs not cited" "$(q '[.kb_efficiency.cited.tasks, .kb_efficiency.not_cited.tasks]')" '[1,1]'

echo "== one computed value per gh-backed figure, through pr-quality.sh and review-rounds.sh =="
ok "time: PR open to merge, mean of 6 h and 2 h" "$(q '.time.pr_open_to_merge_hours | [.prs, .mean_hours, .stale]')" '[2,4,false]'
ok "time: a task's PR opened and merged" "$(q '.tasks["alpha/task-001-done"] | [.pr_opened, .pr_merged]')" '["2026-10-01T03:00:00Z","2026-10-01T09:00:00Z"]'
ok "owner: ready PR to merge, owner merges only (last review → merge)" "$(q '.owner_response.ready_pr_to_merge_hours | [.prs, .mean_hours]')" '[1,2]'
ok "self_merge: one of two merged PRs under yolo" "$(q '.self_merge | [.merged_prs, .loop, .rate]')" '[2,1,0.5]'
ok "self_merge: the reason when not" "$(q .self_merge.not_self_merged)" '{"example-user-007/widget#7":"criteria"}'
ok "self_merge: headline" "$(q .headline.self_merge_rate)" '"50% (1 of 2)"'
ok "quality: CodeRabbit findings per PR (pr-quality.sh)" "$(q '.quality | [.cr_findings, .cr_findings_per_pr]')" '[3,1.5]'
ok "quality: fix rounds per PR (review-rounds.sh)" "$(q '.quality | [.fix_rounds, .fix_rounds_per_pr]')" '[1,0.5]'
ok "quality: first-round merge share" "$(q .quality.first_round_merge_share)" 0.5
ok "quality: a 404 is read once and frozen, never stale" "$(q '.quality | [.prs_named, .prs_read, .stale]')" '[4,4,false]'

echo "== the tick-cost join =="
ok "pm ticks: joined on the tick id, unknown kept apart" "$(q '.tokens.pm_ticks | [.ticks, .measured, .unknown, .tokens]')" '[3,2,1,570]'
ok "…this clone's ticks with no row, other clones' excluded" "$(q .tokens.pm_ticks.ticks_without_row)" 1
ok "idle spend from tick-cost" "$(q '.idle_tick_spend.tick_cost | [.ticks, .measured, .unknown, .tokens]')" '[2,1,1,70]'

echo "== block causes with no source read unknown =="
ok "classifier, usage limit, CI flake" "$(q '.blocked_by_cause.causes | [.classifier_block, .usage_limit, .ci_flake]')" '[null,null,null]'

echo "== the gh cache =="
ok "one file per PR named" "$(ls "$B/.loopd/.pr-cache" | tr '\n' ' ')" "example-user-007__widget__10.json example-user-007__widget__7.json example-user-007__widget__8.json example-user-007__widget__9.json "
ok "…in a directory that ignores itself" "$(cat "$B/.loopd/.pr-cache/.gitignore")" "*"
calls; bash "$M" "$B"
ok "a second run re-reads only the open PR" "$(ncalls):$(grep -c 'pr view 8 ' "$GHFX/calls")" "1:1"
cp "$F" "$TMP/online.json"
calls; GH_OFFLINE=1 bash "$M" "$B"; rc=$?
ok "offline: exit 0" "$rc" 0
ok "…the gh figures are the previous file's, marked stale" "$(jq -c '[.self_merge, .quality, .time.pr_open_to_merge_hours] | map(del(.stale))' "$F")" "$(jq -c '[.self_merge, .quality, .time.pr_open_to_merge_hours] | map(del(.stale))' "$TMP/online.json")"
ok "…stale on each" "$(q '[.self_merge.stale, .quality.stale, .time.pr_open_to_merge_hours.stale, .owner_response.ready_pr_to_merge_hours.stale]')" '[true,true,true,true]'
ok "…and in the headline" "$(q .headline.self_merge_rate)" '"50% (1 of 2) (stale)"'
ok "…file figures are not stale" "$(q .time.stale)" false
GH_OFFLINE=1 bash "$M" "$B"; ok "offline twice: one stale marker" "$(q .headline.self_merge_rate)" '"50% (1 of 2) (stale)"'
ghpr 8 CLOSED 2026-10-04T00:00:00Z null 2026-10-04T01:00:00Z 2026-10-04T01:00:00Z 0
bash "$M" "$B"; ok "back online: stale cleared" "$(q .self_merge.stale)" false
calls; bash "$M" "$B"
ok "every named PR merged or closed: 0 gh calls" "$(ncalls)" 0
mkdir "$TMP/nogh"; ln -s "$(command -v jq)" "$TMP/nogh/jq"
ok "…not even with gh missing" "$(PATH="$TMP/nogh:/usr/bin:/bin" "$BASH" "$M" "$B"; echo "$?:$(q .quality.stale)")" "0:false"
ok "a PR no task names leaves the cache" "$(printf '{}' > "$B/.loopd/.pr-cache/o__r__1.json"; bash "$M" "$B"; [ -e "$B/.loopd/.pr-cache/o__r__1.json" ] && echo kept || echo pruned)" pruned

echo "== main session is unattributed and never summed =="
ok "main session label and figure" "$(q '.delegation.main_session | [.label, .tokens]')" '["unattributed (machine-wide)",60]'
ok "supervision is the ledger alone" "$(q .tokens.supervision)" 1050

echo "== closed projects and the rebuild =="
ok "a removed project keeps its ledger figures" "$(q '.projects.gone | [.state, .open_days]')" '["closed",10]'
cp "$F" "$TMP/first.json"; rm -f "$F"; bash "$M" "$B"
ok "a deleted METRICS.json rebuilds byte-identical" "$(cmp -s "$F" "$TMP/first.json" && echo same)" same

ok "a quoted frontmatter scalar is unquoted" "$(q '.tasks["alpha/task-001-done"] | [.status, .created]')" '["done","2026-10-01T00:00:00Z"]'

echo "== fix rounds are per merged PR, not per task =="
R="$TMP/rounds"; mkdir -p "$R/.loopd" "$R/projects/p/tasks"; echo '{}' > "$R/instance.config.json"; echo '{}' > "$R/.loopd/SNAPSHOT.json"
grep '^\* TICK' "$B/.loopd/log.md" > "$R/.loopd/log.md"
printf -- '---\nstatus: done\n---\n# Notes\n\n* TOTAL 2026-10-01T10:00:00Z · rounds=3 · usage tokens=10 tools=1 ms=1 · %s/1 %s/2\n' "$U" "$U" > "$R/projects/p/tasks/task-001.md"
bash "$M" "$R"
ok "three rounds over two PRs is one fix round per PR" "$(jq -c '[.tokens.merged_prs.fix_rounds, .tokens.merged_prs.fix_rounds_per_pr]' "$R/.loopd/METRICS.json")" '[2,1]'

echo "== an idle ledger with no usage is unknown, never zero =="
I="$TMP/idle"; mkdir -p "$I/.loopd"; echo '{}' > "$I/instance.config.json"; echo '{}' > "$I/.loopd/SNAPSHOT.json"
grep 'example-user-007 idle — fingerprint unchanged (tick-delta)' "$B/.loopd/log.md" > "$I/.loopd/log.md"
bash "$M" "$I"
ok "tokens unknown" "$(jq -c .idle_tick_spend.tokens_measured "$I/.loopd/METRICS.json")" null
ok "headline says unknown" "$(jq -r .headline.idle_tick_spend "$I/.loopd/METRICS.json")" "? (3 idle ticks, none measured)"

echo "== the board switch =="
O="$TMP/off"; mkdir -p "$O/.loopd"; cp "$B/.loopd/log.md" "$O/.loopd/"; echo '{"board": false}' > "$O/instance.config.json"
echo '{}' > "$O/.loopd/SNAPSHOT.json"; bash "$M" "$O"
ok "board: false writes nothing" "$([ -e "$O/.loopd/METRICS.json" ] && echo written || echo none)" none
echo '{}' > "$O/instance.config.json"; rm "$O/.loopd/SNAPSHOT.json"; bash "$M" "$O"
ok "no SNAPSHOT.json writes nothing" "$([ -e "$O/.loopd/METRICS.json" ] && echo written || echo none)" none
ok "step 8 runs it beside write-snapshot.sh" "$(grep -c 'scripts/metrics\.sh \.' "$REPO/plugin/tick-steps/step-8-render.md")" 1
ok "only step 8 runs it (no idle path, no refresh-state.sh)" \
  "$(cd "$REPO/plugin" && grep -rl 'scripts/metrics\.sh' --include='*.sh' --include='*.md' --include='*.ts' --include='*.json' . | grep -v '^./scripts/metrics\.sh$' | tr '\n' ' ')" \
  "./tick-steps/step-8-render.md "

echo "== the atomic write =="
cp "$F" "$TMP/before.json"; mv "$B/.loopd/log.md" "$TMP/log.md"
bash "$M" "$B" 2>/dev/null; ok "an unreadable ledger exits 2" "$?" 2
ok "…and keeps the previous file" "$(cmp -s "$F" "$TMP/before.json" && echo kept)" kept
ok "…with no temp file left" "$(ls -a "$B/.loopd" | grep -c '^\.METRICS')" 0
mv "$TMP/log.md" "$B/.loopd/log.md"
mkdir "$TMP/nojq"; ln -s "$(command -v dirname)" "$TMP/nojq/dirname"
err="$(PATH="$TMP/nojq" "$BASH" "$M" "$B" 2>&1)"; rc=$?
ok "without jq: exit 2" "$rc" 2
ok "…a named error" "$(printf '%s' "$err" | grep -c 'jq not found')" 1
ok "…and the previous file kept" "$(cmp -s "$F" "$TMP/before.json" && echo kept)" kept
fails_kept() { # <label> — metrics.sh exits 2 and leaves the previous file
  bash "$M" "$B" 2>/dev/null; ok "$1: exit 2" "$?" 2
  ok "$1: previous file kept" "$(cmp -s "$F" "$TMP/before.json" && echo kept)" kept
}
cp "$B/instance.config.json" "$TMP/cfg.json"; echo '{ "board": ' > "$B/instance.config.json"
fails_kept "a config that does not parse"; cp "$TMP/cfg.json" "$B/instance.config.json"
echo '{ not json' > "$CLAUDE_CONFIG_DIR/plugins/store/loopd_broken.json"
fails_kept "a usage store that does not parse"; rm "$CLAUDE_CONFIG_DIR/plugins/store/loopd_broken.json"
chmod 000 "$T/task-003-other.md"
if [ -r "$T/task-003-other.md" ]; then echo "  SKIP  an unreadable task doc (running as root)"
else fails_kept "an unreadable task document"; fi
chmod 644 "$T/task-003-other.md"
bash "$M" "$B"; ok "the normal path still writes after each refusal" "$(cmp -s "$F" "$TMP/before.json" && echo same)" same

echo "== the key allowlist =="
ALLOWED='pm_ticks ticks_without_row unknown tick_cost mean_hours loop rate reasons not_self_merged criteria gated
prs_named prs_read cr_reviewed_prs cr_findings cr_findings_per_pr first_round_merge_share x_rows_per_pr
schema_version generated_at headline delegation_share tokens_per_merged_pr idle_tick_spend top_block_cause self_merge_rate
delegation source stale unit role_agent_tokens supervision_tokens share_role_agents by_role by_model dispatches measured tokens main_session label sessions
time tasks_reflected mean_draft_hours mean_queued_hours mean_in_flight_hours mean_working_hours mean_waiting_hours projects_closed mean_project_open_days pr_open_to_merge_hours
supervision role_agents supervision_ticks supervision_ticks_measured merged_prs totals prs per_pr fix_rounds fix_rounds_per_pr
ticks idle_ticks idle_share tokens_measured unmeasured_share blocked_by_cause causes owner merge_gate holds stalled_agent rounds classifier_block usage_limit ci_flake top hours
owner_response answers needs_you_to_action_hours ready_pr_to_merge_hours self_merge quality
kb_efficiency citation_files sources_citing pr_records cited not_cited mean_tokens mean_rounds
tasks project status created promoted first_dispatch reflected dispatches_measured tokens_from draft_hours queued_hours in_flight_hours working_hours waiting_hours pr_opened pr_merged stall_count open_questions
projects state added closed open_days tasks_reflected periods ticks_measured tick_tokens dispatch_tokens idle_measured citations'
extra() { # <json> — keys outside ALLOWED; the keys of a by-id map are data, not fields
  jq -r --arg a "$ALLOWED" '
    def ks(m): if type == "object" then to_entries[] | (if m then empty else .key end),
        (.key as $k | .value | ks($k | IN("tasks", "projects", "periods", "by_role", "by_model", "not_self_merged")))
      elif type == "array" then .[] | ks(false) else empty end;
    ($a | split("\\s+"; null)) as $ok | [ks(false)] | unique | map(select(. as $k | $ok | index([$k]) | not)) | join(" ")' "$1"
}
ok "no key outside the documented set" "$(extra "$F")" ""
printf '%s\n' '{"delegation":{"home path":"/x"},"tasks":{"a/b":{"email":"e"}}}' > "$TMP/bad.json"
ok "…and the check can fail" "$(extra "$TMP/bad.json")" "email home path"
ok "no fixture home path in the file" "$(grep -c "$TMP" "$F")" 0

echo "== guard: wall time on a fixture sized to a real bundle =="
# Sized at refine: 1,093 open lines and 423 citation files. Budget: 5 s (measured ~0.3 s).
G="$TMP/sized"; mkdir -p "$G/.loopd/citations" "$G/projects"; echo '{}' > "$G/instance.config.json"; echo '{}' > "$G/.loopd/SNAPSHOT.json"
awk 'BEGIN { for (i = 0; i < 1100; i++) {
  d = sprintf("2026-%02d-%02dT%02d:00:00Z", 8 + int(i / 300), 1 + i % 28, i % 24)
  printf "* TICK %s by example-user-007 open: tick-%d · full walk\n", d, i
  if (i % 2) printf "* TICK %s by example-user-007 close: walked · usage tokens=%d tools=3 ms=900\n", d, 1000 + i
  else printf "* TICK %s by example-user-007 idle — fingerprint unchanged (tick-delta) · tick-%d\n", d, i } }' > "$G/.loopd/log.md"
for i in $(seq 1 425); do printf 'recorded: 2026-10-01\nKEPT finding-%d\n' "$i" > "$G/.loopd/citations/widget-pr-$i.txt"; done
mkdir -p "$G/.loopd/.pr-cache"
for p in $(seq 1 12); do mkdir -p "$G/projects/p$p/tasks"; for t in 1 2 3 4 5 6; do n=$((p * 10 + t))
  sed "s#/pull/7\$#/pull/$n#" "$T/task-001-done.md" > "$G/projects/p$p/tasks/task-00$t.md"
  jq -n --argjson n "$n" '{v: 1, pr: {state: "MERGED", created_at: "2026-10-01T00:00:00Z", ready_at: "2026-10-01T01:00:00Z",
    merged_at: "2026-10-01T02:00:00Z"}, quality: {merged_at: "x", x_rows: "0", cr_findings: "\($n % 3)", qa_fail: "-"},
    rounds: {coderabbit: ($n % 2 + 1)}}' > "$G/.loopd/.pr-cache/example-user-007__widget__$n.json"; done; done
calls; TIMEFORMAT=%R; secs="$( { time bash "$M" "$G" >/dev/null 2>&1; } 2>&1 )"
ok "the sized fixture is what was measured" "$(jq -c '[.kb_efficiency.citation_files, .idle_tick_spend.ticks, (.tasks | length), .quality.merged_prs]' "$G/.loopd/METRICS.json")" '[425,1100,72,72]'
ok "…with a warm cache: 0 gh calls" "$(ncalls)" 0
# Budgets, measured 2026-11-26 on an M3 Pro: task-001 5 s (~0.3 s, no gh); task-004 5 s, warm cache (~0.6 s).
ok "metrics.sh within the 5 s warm-cache budget (took ${secs}s)" "$(awk -v s="$secs" 'BEGIN { print (s + 0 <= 5) ? "yes" : "no" }')" yes
ok "no python3 in metrics.sh" "$(grep -c python3 "$M")" 0

echo
echo "metrics.test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
