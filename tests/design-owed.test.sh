#!/usr/bin/env bash
# design-owed.test.sh — a build project whose drafts are all refined and that has no
# design.md is owed work: the digest names it and step 2, `tick-delta.sh check` never reads a
# clean tree IDLE past it, and its ✅ approve rows say `no design yet`.
#
# Why (2026-11-18): a build project's drafts were all refined in one pass. The digest named
# step 2 for the missing design.md but printed no line saying so, `check` raised no DELTA,
# and once the tree was clean every tick went IDLE: the design was never drawn, and later
# ticks rendered the drafts as approve rows with no design link and no pre_mortem.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/plugin/scripts/bundle-paths.sh"
S="$REPO/plugin/scripts"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/designowed.XXXXXX")" || { echo "design-owed.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git \
          -c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false \
          -c core.hooksPath=/dev/null "$@"; }

INST="$TMP/inst"
mkdir -p "$INST/projects/a/tasks" "$INST/scripts"
cp "$S"/*.sh "$S"/*.py "$INST/scripts/"; cp -R "$S/lib" "$INST/scripts/lib"
cp -R "$REPO/plugin/tick-steps" "$INST/tick-steps"
mkdir -p "$INST/.loopd"; : > "$INST/.loopd/SCHEMA.md"
printf '/%s\n' "$AB_STATE_DIR" > "$INST/.gitignore"; printf '{}\n' > "$INST/instance.config.json"
GIT -C "$INST" init -q

P="$INST/projects/a"
project() { # <kind> <status> [extra frontmatter]
  printf -- '---\ntype: Project\nkind: %s\ntarget_repo: example-org/example-repo\nstatus: %s\n%b---\n' \
    "$1" "$2" "${3:-}" > "$P/project.md"; }
refined() { # <task file> — a draft step 2 owes nothing but its project's design
  printf -- '---\ntype: Task\nstatus: draft\ntarget_repo: example-org/example-repo\n'"\
"'acceptance_criteria: [ "x" ]\n'"\
"'advisor_notes:\n  - "2026-11-01T10:00:00Z · advisor: approach critique — no concerns"\n---\n\n'"\
"'## Verified facts (as of example-org/example-repo@0123456789abcdef0123456789abcdef01234567)\n\n- a · b\n' > "$P/tasks/$1"; }
unrefined() { printf -- '---\ntype: Task\nstatus: draft\nacceptance_criteria: [ ]\n---\n' > "$P/tasks/$1"; }
design() { printf -- '---\ntype: Design\ntasks:\n  - "cache → task-001"\n  - "api → task-002"\n---\n' > "$P/design.md"; }
commit() { GIT -C "$INST" add -A && GIT -C "$INST" commit -qm fx; }
digest() { "$INST/scripts/tick-delta.sh" digest --instance "$INST" 2>/dev/null; }
check() { local out rc; out="$("$INST/scripts/tick-delta.sh" check --instance "$INST" 2>&1)"; rc=$?
          printf 'rc:%s %s' "$rc" "$(head -1 <<<"$out")"; }
record() { "$INST/scripts/tick-delta.sh" record --instance "$INST" >/dev/null 2>&1; }
recorded() { record; echo $?; }
names_step2() { local d; d="$(digest)"; case "$(grep '^steps:' <<<"$d")" in *step-2-refine-drafts.md*) echo yes ;; *) echo no ;; esac; }
critique() { # the project-level critique receipt, so `critique owed` stays out of the IDLE case
  project build active 'advisor_notes:\n  - "2026-11-01T10:00:00Z · advisor: project critique — no concerns · saw: task-001 task-002"\n'; }

echo "== digest: every draft refined, no design.md =="
project build active
refined task-001-a.md; refined task-002-b.md
commit
ok "two refined drafts, no design.md → exactly one design owed line" "$(digest | grep -c '^design owed ')" 1
ok "…naming the project's design.md"                   "$(digest | sed -n 's/^design owed //p')" "projects/a/design.md"
ok "…and the steps line names step 2"                  "$(names_step2)" yes

echo "== check: a clean recorded tree owing a design is never IDLE =="
ok "record exits 0"                                    "$(recorded)" 0
ok "clean and recorded → DELTA, exit 1" "$(check)" \
   "rc:1 DELTA: design owed projects/a — every draft is refined; step 2 owes its design.md."

echo "== design.md present → no line, IDLE =="
design; critique; commit; record
ok "design.md drawn → no design owed line"             "$(digest | grep -c '^design owed ')" 0
ok "…and IDLE"                                         "$(check | cut -c1-10)" "rc:0 IDLE:"
rm -f "$P/design.md"

echo "== never on research, paused or inputs-waiting =="
project research active; commit; record
ok "a research project → no design owed line"          "$(digest | grep -c '^design owed ')" 0
ok "…and check does not name one"                      "$(check | grep -c 'design owed')" 0
project '"research"' active; commit; record
ok "a quoted kind: \"research\" → no design owed line"  "$(digest | grep -c '^design owed ')" 0
ok "…and check does not name one"                      "$(check | grep -c 'design owed')" 0
project "'research'" active; commit; record
ok "a single-quoted kind → no design owed line"        "$(digest | grep -c '^design owed ')" 0
printf -- '---\ntype: Project\nstatus: active\n---\n' > "$P/project.md"; commit
ok "an omitted kind is build → design owed"            "$(digest | grep -c '^design owed ')" 1
project build paused; commit; record
ok "a paused project → no design owed line"            "$(digest | grep -c '^design owed ')" 0
ok "…and IDLE"                                         "$(check | cut -c1-10)" "rc:0 IDLE:"
project build active 'inputs: later\n'; commit; record
ok "a project waiting on inputs → no design owed line" "$(digest | grep -c '^design owed ')" 0

echo "== an unrefined draft is refine owed, not design owed =="
project build active; unrefined task-003-c.md; commit
ok "one unrefined draft → no design owed line"         "$(digest | grep -c '^design owed ')" 0
ok "…but a refine owed line for it"                    "$(digest | sed -n 's/^refine owed //p')" "projects/a/tasks/task-003-c.md"
rm -f "$P/tasks/task-003-c.md"
rm -f "$P"/tasks/*.md; commit
ok "a project with no task at all → no design owed line" "$(digest | grep -c '^design owed ')" 0

echo "== build-awaiting.sh: the approve row says no design yet =="
refined task-001-a.md
rendered() { : > "$TMP/AWAITING.md"; bash "$INST/scripts/build-awaiting.sh" --instance "$INST" --out "$TMP/AWAITING.md" >/dev/null 2>&1; echo $?; }
approve_row() { rendered >/dev/null; grep -F '**approve**' "$TMP/AWAITING.md"; }
row="$(approve_row)"
ok "no design.md → the approve row stays"              "$(printf '%s\n' "$row" | grep -c '^\* ✅ \*\*approve\*\*')" 1
ok "…marked no design yet"                             "$(printf '%s\n' "$row" | grep -c ' · no design yet · ')" 1
design; row="$(approve_row)"
ok "design.md present → not marked"                    "$(printf '%s\n' "$row" | grep -c 'no design yet')" 0
ok "…and the row links it instead"                     "$(printf '%s\n' "$row" | grep -c '\[design\](/projects/a/design.md)')" 1
rm -f "$P/design.md"; project research active
ok "a research project renders (exit 0)"               "$(rendered)" 0
row="$(grep -F '**approve**' "$TMP/AWAITING.md")"
ok "…with its approve row"                             "$(printf '%s\n' "$row" | grep -c '^\* ✅ \*\*approve\*\*')" 1
ok "…never marked no design yet"                       "$(printf '%s\n' "$row" | grep -c 'no design yet')" 0
project '"research"' active
ok "a quoted research kind → never marked"             "$(approve_row | grep -c 'no design yet')" 0
printf -- '---\ntype: Task\nkind: research\nstatus: draft\nacceptance_criteria: [ "x" ]\n---\n' > "$P/tasks/task-001-a.md"
project build active
ok "a research-kind draft in a build project follows the project" "$(approve_row | grep -c 'no design yet')" 1
refined task-001-a.md

echo "== mutant: without the design owed print the harness fails =="
project build active; refined task-002-b.md; commit
sed "s/printf 'design owed %sdesign.md\\\\n' \"\${d#\"\$inst\"\\/}\"; //" "$S/tick-delta.sh" > "$INST/scripts/tick-delta.sh"
ok "the mutant differs from the script"                "$(cmp -s "$S/tick-delta.sh" "$INST/scripts/tick-delta.sh"; echo $?)" 1
ok "mutant digest prints no design owed line"          "$(digest | grep -c '^design owed ')" 0
ok "…while it still runs to its steps line"            "$(digest | grep -c '^steps:')" 1
cp "$S/tick-delta.sh" "$INST/scripts/tick-delta.sh"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
