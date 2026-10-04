#!/usr/bin/env bash
#
# timebox-inert.test.sh — `timebox:` on a project.md changes NOTHING until something reads
# it (value-gate-at-intake/task-002). The reader is a later task; until it lands, every
# surface that reads a project.md must render byte-identically with the key present, empty
# or absent. The allow half: a change that SHOULD move the output (`status: paused`) does,
# so an identical render is the comparison working, not a comparison that cannot fail.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO/plugin/scripts"
. "$S/bundle-paths.sh"
command -v python3 >/dev/null 2>&1 || { echo "timebox-inert.test: python3 required" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/timebox-inert.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { # <label> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s (want %s, got %s)\n' "$1" "$3" "$2"; fail=$((fail+1)); fi; }

INST="$TMP/inst"
mkdir -p "$INST/$AB_DIR" "$INST/projects/exp/tasks"
printf '{ "org": "o" }\n' > "$INST/instance.config.json"
cp "$REPO/plugin/seed/SCHEMA.md" "$INST/$AB_SCHEMA"
printf '{}\n' > "$INST/$AB_SNAPSHOT"
: > "$INST/$AB_AWAITING"
T="$INST/projects/exp/tasks"
printf -- '---\ntype: Task\ntitle: a\nstatus: ready\nacceptance_criteria: [ "c" ]\nopen_questions: [ ]\ntimestamp: 2026-09-01T00:00:00Z\n---\n' > "$T/task-001-a.md"
printf -- '---\ntype: Task\ntitle: b\nstatus: draft\nacceptance_criteria: [ "c" ]\nopen_questions: [ "Q1: which?" ]\ntimestamp: 2026-09-01T00:00:00Z\n---\n' > "$T/task-002-b.md"
printf -- '---\ntype: Task\ntitle: c\nstatus: blocked\ntimestamp: 2026-09-01T00:00:00Z\n---\n' > "$T/task-003-c.md"
printf -- '---\ntype: Task\ntitle: d\nstatus: in-review\npr: [ "https://github.com/o/r/pull/7" ]\ntimestamp: 2026-09-01T00:00:00Z\n---\n' > "$T/task-004-d.md"

project() { # [<extra frontmatter line>] [<status>]
  { printf -- '---\ntype: Project\ntitle: Experiment\nkind: build\ntarget_repo: o/r\nstatus: %s\n' "${2:-active}"
    [ -z "${1:-}" ] || printf '%s\n' "$1"
    printf 'timestamp: 2026-09-01T00:00:00Z\n---\n\n# Context\n\nfixture\n'; } > "$INST/projects/exp/project.md"; }

# Every surface that reads a project.md and runs offline, concatenated. Generated-at lines
# move by design and are pinned or dropped; nothing else is normalised.
render() {
  ( cd "$INST" || exit 2
    echo "## validate-bundle"; bash "$S/validate-bundle.sh" --strict projects/exp/project.md projects/exp/tasks/*.md 2>&1; echo "rc=$?"
    echo "## project-paused";  bash "$S/project-paused.sh" projects/exp/tasks/task-001-a.md 2>&1; echo "rc=$?"
    for t in projects/exp/tasks/*.md; do
      echo "## task-owner $t"; bash "$S/task-owner.sh" "$t" 2>&1; echo "rc=$?"
    done
    echo "## write-snapshot"; SNAPSHOT_NOW=2026-09-28T00:00:00Z bash "$S/write-snapshot.sh" --quiet 2>&1; echo "rc=$?"
    cat "$AB_SNAPSHOT"
    echo "## build-awaiting"; bash "$S/build-awaiting.sh" --instance . 2>&1; echo "rc=$?"
    grep -v '^Last refreshed:' "$AB_AWAITING"
    echo "## build-board"; bash "$S/build-board.sh" --out "$TMP/board.html" . 2>&1; echo "rc=$?"
    cat "$TMP/board.html" ) > "$TMP/$1.out" 2>&1
}

project "";                  render absent
project "timebox: 6w";       render weeks
project "timebox: 14d";      render days
project "timebox:";          render empty
project "" paused;           render paused

ok "the fixture carries the key (not a vacuous pass)" \
  "$(project 'timebox: 6w'; grep -c '^timebox: 6w$' "$INST/projects/exp/project.md")" 1
ok "every surface rendered (absent run reached the board)" \
  "$(grep -c '^## build-board$' "$TMP/absent.out")" 1
ok "no surface emits the key" "$(grep -c '"timebox\|timebox:' "$TMP/weeks.out")" 0
for v in weeks days empty; do
  ok "timebox ($v) renders byte-identically to absent" \
    "$(cmp -s "$TMP/absent.out" "$TMP/$v.out" && echo same || { diff "$TMP/absent.out" "$TMP/$v.out" | head -5 >&2; echo differs; })" same
done
ok "allow half: status: paused DOES move the render" \
  "$(cmp -s "$TMP/absent.out" "$TMP/paused.out" && echo same || echo differs)" differs

echo "== documented where a reader looks, with its grammar and origin =="
SCHEMA="$REPO/plugin/seed/SCHEMA.md"; SKILL="$REPO/plugin/skills/new-project/SKILL.md"
block="$(awk '/^## type: Project/{f=1} /^## type: Phase/{f=0} f' "$SCHEMA")"
ok "SCHEMA.md Project block defines timebox:" "$(printf '%s\n' "$block" | grep -c '^timebox: ')" 1
ok "…with its grammar"                        "$(printf '%s\n' "$block" | grep -c '<N>d | <N>w')" 1
ok "…measured FROM a named field"             "$(printf '%s\n' "$block" | grep -c 'Measured from\*\* the project.s `timestamp:`')" 1
ok "new-project takes a timebox= flag"        "$(grep -c '^- `timebox=' "$SKILL")" 1
ok "new-project's scaffold writes it"         "$(grep -c '`timebox:`' "$SKILL")" 1

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
