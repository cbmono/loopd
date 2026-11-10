#!/usr/bin/env bash
#
# kb-apply.test.sh — plugin/scripts/kb-apply.sh, run by a human in their own terminal:
# it applies exactly what one hand-written report names, and refuses the whole report on
# any doubt. ok() compares actual to expected. Reasoning: knowledge-base-reflector/task-003.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APPLY="$REPO/plugin/scripts/kb-apply.sh"
AWAIT="$REPO/plugin/scripts/build-awaiting.sh"
STEP7="$REPO/plugin/tick-steps/step-7-knowledge-base.md"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
VALIDATE="$REPO/plugin/scripts/validate-bundle.sh"
[ -x "$APPLY" ] || { echo "kb-apply.test: $APPLY is missing or not executable" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kbapply.XXXXXX")" || {
  echo "kb-apply.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'chmod -R u+rw "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
# Every file under knowledge/, each with its checksum — the before/after comparison.
kbsum() { find knowledge -type f -exec cksum {} + | sort; }
rows() { grep -c '^\* ' "$1" 2>/dev/null || true; }
fp() { cksum <"$1" | awk '{print $1 "-" $2}'; }
# A hand-written report: a draft task carrying the given P<n> lines.
report() { # <path> <proposal lines>
  mkdir -p "$(dirname "$1")"
  local pj; pj="$(dirname "$(dirname "$1")")/project.md"
  [ -f "$pj" ] || printf -- '---\ntype: Project\ntitle: Knowledge reflection\ndescription: "Hand-written reports for plugin/scripts/kb-apply.sh."\nkind: build\nstatus: active\nretain: true\ntimestamp: 2026-10-22T00:00:00Z\n---\n\n# Context\n\nReports.\n' >"$pj"
  printf -- '---\ntype: Task\ntitle: "Knowledge reflection — to review"\nkind: build\nstatus: draft\nassignee: human\nacceptance_criteria: [ ]\nopen_questions:\n  - "Apply this report? Read it, then run plugin/scripts/kb-apply.sh. Decline by cancelling this task."\ntimestamp: 2026-10-22T00:00:00Z\n---\n\n# Proposals\n\n%s\n' "$2" >"$1"
}

D="$TMP/bundle"
mkdir -p "$D/knowledge/findings" "$D/.loopd"
item() { # <slug> <provenance>
  printf -- '---\ntype: Finding\ntitle: Title %s\ndescription: d\nlesson: l %s\ncategory: learning\ntags: [ ]\nstatus: current\nprovenance: %s\ntimestamp: 2026-10-01T00:00:00Z\n---\n\n# Finding\n\nThe claim of %s.\n' \
    "$1" "$1" "$2" "$1" >"$D/knowledge/findings/$1.md"
}
item keeper machine; item duplicate machine; item bystander machine; item handwritten human
cp "$REPO/plugin/seed/knowledge/vocab.md" "$D/knowledge/vocab.md"
printf 'index, regenerated\n' >"$D/knowledge/index.md"
printf '{ "org": "example-org" }\n' >"$D/instance.config.json"
cp "$REPO/plugin/seed/SCHEMA.md" "$D/.loopd/SCHEMA.md"
cd "$D" || exit 2
git init -q . && git config user.name example-user-007 && git config user.email u@example.com
git add -A && git commit -qm init

echo "== a hand-written report renders as one row and touches no byte of knowledge/ =="
BEFORE="$(kbsum)"
REPORT=projects/knowledge-reflection/tasks/task-001-knowledge-reflection.md
report "$REPORT" "P1 · supersede · duplicate · status=superseded · keeper · $(fp knowledge/findings/duplicate.md) · the same claim as keeper, said twice"
: >"$D/.loopd/AWAITING.md"          # absence is the off switch; the human opted in
bash "$AWAIT" --instance "$D" >/dev/null 2>&1
ok "exactly one AWAITING.md row appears"            "$(rows "$D/.loopd/AWAITING.md")" 1
ok "…and it is the report, asking the human"        "$(grep -c "answer.*Knowledge reflection" "$D/.loopd/AWAITING.md")" 1
ok "EVERY file under knowledge/ is byte-identical"  "$([ "$BEFORE" = "$(kbsum)" ] && echo yes || echo no)" yes
ok "validate-bundle accepts the report"             "$("$VALIDATE" "$REPORT" 2>&1 | grep -c ERROR)" 0
rm -f "$D/.loopd/AWAITING.md"
bash "$AWAIT" --instance "$D" >/dev/null 2>&1
ok "absence stays the off switch"                   "$([ -e "$D/.loopd/AWAITING.md" ] && echo yes || echo no)" no

echo "== apply is reachable only by a human running the script =="
ok "no skill calls it"         "$(grep -rl 'kb-apply\.sh' "$REPO/plugin/skills" | wc -l | tr -d ' ')" 0
ok "the hook's refusal names the script" "$(grep -c 'run `plugin/scripts/kb-apply.sh --by <login> --human-docs <slugs> <report>` in their own terminal' "$REPO/plugin/hooks/deny-destructive.sh")" 1
ok "…nor any agent"            "$(grep -rl 'kb-apply\.sh' "$REPO/plugin/agents" | wc -l | tr -d ' ')" 0
ok "…nor the tick's knowledge step" "$(grep -c 'kb-apply\.sh --by' "$STEP7")" 0

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
ok "the exclusion set: the report is closed"        "$(head -1 <<<"$(sed -n 's/^status: //p' "$REPORT")")" "done"
ok "the exclusion set: exactly one commit"          "$(git rev-list --count "$head_before"..HEAD)" 1
ok "…and nothing it touched is left uncommitted"    "$(git status --porcelain knowledge/ "$REPORT" | wc -l | tr -d ' ')" 0
ok "the commit touches only what the report + the exclusion set name" \
  "$(git show --name-only --format= HEAD | sort | tr '\n' ' ')" \
  "knowledge/.ledger-floor knowledge/findings/duplicate.md knowledge/index.md $REPORT "
ok "the same report applied twice is refused"       "$("$APPLY" --by example-user-007 "$REPORT" >/dev/null 2>&1; echo $?)" 1

echo "== the refusals that make nothing else true =="
R2=projects/knowledge-reflection/tasks/task-002-knowledge-reflection.md
report "$R2" "P1 · status · keeper · status=corrected · - · $(fp knowledge/findings/keeper.md) · a second look
P2 · edit · bystander · lesson=a tightened claim · - · $(fp knowledge/findings/bystander.md) · the lesson restated"
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
# Each assertion reads the REFUSAL TEXT: an exit 1 for some earlier reason would prove nothing.
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
printf 'lock\n' >"$D/.loopd/.tick-lock"
ok "apply stands down while a tick holds the lock" \
  "$("$APPLY" --by example-user-007 "$R2" 2>&1 >/dev/null | grep -c 'holds the dispatch lock')" 1
rm -f "$D/.loopd/.tick-lock" "$D/.loopd/.tick-lock.claim"
ok "…and clears once it is free"             "$(bash "$REPO/plugin/scripts/tick-lock.sh" status --instance "$D" >/dev/null 2>&1; echo $?)" 0

SHORT=projects/knowledge-reflection/tasks/task-099-short.md
sed 's/^P1 · .*/P1 · status · keeper/' "$R2" >"$SHORT"
ok "a truncated proposal line refuses the whole report" \
  "$("$APPLY" --by example-user-007 "$SHORT" >/dev/null 2>&1; echo $?)" 1
rm -f "$SHORT"

echo "== criterion 6: the script is documented, and no slash command fronts it =="
# path-scan: absent — the slash command is retired; its absence IS the assertion
ok "no kb-apply skill ships"                        "$([ -e "$REPO/plugin/skills/kb-apply" ] && echo yes || echo no)" no
ok "SCHEMA.md defines the report"                   "$(grep -c '^### The reflection report' "$SCHEMA")" 1
ok "…and names the apply path"                      "$(grep -c 'plugin/scripts/kb-apply.sh`, run by a human' "$SCHEMA")" 1

echo "== human-written docs: tags and status=archived only, only with --human-docs naming them =="
D2="$TMP/bundle-hd"
mkdir -p "$D2/knowledge/findings" "$D2/.loopd"
hitem() { # <slug> <provenance|-> [a block-form tags: item line…]
  local slug="$1" prov="$2"; shift 2
  { printf -- '---\ntype: Finding\ntitle: Title %s\ndescription: d\nlesson: l\ncategory: learning\n' "$slug"
    if [ $# -gt 0 ]; then printf 'tags:\n'; printf '%s\n' "$@"; else printf 'tags: [ ]\n'; fi
    printf 'status: current\n'
    [ "$prov" = - ] || printf 'provenance: %s\n' "$prov"
    printf 'timestamp: 2026-10-01T00:00:00Z\n---\n\n# Finding\n\nA claim.\n'
  } >"$D2/knowledge/findings/$slug.md"
}
hitem m1 machine; hitem h1 human; hitem h2 human; hitem x1 mixed; hitem noprov -; hitem odd robot
hitem blk human '  - a' '  - b'; hitem blkgap human '' '  - a'; hitem blkhash human '# a comment' '  - a'
cp "$REPO/plugin/seed/knowledge/vocab.md" "$D2/knowledge/vocab.md"
printf 'index, regenerated\n' >"$D2/knowledge/index.md"
printf '{ "org": "example-org" }\n' >"$D2/instance.config.json"
cp "$REPO/plugin/seed/SCHEMA.md" "$D2/.loopd/SCHEMA.md"
cd "$D2" || exit 2
git init -q . && git config user.name example-user-007 && git config user.email u@example.com
git add -A && git commit -qm init
fp() { cksum <"knowledge/findings/$1.md" | awk '{print $1 "-" $2}'; }
rep() { # <name> <proposal lines> -> $R
  R="projects/kb-hd/tasks/$1.md"; mkdir -p projects/kb-hd/tasks
  printf -- '---\ntype: Task\ntitle: "r"\nkind: build\nstatus: draft\nassignee: human\nacceptance_criteria: [ ]\nopen_questions: [ ]\ntimestamp: 2026-10-22T00:00:00Z\n---\n\n# Proposals\n\n%s\n' "$2" >"$R"
}
# exit 1, knowledge/ byte-identical, and the refusal it was refused FOR — an exit 1 for an
# earlier reason would prove nothing.
refuse() { # <name> <reason pattern> <kb-apply args…>
  local name="$1" pat="$2" before err rc; shift 2
  before="$(kbsum)"
  err="$("$APPLY" --by example-user-007 "$@" 2>&1 >/dev/null)"; rc=$?
  ok "$name" "$rc/$([ "$before" = "$(kbsum)" ] && echo same || echo changed)/$(grep -c -- "$pat" <<<"$err")" "1/same/1"
}
rep only-human "P1 · edit · h1 · tags=[a] · - · $(fp h1) · tag it"
refuse "a human doc without --human-docs is refused, knowledge/ identical" "only when --human-docs names it" "$R"
rep mixed "P1 · edit · m1 · title=New · - · $(fp m1) · retitle
P2 · edit · h1 · tags=[a] · - · $(fp h1) · tag it
P3 · status · x1 · status=archived · - · $(fp x1) · stale"
MIXED="$R"
refuse "an EXTRA slug in --human-docs is refused"      "is not exactly" --human-docs h1,x1,m1 "$MIXED"
refuse "a MISSING slug in --human-docs is refused"     "is not exactly" --human-docs h1 "$MIXED"
refuse "a DUPLICATED slug in --human-docs is refused"  "names a slug twice" --human-docs h1,x1,h1 "$MIXED"
rep machine-only "P1 · edit · m1 · title=New · - · $(fp m1) · retitle"
refuse "--human-docs on a report with no human doc is refused" "changes no human-written doc" --human-docs m1 "$R"
rep k-merge "P1 · merge · h1 · status=superseded · m1 · $(fp h1) · fold";       refuse "a merge of a human doc is refused"      "takes only" --human-docs h1 "$R"
rep k-rename "P1 · rename · h1 · title=T · m1 · $(fp h1) · rename";             refuse "a rename of a human doc is refused"     "takes only" --human-docs h1 "$R"
rep k-super "P1 · supersede · h1 · status=superseded · m1 · $(fp h1) · dup";     refuse "a supersede of a human doc is refused"  "takes only" --human-docs h1 "$R"
rep k-field "P1 · edit · h1 · title=T · - · $(fp h1) · retitle";                refuse "any field but tags on a human doc is refused" "takes only" --human-docs h1 "$R"
rep k-status "P1 · status · x1 · status=superseded · - · $(fp x1) · redirect";   refuse "status=superseded on a mixed doc is refused" "takes only" --human-docs x1 "$R"
rep k-noprov "P1 · status · noprov · status=archived · - · $(fp noprov) · old"; refuse "an ABSENT provenance: is refused"       "provenance 'absent'" --human-docs noprov "$R"
rep k-odd "P1 · status · odd · status=archived · - · $(fp odd) · old";          refuse "a provenance outside the enum is refused" "provenance 'robot'" --human-docs odd "$R"
rep k-prov "P1 · edit · h1 · provenance=machine · - · $(fp h1) · relabel";      refuse "a provenance: write on a human doc stays refused" "not a proposal's to write" --human-docs h1 "$R"
rep k-ledger "P1 · edit · h1 · ledger=[] · - · $(fp h1) · wipe";                refuse "a ledger: write on a human doc stays refused" "not a proposal's to write" --human-docs h1 "$R"
rep k-block "P1 · edit · blk · tags=[c] · - · $(fp blk) · retag";               refuse "a block-form tags: is refused, the doc byte-identical" "block form" --human-docs blk "$R"
rep k-gap "P1 · edit · blkgap · tags=[c] · - · $(fp blkgap) · retag";         refuse "…with a blank line before its items too" "block form" --human-docs blkgap "$R"
rep k-hash "P1 · edit · blkhash · tags=[c] · - · $(fp blkhash) · retag";      refuse "…and with a # comment line before them" "block form" --human-docs blkhash "$R"

echo "== apply names the human-written docs before it writes =="
rep hd-mixed "P1 · edit · m1 · title=New · - · $(fp m1) · retitle
P2 · edit · h1 · tags=[ops, kb] · - · $(fp h1) · tag it
P3 · status · x1 · status=archived · - · $(fp x1) · stale"
RH="$R"
chmod u-w knowledge/findings
out="$("$APPLY" --by example-user-007 --human-docs x1,h1 "$RH" 2>&1)"; rc=$?
chmod u+w knowledge/findings
ok "the notice is printed before the first write is attempted" \
  "$rc/$(grep -c '^KB HUMAN-WRITTEN DOCS: 2' <<<"$out")/$(grep -c 'could not write' <<<"$out")" 1/1/1
cp knowledge/findings/h1.md "$TMP/h1.before"
out="$("$APPLY" --by example-user-007 --human-docs x1,h1 "$RH" 2>&1)"; rc=$?
ok "the mixed report applies with the set in any order" "$rc" 0
lno() { awk -v s="$1" '!n && index($0, s) { n = NR } END { print n }' <<<"$out"; }
ok "the notice names archived, then tag edits, then KB APPLIED" \
  "$(a=$(lno 'KB HUMAN-WRITTEN DOCS: 2'); b=$(lno '- x1 (provenance: mixed) status=archived'); c=$(lno 'tag edits'); d=$(lno '- h1 (provenance: human) tags=[ops, kb]'); e=$(lno 'KB APPLIED')
     [ -n "$a" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] && [ "$c" -lt "$d" ] && [ "$d" -lt "$e" ] && echo ordered || echo "$a/$b/$c/$d/$e")" ordered
ok "a human doc gains only its field and one ledger: line" \
  "$(diff "$TMP/h1.before" knowledge/findings/h1.md | grep '^[<>]' | cut -c1-9 | tr '\n' '|')" "< tags: [|> tags: [|> ledger:|"
ok "…the ledger names the human" "$(grep -c '^ledger:.* · edit · by example-user-007 · items h1 · ' knowledge/findings/h1.md)" 1
ok "…and provenance: is untouched" "$(sed -n 's/^provenance: //p' knowledge/findings/h1.md)/$(sed -n 's/^status: //p' knowledge/findings/x1.md)" human/archived
cd "$D" || exit 2

echo "== a trailing # comment is read the way validate-bundle.sh reads it =="
D3="$TMP/bundle-comment"
mkdir -p "$D3/knowledge/findings" "$D3/.loopd"
printf -- '---\ntype: Finding\ntitle: T\ndescription: d\nlesson: l\ncategory: learning\ntags: [ ]\nstatus: current\nprovenance: machine  # x\ntimestamp: 2026-10-01T00:00:00Z\n---\n\n# Finding\n\nA claim.\n' \
  >"$D3/knowledge/findings/commented.md"
cp "$REPO/plugin/seed/knowledge/vocab.md" "$D3/knowledge/vocab.md"
printf 'index, regenerated\n' >"$D3/knowledge/index.md"
printf '{ "org": "example-org" }\n' >"$D3/instance.config.json"
cp "$REPO/plugin/seed/SCHEMA.md" "$D3/.loopd/SCHEMA.md"
cd "$D3" || exit 2
git init -q . && git config user.name example-user-007 && git config user.email u@example.com
git add -A && git commit -qm init
ok "validate-bundle reads provenance: machine  # x as machine" \
  "$("$VALIDATE" knowledge/findings/commented.md 2>&1 | grep -c ERROR)" 0
RC3=projects/kb-c/tasks/task-001-commented.md
report "$RC3" "P1 · edit · commented · title=New · - · $(fp commented) · retitle"
sed -i.bak 's/^status: draft$/status: draft  # awaiting the human/' "$RC3" && rm -f "$RC3.bak"
ok "kb-apply accepts the report, its status: commented too" \
  "$("$APPLY" --by example-user-007 "$RC3" >/dev/null 2>"$TMP/comment-apply.err"; echo $?)/$(sed -n 's/^title: //p' knowledge/findings/commented.md)" 0/New
cd "$D" || exit 2

echo "== the guards that keep agents out =="
ok "no tick step applies a report" "$(grep -rl 'kb-apply' "$REPO/plugin/tick-steps" | wc -l | tr -d ' ')" 0
for f in "$SCHEMA"; do
  ok "$(basename "$f") says --human-docs is derivable, so the hook rule binds agents" \
    "$(grep -c 'derivable from the report' "$f")/$(grep -c 'kb_apply_human_docs' "$f")" 1/1
done
ok "SCHEMA records the owner's reversal" "$(grep -c 'owner decision 2026-10-21' "$SCHEMA")" 1
ok "…its provenance table names the narrow path" "$(grep -cE '^\| `(mixed|human)` .*`tags` and `status=archived` only, only through `plugin/scripts/kb-apply.sh --human-docs`' "$SCHEMA")" 2
ok "no plugin line still says the machinery never rewrites a person's doc" \
  "$(grep -rn 'never rewrites what a person wrote' "$REPO/plugin" | wc -l | tr -d ' ')" 0

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
