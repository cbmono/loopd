#!/usr/bin/env bash
#
# seed-conflict-resolution.test.sh — the decidable conflict classes, and the one command
# that runs them. ai-bridge-2x/task-004.
#
# A conflict that recurs on every bundle with the same answer is a rule, not a question.
# So: each class in `plugin/scripts/refresh-seeds.sh`'s DECIDABLE table is pinned against
# a fixture, an undecidable hunk in the SAME file must still reach the human, and the
# bundle tree must gain no `.bak` at all. Plus the two pointers criterion 6/7 name:
# `/<plugin>:init` runs the check-and-fix pass itself, and `welcome fix` points at it.
#
# The fixture builds its own template in a temp git repo — its own controlled seed
# content — so these assertions describe this test's edits and not today's real seed.
# assert() follows the convention of the other harnesses here: 0 is a PASS.
set -euo pipefail

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
REPO="$HERE/.."
[ -f "$REPO/plugin/scripts/refresh-seeds.sh" ] || {
  echo "seed-conflict-resolution.test: no plugin/scripts/refresh-seeds.sh at $REPO" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/seed-conflict.XXXXXX")" || {
  echo "seed-conflict-resolution.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
assert() { if [ "$2" = 0 ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
has()    { grep -q <<<"$2" -- "$1" && echo 0 || echo 1; }
hasnt()  { grep -q <<<"$2" -- "$1" && echo 1 || echo 0; }
gc() { git -c user.email=a@b -c user.name=a commit -qm "$1"; }

# ------------------------------------------------------------- the template, seed v1
TPL="$TMP/tpl"
mkdir -p "$TPL/plugin/scripts"
for f in init-bundle.sh refresh-seeds.sh validate-bundle.sh ai-bridge.sh build-kb-index.sh \
         check-template-version.sh normalise-config.sh link-repos.sh tick-lock.sh \
         bundle-paths.sh; do
  cp "$REPO/plugin/scripts/$f" "$TPL/plugin/scripts/"
done
cp -R "$REPO/plugin/seed" "$TPL/plugin/seed"
cp -R "$REPO/plugin/hooks" "$TPL/plugin/hooks"
cp "$REPO/VERSION" "$TPL/plugin/VERSION"
cp "$REPO/VERSION" "$TPL/VERSION"

# Controlled seed content for the two decidable classes plus one undecidable file.
printf 'node_modules/\n/board.html\n/%s\n' "$AB_LOCK"             > "$TPL/plugin/seed/.gitignore"
printf '# Panel\nintro line\ntail line\n'                           > "$TPL/plugin/seed/CLAUDE.md"
( cd "$TPL" && git init -q -b main . && git add -A && gc "template, seed v1" )

REFRESH="$TPL/plugin/scripts/refresh-seeds.sh"

echo "== the DECIDABLE table is the script's own, and it is enumerable =="
TABLE="$(bash "$REFRESH" --list-decidable)"
assert "knowledge/index.md is a decidable class"  "$(has 'knowledge/index.md' "$TABLE")"
assert "…with build-kb-index.sh named as its rule" "$(has 'build-kb-index.sh' "$TABLE")"
assert ".gitignore is a decidable class"          "$(has '.gitignore' "$TABLE")"
assert "…with the seed-side rule named"           "$(has 'take the seed side' "$TABLE")"
assert "…and every bundle-added line kept"        "$(has 'bundle-added line is kept' "$TABLE")"
assert "CLAUDE.md is a decidable class"           "$(has 'CLAUDE.md' "$TABLE")"
assert "…named instance-additions"                "$(has 'instance-additions' "$TABLE")"
assert "…with the markdown heading spelled out"   "$(has 'kept across seed refreshes' "$TABLE")"

# ------------------------------------------------------------- a bundle, stamped
INST="$TMP/group/_ai-bridge-fixture"
mkdir -p "$INST"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST" > "$TMP/stamp1.out" 2>&1
( cd "$INST" && git init -q -b main . && git add -A && gc "bundle init" )

# The bundle's own edits, three shapes:
#   .gitignore        — a seed-managed line CHANGED and a bundle line added  ⇒ decidable
#   knowledge/index.md — a hand-written stub, while the KB has documents     ⇒ decidable
#   CLAUDE.md         — the same line the seed is about to change            ⇒ undecidable
assert "the keep directory is gitignored by the stamp" \
  "$(yes_if git -C "$INST" check-ignore -q .ai-bridge/refresh/CLAUDE.md.1)"
assert "…while the stamped-seed record stays tracked" \
  "$(git -C "$INST" check-ignore -q .ai-bridge/seed-base/CLAUDE.md && echo 1 || echo 0)"
printf 'node_modules/\n!/board.html\n/%s\nMY-OWN-IGNORE\n' "$AB_LOCK" > "$INST/.gitignore"
mkdir -p "$INST/knowledge/findings"
printf -- '---\ntype: Finding\ntitle: F1\nstatus: current\nlesson: a lesson\ntimestamp: 2026-01-01T00:00:00Z\n---\nbody\n' \
  > "$INST/knowledge/findings/f1.md"
printf '# Knowledge\n\na hand-written stub nobody derived\n' > "$INST/knowledge/index.md"
sed 's/^intro line$/intro line — HOUSE EDIT/' "$INST/CLAUDE.md" > "$TMP/c" && mv "$TMP/c" "$INST/CLAUDE.md"
cp "$INST/CLAUDE.md" "$TMP/claude.pristine"

# ------------------------------------------------------------- the template, seed v2
printf 'node_modules/\n# derived, never tracked\n/board.html\n/%s/\n/%s\n' "$AB_BOARD_DIR" "$AB_LOCK" > "$TPL/plugin/seed/.gitignore"
sed 's/^intro line$/intro line — TEMPLATE V2/' "$TPL/plugin/seed/CLAUDE.md" > "$TMP/c" \
  && mv "$TMP/c" "$TPL/plugin/seed/CLAUDE.md"
( cd "$TPL" && git add -A && gc "template, seed v2" )

echo "== report mode names the decidable classes and writes nothing =="
REPORT="$(bash "$REFRESH" "$INST" 2>&1)"
assert ".gitignore is reported DECIDABLE"      "$(has 'DECIDABLE .gitignore' "$REPORT")"
assert "…with the rule named"                 "$(has 'take the seed side' "$REPORT")"
assert "knowledge/index.md is reported DECIDABLE" "$(has 'DECIDABLE knowledge/index.md' "$REPORT")"
assert "…with the rule named"                 "$(has 'build-kb-index.sh' "$REPORT")"
assert "the summary counts them apart from ported and conflicting" \
  "$(has '2 decidable, 1 conflicting' "$REPORT")"
assert "…and a report run wrote nothing"      "$(yes_if grep -q '^MY-OWN-IGNORE$' "$INST/.gitignore")"
assert "…and left the stub index alone"       "$(yes_if grep -q 'hand-written stub' "$INST/knowledge/index.md")"

echo "== an undecidable hunk is still the human's, in both modes =="
assert "CLAUDE.md is reported CONFLICT"       "$(has 'CONFLICT  CLAUDE.md' "$REPORT")"
assert "…and it is what is left for the human" "$(has 'port the seed change into CLAUDE.md' "$REPORT")"

echo "== --apply resolves the decidable classes and reports RESOLVED =="
APPLY_RC=0
APPLY="$(bash "$REFRESH" "$INST" --apply 2>&1)" || APPLY_RC=$?
assert "--apply exits 0"                      "$([ "$APPLY_RC" -eq 0 ] && echo 0 || echo 1)"
assert ".gitignore is reported RESOLVED"      "$(has 'RESOLVED  .gitignore' "$APPLY")"
assert "…naming the rule that decided it"     "$(has 'take the seed side' "$APPLY")"
assert "…the seed's side of the conflicting hunk landed" \
  "$(yes_if sh -c 'grep -qx "/board.html" "$1" && ! grep -qx "!/board.html" "$1"' _ "$INST/.gitignore")"
assert "…the seed's new managed line landed"  "$(yes_if grep -qx "/$AB_BOARD_DIR/" "$INST/.gitignore")"
assert "…and the bundle's own line was kept"  "$(yes_if grep -qx 'MY-OWN-IGNORE' "$INST/.gitignore")"
assert "…with no conflict marker left in it" \
  "$(grep -qE '^(<<<<<<< |=======$|>>>>>>> )' "$INST/.gitignore" && echo 1 || echo 0)"
assert "knowledge/index.md is reported RESOLVED" "$(has 'RESOLVED  knowledge/index.md' "$APPLY")"
assert "…and was REGENERATED, not merged"     "$(yes_if grep -q 'F1' "$INST/knowledge/index.md")"
assert "…so the hand-written stub is gone"    "$(grep -q 'hand-written stub' "$INST/knowledge/index.md" && echo 1 || echo 0)"
assert "the summary counts them as resolved"  "$(has '2 resolved' "$APPLY")"

echo "== the undecidable conflict survives --apply untouched =="
assert "CLAUDE.md is still CONFLICT"          "$(has 'CONFLICT  CLAUDE.md' "$APPLY")"
assert "…and is byte-identical to before"     "$(yes_if cmp -s "$TMP/claude.pristine" "$INST/CLAUDE.md")"
assert "…and never reported RESOLVED"         "$(hasnt 'RESOLVED  CLAUDE.md' "$APPLY")"

echo "== nothing with conflict markers is written into the bundle tree =="
assert "no .bak file anywhere in the bundle" \
  "$(grep -q . <<<"$(find "$INST" -name '*.bak*')" && echo 1 || echo 0)"
assert "the bundle ROOT gained no .bak" \
  "$(sh -c 'ls "$1"/*.bak* >/dev/null 2>&1' _ "$INST" && echo 1 || echo 0)"
assert "the conflicted merge is kept under .ai-bridge/refresh/" \
  "$(yes_if sh -c 'ls "$1"/CLAUDE.md.* >/dev/null 2>&1' _ "$INST/.ai-bridge/refresh")"
assert "…and it carries the markers"          \
  "$(yes_if sh -c 'grep -qE "^(<<<<<<< |>>>>>>> )" "$1"/CLAUDE.md.*' _ "$INST/.ai-bridge/refresh")"
assert "…and the report names that path"      "$(has '.ai-bridge/refresh/CLAUDE.md' "$APPLY")"

echo "== \"what's left for you\" is only what a human must decide =="
assert "the conflict is listed"               "$(has 'port the seed change into CLAUDE.md' "$APPLY")"
assert "committing is NOT listed as work"     "$(hasnt 'review and commit what changed' "$APPLY")"
# A second --apply has nothing left to say about the two decidable classes, and the only
# item left is the conflict. Resolve that by hand and the section must disappear entirely.
cp "$TPL/plugin/seed/CLAUDE.md" "$INST/CLAUDE.md"
CLEAN="$(bash "$REFRESH" "$INST" --apply 2>&1)"
assert "a bundle with nothing to decide omits the section" "$(hasnt "what.s left for you" "$CLEAN")"
assert "…and does not print the old 'Nothing.' line"       "$(hasnt 'This bundle is up to date' "$CLEAN")"
assert "…and is idempotent on the decidable classes"       "$(hasnt 'RESOLVED' "$CLEAN")"

echo "== /${PN}:init runs the check-and-fix pass itself =="
# Re-diverge one seed-managed .gitignore line so the pass has something to do.
printf 'node_modules/\n# derived, never tracked\n/board.html\n/%s/\n/%s\n/%s\n' "$AB_BOARD_DIR" "$AB_STATE_DIR" "$AB_LOCK" > "$TPL/plugin/seed/.gitignore"
( cd "$TPL" && git add -A && gc "template, seed v3" )
printf 'node_modules/\n!/board.html\n/%s\nMY-OWN-IGNORE\n' "$AB_LOCK" > "$INST/.gitignore"
# A lock and an UNCOMMITTED config the pass must refuse to touch, in the same run. The
# config is the ambiguous tier's only trigger, so this is also what proves a row outside
# the idempotent tier is printed and left alone.
mkdir -p "$INST/$AB_DIR"; printf 'held by a tick\n' > "$INST/$AB_LOCK"
( cd "$INST" && git add -A && gc "before the pass" )
printf '{\n  "org": "decided-minutes-ago"\n}\n' > "$INST/instance.config.json"
cp "$INST/instance.config.json" "$TMP/config.pristine"
STAMP="$(bash "$TPL/plugin/scripts/init-bundle.sh" "$INST" 2>&1)"
assert "the stamp prints the check headings"   "$(has '── seed-drift .idempotent.' "$STAMP")"
assert "…for the config row too"               "$(has '── config-uncommitted .ambiguous.' "$STAMP")"
assert "…and says it acts on the idempotent tier ONLY" \
  "$(has 'acting ONLY on the idempotent tier' "$STAMP")"
assert "…and states the two refusals"          "$(has 'Config files and tick locks are NEVER written' "$STAMP")"
assert "…a non-idempotent tier is reported, not acted on" "$(has 'NOT ACTED ON' "$STAMP")"
assert "…the tick lock it found is still there"        "$(yes_if test -f "$INST/$AB_LOCK")"
assert "…and instance.config.json was never written"   "$(yes_if cmp -s "$TMP/config.pristine" "$INST/instance.config.json")"
assert "…and the seed drift was actually resolved" \
  "$(yes_if sh -c "grep -qx '/$AB_STATE_DIR' \"\$1\" && grep -qx 'MY-OWN-IGNORE' \"\$1\"" _ "$INST/.gitignore")"
assert "…without re-entering the stamp"        "$(hasnt 'NOT re-stamped' "$STAMP")"

echo "== welcome fix points at init and exits 0 =="
FIX_RC=0
FIX="$(bash "$TPL/plugin/scripts/ai-bridge.sh" fix --instance "$INST" 2>&1)" || FIX_RC=$?
assert "welcome fix exits 0"                   "$([ "$FIX_RC" -eq 0 ] && echo 0 || echo 1)"
assert "…and points at /${PN}:init"        "$(has ''"${PN}:"'init' "$FIX")"
assert "…in ONE line"                          "$([ "$(printf '%s\n' "$FIX" | wc -l | tr -d ' ')" = 1 ] && echo 0 || echo 1)"
assert "…and repairs nothing itself"           "$(hasnt 'idempotent tier' "$FIX")"
CHECK="$(bash "$TPL/plugin/scripts/ai-bridge.sh" check --instance "$INST" 2>&1 || true)"
assert "welcome check still surveys the bundle" "$(has 'seed documents' "$CHECK")"

echo "== the docs name init as the command after a plugin update =="
OPS="$(cat "$REPO/docs/operations.md")"
assert "operations.md names init as that command" \
  "$(has 'one command to run after every plugin update' "$OPS")"
assert "…and says what welcome is for"          "$(has 'the banner, and' "$OPS")"
assert "…and carries the decidable table"       "$(has 'decidable conflict classes' "$OPS")"
SEEDCM="$(cat "$REPO/plugin/seed/CLAUDE.md")"
assert "the seed CLAUDE.md names init after a plugin update" \
  "$(has 'After every plugin update, run ..'"${PN}:"'init' "$SEEDCM")"
assert "…and says what welcome is for"          "$(has 'is the banner and' "$SEEDCM")"

# Driven by the table's CLASS, not by a path: the next derived file added as a row is
# covered here without touching this harness. dispatch-reporting-defects/task-018.
echo "== every derived-gitignored row keeps the bundle's copy instead of reporting CONFLICT =="
hasf() { grep -qF <<<"$2" -- "$1" && echo 0 || echo 1; }
DG="$(printf '%s\n' "$TABLE" | awk -F'\t' '$2=="derived-gitignored" {print $1}')"
assert "the table has at least one derived-gitignored row" "$([ -n "$DG" ] && echo 0 || echo 1)"
TPL2="$TMP/tpl2"; cp -R "$TPL" "$TPL2"
INST2="$TMP/group2/_ai-bridge-derived"; mkdir -p "$INST2"
bash "$TPL2/plugin/scripts/init-bundle.sh" "$INST2" > "$TMP/stamp2.out" 2>&1
( cd "$INST2" && git init -q -b main . && git add -A && gc "bundle init" )
for p in $DG; do
  dest="$(ab_seed_dest "$p")"
  assert "$dest is gitignored in a stamped bundle" "$(yes_if git -C "$INST2" check-ignore -q "$dest")"
  sed '1s/.*/written by the generator/' "$INST2/$dest" > "$TMP/x" && mv "$TMP/x" "$INST2/$dest"
  cp "$INST2/$dest" "$TMP/dg.$(printf '%s' "$p" | tr / _)"
  sed '1s/.*/seed prose, v2/' "$TPL2/plugin/seed/$p" > "$TMP/x" && mv "$TMP/x" "$TPL2/plugin/seed/$p"
done
[ -z "$DG" ] || ( cd "$TPL2" && git add -A && gc "template, derived seed edit" )
DG_REPORT="$(bash "$TPL2/plugin/scripts/refresh-seeds.sh" "$INST2" 2>&1)"
DG_RC=0
DG_APPLY="$(bash "$TPL2/plugin/scripts/refresh-seeds.sh" "$INST2" --apply 2>&1)" || DG_RC=$?
assert "--apply exits 0" "$([ "$DG_RC" -eq 0 ] && echo 0 || echo 1)"
for p in $DG; do
  rule="$(printf '%s\n' "$TABLE" | awk -F'\t' -v p="$p" '$1==p {print $3}')"
  assert "$p: report mode says DECIDABLE"         "$(has "DECIDABLE  *$p\$" "$DG_REPORT")"
  assert "…and never CONFLICT"                    "$(hasnt "CONFLICT  *$p\$" "$DG_REPORT")"
  assert "--apply says RESOLVED"                  "$(has "RESOLVED  *$p\$" "$DG_APPLY")"
  assert "…naming its rule"                       "$(hasf "rule: $rule" "$DG_APPLY")"
  assert "…and never CONFLICT"                    "$(hasnt "CONFLICT  *$p\$" "$DG_APPLY")"
  assert "…nor lists it as left for the human"    "$(hasnt "port the seed change into $p" "$DG_APPLY")"
  assert "…and the bundle's copy is byte-identical" \
    "$(yes_if cmp -s "$TMP/dg.$(printf '%s' "$p" | tr / _)" "$INST2/$(ab_seed_dest "$p")")"
done

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
