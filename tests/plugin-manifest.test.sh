#!/usr/bin/env bash
#
# plugin-manifest.test.sh — the plugin packaging surface: both manifests, the skill
# files, and (when the CLI is present) `claude plugin validate --strict`.
#
# The failure this exists for: a manifest edit that parses as JSON but breaks install —
# a renamed field, a `source` path that resolves to nothing, a skill without the
# frontmatter the loader keys on. Each is pinned from both directions where a mutation
# is cheap to plant.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

PJ="$REPO/plugin/.claude-plugin/plugin.json"
MJ="$REPO/.claude-plugin/marketplace.json"

echo "== the two manifests parse, and their required fields hold =="
ok "plugin.json parses"        "$(jq empty "$PJ" >/dev/null 2>&1 && echo yes || echo no)" yes
ok "…name is loopd"            "$(jq -r .name "$PJ")" "loopd"
ok "…version is semver"        "$(jq -r .version "$PJ" | grep -cE '^[0-9]+\.[0-9]+\.[0-9]+$')" 1
ok "marketplace.json parses"   "$(jq empty "$MJ" >/dev/null 2>&1 && echo yes || echo no)" yes
ok "…names the owner"          "$(jq -r '.owner.name // empty' "$MJ" | grep -c .)" 1
ok "…lists the plugin first"   "$(jq -r '.plugins[0].name' "$MJ")" "$(jq -r .name "$PJ")"

echo "== the marketplace source resolves to the plugin it names =="
SRC="$(jq -r '.plugins[0].source' "$MJ")"
ok "source is a same-repo relative path" "$(printf '%s' "$SRC" | grep -c '^\./')" 1
ok "…and it resolves to a plugin manifest" \
   "$([ -f "$REPO/${SRC#./}/.claude-plugin/plugin.json" ] && echo yes || echo no)" yes
ok "…whose name matches the entry" \
   "$(jq -r .name "$REPO/${SRC#./}/.claude-plugin/plugin.json")" "$(jq -r '.plugins[0].name' "$MJ")"
ok "…and whose versions agree" \
   "$([ "$(jq -r .version "$PJ")" = "$(jq -r '.plugins[0].version' "$MJ")" ] && echo yes || echo no)" yes

echo "== the deprecation stub shipped for ONE version, and 1.0.0 removed it =="
# The transition name shipped for eight slices so a machine that installed it found out by
# NAME rather than by a command that quietly stopped resolving. It was always bounded at
# one version, and ai-bridge-v2/task-019 spent that bound.
#
# THE ASSERTION IS NOW ABSENCE, AND BOTH HALVES ARE NEEDED. A directory left behind with no
# marketplace entry is dead weight; an entry left behind with no directory is worse — the
# `source` resolves to nothing and `/plugin install ai-bridge-v2@ai-bridge` fails at the
# host rather than at a skill that could have explained itself. Removing one and forgetting
# the other is the only mistake available here, so each is pinned separately.
# path-scan: absent — asserted GONE on the next line
STUB="$REPO/plugin-deprecated"
ok "plugin-deprecated/ is gone"   "$([ -e "$STUB" ] && echo no || echo yes)" yes
ok "…and so is its marketplace entry" \
   "$(jq -r '[.plugins[].name] | index("ai-bridge-v2") | if . == null then "no" else "yes" end' "$MJ")" no
# Non-vacuity: the same lookup finds the entries that ARE listed, so "no" above is an
# answer about ai-bridge-v2 and not a jq expression that can only ever say no.
ok "…while the lookup still finds a name that IS listed" \
   "$(jq -r --arg n "$(jq -r .name "$PJ")" '[.plugins[].name] | index($n) | if . == null then "no" else "yes" end' "$MJ")" yes
# Every REMAINING source must still resolve — the other thing the removal could have
# broken, and the one a jq check on names alone cannot see. ONE SCANNER, RUN TWICE: over
# the real manifest, and over a planted source that points at the directory just deleted.
# A sweep that can only pass is not a sweep, and a `bad` count of 0 over an EMPTY source
# list is the vacuous form this one would decay into, so the count is asserted too.
unresolved() { # reads sources on stdin, prints how many resolve to no plugin manifest
  local s n=0
  while read -r s; do
    [ -n "$s" ] || continue
    [ -f "$REPO/${s#./}/.claude-plugin/plugin.json" ] || n=$((n+1))
  done
  printf '%s' "$n"
}
srcs="$(jq -r '.plugins[].source' "$MJ")"
ok "every marketplace source resolves to a plugin manifest" \
   "$(printf '%s\n' "$srcs" | unresolved)" 0
ok "…over at least the two entries that are left (the sweep is not vacuous)" \
   "$([ "$(printf '%s\n' "$srcs" | grep -c . | tr -d ' ')" -ge 2 ] && echo yes || echo no)" yes
# The same scanner, on the source the removed entry carried. It must come back 1.
ok "…and that same scanner flags the source the stub entry used to carry" \
   "$(printf './plugin-deprecated\n' | unresolved)" 1

echo "== the ai-bridge alias is a stub for one release, never a second core =="
# loopd/task-007. The old name stays listed so `ai-bridge@ai-bridge` still resolves, but
# from its OWN source: a second ./plugin entry would register every hook twice on a machine
# mid-migration, and release-bump.sh refuses a marketplace with two ./plugin entries.
ASRC="$(jq -r '.plugins[] | select(.name=="ai-bridge") | .source' "$MJ")"
ADESC="$(jq -r '.plugins[] | select(.name=="ai-bridge") | .description' "$MJ")"
ok "the marketplace lists an ai-bridge entry"   "$([ -n "$ASRC" ] && echo yes || echo no)" yes
ok "…from its own source, not ./plugin"         "$([ -n "$ASRC" ] && [ "$ASRC" != ./plugin ] && echo yes || echo no)" yes
ok "…whose manifest is named ai-bridge" \
   "$(jq -r .name "$REPO/${ASRC#./}/.claude-plugin/plugin.json" 2>/dev/null)" ai-bridge
ok "…and ships no hooks and no agents" \
   "$([ -e "$REPO/${ASRC#./}/hooks" ] || [ -e "$REPO/${ASRC#./}/agents" ] && echo no || echo yes)" yes
ok "…its description says it is an alias"       "$(printf '%s' "$ADESC" | grep -c 'ALIAS')" 1
ok "…and points at MIGRATION.md, which exists" \
   "$(grep -q 'MIGRATION.md' <<<"$ADESC" && [ -f "$REPO/MIGRATION.md" ] && echo yes || echo no)" yes
ok "exactly one entry is sourced from ./plugin" \
   "$(jq '[.plugins[] | select(.source=="./plugin")] | length' "$MJ")" 1

echo "== every skill has the frontmatter the loader keys on =="
n=0
for sk in "$REPO"/plugin/skills/*/SKILL.md; do
  [ -f "$sk" ] || continue
  n=$((n+1))
  base="$(basename "$(dirname "$sk")")"
  ok "$base: has a description" "$(awk '/^---$/{c++} c==1 && /^description:/{print "yes"; exit}' "$sk")" yes
done
ok "at least the two launch skills exist (scan not vacuous)" "$([ "$n" -ge 2 ] && echo yes || echo no)" yes

echo "== .claude-plugin/ holds ONLY its manifest (the documented layout rule) =="
ok "plugin/.claude-plugin has one entry" "$(ls -A "$REPO/plugin/.claude-plugin" | wc -l | tr -d ' ')" 1
ok "root .claude-plugin has one entry"   "$(ls -A "$REPO/.claude-plugin" | wc -l | tr -d ' ')" 1

echo "== the CLI's own validator, when present =="
# AB_TIER=gate is tests/run.sh saying "this run is the merge gate" — no harness spawns the
# claude CLI there. Absent (a by-hand run), the tier is deep and the validator runs.
if [ "${AB_TIER:-deep}" = deep ] && command -v claude >/dev/null 2>&1; then
  out="$(claude plugin validate "$REPO/plugin" --strict 2>&1)"; rc=$?
  ok "claude plugin validate --strict passes" "$rc" 0
  # On failure, the validator's own diagnostics are the finding — "got 1, want 0"
  # alone names no field.
  if [ "$rc" -ne 0 ]; then printf '%s\n' "$out" | sed 's/^/        | /'; fi
else
  echo "  SKIP  claude CLI not spawned here (tier=${AB_TIER:-deep}) — jq checks above still hold"
fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
