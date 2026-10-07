#!/usr/bin/env bash
#
# retire-advisor.test.sh — the `advisor` role is retired (2026-10-08), and a bundle that
# still carries its configuration keeps working.
#
# THE DECISION. The advisor was a read-only observer dispatched once per tick, opt-in via
# `roles` + `roleTiers.advisor`. Measured 2026-10-07: enabled in none of the three real
# bundles, four `advisor:` log lines in one of them from an earlier configuration, none
# acted on. It read the same inputs as the project-manager and the PM adjudicated its
# output — a second opinion from the same context, so it failed the "name the
# architectural reason for this agent" test. The owner retired it.
#
# WHAT RETIRING MEANS HERE, in both directions:
#
#   1. GONE. `plugin/agents/advisor.md` is deleted, no shipped document dispatches
#      `<plugin>:advisor`, the launcher has no step 2b, and the seed config neither lists the
#      role nor documents it. Agents are registered by the PLUGIN, not by a link in a bundle
#      (SCHEMA.md: "a bundle has no `.claude/agents/`"), so there is no instance-side link
#      for `/<plugin>:init` step 2b to sweep — the legacy `.claude/agents/advisor.md` link
#      from the pre-plugin era is already in tests/retire-machinery.test.sh's swept set.
#
#   2. STILL WORKING. Real bundles carry `roleTiers.advisor` in their per-machine file,
#      task documents carry `advisor_notes: [ ]` and `advisor:` receipts, and one carries
#      `advisor` in `roles`. Every one of those is INERT, never an error: the bundle
#      validates, re-stamps clean, `resolve-model.sh advisor` still answers (a key nothing
#      reads is not a broken key), and `/<plugin>:welcome check` names the retired entry
#      ONCE as a report with the edit that removes it — exit 0, no fixer, same tier as an
#      unknown top-level key. `advisor_notes` itself is NOT retired: the `plan-architect`
#      approach critique writes it too (tests/approach-critique-trigger.test.sh).
#
# Both halves are asserted because either alone is vacuous: "the file is gone" passes a
# retirement that broke every bundle, and "the bundle still validates" passes a retirement
# that never happened.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
. "$HERE/tools/plugin-name.sh"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"
LAUNCHER="$REPO/plugin/skills/dispatch/SKILL.md"
STEP3="$REPO/plugin/tick-steps/step-3-dispatch.md"
STEP2="$REPO/plugin/tick-steps/step-2-refine-drafts.md"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
SEED_CFG="$REPO/plugin/seed/instance.config.json"
WELCOME="$REPO/plugin/scripts/welcome.sh"
for f in "$LAUNCHER" "$STEP3" "$STEP2" "$SCHEMA" "$SEED_CFG" "$WELCOME"; do
  [ -f "$f" ] || { echo "retire-advisor.test: missing $f" >&2; exit 2; }
done
command -v jq >/dev/null 2>&1 || { echo "retire-advisor.test: jq required" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/retire-advisor.XXXXXX")" || {
  echo "retire-advisor.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
case "$TMP" in /*) ;; *) echo "retire-advisor.test: mktemp returned a relative path" >&2; exit 2 ;; esac
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
# `grep -c`, never `grep -q` in a pipeline: under pipefail a `-q` exits at the first match
# and the writer's EPIPE becomes the pipeline's status.
count() { printf '%s\n' "$1" | grep -cF -- "$2" | tr -d ' '; }
# Every git call strips the repo-redirecting GIT_* variables and pins an identity, so a
# fixture's commits can never land in the repo under test and a machine with no identity
# still runs this.
GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git \
          -c user.email=test@example.com -c user.name=Test -c commit.gpgsign=false \
          -c core.hooksPath=/dev/null "$@"; }

# =======================================================================================
echo "== 1. GONE: the agent, its dispatch, its step, its seed key =="
# =======================================================================================
# path-scan: absent — the whole point of this assertion is that the path is GONE
ok "plugin/agents/advisor.md is deleted" \
  "$([ -e "$REPO/plugin/agents/advisor.md" ] && echo no || echo yes)" yes
ok "no shipped document dispatches ${PN}:advisor" \
  "$(grep -rlF "${PN}:advisor" "$REPO/plugin" | grep -c . | tr -d ' ')" 0
ok "the launcher has no step 2b" \
  "$(grep -c '^2b\. ' "$LAUNCHER" | tr -d ' ')" 0
ok "…and step 3 still follows step 2 (the file still parses as steps)" \
  "$(grep -c '^3\. \*\*On completion' "$LAUNCHER" | tr -d ' ')" 1
ok "step 3 no longer exempts the advisor from the --bg form" \
  "$(grep -c 'two exceptions are the `advisor`' "$STEP3" | tr -d ' ')" 0
ok "…while the plan-architect critique is still the Agent-tool exception" \
  "$(grep -c 'one exception is the `plan-architect` critique' "$STEP3" | tr -d ' ')" 1
ok "the seed config lists no advisor role" \
  "$(jq -r '.roles[]' "$SEED_CFG" | grep -cx advisor | tr -d ' ')" 0
ok "…prices no advisor tier" \
  "$(jq -r '.roleTiers | keys[]' "$SEED_CFG" | grep -cx advisor | tr -d ' ')" 0
ok "…and carries no \$advisor comment key" \
  "$(jq -r 'keys[]' "$SEED_CFG" | grep -cx '\$advisor' | tr -d ' ')" 0

# NOT retired, deliberately — the field outlives the agent because a second writer uses it.
ok "advisor_notes is still a schema field" \
  "$(grep -c '^advisor_notes:' "$SCHEMA" | tr -d ' ')" 1
ok "…marked retired-for-the-advisor in place, with the date" \
  "$(grep -c 'advisor_notes:.*RETIRED on 2026-10-08' "$SCHEMA" | tr -d ' ')" 1
ok "…and the approach critique still writes it" \
  "$(grep -c '`advisor_notes`' "$STEP2" | tr -d ' ' | awk '{print ($1 > 0 ? "yes" : "no")}')" yes
ok "welcome.sh keeps the retired-roles list, naming advisor" \
  "$(grep -c '^RETIRED_ROLES=.*advisor' "$WELCOME" | tr -d ' ')" 1

# =======================================================================================
echo "== 2. STILL WORKING: a bundle with the old configuration validates and stamps clean =="
# =======================================================================================
# A copy of the template with no `.git`, so the installer's own worktree guard never fires
# and `fix`-shaped paths touch nothing real. Same shape as board-in-repo.test.sh.
SRC="$TMP/tpl"; mkdir -p "$SRC"
( cd "$REPO" && git ls-files . ) | while IFS= read -r f; do
  [ -n "$f" ] || continue
  mkdir -p "$SRC/$(dirname "$f")"; cp "$REPO/$f" "$SRC/$f" 2>/dev/null || true
done
chmod +x "$SRC"/plugin/scripts/*.sh "$SRC"/plugin/hooks/*.sh 2>/dev/null || true
INIT="$SRC/plugin/scripts/init-bundle.sh"
VALIDATOR="$SRC/plugin/scripts/validate-bundle.sh"
RESOLVE="$SRC/plugin/scripts/resolve-model.sh"
WRITER="$SRC/plugin/scripts/write-snapshot.sh"
SH="$SRC/plugin/scripts/welcome.sh"

INST="$TMP/group/_loopd-group"; mkdir -p "$INST"
GIT -C "$INST" init -q . >/dev/null 2>&1
bash "$INIT" "$INST" >"$TMP/stamp1" 2>&1 </dev/null; rc1=$?
ok "a fresh stamp succeeds (the fixture is a real bundle)"            "$rc1" 0

# The old configuration, exactly as the three real bundles carry it: the role in the
# tracked roster, the tier in the per-machine file. Written with jq so the rest of each
# file — the seeded `models`/`roleTiers` the stamp just wrote — survives untouched.
jq '.roles += ["advisor"]' "$INST/instance.config.json" > "$TMP/cfg" && mv "$TMP/cfg" "$INST/instance.config.json"
jq '.roleTiers.advisor = "light"' "$INST/instance.config.local.json" > "$TMP/cfg" && mv "$TMP/cfg" "$INST/instance.config.local.json"
ok "fixture: advisor is in roles" \
  "$(jq -r '.roles[]' "$INST/instance.config.json" | grep -cx advisor | tr -d ' ')" 1
ok "fixture: roleTiers.advisor is in the local file" \
  "$(jq -r '.roleTiers.advisor // ""' "$INST/instance.config.local.json")" light

# A task document exactly as the loop left them: an empty `advisor_notes`, an `advisor:`
# receipt in `answered_questions`, an escalated `advisor:` question still open.
TS="2026-01-01T00:00:00Z"
mkdir -p "$INST/objectives" "$INST/projects/ci/tasks"
{ echo '---'; echo 'type: Objective'; echo 'title: Live'; echo 'status: active'
  echo "timestamp: $TS"; echo '---'; echo 'body'; } > "$INST/objectives/live.md"
{ echo '---'; echo 'type: Project'; echo 'title: CI'; echo 'description: one line'
  echo 'kind: build'; echo 'status: active'; echo 'objective: /objectives/live.md'
  echo "timestamp: $TS"; echo '---'; echo 'body'; } > "$INST/projects/ci/project.md"
{ echo '---'; echo 'type: Task'; echo 'title: Observed draft'; echo 'kind: build'
  echo 'status: draft'; echo 'objective: /objectives/live.md'
  echo 'acceptance_criteria: [ ]'
  echo 'open_questions:'
  echo '  - "advisor: Q1: Does criterion 2 contradict the recorded Finding?"'
  echo 'advisor_notes: [ ]'
  echo 'answered_questions:'
  echo '  - "2026-01-01T00:00:01Z · advisor: approach critique — no concerns"'
  echo "timestamp: $TS"; echo '---'; echo 'body'; } > "$INST/projects/ci/tasks/task-001.md"

VOUT="$(cd "$INST" && bash "$VALIDATOR" 2>&1)"; vrc=$?
ok "validate-bundle.sh exits 0 on the old-configuration bundle"         "$vrc" 0
ok "…and says nothing about the advisor (no check was added)"           "$(count "$VOUT" advisor)" 0

bash "$INIT" "$INST" >"$TMP/stamp2" 2>&1 </dev/null; rc2=$?
ok "a re-stamp over the old configuration succeeds"                     "$rc2" 0
# The stamp ends by running the welcome check, so the retired entry IS named there — once,
# as the report asserted in §3 — and nothing else in the stamp's output calls it an error.
ok "…and names the retired entry once, as the welcome report"           "$(grep -c 'config names retired role(s) nothing dispatches:' "$TMP/stamp2" | tr -d ' ')" 1
ok "…never as an error"                                                 "$(grep -i advisor "$TMP/stamp2" | grep -ci 'error' | tr -d ' ')" 0

ALIAS="$(bash "$RESOLVE" --instance "$INST" advisor 2>"$TMP/resolve.err")"; rrc=$?
ok "resolve-model.sh advisor still answers (an inert key is not a broken one)" "$rrc" 0
ok "…with the light tier's alias"                                       "$ALIAS" "$(jq -r '.models.light' "$INST/instance.config.local.json")"

SOUT="$(cd "$INST" && bash "$WRITER" --quiet 2>&1)"; src=$?
ok "write-snapshot.sh runs over the task"                               "$src" 0
ok "…and counts the empty advisor_notes as 0" \
  "$(jq -r '.projects[0].tasks[] | select(.id == "task-001") | .advisor_notes' "$INST/$AB_SNAPSHOT")" 0

# =======================================================================================
echo "== 3. REPORTED ONCE, NEVER AN ERROR: welcome check names the retired entry =="
# =======================================================================================
OUT="$(bash "$SH" check --instance "$INST" --template "$SRC" 2>&1)"; wrc=$?
ok "welcome check exits 0 (a retired role is a report, not a failure)"   "$wrc" 0
HEAD="$(printf '%s\n' "$OUT" | grep 'config names retired role(s) nothing dispatches:')"
ok "ONE headline names the retired role"                                "$(printf '%s\n' "$OUT" | grep -c 'config names retired role(s) nothing dispatches:' | tr -d ' ')" 1
ok "…as a warn (it survives --only-problems and reaches the banner)"    "$(printf '%s\n' "$HEAD" | grep -c '^⚠' | tr -d ' ')" 1
ok "…naming the tracked roles entry, by file"                           "$(count "$HEAD" 'instance.config.json:roles[advisor]')" 1
ok "…and the local roleTiers entry, by file"                            "$(count "$HEAD" 'instance.config.local.json:roleTiers.advisor')" 1
ok "…with the edit that removes it"                                     "$(count "$OUT" 'delete the entry from the file named above')" 1
ok "…and the unknown-key headline is NOT also printed (one headline)"    "$(count "$OUT" 'config carries key(s) nothing reads:')" 0
ok "the row's tier is ambiguous: fix will not touch a config file" \
  "$(bash "$SH" check --list | awk -F'\t' '$1=="config-unknown-keys"{print $2}')" "ambiguous"
ONLY="$(bash "$SH" check --instance "$INST" --template "$SRC" --only-problems 2>&1)"
ok "--only-problems keeps the line (it is the banner's input)"          "$(count "$ONLY" 'config names retired role(s) nothing dispatches:')" 1

# With an unknown top-level key as well: still ONE headline, the retired role folded in
# as a note under it — the banner's row count depends on exactly one line per check.
jq '. + {"unknownKeyProbe": null}' "$INST/instance.config.json" > "$TMP/cfg" && mv "$TMP/cfg" "$INST/instance.config.json"
OUT2="$(bash "$SH" check --instance "$INST" --template "$SRC" 2>&1)"
ok "unknown key + retired role: one unknown-key headline"               "$(count "$OUT2" 'config carries key(s) nothing reads:')" 1
ok "…no second headline for the retired role"                           "$(count "$OUT2" 'config names retired role(s) nothing dispatches:')" 0
ok "…and the retired role is named under it"                            "$(count "$OUT2" 'names retired role(s) nothing dispatches: instance.config.json:roles[advisor]')" 1
jq 'del(.unknownKeyProbe)' "$INST/instance.config.json" > "$TMP/cfg" && mv "$TMP/cfg" "$INST/instance.config.json"

# The clean direction, on the same bundle with both entries removed — without it the
# assertions above are satisfied by a check that names the role everywhere.
jq '.roles -= ["advisor"]' "$INST/instance.config.json" > "$TMP/cfg" && mv "$TMP/cfg" "$INST/instance.config.json"
jq 'del(.roleTiers.advisor)' "$INST/instance.config.local.json" > "$TMP/cfg" && mv "$TMP/cfg" "$INST/instance.config.local.json"
OUT3="$(bash "$SH" check --instance "$INST" --template "$SRC" 2>&1)"; wrc3=$?
ok "both entries removed: check still exits 0"                          "$wrc3" 0
ok "…the row is healthy again"                                          "$(count "$OUT3" 'config keys: every top-level key is one the machinery knows')" 1
ok "…and the advisor is named nowhere in the config rows" \
  "$(printf '%s\n' "$OUT3" | grep 'config' | grep -c advisor | tr -d ' ')" 0

# A malformed value names nothing rather than guessing: `roles` as a string and `roleTiers`
# as null are the documented unset shape and a typo respectively, and neither is the role.
jq '.roles = "advisor" | .roleTiers = null' "$INST/instance.config.local.json" > "$TMP/cfg" && mv "$TMP/cfg" "$INST/instance.config.local.json"
OUT4="$(bash "$SH" check --instance "$INST" --template "$SRC" 2>&1)"; wrc4=$?
ok "a malformed roles/roleTiers value is not reported as the retired role" "$(count "$OUT4" 'retired role')" 0
ok "…and the check still exits 0"                                       "$wrc4" 0

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
