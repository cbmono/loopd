#!/usr/bin/env bash
# The project-manager's prompt is a CORE plus one file per on-demand step
# (ai-bridge-v3/task-024). Three things can silently undo that, and this file is each one:
#
#   1. A GATE DRIFTS INTO A STEP FILE. A tick that read no step file must still be unable to
#      promote, to merge, or to dispatch the other human's work. So the gates are asserted
#      present in the CORE and absent from every step file — both halves, because "it is in
#      the core" says nothing about a second copy two files over.
#   2. A STEP FILE REGISTERS AS AN AGENT. Eight documents dropped into plugin/agents/ could
#      be read as eight agents. The roster is asserted unchanged, by name.
#   3. THE DIGEST STOPS NAMING A STEP. Then the step file is never read and its rules are
#      deleted in effect. Driven against real fixtures, per status — not read off prose.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$REPO/plugin/agents/project-manager.md"
STEPS="$REPO/plugin/tick-steps"
DELTA="$REPO/plugin/scripts/tick-delta.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pm-step-files.XXXXXX")" || {
  echo "pm-step-files.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi }
has() { grep -qF -- "$2" "$1" && echo yes || echo no; }

echo "== the files exist, or every assertion below is vacuous =="
ok "the core prompt exists" "$([ -f "$CORE" ] && echo yes || echo no)" yes
for n in 2-refine-drafts 3-dispatch 4-advance 5-reflect-merges 6-close-projects \
         7-knowledge-base 8-render; do
  ok "step-$n.md exists" "$([ -f "$STEPS/step-$n.md" ] && echo yes || echo no)" yes
done
ok "…and there are exactly seven of them" \
   "$(find "$STEPS" -maxdepth 1 -type f -name '*.md' | grep -c . | tr -d ' ')" 7
ok "every one ends with its own sentinel" \
   "$(for f in "$STEPS"/*.md; do tail -n1 "$f"; done | grep -c '^<!-- end of step [0-9]* -->$' | tr -d ' ')" 7

echo
echo "== 1. NO GATE MOVED. A tick that read no step file still cannot cross one =="
# The exact prose, not a paraphrase: these three are the whole authority boundary.
ok "gate 1: never set a task to ready"   "$(has "$CORE" '**Never set a task to `ready`.**')" yes
ok "gate 2: never merge a PR"            "$(has "$CORE" '**Never merge a PR.**')" yes
ok "gate 3: dispatch only your own human's work" \
   "$(has "$CORE" "**Dispatch only your own human's work.**")" yes
ok "…and gate 3 names the only clearance" "$(has "$CORE" '**Exit 0 is the only clearance**')" yes
for g in '**Never set a task to `ready`.**' '**Never merge a PR.**' \
         "**Dispatch only your own human's work.**"; do
  ok "…and it is NOT restated in a step file" \
     "$(grep -rlF -- "$g" "$STEPS" | grep -c . | tr -d ' ')" 0
done
# The four every-tick sections stay too — each is either a gate or runs on every tick.
ok "step 2.5 (the promotion stamp) is in the core" "$(has "$CORE" '2.5. **Stamp promotions')" yes
ok "step 9 (leave for the human) is in the core"   "$(has "$CORE" '9. **Leave for the human.**')" yes
ok "## Modes is in the core"                       "$(has "$CORE" '## Modes')" yes
ok "## Output is in the core"                      "$(has "$CORE" '## Output')" yes
ok "…and the UNKNOWN rule with them"               "$(has "$CORE" 'returns UNKNOWN')" yes
ok "…and the lock contract"                        "$(has "$CORE" 'tick-lock.sh acquire --as tick')" yes
# Steps 0/0.5/0.9/1 run on EVERY tick, so none of them may be behind a conditional read.
for s in '0. **Sync the bundle first' '0.5. **Take the tick lock' \
         '0.9. **Probe the idle fast-path' '1. **Orient'; do
  ok "core keeps '${s}'" "$(has "$CORE" "$s")" yes
done

echo
echo "== 2. THE AGENT ROSTER IS UNCHANGED — no step file registered as an agent =="
# The three harnesses that enumerate plugin/agents/ all use -maxdepth 1 or a flat glob, so
# the assertion that matters is the ROSTER, by name, not the enumeration style.
ROSTER="$(find "$REPO/plugin/agents" -maxdepth 1 -type f -name '*.md' -exec basename {} .md \; | sort | tr '\n' ' ')"
ok "the seven shipped agents, and only those" "$ROSTER" \
   "auditor cataloguer devops-engineer failure-analyst project-manager qa-reviewer software-engineer "
ok "no step file lives under plugin/agents/" \
   "$(find "$REPO/plugin/agents" -mindepth 2 -name '*.md' | grep -c . | tr -d ' ')" 0
ok "…and no step file declares a name: frontmatter key" \
   "$(grep -l '^name:' "$STEPS"/*.md 2>/dev/null | grep -c . | tr -d ' ')" 0

echo
echo "== 3. THE DIGEST NAMES A STEP ONLY WHEN THE TICK HAS WORK FOR IT =="
inst() { # <dir> <task-status> [extra-frontmatter-line]
  mkdir -p "$1/projects/demo/tasks"
  ( cd "$1" && git init -q . && git config user.email t@e && git config user.name t ) >/dev/null 2>&1
  printf '{ "org": "demo" }\n' > "$1/instance.config.json"
  printf '# SCHEMA\n' > "$1/SCHEMA.md"
  printf -- '---\ntype: Project\ntitle: "Demo"\nstatus: active\n---\n' > "$1/projects/demo/project.md"
  printf -- '---\ntype: Task\ntitle: "T"\nstatus: %s\nkind: build\nacceptance_criteria: [ "x" ]\nopen_questions: [ %s ]\n---\n' \
    "$2" "${3:-}" > "$1/projects/demo/tasks/task-001-t.md"
  ( cd "$1" && git add -A . && git commit -qm init ) >/dev/null 2>&1
}
steps_for() { # <dir> -> the bare step-file names the digest named
  bash "$DELTA" digest --instance "$1" 2>/dev/null | sed -n 's/^steps: *//p' \
    | tr ' ' '\n' | grep . | sed 's#.*/##' | sort | tr '\n' ' '
}
command -v git >/dev/null 2>&1 || { echo "pm-step-files.test: git required" >&2; exit 2; }

D="$TMP/draft";    inst "$D" draft
ok "a draft names step 2"           "$(steps_for "$D")" "step-2-refine-drafts.md "
R="$TMP/ready";    inst "$R" ready
ok "a ready task names step 3"      "$(steps_for "$R")" "step-3-dispatch.md "
P="$TMP/prog";     inst "$P" in-progress
ok "an in-progress task names step 4" "$(steps_for "$P")" "step-4-advance.md "
V="$TMP/review";   inst "$V" in-review
ok "an in-review task names 4 and 5"  "$(steps_for "$V")" "step-4-advance.md step-5-reflect-merges.md "
T="$TMP/term";     inst "$T" done
ok "an all-terminal project names step 6" "$(steps_for "$T")" "step-6-close-projects.md "
# The digest carries open-question COUNTS and never whether one was ANSWERED, which is the
# only thing that names step 2 on a task past draft. So the predicate reads the entry.
A="$TMP/answered"; inst "$A" in-review '"Q1: colour? --- blue"'
ok 'a ` --- `-answered entry names step 2 too' \
   "$(steps_for "$A" | grep -c 'step-2-refine-drafts.md' | tr -d ' ')" 1
# A `]` INSIDE an earlier question ends a sed range before the answer that follows it, so
# step 2 went unnamed — the flow-list truncation fold-answers.sh exists to refuse. The
# predicate reads through that parser, which makes the bracket data.
B="$TMP/bracket"; inst "$B" in-review '"Q1: [a] or [b]?", "Q2: colour? --- blue"'
ok "a ] inside an earlier question does not hide the answer" \
   "$(steps_for "$B" | grep -c 'step-2-refine-drafts.md' | tr -d ' ')" 1
C="$TMP/cancel";   inst "$C" cancelled
ok "nothing owed names nothing…"    "$(steps_for "$C")" "step-6-close-projects.md "
ok "…and the line is always present, even when empty" \
   "$(bash "$DELTA" digest --instance "$T" 2>/dev/null | grep -c '^steps:' | tr -d ' ')" 1

echo
echo "== step 7 is NEVER named by the digest — its trigger is not on disk =="
for d in "$D" "$R" "$P" "$V" "$T" "$A"; do
  ok "…not for $(basename "$d")" "$(steps_for "$d" | grep -c 'step-7' | tr -d ' ')" 0
done
ok "the core carries step 7's own trigger instead" "$(has "$CORE" 'kb-sweep-due.sh')" yes
ok "…naming the reflect outcome as the other one"  "$(has "$CORE" 'step 5 reflected a merge')" yes

echo
echo "== the core tells a tick what to do when the digest cannot answer =="
ok "any exit but 0 reads ALL of them" "$(has "$CORE" 'read ALL of them')" yes
ok "…and an empty line means none"    "$(has "$CORE" 'this tick has work for none of them')" yes
ok "step 8's render half is predicated on the artifacts" \
   "$(has "$CORE" '`AWAITING.md` or `SNAPSHOT.json` present at the bundle root')" yes
ok "an IDLE tick reads no step file at all" "$(has "$CORE" 'reads none of these files')" yes
ok "…and step 0.9 is what skips 1-7"       "$(has "$CORE" '**Skip steps 1–7.**')" yes
# The mechanical half of the same claim: the `steps:` line exists on `digest` ONLY, and an
# idle tick never reaches the digest — it stops at `check`. So there is nothing for an idle
# tick to have been named by, whatever it reports.
bash "$DELTA" record --instance "$T" >/dev/null 2>&1
ok "the probe prints no steps: line, ever" \
   "$(bash "$DELTA" check --instance "$T" 2>/dev/null | grep -c '^steps:' | tr -d ' ')" 0

# An empty `steps:` line says "no step is owed". A tick-steps directory the walk cannot
# find says the opposite, so the digest refuses rather than print a line that reads as the
# first — the core's "any exit but 0 reads ALL of them" is what then applies.
NOSTEPS="$TMP/nosteps"; mkdir -p "$NOSTEPS/scripts"
cp "$REPO/plugin/scripts/tick-delta.sh" "$REPO/plugin/scripts/bundle-paths.sh" \
   "$REPO/plugin/scripts/fold-answers.sh" "$NOSTEPS/scripts/"
ok "no tick-steps directory is exit 2, not an empty steps: line" \
   "$(bash "$NOSTEPS/scripts/tick-delta.sh" digest --instance "$T" >/dev/null 2>&1; echo $?)" 2
ok "…and no steps: line is printed at all" \
   "$(bash "$NOSTEPS/scripts/tick-delta.sh" digest --instance "$T" 2>/dev/null | grep -c '^steps:' | tr -d ' ')" 0

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
