#!/usr/bin/env bash
#
# original-request.test.sh — `original_request:` is written ONCE at intake and never
# rewritten (roadmap R23). Before it existed the human's own wording survived nowhere:
# `/loopd:new-project` derives `title`, `description` and `# Context` from the one-line
# ask, `/loopd:capture` keeps one quoted sentence inside `# Context`, and step 2 (refine)
# bakes every answer into `# Context` IN PLACE. On a shared instance the reviewer then
# saw what the loop made of the ask, never the ask. Four things hold the key in place:
#
#   a. SCHEMA.md names it on BOTH Project and Task, optional, with the write-once
#      declaration in the same register as `stall_count`'s "NEVER HAND-EDITED".
#   b. The two intake skills say they WRITE it (an unwritten key is a schema entry nobody
#      fills), and both say it is never rewritten.
#   c. Step 2 says refine never writes or changes it — the one step that rewrites the
#      body it exists to outlive.
#   d. DRIVEN, not read: `validate-bundle.sh` on a bundle WITHOUT the key says nothing
#      about it (invariant 8 — older bundles lack it, so a warning would fire on 100% of
#      them), and a bundle WITH it is equally silent. The control is a task with a bad
#      status in the same fixture, which the validator must still report — so silence is a
#      fact about the key and not about a validator that stopped speaking.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
NEWPROJ="$REPO/plugin/skills/new-project/SKILL.md"
CAPTURE="$REPO/plugin/skills/capture/SKILL.md"
STEP2="$REPO/plugin/tick-steps/step-2-refine-drafts.md"
VALIDATOR="$REPO/plugin/scripts/validate-bundle.sh"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/original-request.XXXXXX")" || {
  echo "original-request.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
hasf() { [ "$(grep -cF -- "$2" "$1")" -gt 0 ] && echo yes || echo no; }

echo "== the files exist, or every assertion below is vacuous =="
for f in "$SCHEMA" "$NEWPROJ" "$CAPTURE" "$STEP2" "$VALIDATOR"; do
  ok "$(basename "$(dirname "$f")")/$(basename "$f") exists" "$([ -f "$f" ] && echo yes || echo no)" yes
done

echo
echo "== a. SCHEMA.md names the key on BOTH types, optional and write-once =="
# The frontmatter block of one type: from its heading to the closing fence.
block_of() { # <type-heading-prefix>
  awk -v h="## type: $1 " 'index($0, h) == 1 { inb = 1; next }
       inb && /^```$/ && seen { exit }
       inb && /^```yaml$/ { seen = 1; next }
       inb && seen { print }' "$SCHEMA"; }
PROJ="$(block_of Project)"; TASK="$(block_of Task)"
ok "the Project frontmatter block is extractable" "$([ -n "$PROJ" ] && echo yes || echo no)" yes
ok "the Task frontmatter block is extractable"    "$([ -n "$TASK" ] && echo yes || echo no)" yes
for t in Project Task; do
  b="$([ "$t" = Project ] && printf '%s' "$PROJ" || printf '%s' "$TASK")"
  line="$(printf '%s\n' "$b" | grep -F 'original_request:' || true)"
  ok "$t: carries exactly one original_request: line" "$(printf '%s' "$line" | grep -c . | tr -d ' ')" 1
  ok "$t: …declared optional"                      "$(printf '%s' "$line" | grep -cF 'optional' | tr -d ' ')" 1
  ok "$t: …in stall_count's register: NEVER REWRITTEN" "$(printf '%s' "$line" | grep -cF 'WRITTEN ONCE AT CREATION, NEVER REWRITTEN' | tr -d ' ')" 1
  ok "$t: …names refine as a non-writer"             "$(printf '%s' "$line" | grep -cF 'not by refine' | tr -d ' ')" 1
  ok "$t: …says the validator stays silent on absence" "$(printf '%s' "$line" | grep -cF 'emits no diagnostic for its absence' | tr -d ' ')" 1
  ok "$t: …states the why (# Context is rewritten in place)" "$(printf '%s' "$line" | grep -cF 'in place' | tr -d ' ')" 1
  ok "$t: …and the PII rule reaches it"              "$(printf '%s' "$line" | grep -cF 'no customer PII' | tr -d ' ')" 1
done
# Register check, so the phrase above is not a new idiom: stall_count still carries its own.
ok "stall_count still reads PM-OWNED, NEVER HAND-EDITED (the register borrowed)" \
   "$(printf '%s\n' "$TASK" | grep -F 'stall_count:' | grep -cF 'PM-OWNED, NEVER HAND-EDITED' | tr -d ' ')" 1

echo
echo "== b. both intake skills WRITE it, and say it is never rewritten =="
# new-project: in the scaffold step, on project.md AND on the seed tasks (two mentions).
ok "new-project names the key"                     "$(hasf "$NEWPROJ" '`original_request:`')" yes
ok "new-project: on project.md, verbatim"          "$(hasf "$NEWPROJ" 'description from `$ARGUMENTS`')" yes
ok "new-project: …quoted single line"              "$(hasf "$NEWPROJ" 'quoted single-line YAML string')" yes
ok "new-project: …once and never rewritten"        "$(hasf "$NEWPROJ" '**once and never rewritten**')" yes
ok "new-project: …and on every seed task too"      "$(hasf "$NEWPROJ" 'the same verbatim description the project carries')" yes
ok "new-project: two mentions, project + task"     "$(grep -cF -- '`original_request:`' "$NEWPROJ" | tr -d ' ')" 2
# capture: at the provenance step, after the same redaction the # Context line gets.
ok "capture names the key"                         "$(hasf "$CAPTURE" '`original_request:`')" yes
ok "capture: the decisive sentence, verbatim"      "$(hasf "$CAPTURE" 'verbatim as captured, after the same')" yes
ok "capture: …after the same redaction, quoted"    "$(hasf "$CAPTURE" 'redaction, as a quoted single-line YAML string')" yes
ok "capture: …once, here, and never rewritten"     "$(hasf "$CAPTURE" '**once, here, and never rewritten**')" yes
ok "capture: …on every project and task created"   "$(hasf "$CAPTURE" 'on every project and task you')" yes

echo
echo "== c. step 2 says refine never writes or changes it =="
ok "step 2 carries the sentence"                   "$(hasf "$STEP2" 'Refine never writes or changes `original_request:`')" yes
ok "…beside the in-place bake, not elsewhere"      \
   "$(awk '/Bake each answer into the task itself/ { f = 1 } f && /Refine never writes or changes/ { print "yes"; exit }' "$STEP2")" yes
ok "…and it says why (it outlives the # Context rewrite)" "$(hasf "$STEP2" 'survives the rewrite of')" yes

echo
echo "== d. DRIVEN: validate-bundle.sh says nothing about the key, present or absent =="
ok "the validator never mentions original_request" "$(grep -cF -- 'original_request' "$VALIDATOR" | tr -d ' ')" 0
TS="2026-01-01T00:00:00Z"
bundle() { # <dir> <project extra line> <task extra line>
  mkdir -p "$1/projects/p/tasks" "$1/$AB_DIR"
  printf '{ "org": "demo" }\n' > "$1/instance.config.json"
  printf '# Schema\n' > "$1/$AB_SCHEMA"
  { echo '---'; echo 'type: Project'; echo 'title: P'; echo 'description: d'; echo 'kind: build'
    [ -z "$2" ] || echo "$2"
    echo 'target_repo: demo/r'; echo 'status: active'; echo "timestamp: $TS"; echo '---'; echo; echo '# Context'; echo; echo 'x'
  } > "$1/projects/p/project.md"
  { echo '---'; echo 'type: Task'; echo 'title: T'; echo 'description: d'; echo 'kind: build'; echo 'status: draft'
    [ -z "$3" ] || echo "$3"
    echo 'acceptance_criteria: [ ]'; echo 'open_questions: [ ]'; echo "timestamp: $TS"; echo '---'; echo; echo '# Context'; echo; echo 'x'
  } > "$1/projects/p/tasks/task-001-t.md"
}
run() { ( cd "$1" && bash "$VALIDATOR" --strict 2>&1; echo "rc=$?" ); }

WITHOUT="$TMP/without"; bundle "$WITHOUT" "" ""
OUT="$(run "$WITHOUT")"
ok "without the key: exit 0 under --strict"        "$(printf '%s\n' "$OUT" | sed -n 's/^rc=//p')" 0
ok "without the key: no line mentions it"          "$(printf '%s\n' "$OUT" | grep -cF 'original_request' | tr -d ' ')" 0

Q='original_request: "ship the thing the \"customer\" asked for: a, b --- and c"'
WITH="$TMP/with"; bundle "$WITH" "$Q" "$Q"
OUT="$(run "$WITH")"
ok "with the key (quotes, colon, ---): exit 0"     "$(printf '%s\n' "$OUT" | sed -n 's/^rc=//p')" 0
ok "with the key: no line mentions it"             "$(printf '%s\n' "$OUT" | grep -cF 'original_request' | tr -d ' ')" 0

# The control: the same fixture with a status outside the Task enum MUST be reported, so
# the two silences above are about the key, not about a validator that stopped speaking.
CTRL="$TMP/ctrl"; bundle "$CTRL" "" "$Q"
sed -i.bak 's/^status: draft$/status: pondering/' "$CTRL/projects/p/tasks/task-001-t.md" && rm -f "$CTRL/projects/p/tasks/task-001-t.md.bak"
OUT="$(run "$CTRL")"
ok "control: a bad status in the same fixture is non-zero" \
   "$([ "$(printf '%s\n' "$OUT" | sed -n 's/^rc=//p')" != 0 ] && echo yes || echo no)" yes
ok "control: …and names it"                        "$(printf '%s\n' "$OUT" | grep -cF 'pondering' | tr -d ' ')" 1
ok "control: …still without a word about the key"  "$(printf '%s\n' "$OUT" | grep -cF 'original_request' | tr -d ' ')" 0

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
