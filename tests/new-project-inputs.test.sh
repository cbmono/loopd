#!/usr/bin/env bash
#
# new-project-inputs.test.sh — `/loopd:new-project` asks at most one batched question, and a
# project on `inputs: later` waits for its files without the loop asking anything.
#
#   1. THE SKILL: a short argument-hint naming kind/autonomy/inputs; ONE AskUserQuestion of at
#      most three parts; the value gate, clis, browser, objective and success-criteria
#      approval are never asked when unflagged.
#   2. project-inputs.sh: the one reader of `inputs:` — 0 ready · 1 waiting · 2 cannot
#      answer · 3 arrived — and `--release`, its one writer. File PRESENCE only: a source's
#      name never reaches its output or the project log.
#   3. AWAITING.md: a waiting project renders exactly ONE `📥 inputs` row and none of its
#      task rows; a file in sources/ releases it back to the usual rows.
#   4. tick-delta.sh digest: a waiting project's draft names no step 2; an arrived one does.
#
# Every section carries a MUTANT — the guard removed from a copy — that must turn its
# check red, so none of the assertions can pass on a tree that lost the behaviour.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$REPO/plugin/skills/new-project/SKILL.md"
SCRIPTS="$REPO/plugin/scripts"
. "$SCRIPTS/bundle-paths.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/new-project-inputs.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
has() { grep -qF -- "$2" <<<"$(flat "$1")" && echo yes || echo no; }
hasre() { grep -qiE -- "$2" <<<"$(flat "$1")" && echo yes || echo no; }

echo "== 1. the skill: one question, at most three parts =="
hint() { sed -n '/^argument-hint:/{s/^argument-hint:[[:space:]]*//p;q;}' "$1"; }
H="$(hint "$SKILL")"
ok "argument-hint is short (<= 80 chars)"          "$([ "${#H}" -le 80 ] && echo yes || echo no)" yes
for t in 'kind=' 'autonomy=' 'inputs='; do
  ok "…and names $t"                               "$(grep -cF -- "$t" <<<"$H" | tr -d ' ')" 1
done
ok "…and no longer lists every flag"               "$(grep -cE 'success_criteria=|deliverables=|--no-ask' <<<"$H" | tr -d ' ')" 0
ok "one batched AskUserQuestion"                   "$(has "$SKILL" 'ONE question, at most three parts')" yes
ok "…and the skill may ask it"                     "$(grep -m1 '^allowed-tools:' "$SKILL" | grep -c 'AskUserQuestion' | tr -d ' ')" 1
ok "the inputs choice is one of the three"         "$(has "$SKILL" "I'll add files to \`sources/\` first")" yes
ok "inputs= is a flag"                             "$(grep -c '^- `inputs=later|now`' "$SKILL" | tr -d ' ')" 1
ok "criteria are written with no approval round"   "$(has "$SKILL" 'with **no approval round**')" yes
ok "the value gate is never asked"                 "$(has "$SKILL" '**Then the value gate — written on BOTH kinds, never asked.**')" yes
ok "clis/browser/objective are never asked"        "$(has "$SKILL" '**Never asked, whatever the kind**')" yes
# The old questions, by their own words: none may survive the rewrite.
OLD_ASKS='get the user.s OK|Ask for `need:`|ask kind on its own|claude mcp list|offer the best-fitting|grant browser access to this project\?|offer to fix it'
ok "no old question survives"                      "$(hasre "$SKILL" "$OLD_ASKS")" no
# MUTANT: one old ask put back into a copy is caught by the same check.
{ cat "$SKILL"; printf '\n   Propose 2-4 lines and get the user'"'"'s OK.\n'; } > "$TMP/skill-mutant.md"
ok "MUTANT: a restored approval round is caught"   "$(hasre "$TMP/skill-mutant.md" "$OLD_ASKS")" yes
sed 's/^argument-hint:.*/argument-hint: <one-line project description> | <1-5> <text> | submit | cancel  [kind=build|research] [objective=<slug>] [autonomy=<mode>] [inputs=later] [--no-ask]/' \
  "$SKILL" > "$TMP/hint-mutant.md"
HM="$(hint "$TMP/hint-mutant.md")"
ok "MUTANT: the old wall of a hint is caught"      "$([ "${#HM}" -le 80 ] && echo yes || echo no)" no

echo
echo "== 2. project-inputs.sh: the one reader, presence only =="
INST="$TMP/inst"
mk_inst() { # fresh instance with one project <slug> on inputs: <value>
  rm -rf "$INST"; mkdir -p "$INST/$AB_DIR" "$INST/projects/$1/tasks" "$INST/projects/$1/sources"
  printf '{ "org": "o" }\n' > "$INST/instance.config.json"
  printf 'stub\n' > "$INST/$AB_SCHEMA"
  printf '# Awaiting you\n' > "$INST/$AB_AWAITING"
  { printf -- '---\ntype: Project\ntitle: Wait for it\nkind: research\nstatus: %s\nautonomy: gated\n' "${3:-active}"
    [ -n "$2" ] && printf 'inputs: %s\n' "$2"
    printf -- '---\n\n# Context\n'; } > "$INST/projects/$1/project.md"
  printf -- '---\ntype: Task\ntitle: T1\nkind: research\nstatus: draft\nacceptance_criteria: []\nopen_questions: [ "Q1: which colour?" ]\n---\n' \
    > "$INST/projects/$1/tasks/task-001-a.md"
  printf 'Drop files here.\n' > "$INST/projects/$1/sources/README.md"
  printf '# Wait — log\n\n## 2026-01-01\n\n* Created.\n' > "$INST/projects/$1/log.md"
}
rc() { ( cd "$INST" && bash "$SCRIPTS/project-inputs.sh" "$@" >"$TMP/out" 2>&1 ); echo $?; }
mk_inst p later
ok "inputs: later, only README.md → 1 waiting"     "$(rc projects/p/tasks/task-001-a.md)" 1
touch "$INST/projects/p/sources/.DS_Store"
ok "…a dotfile does not release it"                "$(rc projects/p/project.md)" 1
ok "--release while waiting changes nothing"       "$(rc --release projects/p/project.md)/$(grep -c '^inputs: later$' "$INST/projects/p/project.md")" 1/1
mkdir -p "$INST/projects/p/sources/raw"; printf 'x\n' > "$INST/projects/p/sources/raw/Raw-Export-Name.csv"
ok "a file (even nested) → 3 arrived"              "$(rc projects/p/project.md)" 3
ok "…and the output never names it"                "$(grep -c 'Raw-Export-Name' "$TMP/out" | tr -d ' ')" 0
ok "--release → 0, and inputs: now is written"     "$(rc --release projects/p/project.md)/$(grep -c '^inputs: now$' "$INST/projects/p/project.md")" 0/1
ok "…logged under today's heading, newest first"   "$(sed -n 3p "$INST/projects/p/log.md")" "## $(date -u +%Y-%m-%d)"
ok "…by count, never by name"                      "$(grep -c 'released by 1 file' "$INST/projects/p/log.md")/$(grep -c 'Raw-Export-Name' "$INST/projects/p/log.md" "$TMP/out" | awk -F: '{s+=$2} END {print s}')" 1/0
ok "released → 0 ready"                            "$(rc projects/p/project.md)" 0
mk_inst p ""
ok "no inputs: key → 0 (every older project)"      "$(rc projects/p/project.md)" 0
mk_inst p now
ok "inputs: now → 0"                               "$(rc projects/p/project.md)" 0
mk_inst p lator
ok "an unknown value → 2, never a guess"           "$(rc projects/p/project.md)" 2
ok "outside projects/<slug>/ → 2"                  "$(rc instance.config.json)" 2

echo
echo "== 3. AWAITING.md: one row while waiting, the usual rows once released =="
rows() { grep '^\* ' "$INST/$AB_AWAITING" || true; }
render() { bash "${1:-$SCRIPTS}/build-awaiting.sh" --instance "$INST" >/dev/null 2>&1; }
mk_inst p later; render
ok "waiting: exactly one row"                      "$(rows | wc -l | tr -d ' ')" 1
ok "…and it is the inputs row for the project"     "$(rows | grep -c '📥 \*\*inputs\*\* — \[Wait for it\](/projects/p/project.md)' | tr -d ' ')" 1
ok "…naming the folder to fill"                    "$(rows | grep -cF '`projects/p/sources/`' | tr -d ' ')" 1
ok "…and not the draft's question"                 "$(rows | grep -c 'answer' | tr -d ' ')" 0
printf 'x\n' > "$INST/projects/p/sources/notes.txt"; render
ok "a file lands: the inputs row is gone"          "$(rows | grep -c 'inputs\*\*' | tr -d ' ')" 0
ok "…and the draft's own row is back"              "$(rows | grep -c 'answer' | tr -d ' ')" 1
mk_inst p later paused; render
ok "paused wins: no inputs row"                    "$(rows | grep -c 'inputs\*\*' | tr -d ' ')" 0
# MUTANT: the call removed from a copy of the renderer — the draft's row leaks back in.
mkdir -p "$TMP/mut3"; cp -R "$SCRIPTS/." "$TMP/mut3/"
sed -i.bak 's/waiting_inputs "\$pm" && mine/false \&\& mine/' "$TMP/mut3/build-awaiting.sh"
ok "MUTANT: the mutation took"                     "$(grep -c 'false && mine "\$pm"; then' "$TMP/mut3/build-awaiting.sh" | tr -d ' ')" 1
mk_inst p later; render "$TMP/mut3"
ok "MUTANT: no inputs row, the question leaks"     "$(rows | grep -c 'inputs\*\*' | tr -d ' ')/$(rows | grep -c 'answer' | tr -d ' ')" 0/1

echo
echo "== 4. tick-delta.sh digest: a waiting project names no step 2 =="
gitinit() { ( cd "$INST" && git init -q && git add -A && git -c user.name=t -c user.email=t@example.com commit -qm init ) >/dev/null 2>&1; }
steps() { bash "${1:-$SCRIPTS}/tick-delta.sh" digest --instance "$INST" 2>/dev/null; }
mk_inst p later; gitinit
D="$(steps)"
ok "waiting: the digest says so"                   "$(grep -c '^inputs waiting projects/p/project.md$' <<<"$D" | tr -d ' ')" 1
ok "…and step 2 is not named"                      "$(grep '^steps:' <<<"$D" | grep -c 'step-2' | tr -d ' ')" 0
printf 'x\n' > "$INST/projects/p/sources/notes.txt"
D="$(steps)"
ok "arrived: the digest says so"                   "$(grep -c '^inputs arrived projects/p/project.md$' <<<"$D" | tr -d ' ')" 1
ok "…and step 2 is named, to release it"           "$(grep '^steps:' <<<"$D" | grep -c 'step-2' | tr -d ' ')" 1
mk_inst p ""; gitinit
ok "no inputs: key: a draft names step 2 as ever"  "$(steps | grep '^steps:' | grep -c 'step-2' | tr -d ' ')" 1
# MUTANT: the draft guard removed — a waiting project names step 2 again.
mkdir -p "$TMP/mut4"; cp -R "$SCRIPTS/." "$TMP/mut4/"; cp -R "$REPO/plugin/tick-steps" "$TMP/tick-steps"
sed -i.bak 's/\[ "\$inw" = waiting \] || step2=1/step2=1/' "$TMP/mut4/tick-delta.sh"
ok "MUTANT: the mutation took"                     "$(grep -c 'inw" = waiting' "$TMP/mut4/tick-delta.sh" | tr -d ' ')" 0
mk_inst p later; gitinit
ok "MUTANT: a waiting draft names step 2"          "$(steps "$TMP/mut4" | grep '^steps:' | grep -c 'step-2' | tr -d ' ')" 1

echo
echo "== 5. documented where a reader looks =="
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
block="$(awk '/^## type: Project/{f=1} /^## type: Phase/{f=0} f' "$SCHEMA")"
ok "SCHEMA.md Project block defines inputs:"       "$(printf '%s\n' "$block" | grep -c '^inputs: later | now ')" 1
ok "step 2 skips a waiting project"                "$(has "$REPO/plugin/tick-steps/step-2-refine-drafts.md" 'refine none of that project')" yes
ok "…and releases an arrived one"                  "$(grep -c 'project-inputs.sh --release' "$REPO/plugin/tick-steps/step-2-refine-drafts.md" | tr -d ' ')" 1
ok "sources/README.md tells the human"             "$(has "$SKILL" 'the first file other than this README releases the project')" yes

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
