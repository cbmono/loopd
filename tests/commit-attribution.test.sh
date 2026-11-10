#!/usr/bin/env bash
#
# commit-attribution.test.sh — the `Co-Authored-By: Claude` trailer is the DEFAULT on a
# target-repo commit, and `commitAttribution: none` is the only thing that removes it.
#
# WHY THE BRIEF AND NOT THE PROSE. "the agent honours the setting" is unassertable while
# the setting lives only in an instruction; what IS assertable is that the generated
# dispatch brief carries the resolved value, so every criterion below is a string
# comparison on `dispatch-brief.sh` stdout over a fixture bundle. Same argument as
# dispatch-brief.test.sh, which pins the other two sections.
#
# NON-VACUOUS BY CONSTRUCTION: the absent-key, tracked-`none` and local-overrides-tracked
# bundles differ ONLY in their config files, so a script that stopped reading the key
# would flip a verdict rather than print a different shape.
#
# Reasoning: /projects/ai-bridge-next/tasks/task-031-*.md.
# ok() compares actual to expected, as everywhere else in this directory.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BRIEF="$REPO/plugin/scripts/dispatch-brief.sh"
SEED_CFG="$REPO/plugin/seed/instance.config.json"
COMMIT_AS="$REPO/plugin/scripts/commit-as.sh"
CONV="$REPO/plugin/seed/CONVENTIONS.md"
SEED_CLAUDE="$REPO/plugin/seed/CLAUDE.md"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
PM="$REPO/plugin/tick-steps/step-3-dispatch.md"
for f in "$BRIEF" "$SEED_CFG" "$COMMIT_AS" "$CONV" "$SEED_CLAUDE" "$SCHEMA" "$PM"; do
  [ -f "$f" ] || { echo "commit-attribution.test: $f not found" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || { echo "commit-attribution.test: python3 required" >&2; exit 2; }

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-56s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-56s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { "$@" >/dev/null 2>&1 && echo yes || echo no; }
count() { grep -cF -e "$1" "$2"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/commit-attribution.XXXXXX")" || {
  echo "commit-attribution.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# <bundle> [tracked-value] [local-value] — a bundle whose ONLY variable is the key.
bundle() {
  local d="$TMP/$1" tracked="${2-}" local_v="${3-}"
  mkdir -p "$d/projects/demo/tasks"
  if [ -n "$tracked" ]; then
    printf '{ "org": "acme", "commitAttribution": "%s" }\n' "$tracked" > "$d/instance.config.json"
  else
    printf '{ "org": "acme" }\n' > "$d/instance.config.json"
  fi
  [ -n "$local_v" ] &&
    printf '{ "commitAttribution": "%s" }\n' "$local_v" > "$d/instance.config.local.json"
  { printf -- '---\ntype: Task\ntitle: "Ship the widget"\nkind: build\n'
    printf 'target_repo: acme/widget\nstatus: ready\n'
    printf 'acceptance_criteria: [ "one" ]\ntimestamp: 2026-01-01T00:00:00Z\n---\n\n# Context\n\nX.\n'
  } > "$d/projects/demo/tasks/task-001.md"
  printf '%s' "$d"
}
# The `## Commit attribution` body, blank lines dropped.
section() { awk '/^## Commit attribution$/{f=1;next} f&&/^## /{exit} f&&NF' <<<"$1"; }
brief() { bash "$BRIEF" "$1/projects/demo/tasks/task-001.md" 2>/dev/null; }

echo "== the seed ships the key, present and documenting itself in one comment line =="
ok "seed value" \
  "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("commitAttribution"))' "$SEED_CFG")" claude
ok "\$commitAttribution is one line"  "$(grep -c '"\$commitAttribution":' "$SEED_CFG")" 1
ok "…and names the opt-out"          "$(yn grep -q '`none` is the opt-out' "$SEED_CFG")" yes

echo "== the brief carries the resolved value — absent key resolves to claude =="
D="$(bundle absent)"
BODY="$(section "$(brief "$D")")"
ok "the section exists"              "$(yn grep -q '^## Commit attribution$' <<<"$(brief "$D")")" yes
ok "absent ⇒ claude"                 "$(yn grep -q '^commitAttribution: claude' <<<"$BODY")" yes
ok "…and names the trailer"          "$(yn grep -q 'Co-Authored-By: Claude' <<<"$BODY")" yes

echo "== tracked none switches it off, trailer and session URL both =="
D="$(bundle off none)"
BODY="$(section "$(brief "$D")")"
ok "tracked none ⇒ none"             "$(yn grep -q '^commitAttribution: none' <<<"$BODY")" yes
ok "no trailer is named"             "$(yn grep -q 'Co-Authored-By' <<<"$BODY")" no
ok "…and no session URL"             "$(yn grep -q 'NO session URL' <<<"$BODY")" yes

echo "== the local layer wins, in both directions =="
D="$(bundle localoff claude none)"
ok "local none over tracked claude"  "$(yn grep -q '^commitAttribution: none' <<<"$(section "$(brief "$D")")")" yes
D="$(bundle localon none claude)"
ok "local claude over tracked none"  "$(yn grep -q '^commitAttribution: claude' <<<"$(section "$(brief "$D")")")" yes

echo "== an unrecognised value is the documented default, never a silent third mode =="
D="$(bundle typo None)"
ok "'None' ⇒ claude"                 "$(yn grep -q '^commitAttribution: claude' <<<"$(section "$(brief "$D")")")" yes

echo "== the seed prose no longer forbids it =="
ok "CONVENTIONS: no 'no AI attribution'"  "$(count 'no AI attribution' "$CONV")" 0
ok "CLAUDE.md: no 'No AI attribution'"    "$(count 'No AI attribution' "$SEED_CLAUDE")" 0
ok "CLAUDE.md: 'many forbid' is gone"     "$(count 'many forbid AI attribution' "$SEED_CLAUDE")" 0
ok "CONVENTIONS states the default"       "$(yn grep -q 'trailer stays, because it is' "$CONV")" yes
ok "…and that the brief decides"          "$(yn grep -q '## Commit attribution' "$CONV")" yes
ok "CLAUDE.md keeps the invariant"        "$(yn grep -q 'Keep the `Co-Authored-By: Claude` trailer' "$SEED_CLAUDE")" yes
ok "SCHEMA lists the override"            "$(yn grep -q '| `commitAttribution` | \*\*yes\*\*' "$SCHEMA")" yes
ok "PM pastes the third heading"          "$(yn grep -q '`## Commit attribution`' "$PM")" yes

echo "== commit-as.sh is untouched: bundle commits, role author, no trailer, ever =="
ok "it adds no Co-Authored-By"        "$(count 'Co-Authored-By' "$COMMIT_AS")" 0
ok "…and does not read the key"       "$(count 'commitAttribution' "$COMMIT_AS")" 0

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
