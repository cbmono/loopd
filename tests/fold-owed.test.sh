#!/usr/bin/env bash
# fold-owed.test.sh — an answered question on a draft is owed work: the digest names it and
# step 2, `tick-delta.sh check` never reads a clean tree IDLE past it, and a close names the
# previous full tick when that tick never rendered AWAITING.md.
#
# Why (2026-11-18): a human answered a refined draft's only open question in place (an
# unlabelled `advisor:` entry). The digest named step 2 but no task, the tick read step 2's
# work as its `refine owed` lines alone, and once the tree was clean every tick went IDLE.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/plugin/scripts/bundle-paths.sh"
S="$REPO/plugin/scripts"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/foldowed.XXXXXX")" || { echo "fold-owed.test: mktemp -d failed" >&2; exit 2; }
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

printf -- '---\ntype: Project\nkind: build\ntarget_repo: example-org/example-repo\nstatus: active\n'"\
"'advisor_notes:\n  - "2026-11-01T10:00:00Z · advisor: project critique — no concerns · saw: task-001"\n---\n' \
  > "$INST/projects/a/project.md"
printf -- '---\ntype: Design\ntasks:\n  - "task-001: the cache"\n---\n' > "$INST/projects/a/design.md"
T="projects/a/tasks/task-001.md"
draft() { # <open_questions entry> — a refined draft step 2 owes nothing else
  printf -- '---\ntype: Task\nkind: build\nstatus: draft\ntarget_repo: example-org/example-repo\n'"\
"'acceptance_criteria: [ "x" ]\nopen_questions: [ "%s" ]\n'"\
"'advisor_notes:\n  - "2026-11-01T10:00:00Z · advisor: approach critique — no concerns"\n---\n\n'"\
"'## Verified facts (as of example-org/example-repo@0123456789abcdef0123456789abcdef01234567)\n\n- a · b\n' "$1" > "$INST/$T"; }
commit() { GIT -C "$INST" add -A && GIT -C "$INST" commit -qm fx; }
digest() { "$INST/scripts/tick-delta.sh" digest --instance "$INST" 2>/dev/null; }
check() { local out rc; out="$("$INST/scripts/tick-delta.sh" check --instance "$INST" 2>&1)"; rc=$?
          printf 'rc:%s %s' "$rc" "$(head -1 <<<"$out" | cut -c1-60)"; }
record() { "$INST/scripts/tick-delta.sh" record --instance "$INST" >/dev/null 2>&1; }
names_step2() { local d; d="$(digest)"; case "$(grep '^steps:' <<<"$d")" in *step-2-refine-drafts.md*) echo yes ;; *) echo no ;; esac; }

echo "== digest: an answered advisor: entry on a refined draft =="
draft 'advisor: Should the cache be per tenant? --- yes: per tenant'
commit
ok "one answered entry → exactly one fold owed line"  "$(digest | grep -c '^fold owed ')" 1
ok "…naming the task"                                 "$(digest | sed -n 's/^fold owed //p')" "$T"
ok "…and the steps line names step 2"                 "$(names_step2)" yes
ok "…and no refine owed line"                         "$(digest | grep -c '^refine owed ')" 0

echo "== check: a clean recorded tree with an answer is never IDLE =="
record
ok "answered, clean and recorded → owed, not IDLE"    "$(check | cut -c1-50)" "rc:1 DELTA: fold owed $T"
draft 'Q1: Should the cache be per tenant? --- yes'; commit; record
ok "a Q<n>: label is owed the same way"               "$(check | cut -c1-20)" "rc:1 DELTA: fold owe"
draft 'Should the cache be per tenant? --- yes'; commit; record
ok "…and so is an unlabelled entry"                   "$(check | cut -c1-20)" "rc:1 DELTA: fold owe"

draft 'advisor: Should the cache be per tenant?'; commit; record
ok "the same entry unanswered → no fold owed line"    "$(digest | grep -c '^fold owed ')" 0
ok "…and IDLE"                                        "$(check | cut -c1-10)" "rc:0 IDLE:"

draft 'advisor: Should the cache be per tenant? --- yes: per tenant'; commit
( cd "$INST" && bash scripts/fold-answers.sh "$T" ) >/dev/null 2>&1
ok "fold-answers.sh folds it (exit 0 above) → no fold owed line" "$(digest | grep -c '^fold owed ')" 0
commit; record
ok "…but its bake is owed until step 2's refine receipt" "$(check | grep -cF "rc:1 DELTA: refine owed $T")" 1
printf '\n# Notes\n\n* %s refine: baked.\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$INST/$T"; commit; record
ok "…and IDLE"                                        "$(check | cut -c1-10)" "rc:0 IDLE:"

echo "== record --close: the previous full tick's skipped render is noted =="
L="$INST/$AB_LEDGER"; W="$INST/$AB_AWAITING"; T0=2026-11-18T10:00:00Z
PAIR="* TICK $T0 by me open: go
* TICK $T0 by me close: went"
note() { # <ledger lines before this tick's open> -> noted|clean|wrong|no-close
  printf '%s\n* TICK 2026-11-18T11:00:00Z by me open: go\n' "$1" > "$L"
  "$INST/scripts/tick-delta.sh" record --instance "$INST" --tick 2026-11-18T11:00:00Z --close "did things" >/dev/null 2>&1
  case "$(grep '11:00:00Z by me close: ' "$L")" in
    *"; awaiting not rendered by $T0 "*|*"; awaiting not rendered by $T0") echo noted ;;
    *"awaiting not rendered"*) echo wrong ;; '') echo no-close ;; *) echo clean ;; esac; }
: > "$W"; TZ=UTC touch -t 202611180959 "$W"; ( cd "$INST" && bash scripts/build-awaiting.sh ) >/dev/null 2>&1
ok "build-awaiting.sh run after T → clean"           "$(note "$PAIR")" clean
TZ=UTC touch -t 202611180959 "$W"
ok "AWAITING.md backdated before T → noted, naming T" "$(note "$PAIR")" noted
ok "an IDLE line after T is skipped → still T"        "$(note "$PAIR
* TICK 2026-11-18T10:30:00Z by me idle — fingerprint unchanged (tick-delta)")" noted
ok "a reaped close with no open is skipped → still T" "$(note "$PAIR
* TICK 2026-11-18T10:40:00Z by me close: tick-x ended with no ledger entry (tick-reap)")" noted
ok "a dead tick's open with no close is skipped"      "$(note "$PAIR
* TICK 2026-11-18T10:45:00Z by me open: died")" noted
ok "no earlier full tick → clean"                     "$(note "* TICK 2026-11-18T10:30:00Z by me idle — fingerprint unchanged (tick-delta)")" clean
rm -f "$W"
ok "no AWAITING.md at all → clean"                    "$(note "$PAIR")" clean

echo "== mutant: without the fold owed print the harness fails =="
draft 'advisor: Should the cache be per tenant? --- yes: per tenant'; commit
sed "/printf 'fold owed %s/s/printf 'fold owed %s\\\\n' \"\${f#\"\$inst\"\\/}\"; //" "$S/tick-delta.sh" > "$INST/scripts/tick-delta.sh"
mut="$(digest | grep -c '^fold owed ')"
ok "mutant digest prints no fold owed line"           "$mut" 0
ok "…while it still runs to its steps line"            "$(digest | grep -c '^steps:')" 1
cp "$S/tick-delta.sh" "$INST/scripts/tick-delta.sh"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
