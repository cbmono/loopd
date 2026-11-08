#!/usr/bin/env bash
#
# conventions-invariants.test.sh — every invariant in tests/fixtures/conventions-invariants.tsv
# is carried by the CONVENTIONS.md CORE alone (leaner-prompts/task-002). The list starts from
# seed CLAUDE.md's "These are invariants" bullets plus the authority gates, one fixed anchor
# each. It reads the core and never a conventions/ detail file, so a rule moved out of the core
# fails here instead of passing through the detail. Rows whose source starts `pm ` are
# project-manager.md's (leaner-prompts/task-003), read against that file alone, never a
# tick-steps/ file.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$REPO/plugin/seed/CONVENTIONS.md"
LIST="$REPO/tests/fixtures/conventions-invariants.tsv"
SEED="$REPO/plugin/seed/CLAUDE.md"
PM="$REPO/plugin/agents/project-manager.md"
STEPS="$REPO/plugin/tick-steps"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/conventions-invariants.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
entries() { grep -v '^#' "$1" | grep -v '^$'; }
conv_rows() { entries "$1" | awk -F'\t' '$3 !~ /^pm /'; }
pm_rows()   { entries "$1" | awk -F'\t' '$3 ~ /^pm /'; }
# missing <core> <list> — the ids whose anchor the core does not carry, whitespace-folded.
missing() { # [row-filter]
  local text id anchor src
  text="$(tr '\n' ' ' < "$1" | tr -s ' ')"
  while IFS=$'\t' read -r id anchor src; do
    case "$text" in *"$anchor"*) ;; *) echo "$id" ;; esac
  done <<<"$(${3:-entries} "$2")"
}

echo "== the list =="
n="$(entries "$LIST" | wc -l | tr -d ' ')"
ok "the list is readable and non-trivial (is $n)" "$([ "$n" -ge 20 ] && echo yes || echo no)" yes
ok "every entry has three fields" "$(entries "$LIST" | awk -F'\t' 'NF!=3' | wc -l | tr -d ' ')" 0
ok "ids are listed once" "$(entries "$LIST" | cut -f1 | sort | uniq -d | wc -l | tr -d ' ')" 0
ok "anchors are listed once" "$(entries "$LIST" | cut -f2 | sort | uniq -d | wc -l | tr -d ' ')" 0
# The seed's invariant bullets, counted from the seed itself: a ninth one needs a row here.
k="$(awk '/^\*\*These are invariants/{p=1;next} p&&/^## /{exit} p&&/^- /{n++} END{print n+0}' "$SEED")"
ok "seed CLAUDE.md lists its invariants (is $k)" "$([ "$k" -ge 8 ] && echo yes || echo no)" yes
unlisted=""; i=1
while [ "$i" -le "$k" ]; do
  grep -qx "seed CLAUDE.md invariant $i" <<<"$(entries "$LIST" | cut -f3)" || unlisted="$unlisted $i"
  i=$((i+1))
done
ok "every seed invariant has an anchor" "${unlisted:-none}" none
ok "the authority gates are listed" "$(entries "$LIST" | cut -f3 | grep -cx 'authority gate' | awk '{print ($1>=10)?"yes":"no"}')" yes

echo "== the core carries every one =="
M="$(missing "$CORE" "$LIST" conv_rows)"
ok "no invariant is missing from the core" "$(printf '%s' "$M" | grep -c . | tr -d ' ')" 0
[ -z "$M" ] || printf '        %s\n' $M

echo "== mutants =="
awk '/^### The criteria table is the merge gate$/{s=1;next} s&&/^##/{s=0} !s' "$CORE" > "$TMP/core-cut.md"
MM="$(missing "$TMP/core-cut.md" "$LIST" conv_rows | tr '\n' ' ')"
ok "cutting one section flips its invariants" "$MM" "criteria-table-always tick-only-verified row-is-command unverified-blocks-merge "
DETAIL_ONLY='400 is the midpoint of the empty band 378–421'
printf 'planted\t%s\tauthority gate\n' "$DETAIL_ONLY" > "$TMP/list.tsv"
ok "CONTROL: the planted anchor is in a detail file" "$(cat "$REPO"/plugin/seed/conventions/*.md | tr '\n' ' ' | tr -s ' ' | grep -cF "$DETAIL_ONLY" | tr -d ' ')" 1
ok "…and still fails: the detail is never read" "$(missing "$CORE" "$TMP/list.tsv")" planted

echo "== project-manager.md carries its own, and a tick-steps/ file never stands in =="
ok "the PM rows are listed (is $(pm_rows "$LIST" | wc -l | tr -d ' '))" "$(pm_rows "$LIST" | wc -l | awk '{print ($1>=20)?"yes":"no"}')" yes
ok "…both the gates and the every-tick rules" "$(pm_rows "$LIST" | cut -f3 | sort -u | tr '\n' ',')" "pm every tick,pm gate,"
P="$(missing "$PM" "$LIST" pm_rows)"
ok "no PM invariant is missing from project-manager.md" "$(printf '%s' "$P" | grep -c . | tr -d ' ')" 0
[ -z "$P" ] || printf '        %s\n' $P
awk '/^## Authority boundaries/{s=1;next} s&&/^## /{s=0} !s' "$PM" > "$TMP/pm-cut.md"
ok "cutting the authority section flips its invariants" "$(missing "$TMP/pm-cut.md" "$LIST" pm_rows | tr '\n' ' ')" \
   "pm-never-ready pm-never-merge pm-own-work pm-owner-script pm-paused-script pm-autonomy-resolver pm-gated-default pm-one-call "
STEP_ONLY='A task with no dispatch lines records `usage UNKNOWN`, never zero'
printf 'planted\t%s\tpm every tick\n' "$STEP_ONLY" > "$TMP/pm-list.tsv"
ok "CONTROL: the planted anchor is in a step file" "$(cat "$STEPS"/*.md | tr '\n' ' ' | tr -s ' ' | grep -cF "$STEP_ONLY" | tr -d ' ')" 1
ok "…and still fails: project-manager.md alone is read" "$(missing "$PM" "$TMP/pm-list.tsv" pm_rows)" planted

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
