#!/usr/bin/env bash
#
# skill-schema-precondition.test.sh — a skill's instance-root precondition names the RESOLVED
# schema path (bundle-paths.sh AB_SCHEMA), never a bare SCHEMA.md in the cwd, which a migrated
# bundle does not have. A skill added later with the bare form turns this red.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (got $2, want $3)"; fi; }

PRE='[Rr]un from a control-panel instance root|Confirm you are at an instance root|[Mm]ust run from a \*\*control-panel instance root'
RESOLVED='scripts/bundle-paths\.sh AB_SCHEMA'
n=0
for f in "$REPO"/plugin/skills/*/SKILL.md; do
  s="$(basename "$(dirname "$f")")"
  grep -Eq "$PRE" "$f" || continue
  n=$((n+1))
  # A precondition that never mentions SCHEMA.md (handoff) has nothing to resolve.
  if grep -E -A3 "$PRE" "$f" | grep -q 'SCHEMA\.md'; then
    ok "$s: names the resolved schema path" "$(grep -Eq "$RESOLVED" "$f" && echo yes || echo no)" yes
  fi
  ok "$s: no bare cwd SCHEMA.md" \
    "$(grep -Ec 'SCHEMA\.md` (\+|and) `instance\.config\.json`|`instance\.config\.json` (\+|and) `SCHEMA\.md`' "$f")" 0
  tools="$(awk '/^---$/{d++;next} d==1 && /^allowed-tools:/' "$f")"
  if [ -n "$tools" ]; then
    ok "$s: grants bundle-paths.sh" "$(grep -q 'scripts/bundle-paths\.sh:\*' <<<"$tools" && echo yes || echo no)" yes
  fi
done
ok "found the preconditioned skills (at least 7)" "$([ "$n" -ge 7 ] && echo yes || echo no)" yes
echo "$pass passed, $fail failed ($n skills)"
[ "$fail" -eq 0 ]
