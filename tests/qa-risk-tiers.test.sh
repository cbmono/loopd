#!/usr/bin/env bash
#
# qa-risk-tiers.test.sh — plugin/agents/qa-reviewer.md mode B names three risk tiers (UI,
# behaviour-changing, small) in that match order, each row carrying its pick rule and the
# evidence it requires in its own column, first match winning, and execution evidence
# before a diff read; each mutated copy proves an assertion can fail. Tiering redirects
# QA effort, so the budget keys in plugin/seed/instance.config.json are pinned unchanged.
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
col() { row "$1" "$2" | awk -F'|' -v c="$3" '{ v=$c; sub(/^ +/, "", v); sub(/ +$/, "", v); print v }'; }
pick_has() { grep -qF -- "$3" <<<"$(col "$1" "$2" 3)" && echo yes || echo no; }
evid_has() { grep -qF -- "$3" <<<"$(col "$1" "$2" 4)" && echo yes || echo no; }
line_of() { local n; n="$(grep -nE -m1 "^[[:space:]]*\| \*\*$2\*\* \|" "$1")"; n="${n%%:*}"; echo "${n:-0}"; }

check() { # <file> — every assertion on one copy of qa-reviewer.md
  local f="$1" u b s
  for t in UI behaviour-changing small; do
    ok "one '$t' tier row" "$(row "$f" "$t" | wc -l | tr -d ' ')" 1
  done
  u="$(line_of "$f" UI)"; b="$(line_of "$f" behaviour-changing)"; s="$(line_of "$f" small)"
  ok "tiers match in order UI, behaviour-changing, small" \
     "$([ "$u" -gt 0 ] && [ "$u" -lt "$b" ] && [ "$b" -lt "$s" ] && echo yes || echo no)" yes
  ok "the first matching tier wins" \
     "$(grep -qF 'First match wins:' "$f" && echo yes || echo no)" yes
  ok "UI is picked by ui: true"                 "$(pick_has "$f" UI '`ui: true`')" yes
  ok "UI is picked by uiGlobs"                  "$(pick_has "$f" UI '`uiGlobs`')" yes
  ok "UI takes the screenshots as review input" "$(evid_has "$f" UI "the PR's screenshots are the review input")" yes
  ok "UI reads screenshots from the project"    "$(evid_has "$f" UI '`projects/<slug>/deliverables/local/`')" yes
  ok "UI checks one per changed screen"         "$(evid_has "$f" UI 'one per changed screen')" yes
  ok "behaviour-changing is picked past 100 lines" \
     "$(pick_has "$f" behaviour-changing 'the diff exceeds **100** changed lines')" yes
  ok "behaviour-changing is picked by runtime behaviour" \
     "$(pick_has "$f" behaviour-changing 'a criterion changes runtime behaviour')" yes
  ok "behaviour-changing runs the suite and app path" \
     "$(evid_has "$f" behaviour-changing 'run the affected suite and the app path the diff touches')" yes
  ok "small is picked only when neither matched" "$(col "$f" small 3)" neither
  ok "small runs tests and re-derives the table" \
     "$(evid_has "$f" small 'run the change'"'"'s tests and re-derive the criteria table')" yes
  ok "small states it keeps the cheap second opinion" \
     "$(evid_has "$f" small "Keeps step 4's cheap second opinion")" yes
  ok "step 4 runs in every tier" "$(evid_has "$f" small 'step 4 runs unchanged in every tier')" yes
  ok "execution evidence comes before a diff read" \
     "$(grep -qF 'Execution evidence comes before a diff read, in every tier.' "$f" && echo yes || echo no)" yes
}

echo "== qa-reviewer.md names three risk tiers =="
check "$QA"

echo "== a mutated copy fails =="
TMP="$(mktemp -d "${TMPDIR:-/tmp}/qatiers.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
refused() { # <label> <sed expression>
  local p0=$pass f0=$fail r
  sed -E "$2" "$QA" > "$TMP/qa.md"
  check "$TMP/qa.md" >/dev/null; r="$([ "$fail" -gt "$f0" ] && echo yes || echo no)"
  pass=$p0; fail=$f0
  ok "refused: $1" "$r" yes
}
refused "the small row is missing"          '/^[[:space:]]*\| \*\*small\*\* \|/d'
refused "First match wins is deleted"       's/First match wins://'
refused "small is picked always"            's/^([[:space:]]*\| \*\*small\*\* \| )neither /\1always /'
refused "behaviour-changing is under 100"   's/exceeds \*\*100\*\*/is under **100**/'
refused "ui: true moved to the evidence"    's/the task sets `ui: true`, or //; s/(review input\*\*)/\1 `ui: true`/'
refused "screenshots under the bundle root" "s/the project's \`projects\/<slug>\/deliverables\/local\/\`/the bundle's \`deliverables\/local\/\`/"

echo "== the QA budget is unchanged =="
ok "roleTiers.qa-reviewer is apex" "$(jq -r '.roleTiers["qa-reviewer"]' "$CFG")" apex
ok "qaRounds is 1"                 "$(jq -r '.qaRounds' "$CFG")" 1
ok "coderabbitRounds is 1"         "$(jq -r '.coderabbitRounds' "$CFG")" 1

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
