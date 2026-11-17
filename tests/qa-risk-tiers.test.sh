#!/usr/bin/env bash
#
# qa-risk-tiers.test.sh — plugin/agents/qa-reviewer.md mode B names three risk tiers (UI,
# behaviour-changing, small) in that match order, each row carrying its pick rule and the
# evidence it requires, and execution evidence before a diff read. Tiering redirects QA
# effort, so the budget keys in plugin/seed/instance.config.json are pinned unchanged.
# Text and jq only: no git, no network.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
QA="$REPO/plugin/agents/qa-reviewer.md"
CFG="$REPO/plugin/seed/instance.config.json"
pass=0; fail=0
ok() { # <label> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s (want %s, got %s)\n' "$1" "$3" "$2"; fail=$((fail+1)); fi; }

row() { grep -E "^[[:space:]]*\| \*\*$2\*\* \|" "$1"; }
row_has() { row "$1" "$2" | grep -qF -- "$3" && echo yes || echo no; }
line_of() { local n; n="$(grep -nE "^[[:space:]]*\| \*\*$2\*\* \|" "$1" | head -1 | cut -d: -f1)"; echo "${n:-0}"; }

check() { # <file> — every assertion on one copy of qa-reviewer.md
  local f="$1" u b s
  for t in UI behaviour-changing small; do
    ok "one '$t' tier row" "$(row "$f" "$t" | wc -l | tr -d ' ')" 1
  done
  u="$(line_of "$f" UI)"; b="$(line_of "$f" behaviour-changing)"; s="$(line_of "$f" small)"
  ok "tiers match in order UI, behaviour-changing, small" \
     "$([ "$u" -gt 0 ] && [ "$u" -lt "$b" ] && [ "$b" -lt "$s" ] && echo yes || echo no)" yes
  ok "UI is picked by ui: true"                 "$(row_has "$f" UI '`ui: true`')" yes
  ok "UI is picked by uiGlobs"                  "$(row_has "$f" UI '`uiGlobs`')" yes
  ok "UI takes the screenshots as review input" "$(row_has "$f" UI "the PR's screenshots are the review input")" yes
  ok "UI checks one per changed screen"         "$(row_has "$f" UI 'one per changed screen')" yes
  ok "behaviour-changing is picked past 100 lines" "$(row_has "$f" behaviour-changing '**100** changed lines')" yes
  ok "behaviour-changing is picked by runtime behaviour" "$(row_has "$f" behaviour-changing 'a criterion changes runtime behaviour')" yes
  ok "behaviour-changing runs the suite and app path" \
     "$(row_has "$f" behaviour-changing 'run the affected suite and the app path the diff touches')" yes
  ok "small runs tests and re-derives the table" \
     "$(row_has "$f" small 'run the change'"'"'s tests and re-derive the criteria table')" yes
  ok "small states it keeps the cheap second opinion" \
     "$(row_has "$f" small "Keeps step 4's cheap second opinion")" yes
  ok "execution evidence comes before a diff read" \
     "$(grep -qF 'Execution evidence comes before a diff read, in every tier.' "$f" && echo yes || echo no)" yes
}

echo "== qa-reviewer.md names three risk tiers =="
check "$QA"

echo "== a copy missing a tier fails =="
TMP="$(mktemp -d "${TMPDIR:-/tmp}/qatiers.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
grep -vE '^[[:space:]]*\| \*\*small\*\* \|' "$QA" > "$TMP/qa.md"
p0=$pass; f0=$fail; check "$TMP/qa.md" >/dev/null; refused="$([ "$fail" -gt "$f0" ] && echo yes || echo no)"
pass=$p0; fail=$f0
ok "the mutated copy is refused" "$refused" yes

echo "== the QA budget is unchanged =="
ok "roleTiers.qa-reviewer is apex" "$(jq -r '.roleTiers["qa-reviewer"]' "$CFG")" apex
ok "qaRounds is 1"                 "$(jq -r '.qaRounds' "$CFG")" 1
ok "coderabbitRounds is 1"         "$(jq -r '.coderabbitRounds' "$CFG")" 1

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
