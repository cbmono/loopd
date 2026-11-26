#!/usr/bin/env bash
#
# metrics.test.sh — plugin/scripts/metrics.sh derives .loopd/METRICS.json from a fixture
# bundle: one computed value per file-sourced family, `source: none` and unknown never a 0,
# the board switch, the atomic write, the key allowlist and a wall-time budget on a fixture
# sized to a real bundle; then metrics-report.sh (/loopd:metrics) on the same fixture.
# Schema: docs/metrics.md. Reasoning: loopd-usage-metrics/task-001, task-003.
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
* TICK 2026-10-01T01:00:00Z by example-user-007 close: dispatched one · usage tokens=1000 tools=1 ms=10
* TICK 2026-10-01T02:00:00Z by example-user-007 idle — fingerprint unchanged (tick-delta) · tick-2
* TICK 2026-10-01T03:00:00Z by example-user-007 idle — fingerprint unchanged (tick-delta) · tick-3
* TICK 2026-10-01T04:00:00Z by example-user-007 idle — fingerprint unchanged (tick-delta) · tick-4
* TICK 2026-10-01T05:00:00Z by example-user-007 idle — fingerprint unchanged · usage tokens=50 tools=1 ms=1
LOG
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
bash "$M" "$B"; ok "exit 0" "$?" 0
ok "schema_version" "$(q .schema_version)" 1
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
ok "idle: four idle ticks, one measured" "$(q '[.idle_tick_spend.idle_ticks, .idle_tick_spend.measured, .idle_tick_spend.tokens_measured]')" '[4,1,50]'
ok "idle: the unmeasured share is reported, not zeroed" "$(q .idle_tick_spend.unmeasured_share)" 0.75
ok "blocked: owner, merge gate (live PR only), stalled" "$(q '.blocked_by_cause.causes | [.owner.tasks, .merge_gate.holds, .stalled_agent.tasks]')" '[1,1,1]'
ok "owner_response: answers counted" "$(q .owner_response.answers)" 2
ok "kb: label and files read" "$(q '[.kb_efficiency.label, .kb_efficiency.citation_files]')" '["estimate",3]'
ok "kb: cited vs not cited" "$(q '[.kb_efficiency.cited.tasks, .kb_efficiency.not_cited.tasks]')" '[1,1]'

echo "== no source, no number =="
ok "self_merge reads source none" "$(q .self_merge)" '{"source":"none","stale":false}'
ok "quality reads source none" "$(q .quality)" '{"source":"none","stale":false}'
ok "a gh figure reads source none" "$(q .owner_response.ready_pr_to_merge_hours)" '{"source":"none"}'
ok "self-merge headline is a dash" "$(q .headline.self_merge_rate)" '"—"'

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
grep 'idle — fingerprint unchanged (tick-delta)' "$B/.loopd/log.md" > "$I/.loopd/log.md"
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
ALLOWED='schema_version generated_at headline delegation_share tokens_per_merged_pr idle_tick_spend top_block_cause self_merge_rate
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
        (.key as $k | .value | ks($k | IN("tasks", "projects", "periods", "by_role", "by_model")))
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
for p in $(seq 1 12); do mkdir -p "$G/projects/p$p/tasks"; for t in 1 2 3 4 5 6; do cp "$T/task-001-done.md" "$G/projects/p$p/tasks/task-00$t.md"; done; done
TIMEFORMAT=%R; secs="$( { time bash "$M" "$G" >/dev/null 2>&1; } 2>&1 )"
ok "the sized fixture is what was measured" "$(jq -c '[.kb_efficiency.citation_files, .idle_tick_spend.ticks, (.tasks | length)]' "$G/.loopd/METRICS.json")" '[425,1100,72]'
ok "metrics.sh within the 5 s budget (took ${secs}s)" "$(awk -v s="$secs" 'BEGIN { print (s + 0 <= 5) ? "yes" : "no" }')" yes

echo "== /loopd:metrics: metrics-report.sh reads METRICS.json and computes nothing =="
MR="$REPO/plugin/scripts/metrics-report.sh"
rep() { (cd "$1" && shift && bash "$MR" "$@" 2>&1); }
has() { printf '%s\n' "$1" | grep -cF -- "$2" | tr -d ' '; }
sugg() { printf '%s\n' "$1" | sed -n '/^## Suggested changes/,$p' | grep -E '^[0-9]+\. '; }
bash "$M" "$B"; cp "$F" "$TMP/report-before.json"
STUB="$TMP/stub"; mkdir -p "$STUB"
for t in gh git; do printf '#!/bin/sh\necho called >> "%s/stub-calls"\nexit 1\n' "$TMP" > "$STUB/$t"; chmod +x "$STUB/$t"; done
out="$(cd "$B" && PATH="$STUB:$PATH" bash "$MR" 2>&1)"; rc=$?
ok "with gh and git stubbed to fail: exit 0" "$rc" 0
ok "…neither stub was called" "$([ -e "$TMP/stub-calls" ] && echo called || echo never)" never
ok "…and METRICS.json's bytes are unchanged" "$(cmp -s "$F" "$TMP/report-before.json" && echo same)" same
ok "the headline prints METRICS.json's own string" "$(has "$out" '| 85% role agents | 3k |')" 1
ok "per-project table" "$(has "$out" '| gone | closed | 2026-10-01 | 2026-10-11 | 10d |')" 1
ok "per-task table" "$(has "$out" '| alpha/task-001-done | done | 2026-10-01 | 4k | 2 |')" 1
ok "blocked by cause, counted now" "$(has "$out" '| merge gate | 1 holds |')" 1
ok "source: none prints as named, never 0" "$(has "$out" '| self-merge | rate | — source: none |')" 1
ok "unknown prints as named, never 0" "$(has "$out" '| alpha/task-002-live | in-progress | 2026-10-03 | ? unknown |')" 1
ok "KB efficiency is an estimate, not time saved" "$(has "$out" '## KB efficiency — an estimate, not measured time saved')" 1
ok "…and nothing claims time saved" "$(printf '%s\n' "$out" | grep -i 'time saved' | grep -vc 'not \(measured \)\{0,1\}time saved' | tr -d ' ')" 0
ok "a newly logged metric has no backfill" "$(has "$out" 'No backfill: a metric logged for the first time starts empty')" 1
ok "one month: the trend is omitted" "$(has "$out" 'Trend: omitted until three months exist (1 so far).')" 1
ok "one firing rule prints only that one" "$(sugg "$out")" \
  '1. Lengthen the `/loopd:dispatch` gap, or stop the loop between batches: half or more of the ticks found nothing to do. `idle_tick_spend.idle_share` = 80% (rule 1: ≥ 0.5)'
ok "the report is fresh after a full tick" "$(has "$out" '**Stale:**')" 0

V="$TMP/variant"; mkdir -p "$V/.loopd"; echo '{}' > "$V/instance.config.json"; cp "$B/.loopd/log.md" "$V/.loopd/"
variant() { jq "$1" "$TMP/report-before.json" > "$V/.loopd/METRICS.json"; }
variant '.idle_tick_spend.idle_share = 0.9 | .delegation.share_role_agents = 0.25 | .tokens.merged_prs.fix_rounds_per_pr = 1
  | .blocked_by_cause.causes.owner.tasks = 6 | .time.mean_queued_hours = 48 | .tokens.stale = true'
out="$(rep "$V")"
ok "five rules fire, three print, ties to the lower rule" "$(sugg "$out" | sed 's/.*(rule \([0-9]\).*/\1/' | tr '\n' ' ')" "2 4 6 "
ok "each names its metric and value" "$(sugg "$out" | grep -c '`[a-z_.]*` = [0-9]')" 3
ok "a stale family is marked" "$(has "$out" '| tokens (stale) | supervision / role agents |')" 1
variant '.delegation.share_role_agents = null | .idle_tick_spend.idle_share = {"source": "none"} | .tokens.merged_prs.fix_rounds_per_pr = null'
ok "unknown and source none never fire a rule" "$(has "$(rep "$V")" 'No rule fired on these figures.')" 1
variant '.generated_at = "2026-09-30T00:00:00Z"'
out="$(rep "$V")"
ok "older than the last full tick: stale, refreshed by the next changing tick" \
  "$(has "$out" '**Stale:** these figures were generated before the last full tick (2026-10-01T01:00:00Z). They refresh on the next tick that changes something.')" 1
variant '.generated_at = "2026-10-01T01:30:00Z"'
ok "a later IDLE line is not a refresh" "$(has "$(rep "$V")" '**Stale:**')" 0
variant '.periods = {"2026-08": {"tick_tokens": 1000, "dispatch_tokens": 0, "idle_ticks": 1, "merged_prs": 0},
  "2026-09": {"tick_tokens": 2000, "dispatch_tokens": 5000, "idle_ticks": 2, "merged_prs": 1},
  "2026-10": {"tick_tokens": 3000, "dispatch_tokens": 9000, "idle_ticks": 0, "merged_prs": 2}}'
ok "three months: a short trend" "$(has "$(rep "$V")" 'tick tokens 1k → 2k → 3k · dispatch tokens 0 → 5k → 9k')" 1
ok "--since by month, a day selects its month" "$(rep "$V" --since 2026-09-15 | grep -cE '^\| 2026-(08|09|10) ' | tr -d ' ')" 2
ok "…two months: the trend is omitted" "$(has "$(rep "$V" --since 2026-09)" 'omitted until three months exist (2 so far)')" 1
ok "…task rows by month too (a day keeps its whole month)" "$(rep "$B" --since 2026-10-04 | grep -c '^| alpha/' | tr -d ' ')" 3
ok "a future month prints empty tables" "$(has "$(rep "$B" --since 2099-01)" '| none in this selection |')" 2
out="$(rep "$B" --project gone)"
ok "--project narrows projects" "$(printf '%s\n' "$out" | grep -cE '^\| (alpha|gone) \| (live|closed)' | tr -d ' ')" 1
ok "…and tasks (a removed project has none)" "$(printf '%s\n' "$out" | grep -c '^| alpha/' | tr -d ' ')" 0
ok "…and leaves suggestions bundle-wide" "$(sugg "$out" | grep -c 'rule 1')" 1
for bad in "--project nope" "--project ../x" "--since 2026-13" "--since yesterday" "--since" "--verbose"; do
  # shellcheck disable=SC2086
  rep "$B" $bad >/dev/null; ok "invalid input exits 3: $bad" "$?" 3
done
ok "an unknown slug is named" "$(has "$(rep "$B" --project nope)" "no project 'nope'")" 1

variant '.tasks = ([range(0; 200)] | map({key: "alpha/task-\(.)", value: {project: "alpha", status: "done", created: "2026-10-01T00:00:00Z"}}) | from_entries)
  | .tasks["alpha/task-x"] = {project: "alpha", status: "a\u001b[2Jb|c", created: "2026-10-02T00:00:00Z"}'
out="$(rep "$V")"
ok "the report is bounded" "$(printf '%s\n' "$out" | awk 'END { print (NR <= 160) ? "yes" : "no (" NR " lines)" }')" yes
ok "…and names what it cut" "$(has "$out" '… 176 more tasks not shown')" 1
ok "…and control characters and pipes never reach it" "$(printf '%s\n' "$out" | grep -c "$(printf '\033')\|a\[2Jb|c" | tr -d ' ')" 0

echo '{"board": false}' > "$V/instance.config.json"
out="$(rep "$V")"; rc=$?
ok "board false: metrics off, exit 0" "$rc" 0
ok "…naming the on switch" "$(has "$out" 'Metrics are off: "board": false in instance.config.json')" 1
echo '{}' > "$V/instance.config.json"; rm "$V/.loopd/METRICS.json"
out="$(rep "$V")"; rc=$?
ok "absent METRICS.json: metrics off, exit 0" "$rc$(has "$out" 'Metrics are off: no .loopd/METRICS.json. They follow the board switch, "board"')" 01
named() { # <label> <want-substring> — exit 4 with a named error
  out="$(rep "$V")"; ok "$1: exit 4" "$?" 4; ok "…named" "$(has "$out" "metrics-report: .loopd/METRICS.json $2")" 1; }
: > "$V/.loopd/METRICS.json"; named "a zero-byte file" "is empty"
head -c 300 "$TMP/report-before.json" > "$V/.loopd/METRICS.json"; named "a truncated file" "is truncated or not JSON"
variant '.schema_version = 2'; named "an unknown schema" 'has an unknown schema_version 2'
variant 'del(.periods)'; named "a missing section" "is missing a section of schema 1"
variant '.'; out="$(cd "$V" && PATH="$TMP/nojq" "$BASH" "$MR" 2>&1)"; rc=$?
ok "without jq: exit 2 and a named error" "$rc $(has "$out" 'jq not found')" "2 1"
ok "metrics-report.sh never uses python3" "$(grep -c python3 "$MR" | tr -d ' ')" 0

echo
echo "metrics.test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
