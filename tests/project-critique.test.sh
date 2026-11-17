#!/usr/bin/env bash
#
# project-critique.test.sh — tick step 2's project critique: the step text (trigger on an
# existing design.md, the `saw:` receipt and rerun rule, the pre-mortem escalation, the
# per-task brief) and tick-delta.sh's DELTA for an unlaunched, untriaged or not-run one,
# whatever the tasks' statuses. Fixtures under mktemp; no gh, no network.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"
S="$REPO/plugin/scripts"
PM="$REPO/plugin/tick-steps/step-2-refine-drafts.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/projcrit.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git \
          -c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false \
          -c core.hooksPath=/dev/null "$@"; }

BLOCK="$(awk '/^   \*\*Project critique/ { inb = 1 } inb && /^   \*\*Approach critique/ { inb = 0 } inb { print }' "$PM" | tr '\n' ' ' | tr -s ' ')"
in_block() { [ "$(printf '%s\n' "$BLOCK" | grep -cF -- "$1")" -gt 0 ] && echo yes || echo no; }

echo "== step 2 text =="
ok "the project-critique block is extractable"     "$([ -n "$BLOCK" ] && echo yes || echo no)" yes
ok "a design.md with no receipt triggers it"       "$(in_block 'whose `project.md` `advisor_notes` holds no project-critique receipt')" yes
ok "…a design.md drawn before the rule included"   "$(in_block 'a design.md drawn before this rule included')" yes
ok "…in the tick that finds it so"                 "$(in_block 'in the tick that finds it so')" yes
ok "…dispatched namespaced, in the background"     "$(in_block 'one background `loopd:plan-architect` dispatch')" yes
ok "…never on a research project"                  "$(in_block 'Never on a `kind: research` project')" yes
ok "the brief carries project.md, design.md, every task" \
   "$(in_block 'every task'"'"'s title and `acceptance_criteria`')" yes
ok "each receipt entry carries saw:"               "$(in_block 'each entry ending ` · saw: <task ids>`')" yes
ok "…the no-concerns receipt is defined"           "$(in_block 'advisor: project critique — no concerns · saw:')" yes
ok "…not run and its retry apply unchanged"        "$(in_block 'apply unchanged, `not run (<reason>)`')" yes
ok "the rerun rule keys on the newest saw: list"   "$(in_block 'maps a task id missing from the newest receipt'"'"'s `saw:` list')" yes
ok "…at most once per tick per project"            "$(in_block 'at most once per tick per project')" yes
ok "the critic labels a pre-mortem concern"        "$(in_block 'the ask to label `pre-mortem:`')" yes
ok "…which is always escalated"                    "$(in_block 'A `pre-mortem:` concern is always escalated')" yes
ok "…and recorded by triage when no task is open"   "$(in_block 'with none left, the triage line records it')" yes
ok "triage resolves only on evidence the critic read" "$(in_block 'RESOLVE a concern only on evidence the critic could have')" yes
ok "…escalating to the named tasks' open_questions" "$(in_block 'an `advisor:` `open_questions` entry on each task it names')" yes
ok "the DELTA is stated whatever the statuses"     "$(in_block 'whatever its tasks'"'"' statuses')" yes
ok "…it gates no promotion"                        "$(in_block 'It gates no promotion')" yes
ok "…and counts against maxAgentsInFlight"         "$(in_block 'counts against `maxAgentsInFlight`')" yes
ok "the task critique's brief sees the project" \
   "$([ "$(grep -cF 'its project'"'"'s `need:`, `success_criteria` and its sibling tasks'"'"' titles' "$PM")" -gt 0 ] && echo yes || echo no)" yes

echo "== tick-delta.sh check =="
INST="$TMP/inst"; P=projects/p/project.md
mkdir -p "$INST/projects/p/tasks" "$INST/scripts"
for f in tick-delta.sh bundle-paths.sh fold-answers.sh web-queue.sh agent-sessions.sh design-inputs.sh \
         dispatchable-ready.sh resolve-max-agents.sh resolve-config.sh task-owner.sh project-paused.sh; do
  cp "$S/$f" "$INST/scripts/$f"
done
cp "$S"/*.py "$INST/scripts/"; cp -R "$S/lib" "$INST/scripts/lib"
cp -R "$REPO/plugin/tick-steps" "$INST/tick-steps"
printf '/%s\n' "$AB_STATE_DIR" > "$INST/.gitignore"; printf '{}\n' > "$INST/instance.config.json"
GIT -C "$INST" init -q
printf -- '---\ntype: Design\ntasks:\n  - "api → task-001"\n  - "store → task-002"\n---\n' > "$INST/projects/p/design.md"
NC='· advisor: project critique — no concerns'
NR='· advisor: project critique — not run'
N=$'\n'
fx() { # <kind> <task status> <advisor_notes entries, one per line, or empty> [notes body]
  { printf -- '---\ntype: Project\nkind: %s\nstatus: active\n' "$1"
    if [ -n "$3" ]; then printf 'advisor_notes:\n'; printf '%s\n' "$3" | sed 's/^/  - "/; s/$/"/'; fi
    printf -- '---\n\n# Notes\n\n%b' "${4:-}"; } > "$INST/$P"
  for t in 001 002; do printf -- '---\ntype: Task\nstatus: %s\n---\n' "$2" > "$INST/projects/p/tasks/task-$t.md"; done
  GIT -C "$INST" add -A && GIT -C "$INST" commit -qm fx && "$INST/scripts/tick-delta.sh" record --instance "$INST"
}
check() { local out rc; out="$("$INST/scripts/tick-delta.sh" check --instance "$INST" 2>&1)"; rc=$?
          printf 'rc:%s %s' "$rc" "$(head -1 <<<"$out")"; }
UNL="rc:1 DELTA: $P has a design.md task no project critique saw — step 2 owes one."

fx build draft ""
ok "an existing design.md with no receipt is owed a critique"      "$(check)" "$UNL"
fx build done ""
ok "…whatever its tasks' statuses"                                 "$(check)" "$UNL"
fx research draft ""
ok "…never on a research project"                                  "$(check | cut -c1-10)" "rc:0 IDLE:"
fx build draft "2026-11-17T10:00:00Z $NC · saw: task-001 task-002"
ok "a receipt that saw every mapped task owes nothing"             "$(check | cut -c1-10)" "rc:0 IDLE:"
fx build draft "2026-11-17T10:00:00Z $NC · saw: task-001"
ok "design.md maps a task the receipt never saw: rerun owed"       "$(check)" "$UNL"
fx build draft "2026-11-17T10:00:00Z $NC · saw: task-001${N}2026-11-17T12:00:00Z $NC · saw: task-001 task-002"
ok "…the newest receipt's saw: list decides"                       "$(check | cut -c1-10)" "rc:0 IDLE:"
fx build draft "2026-11-17T10:00:00Z $NC"
ok "a receipt with no saw: list is no project receipt"             "$(check)" "$UNL"
fx build draft "2026-11-17T10:00:00Z · pre-mortem: do 001 and 002 conflict? · saw: task-001 task-002"
ok "an untriaged concern is a DELTA naming the project" \
   "$(check)" "rc:1 DELTA: $P has an untriaged project critique — step 2 owes it a triage."
fx build done "2026-11-17T10:00:00Z · pre-mortem: do 001 and 002 conflict? · saw: task-001 task-002"
ok "…whatever its tasks' statuses" \
   "$(check)" "rc:1 DELTA: $P has an untriaged project critique — step 2 owes it a triage."
fx build draft "2026-11-17T10:00:00Z · pre-mortem: do 001 and 002 conflict? · saw: task-001 task-002" \
   '* 2026-11-17T11:00:00Z triage: 0 resolved, 1 escalated\n'
ok "a triage line after it clears it, and the entry stays the receipt" "$(check | cut -c1-10)" "rc:0 IDLE:"
fx build draft "2026-11-17T10:00:00Z $NR (error) · saw: task-001 task-002"
ok "a lone not-run receipt owes one re-dispatch" "$(check)" "rc:1 DELTA: $P project critique not run — re-dispatch owed"
fx build draft "2026-11-17T10:00:00Z $NR (error) · saw: task-001 task-002${N}2026-11-17T12:00:00Z $NR (no result by step 8) · saw: task-001 task-002"
ok "…a second one ends the retries"                                "$(check | cut -c1-10)" "rc:0 IDLE:"
fx build draft "2026-11-17T10:00:00Z $NR (error) · saw: task-001${N}2026-11-17T11:00:00Z $NR (error) · saw: task-001${N}2026-11-17T12:00:00Z $NR (error) · saw: task-001 task-002"
ok "…counted per saw: list: a new list's first failure owes one" "$(check)" "rc:1 DELTA: $P project critique not run — re-dispatch owed"

echo "== lib/critique-receipt.sh =="
. "$S/lib/critique-receipt.sh"
m() { [ "$(printf '%s\n' "$1" | grep -cE "$2")" -gt 0 ] && echo yes || echo no; }
ok "project no-concerns with saw: is a receipt"  "$(m "2026-11-17T10:00:00Z $NC · saw: task-001" "$CRITIQUE_RECEIPT")" yes
ok "project not-run is a receipt"                "$(m "2026-11-17T10:00:00Z $NR (error) · saw: task-001" "$CRITIQUE_NOT_RUN")" yes
ok "…approach critique receipts still match"     "$(m '2026-11-17T10:00:00Z · advisor: approach critique — no concerns' "$CRITIQUE_RECEIPT")" yes
ok "a concern with saw: is not a receipt"        "$(m '2026-11-17T10:00:00Z · why? · saw: task-001' "$CRITIQUE_RECEIPT")" no

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
