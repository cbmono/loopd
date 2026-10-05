#!/usr/bin/env bash
#
# roles-roletiers-asymmetry.test.sh — `roles` and `roleTiers` in
# `seed/instance.config.json` deliberately do NOT share membership, and this pins
# that as a valid, intentional state rather than drift someone "fixes" later.
#
# WHY THIS EXISTS. `roles` is the roster the PM may dispatch a task to. `roleTiers`
# is broader — a model tier for ANY agent this instance dispatches, including ones
# no task is ever assigned to. `plan-architect` is the live example: it carries a
# `roleTiers` entry (`apex`) and has no place in `roles`, because `/plan` and the
# PM's approach critique dispatch it directly and no task is ever assigned to it.
# Undocumented, that reads as a bug to the next person, who "fixes" it by deleting
# the `plan-architect` row or adding it to `roles` — either edit breaks something
# real. See SCHEMA.md 'type: Agent' for the documented distinction this test pins.
#
# `scripts/validate-bundle.sh` does NOT check this today — it validates task/
# knowledge frontmatter (type, status, timestamp, structural refs), never the
# CONTENT of `instance.config.json` beyond confirming the file exists. So the
# asymmetry is "valid" only in the sense that nothing rejects it; this file is the
# thing that pins it, not a change to the validator. Do not add enforcement to
# validate-bundle.sh that would REJECT this asymmetry — that is the one outcome
# this test exists to catch.
#
# assert() follows the same convention as the other harnesses here: 0 is a PASS.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SEED_CFG="$REPO/plugin/seed/instance.config.json"
VALIDATOR="$REPO/plugin/scripts/validate-bundle.sh"
[[ -f "$SEED_CFG" ]] || { echo "roles-roletiers-asymmetry.test: $SEED_CFG not found" >&2; exit 2; }
[[ -f "$VALIDATOR" ]] || { echo "roles-roletiers-asymmetry.test: $VALIDATOR not found" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "roles-roletiers-asymmetry.test: jq required" >&2; exit 2; }

pass=0; fail=0
assert() { # <label> <0|1>
  if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi
}
in_json_array() { jq -e --arg v "$2" '. as $a | ($a | index($v)) != null' <<<"$1" >/dev/null && echo 0 || echo 1; }

echo "== the seeded asymmetry is exactly the one SCHEMA.md documents =="
ROLES="$(jq -c '.roles' "$SEED_CFG")"
ROLETIER_KEYS="$(jq -c '.roleTiers | keys' "$SEED_CFG")"
assert "plan-architect has a roleTiers entry" \
  "$(in_json_array "$ROLETIER_KEYS" "plan-architect")"
assert "plan-architect is absent from roles" \
  "$([[ "$(in_json_array "$ROLES" "plan-architect")" == 1 ]] && echo 0 || echo 1)"

echo "== seed doc strings say the asymmetry is intentional =="
assert '$roles points at $roleTiers / SCHEMA.md' \
  "$(jq -e '.["$roles"] // "" | test("roleTiers|SCHEMA")' "$SEED_CFG" >/dev/null && echo 0 || echo 1)"
assert '$roleTiers names plan-architect and apex' \
  "$(jq -e '.["$roleTiers"] // "" | test("plan-architect") and test("apex")' "$SEED_CFG" >/dev/null && echo 0 || echo 1)"

echo "== validate-bundle.sh confirms the shipped config VALID, asymmetry and all =="
TMP="$(mktemp -d "${TMPDIR:-/tmp}/roles-roletiers-asymmetry.XXXXXX")" || {
  echo "roles-roletiers-asymmetry.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/objectives" "$TMP/projects/live/tasks"
cp "$SEED_CFG" "$TMP/instance.config.json"
echo '# Schema' > "$TMP/SCHEMA.md"
TS="2026-01-01T00:00:00Z"
{
  echo '---'; echo 'type: Objective'; echo 'title: Live'; echo 'status: active'
  echo "timestamp: $TS"; echo '---'; echo 'body'
} > "$TMP/objectives/live.md"
{
  echo '---'; echo 'type: Task'; echo 'title: T'; echo 'status: ready'
  echo 'objective: /objectives/live.md'; echo "timestamp: $TS"; echo '---'; echo 'body'
} > "$TMP/projects/live/tasks/task-001.md"

set +e
OUT="$(cd "$TMP" && bash "$VALIDATOR" 2>&1)"; RC=$?
set -e
assert "validate-bundle exits 0 against the shipped roles/roleTiers asymmetry" \
  "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "validate-bundle reports 0 errors" \
  "$(grep -q '0 errors' <<<"$OUT" && echo 0 || echo 1)"
assert "validate-bundle says nothing about roles or roleTiers" \
  "$(grep -qi 'role' <<<"$OUT" && echo 1 || echo 0)"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
