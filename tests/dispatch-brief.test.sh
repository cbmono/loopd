#!/usr/bin/env bash
#
# dispatch-brief.test.sh — the fixed sections a dispatch brief must carry are pinned
# as GENERATED TEXT, not as a paragraph telling the PM to include them.
#
# WHY IT IS THE SCRIPT'S STDOUT. A brief is prose the project-manager composes at spawn
# time, so "the brief carries X" is unassertable while X lives only in an instruction —
# such a test passes on a brief that was never built
# (knowledge/findings/a-rule-about-a-brief-is-testable-only-when-something-generates-the-
# brief.md). Moving both sections into one script makes every criterion here a string
# comparison on a fixture.
#
# BOTH HEADINGS ARE PINNED IN TWO PLACES ON PURPOSE — here as literals, and against
# `project-manager.md`, which tells the PM to paste the block unchanged. A rename landing
# in the script alone leaves the PM hunting a heading nothing emits.
#
# NON-VACUOUS BY CONSTRUCTION. The Service-doc branch and the no-Service-doc branch are
# run over the SAME task document, with only the doc's existence differing, so a script
# that stopped looking would flip a verdict rather than print a different shape.
#
# `assert()` uses exit-code semantics: 0 is a PASS, matching the other harnesses.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/plugin/scripts/dispatch-brief.sh"
PM_DOC="$REPO/plugin/tick-steps/step-3-dispatch.md"
for f in "$SCRIPT" "$PM_DOC"; do
  [ -f "$f" ] || { echo "dispatch-brief.test: missing $f" >&2; exit 2; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dispatch-brief-fixture.XXXXXX")" || {
  echo "dispatch-brief.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
assert() { if [ "$2" = 0 ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
has()  { grep -qF -e "$1" <<<"$2" && echo 0 || echo 1; }
hasnt(){ grep -qF -e "$1" <<<"$2" && echo 1 || echo 0; }
eq()   { [ "$1" = "$2" ] && echo 0 || echo 1; }

GROUNDING='## Grounding'
EFFORT='## Effort'
DOC="$TMP/projects/demo/tasks/task-001.md"
SVC="$TMP/knowledge/services/widget.md"

# <criteria-count> — a task document with N acceptance criteria and a target_repo.
reset() {
  rm -rf "$TMP/projects" "$TMP/knowledge"
  mkdir -p "$TMP/projects/demo/tasks" "$TMP/knowledge/services"
  printf '{ "org": "acme", "maxPrLoc": 1234, "maxPrFiles": 42 }\n' > "$TMP/instance.config.json"
  local n="${1:-4}" ac="" i
  for i in $(seq 1 "$n"); do ac="$ac\"criterion $i\", "; done
  { printf -- '---\ntype: Task\ntitle: "Ship the widget"\nkind: build\n'
    printf 'target_repo: acme/widget\nstatus: ready\n'
    printf 'acceptance_criteria: [ %s ]\n' "${ac%, }"
    printf 'timestamp: 2026-01-01T00:00:00Z\n---\n\n# Context\n\nSomething.\n'
  } > "$DOC"
}
service() { # writes a Service doc with the given body appended to its frontmatter
  { printf -- '---\ntype: Service\ntitle: widget\nrepo: acme/widget\n'
    printf 'path: services/widget\nstack: [typescript]\nruntime: node 22\nstatus: active\n---\n\n'
    cat
  } > "$SVC"
}
run() { bash "$SCRIPT" "$@" 2>&1; }
rc()  { bash "$SCRIPT" "$@" >/dev/null 2>&1; echo $?; }
# The Grounding body: everything between its heading and the Effort heading, blanks dropped.
grounding_body() { awk -v g="$GROUNDING" -v e="$EFFORT" '
  index($0,g)==1 {f=1; next} index($0,e)==1 {exit} f && NF' <<<"$1"; }

echo "== both fixed sections are present, and the headings match project-manager.md =="

reset 4
service <<'MD'
# Overview

The widget service.
MD
OUT="$(run "$DOC")"
assert "the Grounding heading names the target repo"  "$(has "$GROUNDING (acme/widget)" "$OUT")"
assert "the Effort heading is present"                "$(has "$EFFORT" "$OUT")"
assert "…and the PM is told to paste the Grounding heading" "$(has "$GROUNDING (<target_repo>)" "$(cat "$PM_DOC")")"
assert "…and the Effort heading, in the same document"      "$(has "\`$EFFORT\`" "$(cat "$PM_DOC")")"
assert "…and it names the script that emits them"           "$(has "scripts/dispatch-brief.sh" "$(cat "$PM_DOC")")"
assert "exit 0 with a Service doc present"            "$(rc "$DOC")"

echo "== Grounding is the Service doc's entry points, capped at 15 lines =="

# By suffix: the script resolves `$TMPDIR` through the /var -> /private/var symlink.
assert "it points at the Service doc by path"   "$(has "/knowledge/services/widget.md — read it before you read code." "$OUT")"
assert "…and carries the doc's identity fields" "$(has "path: services/widget" "$OUT")"
assert "…and its section list"                  "$(has "Sections: Overview" "$OUT")"

reset 4
service <<'MD'
# Entry points

- `src/index.ts` — the HTTP entry point.
- `src/worker.ts` — the queue consumer.
MD
OUT="$(run "$DOC")"
assert "an explicit '# Entry points' section wins"      "$(has 'src/index.ts` — the HTTP entry point.' "$OUT")"
assert "…and the identity fallback is then not printed" "$(hasnt "path: services/widget" "$OUT")"

reset 4
{ echo '# Entry points'; echo; for i in $(seq 1 30); do echo "- entry $i"; done; } | service
OUT="$(run "$DOC")"
BODY="$(grounding_body "$OUT")"
assert "a 31-line entry-points section is capped at 15 lines" "$(eq "$(printf '%s\n' "$BODY" | grep -c '')" 15)"
assert "…and the 15th line says it was truncated"             "$(has "truncated at 15 lines" "$BODY")"
assert "…so a later entry is dropped rather than pasted"      "$(hasnt "- entry 20" "$OUT")"

echo "== no Service doc ⇒ ONE line telling the agent to draft it =="

reset 4                                   # same task, only the Service doc removed
OUT="$(run "$DOC")"
BODY="$(grounding_body "$OUT")"
assert "the Grounding body is exactly one line"    "$(eq "$(printf '%s\n' "$BODY" | grep -c '')" 1)"
assert "…naming the doc to draft"                  "$(has 'knowledge/services/widget.md' "$BODY")"
assert "…and the cataloguer as its reviewer"       "$(has 'cataloguer' "$BODY")"
assert "…and it does NOT claim a doc exists"       "$(hasnt "read it before you read code" "$OUT")"
assert "the Effort section still prints"           "$(has "$EFFORT" "$OUT")"

echo "== Effort carries files expected, the LOC ceiling and a turns hint =="

reset 5
service <<'MD'
# Overview

x
MD
OUT="$(run "$DOC")"
assert "files expected is stated"        "$(has "Files expected: ~14" "$OUT")"
assert "the turns hint is stated"        "$(has "first edit by turn ~5" "$OUT")"
if command -v python3 >/dev/null 2>&1; then
  assert "maxPrLoc comes from the instance config"   "$(has "LOC ceiling: 1234 (maxPrLoc)" "$OUT")"
  assert "…and maxPrFiles with it"                   "$(has "42 files (maxPrFiles)" "$OUT")"
  rm -f "$TMP/instance.config.json"
  # No instance.config.json anywhere above the task ⇒ the documented defaults, never a blank.
  OUT2="$(run "$DOC" --instance "$TMP")"
  assert "absent config falls back to 500/100"       "$(has "LOC ceiling: 500 (maxPrLoc), 100 files" "$OUT2")"
else
  echo "  SKIP  config-value assertions (no python3)"
fi

echo "== the band is a function of the criteria count, and its boundaries hold =="

for probe in "3 small ~6" "4 standard ~14" "6 standard ~14" "7 large ~20"; do
  # shellcheck disable=SC2086  # deliberate word split into the probe's three fields
  set -- $probe
  reset "$1"
  assert "$1 criteria ⇒ band $2, files $3" "$(has "Files expected: $3 (band $2 — $1 acceptance criteria)" "$(run "$DOC")")"
done

# SCHEMA.md's block form: one quoted entry per line. count_entries used to keep only the
# LAST line's count, and field() handed it only the key line, so six criteria banded as 0.
reset 1
python3 - "$DOC" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
block = "acceptance_criteria:\n" + "".join('  - "criterion %d, with `x` and [y]"\n' % i for i in range(1, 7))
open(p, "w").write(s.replace('acceptance_criteria: [ "criterion 1" ]\n', block))
PY2
assert "a six-entry BLOCK list counts 6, band standard" \
  "$(has "Files expected: ~14 (band standard — 6 acceptance criteria)" "$(run "$DOC")")"

# A task with NO acceptance_criteria at all: the band arithmetic must see a number, not an
# empty string — it printed `band large —  acceptance criteria` beside two `[: integer
# expression expected` lines before `count_entries` was made to always emit one.
printf -- '---\ntype: Task\ntarget_repo: acme/widget\n---\n\nx\n' > "$TMP/nocrit.md"
OUT3="$(run "$TMP/nocrit.md" --instance "$TMP" 2>&1)"
assert "no acceptance_criteria ⇒ 0, band small" "$(has "Files expected: ~6 (band small — 0 acceptance criteria)" "$OUT3")"
assert "…and no shell error leaks into the brief" "$(hasnt "integer expression expected" "$OUT3")"

echo "== Scratch is one directory per TASK, on a path the target repo ignores =="

# A task's scratch path is unique because it is keyed on the TASK, so the fixture varies
# the task and nothing else: same repo, same worktree, two documents.
scratch_task() { # <doc> <worktree>
  { printf -- '---\ntype: Task\ntarget_repo: acme/widget\n'
    printf 'worktree: %s\nbranch: b\nacceptance_criteria: [ "one" ]\n---\n\nx\n' "$2"
  } > "$1"
}
# The path line: the one under the Scratch heading that is not prose.
scratch_path() { awk '/^## Scratch$/{f=1;next} f&&/^\//{print;exit}' <<<"$1"; }
# <ignores-tmp?> — a target-repo clone at the reposRoot the fixture config names.
clone() {
  rm -rf "$TMP/repos"; mkdir -p "$TMP/repos/widget"
  [ "$1" = yes ] && printf 'tmp/\n' > "$TMP/repos/widget/.gitignore"
  git -c init.defaultBranch=main init -q "$TMP/repos/widget"
  printf '{ "org": "acme", "reposRoot": "%s/repos" }\n' "$TMP" > "$TMP/instance.config.json"
}

mkdir -p "$TMP/projects/demo/tasks"
scratch_task "$TMP/projects/demo/tasks/task-101-alpha.md" "$TMP/wt/alpha"
scratch_task "$TMP/projects/demo/tasks/task-102-beta.md"  "$TMP/wt/beta"
P1="$(scratch_path "$(run "$TMP/projects/demo/tasks/task-101-alpha.md")")"
P2="$(scratch_path "$(run "$TMP/projects/demo/tasks/task-102-beta.md")")"
assert "the Scratch heading carries a path"          "$(has "$TMP/wt/alpha/tmp/task-101-alpha" "$P1")"
assert "…keyed on the task slug, not the session"    "$(has "task-101-alpha" "$P1")"
assert "two tasks get two different scratch paths"   "$([ -n "$P1" ] && [ "$P1" != "$P2" ] && echo 0 || echo 1)"
assert "…and the second names its own task"          "$(has "task-102-beta" "$P2")"

if command -v python3 >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
  clone yes
  OUT4="$(run "$TMP/projects/demo/tasks/task-101-alpha.md" --instance "$TMP")"
  assert "a repo that ignores tmp/ keeps scratch in the worktree" \
    "$(eq "$(scratch_path "$OUT4")" "$TMP/wt/alpha/tmp/task-101-alpha")"
  assert "…and says so, naming git check-ignore"     "$(has 'ignores `tmp/` (`git check-ignore`' "$OUT4")"

  clone no                                  # same fixture, only the .gitignore removed
  OUT5="$(run "$TMP/projects/demo/tasks/task-101-alpha.md" --instance "$TMP")"
  assert "a repo that does NOT ignore tmp/ moves scratch out of it" \
    "$(hasnt "$TMP/wt/alpha" "$(scratch_path "$OUT5")")"
  assert "…and the path is still the task's alone"   "$(has "task-101-alpha" "$(scratch_path "$OUT5")")"
  assert "…and the brief says the repo does not ignore it" "$(has 'does NOT ignore `tmp/`' "$OUT5")"

  rm -rf "$TMP/repos"                       # no clone to check ⇒ UNKNOWN, never a claim
  OUT6="$(run "$TMP/projects/demo/tasks/task-101-alpha.md" --instance "$TMP")"
  assert "no clone ⇒ the ignore state is reported UNKNOWN" "$(has 'is UNKNOWN' "$OUT6")"
  assert "…and it never claims the repo ignores it"        "$(hasnt 'ignores `tmp/` (`git check-ignore`' "$OUT6")"
else
  echo "  SKIP  check-ignore assertions (no python3 or no git)"
fi

assert "the PM is told to paste the Scratch heading" "$(has '`## Scratch`' "$(cat "$PM_DOC")")"

echo "== it refuses rather than guessing =="

assert "a missing task document exits 2"  "$(eq "$(rc "$TMP/nope.md")" 2)"
printf 'no frontmatter here\n' > "$TMP/bare.md"
assert "a document with no frontmatter exits 2" "$(eq "$(rc "$TMP/bare.md")" 2)"
assert "no arguments exits 2"             "$(eq "$(rc)" 2)"

printf '\n  %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
