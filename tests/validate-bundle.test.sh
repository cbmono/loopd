#!/usr/bin/env bash
#
# Exercises plugin/scripts/validate-bundle.sh against a throwaway bundle whose
# every document is a deliberate decision class: valid, invalid enum, missing
# field, dangling structural reference, declared-but-unwritten artifact, and the
# non-concept files that must NOT be validated at all.
#
# That last group is the point of several cases. The first version of the script
# validated `index.md`, `log.md`, `sources/` and `deliverables/` too, and buried 6
# real errors under 77 warnings on a live instance. A validator nobody reads is
# worse than none, so "these files are ignored" is a tested property.
#
# assert() follows the same convention as the other harnesses here: 0 is a PASS.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR="$HERE/../plugin/scripts/validate-bundle.sh"
[[ -f "$VALIDATOR" ]] || { echo "validate-bundle.test: validator not found at $VALIDATOR" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/validate-bundle-fixture.XXXXXX")" || {
  echo "validate-bundle.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
B="$TMP/bundle"
mkdir -p "$B"/{objectives,knowledge/findings}
mkdir -p "$B"/projects/live/{tasks,phases,sources,deliverables}
cd "$B"

echo '{ "org": "x", "reposRoot": "/tmp" }' > instance.config.json
echo '# Schema' > SCHEMA.md

TS="2026-01-01T00:00:00Z"

doc() { # <path> <body...>
  local p="$1"; shift
  mkdir -p "$(dirname "$p")"
  printf '%s\n' "$@" > "$p"
}

# --- valid documents -----------------------------------------------------------
doc objectives/good.md '---' 'type: Objective' 'title: Good' 'status: active' "timestamp: $TS" '---' 'body'
doc projects/live/project.md '---' 'type: Project' 'title: Live' 'kind: build' \
  'objective: /objectives/good.md' 'status: active' "timestamp: $TS" '---' 'body'
doc projects/live/phases/1-a.md '---' 'type: Phase' 'title: A' \
  'project: /projects/live/project.md' 'status: active' "timestamp: $TS" '---' 'body'
doc projects/live/tasks/task-001-ok.md '---' 'type: Task' 'title: Ok' 'status: ready' \
  'objective: /objectives/good.md' 'phase: /projects/live/phases/1-a.md' "timestamp: $TS" '---' 'body'
doc knowledge/findings/good.md '---' 'type: Finding' 'title: F' 'category: learning' \
  'lesson: a one-line takeaway' 'status: current' 'provenance: machine' "timestamp: $TS" '---' 'body'

# A task carrying the free-text `answered_questions:` audit list. Asserted SILENT on
# purpose: that key is deliberately NOT machine-read, so the validator must have no
# opinion about it. There is no error class here with one right answer — a free-text
# list is neither an enum nor a reference — and a "missing ` --- ` delimiter" warning is
# precisely the noise this file's header says buries real errors. If someone later adds
# a check for it, this assertion is what fails.
doc projects/live/tasks/task-013-answered.md '---' 'type: Task' 'title: Answered' 'status: ready' \
  'objective: /objectives/good.md' 'open_questions: [ ]' \
  'answered_questions: [ "2026-01-01T00:00:00Z · Q1: which region? --- eu-central-1", "2026-01-02T00:00:00Z · Q2: moot, the endpoint was removed" ]' \
  "timestamp: $TS" '---' 'body'

# --- one document per failure class -------------------------------------------
doc projects/live/tasks/task-002-bad-status.md '---' 'type: Task' 'title: Bad' \
  'status: activ' "timestamp: $TS" '---' 'body'
doc projects/live/tasks/task-003-wrong-type-status.md '---' 'type: Task' 'title: Wrong' \
  'status: active' "timestamp: $TS" '---' 'a Task may not be "active" — that is a Project status'
doc projects/live/tasks/task-004-no-timestamp.md '---' 'type: Task' 'title: NoTs' 'status: draft' '---' 'body'
doc projects/live/tasks/task-005-no-type.md '---' 'title: NoType' 'status: draft' "timestamp: $TS" '---' 'body'
doc projects/live/tasks/task-006-unknown-type.md '---' 'type: Sprint' 'title: Unknown' "timestamp: $TS" '---' 'body'
doc projects/live/tasks/task-007-dangling.md '---' 'type: Task' 'title: Dangling' 'status: draft' \
  'depends_on: [ /projects/closed/tasks/task-009-gone.md ]' "timestamp: $TS" '---' 'body'
doc projects/live/tasks/task-008-artifact.md '---' 'type: Task' 'title: Artifact' 'status: draft' \
  'artifacts: [ /projects/live/deliverables/not-written-yet.md ]' "timestamp: $TS" '---' 'body'
doc projects/live/tasks/task-009-no-frontmatter.md '# just a heading, no frontmatter'

# --- classes added after review (each was a false negative) --------------------
# A block-style YAML sequence is valid and was silently skipped, so the validator
# could report success while a structural reference dangled.
doc projects/live/tasks/task-010-block-dangling.md '---' 'type: Task' 'title: Block' 'status: draft' \
  'depends_on:' '  - /projects/closed/tasks/task-block-gone.md' "timestamp: $TS" '---' 'body'
# A block sequence that resolves must stay silent.
doc projects/live/tasks/task-011-block-ok.md '---' 'type: Task' 'title: BlockOk' 'status: draft' \
  'depends_on:' '  - /projects/live/tasks/task-001-ok.md' "timestamp: $TS" '---' 'body'
# Frontmatter that opens and never closes used to return the whole file, so bogus
# fields passed.
doc projects/live/tasks/task-012-unterminated.md '---' 'type: Task' 'title: Unterminated' 'status: draft' \
  "timestamp: $TS" 'body with no closing delimiter'
# Service carries its own status enum, which enum_for originally omitted.
doc knowledge/services/bad-service.md '---' 'type: Service' 'title: S' 'status: retired' 'provenance: machine' "timestamp: $TS" '---' 'body'
doc knowledge/services/good-service.md '---' 'type: Service' 'title: S2' 'status: active' 'provenance: machine' "timestamp: $TS" '---' 'body'
# CONVENTIONS.md -> "Write less" bounds a Finding at 40 lines and requires a one-line
# `lesson:`. Both WARN rather than fail: every bundle alive has findings that predate the
# rule, and a validator that fails on all of them is one people switch off.
doc knowledge/findings/no-lesson.md '---' 'type: Finding' 'title: NoLesson' \
  'category: learning' 'status: current' 'provenance: machine' "timestamp: $TS" '---' 'body'
{ printf '%s\n' '---' 'type: Finding' 'title: TooLong' 'category: learning' \
    'lesson: it is too long' 'status: current' 'provenance: machine' "timestamp: $TS" '---'
  for i in $(seq 40); do echo "line $i"; done
} > knowledge/findings/too-long.md
# Below knowledge/<kind>/ is not a schema location and must be ignored.
doc knowledge/findings/sources/raw-note.md '# a raw note a human dropped in'
# The FIFTH knowledge kind. `knowledge/<kind>/` is a shape, not a list of four names,
# so these documents were always collected and checked for type, timestamp and refs —
# the one gap was `status`, because `Reference` carried no enum. A Finding's enum
# applied to a Reference (`open`) is exactly the drift class this script exists for.
doc knowledge/references/bad-ref.md '---' 'type: Reference' 'title: R' 'status: open' 'provenance: machine' "timestamp: $TS" '---' 'body'
doc knowledge/references/good-ref.md '---' 'type: Reference' 'title: R2' 'status: current' 'provenance: machine' "timestamp: $TS" '---' 'body'
# Declaring the enum also makes `status` REQUIRED on a Reference in a schema
# location. Root documents typed `Reference` (SCHEMA.md, AUTONOMY.md) carry none and
# are unaffected, because they are not in one — the `index.md`/`log.md` cases below
# assert that side of it.
doc knowledge/references/no-status-ref.md '---' 'type: Reference' 'title: R3' 'provenance: machine' "timestamp: $TS" '---' 'body'
# `owner` is deliberately NOT validated: it names a person outside the bundle, so
# nothing here can resolve it. Both of these must be silent — including the second,
# whose value is not a username at all (task-owner.sh judges the shape at dispatch,
# where a refusal has somewhere to go). If a check for it is ever added, this fails.
doc projects/live/tasks/task-014-owner.md '---' 'type: Task' 'title: Owned' 'status: draft' \
  'owner: some-user' "timestamp: $TS" '---' 'body'
doc projects/live/tasks/task-015-owner-odd.md '---' 'type: Task' 'title: OddOwner' 'status: draft' \
  'owner: not a username!' "timestamp: $TS" '---' 'body'

# --- open_caveats: a TERMINAL-WRITE gate, not a promotion gate ------------------
# Three states, because two of them cannot tell this field from `open_questions`. The
# third — in-progress with a caveat outstanding must PASS — is the only one that does,
# and a two-case harness would go green on an implementation that gated promotion.
doc projects/live/tasks/task-016-caveat-done.md '---' 'type: Task' 'title: CaveatDone' 'status: done' \
  'open_caveats: [ "2026-01-01T00:00:00Z · the rollout did not fix the 500s — error rate unchanged" ]' \
  "timestamp: $TS" '---' 'body'
doc projects/live/tasks/task-017-caveat-cancelled.md '---' 'type: Task' 'title: CaveatCancelled' 'status: cancelled' \
  'open_caveats: [ "2026-01-02T00:00:00Z · cancelled for a fix that has not landed" ]' \
  "timestamp: $TS" '---' 'body'
doc projects/live/tasks/task-018-caveat-empty.md '---' 'type: Task' 'title: CaveatEmpty' 'status: done' \
  'open_caveats: [ ]' "timestamp: $TS" '---' 'body'
doc projects/live/tasks/task-019-caveat-in-progress.md '---' 'type: Task' 'title: CaveatInProgress' 'status: in-progress' \
  'open_caveats: [ "2026-01-03T00:00:00Z · the rollout has not fixed what this would be cancelled for" ]' \
  "timestamp: $TS" '---' 'body'
# The count primitive this file already had (`flow_entries`) sees only QUOTED entries on
# one line, so block form and bare entries would read as empty and pass the gate in
# silence — the same false negative the block-style `depends_on` cases above record.
doc projects/live/tasks/task-020-caveat-block.md '---' 'type: Task' 'title: CaveatBlock' 'status: done' \
  'open_caveats:' '  - "2026-01-04T00:00:00Z · a block-form caveat is still a caveat"' \
  "timestamp: $TS" '---' 'body'
doc projects/live/tasks/task-021-caveat-bare.md '---' 'type: Task' 'title: CaveatBare' 'status: cancelled' \
  'open_caveats: [ 2026-01-05T00:00:00Z · an unquoted caveat is still a caveat ]' \
  "timestamp: $TS" '---' 'body'

# --- files that must be IGNORED ------------------------------------------------
# Navigation and content. None of these carries frontmatter, and validating them
# is what drowned the first version.
doc projects/live/index.md '# Live — tasks' '* nothing'
doc projects/live/log.md '# Live — log'
doc projects/live/sources/README.md '# sources'
doc projects/live/deliverables/written.md '# a deliverable, not a concept doc'
doc projects/live/HANDOVER.md '# a doc a human dropped in'
doc index.md '# bundle index'
doc log.md '# activity log'

set +e
OUT="$(bash "$VALIDATOR" 2>&1)"; RC=$?
OUT_STRICT="$(bash "$VALIDATOR" --strict 2>&1)"; RC_STRICT=$?
set -e

pass=0; fail=0
assert() { # <label> <0|1>
  if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi
}
saw() { printf '%s\n' "$OUT" | grep -q -- "$1" && echo 0 || echo 1; }
not_seen() { printf '%s\n' "$OUT" | grep -q -- "$1" && echo 1 || echo 0; }

echo "== failure classes are each reported =="
assert "an invalid enum value is an error"        "$(saw "status 'activ' is not valid")"
assert "a valid-elsewhere status is wrong per type" "$(saw "status 'active' is not valid for type Task")"
assert "a missing timestamp is an error"          "$(saw 'missing required field: timestamp')"
assert "a missing type is an error"               "$(saw 'missing required field: type')"
assert "an unknown type is an error"              "$(saw "unknown type 'Sprint'")"
assert "a dangling depends_on is an error"        "$(saw 'dangling reference: /projects/closed/tasks/task-009-gone.md')"
assert "a concept doc with no frontmatter is an error" "$(saw 'no YAML frontmatter')"

echo "== artifacts warn, they do not fail =="
assert "an unwritten declared artifact WARNS"     "$(saw 'declared artifact does not exist yet')"
# The label and the message are on separate lines, so look at the pair.
assert "the artifact finding is labelled WARN, not ERROR" \
  "$(printf '%s\n' "$OUT" | grep -B1 'not-written-yet' | grep -q 'WARN' && echo 0 || echo 1)"
assert "no ERROR mentions the unwritten artifact" \
  "$(printf '%s\n' "$OUT" | grep -B1 'not-written-yet' | grep -q 'ERROR' && echo 1 || echo 0)"

echo "== classes found by review (each was a false negative) =="
assert "a BLOCK-style dangling depends_on is an error" \
  "$(saw 'dangling reference: /projects/closed/tasks/task-block-gone.md')"
assert "a BLOCK-style resolving depends_on is silent" "$(not_seen 'task-011-block-ok.md')"
assert "unterminated frontmatter is an error"        "$(saw 'never closed by a second')"
assert "an invalid Service status is an error"       "$(saw "status 'retired' is not valid for type Service")"
assert "a valid Service status is silent"            "$(not_seen 'good-service.md')"
assert "files below knowledge/<kind>/ are ignored"   "$(not_seen 'raw-note.md')"

echo "== the fifth knowledge kind, and the field deliberately left unchecked =="
assert "an invalid Reference status is an error" \
  "$(saw "status 'open' is not valid for type Reference")"
assert "a valid Reference status is silent"          "$(not_seen 'good-ref.md')"
assert "a Reference must HAVE a status" \
  "$(saw 'type Reference requires a status')"
assert "an owner field is never validated"           "$(not_seen 'task-014-owner.md')"
assert "…not even a malformed one"                   "$(not_seen 'task-015-owner-odd.md')"

echo "== a Finding is bounded, and both bounds only WARN =="
assert "a Finding with no lesson: warns"            "$(saw "no one-line 'lesson:'")"
assert "…and it is a WARN, not an ERROR"            "$(printf '%s\n' "$OUT" | grep -q "WARN.*no-lesson.md" && echo 0 || echo 1)"
assert "a 48-line Finding warns"                    "$(saw 'Finding is 48 lines')"
assert "…naming the cap"                            "$(saw "caps it at 40")"
assert "--strict turns both into failures"          "$([[ $RC_STRICT -ne 0 ]] && echo 0 || echo 1)"

echo "== open_caveats holds a TERMINAL write, and holds nothing else =="
assert "done with a non-empty open_caveats FAILS" \
  "$(saw 'the rollout did not fix the 500s')"
assert "…as an ERROR, not a WARN" \
  "$(printf '%s\n' "$OUT" | grep -B1 'the rollout did not fix the 500s' | grep -q 'ERROR' && echo 0 || echo 1)"
assert "…and no WARN is emitted for it" \
  "$(printf '%s\n' "$OUT" | grep -B1 'the rollout did not fix the 500s' | grep -q 'WARN' && echo 1 || echo 0)"
assert "…naming the status that is held"        "$(saw "status 'done' is held by an open caveat")"
assert "cancelled with a non-empty open_caveats FAILS" \
  "$(saw "status 'cancelled' is held by an open caveat")"
assert "done with an EMPTY open_caveats passes"  "$(not_seen 'task-018-caveat-empty.md')"
assert "in-progress with a non-empty open_caveats passes" \
  "$(not_seen 'task-019-caveat-in-progress.md')"
assert "…so it is not a promotion gate: the caveat text is never quoted for it" \
  "$(not_seen 'has not fixed what this would be cancelled for')"
assert "a BLOCK-form caveat is still seen"       "$(saw 'a block-form caveat is still a caveat')"
assert "a BARE (unquoted) caveat is still seen"  "$(saw 'an unquoted caveat is still a caveat')"

echo "== valid documents are silent =="
for f in objectives/good.md projects/live/project.md projects/live/phases/1-a.md \
         projects/live/tasks/task-001-ok.md projects/live/tasks/task-013-answered.md \
         projects/live/tasks/task-018-caveat-empty.md projects/live/tasks/task-019-caveat-in-progress.md \
         knowledge/findings/good.md knowledge/findings/sources/raw-note.md; do
  assert "no complaint about $f" "$(not_seen "$f")"
done

echo "== non-concept files are never validated =="
for f in 'projects/live/index.md' 'projects/live/log.md' 'projects/live/sources/README.md' \
         'projects/live/deliverables/written.md' 'projects/live/HANDOVER.md' 'index.md' 'log.md'; do
  assert "ignored: $f" "$(printf '%s\n' "$OUT" | grep -E "(ERROR|WARN) +$f\$" | grep -q . && echo 1 || echo 0)"
done

echo "== exit codes =="
assert "errors make it exit 1"                    "$([[ $RC -eq 1 ]] && echo 0 || echo 1)"
assert "--strict also exits non-zero"             "$([[ $RC_STRICT -ne 0 ]] && echo 0 || echo 1)"

echo "== a scope selects DOCUMENTS, and every per-document check runs on it =="
# The 40-line Finding cap used to reach a full run only, so a Finding was written long and
# trimmed later. Naming the document is what makes the cap arrive while it is being written.
set +e
ONE="$(bash "$VALIDATOR" knowledge/findings/too-long.md 2>&1)"; ONE_RC=$?
ONE_STRICT_RC=0; bash "$VALIDATOR" --strict knowledge/findings/too-long.md >/dev/null 2>&1 || ONE_STRICT_RC=$?
GOOD_ONE="$(bash "$VALIDATOR" ./knowledge/findings/good.md 2>&1)"
ABS_ONE="$(bash "$VALIDATOR" "$B/knowledge/findings/too-long.md" 2>&1)"
SKIP_ONE="$(bash "$VALIDATOR" projects/live/HANDOVER.md 2>&1)"; SKIP_RC=$?
set -e
one() { printf '%s\n' "$ONE" | grep -q -- "$1" && echo 0 || echo 1; }
assert "a named Finding is checked on its own"    "$(one 'Finding is 48 lines')"
assert "…and only it"                             "$(printf '%s\n' "$ONE" | grep -q '1 documents checked' && echo 0 || echo 1)"
assert "…so another document's error is not reported" "$(printf '%s\n' "$ONE" | grep -q 'unknown type' && echo 1 || echo 0)"
assert "…and a warning alone still exits 0"       "$([[ $ONE_RC -eq 0 ]] && echo 0 || echo 1)"
assert "--strict gates the single document"       "$([[ $ONE_STRICT_RC -eq 1 ]] && echo 0 || echo 1)"
assert "an absolute path names the same document" "$(printf '%s\n' "$ABS_ONE" | grep -q 'Finding is 48 lines' && echo 0 || echo 1)"
assert "a clean named document is silent"         "$(printf '%s\n' "$GOOD_ONE" | grep -q '0 errors, 0 warnings' && echo 0 || echo 1)"
assert "a named non-concept file is SKIPped"      "$(printf '%s\n' "$SKIP_ONE" | grep -q 'SKIP   projects/live/HANDOVER.md' && echo 0 || echo 1)"
assert "…not turned into an error"                "$([[ $SKIP_RC -eq 0 ]] && echo 0 || echo 1)"

echo "== the knowledge/index.md drift check is bundle-level, so a named scope leaves it out =="
STALE='carries rows the generator would not produce'
printf '# Knowledge Base — index\n\n| hand-written | row |\n' > knowledge/index.md
set +e
IDX_NAMED="$(bash "$VALIDATOR" knowledge/findings/good.md 2>&1)"
IDX_FULL="$(bash "$VALIDATOR" 2>&1)"
IDX_SELF="$(bash "$VALIDATOR" knowledge/index.md 2>&1)"
IDX_ABS="$(bash "$VALIDATOR" "$B/knowledge/index.md" 2>&1)"
set -e
rm knowledge/index.md
seen() { grep -q -- "$2" <<<"$1" && echo 0 || echo 1; }
assert "a named document on a stale index: no index warning" "$(seen "$IDX_NAMED" '0 errors, 0 warnings')"
assert "a no-argument run on the same stale index still warns" "$(seen "$IDX_FULL" "$STALE")"
assert "naming the index itself still checks it"  "$(seen "$IDX_SELF" "$STALE")"
assert "…by absolute path too"                    "$(seen "$IDX_ABS" "$STALE")"
assert "…without also SKIPping it"                "$(printf '%s\n' "$IDX_SELF" | grep -q 'SKIP' && echo 1 || echo 0)"

echo "== --changed reads git, and refuses when it cannot =="
# The ceiling keeps the answer the fixture's, not that of whatever TMPDIR sits under.
set +e; GIT_CEILING_DIRECTORIES="$TMP" bash "$VALIDATOR" --changed >/dev/null 2>&1; NOGIT_RC=$?; set -e
assert "--changed outside a work tree exits 2"    "$([[ $NOGIT_RC -eq 2 ]] && echo 0 || echo 1)"
G="$TMP/changed"; mkdir -p "$G/knowledge/findings"; cd "$G"
echo '{ "org": "x", "reposRoot": "/tmp" }' > instance.config.json; echo '# Schema' > SCHEMA.md
doc knowledge/findings/committed.md '---' 'type: Finding' 'title: C' 'lesson: l' 'status: current' 'provenance: machine' "timestamp: $TS" '---' 'body'
git init -q . && git add -A \
  && git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm init
{ printf -- '---\ntype: Finding\ntitle: N\nlesson: l\nstatus: current\nprovenance: machine\ntimestamp: %s\n---\n' "$TS"
  for i in $(seq 1 50); do echo "line $i"; done; } > knowledge/findings/just-written.md
set +e; CH="$(bash "$VALIDATOR" --changed 2>&1)"; set -e
assert "an untracked over-long Finding is caught" "$(printf '%s\n' "$CH" | grep -q 'just-written.md' && echo 0 || echo 1)"
assert "…and the committed clean one is not rechecked" "$(printf '%s\n' "$CH" | grep -q '1 documents checked' && echo 0 || echo 1)"
cd "$B"

echo "== a clean bundle passes, and --strict still passes with no warnings =="
# task-018/019 stay: they are the two caveat cases that must be CLEAN, not merely unchecked.
rm -f projects/live/tasks/task-00[2-9]*.md projects/live/tasks/task-01[02]*.md \
      projects/live/tasks/task-016*.md projects/live/tasks/task-017*.md \
      projects/live/tasks/task-02[01]*.md \
      knowledge/services/bad-service.md \
      knowledge/findings/no-lesson.md knowledge/findings/too-long.md \
      knowledge/references/bad-ref.md knowledge/references/no-status-ref.md
set +e
CLEAN="$(bash "$VALIDATOR" 2>&1)"; CRC=$?
CLEAN_STRICT_RC=0; bash "$VALIDATOR" --strict >/dev/null 2>&1 || CLEAN_STRICT_RC=$?
set -e
assert "a clean bundle exits 0"                   "$([[ $CRC -eq 0 ]] && echo 0 || echo 1)"
assert "a clean bundle reports 0 errors"          "$(printf '%s\n' "$CLEAN" | grep -q '0 errors, 0 warnings' && echo 0 || echo 1)"
assert "--strict passes when there are no warnings" "$([[ $CLEAN_STRICT_RC -eq 0 ]] && echo 0 || echo 1)"

echo "== objectives/ is optional: no directory, and a project anchored on its own criteria =="
# SCHEMA.md makes `objectives/` an opt-in layer and `objective:` optional, so a bundle with
# neither must be VALID — not merely unchecked. A second fixture, because the one above is
# built around an objective and cannot answer this.
NOOBJ="$TMP/no-objectives"
mkdir -p "$NOOBJ/projects/solo/tasks" "$NOOBJ/knowledge/findings"
cd "$NOOBJ"
echo '{ "org": "x", "reposRoot": "/tmp" }' > instance.config.json
echo '# Schema' > SCHEMA.md
doc projects/solo/project.md '---' 'type: Project' 'title: Solo' 'kind: build' \
  'success_criteria: [ "harness suite 277/0 (today: 277/0)", "seed CLAUDE.md under 22136 bytes" ]' \
  'status: active' "timestamp: $TS" '---' 'body'
doc projects/solo/tasks/task-001-solo.md '---' 'type: Task' 'title: Solo' 'status: ready' \
  'project: /projects/solo/project.md' "timestamp: $TS" '---' 'body'
set +e
NOOBJ_OUT="$(bash "$VALIDATOR" 2>&1)"; NOOBJ_RC=$?
NOOBJ_STRICT_RC=0; bash "$VALIDATOR" --strict >/dev/null 2>&1 || NOOBJ_STRICT_RC=$?
set -e
assert "a bundle with no objectives/ exits 0"    "$([[ $NOOBJ_RC -eq 0 ]] && echo 0 || echo 1)"
assert "…with 0 errors and 0 warnings"           "$(printf '%s\n' "$NOOBJ_OUT" | grep -q '0 errors, 0 warnings' && echo 0 || echo 1)"
assert "…and --strict passes too"                "$([[ $NOOBJ_STRICT_RC -eq 0 ]] && echo 0 || echo 1)"
assert "a project with success_criteria and no objective: is silent" \
  "$(printf '%s\n' "$NOOBJ_OUT" | grep -q 'projects/solo/project.md' && echo 1 || echo 0)"
assert "…and its documents were actually checked, not skipped" \
  "$(printf '%s\n' "$NOOBJ_OUT" | grep -q '2 documents checked' && echo 0 || echo 1)"

echo "== malformed frontmatter is an error, per measured fault class =="
# Each of these four made a real document unreadable to every YAML consumer while
# passing every field check in this script. The validator is bash + awk, so these are
# the classes that have been SEEN, checked structurally — not a YAML parse.
mkdir -p "$TMP/fm/projects/p/tasks" && cd "$TMP/fm"
echo '{ "org": "x", "reposRoot": "/tmp" }' > instance.config.json
mkdir -p .ai-bridge && touch .ai-bridge/SCHEMA.md SCHEMA.md

fmdoc() { # <file> <lines...>
  local f="$1"; shift; mkdir -p "$(dirname "$f")"; printf '%s\n' "$@" > "$f"
}
fmdoc projects/p/tasks/task-001-two-entries.md '---' 'type: Task' 'title: T' 'status: draft' \
  "timestamp: $TS" 'advisor_notes:' '  - "first entry."  - "second opened on the same line"' '---' 'body'
fmdoc projects/p/tasks/task-002-inner-quotes.md '---' 'type: Task' 'title: T' 'status: draft' \
  "timestamp: $TS" 'acceptance_criteria:' '  - "include already lists ["src/**/*", "test/**/*"] so it is covered"' '---' 'body'
fmdoc projects/p/tasks/task-003-colon-space.md '---' 'type: Task' 'title: T' 'status: draft' \
  "timestamp: $TS" 'description: Unblock the deploy: port the guard first' '---' 'body'
fmdoc projects/p/tasks/task-004-reserved.md '---' 'type: Task' 'title: T' 'status: draft' \
  "timestamp: $TS" 'description: `gh pr view --json reviewThreads` errors' '---' 'body'
# the control: every shape above, written legally
fmdoc projects/p/tasks/task-005-legal.md '---' 'type: Task' 'title: T' 'status: draft' \
  "timestamp: $TS" 'description: "Fine: this value is quoted"' 'acceptance_criteria:' \
  '  - "he said \"hello\" and that is escaped"' '  - "a url http://example.com/a:b is not a mapping"' \
  '  - "trailing text after a backtick `cmd` is fine"' '---' 'body'
# A block scalar is opaque text: prose inside it may carry the shapes above and is not
# a fault. Skipping it is what the entry rule is anchored for.
fmdoc projects/p/tasks/task-006-block-scalar.md '---' 'type: Task' 'title: T' 'status: draft' \
  "timestamp: $TS" 'description: |' '  a quoted list in prose: "one"  - "two" stays prose' \
  '  - a dash-led line is block content, not an entry' '  and a colon: space pair is legal here' '---' 'body'
# A single-quoted entry needs no escaping for a double quote, so "one"  - "two" inside
# one is prose. The rule is anchored to a structural entry for exactly this.
fmdoc projects/p/tasks/task-007-single-quoted.md '---' 'type: Task' 'title: T' 'status: draft' \
  "timestamp: $TS" 'acceptance_criteria:' "  - 'he said \"one\"  - \"two\" in one breath'" '---' 'body'
# …and the anchoring must still see past an ESCAPED quote to the real delimiter.
fmdoc projects/p/tasks/task-008-escaped-then-split.md '---' 'type: Task' 'title: T' 'status: draft' \
  "timestamp: $TS" 'acceptance_criteria:' '  - "he said \"go\""  - "and left"' '---' 'body'
# A trailing inline comment is not part of the scalar, so the quotes inside it are not
# inner ones. Rule 3 strips one already; rule 2 flagged this and skipped the document,
# which is why the timestamp below is missing: the field checks must still reach it.
fmdoc projects/p/tasks/task-009-inline-comment.md '---' 'type: Task' 'title: T' 'status: draft' \
  'acceptance_criteria:' '  - "ship it" # reviewer said "go"' '---' 'body'
set +e; FM_OUT="$(bash "$VALIDATOR" 2>&1)"; set -e
fm_saw() { printf '%s\n' "$FM_OUT" | grep -q -- "$1" && echo 0 || echo 1; }
# The path and the message land on TWO lines, so a document counts as flagged only
# when the message follows its own ERROR line. Grepping both on one line finds nothing.
fm_flagged() { printf '%s\n' "$FM_OUT" | grep -A1 -- "$1" | grep -q 'malformed' && echo 0 || echo 1; }
fm_clean() { [ "$(fm_flagged "$1")" = 1 ] && echo 0 || echo 1; }

assert "a list entry opened on another entry's line is an error" "$(fm_saw "opened on another entry")"
assert "unescaped inner quotes in a quoted entry are an error"   "$(fm_saw "unescaped double quotes")"
assert "an unquoted value with a colon-space pair is an error"   "$(fm_saw "contains a colon-space pair")"
assert "an unquoted value opening on a reserved indicator is an error" "$(fm_saw "YAML reserves at the start")"
assert "the message names the offending line"                    "$(fm_saw "line 6:")"
assert "the legal control document is NOT flagged"                "$(fm_clean task-005-legal)"
assert "a block scalar's prose is NOT read as syntax"             "$(fm_clean task-006-block-scalar)"
assert "a single-quoted entry's inner quotes are NOT a delimiter" "$(fm_clean task-007-single-quoted)"
assert "…and an escaped quote does not hide a real split entry"   "$(fm_flagged task-008-escaped-then-split)"
# A malformed document stops at the structure fault, the way an unterminated block does:
# the field checks below it read lines, and lines lie about a broken block.
assert "a malformed document is not also field-checked" \
  "$(printf '%s\n' "$FM_OUT" | grep -q 'task-001-two-entries.md.*missing required' && echo 1 || echo 0)"
assert "an entry whose inline comment carries quotes is NOT flagged" "$(fm_clean task-009-inline-comment)"
assert "…and that document is still field-checked" \
  "$(printf '%s\n' "$FM_OUT" | grep -A1 'task-009-inline-comment.md' | grep -q 'missing required field: timestamp' && echo 0 || echo 1)"

cd "$B"

echo "== provenance: required on all five knowledge types, from a closed set =="
P="$TMP/prov"; mkdir -p "$P"; cd "$P"
echo '{ "org": "x", "reposRoot": "/tmp" }' > instance.config.json; echo '# Schema' > SCHEMA.md
for v in machine mixed human; do
  doc "knowledge/findings/ok-$v.md" '---' 'type: Finding' 'title: F' 'lesson: l' 'status: current' "provenance: $v" "timestamp: $TS" '---' 'body'
done
doc knowledge/teams/none.md '---' 'type: Team' 'title: T' "timestamp: $TS" '---' 'body'
doc knowledge/runbooks/none.md '---' 'type: Runbook' 'title: R' "timestamp: $TS" '---' 'body'
doc knowledge/services/none.md '---' 'type: Service' 'title: S' 'status: active' "timestamp: $TS" '---' 'body'
doc knowledge/references/none.md '---' 'type: Reference' 'title: R' 'status: current' "timestamp: $TS" '---' 'body'
doc knowledge/findings/none.md '---' 'type: Finding' 'title: F' 'lesson: l' 'status: current' "timestamp: $TS" '---' 'body'
doc knowledge/runbooks/bot.md '---' 'type: Runbook' 'title: R' 'provenance: bot' "timestamp: $TS" '---' 'body'
# Only the frontmatter counts: a body line of the same shape is prose.
doc knowledge/teams/body-only.md '---' 'type: Team' 'title: T' "timestamp: $TS" '---' 'provenance: machine'
{ printf '%s\n' '---' 'type: Finding' 'title: Forty' 'lesson: l' 'status: current' 'provenance: machine' "timestamp: $TS" '---'
  for i in $(seq 32); do echo "line $i"; done; } > knowledge/findings/forty.md
set +e; POUT="$(bash "$VALIDATOR" 2>&1)"; set -e
pmiss() { printf '%s\n' "$POUT" | grep -A1 "ERROR  knowledge/$1" | grep -q "requires provenance" && echo 0 || echo 1; }
for k in teams/none runbooks/none services/none references/none findings/none; do
  assert "a missing provenance is an ERROR on $k" "$(pmiss "$k.md")"
done
assert "…and the message names the repair" "$(printf '%s\n' "$POUT" | grep -q 'migrate-bundle.sh --apply fills it from git' && echo 0 || echo 1)"
assert "a value outside the set is an ERROR" "$(printf '%s\n' "$POUT" | grep -q "provenance 'bot' is not one of: machine mixed human" && echo 0 || echo 1)"
assert "a body line is not the field" "$(pmiss teams/body-only.md)"
assert "machine, mixed and human are all silent" "$(printf '%s\n' "$POUT" | grep -q 'ok-' && echo 1 || echo 0)"
assert "the provenance line is not counted against the 40-line cap" "$(printf '%s\n' "$POUT" | grep -q 'forty.md' && echo 1 || echo 0)"
assert "exactly the seven faulty documents error" "$(printf '%s\n' "$POUT" | grep -q ', 7 errors,' && echo 0 || echo 1)"
cd "$B"

echo "== refusing to run outside an instance root =="
mkdir -p "$TMP/notabundle" && cd "$TMP/notabundle"
set +e; bash "$VALIDATOR" >/dev/null 2>&1; OUTSIDE=$?; set -e
assert "exits 2 without SCHEMA.md + instance.config.json" "$([[ $OUTSIDE -eq 2 ]] && echo 0 || echo 1)"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
