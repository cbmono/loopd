#!/usr/bin/env bash
#
# explorer-tier.test.sh — the `explorer` tier resolves like any other role, and its
# ABSENCE is the case that matters: broad reads go to an Explore subagent
# (seed/CONVENTIONS.md), so a caller that resolves nothing and is not told would
# dispatch it on whatever the session happens to be. Pins the whole config path
# offline — roleTiers.explorer -> tier -> models[tier] -> alias — plus the
# no-entry fallback (`light`) and the reason resolve-model.sh prints for it.
#
# Reasoning: /projects/ai-bridge-next/tasks/task-023-*.md.
# ok() compares actual to expected, as everywhere else in this directory.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SEED_CFG="$REPO/plugin/seed/instance.config.json"
RESOLVE="$REPO/plugin/scripts/resolve-model.sh"
CONV="$REPO/plugin/seed/CONVENTIONS.md"
PM="$REPO/plugin/tick-steps/step-3-dispatch.md"
for f in "$SEED_CFG" "$RESOLVE" "$CONV" "$PM"; do
  [ -f "$f" ] || { echo "explorer-tier.test: $f not found" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || { echo "explorer-tier.test: python3 required" >&2; exit 2; }

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-56s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-56s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { "$@" >/dev/null 2>&1 && echo yes || echo no; }
jget() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],{}).get(sys.argv[3],""))' "$1" "$2" "$3"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/explorer-tier.XXXXXX")" || {
  echo "explorer-tier.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

echo "== the seed ships the tier =="
ok "roleTiers.explorer"                   "$(jget "$SEED_CFG" roleTiers explorer)" light
ok "models maps that tier"                "$(jget "$SEED_CFG" models light)"       haiku
ok "explorer is NOT a task assignee"      \
  "$(python3 -c 'import json,sys;print("explorer" in json.load(open(sys.argv[1]))["roles"])' "$SEED_CFG")" False

echo "== the full path resolves offline, like any other agent =="
mkdir -p "$TMP/seeded"; cp "$SEED_CFG" "$TMP/seeded/instance.config.json"
ok "resolve-model.sh explorer"            "$(bash "$RESOLVE" explorer --instance "$TMP/seeded" 2>/dev/null)" haiku
ok "…and software-engineer, unchanged"    "$(bash "$RESOLVE" software-engineer --instance "$TMP/seeded" 2>/dev/null)" opus

echo "== the per-machine layer overrides it entry by entry =="
mkdir -p "$TMP/local"; cp "$SEED_CFG" "$TMP/local/instance.config.json"
printf '{ "roleTiers": { "explorer": "standard" } }\n' > "$TMP/local/instance.config.local.json"
ok "local roleTiers.explorer wins"        "$(bash "$RESOLVE" explorer --instance "$TMP/local" 2>/dev/null)" sonnet

echo "== an absent entry: nothing on stdout, exit 1, and it says why =="
mkdir -p "$TMP/bare"
python3 - "$SEED_CFG" "$TMP/bare/instance.config.json" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
cfg["roleTiers"].pop("explorer", None)
json.dump(cfg, open(sys.argv[2], "w"))
PY
OUT="$(bash "$RESOLVE" explorer --instance "$TMP/bare" 2>"$TMP/err")"; RC=$?
ok "exit code"                            "$RC"                     1
ok "stdout is empty"                      "${OUT:-<empty>}"         "<empty>"
ok "stderr names the agent"               "$(yn grep -q "explorer" "$TMP/err")" yes
ok "…the lookup that failed"              "$(yn grep -q 'roleTiers entry' "$TMP/err")" yes
ok "…and the consequence"                 "$(yn grep -q 'SESSION model' "$TMP/err")" yes

echo "== the fallback is written where the caller reads it =="
ok "CONVENTIONS: no entry => light"       "$(yn grep -q 'no entry ⇒ the seed' "$REPO/plugin/seed/conventions/repos.md")" yes
ok "PM brief resolves explorer"           "$(yn grep -q 'resolve-model.sh explorer' "$PM")" yes
ok "…and says light IS the default"       "$(yn grep -q 'seed default' "$PM")" yes

echo "== the rule replaced the codegraph-first advice =="
ok "one broad-read rule in CONVENTIONS"   "$(grep -c 'would take more than a few files' "$CONV")" 1
ok "no 'before bulk-grepping' advice"     "$(grep -c 'before bulk-grepping' "$CONV")" 0
ok "codegraph kept for blast radius"      "$(yn grep -q 'TypeScript blast radius' "$CONV")" yes

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
