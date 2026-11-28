#!/usr/bin/env bash
#
# metrics-version.test.sh — every writer and reader of METRICS.json names one schema version:
# the schema_version plugin/scripts/metrics.sh writes, METRICS_VERSION in plugin/hooks/register.ts
# (the /pane Metrics view) and METRICS_VERSION in plugin/scripts/metrics-report.sh (the newest it
# reads). 4.20.0 shipped a pane reading 1 while metrics.sh wrote 2. A copy with one site moved
# must disagree, so the check is not vacuous. Reasoning: loopd-usage-metrics/task-006.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/metrics-version.XXXXXX")" || { echo "metrics-version.test: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
command -v jq >/dev/null 2>&1 || { echo "metrics-version.test: jq is required" >&2; exit 2; }
export CLAUDE_CONFIG_DIR="$TMP/config"

versions() { # <plugin dir> <bundle dir> — "<written> <pane> <report>", a site that names none is `-`
  local b="$2"
  mkdir -p "$b/.loopd"; echo '{}' > "$b/instance.config.json"; echo '{}' > "$b/.loopd/SNAPSHOT.json"; : > "$b/.loopd/log.md"
  bash "$1/scripts/metrics.sh" "$b" >/dev/null 2>&1
  printf '%s %s %s\n' "$(jq -r '.schema_version // "-"' "$b/.loopd/METRICS.json" 2>/dev/null || echo -)" \
    "$(sed -n 's/^const METRICS_VERSION = \([0-9][0-9]*\)$/\1/p' "$1/hooks/register.ts" | grep . || echo -)" \
    "$(sed -n 's/^METRICS_VERSION=\([0-9][0-9]*\)$/\1/p' "$1/scripts/metrics-report.sh" | grep . || echo -)"
}
agree() { set -- $1; [ "$1" != - ] && [ "$1" = "$2" ] && [ "$1" = "$3" ] && echo agree || echo disagree; }

echo "== the shipped plugin =="
b="$TMP/bundle"
v="$(versions "$REPO/plugin" "$b")"
ok "metrics.sh, register.ts and metrics-report.sh name one version" "$(agree "$v")" agree
(cd "$b" && bash "$REPO/plugin/scripts/metrics-report.sh" >/dev/null 2>&1); ok "metrics-report.sh reads the file metrics.sh wrote" "$?" 0

echo "== a copy with one site moved disagrees =="
mutant() { # <label> <file under plugin/> <sed expression>
  rm -rf "$TMP/plugin"; mkdir -p "$TMP/plugin/hooks"
  cp -R "$REPO/plugin/scripts" "$TMP/plugin/"; cp "$REPO/plugin/hooks/register.ts" "$TMP/plugin/hooks/"
  sed -i.bak "$3" "$TMP/plugin/$2"
  rm -rf "$TMP/mutant"; ok "$1" "$(agree "$(versions "$TMP/plugin" "$TMP/mutant")")" disagree
}
mutant "register.ts METRICS_VERSION moved" hooks/register.ts 's/^const METRICS_VERSION = [0-9]*$/const METRICS_VERSION = 99/'
mutant "metrics.sh's written version moved" scripts/metrics.sh 's/^SCHEMA=[0-9]*$/SCHEMA=99/'
mutant "metrics-report.sh METRICS_VERSION moved" scripts/metrics-report.sh 's/^METRICS_VERSION=[0-9]*$/METRICS_VERSION=99/'
mutant "a site that names no version" scripts/metrics-report.sh '/^METRICS_VERSION=/d'

echo
echo "metrics-version.test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
