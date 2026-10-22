#!/usr/bin/env bash
#
# papercuts-upstream.test.sh — a papercut pass completes when its proposals target loopd
# plugin surfaces: the classifier resolves names, the writers refuse an empty edit, `pass`
# is held until each plugin surface has an upstream row, and the four sites state one rule.
#
# ok() follows this directory's convention: it compares actual to expected.
# Reasoning: kb-retrieval-and-papercut-fixes/task-001.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PC="$REPO/plugin/scripts/papercuts.sh"
VALIDATOR="$REPO/plugin/scripts/validate-bundle.sh"
SKILL="$REPO/plugin/skills/close-project/SKILL.md"
SITES="$REPO/plugin/tick-steps/step-7-knowledge-base.md $REPO/plugin/agents/project-manager.md
$REPO/plugin/agents/cataloguer.md $SKILL"
[ -x "$PC" ] || { echo "papercuts-upstream.test: missing or not executable: $PC" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/papercuts-up.XXXXXX")" \
  || { echo "papercuts-upstream.test: could not create a temp dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PLUGIN_ROOT="$REPO/plugin"

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-60s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-60s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
rc() { "$@" >/dev/null 2>&1; echo $?; }
up() { bash "$PC" "$@" --date 2026-09-05; }

echo "== 1. the classifier resolves the name in the installed plugin; the prefix never decides =="
for row in script:validate-bundle.sh=plugin script:package.json=instance agent:project-manager=plugin \
           skill:close-project=plugin agent:no-such-agent=instance skill:no-such-skill=instance \
           script:../scripts/papercuts.sh=instance; do
  ok "${row%=*}" "$(bash "$PC" classify --surface "${row%=*}")" "${row#*=}"
done
mkdir -p "$TMP/bare/scripts"
ok "a plugin without the file calls the same name instance" \
  "$(CLAUDE_PLUGIN_ROOT="$TMP/bare" bash "$PC" classify --surface script:validate-bundle.sh)" instance

mkdir -p "$TMP/link/loopd" && ln -s "$REPO/plugin/scripts" "$TMP/link/loopd/bin"
ok "through a linked scripts dir, with no CLAUDE_PLUGIN_ROOT" \
  "$(env -u CLAUDE_PLUGIN_ROOT bash "$TMP/link/loopd/bin/papercuts.sh" classify --surface script:validate-bundle.sh)" plugin

echo
echo "== 2. a fixture bundle whose proposals all target plugin surfaces =="
B="$TMP/bundle"; mkdir -p "$B/knowledge" "$B/projects" && cd "$B" || exit 2
echo '{ "org": "x", "reposRoot": "/tmp" }' > instance.config.json
REC="knowledge/papercuts.md"; UP=".loopd/upstream-proposals.md"
bash "$PC" add --task p/t-1 --surface script:validate-bundle.sh --note 'exits 0 on an unreadable file' --date 2026-09-01 >/dev/null
bash "$PC" add --task p/t-2 --surface agent:project-manager --note 'drafts nothing for a plugin surface' --date 2026-09-02 >/dev/null
printf '2026-09-02 | p/t-3 | rule:no-such-kind | a hand-written line the shape refuses\n' >> "$REC"

err="$(up pass 2>&1 >/dev/null)"; code=$?
ok "pass is refused with two pending plugin surfaces"     "$code" 1
ok "…writes no marker"                                    "$(grep -c '<!-- pass' "$REC")" 0
ok "…and names both surfaces" \
  "$(grep -c 'script:validate-bundle.sh' <<<"$err")$(grep -c 'agent:project-manager' <<<"$err")" 11
ok "report counts the malformed line on its own figure"  "$(bash "$PC" report | grep -c '2 entries · 2 surfaces · 1 malformed')" 1
ok "…and never classifies it"                             "$(bash "$PC" report | grep -c 'rule:')" 0

echo
echo "== 3. the writers refuse an empty edit, and write nothing =="
ok "propose with no --edit"                 "$(rc up propose --surface script:validate-bundle.sh)" 1
ok "propose with an empty --edit"           "$(rc up propose --surface script:validate-bundle.sh --edit '  ')" 1
ok "dismiss with no --reason"               "$(rc up dismiss --surface agent:project-manager)" 1
ok "dismiss with an empty --reason"         "$(rc up dismiss --surface agent:project-manager --reason '')" 1
ok "propose for an instance-owned surface"  "$(rc up propose --surface script:package.json --edit 'add a lint script')" 1
ok "dismiss for an instance-owned surface"  "$(rc up dismiss --surface script:package.json --reason 'not ours')" 1
ok "…no refusal created the upstream file"  "$(yn test -e "$UP")" no
ok "…and pass is still refused"             "$(rc up pass)" 1

echo
echo "== 4. pass only after the write =="
ok "a proposal row is written"              "$(rc up propose --surface script:validate-bundle.sh --edit 'line 41: exit 2 when a ref is unreadable')" 0
err="$(up pass 2>&1 >/dev/null)"; code=$?
ok "…pass is still refused for the other"   "$code" 1
ok "…naming only that one" \
  "$(grep -c 'agent:project-manager' <<<"$err")$(grep -c 'script:validate-bundle.sh' <<<"$err")" 10
ok "a row dated BEFORE the entry does not count" \
  "$(bash "$PC" dismiss --surface agent:project-manager --reason 'an old dismissal' --date 2026-09-01 >/dev/null 2>&1; rc up pass)" 1
ok "a dismissed row is written"             "$(rc up dismiss --surface agent:project-manager --reason 'no longer reproduces on 3.12')" 0
ok "…and now pass marks the record"         "$(rc up pass)" 0
ok "the marker carries the malformed figure" \
  "$(grep -c '^<!-- pass 2026-09-05 — 2 entries, 2 surfaces, 1 malformed -->$' "$REC")" 1
ok "every upstream row has the SCHEMA shape" \
  "$(awk '/^## Entries/{f=1;next} f&&NF' "$UP" | grep -cvE '^[0-9]{4}-[0-9]{2}-[0-9]{2} \| (skill|agent|script):[^|]+ \| (proposal|dismissed) \| .+$')" 0
ok "…three rows, appended" \
  "$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2} \|' "$UP")" 3
ok "validate-bundle.sh reports 0 errors on the bundle holding it" \
  "$(bash "$VALIDATOR" 2>&1 | grep -cE '^[[:space:]]*ERROR')" 0
ok "…and exits 0"                           "$(rc bash "$VALIDATOR")" 0

echo
echo "== 5. a malformed or instance-only record neither blocks nor needs the file =="
M="$TMP/malformed"; mkdir -p "$M/knowledge" && cd "$M" || exit 2
printf '# Papercuts\n\n## Entries\n\n2026-09-02 | p/t | rule:x | a malformed line on its own here\n' > "$REC"
ok "one malformed line: pass is not refused" "$(rc up pass)" 0
ok "…and the marker says 1 malformed"        "$(grep -c '0 entries, 0 surfaces, 1 malformed' "$REC")" 1
bash "$PC" add --task p/t --surface script:package.json --note 'an instance surface papercut' --date 2026-09-06 >/dev/null
ok "an instance-only entry: pass is not refused" "$(rc bash "$PC" pass --date 2026-09-07)" 0
ok "…and no upstream file was needed"        "$(yn test -e "$UP")" no

echo
echo "== 6. one rule, four sites =="
norm() { tr '\n' ' ' < "$1" | tr -s ' '; }
RULE='an instance-owned surface becomes a `draft` task in its owning project; a loopd plugin surface is written to `.loopd/upstream-proposals.md` instead'
SIDE='`pass` checks only the plugin side; the drafts are'
states() { local t; t="$(norm "$1")"; grep -qF "$RULE" <<<"$t" && grep -qF "$SIDE" <<<"$t"; }
for f in $SITES; do ok "${f#"$REPO"/} states the rule" "$(yn states "$f")" yes; done
sed 's/a loopd plugin surface is written/a plugin surface goes/' "$SKILL" > "$TMP/dropped.md"
ok "…and a site that drops it fails the row"   "$(yn states "$TMP/dropped.md")" no
ok "close-project names the refused-pass branch" \
  "$(norm "$SKILL" | grep -cF 'If `pass` exits 1, closeout continues without a marker')" 1
ok "…logs the refused surfaces"               "$(norm "$SKILL" | grep -cF '`papercuts pass refused: <surfaces>`')" 1
ok "…and calls the writers in the granted form" \
  "$(grep -cE '^   bash \$\{CLAUDE_PLUGIN_ROOT\}/scripts/papercuts\.sh (propose|dismiss) ' "$SKILL")" 2
ok "the path is one constant in bundle-paths.sh" \
  "$("$REPO/plugin/scripts/bundle-paths.sh" AB_UPSTREAM)" .loopd/upstream-proposals.md
ok "SCHEMA.md defines both row shapes" \
  "$(grep -cE '^DATE \| KIND:NAME \| (proposal \| <concrete edit>|dismissed \| <reason>)$' "$REPO/plugin/seed/SCHEMA.md")" 2

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
