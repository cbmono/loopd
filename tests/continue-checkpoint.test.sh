#!/usr/bin/env bash
# continue-checkpoint.sh + build-awaiting.sh — the "should this continue?" row
# (value-gate-at-intake task-003). Every fixture CREATES AWAITING.md: absent is off for good,
# so a fixture without it would pass while the feature was dead.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CK="$REPO/plugin/scripts/continue-checkpoint.sh"
AW="$REPO/plugin/scripts/build-awaiting.sh"
TD="$REPO/plugin/scripts/tick-delta.sh"
. "$REPO/plugin/scripts/bundle-paths.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/continue-checkpoint.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
export CHECKPOINT_TODAY=2026-10-05

# <dir> <config json> — an instance with AWAITING.md present
inst() {
  mkdir -p "$1/projects" "$1/$AB_DIR"
  printf '%s\n' "$2" > "$1/instance.config.json"
  printf '# SCHEMA\n' > "$1/$AB_SCHEMA"
  : > "$1/$AB_AWAITING"
}
# <dir> <slug> <timestamp> <done> <open> [extra frontmatter line]...
proj() {
  local d="$1" s="$2" ts="$3" nd="$4" no="$5" i; shift 5
  mkdir -p "$d/projects/$s/tasks"
  { printf -- '---\ntype: Project\ntitle: "%s"\nno_owner: Dana\nstatus: active\ntimestamp: %s\n' "$s" "$ts"
    for i in "$@"; do printf '%s\n' "$i"; done; printf -- '---\n'; } > "$d/projects/$s/project.md"
  for ((i = 1; i <= nd; i++)); do printf -- '---\ntype: Task\nstatus: done\n---\n' > "$d/projects/$s/tasks/d$i.md"; done
  for ((i = 1; i <= no; i++)); do printf -- '---\ntype: Task\nstatus: ready\n---\n' > "$d/projects/$s/tasks/o$i.md"; done
}
rows() { bash "$AW" --instance "$1" >/dev/null 2>&1; grep -c '^\* ⏳ \*\*continue\*\*' "$1/$AB_AWAITING"; }
row_for() { grep "^\* ⏳ \*\*continue\*\* — \[$2\]" "$1/$AB_AWAITING"; }
CFG='{ "org": "demo", "continueAfterTasks": 16, "continueAfterDays": 20 }'

echo "== opt-in: an unconfigured bundle never asks =="
U="$TMP/unconfigured"; inst "$U" '{ "org": "demo" }'
proj "$U" big 2026-01-01T00:00:00Z 40 1 "timebox: 1d"
ok "continue-checkpoint.sh prints nothing" "$(bash "$CK" --instance "$U" | wc -l | tr -d ' ')" 0
ok "no continue row on a project past every threshold" "$(rows "$U")" 0
inst "$TMP/nulls" '{ "continueAfterTasks": null, "continueAfterDays": "soon" }'
proj "$TMP/nulls" big 2026-01-01T00:00:00Z 40 1
ok "null or non-integer keys are absent, not a default" "$(rows "$TMP/nulls")" 0

echo
echo "== every active project past N, and a time-boxed one sooner — asserted separately =="
A="$TMP/asks"; inst "$A" "$CFG"
proj "$A" by-tasks  2026-10-01T00:00:00Z 16 1
proj "$A" by-days   2026-09-10T00:00:00Z 2 1
proj "$A" below     2026-09-20T00:00:00Z 15 1
proj "$A" boxed     2026-09-27T00:00:00Z 1 1 "timebox: 1w"
proj "$A" boxed-in  2026-10-01T00:00:00Z 1 1 "timebox: 2w"
proj "$A" bad-box   2026-09-27T00:00:00Z 1 1 "timebox: 1 week"
rows "$A" >/dev/null
ok "an unlabelled project at N tasks done is asked" "$(row_for "$A" by-tasks | grep -c '16 tasks done since started')" 1
ok "an unlabelled project N days old is asked" "$(row_for "$A" by-days | grep -c '25 days since started')" 1
ok "an unlabelled project below both is not" "$(row_for "$A" below | wc -l | tr -d ' ')" 0
ok "a time-boxed project is asked BEFORE either N" "$(row_for "$A" boxed | grep -c '1w time-box ran out (8 days')" 1
ok "…but not before its box runs out" "$(row_for "$A" boxed-in | wc -l | tr -d ' ')" 0
ok "a malformed timebox is no time-box" "$(row_for "$A" bad-box | wc -l | tr -d ' ')" 0
ok "the row names the person in no_owner:" "$(row_for "$A" by-tasks | grep -c 'Dana: should this continue?')" 1
ok "exactly three rows, one per due project" "$(grep -c '^\* ⏳' "$A/$AB_AWAITING")" 3
ok "the queue heading counts them" "$(grep -c '^## 🔴 Awaiting you (3)$' "$A/$AB_AWAITING")" 1

echo
echo "== report-only: it asks and changes nothing =="
B="$TMP/readonly"; inst "$B" "$CFG"; proj "$B" big 2026-01-01T00:00:00Z 20 2
( cd "$B" && find projects instance.config.json -type f -exec cksum {} + | sort ) > "$TMP/before"
rows "$B" >/dev/null
( cd "$B" && find projects instance.config.json -type f -exec cksum {} + | sort ) > "$TMP/after"
ok "every project and task file is byte-identical after a render" "$(cmp -s "$TMP/before" "$TMP/after" && echo same || echo changed)" same
ok "no status: was rewritten" "$(grep -rh '^status:' "$B/projects" | grep -c -e active -e ready -e done)" 23
ok "no AWAITING.md ⇒ none is created" "$(rm "$B/$AB_AWAITING"; bash "$AW" --instance "$B" >/dev/null; [ -e "$B/$AB_AWAITING" ] && echo yes || echo no)" no

echo
echo "== once: the record is tracked frontmatter, and the clock re-arms from it =="
O="$TMP/once"; inst "$O" "$CFG"; proj "$O" big 2026-09-01T00:00:00Z 3 1
ok "a due project renders one row" "$(rows "$O")" 1
ok "…and still one on the next render, never two" "$(rows "$O")" 1
rec="$(row_for "$O" big | sed -n 's/.*add `continued: \([^`]*\)`.*/\1/p')"
ok "the row prints the exact record to add" "$rec" "2026-10-05 3"
proj "$O" big 2026-09-01T00:00:00Z 3 1 "continued: $rec"
ok "with continued: recorded, it is not asked" "$(rows "$O")" 0
ok "…19 days later, still not" "$(CHECKPOINT_TODAY=2026-10-24 rows "$O")" 0
ok "…20 days after the answer it re-arms" "$(CHECKPOINT_TODAY=2026-10-25 rows "$O")" 1
proj "$O" big 2026-09-01T00:00:00Z 19 1 "continued: 2026-10-05 3"
rows "$O" >/dev/null
ok "16 more tasks done since the answer re-arm it" "$(row_for "$O" big | grep -c '16 tasks done since continued')" 1
proj "$O" big 2026-09-01T00:00:00Z 3 1 "continued: yes"
ok "an unreadable continued: is no answer — it asks" "$(rows "$O")" 1

echo
echo "== who decides when no_owner: is empty: the creator, then defaultOwner =="
W="$TMP/who"; inst "$W" '{ "continueAfterDays": 20, "defaultOwner": "example-user-008" }'
printf '{ "ownerGithubUser": "example-user-008" }\n' > "$W/instance.config.local.json"
proj "$W" made 2026-09-01T00:00:00Z 0 1; sed -i.bak 's/^no_owner: Dana$/no_owner:/' "$W/projects/made/project.md"
proj "$W" orphan 2026-09-01T00:00:00Z 0 1; sed -i.bak 's/^no_owner: Dana$/no_owner:/' "$W/projects/orphan/project.md"
printf '## 2026-09-02 — Project added: made-later\n\nAdded by example-user-008.\n\n## 2026-09-01 — Project added: made\n\n**Added 2026-09-01T00:00:00Z by example-user-007.** Measured by hand.\n' > "$W/$AB_LEDGER"
rows "$W" >/dev/null
ok "empty no_owner: ⇒ the login on the creation entry" "$(row_for "$W" made | grep -c 'example-user-007: should')" 1
ok "no creation entry ⇒ defaultOwner" "$(row_for "$W" orphan | grep -c 'example-user-008: should')" 1

echo
echo "== the other gates still hold =="
G="$TMP/gates"; inst "$G" "$CFG"
proj "$G" paused 2026-01-01T00:00:00Z 20 1; sed -i.bak 's/^status: active$/status: paused/' "$G/projects/paused/project.md"
proj "$G" finished 2026-01-01T00:00:00Z 20 0
proj "$G" theirs 2026-01-01T00:00:00Z 20 1 "owner: example-user-008"
printf '{ "ownerGithubUser": "example-user-007" }\n' > "$G/instance.config.local.json"
rows "$G" >/dev/null
ok "a paused project is not asked (paused is the answer)" "$(row_for "$G" paused | wc -l | tr -d ' ')" 0
ok "an all-terminal project gets close, not continue" "$(grep -c '🏁 \*\*close\*\* — \[finished\]' "$G/$AB_AWAITING"):$(row_for "$G" finished | wc -l | tr -d ' ')" 1:0
ok "another human's project stays out of this clone's queue" "$(row_for "$G" theirs | wc -l | tr -d ' ')" 0

echo
echo "== the idle fast-path sees a project cross its threshold =="
T="$TMP/tick"; inst "$T" "$CFG"; proj "$T" slow 2026-09-20T00:00:00Z 1 1
git -C "$T" init -q && git -C "$T" -c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false add -A \
  && git -C "$T" -c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false commit -qm init
fp() { bash "$TD" digest --instance "$T" 2>/dev/null | grep '^checkpoint'; }
ok "below the threshold the due set is empty" "$(fp)" "checkpoint "
ok "a stalled project crossing it moves the fingerprint" "$(CHECKPOINT_TODAY=2026-10-10 fp)" "checkpoint /projects/slow/project.md "
ok "…and no queue means no checkpoint line" "$(rm "$T/$AB_AWAITING"; fp | wc -l | tr -d ' ')" 0

echo
echo "continue-checkpoint: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
