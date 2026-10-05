#!/usr/bin/env bash
#
# kb-reflect.test.sh — plugin/scripts/kb-propose.sh and plugin/scripts/kb-apply.sh, the
# split a scheduled run PROPOSES and a human-typed /loopd:kb-apply APPLIES.
#
# BYTE-IDENTITY IS ASSERTED ON A PRODUCTIVE RUN. The proposer is a FIXTURE that always
# emits one proposal, because the real one is task-004 and depends on this task — a
# criterion needing the live reflector could never be met here, and a run with nothing to
# propose passes byte-identity trivially, which is the hole the criterion was written
# against. ok() compares actual to expected. Reasoning: knowledge-base-reflector/task-003.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROPOSE="$REPO/plugin/scripts/kb-propose.sh"
APPLY="$REPO/plugin/scripts/kb-apply.sh"
AWAIT="$REPO/plugin/scripts/build-awaiting.sh"
SKILL="$REPO/plugin/skills/kb-apply/SKILL.md"
STEP7="$REPO/plugin/tick-steps/step-7-knowledge-base.md"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
VALIDATE="$REPO/plugin/scripts/validate-bundle.sh"
for f in "$PROPOSE" "$APPLY"; do
  [ -x "$f" ] || { echo "kb-reflect.test: $f is missing or not executable" >&2; exit 2; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kbreflect.XXXXXX")" || {
  echo "kb-reflect.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'chmod -R u+rw "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
# Every file under knowledge/, each with its checksum — the before/after comparison.
kbsum() { find knowledge -type f -exec cksum {} + | sort; }
rows() { grep -c '^\* ' "$1" 2>/dev/null || true; }
# A script's executable lines. The header states the absences, so a grep over the whole
# file answers "is it written down", never "does it call it" — which is what is asserted.
code() { grep -vE '^[[:space:]]*#' "$1"; }

D="$TMP/bundle"
mkdir -p "$D/knowledge/findings" "$D/.ai-bridge"
item() { # <slug> <provenance>
  printf -- '---\ntype: Finding\ntitle: Title %s\ndescription: d\nlesson: l %s\ncategory: learning\ntags: [ ]\nstatus: current\nprovenance: %s\ntimestamp: 2026-10-01T00:00:00Z\n---\n\n# Finding\n\nThe claim of %s.\n' \
    "$1" "$1" "$2" "$1" >"$D/knowledge/findings/$1.md"
}
item keeper machine; item duplicate machine; item bystander machine; item handwritten human
cp "$REPO/plugin/seed/knowledge/vocab.md" "$D/knowledge/vocab.md"
printf 'index, regenerated\n' >"$D/knowledge/index.md"
printf '{ "org": "example-org" }\n' >"$D/instance.config.json"
cp "$REPO/plugin/seed/SCHEMA.md" "$D/.ai-bridge/SCHEMA.md"
cd "$D" || exit 2
git init -q . && git config user.name example-user-007 && git config user.email u@example.com
git add -A && git commit -qm init

# The fixture proposer: always exactly one proposal, so the run below is PRODUCTIVE.
ONE="$TMP/proposer-one.sh"
cat >"$ONE" <<'EOS'
#!/usr/bin/env bash
echo "supersede · duplicate · status=superseded · keeper · the same claim as keeper, said twice"
EOS
chmod +x "$ONE"

echo "== criterion 1: a PRODUCTIVE scheduled run reports, raises one row, and writes no byte of knowledge/ =="
BEFORE="$(kbsum)"
: >"$D/.ai-bridge/AWAITING.md"          # absence is the off switch; the human opted in
out="$("$PROPOSE" --proposer "$ONE" 2>"$TMP/propose.err")"; rc=$?
ok "the scheduled run exits 0 — it found something" "$rc" 0
ok "…and reports what it proposes"                  "$(grep -c '^KB REFLECTION: 1 proposal' <<<"$out")" 1
REPORT="$(sed -n 's/.* in \(projects[^ ]*\.md\) .*/\1/p' <<<"$out")"
ok "…naming a report that exists"                   "$([ -f "$REPORT" ] && echo yes || echo no)" yes
bash "$AWAIT" --instance "$D" >/dev/null 2>&1
ok "exactly one AWAITING.md row appears"            "$(rows "$D/.ai-bridge/AWAITING.md")" 1
ok "…and it is the report, asking the human"        "$(grep -c "answer.*Knowledge reflection" "$D/.ai-bridge/AWAITING.md")" 1
ok "EVERY file under knowledge/ is byte-identical"  "$([ "$BEFORE" = "$(kbsum)" ] && echo yes || echo no)" yes
ok "…and git sees no change there either"           "$(git status --porcelain knowledge/ | wc -l | tr -d ' ')" 0
ok "the report is a task document, so the row has a source" "$(head -1 <<<"$(sed -n 's/^type: //p' "$REPORT")")" Task
ok "…left as a draft the human never promotes"      "$(head -1 <<<"$(sed -n 's/^status: //p' "$REPORT")")" draft
ok "…carrying the one proposal"                     "$(grep -c '^P1 · supersede · duplicate · ' "$REPORT")" 1
ok "validate-bundle accepts the report"             "$("$VALIDATE" "$REPORT" 2>&1 | grep -c ERROR)" 0

echo "== criterion 2: the row comes from the normal machinery, never from the scheduled run =="
ok "kb-propose.sh contains no write to AWAITING.md" \
  "$(grep -cE 'AWAITING|AB_AWAITING' "$PROPOSE" | tr -d ' ')" 1
ok "…and that one mention is the prose saying it does not" \
  "$(grep -cE '^# .*never AWAITING\.md' "$PROPOSE" | tr -d ' ')" 1
ok "it calls neither build-awaiting.sh nor any renderer" \
  "$(code "$PROPOSE" | grep -c 'build-awaiting' | tr -d ' ')" 0
rm -f "$D/.ai-bridge/AWAITING.md"
bash "$AWAIT" --instance "$D" >/dev/null 2>&1
ok "absence stays the off switch across the whole path" "$([ -e "$D/.ai-bridge/AWAITING.md" ] && echo yes || echo no)" no
: >"$D/.ai-bridge/AWAITING.md"
bash "$AWAIT" --instance "$D" >/dev/null 2>&1
ok "…and the row is re-rendered from the task document alone" "$(rows "$D/.ai-bridge/AWAITING.md")" 1

echo "== criterion 3: apply is reachable only through the slash command =="
ok "the cron entry point contains no call to kb-apply.sh" "$(code "$PROPOSE" | grep -c 'kb-apply\.sh' | tr -d ' ')" 0
ok "…no call to ledger.sh, commit-as.sh or build-kb-index.sh" \
  "$(code "$PROPOSE" | grep -cE 'ledger\.sh|commit-as\.sh|build-kb-index\.sh' | tr -d ' ')" 0
ok "…and no git write verb at all"  "$(code "$PROPOSE" | grep -cE 'git (add|commit|mv|rm|checkout)' | tr -d ' ')" 0
# The positive control: an entry point that calls nothing would pass the three above.
ok "the skill DOES call it — the one path that applies" "$(grep -c 'scripts/kb-apply\.sh' "$SKILL" | tr -d ' ')" 2
ok "…and no other skill does"  "$(grep -rl 'scripts/kb-apply\.sh' "$REPO/plugin/skills" | wc -l | tr -d ' ')" 1
ok "…nor any agent"            "$(grep -rl 'kb-apply\.sh' "$REPO/plugin/agents" | wc -l | tr -d ' ')" 0
ok "the tick step runs the proposer and never the apply" \
  "$(grep -c 'kb-propose\.sh' "$STEP7")/$(grep -c 'kb-apply\.sh --by' "$STEP7")" "1/0"

echo "== criterion 4: apply writes what the report names, plus a stated exclusion set =="
bystander_before="$(cksum <knowledge/findings/bystander.md)"
head_before="$(git rev-parse HEAD)"
"$APPLY" --by example-user-007 "$REPORT" >/dev/null 2>"$TMP/apply.err"; rc=$?
ok "it applies"                                     "$rc" 0
ok "the proposed field is written"                  "$(head -1 <<<"$(sed -n 's/^status: //p' knowledge/findings/duplicate.md)")" superseded
ok "a change the report does not name is not applied" "$(cksum <knowledge/findings/bystander.md)" "$bystander_before"
ok "…and the keeper's own frontmatter is untouched" "$(head -1 <<<"$(sed -n 's/^status: //p' knowledge/findings/keeper.md)")" current
ok "the exclusion set: the per-item ledger entry"   "$(grep -c '^ledger:.*supersede.*items duplicate,keeper' knowledge/findings/duplicate.md)" 1
ok "…recording the human, never a role"             "$(grep -c 'by example-user-007' knowledge/findings/duplicate.md)" 1
ok "the exclusion set: the derived index is regenerated" \
  "$([ "$(cksum <knowledge/index.md)" != "$(git show "$head_before":knowledge/index.md | cksum)" ] && echo yes || echo no)" yes
ok "the exclusion set: the report is closed"        "$(head -1 <<<"$(sed -n 's/^status: //p' "$REPORT")")" done
ok "the exclusion set: exactly one commit"          "$(git rev-list --count "$head_before"..HEAD)" 1
ok "…and nothing it touched is left uncommitted"    "$(git status --porcelain knowledge/ "$REPORT" | wc -l | tr -d ' ')" 0
ok "the commit touches only what the report + the exclusion set name" \
  "$(git show --name-only --format= HEAD | sort | tr '\n' ' ')" \
  "knowledge/.ledger-floor knowledge/findings/duplicate.md knowledge/index.md $REPORT "
ok "the same report applied twice is refused"       "$("$APPLY" --by example-user-007 "$REPORT" >/dev/null 2>&1; echo $?)" 1

echo "== the refusals that make nothing else true =="
: >"$D/.ai-bridge/AWAITING.md"
P2="$TMP/proposer-human.sh"
printf '#!/usr/bin/env bash\necho "edit · handwritten · status=superseded · - · reads like keeper"\n' >"$P2"
chmod +x "$P2"
before2="$(kbsum)"
ok "a proposal against a human-authored item is dropped" "$("$PROPOSE" --proposer "$P2" >/dev/null 2>&1; echo $?)" 1
ok "…leaving knowledge/ byte-identical"             "$([ "$before2" = "$(kbsum)" ] && echo yes || echo no)" yes
ok "no proposer configured is silence, not a failure" "$("$PROPOSE" >/dev/null 2>&1; echo $?)" 1
ok "a proposer that FAILED is unknown, never nothing to propose" \
  "$("$PROPOSE" --proposer 'exit 7' >/dev/null 2>&1; echo $?)" 2
P3="$TMP/proposer-two.sh"
cat >"$P3" <<'EOS'
#!/usr/bin/env bash
echo "status · keeper · status=corrected · - · a second look"
echo "edit · bystander · lesson=a tightened claim · - · the lesson restated"
EOS
chmod +x "$P3"
out2="$("$PROPOSE" --proposer "$P3" 2>/dev/null)"
R2="$(sed -n 's/.* in \(projects[^ ]*\.md\) .*/\1/p' <<<"$out2")"
ok "a second run reports two proposals"             "$(grep -c '^P[12] · ' "$R2")" 2
sed -i.bak 's/^title: Title keeper$/title: Title keeper edited/' knowledge/findings/keeper.md && rm -f knowledge/findings/keeper.md.bak
by_before="$(cksum <knowledge/findings/bystander.md)"
ok "an item edited since the report refuses the WHOLE report" \
  "$("$APPLY" --by example-user-007 "$R2" >/dev/null 2>&1; echo $?)" 1
ok "…applying none of it — the second item is untouched" "$(cksum <knowledge/findings/bystander.md)" "$by_before"
ok "…and the report stays open"                     "$(head -1 <<<"$(sed -n 's/^status: //p' "$R2")")" draft
ok "a role name as --by is refused"                 "$("$APPLY" --by cataloguer "$R2" >/dev/null 2>&1; echo $?)" 2
ok "a report outside projects/*/tasks/ is refused"  "$("$APPLY" --by example-user-007 knowledge/index.md >/dev/null 2>&1; echo $?)" 1
echo "== round 2: the write scope is closed, and a partial apply cannot start =="
LEDGER_BEFORE="$(grep -c '^ledger:' knowledge/findings/duplicate.md)"
for k in ledger provenance; do
  printf '#!/usr/bin/env bash\necho "edit · bystander · %s=x · - · why"\n' "$k" >"$TMP/p-$k.sh"
  chmod +x "$TMP/p-$k.sh"
  # Its own project slug: the default one already holds a draft report, and the
  # waiting-report guard would short-circuit before the proposer ever ran.
  ok "a proposal writing $k: is dropped at propose" \
    "$("$PROPOSE" --proposer "$TMP/p-$k.sh" --project "kb-r2-$k" 2>&1 >/dev/null | grep -c "'$k' is not a proposal")" 1
  ok "…and no report was written for it" "$([ -d "projects/kb-r2-$k/tasks" ] && ls "projects/kb-r2-$k/tasks" | grep -c . || echo 0)" 0
done
# propose already refuses these, so apply needs a hand-built report of its own. Each
# assertion reads the REFUSAL TEXT: an exit 1 for some earlier reason would prove nothing.
FORGED=projects/knowledge-reflection/tasks/task-098-forged.md
mk() { { sed -n '1,/^---$/p' "$R2" | sed 's/^status: .*/status: draft/'
         printf '\n# Proposals\n\n%s\n' "$1"; } >"$FORGED"; }
refusal() { "$APPLY" --by example-user-007 "$FORGED" 2>&1 >/dev/null | tail -1; }
FP="$(cksum <knowledge/findings/duplicate.md | awk '{print $1 "-" $2}')"
mk "P1 · edit · duplicate · ledger=[] · - · $FP · wipe it"
ok "a ledger: write is refused before any write lands" \
  "$(refusal | grep -c "'ledger' is not a proposal")" 1
ok "…leaving the item's ledger intact"       "$(grep -c '^ledger:' knowledge/findings/duplicate.md)" "$LEDGER_BEFORE"
mk "P1 · edit · duplicate · title=A · - · $FP · one
P2 · edit · duplicate · lesson=B · - · $FP · two"
ok "two proposals naming one item are refused" \
  "$(refusal | grep -c 'named by more than one proposal')" 1
mk "P1 · supersede · duplicate · status=superseded · duplicate · $FP · itself"
ok "--with naming the item itself is refused before the field write" \
  "$(refusal | grep -c 'names duplicate itself')" 1
ok "…and that item is byte-identical"        "$(cksum <knowledge/findings/duplicate.md | awk '{print $1 "-" $2}')" "$FP"
rm -f "$FORGED"
ok "a '..' project slug is refused, not resolved" \
  "$("$PROPOSE" --proposer "$ONE" --project .. >/dev/null 2>&1; echo $?)" 2
ok "…and no tasks/ appeared at the instance root" "$([ -e tasks ] && echo yes || echo no)" no
printf 'lock\n' >"$D/.ai-bridge/.tick-lock"
ok "apply stands down while a tick holds the lock" \
  "$("$APPLY" --by example-user-007 "$R2" 2>&1 >/dev/null | grep -c 'holds the dispatch lock')" 1
rm -f "$D/.ai-bridge/.tick-lock" "$D/.ai-bridge/.tick-lock.claim"
ok "…and clears once it is free"             "$(bash "$REPO/plugin/scripts/tick-lock.sh" status --instance "$D" >/dev/null 2>&1; echo $?)" 0
ok "the skill discovers reports under ANY project slug" \
  "$(grep -c 'projects/\*/tasks/\*\.md' "$SKILL")" 1

ok "a report that is still waiting blocks a second run" \
  "$("$PROPOSE" --proposer "$ONE" >/dev/null 2>&1; echo $?)" 1
SHORT=projects/knowledge-reflection/tasks/task-099-short.md
sed 's/^P1 · .*/P1 · status · keeper/' "$R2" >"$SHORT"
ok "a truncated proposal line refuses the whole report" \
  "$("$APPLY" --by example-user-007 "$SHORT" >/dev/null 2>&1; echo $?)" 1
rm -f "$SHORT"

echo "== criterion 6: the command is namespaced, state-changing and documented =="
ok "the skill ships"                                "$([ -f "$SKILL" ] && echo yes || echo no)" yes
ok "…named for its directory"                       "$(head -1 <<<"$(sed -n 's/^name: //p' "$SKILL")")" kb-apply
ok "…human-triggered, never model-invoked"          "$(head -1 <<<"$(sed -n 's/^disable-model-invocation: //p' "$SKILL")")" true
ok "…and it is in plugin-skills.test.sh's STATE_CHANGING list" \
  "$(grep -c '^STATE_CHANGING=.*kb-apply' "$REPO/tests/plugin-skills.test.sh")" 1
ok "the README's command table carries the row"     "$(grep -c '^| `/loopd:kb-apply <report>` |' "$REPO/README.md")" 1
ok "SCHEMA.md defines the report"                   "$(grep -c '^### The reflection report' "$SCHEMA")" 1
ok "…and names both halves"                         "$(grep -c 'scripts/kb-propose.sh' "$SCHEMA")/$(grep -c 'scripts/kb-apply.sh' "$SCHEMA")" "1/1"

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
